// lib/core/database/local_db.dart
//
// NOVA X local persistence layer — SharedPreferences-backed
// v2.1 additions:
//   • Profile image path storage
//   • NOVA X Business CRUD (max 2 per user)
//   • Business search helper
//   • Search engine preference

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class LocalDB {
  static late SharedPreferences _p;

  // ── Keys ───────────────────────────────────────────────────────────────────
  static const _kProfile       = 'nx_profile';
  static const _kProfileImg    = 'nx_profile_image';
  static const _kSearch        = 'nx_search_history';
  static const _kHistory       = 'nx_history';
  static const _kBookmarks     = 'nx_bookmarks';
  static const _kDownloads     = 'nx_downloads';
  static const _kBusinesses    = 'nx_businesses';
  static const _kSearchEngine  = 'nx_search_engine';

  // ── Init ── called from main.dart as `await LocalDB.initialize()` ──────────
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

  // ── Profile image ──────────────────────────────────────────────────────────
  static String? getProfileImagePath() => _p.getString(_kProfileImg);

  static Future<void> saveProfileImagePath(String path) async =>
      _p.setString(_kProfileImg, path);

  static Future<void> clearProfileImage() async => _p.remove(_kProfileImg);

  // ═══════════════════════════════════════════════════════════════════════════
  // SEARCH ENGINE PREFERENCE
  // ═══════════════════════════════════════════════════════════════════════════
  /// Returns stored engine key: 'google' | 'bing' | 'duckduckgo' | 'yahoo'
  static String getSearchEngine() =>
      _p.getString(_kSearchEngine) ?? 'google';

  static Future<void> setSearchEngine(String engine) async =>
      _p.setString(_kSearchEngine, engine);

  // ═══════════════════════════════════════════════════════════════════════════
  // SEARCH HISTORY
  // ═══════════════════════════════════════════════════════════════════════════
  static List<String> getSearchHistory() =>
      _p.getStringList(_kSearch) ?? [];

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

  /// Builds the correct search URL using the stored search engine.
  /// Passes direct URLs through unchanged; bare domain names get https://.
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
          try {
            return jsonDecode(s) as Map<String, dynamic>;
          } catch (_) {
            return <String, dynamic>{};
          }
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
    await _p.setStringList(
        _kHistory, list.take(200).map(jsonEncode).toList());
  }

  static Future<void> clearHistory() async => _p.remove(_kHistory);

  // ═══════════════════════════════════════════════════════════════════════════
  // BOOKMARKS
  // ═══════════════════════════════════════════════════════════════════════════
  static List<Map<String, dynamic>> getBookmarks() {
    return (_p.getStringList(_kBookmarks) ?? [])
        .map((s) {
          try {
            return jsonDecode(s) as Map<String, dynamic>;
          } catch (_) {
            return <String, dynamic>{};
          }
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
          try {
            return jsonDecode(s) as Map<String, dynamic>;
          } catch (_) {
            return <String, dynamic>{};
          }
        })
        .where((m) => m.isNotEmpty)
        .toList();
  }

  static Future<void> addDownload(Map<String, dynamic> item) async {
    final list = getDownloads();
    list.insert(0, item);
    await _p.setStringList(
        _kDownloads, list.take(100).map(jsonEncode).toList());
  }

  static Future<void> clearDownloads() async => _p.remove(_kDownloads);

  // ═══════════════════════════════════════════════════════════════════════════
  // NOVA X BUSINESS  (max 2 per user)
  // ═══════════════════════════════════════════════════════════════════════════

  /// All businesses across all users
  static List<Map<String, dynamic>> getAllBusinesses() {
    return (_p.getStringList(_kBusinesses) ?? [])
        .map((s) {
          try {
            return jsonDecode(s) as Map<String, dynamic>;
          } catch (_) {
            return <String, dynamic>{};
          }
        })
        .where((m) => m.isNotEmpty)
        .toList();
  }

  /// Businesses belonging to [ownerEmail]
  static List<Map<String, dynamic>> getUserBusinesses(String ownerEmail) =>
      getAllBusinesses()
          .where((b) => b['owner'] == ownerEmail)
          .toList();

  /// Returns false if user already has 2 businesses
  static Future<bool> addBusiness(Map<String, dynamic> biz) async {
    final all = getAllBusinesses();
    final userCount =
        all.where((b) => b['owner'] == biz['owner']).length;
    if (userCount >= 2) return false;

    biz['id']        = DateTime.now().millisecondsSinceEpoch.toString();
    biz['createdAt'] = DateTime.now().toIso8601String();
    all.insert(0, biz);
    await _p.setStringList(_kBusinesses, all.map(jsonEncode).toList());
    return true;
  }

  static Future<void> deleteBusiness(String id) async {
    final all = getAllBusinesses()
      ..removeWhere((b) => b['id'] == id);
    await _p.setStringList(_kBusinesses, all.map(jsonEncode).toList());
  }

  static Future<void> clearAllBusinesses() async =>
      _p.remove(_kBusinesses);

  /// Returns first business whose name contains [query] (case-insensitive)
  static Map<String, dynamic>? searchBusiness(String query) {
    final q = query.toLowerCase().trim();
    if (q.isEmpty) return null;
    try {
      return getAllBusinesses().firstWhere(
        (b) => (b['name'] as String? ?? '').toLowerCase().contains(q),
      );
    } catch (_) {
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // CLEAR ALL
  // ═══════════════════════════════════════════════════════════════════════════
  static Future<void> clearAll() async {
    await clearSearchHistory();
    await clearHistory();
    await clearBookmarks();
    await clearDownloads();
    await clearProfileImage();
    await _p.remove(_kProfile);
    // Note: deliberately keeps businesses and search engine preference
  }

  // ── Stats helpers ──────────────────────────────────────────────────────────
  static int get bookmarkCount => getBookmarks().length;
  static int get historyCount  => getHistory().length;
  static int get downloadCount => getDownloads().length;
}
