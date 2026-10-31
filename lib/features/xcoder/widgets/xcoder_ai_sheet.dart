// lib/features/xcoder/widgets/xcoder_ai_sheet.dart
//
// NOVA panel of X Coder (Premium): generate, complete, explain, fix,
// refactor, comment, tests, optimize, review, docs, or ask anything about
// the open file. Code answers are shown as a diff first; nothing changes in
// the file until the developer taps Apply / Insert.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/services/subscription_service.dart';
import '../../ai/widgets/nova_markdown_view.dart';
import '../../nova/services/nova_api.dart';
import '../../premium/screens/subscription_screen.dart';
import '../ai/nova_coder_client.dart';
import '../ai/xcoder_ai.dart';
import '../editor/ace_editor.dart';
import 'xcoder_agent_sheet.dart';
import 'xcoder_ui.dart';

abstract class XAiHost {
  String get fileName;
  String get languageLabel;
  List<AceAnnotation> get fileProblems;
  Future<Map<String, dynamic>> editorContext();
  Future<List<({String name, String snippet})>> relatedFiles();
  Future<void> insertCode(String code, {required bool replaceSelection});
  Future<void> replaceFile(String code);
  Future<void> createFile(String suggestedName, String content);

  /// 3.11.1 — project context for NOVA Coder (tree, open file, other open
  /// files, diagnostics, recent terminal / console output).
  Future<Map<String, Object?>> coderContext({required bool includeSelection, bool wholeFile = true});
}

Future<void> showXAiSheet(BuildContext context, XAiHost host, {XAiTask task = XAiTask.ask, String prompt = ''}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => DraggableScrollableSheet(
      initialChildSize: 0.86,
      minChildSize: 0.4,
      maxChildSize: 0.97,
      expand: false,
      builder: (ctx, scroll) => _AiSheet(host: host, initialTask: task, initialPrompt: prompt, scroll: scroll),
    ),
  );
}

class _AiSheet extends StatefulWidget {
  const _AiSheet({required this.host, required this.initialTask, required this.initialPrompt, required this.scroll});
  final XAiHost host;
  final XAiTask initialTask;
  final String initialPrompt;
  final ScrollController scroll;

  @override
  State<_AiSheet> createState() => _AiSheetState();
}

class _Turn {
  _Turn(this.task, this.prompt);
  final XAiTask task;
  final String prompt;
  NovaCodeResult? result;
  String? error;
  String original = ''; // what the code would replace (for the diff)
  bool selectionScope = false;
  bool applied = false;
  String streaming = '';
  bool needsPremium = false;
  String? note; // e.g. "Answered by NOVA AI — …"
}

class _AiSheetState extends State<_AiSheet> {
  final _ai = XCoderAi();
  late XAiTask _task = widget.initialTask;
  late final _prompt = TextEditingController(text: widget.initialPrompt);
  final List<_Turn> _turns = [];
  bool _busy = false;
  String _selection = '';
  bool _useSelection = true;

