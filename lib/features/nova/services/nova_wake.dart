// lib/features/nova/services/nova_wake.dart
//
// "Hey NOVA" wake word — Dart side of NovaWakeService (Android).
//
// The detector runs entirely on the phone (sherpa-onnx keyword spotting).
// Dart only turns it on/off, reads its status, and tells it to step aside
// while NOVA's own screens are open (so NOVA never wakes itself).

import 'dart:async';

import 'package:flutter/services.dart';

class NovaWakeStatus {
  const NovaWakeStatus({
    this.supported = false,
    this.enabled = false,
    this.running = false,
    this.background = false,
    this.overlay = false,
    this.notifications = false,
    this.microphone = false,
    this.error,
    this.screenOff = false,
    this.batteryUnrestricted = false,
  });

  /// The detector can run on this phone (model present, CPU supported).
  final bool supported;

  /// The user turned "Hey NOVA" on.
  final bool enabled;

  /// Listening right now.
  final bool running;

  /// Android 10+: can listen while other apps are open.
  final bool background;

  /// "Display over other apps" allowed: the panel opens directly from other apps.
  final bool overlay;

  /// Notifications allowed (needed for the "tap to talk" alert).
  final bool notifications;

  final bool microphone;

  /// Last start problem: microphone · start_not_allowed · unsupported · engine_error.
  final String? error;

  /// "Listen when the screen is off" is on (off by default).
  final bool screenOff;

  /// NOVA X's battery use is "Unrestricted" (phones stop it less often).
  final bool batteryUnrestricted;

  factory NovaWakeStatus.fromMap(Map<dynamic, dynamic> m) => NovaWakeStatus(
        supported: m['supported'] == true,
        enabled: m['enabled'] == true,
        running: m['running'] == true,
        background: m['background'] == true,
        overlay: m['overlay'] == true,
        notifications: m['notifications'] == true,
        microphone: m['microphone'] == true,
        error: m['error'] is String ? m['error'] as String : null,
        screenOff: m['screenOff'] == true,
        batteryUnrestricted: m['batteryUnrestricted'] == true,
      );
}

class NovaWake {
  NovaWake._();

  static const MethodChannel _channel = MethodChannel('com.tlyfe.nova_x/nova');

  static Future<NovaWakeStatus> status() async {
    try {
      final m = await _channel.invokeMethod<Object>('wakeStatus');
      return m is Map ? NovaWakeStatus.fromMap(m) : const NovaWakeStatus();
    } catch (_) {
      return const NovaWakeStatus();
    }
  }

  /// Returns false when Android refused to start listening.
  static Future<bool> setEnabled(bool enabled) async {
    try {
      return await _channel.invokeMethod<bool>('setWakeEnabled', {'enabled': enabled}) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Pause "Hey NOVA" while [reason] is active (NOVA panel open, NOVA talking…).
  static Future<void> hold(String reason, bool held) async {
    try {
      await _channel.invokeMethod<void>('setWakeHold', {'reason': reason, 'held': held});
    } catch (_) {
      // best effort (no channel in tests)
    }
  }

  static final Map<String, Timer> _timedHolds = {};

  /// Another microphone user in NOVA X (voice search, a web page's mic) is
  /// about to start: pause "Hey NOVA" and give the listener a moment to
  /// release the microphone. Released by [resumeAfterOtherMic], or
  /// automatically after [max] in case the end is never reported.
  static Future<void> pauseForOtherMic(String reason,
      {Duration max = const Duration(seconds: 35)}) async {
    _timedHolds.remove(reason)?.cancel();
    _timedHolds[reason] = Timer(max, () {
      _timedHolds.remove(reason);
      hold(reason, false);
    });
    await hold(reason, true);
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }

  static void resumeAfterOtherMic(String reason) {
    _timedHolds.remove(reason)?.cancel();
    hold(reason, false);
  }

  /// "Listen when the screen is off": keep listening with the screen off or
  /// locked and open NOVA over the lock screen. Uses more battery.
  static Future<void> setScreenOff(bool enabled) async {
    try {
      await _channel.invokeMethod<bool>('setWakeScreenOff', {'enabled': enabled});
    } catch (_) {
      // best effort (no channel in tests)
    }
  }

  /// Android's battery-optimisation settings (to choose "Unrestricted").
  static Future<void> openBatterySettings() async {
    try {
      await _channel.invokeMethod<bool>('openBatterySettings');
    } catch (_) {
      // best effort
    }
  }

  static Future<void> openOverlaySettings() async {
    try {
      await _channel.invokeMethod<bool>('openOverlaySettings');
    } catch (_) {
      // best effort (no channel in tests)
    }
  }

  /// Why the floating NOVA window opened: 'wake' ("Hey NOVA") or 'assist'.
  static Future<String> launchReason() async {
    try {
      return await _channel.invokeMethod<String>('launchReason') ?? 'assist';
    } catch (_) {
      return 'assist';
    }
  }
}
