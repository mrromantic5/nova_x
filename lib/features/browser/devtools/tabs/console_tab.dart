// lib/features/browser/devtools/tabs/console_tab.dart
//
// Console: live messages with levels, source location and stack, filters,
// search, preserve-log, plus a JavaScript REPL (top-level await, $0, $, $$,
// $x, history ↑↓, multi-line) with expandable object results.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../devtools_bridge.dart';
import '../dt_ui.dart';

class _Entry {
  _Entry.log(Map<String, dynamic> m)
      : level = m['type']?.toString() ?? 'log',
        text = m['msg']?.toString() ?? '',
        src = m['src']?.toString() ?? '',
        stack = m['stack']?.toString() ?? '',
        time = m['time']?.toString() ?? '',
        input = false,
        result = null;
  _Entry.input(this.text)
      : level = 'input',
        src = '',
        stack = '',
        time = '',
        input = true,
        result = null;
  _Entry.result(Map<String, dynamic> r)
      : level = r['type'] == 'error' ? 'error' : 'result',
        text = r['text']?.toString() ?? '',
        src = '',
        stack = '',
        time = '',
        input = false,
        result = r;
  final String level;
  final String text;
  final String src;
  final String stack;
  final String time;
  final bool input;
  final Map<String, dynamic>? result;
}

class ConsoleTab extends StatefulWidget {
  const ConsoleTab({
    super.key,
    required this.bridge,
    required this.logs,
    required this.changes,
    required this.onClear,
    required this.inputSeed,
    required this.onRevealElement,
  });
  final DevtoolsBridge bridge;
  final List<Map<String, dynamic>> logs;
  final Stream<void>? changes;
  final VoidCallback onClear;
  final ValueNotifier<String> inputSeed;
  final void Function(List<int> path) onRevealElement;

  @override
  State<ConsoleTab> createState() => _ConsoleTabState();
}

