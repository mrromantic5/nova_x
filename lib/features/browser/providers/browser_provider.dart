import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

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
    String? url,
    String? title,
    double? progress,
    InAppWebViewController? controller,
  }) => BrowserTab(
    id:         id,
    url:        url        ?? this.url,
    title:      title      ?? this.title,
    progress:   progress   ?? this.progress,
    controller: controller ?? this.controller,
  );
}

class BrowserNotifier extends StateNotifier<List<BrowserTab>> {
  BrowserNotifier() : super([]);

  String? _activeId;
  String? get activeId => _activeId;

  void openTab(String url) {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    state       = [...state, BrowserTab(id: id, url: url)];
    _activeId   = id;
  }

  void closeTab(String id) {
    state = state.where((t) => t.id != id).toList();
    if (_activeId == id) {
      _activeId = state.isNotEmpty ? state.last.id : null;
    }
  }

  void updateTab(String id, {String? url, String? title, double? progress}) {
    state = [
      for (final t in state)
        if (t.id == id) t.copyWith(url: url, title: title, progress: progress)
        else t,
    ];
  }

  void setActive(String id) => _activeId = id;
}

final browserProvider =
    StateNotifierProvider<BrowserNotifier, List<BrowserTab>>(
        (_) => BrowserNotifier());
