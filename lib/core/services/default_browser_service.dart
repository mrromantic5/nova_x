// lib/core/services/default_browser_service.dart
//
// Bridges to the native default-browser APIs (RoleManager on Android 10+,
// Default-apps settings on older). Also surfaces incoming http(s) links that
// launched the app, and awards the one-time 5-point reward when NOVA X
// actually becomes the default browser.
//
// Native side: MainActivity.kt (com.tlyfe.nova_x/default_browser channel)
//
// Method calls Flutter → Native:
//   "isDefault"      → bool
//   "request"        → void  (opens system dialog; result arrives via onRoleResult)
//   "getInitialUrl"  → String?
//
// Method calls Native → Flutter:
//   "onNewUrl"    (String url) — link opened while app is running
//   "onRoleResult" (bool granted) — user dismissed the Android role dialog

import 'package:flutter/services.dart';
import 'rewards_service.dart';

class DefaultBrowserService {
  static const _ch = MethodChannel('com.tlyfe.nova_x/default_browser');

  // ── Callbacks ──────────────────────────────────────────────────────────────

  /// Called when another app opens a URL and NOVA X handles it while running.
  static void Function(String url)? onIncomingUrl;

  /// Called after the Android role-request dialog closes (Android 10+ only).
  /// `granted` is true if the user chose NOVA X.
  static void Function(bool granted)? onRoleResult;

  static bool _handlerSet = false;

  // ── Internal ───────────────────────────────────────────────────────────────

  static void _ensureHandler() {
    if (_handlerSet) return;
    _handlerSet = true;
    _ch.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onNewUrl':
          if (call.arguments is String) {
            onIncomingUrl?.call(call.arguments as String);
          }
          break;
        case 'onRoleResult':
          final granted = call.arguments == true;
          onRoleResult?.call(granted);
          if (granted) {
            // User just granted the role — claim the one-time reward.
            await RewardsService.earn(RewardTaskKey.defaultBrowser);
          }
          break;
      }
      return null;
    });
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Returns true if NOVA X is currently the default browser.
  static Future<bool> isDefault() async {
    _ensureHandler();
    try {
      return (await _ch.invokeMethod<bool>('isDefault')) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Opens the system dialog (Android 10+) or Default Apps settings (older)
  /// to set NOVA X as the default browser.
  /// On Android 10+, the result arrives via the [onRoleResult] callback.
  static Future<void> request() async {
    _ensureHandler();
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
      await RewardsService.earn(RewardTaskKey.defaultBrowser);
    }
    return def;
  }
}