  @override
  void initState() {
    super.initState();
    widget.host.editorContext().then((c) {
      if (mounted) setState(() => _selection = (c['selection'] as String?) ?? '');
    });
    if (XCoderAi.available &&
        ((widget.initialTask != XAiTask.ask && widget.initialTask != XAiTask.generate) || widget.initialPrompt.trim().isNotEmpty)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _send());
    }
  }

  @override
  void dispose() {
    _ai.cancel();
    _prompt.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_busy) return;
    final text = _prompt.text.trim();
    if ((_task == XAiTask.generate || _task == XAiTask.ask) && text.isEmpty) {
      xToast(context, _task == XAiTask.generate ? 'Describe the code you want.' : 'Type your question.');
      return;
    }
    final ctx = await widget.host.editorContext();
    final value = (ctx['value'] as String?) ?? '';
    final sel = _useSelection ? ((ctx['selection'] as String?) ?? '') : '';
    if (value.length > XAiRequest.maxCode && sel.isEmpty && _task != XAiTask.generate && _task != XAiTask.complete) {
      if (mounted) xToast(context, 'This file is large — select the part NOVA should work on.', error: true);
      return;
    }
    final turn = _Turn(_task, text)
      ..selectionScope = sel.isNotEmpty
      ..original = sel.isNotEmpty ? sel : value;
    setState(() {
      _turns.add(turn);
      _busy = true;
      _prompt.clear();
    });
    _scrollToEnd();
    try {
      final related = _task == XAiTask.generate || _task == XAiTask.fix || _task == XAiTask.tests
          ? await widget.host.relatedFiles()
          : const <({String name, String snippet})>[];
      final context = await widget.host.coderContext(includeSelection: sel.isNotEmpty);
      // earlier answers in this panel make it a conversation
      final history = <Map<String, String>>[
        for (final p in _turns.where((x) => x != turn && x.result != null).toList().reversed.take(4).toList().reversed) ...[
          {'role': 'user', 'content': p.prompt.isEmpty ? XCoderAi.defaultPrompt(p.task) : p.prompt},
          {'role': 'assistant', 'content': p.result!.reply.length > 6000 ? p.result!.reply.substring(0, 6000) : p.result!.reply},
        ],
      ];
      turn.result = await _ai.run(XAiRequest(
        task: _task,
        fileName: widget.host.fileName,
        language: widget.host.languageLabel,
        instruction: text,
        code: _task == XAiTask.complete ? '' : value,
        selection: sel,
        before: _task == XAiTask.complete ? _beforeCursor(ctx) : '',
        after: _task == XAiTask.complete ? _afterCursor(ctx) : '',
        diagnostics: _task == XAiTask.fix || _task == XAiTask.review ? widget.host.fileProblems : const [],
        files: related,
      ),
          context: context,
          history: history,
          onDelta: (text) {
            if (!mounted) return;
            setState(() => turn.streaming = text);
            _scrollToEnd();
          });
      turn.note = _ai.fallbackNote;
    } on CoderException catch (e) {
      if (e.code != 'cancelled') turn.error = e.message;
      turn.needsPremium = e.needsPremium;
    } on NovaApiException catch (e) {
      turn.error = e.userMessage;
    } catch (_) {
      turn.error = 'NOVA couldn’t answer. Check your connection and try again.';
    }
    if (!mounted) return;
    setState(() => _busy = false);
    _scrollToEnd();
  }

  static String _beforeCursor(Map<String, dynamic> c) {
    final before = (c['before'] as String?) ?? '';
    final line = (c['line'] as String?) ?? '';
    final col = ((c['column'] as num?) ?? 0).toInt();
    final head = line.substring(0, col < 0 ? 0 : (col > line.length ? line.length : col));
    return before.isEmpty ? head : '$before\n$head';
  }

  static String _afterCursor(Map<String, dynamic> c) {
    final line = (c['line'] as String?) ?? '';
    final col = ((c['column'] as num?) ?? 0).toInt();
    final tail = col >= line.length ? '' : line.substring(col < 0 ? 0 : col);
    final after = (c['after'] as String?) ?? '';
    return after.isEmpty ? tail : '$tail\n$after';
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.scroll.hasClients) {
        widget.scroll.animateTo(widget.scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _review(_Turn t) async {
    final code = t.result!.code;
    final diff = lineDiff(t.original, code);
    final apply = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: XC.side,
      builder: (ctx) => XDiffSheet(diff: diff, title: t.selectionScope ? 'Selection' : widget.host.fileName),
    );
    if (apply == true) await _apply(t, replace: true);
  }

  Future<void> _apply(_Turn t, {required bool replace}) async {
    final code = t.result!.code;
    if (replace && !t.selectionScope && t.task != XAiTask.complete && t.task != XAiTask.generate) {
      await widget.host.replaceFile(code);
    } else {
      await widget.host.insertCode(code, replaceSelection: replace && t.selectionScope);
    }
    setState(() => t.applied = true);
    if (mounted) xToast(context, replace ? 'Applied — Undo (↶) reverts it' : 'Inserted at the cursor');
  }

  String _suggestTestName() {
    final n = widget.host.fileName;
    final dot = n.lastIndexOf('.');
    final base = dot > 0 ? n.substring(0, dot) : n;
    final ext = dot > 0 ? n.substring(dot) : '.txt';
    return switch (ext) {
      '.py' => 'test_$base.py',
      '.dart' => '${base}_test.dart',
      '.go' => '${base}_test.go',
      _ => '$base.test$ext',
    };
  }

  // ── UI ────────────────────────────────────────────────────────────────

  Widget _upsell() => Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
        child: Column(children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [const Color(0xFF7C4DFF).withOpacity(0.25), const Color(0xFF00D4FF).withOpacity(0.15)]),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: XC.border),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.auto_awesome_rounded, color: Color(0xFFFFD54F)),
                const SizedBox(width: 8),
                Text('NOVA in X Coder is Premium', style: XC.ui(16, weight: FontWeight.w800)),
              ]),
              const SizedBox(height: 12),
              for (final l in const [
                'Generate code from a description',
                'Fix errors the editor finds — with a diff before anything changes',
                'Explain, refactor, comment and optimize',
                'Write unit tests and documentation',
                'Senior-engineer code reviews',
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.check_rounded, size: 18, color: XC.ok),
                    const SizedBox(width: 8),
                    Expanded(child: Text(l, style: XC.ui(13.5))),
                  ]),
                ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => const SubscriptionScreen()));
                    await SubscriptionService.fetchStatus();
                    if (mounted) setState(() {});
                  },
                  child: const Text('See Premium'),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          Text('The editor, linting, autocomplete, terminal and preview are free and work offline.',
              style: XC.ui(12, color: XC.faint), textAlign: TextAlign.center),
        ]),
      );

  Widget _turnView(_Turn t) {
    final r = t.result;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: XC.accent.withOpacity(0.15), borderRadius: BorderRadius.circular(6)),
            child: Text(t.task.label, style: XC.ui(11.5, color: XC.accent, weight: FontWeight.w700)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(t.prompt.isEmpty ? (t.selectionScope ? 'selection' : widget.host.fileName) : t.prompt,
                style: XC.ui(13, color: XC.dim), maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
        ]),
        const SizedBox(height: 8),
        if (r == null && t.error == null && t.streaming.isNotEmpty) ...[
          NovaMarkdownView(text: t.streaming, fontSize: 13.5),
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: SizedBox(width: 22, height: 3, child: LinearProgressIndicator(color: XC.accent, backgroundColor: Colors.transparent)),
          ),
        ],
        if (r == null && t.error == null && t.streaming.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Row(children: [
              SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: XC.accent)),
              SizedBox(width: 10),
              Text('NOVA is working…', style: TextStyle(color: XC.dim)),
            ]),
          ),
        if (r != null && t.note != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.info_outline_rounded, size: 14, color: XC.faint),
              const SizedBox(width: 6),
              Expanded(child: Text(t.note!, style: XC.ui(11.5, color: XC.faint))),
            ]),
          ),
        if (t.error != null && t.needsPremium)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: FilledButton.icon(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SubscriptionScreen())),
              icon: const Icon(Icons.workspace_premium_rounded, size: 18),
              label: const Text('Get NOVA X Premium'),
            ),
          ),
        if (t.error != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: XC.error.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
            child: Text(t.error!, style: XC.ui(13, color: XC.error)),
          ),
        if (r != null) ...[
          NovaMarkdownView(text: r.reply, fontSize: 13.5),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 6, children: [
            if (r.hasCode && t.task.editsCode && t.task != XAiTask.generate && t.task != XAiTask.complete)
              _action(Icons.difference_outlined, t.applied ? 'Applied' : 'Review & apply', t.applied ? null : () => _review(t), primary: true),
            if (r.hasCode && (t.task == XAiTask.generate || t.task == XAiTask.complete))
              _action(Icons.input_rounded, 'Insert at cursor', () => _apply(t, replace: false), primary: true),
            if (r.hasCode && t.task == XAiTask.generate && _selection.isNotEmpty)
              _action(Icons.swap_horiz_rounded, 'Replace selection', () async {
                await widget.host.insertCode(r.code, replaceSelection: true);
                if (mounted) xToast(context, 'Replaced — Undo (↶) reverts it');
              }),
            if (r.hasCode && (t.task == XAiTask.tests || t.task == XAiTask.generate))
              _action(Icons.note_add_outlined, 'New file', () async {
                await widget.host.createFile(t.task == XAiTask.tests ? _suggestTestName() : 'snippet.${widget.host.fileName.split('.').last}', r.code);
                if (mounted) Navigator.pop(context);
              }),
            if (r.hasCode && t.task == XAiTask.docs)
              _action(Icons.note_add_outlined, 'Save as README', () async {
                await widget.host.createFile('README.md', r.reply);
                if (mounted) Navigator.pop(context);
              }),
            _action(Icons.copy_rounded, r.hasCode ? 'Copy code' : 'Copy', () {
              Clipboard.setData(ClipboardData(text: r.hasCode ? r.code : r.reply));
              xToast(context, 'Copied');
            }),
          ]),
        ],
        const Divider(color: XC.border, height: 22),
      ]),
    );
  }

  Widget _action(IconData i, String label, VoidCallback? onTap, {bool primary = false}) => primary
      ? FilledButton.icon(
          onPressed: onTap,
          icon: Icon(i, size: 16),
          label: Text(label),
          style: FilledButton.styleFrom(visualDensity: VisualDensity.compact, backgroundColor: XC.status),
        )
      : OutlinedButton.icon(
          onPressed: onTap,
          icon: Icon(i, size: 16),
          label: Text(label),
          style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: XC.text, side: const BorderSide(color: XC.border)),
        );

  @override
  Widget build(BuildContext context) {
    final premium = XCoderAi.available;
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      decoration: const BoxDecoration(color: XC.side, borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      child: Column(children: [
        const SizedBox(height: 8),
        Container(width: 38, height: 4, decoration: BoxDecoration(color: XC.border, borderRadius: BorderRadius.circular(2))),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 4),
          child: Row(children: [
            const Icon(Icons.auto_awesome_rounded, color: Color(0xFFFFD54F), size: 20),
            const SizedBox(width: 8),
            Text('NOVA Coder', style: XC.ui(16, weight: FontWeight.w800)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFFFFD54F), Color(0xFFFFA000)]), borderRadius: BorderRadius.circular(5)),
              child: Text('PREMIUM', style: XC.ui(9.5, color: Colors.black87, weight: FontWeight.w800)),
            ),
            const Spacer(),
            Flexible(
              child: Text('${widget.host.fileName} · ${widget.host.languageLabel}',
                  style: XC.ui(11.5, color: XC.faint), overflow: TextOverflow.ellipsis),
            ),
            if (widget.host is XAgentHost)
              IconButton(
                tooltip: 'NOVA Agent — change several files',
                onPressed: () {
                  final host = widget.host as XAgentHost;
                  final nav = Navigator.of(context);
                  nav.pop();
                  showXAgentSheet(nav.context, host);
                },
                icon: const Icon(Icons.smart_toy_outlined, color: XC.accent),
              ),
            IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded, color: XC.dim)),
          ]),
        ),
        if (!premium)
          Expanded(child: ListView(controller: widget.scroll, children: [_upsell()]))
        else ...[
          SizedBox(
            height: 40,
            child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
              for (final t in XAiTask.values)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(t.label),
                    selected: _task == t,
                    onSelected: (_) => setState(() => _task = t),
                    labelStyle: XC.ui(12.5, color: _task == t ? Colors.white : XC.dim, weight: FontWeight.w600),
                    selectedColor: XC.status,
                    backgroundColor: XC.bg,
                    side: const BorderSide(color: XC.border),
                    visualDensity: VisualDensity.compact,
                    showCheckmark: false,
                  ),
                ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Row(children: [
              Expanded(child: Text(_task.hint, style: XC.ui(12, color: XC.faint))),
              if (_selection.isNotEmpty && _task != XAiTask.generate && _task != XAiTask.complete)
                FilterChip(
                  label: Text(_useSelection ? 'Selection (${_selection.length} chars)' : 'Whole file'),
                  selected: _useSelection,
                  onSelected: (v) => setState(() => _useSelection = v),
                  labelStyle: XC.ui(11.5, color: XC.text),
                  backgroundColor: XC.bg,
                  selectedColor: XC.tabActive,
                  side: const BorderSide(color: XC.border),
                  visualDensity: VisualDensity.compact,
                  showCheckmark: false,
                ),
            ]),
          ),
          Expanded(
            child: _turns.isEmpty
                ? ListView(controller: widget.scroll, padding: const EdgeInsets.all(24), children: [
                    const Icon(Icons.code_rounded, size: 36, color: XC.faint),
                    const SizedBox(height: 10),
                    Text(
                      'Pick a task and tap Send. NOVA sees this file (or your selection) and the problems the editor found. '
                      'You review every change before it’s applied.',
                      style: XC.ui(13, color: XC.dim),
                      textAlign: TextAlign.center,
                    ),
                  ])
                : ListView(controller: widget.scroll, children: [for (final t in _turns) _turnView(t)]),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(12, 8, 8, 10 + bottom),
            decoration: const BoxDecoration(border: Border(top: BorderSide(color: XC.border))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(
                child: TextField(
                  controller: _prompt,
                  minLines: 1,
                  maxLines: 5,
                  style: XC.ui(14),
                  textInputAction: TextInputAction.newline,
                  decoration: InputDecoration(
                    hintText: switch (_task) {
                      XAiTask.generate => 'e.g. a responsive navbar with a dark-mode toggle',
                      XAiTask.ask => 'Ask about this code…',
                      _ => 'Optional: extra instructions',
                    },
                    hintStyle: XC.ui(13, color: XC.faint),
                    filled: true,
                    fillColor: XC.bg,
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              _busy
                  ? IconButton(
                      onPressed: () {
                        _ai.cancel();
                        setState(() {
                          _busy = false;
                          if (_turns.isNotEmpty && _turns.last.result == null) _turns.last.error = 'Stopped.';
                        });
                      },
                      icon: const Icon(Icons.stop_circle_outlined, color: XC.error, size: 30),
                    )
                  : IconButton(onPressed: _send, icon: const Icon(Icons.send_rounded, color: XC.accent, size: 26)),
            ]),
          ),
        ],
      ]),
    );
  }
}

