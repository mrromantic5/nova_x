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
        'url':       url,
        'title':     title.isNotEmpty ? title : url,
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
        final decoded = jsonDecode(e);
        if (decoded is Map<String, dynamic>) result.add(decoded);
      } catch (_) {}
    }
    return result.reversed.toList();
  }

  static Future<void> clearHistory() async {
    await _prefs.remove('browser_history');
  }

  // ── Bookmarks ─────────────────────────────────────────────────────────────

  static Future<void> addBookmark(String url, String title) async {
    try {
      final list = _prefs.getStringList('bookmarks') ?? [];
      // Avoid duplicates
      final alreadyExists = list.any((b) {
        try { return (jsonDecode(b) as Map)['url'] == url; }
        catch (_) { return false; }
      });
      if (alreadyExists) return;
      list.add(jsonEncode({
        'url':       url,
        'title':     title.isNotEmpty ? title : url,
        'timestamp': DateTime.now().toIso8601String(),
      }));
      await _prefs.setStringList('bookmarks', list);
    } catch (_) {}
  }

  static Future<void> removeBookmark(String url) async {
    try {
      final list = _prefs.getStringList('bookmarks') ?? [];
      list.removeWhere((b) {
        try { return (jsonDecode(b) as Map)['url'] == url; }
        catch (_) { return false; }
      });
      await _prefs.setStringList('bookmarks', list);
    } catch (_) {}
  }

  static List<Map<String, dynamic>> getBookmarks() {
    final raw = _prefs.getStringList('bookmarks') ?? [];
    final result = <Map<String, dynamic>>[];
    for (final e in raw) {
      try {
        final decoded = jsonDecode(e);
        if (decoded is Map<String, dynamic>) result.add(decoded);
      } catch (_) {}
    }
    return result.reversed.toList();
  }

  static bool isBookmarked(String url) {
    final list = _prefs.getStringList('bookmarks') ?? [];
    return list.any((b) {
      try { return (jsonDecode(b) as Map)['url'] == url; }
      catch (_) { return false; }
    });
  }

  static Future<void> clearBookmarks() async {
    await _prefs.remove('bookmarks');
  }

  // ── Settings ──────────────────────────────────────────────────────────────

  static Future<void> setSearchEngine(String engine) async {
    await _prefs.setString('search_engine', engine);
  }

  static String getSearchEngine() {
    return _prefs.getString('search_engine') ?? 'google';
  }

  static String buildSearchUrl(String query) {
    final q = Uri.encodeComponent(query);
    switch (getSearchEngine()) {
      case 'bing':        return 'https://www.bing.com/search?q=$q';
      case 'duckduckgo':  return 'https://duckduckgo.com/?q=$q';
      case 'yahoo':       return 'https://search.yahoo.com/search?p=$q';
      default:            return 'https://www.google.com/search?q=$q';
    }
  }

  // ── Auth token ────────────────────────────────────────────────────────────

  static Future<void> saveToken(String token) async {
    await _prefs.setString('auth_token', token);
  }

  static String? getToken() => _prefs.getString('auth_token');

  static Future<void> clearToken() async {
    await _prefs.remove('auth_token');
  }
}
