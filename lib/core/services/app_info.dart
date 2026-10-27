// lib/core/services/app_info.dart
//
// 3.9.0 — the installed version (from Android, so it can never be out of
// date) and an anonymous install id for support / analytics.

import 'package:flutter/services.dart';

class AppInfo {
  AppInfo._();

  /// Used when Android can't be asked (tests, older native build).
  /// Keep in step with pubspec.yaml.
  static const String fallbackVersion = '3.9.1';
  static const int fallbackBuild = 18;

  static const MethodChannel _ch = MethodChannel('com.tlyfe.nova_x/nova');

  static String _version = fallbackVersion;
  static int _build = fallbackBuild;
  static String? _installId;
  static bool _loaded = false;

  static String get version => _version;
  static int get build => _build;

  /// SHA-256 of the Android id (never the raw id), or null.
  static String? get installId => _installId;

  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final m = await _ch.invokeMapMethod<String, dynamic>('appVersion');
      final v = m?['version'];
      final b = m?['build'];
      if (v is String && v.isNotEmpty) _version = v;
      if (b is num && b > 0) _build = b.toInt();
    } catch (_) {}
    try {
      final id = await _ch.invokeMethod<String>('installId');
      if (id != null && RegExp(r'^[a-f0-9]{64}$').hasMatch(id)) _installId = id;
    } catch (_) {}
  }

  /// "NOVA X 3.9.0 (17) · Android"
  static String get label => 'NOVA X $_version ($_build) · Android';
}
