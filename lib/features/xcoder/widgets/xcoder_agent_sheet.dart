// lib/features/xcoder/widgets/xcoder_agent_sheet.dart
//
// NOVA Agent (Premium): describe a change in plain words — "add a dark mode
// toggle", "fix the login form validation", "split app.js into modules" —
// and NOVA Coder works on the whole project like a coding agent:
//   1. it reads the file tree and asks for the files it needs (the app sends
//      them, up to 3 rounds),
//   2. it returns a plan: summary, steps, exact file edits and suggested
//      terminal commands,
//   3. you review every file as a diff, untick what you don't want, and
//      apply. Commands run only when you tap them.

import 'package:flutter/material.dart';

import '../../ai/widgets/nova_markdown_view.dart';
import '../../premium/screens/subscription_screen.dart';
import '../ai/nova_coder_client.dart';
import '../ai/xcoder_ai.dart';
import 'xcoder_ai_sheet.dart';
import 'xcoder_ui.dart';

abstract class XAgentHost {
  String get projectName;
  Future<List<String>> projectFiles();
  Future<String?> readProjectFile(String rel);
  Future<Map<String, Object?>> coderContext({required bool includeSelection, bool wholeFile = true});

  /// Applies the edits; returns a line per edit ("✓ app.js updated", "✗ …").
  Future<List<String>> applyAgentEdits(List<AgentEdit> edits);
  Future<void> runInTerminal(String command);
}

Future<void> showXAgentSheet(BuildContext context, XAgentHost host, {String instruction = ''}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.97,
      expand: false,
      builder: (ctx, scroll) => _AgentSheet(host: host, scroll: scroll, initial: instruction),
    ),
  );
}

class _Run {
  _Run(this.instruction);
  final String instruction;
  final List<String> log = [];
  AgentResult? plan;
  String? error;
  bool needsPremium = false;
  final Set<int> skipped = {};
  List<String>? applied;
  final Map<int, String> previews = {}; // edit index → new text (for diffs)
  final Map<int, String> originals = {};
  final Map<int, String> problems = {};
}

class _AgentSheet extends StatefulWidget {
  const _AgentSheet({required this.host, required this.scroll, required this.initial});
  final XAgentHost host;
  final ScrollController scroll;
  final String initial;

  @override
  State<_AgentSheet> createState() => _AgentSheetState();
}

class _AgentSheetState extends State<_AgentSheet> {
  final _coder = NovaCoderClient();
  late final _input = TextEditingController(text: widget.initial);
  final List<_Run> _runs = [];
  bool _busy = false;

  static const _examples = [
    'Add a dark mode toggle that remembers the choice',
    'Find and fix the bugs in this project',
    'Make the page responsive on phones',
    'Add form validation with clear error messages',
    'Write a README for this project',
  ];

  @override
  void dispose() {
    _coder.dispose();
    _input.dispose();
    super.dispose();
  }

