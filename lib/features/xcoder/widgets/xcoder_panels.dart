// lib/features/xcoder/widgets/xcoder_panels.dart
//
// Bottom panel of X Coder: PROBLEMS · TERMINAL · OUTPUT · SEARCH.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../editor/ace_editor.dart';
import '../terminal/xcoder_terminal.dart';
import '../workspace/xcoder_workspace.dart';
import 'xcoder_ui.dart';

enum XPanel { problems, terminal, output, search }

class XProblem {
  const XProblem(this.rel, this.name, this.a);
  final String? rel;
  final String name;
  final AceAnnotation a;
}

// ── Problems ─────────────────────────────────────────────────────────────────

class ProblemsView extends StatelessWidget {
  const ProblemsView({super.key, required this.problems, required this.onOpen, this.onFixWithNova});
  final List<XProblem> problems;
  final void Function(XProblem) onOpen;
  final VoidCallback? onFixWithNova;

  @override
  Widget build(BuildContext context) {
    if (problems.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.check_circle_outline_rounded, color: XC.ok, size: 28),
          const SizedBox(height: 8),
          Text('No problems in open files', style: XC.ui(13, color: XC.dim)),
          const SizedBox(height: 4),
          Text('JavaScript, CSS, HTML, JSON, PHP, XML and YAML are checked as you type.',
              style: XC.ui(11.5, color: XC.faint), textAlign: TextAlign.center),
        ]),
      );
    }
    final sorted = [...problems]..sort((a, b) {
        int rank(AceAnnotation x) => x.isError ? 0 : (x.isWarning ? 1 : 2);
        final r = rank(a.a).compareTo(rank(b.a));
        if (r != 0) return r;
        final f = a.name.compareTo(b.name);
        return f != 0 ? f : a.a.row.compareTo(b.a.row);
      });
    return Column(children: [
      if (onFixWithNova != null && problems.any((p) => p.a.isError || p.a.isWarning))
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 2),
          child: Row(children: [
            Expanded(
              child: Text('${problems.where((p) => p.a.isError).length} errors · ${problems.where((p) => p.a.isWarning).length} warnings',
                  style: XC.ui(12, color: XC.dim)),
            ),
            TextButton.icon(
              onPressed: onFixWithNova,
              icon: const Icon(Icons.auto_awesome_rounded, size: 16),
              label: const Text('Fix with NOVA'),
            ),
          ]),
        ),
      Expanded(
        child: ListView.builder(
          itemCount: sorted.length,
          itemBuilder: (_, i) {
            final p = sorted[i];
            final (icon, color) = p.a.isError
                ? (Icons.error_outline_rounded, XC.error)
                : p.a.isWarning
                    ? (Icons.warning_amber_rounded, XC.warning)
                    : (Icons.info_outline_rounded, XC.info);
            return InkWell(
              onTap: () => onOpen(p),
              onLongPress: () {
                Clipboard.setData(ClipboardData(text: '${p.name}:${p.a.row + 1}:${p.a.column + 1} ${p.a.text}'));
                xToast(context, 'Copied');
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(icon, size: 16, color: color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text.rich(TextSpan(children: [
                      TextSpan(text: p.a.text, style: XC.ui(12.5)),
                      TextSpan(text: '   ${p.name} [Ln ${p.a.row + 1}, Col ${p.a.column + 1}]', style: XC.ui(11.5, color: XC.faint)),
                    ])),
                  ),
                ]),
              ),
            );
          },
        ),
      ),
    ]);
  }
}

// ── Terminal ─────────────────────────────────────────────────────────────────

class TerminalView extends StatefulWidget {
  const TerminalView({super.key, required this.terminal, this.autofocus = false});
  final XTerminal terminal;
  final bool autofocus;

  @override
  State<TerminalView> createState() => _TerminalViewState();
}

