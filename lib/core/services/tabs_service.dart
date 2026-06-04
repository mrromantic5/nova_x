// lib/core/services/tabs_service.dart
//
// Brave-style multi-tab + tab-group store for NOVA X.
// Self-contained ChangeNotifier persisted to SharedPreferences. The browser
// upserts the current page as a tab; the Tabs switcher reads/edits this store.

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BrowserTabItem {
  final String id;
  String url;
  String title;
  String? groupId;
  int updatedAt;
  BrowserTabItem({
    required this.id,
    required this.url,
    this.title = 'New Tab',
    this.groupId,
    required this.updatedAt,
  });
  Map<String, dynamic> toJson() =>
      {'id': id, 'url': url, 'title': title, 'groupId': groupId, 'updatedAt': updatedAt};
  factory BrowserTabItem.fromJson(Map<String, dynamic> m) => BrowserTabItem(
        id: (m['id'] ?? '').toString(),
        url: (m['url'] ?? '').toString(),
        title: (m['title'] ?? 'New Tab').toString(),
        groupId: m['groupId']?.toString(),
        updatedAt: (m['updatedAt'] is num) ? (m['updatedAt'] as num).toInt() : 0,
      );
}

class TabGroup {
  final String id;
  String name;
  int color;
  TabGroup({required this.id, required this.name, required this.color});
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'color': color};
  factory TabGroup.fromJson(Map<String, dynamic> m) => TabGroup(
        id: (m['id'] ?? '').toString(),
        name: (m['name'] ?? 'Group').toString(),
        color: (m['color'] is num) ? (m['color'] as num).toInt() : 0xFF00D4FF,
      );
}

/// Result returned by the Tabs switcher to the browser.
class TabsResult {
  final String? url;
  final String? tabId;
  final bool newTab;
  final bool incognito;
  TabsResult({this.url, this.tabId, this.newTab = false, this.incognito = false});
}

class TabsService extends ChangeNotifier {
  TabsService._();
  static final TabsService instance = TabsService._();

  static const _key = 'nx_tabs_v1';
  bool _loaded = false;

  List<BrowserTabItem> tabs = [];
  List<TabGroup> groups = [];

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_key);
      if (raw != null && raw.isNotEmpty) {
        final m = jsonDecode(raw) as Map<String, dynamic>;
        tabs = [
          for (final t in (m['tabs'] as List? ?? const []))
            BrowserTabItem.fromJson(Map<String, dynamic>.from(t))
        ];
        groups = [
          for (final g in (m['groups'] as List? ?? const []))
            TabGroup.fromJson(Map<String, dynamic>.from(g))
        ];
      }
    } catch (_) {}
    notifyListeners();
  }

  Future<void> _save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_key, jsonEncode({
        'tabs': [for (final t in tabs) t.toJson()],
        'groups': [for (final g in groups) g.toJson()],
      }));
    } catch (_) {}
  }

  String _newId() =>
      '${DateTime.now().microsecondsSinceEpoch}_${tabs.length}';

  BrowserTabItem openTab(String url, {String title = 'New Tab', String? groupId}) {
    final t = BrowserTabItem(
      id: _newId(),
      url: url,
      title: title,
      groupId: groupId,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    tabs = [...tabs, t];
    _save();
    notifyListeners();
    return t;
  }

  void updateTab(String id, {String? url, String? title}) {
    for (final t in tabs) {
      if (t.id == id) {
        if (url != null && url.isNotEmpty) t.url = url;
        if (title != null && title.isNotEmpty) t.title = title;
        t.updatedAt = DateTime.now().millisecondsSinceEpoch;
        _save();
        notifyListeners();
        return;
      }
    }
  }

  void closeTab(String id) {
    tabs = tabs.where((t) => t.id != id).toList();
    _save();
    notifyListeners();
  }

  void closeAll() {
    tabs = [];
    _save();
    notifyListeners();
  }

  TabGroup createGroup(String name, int color) {
    final g = TabGroup(id: 'g${_newId()}', name: name, color: color);
    groups = [...groups, g];
    _save();
    notifyListeners();
    return g;
  }

  void renameGroup(String groupId, String name) {
    for (final g in groups) {
      if (g.id == groupId) {
        g.name = name;
        _save();
        notifyListeners();
        return;
      }
    }
  }

  void deleteGroup(String groupId) {
    for (final t in tabs) {
      if (t.groupId == groupId) t.groupId = null;
    }
    groups = groups.where((g) => g.id != groupId).toList();
    _save();
    notifyListeners();
  }

  void assignToGroup(String tabId, String? groupId) {
    for (final t in tabs) {
      if (t.id == tabId) {
        t.groupId = groupId;
        _save();
        notifyListeners();
        return;
      }
    }
  }

  List<BrowserTabItem> tabsInGroup(String? groupId) =>
      tabs.where((t) => t.groupId == groupId).toList();
}
