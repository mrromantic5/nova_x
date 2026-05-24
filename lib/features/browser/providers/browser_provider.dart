import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Represents a single browser tab with its metadata.
class BrowserTab {
  final String id;
  final String url;
  final String title;
  final double progress;
  InAppWebViewController? controller;

  BrowserTab({
    required this.id,
    required this.url,
    this.title    = 'New Tab',
    this.progress = 0.0,
    this.controller,
  });

  BrowserTab copyWith({
    String? id,
    String? url,
    String? title,
    double? progress,
    InAppWebViewController? controller,
  }) {
    return BrowserTab(
      id:         id         ?? this.id,
      url:        url        ?? this.url,
      title:      title      ?? this.title,
      progress:   progress   ?? this.progress,
      controller: controller ?? this.controller,
    );
  }
}

/// Riverpod notifier managing the list of open browser tabs.
class BrowserNotifier extends StateNotifier<List<BrowserTab>> {
  BrowserNotifier() : super([]);

  String? _activeTabId;
  String? get activeTabId => _activeTabId;

  void createNewTab(String url) {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    state = [...state, BrowserTab(id: id, url: url)];
    _activeTabId = id;
  }

  void closeTab(String id) {
    state = state.where((t) => t.id != id).toList();
    if (_activeTabId == id) {
      _activeTabId = state.isNotEmpty ? state.last.id : null;
    }
  }

  void updateTab(String id, {String? url, String? title}) {
    state = [
      for (final tab in state)
        if (tab.id == id) tab.copyWith(url: url, title: title) else tab,
    ];
  }

  void updateProgress(String id, double progress) {
    state = [
      for (final tab in state)
        if (tab.id == id) tab.copyWith(progress: progress) else tab,
    ];
  }

  void setActiveTab(String id) => _activeTabId = id;
}

final browserProvider =
    StateNotifierProvider<BrowserNotifier, List<BrowserTab>>(
        (_) => BrowserNotifier());
