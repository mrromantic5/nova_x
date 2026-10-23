// lib/core/services/default_browser_service.dart
//
// Bridge to MainActivity's default-browser channel:
//   • isDefault()   — is NOVA X the system default browser right now?
//   • request()     — shows the system "Set as default" dialog (Android 10+)
//                     or opens Default apps settings (Android 7–9). On 10+ the
//                     Future completes only after the user answers the dialog.
//   • initialUrl()  — one-shot link that launched / was waiting for the app.
//   • onIncomingUrl — callback for links that arrive while the app is open.
//   • initialFeature() / onOpenFeature — a NOVA X page the floating NOVA
//                     assistant asked to open (same one-shot hand-over).
//
// Also awards the one-time 5-point reward when NOVA X becomes the default.

import 'dart:async';
import 'package:flutter/services.dart';
import 'rewards_service.dart';

class DefaultBrowserService {
  static const _ch = MethodChannel('com.tlyfe.nova_x/default_browser');

  /// Set by the home screen while it is mounted. Links that arrive while this
  /// is null are kept natively and returned by [initialUrl] later.
  static void Function(String url)? onIncomingUrl;

  /// Set by the home screen while it is mounted: opens a NOVA X page by id.
  /// Returns false when the id is unknown.
  static bool Function(String featureId)? onOpenFeature;

  static bool _handlerSet = false;
  static Future<bool>? _requestInFlight;

  /// Registers the native → Dart handler. Safe to call more than once.
  static void init() {
    if (_handlerSet) return;
    _handlerSet = true;
    _ch.setMethodCallHandler(_onNativeCall);
  }

  static Future<dynamic> _onNativeCall(MethodCall call) async {
    if (call.method == 'onNewUrl' && call.arguments is String) {
      final cb = onIncomingUrl;
      if (cb == null) return false; // native side keeps it for initialUrl()
      cb(call.arguments as String);
      return true;
    }
    if (call.method == 'onOpenFeature' && call.arguments is String) {
      final cb = onOpenFeature;
      if (cb == null) return false; // kept natively for initialFeature()
      cb(call.arguments as String);
      return true;
    }
    return false;
  }

  static Future<bool> isDefault() async {
    try {
      return (await _ch.invokeMethod<bool>('isDefault')) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Asks the system to make NOVA X the default browser.
  /// Returns true if NOVA X is the default afterwards.
  /// Concurrent taps share a single request (no stacked dialogs).
  static Future<bool> request() {
    return _requestInFlight ??=
        _doRequest().whenComplete(() => _requestInFlight = null);
  }

  static Future<bool> _doRequest() async {
    init();
    bool granted;
    try {
      granted = (await _ch
              .invokeMethod<bool>('request')
              // Safety net: never leave a spinner hanging if the dialog
              // result is lost (e.g. "Don't keep activities" dev option).
              .timeout(const Duration(minutes: 3))) ??
          false;
    } on TimeoutException {
      granted = await isDefault();
    } catch (_) {
      granted = false;
    }
    if (granted) {
      // Server enforces once-ever; safe to call repeatedly.
      RewardsService.earn(RewardTaskKey.defaultBrowser);
    }
    return granted;
  }

  /// Opens the system Default apps screen directly.
  static Future<bool> openSettings() async {
    try {
      return (await _ch.invokeMethod<bool>('openSettings')) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Link that launched the app, or arrived before the home screen was ready.
  /// One-shot: returns null on subsequent calls.
  static Future<String?> initialUrl() async {
    init();
    try {
      return await _ch.invokeMethod<String>('getInitialUrl');
    } catch (_) {
      return null;
    }
  }

  /// NOVA X page the assistant asked to open before the home screen was
  /// ready. One-shot: returns null on subsequent calls.
  static Future<String?> initialFeature() async {
    init();
    try {
      return await _ch.invokeMethod<String>('getInitialFeature');
    } catch (_) {
      return null;
    }
  }

  /// If NOVA X is now the default browser, claim the one-time 5-point reward.
  static Future<bool> checkAndAward() async {
    final def = await isDefault();
    if (def) {
      RewardsService.earn(RewardTaskKey.defaultBrowser);
    }
    return def;
  }
}
