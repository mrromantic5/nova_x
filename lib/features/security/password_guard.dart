// lib/features/security/password_guard.dart
//
// Password Guard — a protected password can't be sent to a site it doesn't
// belong to, even a phishing page registered an hour ago that no threat
// list knows yet (the way 2FA-bypassing phishing kits work).
//
//  • Every password saved in NOVA X's password manager is protected
//    automatically for its own site; more can be added by hand (e.g. your
//    Google password for google.com and youtube.com).
//  • Only a slow salted hash (PBKDF2-HMAC-SHA256) is kept — never the
//    password — plus a 16-bit tag so most typing needs no hashing at all.
//  • In every page, before a password can leave (form submit, fetch, XHR,
//    sendBeacon, WebSocket), the page script asks NOVA X. If it's a
//    protected password on the wrong site: the send is cancelled, the fields
//    are cleared, NOVA Shield refuses every further upload (any request that
//    isn't a plain GET) from that tab, and NOVA X explains what happened.
//  • Nothing is sent anywhere: the check happens on this phone.
// Android (3.13.0): same crypto and page script as NOVA X for PC. The hashes
// are kept in encrypted storage (flutter_secure_storage), never the password.
// Hashing runs in an isolate through static helpers whose closures capture
// only plain data (on PC a closure that captured the tab crashed silently).

import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart' as fss;
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/services/password_service.dart';
import '../cyber/ui/cyber_palette.dart';
import '../pro/pro_ui.dart';
import '../shield/engine/shield_engine.dart';

class GuardEntry {
  GuardEntry({
    required this.id,
    required this.label,
    required this.hosts,
    required this.salt,
    required this.hash,
    required this.tag,
    required this.source,
    this.srcKey = '',
  });

  final String id;
  String label;
  final List<String> hosts;
  final String salt; // base64
  final String hash; // base64
  final int tag;
  final String source; // 'manager' | 'manual'
  final String srcKey;

  Map<String, Object?> toJson() =>
      {'id': id, 'label': label, 'hosts': hosts, 'salt': salt, 'hash': hash, 'tag': tag, 'source': source, 'srcKey': srcKey};

  static GuardEntry? fromJson(Object? j) {
    if (j is! Map || j['hash'] is! String || j['salt'] is! String) return null;
    return GuardEntry(
      id: '${j['id'] ?? ''}',
      label: '${j['label'] ?? ''}',
      hosts: [for (final h in (j['hosts'] as List? ?? const [])) '$h'],
      salt: j['salt'] as String,
      hash: j['hash'] as String,
      tag: (j['tag'] as num?)?.toInt() ?? -1,
      source: '${j['source'] ?? 'manual'}',
      srcKey: '${j['srcKey'] ?? ''}',
    );
  }
}

class GuardAlert {
  GuardAlert({required this.host, required this.labels, required this.belongsTo, required this.at});
  final String host;
  final List<String> labels;
  final List<String> belongsTo;
  final DateTime at;
}

class PasswordGuard extends ChangeNotifier {
  PasswordGuard._();
  static final PasswordGuard instance = PasswordGuard._();

  static const String _kStore = 'nova_password_guard_v1';
  static const String _kOn = 'nova_password_guard_on';
  static const String handlerName = 'novaxPwGuard';
  static const int iterations = 60000;

  static const _secure = fss.FlutterSecureStorage(aOptions: fss.AndroidOptions(encryptedSharedPreferences: true));
  SharedPreferences? _prefs;
  bool _loaded = false;
  Future<void>? _loading;
  bool enabled = true;
  late Uint8List _appKey;
  final List<GuardEntry> entries = [];
  final List<GuardAlert> alerts = [];
  bool _syncing = false;

  // ── Crypto (pure; tested) ─────────────────────────────────────────────────

