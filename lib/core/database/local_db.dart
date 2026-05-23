import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class LocalDB {
  static late SharedPreferences _prefs;

  static Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
  }

  static Future<void> saveHistoryItem(String url, String title) async {
    List<String> history = _prefs.getStringList('browser_history') ?? [];
    Map<String, String> item = {
      'url': url,
      'title': title,
      'timestamp': DateTime.now().toIso8601String()
    };
    history.add(jsonEncode(item));
    await _prefs.setStringList('browser_history', history);
  }

  static List<Map<String, dynamic>> getHistory() {
    List<String> history = _prefs.getStringList('browser_history') ?? [];
    return history.map((e) => jsonDecode(e) as Map<String, dynamic>).toList().reversed.toList();
  }

  static Future<void> saveToken(String token) async {
    await _prefs.setString('auth_token', token);
  }

  static String? getToken() {
    return _prefs.getString('auth_token');
  }
}
