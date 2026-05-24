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
      final List<String> history =
          _prefs.getStringList('browser_history') ?? [];

      final Map<String, String> item = {
        'url':       url,
        'title':     title.isNotEmpty ? title : url,
        'timestamp': DateTime.now().toIso8601String(),
      };

      history.add(jsonEncode(item));

      // Keep only the 500 most recent entries to avoid unbounded growth
      final trimmed =
          history.length > 500 ? history.sublist(history.length - 500) : history;

      await _prefs.setStringList('browser_history', trimmed);
    } catch (_) {
      // Silently ignore write failures — history is non-critical
    }
  }

  static List<Map<String, dynamic>> getHistory() {
    final List<String> raw =
        _prefs.getStringList('browser_history') ?? [];

    final List<Map<String, dynamic>> result = [];

    for (final entry in raw) {
      try {
        // FIXED: previously an uncaught FormatException from corrupted JSON
        // would crash the app on launch.  We now skip bad entries silently.
        final decoded = jsonDecode(entry);
        if (decoded is Map<String, dynamic>) {
          result.add(decoded);
        }
      } catch (_) {
        // Skip corrupted entry — do not rethrow
      }
    }

    return result.reversed.toList();
  }

  static Future<void> clearHistory() async {
    await _prefs.remove('browser_history');
  }

  // ── Auth token ───────────────────────────────────────────────────────────

  static Future<void> saveToken(String token) async {
    await _prefs.setString('auth_token', token);
  }

  static String? getToken() {
    return _prefs.getString('auth_token');
  }

  static Future<void> clearToken() async {
    await _prefs.remove('auth_token');
  }
}
