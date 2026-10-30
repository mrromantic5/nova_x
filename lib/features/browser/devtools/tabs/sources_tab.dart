// lib/features/browser/devtools/tabs/sources_tab.dart
//
// Sources: every file the page loaded (document, scripts, stylesheets,
// images, fonts, fetch/XHR) grouped by host and folder, plus inline
// <script>/<style> blocks. Opens any text file in a code viewer with syntax
// highlighting, pretty-print, search, word wrap, copy and "Edit in X Coder".
// Files the page itself can't read (other domains / CORS) are downloaded by
// the app instead.

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../devtools/screens/code_editor_screen.dart';
import '../../../xcoder/editor/ace_editor.dart';
import '../../../xcoder/widgets/xcoder_ui.dart' show aceModeFor;
import '../devtools_bridge.dart';
import '../dt_ui.dart';

class SourcesTab extends StatefulWidget {
  const SourcesTab({super.key, required this.bridge, required this.pageUrl});
  final DevtoolsBridge bridge;
  final String pageUrl;

  @override
  State<SourcesTab> createState() => _SourcesTabState();
}

class _SourcesTabState extends State<SourcesTab> {
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _inline = [];
  bool _loading = true;
  String? _error;
  String _filter = '';
  String _type = 'all';
  final Set<String> _closed = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final r = await widget.bridge.call('resources');
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = r.ok ? null : r.error;
      _items = r.items.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
      _inline = (r.map['inline'] as List? ?? const []).whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
    });
  }

  Future<void> _open(String url) async {
    final name = _nameOf(url);
    xToast(context, 'Opening $name…');
    var r = await widget.bridge.call('fetchText', url);
    String? text = r.map['text'] as String?;
    if (text == null && r.map['error'] == 'binary') {
      if (mounted) xToast(context, '$name is a binary file (${r.map['contentType']}).', error: true);
      return;
    }
    if (text == null) {
      // The page can't read it (CORS) — download it from the app instead.
      try {
        final res = await Dio(BaseOptions(responseType: ResponseType.plain, receiveTimeout: const Duration(seconds: 25),
                headers: {'User-Agent': 'Mozilla/5.0 (Linux; Android) NOVA-X DevTools'}))
            .get<String>(url);
        text = res.data ?? '';
      } catch (e) {
        if (mounted) xToast(context, 'Couldn’t load $name: $e', error: true);
        return;
      }
    }
    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => SourceViewerScreen(title: name, url: url, text: text!)));
  }

  Future<void> _openInline(Map<String, dynamic> i) async {
    final r = await widget.bridge.call('inlineSource', {'kind': i['kind'], 'index': i['index']});
    if (!mounted) return;
    final text = r.map['text'] as String?;
    if (text == null) {
      xToast(context, r.error ?? 'Not found', error: true);
      return;
    }
    final name = i['kind'] == 'style' ? 'inline-style-${i['index']}.css' : 'inline-script-${i['index']}.js';
    Navigator.push(context, MaterialPageRoute(builder: (_) => SourceViewerScreen(title: name, url: widget.pageUrl, text: text)));
  }

  static String _nameOf(String url) {
    final u = Uri.tryParse(url);
    final seg = u?.pathSegments.where((s) => s.isNotEmpty).lastOrNull;
    return seg == null || seg.isEmpty ? '(index)' : seg;
  }

  static IconData _icon(String t) => switch (t) {
        'document' => Icons.description_outlined,
        'script' => Icons.javascript_rounded,
        'stylesheet' => Icons.css_rounded,
        'image' => Icons.image_outlined,
        'font' => Icons.font_download_outlined,
        'fetch' => Icons.swap_vert_rounded,
        _ => Icons.insert_drive_file_outlined,
      };

  static Color _color(String t) => switch (t) {
        'document' => const Color(0xFFE44D26),
        'script' => const Color(0xFFF7DF1E),
        'stylesheet' => const Color(0xFF42A5F5),
        'image' => const Color(0xFF26A69A),
        'font' => const Color(0xFFB39DDB),
        'fetch' => const Color(0xFF90A4AE),
        _ => XC.dim,
      };

  @override
  Widget build(BuildContext context) {
    final f = _filter.toLowerCase();
    final items = _items.where((e) {
      if (_type != 'all' && e['type'] != _type) return false;
      return f.isEmpty || '${e['url']}'.toLowerCase().contains(f);
    }).toList();
    // group: host → folder → files
    final groups = <String, Map<String, List<Map<String, dynamic>>>>{};
    for (final e in items) {
      final u = Uri.tryParse('${e['url']}');
      final host = u == null || u.host.isEmpty ? '${e['url']}'.split(':').first : u.host;
      final segs = u?.pathSegments ?? const <String>[];
      final folder = segs.length > 1 ? '/${segs.sublist(0, segs.length - 1).join('/')}' : '/';
      groups.putIfAbsent(host, () => {}).putIfAbsent(folder, () => []).add(e);
    }
    return Column(children: [
      DtToolbar(children: [
        Expanded(child: DtFilter(onChanged: (v) => setState(() => _filter = v), hint: 'Filter files')),
        XIconBtn(Icons.refresh_rounded, tooltip: 'Reload list', onTap: _load),
      ]),
      SizedBox(
        height: 34,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5), children: [
          for (final t in const ['all', 'document', 'script', 'stylesheet', 'image', 'font', 'fetch', 'other'])
            DtChip(t == 'all' ? 'All' : t == 'stylesheet' ? 'CSS' : t == 'script' ? 'JS' : t[0].toUpperCase() + t.substring(1),
                selected: _type == t, onTap: () => setState(() => _type = t)),
        ]),
      ),
      Expanded(
        child: _loading
            ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
            : _error != null
                ? DtEmpty(Icons.error_outline_rounded, 'Can’t list sources', body: _error!)
                : ListView(children: [
                    for (final h in groups.entries) ...[
                      InkWell(
                        onTap: () => setState(() => _closed.contains(h.key) ? _closed.remove(h.key) : _closed.add(h.key)),
                        child: Container(
                          color: XC.bar,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                          child: Row(children: [
                            Icon(_closed.contains(h.key) ? Icons.arrow_right_rounded : Icons.arrow_drop_down_rounded, color: XC.dim),
                            const Icon(Icons.cloud_outlined, size: 16, color: XC.dim),
                            const SizedBox(width: 6),
                            Expanded(child: Text(h.key, style: XC.ui(12.5, weight: FontWeight.w700))),
                            Text('${h.value.values.fold<int>(0, (s, l) => s + l.length)}', style: XC.ui(11, color: XC.faint)),
                          ]),
                        ),
                      ),
                      if (!_closed.contains(h.key))
                        for (final d in h.value.entries) ...[
                          if (d.key != '/')
                            Padding(
                              padding: const EdgeInsets.fromLTRB(28, 6, 8, 2),
                              child: Row(children: [
                                const Icon(Icons.folder_outlined, size: 15, color: Color(0xFF90A4C8)),
                                const SizedBox(width: 6),
                                Expanded(child: Text(d.key, style: XC.mono(11.5, color: XC.dim), overflow: TextOverflow.ellipsis)),
                              ]),
                            ),
                          for (final e in d.value)
                            InkWell(
                              onTap: e['type'] == 'image' || e['type'] == 'font' ? null : () => _open('${e['url']}'),
                              onLongPress: () => dtCopy(context, '${e['url']}', 'Copied URL'),
                              child: Padding(
                                padding: EdgeInsets.fromLTRB(d.key == '/' ? 30 : 46, 6, 10, 6),
                                child: Row(children: [
                                  Icon(_icon('${e['type']}'), size: 16, color: _color('${e['type']}')),
                                  const SizedBox(width: 8),
                                  Expanded(child: Text(_nameOf('${e['url']}'), style: XC.mono(12.5), overflow: TextOverflow.ellipsis)),
                                  if ((e['size'] as num? ?? 0) > 0) Text(fmtBytes(e['size'] as num), style: XC.ui(10.5, color: XC.faint)),
                                ]),
                              ),
                            ),
                        ],
                    ],
                    if (_inline.isNotEmpty) ...[
                      const DtSection('Inline in this page'),
                      for (final i in _inline)
                        ListTile(
                          dense: true,
                          leading: Icon(i['kind'] == 'style' ? Icons.css_rounded : Icons.javascript_rounded,
                              size: 18, color: i['kind'] == 'style' ? const Color(0xFF42A5F5) : const Color(0xFFF7DF1E)),
                          title: Text('<${i['kind']}> #${i['index']}', style: XC.mono(12.5)),
                          subtitle: Text('${fmtBytes(i['size'] as num? ?? 0)}${i['type'] != null && i['type'] != 'text/javascript' ? ' · ${i['type']}' : ''}',
                              style: XC.ui(11, color: XC.faint)),
                          onTap: () => _openInline(i),
                        ),
                    ],
                  ]),
      ),
    ]);
  }
}

