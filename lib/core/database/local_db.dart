import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class LocalDB {
  static late SharedPreferences _prefs;

  static Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // ── History ──────────────────────────────────────────────────────────────
  static Future<void> saveHistoryItem(String url, String title) async {
    try {
      final list = _prefs.getStringList('browser_history') ?? [];
      final item = jsonEncode({
        'url': url, 'title': title.isNotEmpty ? title : url,
        'timestamp': DateTime.now().toIso8601String(),
      });
      list.add(item);
      final trimmed = list.length > 500 ? list.sublist(list.length - 500) : list;
      await _prefs.setStringList('browser_history', trimmed);
    } catch (_) {}
  }

  static List<Map<String, dynamic>> getHistory() {
    final raw = _prefs.getStringList('browser_history') ?? [];
    final result = <Map<String, dynamic>>[];
    for (final e in raw) {
      try {
        final d = jsonDecode(e);
        if (d is Map<String, dynamic>) result.add(d);
      } catch (_) {}
    }
    return result.reversed.toList();
  }

  static Future<void> clearHistory() async => _prefs.remove('browser_history');

  // ── Bookmarks ─────────────────────────────────────────────────────────────
  static Future<void> addBookmark(String url, String title) async {
    try {
      final list = _prefs.getStringList('bookmarks') ?? [];
      final exists = list.any((b) {
        try { return (jsonDecode(b) as Map)['url'] == url; } catch (_) { return false; }
      });
      if (exists) return;
      list.add(jsonEncode({'url': url, 'title': title.isNotEmpty ? title : url,
          'timestamp': DateTime.now().toIso8601String()}));
      await _prefs.setStringList('bookmarks', list);
    } catch (_) {}
  }

  static Future<void> removeBookmark(String url) async {
    try {
      final list = _prefs.getStringList('bookmarks') ?? [];
      list.removeWhere((b) {
        try { return (jsonDecode(b) as Map)['url'] == url; } catch (_) { return false; }
      });
      await _prefs.setStringList('bookmarks', list);
    } catch (_) {}
  }

  static List<Map<String, dynamic>> getBookmarks() {
    final raw = _prefs.getStringList('bookmarks') ?? [];
    final result = <Map<String, dynamic>>[];
    for (final e in raw) {
      try {
        final d = jsonDecode(e);
        if (d is Map<String, dynamic>) result.add(d);
      } catch (_) {}
    }
    return result.reversed.toList();
  }

  static bool isBookmarked(String url) {
    final list = _prefs.getStringList('bookmarks') ?? [];
    return list.any((b) {
      try { return (jsonDecode(b) as Map)['url'] == url; } catch (_) { return false; }
    });
  }

  static Future<void> clearBookmarks() async => _prefs.remove('bookmarks');

  // ── Search History ─────────────────────────────────────────────────────────
  static Future<void> addSearchQuery(String query) async {
    if (query.trim().isEmpty) return;
    final list = _prefs.getStringList('search_history') ?? [];
    list.remove(query); // remove duplicate
    list.insert(0, query);
    await _prefs.setStringList('search_history', list.take(30).toList());
  }

  static List<String> getSearchHistory() =>
      _prefs.getStringList('search_history') ?? [];

  static Future<void> clearSearchHistory() async =>
      _prefs.remove('search_history');

  static Future<void> removeSearchQuery(String query) async {
    final list = _prefs.getStringList('search_history') ?? [];
    list.remove(query);
    await _prefs.setStringList('search_history', list);
  }

  // ── User Profile ──────────────────────────────────────────────────────────
  static Future<void> saveProfile(Map<String, dynamic> profile) async {
    await _prefs.setString('user_profile', jsonEncode(profile));
  }

  static Map<String, dynamic> getProfile() {
    final raw = _prefs.getString('user_profile');
    if (raw == null) return {};
    try { return jsonDecode(raw) as Map<String, dynamic>; } catch (_) { return {}; }
  }

  static Future<void> clearProfile() async => _prefs.remove('user_profile');

  // ── Downloads ─────────────────────────────────────────────────────────────
  static Future<void> addDownload(Map<String, dynamic> download) async {
    try {
      final list = _prefs.getStringList('downloads') ?? [];
      list.insert(0, jsonEncode(download));
      await _prefs.setStringList('downloads', list.take(100).toList());
    } catch (_) {}
  }

  static List<Map<String, dynamic>> getDownloads() {
    final raw = _prefs.getStringList('downloads') ?? [];
    final result = <Map<String, dynamic>>[];
    for (final e in raw) {
      try {
        final d = jsonDecode(e);
        if (d is Map<String, dynamic>) result.add(d);
      } catch (_) {}
    }
    return result;
  }

  static Future<void> clearDownloads() async => _prefs.remove('downloads');

  // ── Settings ──────────────────────────────────────────────────────────────
  static Future<void> setSearchEngine(String engine) async =>
      _prefs.setString('search_engine', engine);

  static String getSearchEngine() =>
      _prefs.getString('search_engine') ?? 'google';

  static String buildSearchUrl(String query) {
    final q = Uri.encodeComponent(query);
    switch (getSearchEngine()) {
      case 'bing':        return 'https://www.bing.com/search?q=$q';
      case 'duckduckgo':  return 'https://duckduckgo.com/?q=$q';
      case 'yahoo':       return 'https://search.yahoo.com/search?p=$q';
      default:            return 'https://www.google.com/search?q=$q';
    }
  }

  // Auth
  static Future<void> saveToken(String token) async =>
      _prefs.setString('auth_token', token);
  static String? getToken() => _prefs.getString('auth_token');
  static Future<void> clearToken() async => _prefs.remove('auth_token');
}
