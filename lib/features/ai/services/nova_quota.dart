// lib/features/ai/services/nova_quota.dart
//
// Fair-use limits for NOVA AI (3.8.0), shared by the NOVA AI chat and the
// "Hey NOVA" assistant panel (both Flutter engines read the same stored
// counts):
//
//   • photo uploads (photos, screenshots, "Read my screen", "Ask NOVA about
//     this page"): 5 per 2 hours
//   • image generation (/image …): 5 per 2 hours
//
// The 2-hour window starts with the first use; when it ends the count goes
// back to 0. The window maths is pure (NovaQuotaWindow) and unit-tested.

import 'package:shared_preferences/shared_preferences.dart';

enum NovaQuotaKind { upload, image }

class NovaQuotaRules {
  NovaQuotaRules._();
  static const int limit = 5;
  static const Duration window = Duration(hours: 2);
}

/// What the user has left right now.
class NovaQuotaStatus {
  const NovaQuotaStatus({required this.kind, required this.used, this.resetAt});

  final NovaQuotaKind kind;
  final int used;

  /// When the count goes back to 0 (null when nothing was used yet).
  final DateTime? resetAt;

  int get limit => NovaQuotaRules.limit;
  int get remaining => _bound(limit - used);
  bool get exhausted => remaining == 0;

  /// Time left until the reset (zero when already reset / never used).
  Duration leftAt(DateTime now) {
    final r = resetAt;
    if (r == null) return Duration.zero;
    final d = r.difference(now);
    return d.isNegative ? Duration.zero : d;
  }
}

/// 0…limit.
int _bound(int v) => v < 0 ? 0 : (v > NovaQuotaRules.limit ? NovaQuotaRules.limit : v);

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
  static (int, int)? use(int used, int startMs, int nowMs, int count) {
    final (u, s) = current(used, startMs, nowMs);
    if (count <= 0) return (u, s);
    if (u + count > NovaQuotaRules.limit) return null;
    return (u + count, s == 0 ? nowMs : s);
  }

  static DateTime? resetAt(int used, int startMs) => used > 0 && startMs > 0
      ? DateTime.fromMillisecondsSinceEpoch(startMs + NovaQuotaRules.window.inMilliseconds)
      : null;

  /// Stored as "used|startMs".
  static (int, int) decode(String? raw) {
    final parts = (raw ?? '').split('|');
    if (parts.length != 2) return (0, 0);
    final u = int.tryParse(parts[0]) ?? 0;
    final s = int.tryParse(parts[1]) ?? 0;
    return (_bound(u), s < 0 ? 0 : s);
  }

  static String encode(int used, int startMs) => '$used|$startMs';
}

class NovaQuota {
  NovaQuota._();

  static String _key(NovaQuotaKind k) => 'nova_quota_${k.name}';

  /// For tests.
  static DateTime Function() clock = DateTime.now;

  static Future<SharedPreferences> _prefs() async {
    final p = await SharedPreferences.getInstance();
    // The other NOVA engine (chat ↔ assistant panel) may have used some.
    try {
      await p.reload();
    } catch (_) {}
    return p;
  }

  static Future<NovaQuotaStatus> status(NovaQuotaKind kind) async {
    final p = await _prefs();
    final (u0, s0) = NovaQuotaWindow.decode(p.getString(_key(kind)));
    final (u, s) = NovaQuotaWindow.current(u0, s0, clock().millisecondsSinceEpoch);
    return NovaQuotaStatus(kind: kind, used: u, resetAt: NovaQuotaWindow.resetAt(u, s));
  }

  /// Uses [count] (photos / images). Returns null when they fit (and were
  /// counted), otherwise the status to show in the limit message.
  static Future<NovaQuotaStatus?> tryUse(NovaQuotaKind kind, [int count = 1]) async {
    final p = await _prefs();
    final (u0, s0) = NovaQuotaWindow.decode(p.getString(_key(kind)));
    final now = clock().millisecondsSinceEpoch;
    final next = NovaQuotaWindow.use(u0, s0, now, count);
    if (next == null) {
      final (u, s) = NovaQuotaWindow.current(u0, s0, now);
      return NovaQuotaStatus(kind: kind, used: u, resetAt: NovaQuotaWindow.resetAt(u, s));
    }
    await p.setString(_key(kind), NovaQuotaWindow.encode(next.$1, next.$2));
    return null;
  }

  /// Gives back [count] (e.g. the generation failed, nothing was received).
  static Future<void> refund(NovaQuotaKind kind, [int count = 1]) async {
    final p = await _prefs();
    final (u0, s0) = NovaQuotaWindow.decode(p.getString(_key(kind)));
    final (u, s) = NovaQuotaWindow.current(u0, s0, clock().millisecondsSinceEpoch);
    final left = _bound(u - count);
    await p.setString(_key(kind), NovaQuotaWindow.encode(left, left == 0 ? 0 : s));
  }
}
