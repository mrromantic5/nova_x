// lib/features/ai/services/nova_quota.dart
//
// Fair-use limits for NOVA AI, shared by the NOVA AI chat and the "Hey NOVA"
// assistant panel (both Flutter engines read the same stored counts):
//
//   • photo uploads (photos, screenshots, "Read my screen", "Ask NOVA about
//     this page"): 5 per 24 hours
//   • image generation (/image …): 5 per 24 hours
//
// 3.8.1: the limits reset 24 hours after the first use (3.8.0: 2 hours).
// The window starts with the first use; when it ends the count goes back to
// 0. The window maths is pure (NovaQuotaWindow) and unit-tested.
//
// 3.9.0 — plans. The paid AI service is protected by daily limits that grow
// with the plan:
//
//                       Free   AI Boost (coins, 24 h)   Premium
//   NOVA AI messages      40          80                  300
//   photo uploads          5          10                   30
//   image generations      5          10                   20
//   video generations      0           0                    3
//
// (Messages = questions that reach NOVA AI — chat, "Hey NOVA" answers, page
// summaries. Opening pages, music, speed tests and other on-phone commands
// are free and unlimited.)

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/services/rewards_entitlements.dart';
import '../../../core/services/analytics_service.dart';

enum NovaQuotaKind { upload, image, chat, video }

/// Which limits apply.
enum NovaTier { free, boost, premium }

class NovaQuotaRules {
  NovaQuotaRules._();

  /// The free photo / image limit (kept for older callers and tests).
  static const int limit = 5;
  static const Duration window = Duration(hours: 24);

  /// Highest count ever stored (any plan).
  static const int maxStored = 1000;

  static int limitFor(NovaQuotaKind kind, NovaTier plan) => switch (kind) {
        NovaQuotaKind.chat => switch (plan) { NovaTier.free => 40, NovaTier.boost => 80, NovaTier.premium => 300 },
        NovaQuotaKind.upload => switch (plan) { NovaTier.free => 5, NovaTier.boost => 10, NovaTier.premium => 30 },
        NovaQuotaKind.image => switch (plan) { NovaTier.free => 5, NovaTier.boost => 10, NovaTier.premium => 20 },
        NovaQuotaKind.video => plan == NovaTier.premium ? 3 : 0,
      };
}

/// What the user has left right now.
class NovaQuotaStatus {
  const NovaQuotaStatus({
    required this.kind,
    required this.used,
    this.resetAt,
    this.limit = NovaQuotaRules.limit,
    this.plan = NovaTier.free,
  });

  final NovaQuotaKind kind;
  final int used;

  /// When the count goes back to 0 (null when nothing was used yet).
  final DateTime? resetAt;

  final int limit;
  final NovaTier plan;

  int get remaining => _bound(limit - used, limit);
  bool get exhausted => remaining == 0;

  /// Time left until the reset (zero when already reset / never used).
  Duration leftAt(DateTime now) {
    final r = resetAt;
    if (r == null) return Duration.zero;
    final d = r.difference(now);
    return d.isNegative ? Duration.zero : d;
  }
}

/// 0…max.
int _bound(int v, [int max = NovaQuotaRules.limit]) => v < 0 ? 0 : (v > max ? max : v);

/// Pure window maths (tested).
class NovaQuotaWindow {
  NovaQuotaWindow._();

  /// (used, startMs) after an expired window is cleared.
  static (int, int) current(int used, int startMs, int nowMs) {
    if (startMs <= 0 || used <= 0) return (0, 0);
    if (nowMs < startMs) return (0, 0); // clock moved back: start over
    if (nowMs - startMs >= NovaQuotaRules.window.inMilliseconds) return (0, 0);
    return (used, startMs);
  }

  /// Uses [count] if they fit: returns the new (used, startMs), or null.
  static (int, int)? use(int used, int startMs, int nowMs, int count,
      [int limit = NovaQuotaRules.limit]) {
    final (u, s) = current(used, startMs, nowMs);
    if (count <= 0) return (u, s);
    if (u + count > limit) return null;
    return (u + count, s == 0 ? nowMs : s);
  }