class _ConsoleTabState extends State<ConsoleTab> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<_Entry> _repl = []; // REPL inputs & results, interleaved by order
  final List<int> _replAt = []; // log count when each REPL entry was added
  final List<String> _history = [];
  int _hist = -1;
  StreamSubscription<void>? _sub;
  Set<String> _levels = {'log', 'info', 'warn', 'error', 'debug'};
  String _filter = '';
  bool _follow = true;
  int _cleared = 0;

  @override
  void initState() {
    super.initState();
    _sub = widget.changes?.listen((_) {
      if (!mounted) return;
      setState(() {});
      _toEnd();
    });
    widget.inputSeed.addListener(_seed);
    WidgetsBinding.instance.addPostFrameCallback((_) => _toEnd(jump: true));
  }

  void _seed() {
    final v = widget.inputSeed.value;
    if (v.isEmpty) return;
    _input.text = v;
    _input.selection = TextSelection.collapsed(offset: v.length);
  }

  @override
  void dispose() {
    _sub?.cancel();
    widget.inputSeed.removeListener(_seed);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _toEnd({bool jump = false}) {
    if (!_follow) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      if (jump) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      } else {
        _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 160), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _run() async {
    final code = _input.text.trim();
    if (code.isEmpty) return;
    _history.remove(code);
    _history.add(code);
    _hist = -1;
    _input.clear();
    setState(() {
      _repl.add(_Entry.input(code));
      _replAt.add(widget.logs.length);
    });
    _toEnd();
    final r = await widget.bridge.evaluate(code);
    if (!mounted) return;
    if (r['type'] == 'clear') {
      _clear();
      return;
    }
    setState(() {
      _repl.add(_Entry.result(r));
      _replAt.add(widget.logs.length);
    });
    _toEnd();
  }

  void _clear() {
    widget.onClear();
    setState(() {
      _repl.clear();
      _replAt.clear();
      _cleared = 0;
    });
  }

  List<_Entry> _merged() {
    final logs = widget.logs;
    final out = <_Entry>[];
    var r = 0;
    for (var i = _cleared; i <= logs.length; i++) {
      while (r < _repl.length && _replAt[r] <= i) {
        out.add(_repl[r++]);
      }
      if (i < logs.length) out.add(_Entry.log(logs[i]));
    }
    while (r < _repl.length) {
      out.add(_repl[r++]);
    }
    final f = _filter.toLowerCase();
    return out.where((e) {
      if (e.input || e.level == 'result') return true;
      final lvl = e.level == 'error' ? 'error' : e.level;
      if (!_levels.contains(lvl)) return false;
      return f.isEmpty || e.text.toLowerCase().contains(f) || e.src.toLowerCase().contains(f);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final entries = _merged();
    final errors = widget.logs.where((l) => l['type'] == 'error').length;
    final warns = widget.logs.where((l) => l['type'] == 'warn').length;
    return Column(children: [
      DtToolbar(children: [
        XIconBtn(Icons.block_rounded, tooltip: 'Clear console', onTap: _clear, size: 18),
        Expanded(child: DtFilter(onChanged: (v) => setState(() => _filter = v), hint: 'Filter messages')),
        PopupMenuButton<String>(
          color: XC.side,
          tooltip: 'Levels',
          icon: Row(mainAxisSize: MainAxisSize.min, children: [
            if (errors > 0) Text('$errors', style: XC.ui(11, color: XC.error, weight: FontWeight.w700)),
            if (errors > 0) const Icon(Icons.cancel, size: 13, color: XC.error),
            if (warns > 0) const SizedBox(width: 4),
            if (warns > 0) Text('$warns', style: XC.ui(11, color: XC.warning, weight: FontWeight.w700)),
            if (warns > 0) const Icon(Icons.warning_rounded, size: 13, color: XC.warning),
            const Icon(Icons.arrow_drop_down_rounded, color: XC.dim),
          ]),
          onSelected: (v) => setState(() {
            if (v == 'all') {
              _levels = {'log', 'info', 'warn', 'error', 'debug'};
            } else if (v == 'errors') {
              _levels = {'error'};
            } else if (_levels.contains(v)) {
              _levels = {..._levels}..remove(v);
            } else {
              _levels = {..._levels, v};
            }
          }),
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'all', child: Text('All levels')),
            const PopupMenuItem(value: 'errors', child: Text('Errors only')),
            const PopupMenuDivider(),
            for (final l in ['log', 'info', 'warn', 'error', 'debug'])
              CheckedPopupMenuItem(value: l, checked: _levels.contains(l), child: Text(l == 'log' ? 'Verbose / log' : l[0].toUpperCase() + l.substring(1))),
          ],
        ),
      ]),
      Expanded(
        child: NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n is UserScrollNotification) {
              final atEnd = _scroll.position.pixels >= _scroll.position.maxScrollExtent - 40;
              if (_follow != atEnd) setState(() => _follow = atEnd);
            }
            return false;
          },
          child: entries.isEmpty
              ? const DtEmpty(Icons.terminal_rounded, 'Console is empty',
                  body: 'Messages from console.log, errors and failed loads appear here. Type JavaScript below to run it on the page.')
              : SelectionArea(
                  child: ListView.builder(
                    controller: _scroll,
                    itemCount: entries.length,
                    itemBuilder: (_, i) => _ConsoleRow(entry: entries[i], bridge: widget.bridge, onReveal: widget.onRevealElement),
                  ),
                ),
        ),
      ),
      if (!_follow)
        InkWell(
          onTap: () {
            setState(() => _follow = true);
            _toEnd();
          },
          child: Container(
            width: double.infinity,
            color: XC.status,
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text('↓ New messages', textAlign: TextAlign.center, style: XC.ui(11.5, color: Colors.white)),
          ),
        ),
      Container(
        decoration: const BoxDecoration(color: Color(0xFF070D18), border: Border(top: BorderSide(color: XC.border))),
        padding: const EdgeInsets.only(left: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Padding(padding: const EdgeInsets.only(bottom: 11), child: Text('›', style: XC.mono(16, color: XC.accent, weight: FontWeight.w700))),
          const SizedBox(width: 6),
          Expanded(
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.enter, control: true): _run,
                const SingleActivator(LogicalKeyboardKey.arrowUp, alt: true): () => _histStep(-1),
                const SingleActivator(LogicalKeyboardKey.arrowDown, alt: true): () => _histStep(1),
              },
              child: TextField(
                controller: _input,
                minLines: 1,
                maxLines: 6,
                autocorrect: false,
                enableSuggestions: false,
                keyboardType: TextInputType.multiline,
                style: XC.mono(12.5),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: r'JavaScript — e.g. document.title, $0, await fetch(…)',
                  hintStyle: XC.mono(11.5, color: XC.faint),
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ),
          XIconBtn(Icons.history_rounded, tooltip: 'Previous command', onTap: _history.isEmpty ? null : () => _histStep(-1), size: 18),
          XIconBtn(Icons.play_arrow_rounded, tooltip: 'Run (Ctrl+Enter)', onTap: _run, color: XC.ok, size: 24),
        ]),
      ),
    ]);
  }

  void _histStep(int d) {
    if (_history.isEmpty) return;
    _hist = _hist == -1 ? _history.length - 1 : (_hist + d).clamp(0, _history.length - 1);
    final v = _history[_hist];
    _input.value = TextEditingValue(text: v, selection: TextSelection.collapsed(offset: v.length));
  }
}

class _ConsoleRow extends StatefulWidget {
  const _ConsoleRow({required this.entry, required this.bridge, required this.onReveal});
  final _Entry entry;
  final DevtoolsBridge bridge;
  final void Function(List<int>) onReveal;

  @override
  State<_ConsoleRow> createState() => _ConsoleRowState();
}

