// lib/features/playback/playback_quota.dart
//
// AI Playback (3.12.0): 10 plays per 24 hours on the free plan, unlimited
// with NOVA X Premium. A play is counted when a new conversation is created;
// replaying the same one doesn't count again.

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../core/services/rewards_entitlements.dart';

class PlaybackQuota {
  PlaybackQuota._();

  static const int freeLimit = 10;
  static const Duration window = Duration(hours: 24);
  static const _key = 'nx_playback_uses';

  /// For tests.
  static bool Function() isPremium = () => RewardsEntitlements.isPremium;

  static Future<List<int>> _uses() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_key);
      final list = raw == null ? const [] : (jsonDecode(raw) as List);
      final from = DateTime.now().subtract(window).millisecondsSinceEpoch;
      return list.whereType<num>().map((n) => n.toInt()).where((t) => t > from).toList();
    } catch (_) {
      return [];
    }
  }

  /// Free plays left (null = unlimited, Premium).
  static Future<int?> left() async {
    if (isPremium()) return null;
    final n = freeLimit - (await _uses()).length;
    return n < 0 ? 0 : n;
  }

  /// When the oldest counted play stops counting (free plan, limit reached).
  static Future<DateTime?> nextFreeAt() async {
    final uses = await _uses();
    if (uses.length < freeLimit) return null;
    uses.sort();
    return DateTime.fromMillisecondsSinceEpoch(uses.first).add(window);
  }

  static Future<void> recordUse() async {
    if (isPremium()) return;
    try {
      final uses = await _uses()..add(DateTime.now().millisecondsSinceEpoch);
      await (await SharedPreferences.getInstance()).setString(_key, jsonEncode(uses));
    } catch (_) {}
  }
}
