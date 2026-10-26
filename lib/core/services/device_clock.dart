// lib/core/services/device_clock.dart
//
// 3.9.0 — the phone's own date, time and time zone, everywhere:
//
//   • DeviceClock.context() → {tz, offset_min} sent to NOVA AI so it answers
//     "what's the date / time" in the user's time zone (not Ghana's / UTC).
//   • DeviceClock.syncToServer() → tells the API the time zone, so greeting
//     notifications arrive at the user's local morning / afternoon / evening.
//   • ServerTime.parse() → server times are UTC; they are shown in the phone's
//     local time (before 3.9.0 they were read as if they were local).

import 'package:flutter/services.dart';

class DeviceClock {
  DeviceClock._();

  static const MethodChannel _ch = MethodChannel('com.tlyfe.nova_x/nova');

  static String? _tz;
  static int? _syncedOffset;
  static String? _syncedTz;

  /// IANA time zone of the phone ("Asia/Dubai"), when known.
  static String? get timeZoneId => _tz;

  /// Minutes ahead of UTC right now (DST included).
  static int get offsetMinutes => DateTime.now().timeZoneOffset.inMinutes;

  /// Reads the time zone from Android. Safe to call many times.
  static Future<String?> load() async {
    try {
      final m = await _ch.invokeMapMethod<String, dynamic>('deviceClock');
      final tz = m?['tz'];
      if (tz is String && tz.isNotEmpty && tz.length <= 64) _tz = tz;
    } catch (_) {
      // Older native build / tests: the offset alone still works.
    }
    return _tz;
  }

  /// Sent with every NOVA AI request.
  static Map<String, Object?> context() => {
        if (_tz != null) 'tz': _tz,
        'offset_min': offsetMinutes,
      };

  /// "+04:00"
  static String offsetLabel([int? minutes]) {
    final m = minutes ?? offsetMinutes;
    final sign = m < 0 ? '-' : '+';
    final a = m.abs();
    return '$sign${(a ~/ 60).toString().padLeft(2, '0')}:${(a % 60).toString().padLeft(2, '0')}';
  }

  /// Tells the API the phone's time zone (greetings at local time). Only
  /// sends when it changed since the last successful send in this run.
  static Future<void> syncToServer(Future<bool> Function(String? tz, int offsetMin) send) async {
    await load(); // the user may have travelled since the last time
    final off = offsetMinutes;
    if (_syncedTz == _tz && _syncedOffset == off) return;
    try {
      if (await send(_tz, off)) {
        _syncedTz = _tz;
        _syncedOffset = off;
      }
    } catch (_) {}
  }

  /// Forget the last sync (after sign-in / a new push token).
  static void resetSync() {
    _syncedTz = null;
    _syncedOffset = null;
  }
}

/// Times from the NOVA X server.
class ServerTime {
  ServerTime._();

  static final RegExp _hasZone = RegExp(r'(Z|[+-]\d\d:?\d\d)$');

  /// Parses a server time and returns it in the phone's local time.
  /// "2026-10-26 08:15:00" (no zone) is UTC; ISO times with "Z" or an offset
  /// keep their zone. Null for empty / unreadable values.
  static DateTime? parse(Object? value) {
    if (value == null) return null;
    var s = value.toString().trim();
    if (s.isEmpty || s.startsWith('0000')) return null;
    s = s.replaceFirst(' ', 'T');
    if (s.length == 10) s = '${s}T00:00:00'; // date only
    if (!_hasZone.hasMatch(s)) s = '${s}Z';
    final t = DateTime.tryParse(s);
    return t?.toLocal();
  }
}
