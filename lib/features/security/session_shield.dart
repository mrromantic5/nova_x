// lib/features/security/session_shield.dart
//
// Session Shield (3.13.0, ported from NOVA X for PC) — makes stolen session
// cookies expire sooner. For the sites the user protects (bank, email,
// admin panels…) NOVA X deletes their cookies and site storage:
//   • when NOVA X goes to the background and is closed — Android may close
//     NOVA X without warning, so protected sites are ALSO signed out every
//     time NOVA X starts (anything missed is cleaned then);
//   • optionally when NOVA X comes back after N minutes in the background;
//   • "Sign out of … now" at once.
// Cookies: CookieManager (NOVA X's own WebView only). Storage: WebStorage
// (localStorage, IndexedDB… of that origin). Incognito tabs keep nothing.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SessionShield extends ChangeNotifier {
  SessionShield._();
  static final SessionShield instance = SessionShield._();

  static const String _kSites = 'nova_session_shield_sites';
  static const String _kIdle = 'nova_session_shield_idle_min';
  static const String _kLog = 'nova_session_shield_log';
  static const String _kHosts = 'nova_session_shield_hosts';

  SharedPreferences? _prefs;
  bool _loaded = false;
  Future<void>? _loading;
  final Set<String> sites = {};

  /// Hosts seen under protected sites (Android can't list cookie domains, so
  /// NOVA X remembers which subdomains it visited, e.g. login.mybank.com).
  final Set<String> _hosts = {};
  int idleMinutes = 0; // 0 = only when NOVA X closes
  final List<String> log = [];
  DateTime? _backgroundSince;
  bool _startupDone = false;

  Future<void> ensureLoaded() => _loaded ? Future.value() : (_loading ??= _load());

  Future<void> _load() async {
    _prefs = await SharedPreferences.getInstance();
    sites
      ..clear()
      ..addAll(_prefs!.getStringList(_kSites) ?? const []);
    _hosts
      ..clear()
      ..addAll(_prefs!.getStringList(_kHosts) ?? const []);
    idleMinutes = _prefs!.getInt(_kIdle) ?? 0;
    log
      ..clear()
      ..addAll(_prefs!.getStringList(_kLog) ?? const []);
    _loaded = true;
  }

  static String _key(String host) => host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');

  /// Is [host] (or a parent domain) protected?
  bool isProtected(String host) {
    final h = _key(host);
    return h.isNotEmpty && sites.any((s) => h == s || h.endsWith('.$s'));
  }

  static bool hostUnder(String host, String site) {
    final h = host.toLowerCase().replaceFirst(RegExp(r'^\.'), '');
    return h == site || h.endsWith('.$site');
  }

  Future<void> setProtected(String host, bool on) async {
    await ensureLoaded();
    final h = _key(host);
    if (h.isEmpty) return;
    if (on) {
      sites.add(h);
    } else {
      sites.removeWhere((s) => h == s || h.endsWith('.$s'));
      _hosts.removeWhere((x) => hostUnder(x, h));
    }
    await _prefs?.setStringList(_kSites, sites.toList()..sort());
    await _prefs?.setStringList(_kHosts, _hosts.toList()..sort());
    notifyListeners();
  }

  Future<void> setIdleMinutes(int m) async {
    await ensureLoaded();
    idleMinutes = m.clamp(0, 24 * 60);
    await _prefs?.setInt(_kIdle, idleMinutes);
    notifyListeners();
  }

  /// A page of [host] was opened (not incognito): remember the host so its
  /// cookies are found later.
  Future<void> noteVisit(String host) async {
    await ensureLoaded();
    final h = host.toLowerCase();
    if (h.isEmpty || !isProtected(h) || _hosts.contains(h)) return;
    _hosts.add(h);
    if (_hosts.length > 200) _hosts.remove(_hosts.first);
    await _prefs?.setStringList(_kHosts, _hosts.toList()..sort());
  }

  void _addLog(String s) {
    final now = DateTime.now();
    log.insert(0, '${now.toIso8601String().substring(0, 16).replaceFirst('T', ' ')}  $s');
    if (log.length > 50) log.removeRange(50, log.length);
    _prefs?.setStringList(_kLog, log);
  }

  /// Deletes cookies and site storage of [targets] (sites) and the hosts
  /// seen under them. Returns how many cookies were deleted.
  Future<int> wipe(Iterable<String> targets) async {
    final list = targets.map(_key).where((s) => s.isNotEmpty).toSet();
    if (list.isEmpty) return 0;
    final hosts = <String>{
      for (final s in list) ...[s, 'www.$s'],
      for (final h in _hosts)
        if (list.any((s) => hostUnder(h, s))) h,
    };
    final cookies = CookieManager.instance();
    var deleted = 0;
    for (final h in hosts) {
      final url = WebUri('https://$h/');
      try {
        final before = await cookies.getCookies(url: url);
        deleted += before.length;
      } catch (_) {}
      try {
        await cookies.deleteCookies(url: url);
      } catch (_) {}
      for (final s in list) {
        if (!hostUnder(h, s)) continue;
        try {
          await cookies.deleteCookies(url: url, domain: '.$s');
        } catch (_) {}
      }
    }
    final storage = WebStorageManager.instance();
    for (final h in hosts) {
      for (final scheme in const ['https', 'http']) {
        try {
          await storage.deleteOrigin(origin: '$scheme://$h');
        } catch (_) {}
      }
    }
    return deleted;
  }

  // ── Start, background, return ─────────────────────────────────────────────

  /// NOVA X started: sign out of protected sites (closing may have been cut
  /// short by Android). Runs once per app run.
  Future<void> onAppStart() async {
    await ensureLoaded();
    if (_startupDone) return;
    _startupDone = true;
    if (sites.isEmpty) return;
    final n = await wipe(sites);
    if (n > 0) _addLog('NOVA X started: signed out of ${sites.length} protected site(s) ($n cookies)');
    notifyListeners();
  }

  /// NOVA X went to the background.
  void onBackground() => _backgroundSince ??= DateTime.now();

  /// NOVA X is closing (Android doesn't always say so; start-up covers that).
  Future<void> onAppExit() async {
    await ensureLoaded();
    if (sites.isEmpty) return;
    try {
      await wipe(sites).timeout(const Duration(seconds: 3));
      _addLog('NOVA X closed: signed out of ${sites.length} protected site(s)');
    } catch (_) {}
  }

  /// NOVA X is back on screen. Returns true when protected sites were signed
  /// out (the open tab may need a reload).
  Future<bool> onForeground() async {
    final since = _backgroundSince;
    _backgroundSince = null;
    await ensureLoaded();
    if (since == null || sites.isEmpty || idleMinutes <= 0) return false;
    final away = DateTime.now().difference(since);
    if (away.inMinutes < idleMinutes) return false;
    final n = await wipe(sites);
    _addLog('Away for ${away.inMinutes} min: signed out of ${sites.length} protected site(s) ($n cookies)');
    notifyListeners();
    return true;
  }

  /// "Sign out everywhere now" (all protected sites).
  Future<int> signOutEverywhereNow() async {
    await ensureLoaded();
    if (sites.isEmpty) return 0;
    final n = await wipe(sites);
    _addLog('Sign out everywhere: ${sites.join(', ')} ($n cookies)');
    notifyListeners();
    return n;
  }

  /// Signs out of one site (Site Control Center).
  Future<int> signOutSite(String host) async {
    await ensureLoaded();
    final key = _key(host);
    if (key.isEmpty) return 0;
    final n = await wipe([key]);
    _addLog('Signed out of $key ($n cookies)');
    notifyListeners();
    return n;
  }

  String exportJson() => jsonEncode({'sites': sites.toList(), 'idle': idleMinutes});
}