  static DateTime? resetAt(int used, int startMs) => used > 0 && startMs > 0
      ? DateTime.fromMillisecondsSinceEpoch(startMs + NovaQuotaRules.window.inMilliseconds)
      : null;

  /// Stored as "used|startMs".
  static (int, int) decode(String? raw, [int max = NovaQuotaRules.limit]) {
    final parts = (raw ?? '').split('|');
    if (parts.length != 2) return (0, 0);
    final u = int.tryParse(parts[0]) ?? 0;
    final s = int.tryParse(parts[1]) ?? 0;
    return (_bound(u, max), s < 0 ? 0 : s);
  }

  static String encode(int used, int startMs) => '$used|$startMs';
}

class NovaQuota {
  NovaQuota._();

  static String _key(NovaQuotaKind k) => 'nova_quota_${k.name}';

  /// For tests.
  static DateTime Function() clock = DateTime.now;

  /// The plan whose limits apply (premium > AI Boost > free).
  static NovaTier Function() plan = _currentPlan;

  static NovaTier _currentPlan() {
    if (RewardsEntitlements.isPremium) return NovaTier.premium;
    if (RewardsEntitlements.isUnlocked('ai_boost')) return NovaTier.boost;
    return NovaTier.free;
  }

  static Future<SharedPreferences> _prefs() async {
    final p = await SharedPreferences.getInstance();
    // The other NOVA engine (chat ↔ assistant panel) may have used some.
    try {
      await p.reload();
    } catch (_) {}
    // The assistant panel runs in its own engine: make sure it knows the plan.
    try {
      await RewardsEntitlements.loadCache();
    } catch (_) {}
    return p;
  }

  static NovaQuotaStatus _status(NovaQuotaKind kind, int used, int startMs) {
    final pl = plan();
    final limit = NovaQuotaRules.limitFor(kind, pl);
    return NovaQuotaStatus(
      kind: kind,
      used: used,
      resetAt: NovaQuotaWindow.resetAt(used, startMs),
      limit: limit,
      plan: pl,
    );
  }

  static Future<NovaQuotaStatus> status(NovaQuotaKind kind) async {
    final p = await _prefs();
    final (u0, s0) = NovaQuotaWindow.decode(p.getString(_key(kind)), NovaQuotaRules.maxStored);
    final (u, s) = NovaQuotaWindow.current(u0, s0, clock().millisecondsSinceEpoch);
    return _status(kind, u, s);
  }

  /// Uses [count] (messages / photos / images). Returns null when they fit
  /// (and were counted), otherwise the status to show in the limit message.
  static Future<NovaQuotaStatus?> tryUse(NovaQuotaKind kind, [int count = 1]) async {
    final p = await _prefs();
    final (u0, s0) = NovaQuotaWindow.decode(p.getString(_key(kind)), NovaQuotaRules.maxStored);
    final now = clock().millisecondsSinceEpoch;
    final limit = NovaQuotaRules.limitFor(kind, plan());
    final next = NovaQuotaWindow.use(u0, s0, now, count, limit);
    if (next == null) {
      final (u, s) = NovaQuotaWindow.current(u0, s0, now);
      AnalyticsService.log('limit_reached', feature: kind.name, props: {'plan': plan().name});
      return _status(kind, u, s);
    }
    await p.setString(_key(kind), NovaQuotaWindow.encode(next.$1, next.$2));
    return null;
  }

  /// Gives back [count] (e.g. the generation failed, nothing was received).
  static Future<void> refund(NovaQuotaKind kind, [int count = 1]) async {
    final p = await _prefs();
    final (u0, s0) = NovaQuotaWindow.decode(p.getString(_key(kind)), NovaQuotaRules.maxStored);
    final (u, s) = NovaQuotaWindow.current(u0, s0, clock().millisecondsSinceEpoch);
    final left = _bound(u - count, NovaQuotaRules.maxStored);
    await p.setString(_key(kind), NovaQuotaWindow.encode(left, left == 0 ? 0 : s));
  }
}

/// Thrown by the NOVA AI client when today's message limit is used up.
class NovaQuotaExceeded implements Exception {
  const NovaQuotaExceeded(this.status);
  final NovaQuotaStatus status;
  @override
  String toString() => 'NovaQuotaExceeded(${status.kind.name})';
}