/// Read-only code viewer (bundled Ace): highlighting, pretty-print, search.
class SourceViewerScreen extends StatefulWidget {
  const SourceViewerScreen({super.key, required this.title, required this.url, required this.text});
  final String title;
  final String url;
  final String text;

  @override
  State<SourceViewerScreen> createState() => _SourceViewerScreenState();
}

class _SourceViewerScreenState extends State<SourceViewerScreen> {
  final _ace = AceController();
  bool _wrap = false;
  bool _pretty = false;
  AceCursor _cursor = const AceCursor();

  String get _mode {
    final m = aceModeFor(widget.title);
    if (m != 'text') return m;
    final t = widget.text.trimLeft();
    if (t.startsWith('<')) return 'html';
    if (t.startsWith('{') || t.startsWith('[')) return 'json';
    return 'javascript';
  }

  @override
  void initState() {
    super.initState();
    _ace.events.listen((e) {
      if (e is AceReady) {
        _ace.settings({'theme': 'one_dark', 'fontSize': 12.5, 'wrap': _wrap, 'live': false});
      } else if (e is AceCursorMoved && mounted) {
        setState(() => _cursor = e.cursor);
      }
    });
    _ace.open('src', widget.text, _mode, name: widget.title).then((_) => _ace.setReadOnly(true));
    // Minified? offer pretty-print right away.
    final lines = '\n'.allMatches(widget.text).length + 1;
    if (widget.text.length > 2000 && widget.text.length / lines > 300) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) xToast(context, 'Looks minified — tap { } to pretty-print.');
      });
    }
  }

  @override
  void dispose() {
    _ace.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: XC.bg,
      appBar: AppBar(
        backgroundColor: XC.bar,
        titleSpacing: 0,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.title, style: XC.ui(14.5, weight: FontWeight.w700), overflow: TextOverflow.ellipsis),
          Text('${fmtBytes(widget.text.length)} · Ln ${_cursor.row + 1}, Col ${_cursor.column + 1}', style: XC.ui(11, color: XC.faint)),
        ]),
        actions: [
          XIconBtn(Icons.data_object_rounded, tooltip: 'Pretty-print', color: _pretty ? XC.accent : XC.dim, onTap: () async {
            final r = await _ace.format();
            if (!mounted) return;
            if (r.ok) {
              setState(() => _pretty = true);
            } else {
              xToast(context, r.error ?? 'Can’t pretty-print this file', error: true);
            }
          }),
          XIconBtn(Icons.search_rounded, tooltip: 'Find', onTap: () => _ace.cmd('searchBox', {'replace': false})),
          PopupMenuButton<String>(
            color: XC.side,
            icon: const Icon(Icons.more_vert_rounded, color: XC.dim),
            onSelected: (v) async {
              switch (v) {
                case 'wrap':
                  setState(() => _wrap = !_wrap);
                  await _ace.settings({'wrap': _wrap});
                case 'copy':
                  final t = await _ace.value('src') ?? widget.text;
                  if (mounted) dtCopy(context, t, 'Copied ${fmtBytes(t.length)}');
                case 'url':
                  dtCopy(context, widget.url, 'Copied URL');
                case 'xcoder':
                  final t = await _ace.value('src') ?? widget.text;
                  if (!mounted) return;
                  final lang = kLangs.where((l) => l.mode == _mode).firstOrNull;
                  Navigator.push(context, MaterialPageRoute(builder: (_) => CodeEditorScreen(
                        initialContent: t,
                        initialFileName: widget.title.contains('.') ? widget.title : '${widget.title}.${lang?.ext ?? 'txt'}',
                        initialLang: lang,
                      )));
                case 'goto':
                  final v = await xPrompt(context, title: 'Go to line', hint: '1', action: 'Go',
                      validate: (s) => int.tryParse(s.trim()) == null ? 'Enter a number' : null);
                  if (v != null) await _ace.gotoLine(int.parse(v) - 1);
                case 'fold':
                  await _ace.cmd('foldAll');
              }
            },
            itemBuilder: (_) => [
              CheckedPopupMenuItem(value: 'wrap', checked: _wrap, child: const Text('Word wrap')),
              const PopupMenuItem(value: 'goto', child: Text('Go to line…')),
              const PopupMenuItem(value: 'fold', child: Text('Fold all')),
              const PopupMenuItem(value: 'copy', child: Text('Copy all')),
              const PopupMenuItem(value: 'url', child: Text('Copy URL')),
              const PopupMenuItem(value: 'xcoder', child: Text('Edit in X Coder')),
            ],
          ),
        ],
      ),
      body: AceEditorView(controller: _ace),
    );
  }
}