  void _toEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.scroll.hasClients) {
        widget.scroll.animateTo(widget.scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _start() async {
    final typed = _input.text.trim();
    if (typed.isEmpty || _busy) return;
    // Answering the agent's question continues the same task.
    final last = _runs.isEmpty ? null : _runs.last;
    final text = last?.plan?.type == 'question'
        ? '${last!.instruction}\n\nYour question: ${last.plan!.question}\nMy answer: $typed'
        : typed;
    if (!XCoderAi.available) {
      setState(() => _runs.add(_Run(text)
        ..error = 'NOVA Agent is part of NOVA X Premium.'
        ..needsPremium = true));
      return;
    }
    final run = _Run(text);
    setState(() {
      _runs.add(run);
      _busy = true;
      _input.clear();
    });
    _toEnd();
    try {
      final base = await widget.host.coderContext(includeSelection: true);
      final files = <Map<String, String>>[];
      final history = <Map<String, String>>[];
      for (final r in _runs.where((r) => r != run && r.plan != null).toList().reversed.take(2).toList().reversed) {
        history
          ..add({'role': 'user', 'content': r.instruction})
          ..add({'role': 'assistant', 'content': r.plan!.summary});
      }
      run.log.add('Reading the project (${(base['tree'] as List?)?.length ?? 0} files)…');
      setState(() {});
      for (var round = 1; round <= 4; round++) {
        final res = await _coder.agent(
          instruction: text,
          context: {...base, if (files.isNotEmpty) 'files': files},
          history: history,
          round: round,
        );
        if (!mounted) return;
        if (res.type == 'need_files') {
          final names = res.files.where((f) => !files.any((x) => x['path'] == f)).toList();
          if (names.isEmpty) break;
          run.log.add('Reading ${names.join(', ')}${res.why.isEmpty ? '' : ' — ${res.why}'}');
          setState(() {});
          for (final n in names) {
            final t = await widget.host.readProjectFile(n);
            files.add({'path': n, 'content': t ?? '(this file does not exist)'});
          }
          continue;
        }
        run.plan = res;
        if (res.type == 'plan') await _preview(run);
        break;
      }
      if (run.plan == null) run.error = 'NOVA Coder couldn’t finish a plan. Try a more specific task.';
    } on CoderException catch (e) {
      if (e.code != 'cancelled') run.error = e.message;
      run.needsPremium = e.needsPremium;
    } catch (e) {
      run.error = 'Something went wrong: $e';
    }
    if (!mounted) return;
    setState(() => _busy = false);
    _toEnd();
  }

  /// Works out the new text of every edit now, so problems show before Apply.
  Future<void> _preview(_Run run) async {
    final edits = run.plan!.edits;
    for (var i = 0; i < edits.length; i++) {
      final e = edits[i];
      final old = await widget.host.readProjectFile(e.path);
      run.originals[i] = old ?? '';
      switch (e.action) {
        case 'create' || 'replace':
          run.previews[i] = e.content ?? '';
          if (e.action == 'create' && old != null) run.problems[i] = 'File exists — it will be replaced';
        case 'patch':
          if (old == null) {
            run.problems[i] = 'File not found';
            run.skipped.add(i);
          } else {
            final (text, err) = applyPatches(old, e.patches);
            if (text == null) {
              run.problems[i] = err!;
              run.skipped.add(i);
            } else {
              run.previews[i] = text;
            }
          }
        case 'delete':
          if (old == null) {
            run.problems[i] = 'File not found';
            run.skipped.add(i);
          }
          run.previews[i] = '';
      }
    }
  }

  Future<void> _apply(_Run run) async {
    final edits = <AgentEdit>[];
    for (var i = 0; i < run.plan!.edits.length; i++) {
      if (run.skipped.contains(i)) continue;
      final e = run.plan!.edits[i];
      // apply the previewed text (patches already resolved)
      edits.add(e.action == 'patch' ? AgentEdit(path: e.path, action: 'replace', content: run.previews[i]) : e);
    }
    if (edits.isEmpty) {
      xToast(context, 'Nothing selected to apply.');
      return;
    }
    if (edits.any((e) => e.action == 'delete')) {
      final n = edits.where((e) => e.action == 'delete').length;
      if (!await xConfirm(context, 'Delete $n file${n == 1 ? '' : 's'}?', 'The agent’s plan deletes files. They can’t be restored with Undo.')) return;
    }
    final out = await widget.host.applyAgentEdits(edits);
    if (!mounted) return;
    setState(() => run.applied = out);
    xToast(context, 'Applied ${out.where((l) => l.startsWith('✓')).length} change${edits.length == 1 ? '' : 's'}');
  }

  // ── UI ────────────────────────────────────────────────────────────────

  Widget _runView(_Run run) {
    final p = run.plan;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.person_outline_rounded, size: 18, color: XC.dim),
          const SizedBox(width: 8),
          Expanded(child: Text(run.instruction, style: XC.ui(14, weight: FontWeight.w600))),
        ]),
        const SizedBox(height: 8),
        for (final l in run.log)
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 3),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.subdirectory_arrow_right_rounded, size: 14, color: XC.faint),
              const SizedBox(width: 6),
              Expanded(child: Text(l, style: XC.mono(11.5, color: XC.dim))),
            ]),
          ),
        if (p == null && run.error == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Row(children: [
              SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: XC.accent)),
              SizedBox(width: 10),
              Text('NOVA Agent is working on it…', style: TextStyle(color: XC.dim)),
            ]),
          ),
        if (run.error != null) ...[
          if (run.needsPremium)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: FilledButton.icon(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SubscriptionScreen())),
                icon: const Icon(Icons.workspace_premium_rounded, size: 18),
                label: const Text('Get NOVA X Premium'),
              ),
            ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: XC.error.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
            child: Text(run.error!, style: XC.ui(13, color: XC.error)),
          ),
        ],
        if (p != null && p.type == 'question')
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: XC.info.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('NOVA Agent needs to know', style: XC.ui(12, color: XC.info, weight: FontWeight.w700)),
              const SizedBox(height: 4),
              NovaMarkdownView(text: p.question, fontSize: 13.5),
              const SizedBox(height: 6),
              Text('Answer below — your answer is sent with the task.', style: XC.ui(11.5, color: XC.faint)),
            ]),
          ),
        if (p != null && p.type == 'plan') ..._planView(run, p),
        const Divider(color: XC.border, height: 24),
      ]),
    );
  }

  List<Widget> _planView(_Run run, AgentResult p) => [
        NovaMarkdownView(text: p.summary, fontSize: 13.5),
        if (p.steps.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final (i, s) in p.steps.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text('${i + 1}. $s', style: XC.ui(12.5, color: XC.dim)),
            ),
        ],
        if (p.edits.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text('CHANGES (${p.edits.length})', style: XC.ui(11, color: XC.dim, weight: FontWeight.w800)),
          const SizedBox(height: 4),
          for (final (i, e) in p.edits.indexed) _editRow(run, i, e),
          const SizedBox(height: 6),
          run.applied == null
              ? Row(children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _apply(run),
                      icon: const Icon(Icons.done_all_rounded, size: 18),
                      label: Text('Apply ${p.edits.length - run.skipped.length} change${p.edits.length - run.skipped.length == 1 ? '' : 's'}'),
                      style: FilledButton.styleFrom(backgroundColor: XC.status),
                    ),
                  ),
                ])
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  for (final l in run.applied!)
                    Text(l, style: XC.mono(11.5, color: l.startsWith('✓') ? XC.ok : XC.error)),
                  const SizedBox(height: 4),
                  Text('Use Undo in a file to go back, or ask the agent for another change.', style: XC.ui(11.5, color: XC.faint)),
                ]),
        ],
        if (p.commands.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('SUGGESTED COMMANDS', style: XC.ui(11, color: XC.dim, weight: FontWeight.w800)),
          for (final c in p.commands)
            Container(
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
              decoration: BoxDecoration(color: const Color(0xFF070D18), borderRadius: BorderRadius.circular(8), border: Border.all(color: XC.border)),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('\$ ${c.command}', style: XC.mono(12, color: XC.ok)),
                    if (c.why.isNotEmpty) Text(c.why, style: XC.ui(11, color: XC.faint)),
                    if (!c.phone) Text('Runs on a computer / server, not on the phone', style: XC.ui(10.5, color: XC.warning)),
                  ]),
                ),
                if (c.phone)
                  TextButton(
                    onPressed: () async {
                      Navigator.pop(context);
                      await widget.host.runInTerminal(c.command);
                    },
                    child: const Text('Run'),
                  ),
              ]),
            ),
        ],
        if (p.notes.isNotEmpty) ...[
          const SizedBox(height: 10),
          for (final n in p.notes) Text('• $n', style: XC.ui(12, color: XC.dim)),
        ],
      ];

  Widget _editRow(_Run run, int i, AgentEdit e) {
    final on = !run.skipped.contains(i);
    final problem = run.problems[i];
    final (icon, color, verb) = switch (e.action) {
      'create' => (Icons.note_add_outlined, XC.ok, 'create'),
      'delete' => (Icons.delete_outline_rounded, XC.error, 'delete'),
      'patch' => (Icons.difference_outlined, XC.info, 'edit'),
      _ => (Icons.edit_document, XC.warning, 'rewrite'),
    };
    final diff = run.previews.containsKey(i) ? lineDiff(run.originals[i] ?? '', run.previews[i] ?? '') : null;
    final stats = diff == null ? null : diffStats(diff);
    return InkWell(
      onTap: diff == null
          ? null
          : () => showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: XC.side,
                builder: (_) => XDiffSheet(diff: diff, title: e.path),
              ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Checkbox(
            value: on,
            onChanged: run.applied != null || (problem != null && e.action == 'patch')
                ? null
                : (v) => setState(() => v == true ? run.skipped.remove(i) : run.skipped.add(i)),
            visualDensity: VisualDensity.compact,
          ),
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e.path, style: XC.mono(12.5), overflow: TextOverflow.ellipsis),
              Text(problem ?? verb, style: XC.ui(10.5, color: problem != null ? XC.warning : XC.faint)),
            ]),
          ),
          if (stats != null) ...[
            Text('+${stats.$1}', style: XC.mono(11, color: XC.ok)),
            const SizedBox(width: 4),
            Text('−${stats.$2}', style: XC.mono(11, color: XC.error)),
            const Icon(Icons.chevron_right_rounded, size: 18, color: XC.faint),
          ],
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      decoration: const BoxDecoration(color: XC.side, borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      child: Column(children: [
        const SizedBox(height: 8),
        Container(width: 38, height: 4, decoration: BoxDecoration(color: XC.border, borderRadius: BorderRadius.circular(2))),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 4),
          child: Row(children: [
            const Icon(Icons.smart_toy_outlined, color: XC.accent, size: 20),
            const SizedBox(width: 8),
            Text('NOVA Agent', style: XC.ui(16, weight: FontWeight.w800)),
            const SizedBox(width: 8),
            Flexible(child: Text(widget.host.projectName, style: XC.ui(11.5, color: XC.faint), overflow: TextOverflow.ellipsis)),
            const Spacer(),
            IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded, color: XC.dim)),
          ]),
        ),
        Expanded(
          child: _runs.isEmpty
              ? ListView(controller: widget.scroll, padding: const EdgeInsets.all(20), children: [
                  Text('Tell NOVA Agent what to build or fix. It reads your project, plans the change across files and shows you every edit before anything is saved.',
                      style: XC.ui(13.5, color: XC.dim)),
                  const SizedBox(height: 14),
                  for (final ex in _examples)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: OutlinedButton(
                        onPressed: () => setState(() => _input.text = ex),
                        style: OutlinedButton.styleFrom(alignment: Alignment.centerLeft, foregroundColor: XC.text, side: const BorderSide(color: XC.border)),
                        child: Text(ex, style: XC.ui(13)),
                      ),
                    ),
                ])
              : ListView(controller: widget.scroll, children: [for (final r in _runs) _runView(r)]),
        ),
        Container(
          padding: EdgeInsets.fromLTRB(12, 8, 8, 10 + bottom),
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: XC.border))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: TextField(
                controller: _input,
                minLines: 1,
                maxLines: 6,
                style: XC.ui(14),
                decoration: InputDecoration(
                  hintText: 'Describe the change…',
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
                ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)))
                : IconButton(onPressed: _start, icon: const Icon(Icons.send_rounded, color: XC.accent, size: 26)),
          ]),
        ),
      ]),
    );
  }
}
