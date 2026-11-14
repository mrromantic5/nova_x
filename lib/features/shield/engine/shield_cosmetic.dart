// lib/features/shield/engine/shield_cosmetic.dart
//
// NOVA Shield — page clean-up (the part of ad blocking you can see).
//
// NOVA Shield stops ad and tracker requests before they leave the phone,
// but the page still keeps the boxes it made for them. This file removes
// those leftovers, the way mature blockers do:
//
//  1. Collapse: when the engine blocks an ad frame, image or video, the
//     element that was waiting for it (and empty wrappers around it) is
//     hidden, so the content moves up instead of leaving a grey gap.
//  2. Element hiding: EasyList's element-hiding rules ("##" rules) —
//     ~13,000 generic ad-container rules plus ~9,000 rules for specific
//     sites, with their exceptions.
//       • Generic rules are applied by a small "surveyor" in the page: it
//         only adds a rule when an element with that id / class actually
//         exists, so pages don't pay for 13,000 selectors.
//       • Site rules are sent for the site being opened (a document-start
//         user script, before the page's own scripts run; checked again
//         when the page has loaded).
//
// Off on sites where NOVA Shield is paused, when Shield blocking is off,
// and in Safe View. Procedural rules (":has-text", scriptlets) are not used.
// Lists: EasyList (https://easylist.to/), GPLv3 / CC BY-SA 3.0. Refreshed
// weekly on this phone; a bundled snapshot is used until then.
// Android (3.13.0): same rules, surveyor and collapse logic as NOVA X for PC.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'shield_lists.dart' show ShieldLists;

/// Parsed element-hiding rules.
class CosmeticRules {
  CosmeticRules({
    required this.ids,
    required this.classes,
    required this.complex,
    required this.specific,
    required this.exceptions,
  });

  /// Generic "##" rules split for the surveyor: plain ids, plain classes,
  /// and the rest (attribute / compound selectors).
  final Set<String> ids;
  final Set<String> classes;
  final List<String> complex;

  /// Site rules: domain → selectors.
  final Map<String, List<String>> specific;

  /// Exceptions ("#@#"): domain → selectors not to hide there (generic or site).
  final Map<String, List<String>> exceptions;

  int get genericCount => ids.length + classes.length + complex.length;
  int get siteCount => specific.values.fold(0, (n, l) => n + l.length);
  int get count => genericCount + siteCount;

  static final RegExp _plain = RegExp(r'^[A-Za-z0-9_-]+$');
  static final RegExp _domain = RegExp(r'^[a-z0-9*][a-z0-9.*-]*$');

  /// Element-hiding lines of an Adblock-style list (other lines are skipped).
  static CosmeticRules parse(String text) {
    final ids = <String>{};
    final classes = <String>{};
    final complex = <String>{};
    final specific = <String, Set<String>>{};
    final exceptions = <String, Set<String>>{};
    for (var line in const LineSplitter().convert(text)) {
      line = line.trim();
      if (line.isEmpty || line.startsWith('!') || line.startsWith('[')) continue;
      // Procedural / scriptlet rules are not supported here.
      if (line.contains('#?#') || line.contains(r'#$#') || line.contains('#%#') ||
          line.contains(':-abp-') || line.contains(':has-text') || line.contains(':upward') ||
          line.contains(':xpath') || line.contains(':style(') || line.contains(':remove(')) {
        continue;
      }
      final exc = line.indexOf('#@#');
      final hide = line.indexOf('##');
      final int at;
      final bool isException;
      if (exc >= 0 && (hide < 0 || exc < hide)) {
        at = exc;
        isException = true;
      } else if (hide >= 0) {
        at = hide;
        isException = false;
      } else {
        continue;
      }
      final domains = line.substring(0, at).trim();
      final selector = line.substring(at + (isException ? 3 : 2)).trim();
      if (selector.isEmpty || selector.length > 400 || selector.contains('{') || selector.contains('}')) continue;
      if (domains.isEmpty) {
        if (isException) continue; // a generic exception (rare) — ignored
        if (selector.startsWith('#') && _plain.hasMatch(selector.substring(1))) {
          ids.add(selector.substring(1));
        } else if (selector.startsWith('.') && _plain.hasMatch(selector.substring(1))) {
          classes.add(selector.substring(1));
        } else {
          complex.add(selector);
        }
        continue;
      }
      for (var d in domains.split(',')) {
        d = d.trim().toLowerCase();
        if (d.isEmpty || d.startsWith('~') || !_domain.hasMatch(d)) continue; // "~site" negations are skipped
        (isException ? exceptions : specific).putIfAbsent(d, () => <String>{}).add(selector);
      }
    }
    return CosmeticRules(
      ids: ids,
      classes: classes,
      complex: complex.toList(),
      specific: {for (final e in specific.entries) e.key: e.value.toList()},
      exceptions: {for (final e in exceptions.entries) e.key: e.value.toList()},
    );
  }

