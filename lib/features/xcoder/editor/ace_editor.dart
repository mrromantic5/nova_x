// lib/features/xcoder/editor/ace_editor.dart
//
// Flutter side of the X Coder editor (assets/xcoder/editor.html).
// Ace 1.43.4 is bundled with the app, so the editor, syntax highlighting,
// autocompletion, snippets and linting work with no internet.
//
// One WebView hosts every open file as its own Ace session (own undo
// history, cursor, folds). Commands go in through `window.nx.cmd(name, args)`
// with callAsyncJavaScript (arguments are passed as data, never pasted into
// script text). Events come back on the 'xc' handler.

import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Where the bundled editor page is served from (same origin as its workers).
const String kXCoderEditorUrl =
    'https://appassets.androidplatform.net/assets/flutter_assets/assets/xcoder/editor.html';

class AceAnnotation {
  const AceAnnotation({required this.row, required this.column, required this.type, required this.text});
  final int row;
  final int column;
  final String type; // error | warning | info
  final String text;

  bool get isError => type == 'error';
  bool get isWarning => type == 'warning';

  static AceAnnotation? fromMap(Object? m) {
    if (m is! Map) return null;
    return AceAnnotation(
      row: m['row'] is num ? (m['row'] as num).toInt() : 0,
      column: m['column'] is num ? (m['column'] as num).toInt() : 0,
      type: m['type']?.toString() ?? 'info',
      text: m['text']?.toString() ?? '',
    );
  }
}

class AceCursor {
  const AceCursor({this.row = 0, this.column = 0, this.selected = 0, this.lines = 0, this.selections = 1});
  final int row;
  final int column;
  final int selected;
  final int lines;
  final int selections;
}

/// Events from the editor page.
sealed class AceEvent {
  const AceEvent();
}

class AceReady extends AceEvent {
  const AceReady(this.version);
  final String version;
}

class AceChanged extends AceEvent {
  const AceChanged(this.id, this.dirty, this.chars);
  final String id;
  final bool dirty;
  final int chars;
}

class AceCursorMoved extends AceEvent {
  const AceCursorMoved(this.id, this.cursor);
  final String id;
  final AceCursor cursor;
}

class AceAnnotations extends AceEvent {
  const AceAnnotations(this.id, this.items);
  final String id;
  final List<AceAnnotation> items;
}

class AceKey extends AceEvent {
  const AceKey(this.key);
  final String key; // save | palette | quickOpen | run | terminal | ai | findInFiles
}

class AceTheme extends AceEvent {
  const AceTheme(this.background, this.dark);
  final Color? background;
  final bool dark;
}

class AceController {
  InAppWebViewController? _wvc;
  final _events = StreamController<AceEvent>.broadcast();
  final _ready = Completer<void>();
  final _pending = Queue<Future<void> Function()>();
  String? _current;

  Stream<AceEvent> get events => _events.stream;
  bool get isReady => _ready.isCompleted;
  Future<void> get ready => _ready.future;
  String? get currentId => _current;

  void _attach(InAppWebViewController c) {
    _wvc = c;
    c.addJavaScriptHandler(handlerName: 'xc', callback: (args) {
      if (args.isEmpty || args.first is! Map) return null;
      _onEvent(Map<String, dynamic>.from(args.first as Map));
      return null;
    });
  }

  void _onEvent(Map<String, dynamic> e) {
    final id = e['id']?.toString() ?? '';
    switch (e['type']) {
      case 'ready':
        if (!_ready.isCompleted) _ready.complete();
        _events.add(AceReady(e['version']?.toString() ?? ''));
        while (_pending.isNotEmpty) {
          _pending.removeFirst()();
        }
      case 'change':
        _events.add(AceChanged(id, e['dirty'] == true, e['chars'] is num ? (e['chars'] as num).toInt() : 0));
      case 'cursor':
        int n(String k) => e[k] is num ? (e[k] as num).toInt() : 0;
        _events.add(AceCursorMoved(id, AceCursor(row: n('row'), column: n('column'), selected: n('selected'),
            lines: n('lines'), selections: n('selections'))));
      case 'annotations':
        final items = e['items'] is List
            ? (e['items'] as List).map(AceAnnotation.fromMap).whereType<AceAnnotation>().toList()
            : const <AceAnnotation>[];
        _events.add(AceAnnotations(id, items));
      case 'key':
        _events.add(AceKey(e['key']?.toString() ?? ''));
      case 'theme':
        _events.add(AceTheme(_parseCss(e['background']?.toString()), e['dark'] == true));
    }
  }