class _TerminalViewState extends State<TerminalView> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.terminal.welcome();
    widget.terminal.addListener(_changed);
  }

  @override
  void didUpdateWidget(TerminalView old) {
    super.didUpdateWidget(old);
    if (old.terminal != widget.terminal) {
      old.terminal.removeListener(_changed);
      widget.terminal.welcome();
      widget.terminal.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.terminal.removeListener(_changed);
    _input.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Color _color(TermStyle s) => switch (s) {
        TermStyle.input => XC.accent,
        TermStyle.err => XC.error,
        TermStyle.warn => XC.warning,
        TermStyle.info => XC.info,
        TermStyle.ok => XC.ok,
        TermStyle.dim => XC.faint,
        TermStyle.out => XC.text,
      };

  Future<void> _submit() async {
    final t = _input.text;
    _input.clear();
    await widget.terminal.submit(t);
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.terminal;
    return Container(
      color: const Color(0xFF070D18),
      child: Column(children: [
        Expanded(
          child: SelectionArea(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
              itemCount: t.lines.length,
              itemBuilder: (_, i) {
                final l = t.lines[i];
                return Text(l.text, style: XC.mono(12, color: _color(l.style)), softWrap: true);
              },
            ),
          ),
        ),
        Container(
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: XC.border))),
          padding: const EdgeInsets.only(left: 10),
          child: Row(children: [
            Flexible(
              flex: 0,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 160),
                child: Text(t.busy ? '› ' : t.prompt,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: XC.mono(12, color: t.busy ? XC.warning : XC.ok)),
              ),
            ),
            Expanded(
              child: CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.arrowUp): () {
                    final h = t.historyStep(-1);
                    if (h != null) _input.value = TextEditingValue(text: h, selection: TextSelection.collapsed(offset: h.length));
                  },
                  const SingleActivator(LogicalKeyboardKey.arrowDown): () {
                    final h = t.historyStep(1);
                    if (h != null) _input.value = TextEditingValue(text: h, selection: TextSelection.collapsed(offset: h.length));
                  },
                  const SingleActivator(LogicalKeyboardKey.tab): () async {
                    final c = await t.complete(_input.text);
                    if (c != null) _input.value = TextEditingValue(text: c, selection: TextSelection.collapsed(offset: c.length));
                  },
                  const SingleActivator(LogicalKeyboardKey.keyC, control: true): t.interrupt,
                  const SingleActivator(LogicalKeyboardKey.keyL, control: true): t.clear,
                },
                child: TextField(
                  controller: _input,
                  focusNode: _focus,
                  autofocus: widget.autofocus,
                  autocorrect: false,
                  enableSuggestions: false,
                  keyboardType: TextInputType.visiblePassword, // no autocorrect / caps on Android keyboards
                  textCapitalization: TextCapitalization.none,
                  style: XC.mono(12.5),
                  cursorColor: XC.accent,
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: t.busy ? 'input for the running program…' : 'command',
                    hintStyle: XC.mono(12, color: XC.faint),
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  onSubmitted: (_) => _submit(),
                ),
              ),
            ),
            _key('↑', () {
              final h = t.historyStep(-1);
              if (h != null) _input.value = TextEditingValue(text: h, selection: TextSelection.collapsed(offset: h.length));
            }),
            _key('Tab', () async {
              final c = await t.complete(_input.text);
              if (c != null) _input.value = TextEditingValue(text: c, selection: TextSelection.collapsed(offset: c.length));
            }),
            if (t.busy) _key('^C', t.interrupt, color: XC.error) else _key('⏎', _submit, color: XC.accent),
          ]),
        ),
      ]),
    );
  }

  Widget _key(String label, VoidCallback onTap, {Color color = XC.dim}) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Text(label, style: XC.mono(12.5, color: color, weight: FontWeight.w600)),
        ),
      );
}

// ── Output (run results, preview console) ────────────────────────────────────

class OutputLine {
  const OutputLine(this.level, this.text, this.time);
  final String level;
  final String text;
  final DateTime time;
}

class OutputView extends StatelessWidget {
  const OutputView({super.key, required this.lines, required this.onClear});
  final List<OutputLine> lines;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    if (lines.isEmpty) {
      return Center(child: Text('Output of ▶ Run and the preview console appears here.', style: XC.ui(12.5, color: XC.faint)));
    }
    return Stack(children: [
      SelectionArea(
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 30),
          itemCount: lines.length,
          itemBuilder: (_, i) {
            final l = lines[i];
            final c = switch (l.level) {
              'error' => XC.error,
              'warn' => XC.warning,
              'info' => XC.info,
              'debug' => XC.faint,
              'system' => XC.accent,
              _ => XC.text,
            };
            final t = l.time;
            final ts = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
            return Container(
              color: l.level == 'error' ? XC.error.withOpacity(0.07) : (l.level == 'warn' ? XC.warning.withOpacity(0.05) : null),
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('$ts  ', style: XC.mono(11, color: XC.faint)),
                Expanded(child: Text(l.text, style: XC.mono(12, color: c))),
              ]),
            );
          },
        ),
      ),
      Positioned(
        right: 6,
        bottom: 4,
        child: XIconBtn(Icons.block_rounded, tooltip: 'Clear output', onTap: onClear, size: 18),
      ),
    ]);
  }
}

// ── Find in files ────────────────────────────────────────────────────────────

class SearchView extends StatefulWidget {
  const SearchView({super.key, required this.project, required this.onOpen, required this.onReplaced, this.initial = ''});
  final XProject project;
  final void Function(XSearchHit) onOpen;
  final Future<void> Function() onReplaced;
  final String initial;

