// lib/core/services/business_badge_service.dart
//
// Tracks which businesses the user has already seen so the Business
// nav icon can show a badge count of NEW (not-yet-seen) businesses.
//
// Mirrors the AdvertService "read ids" pattern, but with a first-run
// baseline: on a brand-new install we mark every existing business as
// seen and show 0, so the badge only appears for businesses added AFTER
// the user's first launch / after they last opened the Business page.

import 'package:shared_preferences/shared_preferences.dart';

class BusinessBadgeService {
  static const _kSeenIds = 'nx_business_seen_ids';

  static SharedPreferences? _prefs;
  static Future<void> init() async =>
      _prefs ??= await SharedPreferences.getInstance();

  // ── Count of businesses the user hasn't seen yet ──────────────────────────
  // `businesses` is the list returned by ApiService.getBusinesses()
  // (each item is a Map with an int 'id').
  static int unseenCount(List<Map<String, dynamic>> businesses) {
    final stored = _prefs?.getStringList(_kSeenIds);

    // First run ever → establish baseline, show nothing.
    if (stored == null) {
      _saveSeen(businesses);
      return 0;
    }

    final seen = stored.map((s) => int.tryParse(s) ?? -1).toSet();
    return businesses.where((b) => !seen.contains(_idOf(b))).length;
  }

  // ── Mark every current business as seen → clears the badge ────────────────
  static Future<void> markAllSeen(List<Map<String, dynamic>> businesses) async {
    await _saveSeen(businesses);
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  static Future<void> _saveSeen(List<Map<String, dynamic>> businesses) async {
    final ids = businesses
        .map((b) => _idOf(b).toString())
        .where((s) => s != '-1')
        .toList();
    await _prefs?.setStringList(_kSeenIds, ids);
  }

  static int _idOf(Map<String, dynamic> b) {
    final raw = b['id'];
    if (raw is int) return raw;
    return int.tryParse(raw.toString()) ?? -1;
  }
}