  static Color? _parseCss(String? s) {
    final m = RegExp(r'rgba?\((\d+),\s*(\d+),\s*(\d+)').firstMatch(s ?? '');
    if (m == null) return null;
    return Color.fromARGB(255, int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!));
  }

  /// Runs a command in the editor page. Returns its (JSON) result or null.
  Future<Object?> cmd(String name, [Map<String, Object?> args = const {}]) async {
    final c = _wvc;
    if (c == null) return null;
    if (!isReady) await ready.timeout(const Duration(seconds: 20), onTimeout: () {});
    try {
      final r = await c.callAsyncJavaScript(
        functionBody: 'return window.nx ? window.nx.cmd(name, args) : null;',
        arguments: {'name': name, 'args': args},
      );
      if (r == null || r.error != null) return null;
      return r.value;
    } catch (e) {
      if (kDebugMode) debugPrint('ace $name failed: $e');
      return null;
    }
  }

  // ── Typed helpers ─────────────────────────────────────────────────────
  Future<void> open(String id, String content, String mode, {String name = '', bool focus = true}) async {
    await cmd('open', {'id': id, 'content': content, 'mode': mode, 'name': name, 'focus': focus});
    if (focus) _current = id;
  }

  Future<void> switchTo(String id) async {
    await cmd('switchTo', {'id': id});
    _current = id;
  }

  Future<void> close(String id) async {
    await cmd('close', {'id': id});
    if (_current == id) _current = null;
  }

  Future<String?> value([String? id]) async {
    final v = await cmd('getValue', {'id': id ?? _current});
    return v is String ? v : null;
  }

  Future<void> setValue(String text, {String? id, bool keepUndo = true, bool markSaved = false}) =>
      cmd('setValue', {'id': id ?? _current, 'text': text, 'keepUndo': keepUndo, 'markSaved': markSaved});

  Future<void> markSaved([String? id]) => cmd('markSaved', {'id': id ?? _current});
  Future<void> setMode(String mode, [String? id]) => cmd('setMode', {'id': id ?? _current, 'mode': mode});
  Future<void> settings(Map<String, Object?> s) => cmd('settings', s);
  Future<void> insert(String text, {String where = 'cursor', bool highlight = true}) =>
      cmd('insert', {'text': text, 'where': where, 'highlight': highlight});
  Future<void> typeKey(String key) => cmd('typeKey', {'key': key});
  Future<void> exec(String command) => cmd('exec', {'command': command});
  Future<void> gotoLine(int row, [int column = 0]) => cmd('gotoLine', {'row': row, 'column': column});
  Future<void> focus() => cmd('focus');
  Future<void> blur() => cmd('blur');
  Future<void> setReadOnly(bool ro, [String? id]) => cmd('setReadOnly', {'id': id ?? _current, 'readOnly': ro});

  Future<({bool ok, String? error})> format() async {
    final r = await cmd('format');
    if (r is Map) return (ok: r['ok'] == true, error: r['error']?.toString());
    return (ok: false, error: 'Formatting is not available.');
  }

  Future<String> selection() async {
    final v = await cmd('selection');
    return v is String ? v : '';
  }

  /// {selection, before, after, line, row, column, value}
  Future<Map<String, dynamic>> context() async {
    final v = await cmd('context');
    return v is Map ? Map<String, dynamic>.from(v) : const {};
  }

  Future<int> findAll(String q, {bool regex = false, bool caseSensitive = false, bool wholeWord = false}) async {
    final v = await cmd('findAll', {'query': q, 'regex': regex, 'caseSensitive': caseSensitive, 'wholeWord': wholeWord});
    return v is num ? v.toInt() : 0;
  }

  Future<bool> find(String q, {bool back = false, bool regex = false, bool caseSensitive = false, bool wholeWord = false}) async =>
      await cmd('find', {'query': q, 'back': back, 'regex': regex, 'caseSensitive': caseSensitive, 'wholeWord': wholeWord}) == true;

  Future<int> replaceAll(String q, String repl, {bool regex = false, bool caseSensitive = false, bool wholeWord = false}) async {
    final v = await cmd('replaceAll',
        {'query': q, 'replacement': repl, 'regex': regex, 'caseSensitive': caseSensitive, 'wholeWord': wholeWord});
    return v is num ? v.toInt() : 0;
  }

  Future<List<({int row, String name, int indent})>> outline() async {
    final v = await cmd('outline');
    if (v is! List) return const [];
    return [
      for (final e in v)
        if (e is Map)
          (
            row: e['row'] is num ? (e['row'] as num).toInt() : 0,
            name: e['name']?.toString() ?? '',
            indent: e['indent'] is num ? (e['indent'] as num).toInt() : 0,
          )
    ];
  }

  Future<void> projectWords(List<String> words) => cmd('projectWords', {'words': words});

  void dispose() {
    _events.close();
    _wvc = null;
  }
}

/// The editor surface. Put it in the layout once and drive it with [controller].
class AceEditorView extends StatefulWidget {
  const AceEditorView({super.key, required this.controller, this.background = const Color(0xFF0B1424)});

  final AceController controller;
  final Color background;

  @override
  State<AceEditorView> createState() => _AceEditorViewState();
}

class _AceEditorViewState extends State<AceEditorView> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ColoredBox(
      color: widget.background,
      child: InAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(kXCoderEditorUrl)),
        initialSettings: InAppWebViewSettings(
          webViewAssetLoader: WebViewAssetLoader(pathHandlers: [AssetsPathHandler(path: '/assets/')]),
          javaScriptEnabled: true,
          transparentBackground: true,
          supportZoom: false,
          builtInZoomControls: false,
          displayZoomControls: false,
          allowFileAccess: false,
          allowContentAccess: false,
          allowFileAccessFromFileURLs: false,
          allowUniversalAccessFromFileURLs: false,
          cacheEnabled: true,
          disableContextMenu: false,
          verticalScrollBarEnabled: false,
          horizontalScrollBarEnabled: false,
          overScrollMode: OverScrollMode.NEVER,
          textZoom: 100,
          useHybridComposition: true,
          useShouldOverrideUrlLoading: true,
        ),
        onWebViewCreated: widget.controller._attach,
        // The editor page only loads its own bundled files.
        shouldOverrideUrlLoading: (c, a) async {
          final u = a.request.url?.toString() ?? '';
          return u.startsWith('https://appassets.androidplatform.net/')
              ? NavigationActionPolicy.ALLOW
              : NavigationActionPolicy.CANCEL;
        },
      ),
    );
  }
}
