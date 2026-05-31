// lib/core/services/default_browser_service.dart
//
// Bridges to the native default-browser APIs (RoleManager on Android 10+,
// default-apps settings on older). Also surfaces incoming http(s) links that
// launched the app, and awards the one-time 5-point reward when NOVA X
// actually becomes the default browser.

import 'package:flutter/services.dart';
import 'rewards_service.dart';

class DefaultBrowserService {
  static const _ch = MethodChannel('com.example.nova_x/default_browser');

  /// Callback the app sets to open a URL that arrived while running.
  static void Function(String url)? onIncomingUrl;
  static bool _handlerSet = false;

  static void _ensureHandler() {
    if (_handlerSet) return;
    _handlerSet = true;
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'onNewUrl' && call.arguments is String) {
        onIncomingUrl?.call(call.arguments as String);
      }
      return null;
    });
  }

  static Future<bool> isDefault() async {
    try {
      return (await _ch.invokeMethod<bool>('isDefault')) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Opens the system dialog to set NOVA X as the default browser.
  static Future<void> request() async {
    try {
      await _ch.invokeMethod('request');
    } catch (_) {/* settings unavailable */}
  }

  /// URL that launched the app from another app (one-shot), or null.
  static Future<String?> initialUrl() async {
    _ensureHandler();
    try {
      return await _ch.invokeMethod<String>('getInitialUrl');
    } catch (_) {
      return null;
    }
  }

  /// If NOVA X is now the default browser, claim the one-time 5-point reward.
  static Future<bool> checkAndAward() async {
    final def = await isDefault();
    if (def) {
      // Server enforces once-ever; safe to call repeatedly.
      RewardsService.earn(RewardTaskKey.defaultBrowser);
    }
    return def;
  }
}
