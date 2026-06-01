// lib/core/services/rewards_entitlements.dart
//
// Global, app-wide "gate" for premium features. Every gated screen asks
// RewardsEntitlements.isUnlocked('shield') etc. The server is the source of
// truth; this just caches the answer so gates resolve instantly without a
// network flash, and refreshes from the server on launch + after every redeem.

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'rewards_service.dart';

class RewardsEntitlements {
  static const _kCache = 'nx_entitlements_cache_v1';
  static const _kPremium = 'nx_premium_active_v1';

  // feature_key -> expiry (UTC-naive local DateTime from server)
  static final Map<String, DateTime> _expiry = {};
  static bool _loadedFromCache = false;
  static bool _premium = false;

  // ── Premium (subscription) ───────────────────────────────────────────────
  /// True when the user has an active premium subscription. Premium is a master
  /// key: it unlocks every gated feature regardless of points/trials.
  static bool get isPremium => _premium;

  static Future<void> setPremium(bool value) async {
    _premium = value;
    try {
      (await SharedPreferences.getInstance()).setBool(_kPremium, value);
    } catch (_) {}
  }

  // ── Reads (used by feature gates) ────────────────────────────────────────
  static bool isUnlocked(String featureKey) {
    if (_premium) return true;           // premium unlocks everything
    final e = _expiry[featureKey];
    return e != null && e.isAfter(DateTime.now());
  }

  static DateTime? expiryOf(String featureKey) => _expiry[featureKey];

  /// Whole days remaining (rounded up), 0 if locked/expired.
  static int daysLeft(String featureKey) {
    final e = _expiry[featureKey];
    if (e == null) return 0;
    final diff = e.difference(DateTime.now());
    if (diff.isNegative) return 0;
    return diff.inHours <= 24 ? 1 : (diff.inHours / 24).ceil();
  }

  /// "5d left" / "12h left" / "Locked"
  static String statusLabel(String featureKey) {
    final e = _expiry[featureKey];
    if (e == null || !e.isAfter(DateTime.now())) return 'Locked';
    final diff = e.difference(DateTime.now());
    if (diff.inDays >= 1) return '${diff.inDays}d left';
    if (diff.inHours >= 1) return '${diff.inHours}h left';
    return '${diff.inMinutes}m left';
  }

  // ── Lifecycle ────────────────────────────────────────────────────────────
  /// Call early (e.g. app start) for instant gating before the network returns.
  static Future<void> loadCache() async {
    if (_loadedFromCache) return;
    _loadedFromCache = true;
    try {
      final sp = await SharedPreferences.getInstance();
      _premium = sp.getBool(_kPremium) ?? false;
      final raw = sp.getString(_kCache);
      if (raw == null) return;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      _expiry.clear();
      m.forEach((k, v) {
        final dt = DateTime.tryParse(v.toString());
        if (dt != null) _expiry[k] = dt;
      });
    } catch (_) {/* ignore */}
  }

  /// Pull fresh truth from the server. Call on launch + after each redeem.
  static Future<void> refresh() async {
    final ents = await RewardsService.fetchEntitlements();
    if (ents.isEmpty) return;          // keep cache if offline
    _expiry.clear();
    ents.forEach((k, e) {
      if (e.expiresAt != null) _expiry[k] = e.expiresAt!;
    });
    await _persist();
  }

  /// Optimistically set after a successful redeem so the UI unlocks instantly.
  static Future<void> setExpiry(String featureKey, String? isoExpiry) async {
    if (isoExpiry == null) return;
    final dt = DateTime.tryParse(isoExpiry.replaceFirst(' ', 'T'));
    if (dt != null) {
      _expiry[featureKey] = dt;
      await _persist();
    }
  }

  static Future<void> _persist() async {
    try {
      final p = await SharedPreferences.getInstance();
      final m = _expiry.map((k, v) => MapEntry(k, v.toIso8601String()));
      await p.setString(_kCache, jsonEncode(m));
    } catch (_) {/* ignore */}
  }

  static void clear() {
    _expiry.clear();
  }
}