  @override
  State<SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends State<SearchView> {
  late final _q = TextEditingController(text: widget.initial);
  final _r = TextEditingController();
  final _inc = TextEditingController();
  bool _regex = false, _case = false, _word = false, _showReplace = false, _busy = false;
  List<XSearchHit> _hits = const [];
  String _searched = '';

  @override
  void initState() {
    super.initState();
    if (widget.initial.isNotEmpty) _run();
  }

  Future<void> _run() async {
    final q = _q.text;
    if (q.isEmpty) {
      setState(() => _hits = const []);
      return;
    }
    setState(() => _busy = true);
    final hits = await XWorkspace.instance.search(widget.project, q,
        regex: _regex, caseSensitive: _case, wholeWord: _word, include: _inc.text);
    if (!mounted) return;
    setState(() {
      _hits = hits;
      _busy = false;
      _searched = q;
    });
  }

  Future<void> _replaceAll() async {
    if (_q.text.isEmpty || _hits.isEmpty) return;
    final files = _hits.map((h) => h.rel).toSet().length;
    if (!await xConfirm(context, 'Replace in $files file${files == 1 ? '' : 's'}?',
        'Every match of “${_q.text}” becomes “${_r.text}”. Open files reload; use Undo in each file to go back.',
        action: 'Replace all', danger: false)) {
      return;
    }
    final (f, n) = await XWorkspace.instance.replaceInFiles(widget.project, _q.text, _r.text,
        regex: _regex, caseSensitive: _case, wholeWord: _word);
    await widget.onReplaced();
    if (!mounted) return;
    xToast(context, 'Replaced $n in $f file${f == 1 ? '' : 's'}');
    _run();
  }

  Widget _toggle(String label, bool on, VoidCallback tap) => InkWell(
        onTap: () {
          tap();
          _run();
        },
        borderRadius: BorderRadius.circular(4),
        child: Container(
          margin: const EdgeInsets.only(left: 4),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: on ? XC.accent.withOpacity(0.18) : Colors.transparent,
            border: Border.all(color: on ? XC.accent : XC.border),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(label, style: XC.mono(11, color: on ? XC.accent : XC.dim, weight: FontWeight.w700)),
        ),
      );

  InputDecoration _dec(String hint) => InputDecoration(
        isDense: true,
        hintText: hint,
        hintStyle: XC.ui(12.5, color: XC.faint),
        filled: true,
        fillColor: XC.bg,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: XC.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: XC.border)),
      );

  @override
  Widget build(BuildContext context) {
    final byFile = <String, List<XSearchHit>>{};
    for (final h in _hits) {
      byFile.putIfAbsent(h.rel, () => []).add(h);
    }
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
        child: Row(children: [
          InkWell(
            onTap: () => setState(() => _showReplace = !_showReplace),
            child: Icon(_showReplace ? Icons.expand_more_rounded : Icons.chevron_right_rounded, color: XC.dim),
          ),
          Expanded(child: TextField(controller: _q, style: XC.mono(13), decoration: _dec('Search'), onSubmitted: (_) => _run())),
          _toggle('Aa', _case, () => _case = !_case),
          _toggle('ab', _word, () => _word = !_word),
          _toggle('.*', _regex, () => _regex = !_regex),
        ]),
      ),
      if (_showReplace)
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 6, 8, 0),
          child: Row(children: [
            Expanded(child: TextField(controller: _r, style: XC.mono(13), decoration: _dec('Replace'))),
            XIconBtn(Icons.find_replace_rounded, tooltip: 'Replace all', onTap: _hits.isEmpty ? null : _replaceAll, size: 18),
          ]),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(32, 6, 8, 4),
        child: TextField(controller: _inc, style: XC.mono(12), decoration: _dec('files to include, e.g. *.js, src/'), onSubmitted: (_) => _run()),
      ),
      if (_busy) const LinearProgressIndicator(minHeight: 2, color: XC.accent, backgroundColor: Colors.transparent),
      if (!_busy && _searched.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 2, 12, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('${_hits.length}${_hits.length >= 500 ? '+' : ''} results in ${byFile.length} files',
                style: XC.ui(11.5, color: XC.faint)),
          ),
        ),
      Expanded(
        child: ListView(children: [
          for (final e in byFile.entries) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 2),
              child: Row(children: [
                Icon(fileVisual(e.key).icon, size: 15, color: fileVisual(e.key).color),
                const SizedBox(width: 6),
                Expanded(child: Text(e.key, style: XC.ui(12.5, weight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
                Text('${e.value.length}', style: XC.ui(11, color: XC.faint)),
              ]),
            ),
            for (final h in e.value)
              InkWell(
                onTap: () => widget.onOpen(h),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(32, 3, 10, 3),
                  child: Row(children: [
                    SizedBox(width: 38, child: Text('${h.row + 1}', style: XC.mono(11, color: XC.faint))),
                    Expanded(child: _highlight(h.line.trimLeft(), _searched)),
                  ]),
                ),
              ),
          ],
        ]),
      ),
    ]);
  }

  Widget _highlight(String line, String q) {
    if (_regex || q.isEmpty) return Text(line, style: XC.mono(12), maxLines: 1, overflow: TextOverflow.ellipsis);
    final i = _case ? line.indexOf(q) : line.toLowerCase().indexOf(q.toLowerCase());
    if (i < 0) return Text(line, style: XC.mono(12), maxLines: 1, overflow: TextOverflow.ellipsis);
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: line.substring(0, i), style: XC.mono(12)),
        TextSpan(
            text: line.substring(i, i + q.length),
            style: XC.mono(12, color: Colors.black).copyWith(backgroundColor: const Color(0xFFFFCB6B))),
        TextSpan(text: line.substring(i + q.length), style: XC.mono(12)),
      ]),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
