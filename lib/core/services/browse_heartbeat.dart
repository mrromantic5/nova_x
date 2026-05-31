// lib/core/services/browse_heartbeat.dart
//
// Pings the server's browse-time accumulator every 60s while the app is open.
// The server only counts beats >= 55s apart, so this honestly measures ~real
// browsing minutes toward the "browse 10 minutes" task. Safe to start once.

import 'dart:async';
import 'api_service.dart';
import 'rewards_service.dart';

class BrowseHeartbeat {
  static Timer? _timer;

  static bool get isRunning => _timer != null;

  static void start() {
    if (_timer != null) return;
    _beat(); // first beat right away
    _timer = Timer.periodic(const Duration(seconds: 60), (_) => _beat());
  }

  static void stop() {
    _timer?.cancel();
    _timer = null;
  }

  static Future<void> _beat() async {
    try {
      if (!await ApiService.isLoggedIn()) return;
      await RewardsService.heartbeat();
    } catch (_) {/* silent — never disrupt browsing */}
  }
}
