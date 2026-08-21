// lib/core/services/update_service.dart
//
// NOVA X — SaaS-grade App Update Service
// Fetches version.json from server, compares with installed version,
// shows premium update dialog when a new version is available.
//
// HOW TO RELEASE AN UPDATE:
//   1. Bump version in pubspec.yaml  (e.g. 3.1.1+6 → 3.1.2+7)
//   2. Update version.json on your server with the new version number
//   3. Push to GitHub → CI builds & uploads to Play Store automatically
//   4. Users see the update popup next time they open the app

import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nova_x/core/widgets/update_dialog.dart';

class UpdateService {
  // ── Hosted on your server — update version.json whenever you release ──────
  static const String _versionUrl =
      'https://c.x.t-lyfe.com.ng/nova_x/version.json';

  static const String _firstSeenKey = 'nx_update_first_seen_';

  // ── Main entry point — call from HomeScreen.initState ────────────────────
  static Future<void> checkForUpdate(BuildContext context) async {
    try {
      // Small delay so home screen renders first
      await Future.delayed(const Duration(seconds: 2));
      if (!context.mounted) return;

      final remote = await _fetchRemoteVersion();
      if (remote == null) return;

      final info = await PackageInfo.fromPlatform();
      final installedVersion = info.version;         // e.g. "3.1.0"
      final remoteVersion    = remote['version'] as String; // e.g. "3.1.1"

      if (!_isNewerVersion(remoteVersion, installedVersion)) return;

      // Track when the user first saw this update (for grace period countdown)
      final prefs = await SharedPreferences.getInstance();
      final seenKey = '$_firstSeenKey$remoteVersion';
      final firstSeen = prefs.getString(seenKey);
      if (firstSeen == null) {
        await prefs.setString(seenKey, DateTime.now().toIso8601String());
      }

      final firstSeenDate = DateTime.parse(
          prefs.getString(seenKey) ?? DateTime.now().toIso8601String());

      final graceDays    = (remote['grace_days'] as int?) ?? 5;
      final forceUpdate  = (remote['force_update'] as bool?) ?? false;
      final daysElapsed  = DateTime.now().difference(firstSeenDate).inDays;
      final daysLeft     = (graceDays - daysElapsed).clamp(0, graceDays);
      final mustUpdate   = forceUpdate && daysLeft == 0;

      if (!context.mounted) return;

      showDialog(
        context: context,
        barrierDismissible: !mustUpdate,
        barrierColor: Colors.black87,
        builder: (_) => UpdateDialog(
          currentVersion:  installedVersion,
          newVersion:      remoteVersion,
          whatsNew:        remote['whats_new'] as String? ?? '',
          playStoreUrl:    remote['play_store_url'] as String? ?? '',
          daysLeft:        daysLeft,
          graceDays:       graceDays,
          mustUpdate:      mustUpdate,
        ),
      );
    } catch (_) {
      // Silently fail — never crash the app over an update check
    }
  }

  // ── Fetch & parse version.json from server ────────────────────────────────
  static Future<Map<String, dynamic>?> _fetchRemoteVersion() async {
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
      ));
      final response = await dio.get(_versionUrl);
      if (response.statusCode == 200) {
        final data = response.data is String
            ? jsonDecode(response.data as String)
            : response.data;
        return Map<String, dynamic>.from(data as Map);
      }
    } catch (_) {}
    return null;
  }

  // ── Semantic version comparison ───────────────────────────────────────────
  // Returns true if remote (e.g. "3.1.1") is newer than installed (e.g. "3.1.0")
  static bool _isNewerVersion(String remote, String installed) {
    try {
      final r = remote.split('.').map(int.parse).toList();
      final i = installed.split('.').map(int.parse).toList();
      // Pad shorter version with zeros
      while (r.length < 3) r.add(0);
      while (i.length < 3) i.add(0);
      for (int idx = 0; idx < 3; idx++) {
        if (r[idx] > i[idx]) return true;
        if (r[idx] < i[idx]) return false;
      }
      return false;
    } catch (_) {
      return false;
    }
  }
}
