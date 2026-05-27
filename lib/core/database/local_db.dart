// lib/core/database/local_db.dart
//
// NOVA X local persistence layer — SharedPreferences-backed.
// v2.2 additions:
//   • Background image preference (asset path or device file path)
//   • Custom Quick Access speed dial (user-edited list)
//   • Business search-count tracking for algorithmic ordering

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class LocalDB {
  static late SharedPreferences _p;

  // ── Keys ───────────────────────────────────────────────────────────────────
  static const _kProfile        = 'nx_profile';
  static const _kProfileImg     = 'nx_profile_image';
  static const _kSearch         = 'nx_search_history';
  static const _kHistory        = 'nx_history';
  static const _kBookmarks      = 'nx_bookmarks';
  static const _kDownloads      = 'nx_downloads';
  static const _kBusinesses     = 'nx_businesses';
  static const _kSearchEngine   = 'nx_search_engine';
  static const _kBackground     = 'nx_background_image';   // NEW
  static const _kSpeedDial      = 'nx_speed_dial';         // NEW

  // ── Default Quick Access list (used until user customises) ────────────────
  static const List<Map<String, dynamic>> defaultSpeedDial = [
    {'name': 'Google',    'url': 'https://google.com',                   'domain': 'google.com'},
    {'name': 'YouTube',   'url': 'https://m.youtube.com',                'domain': 'youtube.com'},
    {'name': 'Facebook',  'url': 'https://m.facebook.com',               'domain': 'facebook.com'},
    {'name': 'WhatsApp',  'url': 'https://web.whatsapp.com',             'domain': 'whatsapp.com'},
    {'name': 'Instagram', 'url': 'https://instagram.com',                'domain': 'instagram.com'},
    {'name': 'ChatXAP',   'url': 'https://c.x.t-lyfe.com.ng/login.html', 'domain': 'c.x.t-lyfe.com.ng'},
    {'name': 'X',         'url': 'https://x.com',                        'domain': 'x.com'},
    {'name': 'TikTok',    'url': 'https://www.tiktok.com',               'domain': 'tiktok.com'},
    {'name': 'Wikipedia', 'url': 'https://en.m.wikipedia.org',           'domain': 'wikipedia.org'},
    {'name': 'Gmail',     'url': 'https://mail.google.com',              'domain': 'mail.google.com'},
  ];

  // ── Init ──────────────────────────────────────────────────────────────────
  static Future<void> initialize() async {
    _p = await SharedPreferences.getInstance();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PROFILE
  // ═══════════════════════════════════════════════════════════════════════════
  static Map<String, dynamic> getProfile() {
    final raw = _p.getString(_kProfile);
    if (raw == null) return {'name': '', 'email': '', 'avatarColor': 'cyan'};
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return {'name': '', 'email': '', 'avatarColor': 'cyan'};
    }
  }

  static Future<void> saveProfile(Map<String, dynamic> data) async =>
      _p.setString(_kProfile, jsonEncode(data));

  static String? getProfileImagePath() => _p.getString(_kProfileImg);

  static Future<void> saveProfileImagePath(String path) async =>
      _p.setString(_kProfileImg, path);

  static Future<void> clearProfileImage() async => _p.remove(_kProfileImg);

  // ═══════════════════════════════════════════════════════════════════════════
  // BACKGROUND IMAGE
  // ═══════════════════════════════════════════════════════════════════════════
  /// Returns the chosen background. Format:
  ///   • "assets/backgrounds/foo.jpg" — bundled asset
  ///   • "/data/user/0/.../bg.jpg"    — device file path
  ///   • null                          — use default gradient
  static String? getBackgroundImage() => _p.getString(_kBackground);

  static Future<void> setBackgroundImage(String path) async =>
      _p.setString(_kBackground, path);

  static Future<void> clearBackgroundImage() async => _p.remove(_kBackground);

  /// True if the saved value points to a bundled asset
  static bool isBackgroundAsset() {
    final bg = getBackgroundImage();
    return bg != null && bg.startsWith('assets/');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SPEED DIAL (Quick Access)
  // ═══════════════════════════════════════════════════════════════════════════
  /// Returns user's custom list or [defaultSpeedDial] if never edited.
  static List<Map<String, dynamic>> getSpeedDial() {
    final raw = _p.getStringList(_kSpeedDial);
    if (raw == null) {
      return defaultSpeedDial.map((m) => Map<String, dynamic>.from(m)).toList();
    }
    final out = <Map<String, dynamic>>[];
    for (final s in raw) {
      try {
        out.add(jsonDecode(s) as Map<String, dynamic>);
      } catch (_) {}
    }
    return out;
  }

  static Future<void> saveSpeedDial(List<Map<String, dynamic>> sites) async =>
      _p.setStringList(_kSpeedDial, sites.map(jsonEncode).toList());

  static Future<void> resetSpeedDial() async => _p.remove(_kSpeedDial);

  /// Extracts a clean domain from any URL — used when adding a custom site.
  static String extractDomain(String url) {
    var u = url.trim();
    if (u.startsWith('http://'))  u = u.substring(7);
    if (u.startsWith('https://')) u = u.substring(8);
    if (u.startsWith('www.'))     u = u.substring(4);
    final slash = u.indexOf('/');
    if (slash > 0) u = u.substring(0, slash);
    return u;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SEARCH ENGINE
  // ═══════════════════════════════════════════════════════════════════════════
  static String getSearchEngine() => _p.getString(_kSearchEngine) ?? 'google';

  static Future<void> setSearchEngine(String engine) async =>
      _p.setString(_kSearchEngine, engine);

  // ═══════════════════════════════════════════════════════════════════════════
  // SEARCH HISTORY
  // ═══════════════════════════════════════════════════════════════════════════
  static List<String> getSearchHistory() => _p.getStringList(_kSearch) ?? [];

  static Future<void> addSearchQuery(String q) async {
    final list = getSearchHistory()..remove(q);
    list.insert(0, q);
    await _p.setStringList(_kSearch, list.take(30).toList());
  }

  static Future<void> removeSearchQuery(String q) async {
    final list = getSearchHistory()..remove(q);
    await _p.setStringList(_kSearch, list);
  }

  static Future<void> clearSearchHistory() async => _p.remove(_kSearch);

  static String buildSearchUrl(String q) {
    final trimmed = q.trim();
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    final domainRx =
        RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9\-\.]+\.[a-zA-Z]{2,}(/.*)?$');
    if (domainRx.hasMatch(trimmed) && !trimmed.contains(' ')) {
      return 'https://$trimmed';
    }
    final encoded = Uri.encodeComponent(trimmed);
    return switch (getSearchEngine()) {
      'bing'       => 'https://www.bing.com/search?q=$encoded',
      'duckduckgo' => 'https://duckduckgo.com/?q=$encoded',
      'yahoo'      => 'https://search.yahoo.com/search?p=$encoded',
      _            => 'https://www.google.com/search?q=$encoded',
    };
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // HISTORY
  // ═══════════════════════════════════════════════════════════════════════════
  static List<Map<String, dynamic>> getHistory() {
    return (_p.getStringList(_kHistory) ?? [])
        .map((s) {
          try { return jsonDecode(s) as Map<String, dynamic>; }
          catch (_) { return <String, dynamic>{}; }
        })
        .where((m) => m.isNotEmpty)
        .toList();
  }

  static Future<void> saveHistoryItem(String url, String title) async {
    final list = getHistory();
    list.removeWhere((h) => h['url'] == url);
    list.insert(0, {
      'url':   url,
      'title': title.isNotEmpty ? title : url,
      'time':  DateTime.now().toIso8601String(),
    });
    await _p.setStringList(_kHistory, list.take(200).map(jsonEncode).toList());
  }

  static Future<void> clearHistory() async => _p.remove(_kHistory);

  // ═══════════════════════════════════════════════════════════════════════════
  // BOOKMARKS
  // ═══════════════════════════════════════════════════════════════════════════
  static List<Map<String, dynamic>> getBookmarks() {
    return (_p.getStringList(_kBookmarks) ?? [])
        .map((s) {
          try { return jsonDecode(s) as Map<String, dynamic>; }
          catch (_) { return <String, dynamic>{}; }
        })
        .where((m) => m.isNotEmpty)
        .toList();
  }

  static bool isBookmarked(String url) =>
      getBookmarks().any((b) => b['url'] == url);

  static Future<void> addBookmark(String url, String title) async {
    final list = getBookmarks();
    if (!list.any((b) => b['url'] == url)) {
      list.insert(0, {
        'url':   url,
        'title': title.isNotEmpty ? title : url,
        'time':  DateTime.now().toIso8601String(),
      });
      await _p.setStringList(_kBookmarks, list.map(jsonEncode).toList());
    }
  }

  static Future<void> removeBookmark(String url) async {
    final list = getBookmarks()..removeWhere((b) => b['url'] == url);
    await _p.setStringList(_kBookmarks, list.map(jsonEncode).toList());
  }

  static Future<void> clearBookmarks() async => _p.remove(_kBookmarks);

  // ═══════════════════════════════════════════════════════════════════════════
  // DOWNLOADS
  // ═══════════════════════════════════════════════════════════════════════════
  static List<Map<String, dynamic>> getDownloads() {
    return (_p.getStringList(_kDownloads) ?? [])
        .map((s) {
          try { return jsonDecode(s) as Map<String, dynamic>; }
          catch (_) { return <String, dynamic>{}; }
        })
        .where((m) => m.isNotEmpty)
        .toList();
  }

  static Future<void> addDownload(Map<String, dynamic> item) async {
    final list = getDownloads();
    list.insert(0, item);
    await _p.setStringList(_kDownloads, list.take(100).map(jsonEncode).toList());
  }

  static Future<void> clearDownloads() async => _p.remove(_kDownloads);

  // ═══════════════════════════════════════════════════════════════════════════
  // NOVA X BUSINESS (max 2 per user) — now with search-count tracking
  // ═══════════════════════════════════════════════════════════════════════════
  static List<Map<String, dynamic>> getAllBusinesses() {
    return (_p.getStringList(_kBusinesses) ?? [])
        .map((s) {
          try { return jsonDecode(s) as Map<String, dynamic>; }
          catch (_) { return <String, dynamic>{}; }
        })
        .where((m) => m.isNotEmpty)
        .toList();
  }

  static List<Map<String, dynamic>> getUserBusinesses(String ownerEmail) =>
      getAllBusinesses().where((b) => b['owner'] == ownerEmail).toList();

  /// Returns false if user already has 2 businesses
  static Future<bool> addBusiness(Map<String, dynamic> biz) async {
    final all = getAllBusinesses();
    final userCount = all.where((b) => b['owner'] == biz['owner']).length;
    if (userCount >= 2) return false;

    biz['id']          = DateTime.now().millisecondsSinceEpoch.toString();
    biz['createdAt']   = DateTime.now().toIso8601String();
    biz['searchCount'] = 0;
    all.insert(0, biz);
    await _p.setStringList(_kBusinesses, all.map(jsonEncode).toList());
    return true;
  }

  static Future<void> deleteBusiness(String id) async {
    final all = getAllBusinesses()..removeWhere((b) => b['id'] == id);
    await _p.setStringList(_kBusinesses, all.map(jsonEncode).toList());
  }

  static Future<void> clearAllBusinesses() async => _p.remove(_kBusinesses);

  /// Returns first business whose name contains [query] (case-insensitive)
  /// AND increments its search counter so the directory ranks it higher.
  static Map<String, dynamic>? searchBusiness(String query) {
    final q = query.toLowerCase().trim();
    if (q.isEmpty) return null;
    final all = getAllBusinesses();
    Map<String, dynamic>? match;
    try {
      match = all.firstWhere(
        (b) => (b['name'] as String? ?? '').toLowerCase().contains(q),
      );
    } catch (_) {
      return null;
    }

    // Fire-and-forget: bump the counter and re-save
    _bumpBusinessSearchCount(match['id'] as String);
    return match;
  }

  /// Sync persistence of search-count increment (no await on caller side)
  static void _bumpBusinessSearchCount(String id) {
    final all = getAllBusinesses();
    final idx = all.indexWhere((b) => b['id'] == id);
    if (idx < 0) return;
    final current = (all[idx]['searchCount'] as int?) ?? 0;
    all[idx]['searchCount'] = current + 1;
    _p.setStringList(_kBusinesses, all.map(jsonEncode).toList());
  }

  /// Returns all businesses ranked by search count (descending)
  /// — used by the Business directory to show "trending" first.
  static List<Map<String, dynamic>> getRankedBusinesses() {
    final all = getAllBusinesses();
    all.sort((a, b) {
      final ac = (a['searchCount'] as int?) ?? 0;
      final bc = (b['searchCount'] as int?) ?? 0;
      return bc.compareTo(ac);
    });
    return all;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CLEAR ALL (keeps businesses, speed dial, background, search engine pref)
  // ═══════════════════════════════════════════════════════════════════════════
  static Future<void> clearAll() async {
    await clearSearchHistory();
    await clearHistory();
    await clearBookmarks();
    await clearDownloads();
    await clearProfileImage();
    await _p.remove(_kProfile);
  }

  // ── Stats helpers ──────────────────────────────────────────────────────────
  static int get bookmarkCount => getBookmarks().length;
  static int get historyCount  => getHistory().length;
  static int get downloadCount => getDownloads().length;
}
