// lib/features/shield/engine/shield_engine.dart
//
// NOVA Shield blocking on Android (3.13.0), ported from NOVA X for PC.
//
//  • Requests made by pages inside NOVA X's own WebView are checked in the
//    browser's shouldInterceptRequest. A request is blocked when its host
//    (or a parent domain) is on the EasyList / EasyPrivacy domain lists and
//    it is THIRD-PARTY (a different site from the page) — the same rule as
//    the PC engine. The page itself (main frame) is never blocked.
//  • A blocked request gets an empty 403 answer.
//  • Every number shown comes from a real blocked request: per page (the
//    current tab) and lifetime / per day, stored on this phone. Nothing is
//    estimated.
//  • Off when the ad & tracker blocker is off, and on sites where the user
//    paused NOVA Shield.
//
// Only NOVA X's own WebView is affected: other apps' ads are never touched
// (Google Play Device and Network Abuse policy).

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/database/local_db.dart';
import 'shield_cosmetic.dart';
import 'shield_lists.dart';

/// One blocked request.
class ShieldEvent {
  ShieldEvent({required this.url, required this.host, required this.rule, required this.category, required this.type, required this.at});

  final String url;
  final String host;

  /// The list domain that matched (the host itself or a parent domain).
  final String rule;
  final String category;

  /// 'image' | 'media' | 'document' | 'script' | 'other' (from the request).
  final String type;
  final DateTime at;
}

/// The counts for the page shown in one tab.
class TabShieldCounts {
  String page = '';
  int total = 0;
  final Map<String, int> byCategory = {};
  final Map<String, int> byHost = {};
  final List<ShieldEvent> recent = [];

  int get uniqueHosts => byHost.length;

  void reset(String newPage) {
    page = newPage;
    total = 0;
    byCategory.clear();
    byHost.clear();
    recent.clear();
  }

  void add(ShieldEvent e) {
    total++;
    byCategory[e.category] = (byCategory[e.category] ?? 0) + 1;
    if (e.host.isNotEmpty) byHost[e.host] = (byHost[e.host] ?? 0) + 1;
    recent.add(e);
    if (recent.length > 300) recent.removeAt(0);
  }
}

/// "shop.news.example.co.uk" → "example.co.uk" (same rule as NOVA Cyber).
String shieldSiteOf(String host) {
  final h = host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
  if (RegExp(r'^\d+\.\d+\.\d+\.\d+$').hasMatch(h) || h.contains(':')) return h;
  final p = h.split('.');
  if (p.length <= 2) return h;
  const second = {'co', 'com', 'org', 'net', 'gov', 'edu', 'ac', 'or', 'ne', 'go', 'gob', 'mil', 'nic', 'sch'};
  final n = second.contains(p[p.length - 2]) && p.last.length == 2 ? 3 : 2;
  return p.sublist(p.length - n).join('.');
}

class NovaShieldEngine extends ChangeNotifier {
  NovaShieldEngine._();
  static final NovaShieldEngine instance = NovaShieldEngine._();

  static const String _kPaused = 'nova_shield_paused_sites';
  static const String _kLifetime = 'nova_shield_lifetime_v1';

  SharedPreferences? _prefs;
  bool _ready = false;
  Future<void>? _init;

  /// Domain rules (null until loaded: nothing is blocked before that).
  Map<String, String>? _rules;
  String listSource = '';
  DateTime? listUpdated;
  int get ruleCount => _rules?.length ?? 0;

  final Set<String> paused = {};
  final Map<int, TabShieldCounts> _tabs = {};
  int lifetimeTotal = 0;
  final Map<String, int> lifetimeByCategory = {};
  final Map<String, int> perDay = {}; // 'yyyy-mm-dd' → count
  Timer? _saveTimer;

  /// The ad & tracker blocker switch (Settings and the browser menu).
  bool get enabled => testEnabled ?? LocalDB.getAdBlockEnabled();

  /// Tests only: the switch and the rules without the phone's storage.
  @visibleForTesting
  bool? testEnabled;

  @visibleForTesting
  void useRulesForTest(Map<String, String> rules) => _rules = rules;

