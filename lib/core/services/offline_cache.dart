// lib/core/services/offline_cache.dart
//
// Small JSON snapshots kept on the phone with the time they were saved
// (business listings, last coin balance), so the app can show them offline
// and say "saved 2 h ago". Nothing here is uploaded.
//
// 3.11.3: the picture cache (Quick Access icons, news and business pictures)
// was removed — pictures load straight from the web again, as before 3.11.0.

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class OfflineCache {
  OfflineCache._();

  /// FNV-1a 64-bit of [s] as 16 hex characters (a short, stable storage key).
  static String keyFor(String s) {
    // 64-bit arithmetic wraps on the Dart VM, as FNV needs.
    var h = 0xcbf29ce484222325;
    const prime = 0x100000001b3;
    for (final c in utf8.encode(s)) {
      h ^= c;
      h *= prime;
    }
    final hi = (h >> 32) & 0xFFFFFFFF, lo = h & 0xFFFFFFFF;
    return hi.toRadixString(16).padLeft(8, '0') + lo.toRadixString(16).padLeft(8, '0');
  }

  // ── JSON snapshots ──────────────────────────────────────────────────────

  /// Saves [value] (anything jsonEncode accepts) under [key] with the time.
  static Future<void> putJson(String key, Object? value) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('nx_offline_$key', jsonEncode({'at': DateTime.now().millisecondsSinceEpoch, 'v': value}));
    } catch (_) {}
  }

  /// (value, savedAt) or null.
  static Future<(Object?, DateTime)?> getJson(String key) async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString('nx_offline_$key');
      if (raw == null) return null;
      final m = jsonDecode(raw);
      if (m is! Map || m['at'] is! int) return null;
      return (m['v'], DateTime.fromMillisecondsSinceEpoch(m['at'] as int));
    } catch (_) {
      return null;
    }
  }

  static Future<void> remove(String key) async {
    try {
      (await SharedPreferences.getInstance()).remove('nx_offline_$key');
    } catch (_) {}
  }

  /// "just now", "5 min ago", "3 h ago", "2 days ago".
  static String age(DateTime at) {
    final d = DateTime.now().difference(at);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours} h ago';
    return '${d.inDays} day${d.inDays == 1 ? '' : 's'} ago';
  }
}
