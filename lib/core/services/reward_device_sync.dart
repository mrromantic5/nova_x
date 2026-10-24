// lib/core/services/reward_device_sync.dart
//
// Tracked rewards (3.8.0): coins that are held only while a phone setting
// stays on.
//
//   • NOVA X is the default browser            → 50 coins
//   • NOVA assistant fully set up (100 coins): NOVA X is the digital
//     assistant + Microphone, Contacts, Music and audio, Display over other
//     apps and Battery "Unrestricted" all allowed
//
// The app reads the real settings on the phone on every launch/return and
// after the user changes one, and reports them to rewards.php
// (?action=sync-device). The server credits a reward when its setting turns
// on and takes the coins back when it turns off; this shows the result as a
// bottom toast. One phone's rewards can't be collected again by switching
// accounts (the server compares a one-way hash of the phone, never the raw ID).

import 'dart:async';

import 'package:flutter/services.dart';

import '../widgets/nova_toast.dart';
import 'api_service.dart';
import 'default_browser_service.dart';
import 'rewards_service.dart';

/// The NOVA assistant settings the 100-coin reward needs (Android side:
/// NovaBridge "setupStatus").
class NovaSetupStatus {
  const NovaSetupStatus(this.items);

  /// assistant · microphone · contacts · audio · overlay · battery → on/off.
  final Map<String, bool> items;

  static const List<String> keys = ['assistant', 'microphone', 'contacts', 'audio', 'overlay', 'battery'];

  static String label(String key) => switch (key) {
        'assistant' => 'NOVA X as digital assistant',
        'microphone' => 'Microphone',
        'contacts' => 'Contacts',
        'audio' => 'Music and audio',
        'overlay' => 'Open NOVA over other apps',
        'battery' => 'Battery: Unrestricted',
        _ => key,
      };

  bool get complete => keys.every((k) => items[k] == true);
  int get doneCount => keys.where((k) => items[k] == true).length;

  factory NovaSetupStatus.fromMap(Map<dynamic, dynamic>? m) =>
      NovaSetupStatus({for (final k in keys) k: m?[k] == true});
}

/// One change the server made (shown as a toast).
class RewardSyncEvent {
  const RewardSyncEvent(this.key, this.type, this.points, this.message);
  final String key; // default_browser · nova_setup
  final String type; // credited · deducted · other_account · paused
  final int points;
  final String message;

  factory RewardSyncEvent.fromMap(Map<dynamic, dynamic> m) => RewardSyncEvent(
        m['key'] is String ? m['key'] as String : '',
        m['type'] is String ? m['type'] as String : '',
        m['points'] is num ? (m['points'] as num).toInt() : 0,
        m['message'] is String ? m['message'] as String : '',
      );
}

class RewardDeviceSync {
  RewardDeviceSync._();

  static const MethodChannel _nova = MethodChannel('com.tlyfe.nova_x/nova');
  static Future<List<RewardSyncEvent>>? _inFlight;
  static DateTime? _lastAt;
  static Map<String, bool>? _lastSent;

  /// Changes are reported here too (the Rewards screen refreshes).
  static final StreamController<List<RewardSyncEvent>> _events = StreamController.broadcast();
  static Stream<List<RewardSyncEvent>> get events => _events.stream;

  /// The NOVA settings on this phone right now.
  static Future<NovaSetupStatus> setupStatus() async {
    try {
      final m = await _nova.invokeMethod<Object>('setupStatus');
      return NovaSetupStatus.fromMap(m is Map ? m : null);
    } catch (_) {
      return const NovaSetupStatus({});
    }
  }

  /// Reports the phone's settings. [force] skips the 15-second spacing (use
  /// it right after the user changed a setting). Safe to call often.
  static Future<List<RewardSyncEvent>> sync({bool force = false, bool notify = true}) {
    final running = _inFlight;
    if (running != null) return running;
    final last = _lastAt;
    if (!force && last != null && DateTime.now().difference(last) < const Duration(seconds: 15)) {
      return Future.value(const []);
    }
    final f = _run(notify).whenComplete(() => _inFlight = null);
    _inFlight = f;
    return f;
  }

  static Future<List<RewardSyncEvent>> _run(bool notify) async {
    if (!await ApiService.isLoggedIn()) return const [];
    _lastAt = DateTime.now();
    final isDefault = await DefaultBrowserService.isDefault();
    final setup = await setupStatus();
    final states = {'default_browser': isDefault, 'nova_setup': setup.complete};
    String? device;
    try {
      device = await _nova.invokeMethod<String>('installId');
    } catch (_) {
      device = null;
    }
    final result = await RewardsService.syncDevice(states, device);
    if (!result.success) return const [];
    _lastSent = states;
    final raw = result.data['events'];
    final events = <RewardSyncEvent>[
      if (raw is List)
        for (final e in raw)
          if (e is Map) RewardSyncEvent.fromMap(e),
    ];
    if (events.isNotEmpty) {
      _events.add(events);
      if (notify) {
        for (final e in events) {
          _toast(e);
        }
      }
    }
    return events;
  }

  /// What was last reported (for tests / diagnostics).
  static Map<String, bool>? get lastSent => _lastSent;

  static void _toast(RewardSyncEvent e) {
    switch (e.type) {
      case 'credited':
        NovaToast.show(e.message, title: '+${e.points} coins', kind: NovaToastKind.reward);
      case 'deducted':
        NovaToast.show(e.message,
            title: '−${e.points} coins', kind: NovaToastKind.warning, duration: const Duration(seconds: 6));
      default:
        if (e.message.isNotEmpty) NovaToast.show(e.message, kind: NovaToastKind.info);
    }
  }
}
