// lib/core/services/offline_service.dart
//
// Stores pages saved for offline reading (Chrome-style). The browser writes an
// MHTML web-archive to app storage via WebView.saveWebArchive(); this service
// tracks the saved files (title/url/path/savedAt) in SharedPreferences.

import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OfflinePage {
  final String id;
  final String url;
  final String title;
  final String path;
  final int savedAt;
  OfflinePage({
    required this.id,
    required this.url,
    required this.title,
    required this.path,
    required this.savedAt,
  });
  Map<String, dynamic> toJson() =>
      {'id': id, 'url': url, 'title': title, 'path': path, 'savedAt': savedAt};
  factory OfflinePage.fromJson(Map<String, dynamic> m) => OfflinePage(
        id: (m['id'] ?? '').toString(),
        url: (m['url'] ?? '').toString(),
        title: (m['title'] ?? 'Saved page').toString(),
        path: (m['path'] ?? '').toString(),
        savedAt: (m['savedAt'] is num) ? (m['savedAt'] as num).toInt() : 0,
      );
}

class OfflineService extends ChangeNotifier {
  OfflineService._();
  static final OfflineService instance = OfflineService._();

  static const _key = 'nx_offline_v1';
  bool _loaded = false;
  List<OfflinePage> pages = [];

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_key);
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw) as List;
        pages = [
          for (final e in list) OfflinePage.fromJson(Map<String, dynamic>.from(e))
        ];
      }
    } catch (_) {}
    notifyListeners();
  }

  Future<void> _save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_key, jsonEncode([for (final e in pages) e.toJson()]));
    } catch (_) {}
  }

  Future<void> add(OfflinePage page) async {
    pages = [page, ...pages];
    await _save();
    notifyListeners();
  }

  Future<void> remove(String id) async {
    OfflinePage? found;
    for (final p in pages) {
      if (p.id == id) found = p;
    }
    if (found != null && found.path.isNotEmpty) {
      try {
        final f = File(found.path);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
    pages = pages.where((p) => p.id != id).toList();
    await _save();
    notifyListeners();
  }
}