  /// "shop.news.example.co.uk" → itself and every parent domain.
  static List<String> _hostChain(String host) {
    final h = host.toLowerCase().replaceFirst(RegExp(r'\.$'), '');
    final parts = h.split('.');
    return [for (var i = 0; i < parts.length - 1; i++) parts.sublist(i).join('.')];
  }

  /// What applies on [host]: site selectors to hide and selectors excepted.
  ({List<String> hide, List<String> except}) forHost(String host) {
    final hide = <String>{};
    final except = <String>{};
    for (final d in _hostChain(host)) {
      hide.addAll(specific[d] ?? const []);
      except.addAll(exceptions[d] ?? const []);
      // "example.*" style entries (any top-level domain).
      final dot = d.indexOf('.');
      if (dot > 0) {
        final wild = '${d.substring(0, d.lastIndexOf('.'))}.*';
        hide.addAll(specific[wild] ?? const []);
        except.addAll(exceptions[wild] ?? const []);
      }
    }
    hide.removeAll(except);
    return (hide: hide.toList(), except: except.toList());
  }

  /// The generic data embedded in the page surveyor.
  String surveyorData() => jsonEncode({'i': ids.join(' '), 'c': classes.join(' '), 'x': complex});
}

class ShieldCosmetic {
  ShieldCosmetic._();
  static final ShieldCosmetic instance = ShieldCosmetic._();

  static const String asset = 'assets/shield/nova_cosmetic.txt';
  static const Duration updateEvery = Duration(days: 7);
  static const int minimumRules = 5000;
  static const String _gh = 'https://raw.githubusercontent.com/easylist/easylist/master/easylist';
  static const List<String> sources = [
    '$_gh/easylist_general_hide.txt',
    '$_gh/easylist_specific_hide.txt',
    '$_gh/easylist_allowlist_general_hide.txt',
  ];

  CosmeticRules? _rules;
  Future<CosmeticRules?>? _loading;
  String? _script; // the surveyor (built once per run)
  bool _updating = false;
  DateTime? updated; // null = bundled snapshot

  CosmeticRules? get rules => _rules;

  /// Static so the isolate closure captures only the text.
  static Future<CosmeticRules> _parse(String text) => Isolate.run(() => CosmeticRules.parse(text));

  static Future<File> _cache() async => File('${(await ShieldLists.shieldDir()).path}${Platform.pathSeparator}cosmetic.txt');

  Future<CosmeticRules?> load() => _rules != null ? Future.value(_rules) : (_loading ??= _load());

  Future<CosmeticRules?> _load() async {
    try {
      final cache = await _cache();
      if (await cache.exists()) {
        final text = await cache.readAsString();
        final r = await _parse(text);
        if (r.count >= minimumRules) {
          _rules = r;
          updated = (await cache.lastModified());
        }
      }
    } catch (_) {}
    if (_rules == null) {
      try {
        final text = await rootBundle.loadString(asset);
        _rules = await _parse(text);
      } catch (_) {}
    }
    final r = _rules;
    if (r != null) _script = surveyorSource(r.surveyorData());
    unawaited(Future<void>.delayed(const Duration(seconds: 40), updateIfDue));
    return r;
  }

