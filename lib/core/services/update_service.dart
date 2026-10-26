// lib/core/services/update_service.dart
//
// NOVA X — "Update available" popup (3.9.0).
//
// HOW TO RELEASE AN UPDATE
//   1. Publish the new version on Google Play (versionCode higher than now).
//   2. Admin dashboard → App Updates → New release: version, build number
//      (the versionCode), message, what's new, optional "force update".
//   That's it — every older app shows the popup on its next launch.
//
// Behaviour
//   • Shown once per app launch while a newer build is published.
//   • ✕ or "Maybe later" closes it until the app is opened again.
//   • "Update now" opens NOVA X on Google Play.
//   • A forced update can't be dismissed.
//   • The installed version comes from Android (never a hard-coded number).
//   • Fallback: the old version.json on the server, if the dashboard has no
//     release yet.

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../widgets/update_dialog.dart';
import 'app_info.dart';
import 'platform_api.dart';

class UpdateService {
  UpdateService._();

  static const String _versionUrl = 'https://api.browser.t-lyfe.com.ng/version.json';

  /// Once per launch (cleared when the process starts again).
  static bool _shownThisLaunch = false;
  static bool _checking = false;

  static Future<void> checkForUpdate(BuildContext context) async {
    if (_shownThisLaunch || _checking) return;
    _checking = true;
    try {
      // Let the home screen settle first.
      await Future<void>.delayed(const Duration(seconds: 2));
      await AppInfo.load();
      final release = await PlatformApi.latestRelease(AppInfo.build) ?? await _fromVersionJson();
      if (release == null || !context.mounted || _shownThisLaunch) return;
      _shownThisLaunch = true;
      await showDialog<void>(
        context: context,
        barrierDismissible: !release.forceUpdate,
        barrierColor: Colors.black.withOpacity(0.78),
        builder: (_) => UpdateDialog(
          currentVersion: AppInfo.version,
          release: release,
        ),
      );
    } catch (_) {
      // Never crash the app over an update check.
    } finally {
      _checking = false;
    }
  }

  /// Old mechanism: version.json { version, whats_new, play_store_url, force_update }.
  static Future<AppRelease?> _fromVersionJson() async {
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
      ));
      final r = await dio.get<Object>(_versionUrl);
      Object? data = r.data;
      if (data is String) data = jsonDecode(data);
      if (data is! Map) return null;
      final remote = '${data['version'] ?? ''}';
      if (!isNewerVersion(remote, AppInfo.version)) return null;
      return AppRelease(
        version: remote,
        build: AppInfo.build + 1,
        title: 'A new version of NOVA X is ready',
        message: '',
        whatsNew: '${data['whats_new'] ?? ''}'
            .split('\n')
            .map((l) => l.replaceFirst(RegExp(r'^\s*[-•*]\s*'), '').trim())
            .where((l) => l.isNotEmpty)
            .take(8)
            .toList(),
        forceUpdate: data['force_update'] == true,
        playUrl: PlatformApi.playStoreUrl,
      );
    } catch (_) {
      return null;
    }
  }

  /// "3.10.0" is newer than "3.9.1".
  static bool isNewerVersion(String remote, String installed) {
    List<int> parts(String v) {
      final p = v.split('+').first.split('.').map((x) => int.tryParse(x.trim()) ?? -1).toList();
      while (p.length < 3) {
        p.add(0);
      }
      return p;
    }

    try {
      final r = parts(remote), i = parts(installed);
      if (r.contains(-1) || i.contains(-1)) return false;
      for (var k = 0; k < 3; k++) {
        if (r[k] > i[k]) return true;
        if (r[k] < i[k]) return false;
      }
    } catch (_) {}
    return false;
  }
}