  Future<void> ensureReady() => _ready ? Future.value() : (_init ??= _load());

  Future<void> _load() async {
    _prefs = await SharedPreferences.getInstance();
    paused
      ..clear()
      ..addAll(_prefs!.getStringList(_kPaused) ?? const []);
    try {
      final raw = _prefs!.getString(_kLifetime);
      if (raw != null) {
        final j = jsonDecode(raw);
        if (j is Map) {
          lifetimeTotal = (j['total'] as num?)?.toInt() ?? 0;
          final cats = j['cats'];
          if (cats is Map) cats.forEach((k, v) => lifetimeByCategory['$k'] = (v as num).toInt());
          final days = j['days'];
          if (days is Map) days.forEach((k, v) => perDay['$k'] = (v as num).toInt());
        }
      }
    } catch (_) {}
    try {
      final lists = await ShieldLists.instance.load();
      _useLists(lists);
    } catch (_) {}
    unawaited(ShieldCosmetic.instance.load());
    _ready = true;
    notifyListeners();
    // Fresh lists once a week, in the background.
    unawaited(_backgroundUpdate());
  }

  void _useLists(ShieldListSet lists) {
    _rules = lists.rules;
    listSource = lists.source;
    listUpdated = lists.updated;
  }

  Future<void> _backgroundUpdate() async {
    await Future<void>.delayed(const Duration(seconds: 20));
    final fresh = await ShieldLists.instance.updateIfDue();
    if (fresh != null) {
      _useLists(fresh);
      notifyListeners();
    }
  }

  /// Downloads the lists now (NOVA Shield › About lists › Update now).
  Future<bool> updateListsNow() async {
    final fresh = await ShieldLists.instance.updateIfDue(force: true);
    await ShieldCosmetic.instance.updateIfDue(force: true);
    if (fresh == null) return false;
    _useLists(fresh);
    notifyListeners();
    return true;
  }

  TabShieldCounts countsFor(int tab) => _tabs[tab] ??= TabShieldCounts();

  void forgetTab(int tab) {
    _tabs.remove(tab);
    _locked.remove(tab);
  }

  // Password Guard: after a protected password was stopped on a page, every
  // upload from that tab (any request that isn't a plain GET/HEAD) is
  // refused until the user decides — even when the blocker itself is off.
  final Set<int> _locked = {};

  void lockPosts(int tab, bool on) {
    if (on) {
      _locked.add(tab);
    } else {
      _locked.remove(tab);
    }
  }

  bool isLocked(int tab) => _locked.contains(tab);

  /// Should this request from a locked tab be refused?
  bool refusedUpload(int tab, String method) {
    if (!_locked.contains(tab)) return false;
    final m = method.toUpperCase();
    return m != 'GET' && m != 'HEAD' && m != 'OPTIONS';
  }

  int blockedToday() => perDay[_dayKey(DateTime.now())] ?? 0;

  static String _dayKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// A new page starts loading in [tab]: its counts start from zero.
  void pageStarted(int tab, String url) {
    final c = countsFor(tab);
    if (c.page == url) return;
    c.reset(url);
    notifyListeners();
  }

  // ── Matching ──────────────────────────────────────────────────────────────

  /// The list rule [host] matches (itself or a parent domain), or null.
  String? matchHost(String host) {
    final rules = _rules;
    if (rules == null || host.isEmpty) return null;
    var h = host.toLowerCase();
    if (h.endsWith('.')) h = h.substring(0, h.length - 1);
    while (true) {
      if (rules.containsKey(h)) return h;
      final dot = h.indexOf('.');
      if (dot < 0 || h.indexOf('.', dot + 1) < 0) return null; // stop at "example.com"
      h = h.substring(dot + 1);
    }
  }