  /// Weekly refresh from the EasyList repository (takes effect for new tabs
  /// and on the next start; site rules apply right away).
  Future<bool> updateIfDue({bool force = false}) async {
    if (_updating) return false;
    try {
      final cache = await _cache();
      if (!force && await cache.exists() && DateTime.now().difference(await cache.lastModified()) < updateEvery) {
        return false;
      }
    } catch (_) {}
    _updating = true;
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..userAgent = 'NOVA-X-Shield/1.0 (+list update)';
    try {
      final parts = <String>[];
      for (final url in sources) {
        final req = await client.getUrl(Uri.parse(url)).timeout(const Duration(seconds: 20));
        final res = await req.close().timeout(const Duration(seconds: 60));
        if (res.statusCode != 200) {
          await res.drain<void>();
          return false;
        }
        parts.add(await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 120)));
      }
      final text = parts.join('\n');
      final r = await _parse(text);
      if (r.count < minimumRules) return false;
      await (await ShieldLists.shieldDir()).create(recursive: true);
      final cache = await _cache();
      final tmp = File('${cache.path}.tmp');
      await tmp.writeAsString(text, flush: true);
      if (await cache.exists()) await cache.delete();
      await tmp.rename(cache.path);
      _rules = r;
      _script = surveyorSource(r.surveyorData());
      updated = DateTime.now();
      return true;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
      _updating = false;
    }
  }

  // ── In the page ───────────────────────────────────────────────────────────

  /// Document-start script for main frames (null until the rules are loaded).
  String? script() => _script;

  /// The per-site part, as a script that configures the surveyor.
  static String siteConfigScript({required bool off, required List<String> hide, required List<String> except}) {
    final cfg = jsonEncode({'off': off, 'hide': hide, 'exc': except});
    return '(function(){var c=$cfg;window.__novaCosCfg=c;if(window.__novaCosApply)window.__novaCosApply(c);})();';
  }

  static const String _siteGroup = 'nova_shield_cosmetic_site';

  /// A page of [host] starts loading in [c]: its site rules are queued as a
  /// document-start user script (Android System WebView runs it before the
  /// page's own scripts on the next document).
  Future<void> applyOnLoadStart(InAppWebViewController c, String host, {required bool off}) async {
    final r = await load();
    if (r == null) return;
    final site = off ? (hide: const <String>[], except: const <String>[]) : r.forHost(host);
    final source = siteConfigScript(off: off, hide: site.hide, except: site.except);
    try {
      await c.removeUserScriptsByGroupName(groupName: _siteGroup);
      await c.addUserScript(
        userScript: UserScript(
          groupName: _siteGroup,
          source: source,
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
          forMainFrameOnly: true,
        ),
      );
    } catch (_) {}
    // The document may already exist: configure it now as well.
    try {
      await c.evaluateJavascript(source: source);
    } catch (_) {}
  }

  /// After load: make sure the page has its settings (if the early script
  /// missed this document) — harmless when it already has them.
  Future<void> applyOnLoadStop(InAppWebViewController c, String host, {required bool off}) async {
    final r = await load();
    if (r == null) return;
    final site = off ? (hide: const <String>[], except: const <String>[]) : r.forHost(host);
    try {
      final script = _script;
      // The surveyor itself, in case the document-start script didn't run
      // (it returns at once when it is already in the page).
      if (!off && script != null) await c.evaluateJavascript(source: script);
      await c.evaluateJavascript(source: siteConfigScript(off: off, hide: site.hide, except: site.except));
    } catch (_) {}
  }

  /// Hides the elements that were waiting for blocked [urls] (ad frames,
  /// images, videos) and empty wrappers around them.
  static Future<void> collapse(InAppWebViewController c, List<String> urls) async {
    if (urls.isEmpty) return;
    try {
      await c.evaluateJavascript(source: 'window.__novaCollapse&&window.__novaCollapse(${jsonEncode(urls)});');
    } catch (_) {}
  }

  /// The surveyor + collapser (public for tests).
  static String surveyorSource(String data) => _template.replaceFirst('__DATA__', data);

  static const String _template = r'''
(function () {
  'use strict';
  if (window.__novaCosmetic) return;
  try { Object.defineProperty(window, '__novaCosmetic', { value: 1 }); } catch (e) { return; }
  var D = __DATA__;
  var IDS = null, CLS = null;
  var cfg = null, off = false, exc = new Set(), done = new Set(), sheet = null, styleEl = null;
  var blocked = new Set(), pending = [], timer = 0, observer = null;

  function ensureSheet() {
    if (styleEl && styleEl.isConnected && sheet) return true;
    var root = document.head || document.documentElement;
    if (!root) return false;
    styleEl = document.createElement('style');
    root.appendChild(styleEl);
    sheet = styleEl.sheet;
    // Rules added before (if the page replaced the <head>).
    done.forEach(function (sel) { insert(sel); });
    return !!sheet;
  }
  function insert(sel) {
    try { sheet.insertRule(sel + '{display:none!important}', sheet.cssRules.length); } catch (e) {}
  }
  function hide(sel) {
    if (off || done.has(sel) || exc.has(sel)) return;
    done.add(sel);
    // Before <html> exists the rule waits in "done"; ensureSheet adds it.
    if (sheet && styleEl && styleEl.isConnected) insert(sel); else ensureSheet();
  }

  // Generic rules: only for ids / classes that exist on this page.
  function survey(el) {
    if (!el || el.nodeType !== 1) return;
    var id = el.id;
    if (id && IDS.has(id)) hide('#' + id);
    var cl = el.classList;
    if (cl && cl.length) for (var i = 0; i < cl.length; i++) if (CLS.has(cl[i])) hide('.' + cl[i]);
    var t = el.tagName;
    if (blocked.size && (t === 'IFRAME' || t === 'IMG' || t === 'VIDEO' || t === 'EMBED' || t === 'OBJECT')) checkBlocked(el);
  }
  function surveyTree(root) {
    survey(root);
    if (!root.querySelectorAll) return;
    var list = root.querySelectorAll('[id],[class],iframe,img,video,embed,object');
    for (var i = 0; i < list.length; i++) survey(list[i]);
  }
  function flush() {
    timer = 0;
    if (!off && done.size) ensureSheet();
    var batch = pending; pending = [];
    for (var i = 0; i < batch.length; i++) if (batch[i].isConnected) surveyTree(batch[i]);
  }
  function queue(n) {
    pending.push(n);
    if (!timer) timer = setTimeout(flush, 60);
  }
  function start() {
    if (off || observer) return;
    if (!IDS) { IDS = new Set(D.i ? D.i.split(' ') : []); CLS = new Set(D.c ? D.c.split(' ') : []); }
    for (var i = 0; i < D.x.length; i++) hide(D.x[i]);
    if (document.documentElement) surveyTree(document.documentElement);
    observer = new MutationObserver(function (muts) {
      for (var i = 0; i < muts.length; i++) {
        var m = muts[i];
        if (m.type === 'attributes') queue(m.target);
        else for (var j = 0; j < m.addedNodes.length; j++) if (m.addedNodes[j].nodeType === 1) queue(m.addedNodes[j]);
      }
    });
    observer.observe(document, { childList: true, subtree: true, attributes: true, attributeFilter: ['id', 'class'] });
  }
  function stop() {
    if (observer) { observer.disconnect(); observer = null; }
    if (styleEl) { try { styleEl.remove(); } catch (e) {} }
    styleEl = null; sheet = null; done.clear();
  }

  window.__novaCosApply = function (c) {
    c = c || {};
    var wasOff = off;
    cfg = c; off = !!c.off; exc = new Set(c.exc || []);
    if (off) { stop(); return; }
    if (wasOff) done.clear();
    (c.hide || []).forEach(hide);
    start();
  };

  // ── Collapse elements whose request the engine blocked ──
  function key(u) { try { return new URL(u, location.href).href.slice(0, 300); } catch (e) { return ''; } }
  function srcOf(el) {
    return el.currentSrc || el.src || el.data || el.getAttribute('src') || el.getAttribute('data') || '';
  }
  function hasContent(p, except) {
    if ((p.innerText || '').trim().length > 0) return true;
    for (var c = p.firstElementChild; c; c = c.nextElementSibling) {
      if (c === except || /^(SCRIPT|STYLE|NOSCRIPT|TEMPLATE|LINK|META)$/.test(c.tagName)) continue;
      if (c.offsetWidth * c.offsetHeight > 0) return true;
    }
    return false;
  }
  function collapse(el) {
    if (off || el.__novaCollapsed) return;
    el.__novaCollapsed = 1;
    if (el.tagName === 'SOURCE' && el.parentElement) el = el.parentElement;
    el.style.setProperty('display', 'none', 'important');
    var child = el, p = el.parentElement;
    for (var depth = 0; p && depth < 3; depth++) {
      if (p === document.body || p === document.documentElement) break;
      if (hasContent(p, child)) break;
      p.style.setProperty('display', 'none', 'important');
      child = p; p = p.parentElement;
    }
  }
  function checkBlocked(el) {
    var s = srcOf(el);
    if (s && blocked.has(key(s))) collapse(el);
  }
  window.__novaCollapse = function (urls) {
    if (off || !urls) return;
    for (var i = 0; i < urls.length; i++) { var k = key(urls[i]); if (k) blocked.add(k); }
    var list = document.querySelectorAll('iframe,img,video,embed,object,source');
    for (var j = 0; j < list.length; j++) checkBlocked(list[j]);
  };

  if (window.__novaCosCfg) window.__novaCosApply(window.__novaCosCfg);
})();''';
}
