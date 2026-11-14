// lib/features/pro/pro_tab.dart
//
// NOVA X Pro tools (3.13.0, Android): the browser tab the tools work on.
//
// On PC the tools receive a desktop tab object. On Android each open
// BrowserView registers a ProTab here (its WebView controller, address,
// title, incognito / Safe View state), so the same tool code can read the
// page, reload it, go back or open another address.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class ProTab {
  ProTab({
    required this.id,
    required this.incognito,
    this.safe = false,
    required this.reloadPage,
    required this.leavePage,
  });

  /// Unique per open browser screen (also the NOVA Shield counts key).
  final int id;
  final bool incognito;

  /// Safe View (Open Safely): scripts off, downloads refused, nothing kept.
  final bool safe;

  InAppWebViewController? web;
  String url = '';
  String title = '';
  int progress = 100;

  /// Reloads the page (after a setting changed).
  final Future<void> Function() reloadPage;

  /// Goes back, or closes the browser screen when there is no page to go back to.
  final Future<void> Function() leavePage;

  bool get loading => progress < 100;
  bool get isWeb => url.startsWith('http://') || url.startsWith('https://');
  String get host => Uri.tryParse(url)?.host ?? '';
}

class ProTabs extends ChangeNotifier {
  ProTabs._();
  static final ProTabs instance = ProTabs._();

  final List<ProTab> _tabs = [];

  /// Opens a new browser screen for a URL. Set by the app (it knows the
  /// BrowserView route); null until then.
  void Function(String url, {bool incognito, bool safe})? opener;

  List<ProTab> get tabs => List.unmodifiable(_tabs);

  /// The browser screen on top (the one the user sees).
  ProTab? get active => _tabs.isEmpty ? null : _tabs.last;

  void register(ProTab t) {
    _tabs.remove(t);
    _tabs.add(t);
    notifyListeners();
  }

  void unregister(ProTab t) {
    _tabs.remove(t);
    notifyListeners();
  }

  /// A browser screen came back on top.
  void activate(ProTab t) {
    if (!_tabs.contains(t) || identical(_tabs.last, t)) return;
    _tabs.remove(t);
    _tabs.add(t);
  }

  void refresh() => notifyListeners();

  /// Opens [url] in a new browser screen.
  void openUrl(String url, {bool incognito = false, bool safe = false}) => opener?.call(url, incognito: incognito, safe: safe);

  Future<void> close(ProTab t) => t.leavePage();
}

/// Shows a message when a Pro tool is opened without a web page.
void proNeedsPage(BuildContext context) => ScaffoldMessenger.maybeOf(context)
    ?.showSnackBar(const SnackBar(content: Text('Open a web page first, then try again.')));