class XDiffSheet extends StatelessWidget {
  const XDiffSheet({super.key, required this.diff, required this.title});
  final List<DiffLine> diff;
  final String title;

  @override
  Widget build(BuildContext context) {
    final (add, rem) = diffStats(diff);
    // show changes with 3 lines of context
    final keep = List<bool>.filled(diff.length, false);
    for (var i = 0; i < diff.length; i++) {
      if (diff[i].op != DiffOp.same) {
        for (var k = (i - 3).clamp(0, diff.length - 1); k <= (i + 3).clamp(0, diff.length - 1); k++) {
          keep[k] = true;
        }
      }
    }
    final rows = <Widget>[];
    var gap = false;
    for (var i = 0; i < diff.length; i++) {
      if (!keep[i]) {
        if (!gap) rows.add(Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Text('  ⋯', style: XC.mono(12, color: XC.faint))));
        gap = true;
        continue;
      }
      gap = false;
      final d = diff[i];
      final (bg, sign, color) = switch (d.op) {
        DiffOp.add => (XC.added, '+', XC.ok),
        DiffOp.remove => (XC.removed, '−', XC.error),
        DiffOp.same => (Colors.transparent, ' ', XC.dim),
      };
      rows.add(Container(
        color: bg,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 34, child: Text('${d.oldNo ?? ''}', style: XC.mono(10.5, color: XC.faint), textAlign: TextAlign.right)),
          SizedBox(width: 34, child: Text('${d.newNo ?? ''}', style: XC.mono(10.5, color: XC.faint), textAlign: TextAlign.right)),
          SizedBox(width: 16, child: Text(' $sign', style: XC.mono(12, color: color))),
          Expanded(child: Text(d.text, style: XC.mono(12, color: d.op == DiffOp.same ? XC.dim : XC.text))),
        ]),
      ));
    }
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.85,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
            child: Row(children: [
              const Icon(Icons.difference_outlined, color: XC.accent),
              const SizedBox(width: 8),
              Expanded(child: Text('Changes to $title', style: XC.ui(15, weight: FontWeight.w700), overflow: TextOverflow.ellipsis)),
              Text('+$add', style: XC.mono(12.5, color: XC.ok, weight: FontWeight.w700)),
              const SizedBox(width: 8),
              Text('−$rem', style: XC.mono(12.5, color: XC.error, weight: FontWeight.w700)),
              const SizedBox(width: 8),
            ]),
          ),
          Expanded(
            child: add + rem == 0
                ? Center(child: Text('No changes — NOVA returned the same code.', style: XC.ui(13, color: XC.dim)))
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minWidth: MediaQuery.of(context).size.width, maxWidth: MediaQuery.of(context).size.width > 1400 ? MediaQuery.of(context).size.width : 1400),
                      child: ListView(children: rows),
                    ),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
            child: Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, false),
                  style: OutlinedButton.styleFrom(foregroundColor: XC.text, side: const BorderSide(color: XC.border)),
                  child: const Text('Discard'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: add + rem == 0 ? null : () => Navigator.pop(context, true),
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Apply'),
                  style: FilledButton.styleFrom(backgroundColor: XC.status),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