class _ConsoleRowState extends State<_ConsoleRow> {
  bool _stack = false;

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    final (Color fg, Color? bg, IconData? icon) = switch (e.level) {
      'error' => (const Color(0xFFFF8A80), const Color(0x22FF5370), Icons.cancel),
      'warn' => (const Color(0xFFFFE082), const Color(0x1AFFCB6B), Icons.warning_rounded),
      'info' => (const Color(0xFF82AAFF), null, Icons.info_outline_rounded),
      'debug' => (XC.faint, null, null),
      'input' => (XC.accent, null, Icons.chevron_right_rounded),
      'result' => (XC.text, null, Icons.chevron_left_rounded),
      _ => (XC.text, null, null),
    };
    final res = e.result;
    return Container(
      decoration: BoxDecoration(color: bg, border: const Border(bottom: BorderSide(color: Color(0xFF13203A)))),
      padding: const EdgeInsets.fromLTRB(6, 4, 8, 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 18, child: icon == null ? null : Icon(icon, size: 14, color: fg)),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (res != null && res['handle'] != null)
              _ObjectNode(bridge: widget.bridge, preview: res, onReveal: widget.onReveal)
            else
              GestureDetector(
                onTap: e.stack.isNotEmpty ? () => setState(() => _stack = !_stack) : null,
                child: Text(e.text, style: XC.mono(12, color: fg)),
              ),
            if (_stack && e.stack.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(e.stack, style: XC.mono(10.5, color: XC.faint))),
          ]),
        ),
        if (e.src.isNotEmpty)
          Padding(padding: const EdgeInsets.only(left: 6), child: Text(e.src, style: XC.mono(10.5, color: XC.faint))),
      ]),
    );
  }
}

/// Expandable object (fetches properties from the page on demand).
class _ObjectNode extends StatefulWidget {
  const _ObjectNode({required this.bridge, required this.preview, required this.onReveal, this.name, this.depth = 0});
  final DevtoolsBridge bridge;
  final Map<String, dynamic> preview;
  final void Function(List<int>) onReveal;
  final String? name;
  final int depth;

  @override
  State<_ObjectNode> createState() => _ObjectNodeState();
}

class _ObjectNodeState extends State<_ObjectNode> {
  bool _open = false;
  List<Map<String, dynamic>>? _props;
  String? _error;

  Future<void> _toggle() async {
    if (_open) {
      setState(() => _open = false);
      return;
    }
    setState(() => _open = true);
    if (_props != null) return;
    final r = await widget.bridge.call('props', widget.preview['handle']);
    if (!mounted) return;
    setState(() {
      if (!r.ok) _error = r.error;
      _props = r.items.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
    });
  }

  Color _color(String t) => switch (t) {
        'string' => const Color(0xFFCE9178),
        'number' || 'bigint' => const Color(0xFFB5CEA8),
        'boolean' || 'null' || 'undefined' => const Color(0xFF569CD6),
        'function' => const Color(0xFFDCDCAA),
        'element' => const Color(0xFF4EC9B0),
        'error' => const Color(0xFFFF8A80),
        _ => XC.text,
      };

  @override
  Widget build(BuildContext context) {
    final p = widget.preview;
    final t = p['type']?.toString() ?? '';
    final expandable = p['handle'] != null;
    final path = p['path'] is List ? (p['path'] as List).whereType<num>().map((e) => e.toInt()).toList() : null;
    final label = Text.rich(
      TextSpan(children: [
        if (expandable)
          WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Icon(_open ? Icons.arrow_drop_down_rounded : Icons.arrow_right_rounded, size: 16, color: XC.dim)),
        if (widget.name != null) TextSpan(text: '${widget.name}: ', style: XC.mono(12, color: const Color(0xFF9CDCFE))),
        TextSpan(text: p['type'] == 'string' && widget.depth > 0 ? '"${p['text']}"' : '${p['text']}', style: XC.mono(12, color: _color(t))),
      ]),
      maxLines: _open ? null : 3,
      overflow: _open ? null : TextOverflow.ellipsis,
    );
    return Padding(
      padding: EdgeInsets.only(left: widget.depth == 0 ? 0 : 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: InkWell(onTap: expandable ? _toggle : null, child: label)),
          if (path != null)
            InkWell(
              onTap: () => widget.onReveal(path),
              child: const Padding(padding: EdgeInsets.all(2), child: Icon(Icons.ads_click_rounded, size: 14, color: XC.accent)),
            ),
        ]),
        if (_open && _props == null && _error == null) const Padding(padding: EdgeInsets.all(4), child: SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5))),
        if (_open && _error != null) Text(_error!, style: XC.mono(11, color: XC.error)),
        if (_open && _props != null)
          for (final c in _props!)
            _ObjectNode(bridge: widget.bridge, preview: c, onReveal: widget.onReveal, name: c['key']?.toString(), depth: widget.depth + 1),
      ]),
    );
  }
}
