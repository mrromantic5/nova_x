// lib/features/cyber/engine/cyber_storage.dart
//
// 3.14.0: where NOVA Cyber keeps its local files on Android (rule packs,
// audit log). The app's private support folder (path_provider) instead of
// %LOCALAPPDATA% on Windows; never shared with other apps. Tests use the
// system temp folder.

import 'dart:io';

import 'package:path_provider/path_provider.dart';

class CyberStorage {
  CyberStorage._();

  static String? _base;

  /// Folder that holds `cyber/…` (set by [init]).
  static String get base => _base ?? Directory.systemTemp.path;

  static Future<void> init() async {
    if (_base != null) return;
    try {
      _base = (await getApplicationSupportDirectory()).path;
    } catch (_) {}
  }

  static String path(List<String> parts) => [base, 'cyber', ...parts].join(Platform.pathSeparator);
}