  /// PBKDF2-HMAC-SHA256 (RFC 8018).
  static Uint8List pbkdf2(List<int> password, List<int> salt, int rounds, {int length = 32}) {
    final hmac = Hmac(sha256, password);
    final out = BytesBuilder();
    var block = 1;
    while (out.length < length) {
      final s = Uint8List(salt.length + 4)
        ..setRange(0, salt.length, salt)
        ..[salt.length] = (block >> 24) & 0xff
        ..[salt.length + 1] = (block >> 16) & 0xff
        ..[salt.length + 2] = (block >> 8) & 0xff
        ..[salt.length + 3] = block & 0xff;
      var u = hmac.convert(s).bytes;
      final t = Uint8List.fromList(u);
      for (var i = 1; i < rounds; i++) {
        u = hmac.convert(u).bytes;
        for (var j = 0; j < t.length; j++) {
          t[j] ^= u[j];
        }
      }
      out.add(t);
      block++;
    }
    return Uint8List.fromList(out.toBytes().sublist(0, length));
  }

  static int tagOf(List<int> appKey, String password) {
    final d = Hmac(sha256, appKey).convert(utf8.encode(password)).bytes;
    return (d[0] << 8) | d[1];
  }

  static bool _sameBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var r = 0;
    for (var i = 0; i < a.length; i++) {
      r |= a[i] ^ b[i];
    }
    return r == 0;
  }

  /// "accounts.google.com" belongs to an entry for "google.com".
  static bool hostAllowed(String host, Iterable<String> hosts) {
    final h = host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
    return hosts.any((x) {
      final s = x.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
      return s.isNotEmpty && (h == s || h.endsWith('.$s'));
    });
  }

  static GuardEntry makeEntry(Uint8List appKey,
      {required String id, required String label, required List<String> hosts, required String password, required String source, String srcKey = ''}) {
    final r = Random.secure();
    final salt = Uint8List.fromList(List.generate(16, (_) => r.nextInt(256)));
    final hash = pbkdf2(utf8.encode(password), salt, iterations);
    return GuardEntry(
      id: id,
      label: label,
      hosts: hosts,
      salt: base64.encode(salt),
      hash: base64.encode(hash),
      tag: tagOf(appKey, password),
      source: source,
      srcKey: srcKey,
    );
  }

  /// Entries whose password equals [password] (tag first, then PBKDF2).
  static List<GuardEntry> matching(Uint8List appKey, List<GuardEntry> entries, String password) {
    if (password.isEmpty) return const [];
    final tag = tagOf(appKey, password);
    final out = <GuardEntry>[];
    final pw = utf8.encode(password);
    for (final e in entries) {
      if (e.tag != tag) continue;
      final h = pbkdf2(pw, base64.decode(e.salt), iterations);
      if (_sameBytes(h, base64.decode(e.hash))) out.add(e);
    }
    return out;
  }

  /// 'alert' when [password] is protected and [host] is none of its sites.
  static (bool, List<GuardEntry>) verdict(Uint8List appKey, List<GuardEntry> entries, String host, String password) {
    final m = matching(appKey, entries, password);
    if (m.isEmpty) return (false, const []);
    if (m.any((e) => hostAllowed(host, e.hosts))) return (false, m);
    return (true, m);
  }

  // ── Background hashing ────────────────────────────────────────────────────
  // Static, so each isolate closure captures only its own arguments. (A
  // closure inside an instance method can drag the tab, a BuildContext or
  // this object into the isolate message, which Dart refuses to send.)

  static Future<Map<String, Object?>> _entryJson(Uint8List key, String id, String label, List<String> hosts,
          String password, String source) =>
      Isolate.run(() => makeEntry(key, id: id, label: label, hosts: hosts, password: password, source: source).toJson());

  static Future<List<Map<String, Object?>>> _managerEntriesJson(
          Uint8List key, List<(String id, String label, String host, String password, String srcKey)> specs) =>
      Isolate.run(() => [
            for (final s in specs)
              makeEntry(key, id: s.$1, label: s.$2, hosts: [s.$3], password: s.$4, source: 'manager', srcKey: s.$5).toJson(),
          ]);

  static Future<(bool, List<String>)> _verdictIds(Uint8List key, List<GuardEntry> list, String host, String password) =>
      Isolate.run(() {
        final (a, m) = verdict(key, list, host, password);
        return (a, [for (final e in m) e.id]);
      });

  // ── Store ─────────────────────────────────────────────────────────────────

  Future<void> ensureLoaded() => _loaded ? Future.value() : (_loading ??= _load());

  Future<void> _load() async {
    _prefs = await SharedPreferences.getInstance();
    enabled = _prefs!.getBool(_kOn) ?? true;
    var key = <int>[];
    try {
      final raw = await _secure.read(key: _kStore);
      if (raw != null) {
        final j = jsonDecode(raw);
        if (j is Map) {
          key = base64.decode('${j['key'] ?? ''}');
          for (final e in (j['entries'] as List? ?? const [])) {
            final g = GuardEntry.fromJson(e);
            if (g != null) entries.add(g);
          }
        }
      }
    } catch (_) {}
    if (key.length != 32) {
      final r = Random.secure();
      key = List.generate(32, (_) => r.nextInt(256));
      entries.clear();
    }
    _appKey = Uint8List.fromList(key);
    _loaded = true;
    await _save();
    unawaited(syncWithPasswordManager());
  }

  Future<void> _save() async {
    await _secure.write(key: _kStore, value: jsonEncode({
      'key': base64.encode(_appKey),
      'entries': [for (final e in entries) if (e.source != 'selftest') e.toJson()],
    }));
  }

  /// Self-test: a temporary password that belongs to [host] (never saved).
  Future<void> addSelfTestEntry(String password, String host) async {
    await ensureLoaded();
    final key = _appKey;
    final json = await _entryJson(key, 'selftest', 'Self-test', [host], password, 'selftest');
    final g = GuardEntry.fromJson(json);
    entries.removeWhere((e) => e.source == 'selftest');
    if (g != null) entries.add(g);
  }

  void removeSelfTestEntry() => entries.removeWhere((e) => e.source == 'selftest');

  Future<void> setEnabled(bool v) async {
    await ensureLoaded();
    enabled = v;
    await _prefs?.setBool(_kOn, v);
    notifyListeners();
  }

  int get managerCount => entries.where((e) => e.source == 'manager').length;
  int get protectedCount => entries.where((e) => e.source != 'selftest').length;
  int get manualCount => entries.where((e) => e.source == 'manual').length;

  /// Protects every password saved in NOVA X's password manager for its own
  /// site (new or changed ones are hashed in the background).
  Future<void> syncWithPasswordManager() async {
    if (_syncing) return;
    _syncing = true;
    try {
      await ensureLoaded();
      final creds = await PasswordService.getAllCredentials();
      final key = _appKey;
      final wanted = <String, Map<String, String>>{};
      for (final c in creds) {
        final pw = c['password'] ?? '';
        final domain = (c['domain'] ?? '').replaceAll('_', '');
        if (pw.length < 4 || domain.isEmpty) continue;
        final sk = base64.encode(Hmac(sha256, key).convert(utf8.encode('${c['domain']}\u0000${c['username']}\u0000$pw')).bytes);
        wanted[sk] = {'domain': domain, 'user': c['username'] ?? '', 'pw': pw};
      }
      final before = entries.length;
      entries.removeWhere((e) => e.source == 'manager' && !wanted.containsKey(e.srcKey));
      final have = entries.map((e) => e.srcKey).toSet();
      final todo = wanted.entries.where((e) => !have.contains(e.key)).toList();
      if (todo.isNotEmpty) {
        final made = await _managerEntriesJson(key, [
          for (final t in todo)
            (
              'm${t.key.hashCode.toUnsigned(32)}',
              '${t.value['user']!.isEmpty ? '' : '${t.value['user']} · '}${t.value['domain']}',
              t.value['domain']!,
              t.value['pw']!,
              t.key,
            ),
        ]);
        for (final m in made) {
          final g = GuardEntry.fromJson(m);
          if (g != null) entries.add(g);
        }
      }
      if (todo.isNotEmpty || entries.length != before) {
        await _save();
        notifyListeners();
      }
    } catch (_) {
    } finally {
      _syncing = false;
    }
  }

  /// Protect a password by hand for one or more sites.
  Future<void> addManual(String label, List<String> hosts, String password) async {
    await ensureLoaded();
    final key = _appKey;
    final id = 'u${DateTime.now().microsecondsSinceEpoch}';
    final json = await _entryJson(key, id, label, List<String>.of(hosts), password, 'manual');
    final g = GuardEntry.fromJson(json);
    if (g != null) entries.add(g);
    await _save();
    notifyListeners();
  }

  Future<void> remove(GuardEntry e) async {
    entries.remove(e);
    await _save();
    notifyListeners();
  }

  Future<void> allowHost(List<GuardEntry> matched, String host) async {
    final h = host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
    for (final e in matched) {
      if (!e.hosts.contains(h)) e.hosts.add(h);
    }
    await _save();
    notifyListeners();
  }

  /// The page in tab [tabKey] asks whether [password] may be sent from
  /// [host]. [leave] takes the user away from the page (back, or close).
  Future<String> check(BuildContext? context, int tabKey, String host, String password, {Future<void> Function()? leave}) async {
    await ensureLoaded();
    final selfTest = entries.any((e) => e.source == 'selftest');
    if ((!enabled && !selfTest) || password.length < 4 || entries.isEmpty) return 'ok';
    final key = _appKey;
    final list = List<GuardEntry>.of(entries);
    final tag = tagOf(key, password);
    if (!list.any((e) => e.tag == tag)) return 'ok'; // common case: no hashing at all
    final (alert, matched) = await _verdictIds(key, list, host, password);
    if (!alert) return 'ok';
    final hit = entries.where((e) => matched.contains(e.id)).toList();
    // Stop every further upload from this tab (NOVA Shield refuses any
    // request that isn't a plain GET until the user decides).
    NovaShieldEngine.instance.lockPosts(tabKey, true);
    if (hit.every((e) => e.source == 'selftest')) return 'alert';
    alerts.insert(0, GuardAlert(
      host: host,
      labels: [for (final e in hit) e.label],
      belongsTo: {for (final e in hit) ...e.hosts}.toList(),
      at: DateTime.now(),
    ));
    if (alerts.length > 30) alerts.removeLast();
    notifyListeners();
    if (context != null && context.mounted) {
      unawaited(showProDialog<void>(context, (ctx) => _AlertDialog(tabKey: tabKey, host: host, matched: hit, leave: leave)));
    }
    return 'alert';
  }

  /// The page script (document start, all frames). Null when off.
  String? script() => enabled ? scriptSource : null;

  static const String scriptSource = r'''
(function(){
  'use strict';
  if (window.__novaPwGuard) return;
  try { Object.defineProperty(window, '__novaPwGuard', { value: 1 }); } catch (e) { return; }
  var verdicts = new Map(), alerted = [], locked = false, bypass = false;

  function ask(v) {
    return new Promise(function (resolve) {
      var done = false, timer = setTimeout(function () { if (!done) { done = true; resolve('ok'); } }, 15000);
      function finish(r) { if (!done) { done = true; clearTimeout(timer); resolve(r === 'alert' ? 'alert' : 'ok'); } }
      try {
        var b = window.flutter_inappwebview;
        if (!b || !b.callHandler) { finish('ok'); return; }
        b.callHandler('novaxPwGuard', { v: v, host: location.hostname }).then(finish, function () { finish('ok'); });
      } catch (e) { finish('ok'); }
    });
  }
  function check(v) {
    if (!v || v.length < 4) return Promise.resolve('ok');
    var known = verdicts.get(v);
    if (known === 'ok' || known === 'alert') return Promise.resolve(known);
    if (known) return known;
    var p = ask(v);
    verdicts.set(v, p);
    p.then(function (r) { verdicts.set(v, r); if (r === 'alert') lock(v); });
    if (verdicts.size > 40) verdicts.delete(verdicts.keys().next().value);
    return p;
  }
  function fields(root) {
    var out = [];
    try {
      (root || document).querySelectorAll('input').forEach(function (i) {
        if (i.type === 'password' || /current-password|new-password/.test(i.autocomplete || '')) out.push(i);
      });
    } catch (e) {}
    return out;
  }
  function lock(v) {
    locked = true;
    if (v && alerted.indexOf(v) < 0) alerted.push(v);
    fields().forEach(function (f) { if (!v || f.value === v) { f.value = ''; try { f.dispatchEvent(new Event('input', { bubbles: true })); } catch (e) {} } });
  }
  function secretsIn(text) {
    text = String(text || '');
    if (!text) return [];
    var vals = fields().map(function (f) { return f.value; }).filter(function (v) { return v && v.length >= 4; }).concat(alerted);
    var hits = [];
    vals.forEach(function (v) {
      if (hits.indexOf(v) >= 0) return;
      var enc = ''; try { enc = encodeURIComponent(v); } catch (e) {}
      if (text.indexOf(v) >= 0 || (enc && text.indexOf(enc) >= 0) || text.indexOf(JSON.stringify(v).slice(1, -1)) >= 0) hits.push(v);
    });
    return hits;
  }
  function allowedSync(hits) { return hits.every(function (v) { return verdicts.get(v) === 'ok'; }); }
  function gate(text) {
    var hits = secretsIn(text);
    if (!hits.length) return Promise.resolve(true);
    if (hits.some(function (v) { return alerted.indexOf(v) >= 0; })) return Promise.resolve(false);
    return Promise.all(hits.map(check)).then(function (rs) { return rs.indexOf('alert') < 0; });
  }
  function bodyText(body) {
    if (body == null) return '';
    if (typeof body === 'string') return body;
    try {
      if (body instanceof URLSearchParams) return body.toString();
      if (body instanceof FormData) { var o = []; body.forEach(function (v, k) { o.push(k + '=' + (typeof v === 'string' ? v : '')); }); return o.join('&'); }
      if (body instanceof Blob || body instanceof ArrayBuffer || ArrayBuffer.isView(body)) return '';
    } catch (e) {}
    try { return JSON.stringify(body); } catch (e) { return String(body); }
  }
  function formText(form) { try { return bodyText(new FormData(form)) + ' ' + (form.action || ''); } catch (e) { return ''; } }

  // Pre-check while typing, so the answer is ready on submit.
  var timer = null;
  addEventListener('input', function (e) {
    var t = e.target;
    if (!t || t.tagName !== 'INPUT' || !(t.type === 'password' || /current-password|new-password/.test(t.autocomplete || ''))) return;
    clearTimeout(timer);
    timer = setTimeout(function () { if (t.value && t.value.length >= 4) check(t.value); }, 250);
  }, true);

  // Form submissions (user Enter / click, requestSubmit).
  addEventListener('submit', function (e) {
    if (bypass) return;
    var form = e.target; if (!form || form.tagName !== 'FORM') return;
    var text = formText(form), hits = secretsIn(text);
    if (!hits.length || allowedSync(hits)) return;
    e.preventDefault(); e.stopImmediatePropagation();
    var submitter = e.submitter;
    gate(text).then(function (ok) {
      if (!ok) return;
      bypass = true;
      try { if (form.requestSubmit) form.requestSubmit(submitter && submitter.form === form ? submitter : undefined); else HTMLFormElement.prototype.submit.call(form); }
      finally { bypass = false; }
    });
  }, true);

  // Programmatic form.submit() (no submit event).
  try {
    var formSubmit = HTMLFormElement.prototype.submit;
    Object.defineProperty(HTMLFormElement.prototype, 'submit', { configurable: true, writable: true, value: function submit() {
      var form = this, text = formText(form), hits = secretsIn(text);
      if (bypass || !hits.length || allowedSync(hits)) return formSubmit.call(form);
      gate(text).then(function (ok) { if (ok) formSubmit.call(form); });
    } });
  } catch (e) {}

  // fetch
  try {
    var origFetch = window.fetch;
    var fetchWrap = function fetch(input, init) {
      var self = this, args = arguments;
      var url = typeof input === 'string' ? input : (input && input.url) || '';
      var pre = url + ' ' + bodyText(init && init.body);
      var go = function (text) {
        return gate(text).then(function (ok) {
          if (!ok) throw new TypeError('NOVA X Password Guard blocked sending a protected password to ' + location.hostname);
          return origFetch.apply(self, args);
        });
      };
      if (typeof Request !== 'undefined' && input instanceof Request && !(init && init.body)) {
        var hasFields = fields().some(function (f) { return f.value; }) || alerted.length;
        if (hasFields) return input.clone().text().then(function (t) { return go(pre + ' ' + t); }, function () { return go(pre); });
      }
      var hits = secretsIn(pre);
      if (!hits.length || allowedSync(hits)) return origFetch.apply(self, args);
      return go(pre);
    };
    window.fetch = fetchWrap;
  } catch (e) {}

  // XMLHttpRequest
  try {
    var xo = XMLHttpRequest.prototype.open, xs = XMLHttpRequest.prototype.send;
    XMLHttpRequest.prototype.open = function open(m, u) { this.__novaUrl = String(u || ''); this.__novaAsync = arguments.length < 3 || arguments[2] !== false; return xo.apply(this, arguments); };
    XMLHttpRequest.prototype.send = function send(body) {
      var self = this, args = arguments, text = (self.__novaUrl || '') + ' ' + bodyText(body), hits = secretsIn(text);
      if (!hits.length || allowedSync(hits)) return xs.apply(self, args);
      if (self.__novaAsync === false) { check(hits[0]); throw new DOMException('Blocked by NOVA X Password Guard', 'NetworkError'); }
      gate(text).then(function (ok) {
        if (ok) { xs.apply(self, args); return; }
        try { self.abort(); } catch (e) {}
        try { self.dispatchEvent(new ProgressEvent('error')); } catch (e) {}
      });
    };
  } catch (e) {}

  // sendBeacon (synchronous answer: refuse until the password is known safe)
  try {
    if (navigator.sendBeacon) {
      var sb = navigator.sendBeacon.bind(navigator);
      navigator.sendBeacon = function sendBeacon(url, data) {
        var hits = secretsIn(String(url) + ' ' + bodyText(data));
        if (hits.length && !allowedSync(hits)) { hits.forEach(check); return false; }
        return sb(url, data);
      };
    }
  } catch (e) {}

  // WebSocket
  try {
    var wsSend = WebSocket.prototype.send;
    WebSocket.prototype.send = function send(data) {
      var self = this, hits = secretsIn(bodyText(data));
      if (!hits.length || allowedSync(hits)) return wsSend.call(self, data);
      gate(bodyText(data)).then(function (ok) { if (ok) wsSend.call(self, data); });
    };
  } catch (e) {}
})();''';
}