  /// Is [url] (loaded by the page [pageUrl]) blocked? Returns the event to
  /// record, or null. Pure check: nothing is counted here.
  ShieldEvent? check(String url, String pageUrl, {String type = 'other'}) {
    if (!enabled) return null;
    final u = Uri.tryParse(url);
    if (u == null || (u.scheme != 'http' && u.scheme != 'https' && u.scheme != 'ws' && u.scheme != 'wss')) return null;
    final page = Uri.tryParse(pageUrl);
    final pageHost = page?.host ?? '';
    if (pageHost.isNotEmpty && isPaused(pageHost)) return null;
    // Third-party only: a site's own requests are never blocked.
    if (pageHost.isNotEmpty && shieldSiteOf(u.host) == shieldSiteOf(pageHost)) return null;
    final rule = matchHost(u.host);
    if (rule == null) return null;
    return ShieldEvent(url: url, host: u.host, rule: rule, category: _rules![rule] ?? ShieldCategory.ads, type: type, at: DateTime.now());
  }

  /// Records a blocked request for [tab] (counts + page clean-up).
  void record(int tab, ShieldEvent e) {
    countsFor(tab).add(e);
    lifetimeTotal++;
    lifetimeByCategory[e.category] = (lifetimeByCategory[e.category] ?? 0) + 1;
    final day = _dayKey(e.at);
    perDay[day] = (perDay[day] ?? 0) + 1;
    if (perDay.length > 60) {
      final keys = perDay.keys.toList()..sort();
      for (final k in keys.take(perDay.length - 60)) {
        perDay.remove(k);
      }
    }
    _scheduleSave();
    _notifySoon();
  }

  /// Guesses the kind of request from what the WebView sends (Android does
  /// not say whether a request is an image, a frame or a script).
  static String requestType(WebResourceRequest r) {
    final accept = (r.headers?['Accept'] ?? r.headers?['accept'] ?? '').toLowerCase();
    final path = r.url.path.toLowerCase();
    if (accept.startsWith('image/') || RegExp(r'\.(png|jpe?g|gif|webp|avif|svg|ico|bmp)$').hasMatch(path)) return 'image';
    if (accept.startsWith('video/') || accept.startsWith('audio/') || RegExp(r'\.(mp4|webm|m3u8|mp3|ogg|mov)$').hasMatch(path)) return 'media';
    if (accept.startsWith('text/html')) return 'document';
    if (RegExp(r'\.m?js$').hasMatch(path)) return 'script';
    return 'other';
  }

  /// The empty answer given for a blocked request.
  static WebResourceResponse blockedResponse() => WebResourceResponse(
        contentType: 'text/plain',
        contentEncoding: 'utf-8',
        statusCode: 403,
        reasonPhrase: 'Blocked by NOVA Shield',
        headers: const {'Cache-Control': 'no-store'},
        data: Uint8List(0),
      );

  Timer? _notifyTimer;
  void _notifySoon() {
    if (_notifyTimer?.isActive ?? false) return;
    _notifyTimer = Timer(const Duration(milliseconds: 250), notifyListeners);
  }

  void _scheduleSave() {
    if (_saveTimer?.isActive ?? false) return;
    _saveTimer = Timer(const Duration(seconds: 5), () {
      _prefs?.setString(_kLifetime, jsonEncode({'total': lifetimeTotal, 'cats': lifetimeByCategory, 'days': perDay}));
    });
  }

  // ── Settings ──────────────────────────────────────────────────────────────

  Future<void> setEnabled(bool v) async {
    await LocalDB.setAdBlockEnabled(v);
    notifyListeners();
  }

  static String siteKey(String host) => host.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');

  bool isPaused(String host) {
    final h = siteKey(host);
    return paused.any((p) => h == p || h.endsWith('.$p'));
  }

  Future<void> setPaused(String host, bool pause) async {
    await ensureReady();
    final h = siteKey(host);
    if (h.isEmpty) return;
    if (pause) {
      paused.add(h);
    } else {
      paused.removeWhere((p) => h == p || h.endsWith('.$p'));
    }
    await _prefs?.setStringList(_kPaused, paused.toList()..sort());
    notifyListeners();
  }

  Future<void> resetLifetime() async {
    lifetimeTotal = 0;
    lifetimeByCategory.clear();
    perDay.clear();
    await _prefs?.remove(_kLifetime);
    notifyListeners();
  }
}