class _AlertDialog extends StatelessWidget {
  const _AlertDialog({required this.tabKey, required this.host, required this.matched, this.leave});
  final int tabKey;
  final String host;
  final List<GuardEntry> matched;
  final Future<void> Function()? leave;

  @override
  Widget build(BuildContext context) {
    final p = NovaThemeScope.of(context);
    final belongs = {for (final e in matched) ...e.hosts}.toList();
    return ProDialog(
      icon: Icons.password_rounded,
      title: 'Password Guard stopped your password',
      subtitle: host,
      guide: 'password_guard',
      width: 620,
      height: 560,
      actions: [
        TextButton(
          onPressed: () async {
            final ok = await showProDialog<bool>(context, (ctx) => AlertDialog(
                  title: const Text('Is this really your site?'),
                  content: Text('Only continue if you are sure $host belongs to the same company as ${belongs.join(', ')}. '
                      'Phishing pages copy the real site perfectly.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                    FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Yes, trust $host')),
                  ],
                ));
            if (ok == true) {
              await PasswordGuard.instance.allowHost(matched, host);
              NovaShieldEngine.instance.lockPosts(tabKey, false);
              if (context.mounted) Navigator.pop(context);
            }
          },
          child: const Text('This site is mine'),
        ),
        FilledButton.icon(
          onPressed: () async {
            Navigator.pop(context);
            await leave?.call();
          },
          icon: const Icon(Icons.exit_to_app_rounded, size: 18),
          label: const Text('Leave this page'),
        ),
      ],
      child: ListView(padding: const EdgeInsets.all(20), children: [
        Text('You typed a protected password on $host — but it belongs to ${belongs.join(', ')}.',
            style: p.ui(size: 14, weight: FontWeight.w700, color: p.text, height: 1.4)),
        const SizedBox(height: 10),
        Text(
          'This is how phishing works: a copy of a login page on another address collects your password (and even your 2FA code). '
          'NOVA X cancelled the send, cleared the field and is blocking uploads from this page.',
          style: p.ui(size: 13, color: p.textMuted, height: 1.45),
        ),
        const SizedBox(height: 14),
        ProCard(
          title: 'Protected passwords that matched',
          icon: Icons.lock_rounded,
          child: Column(children: [
            for (final e in matched) ProFindingRow(level: ProLevel.high, title: e.label, detail: 'Belongs to ${e.hosts.join(', ')}'),
          ]),
        ),
        Text('If you think you already sent it, change that password on the real site now.',
            style: p.ui(size: 12.5, color: p.warning)),
      ]),
    );
  }
}
