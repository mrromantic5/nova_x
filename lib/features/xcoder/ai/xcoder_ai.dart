// lib/features/xcoder/ai/xcoder_ai.dart
//
// NOVA inside X Coder (Premium). 3.11.1: answers come from NOVA Coder
// (backend/nova-coder-worker, streamed, with the project as context); the
// NOVA AI Worker's /code endpoint is the fallback while NOVA Coder isn't
// deployed. A line diff lets the developer review every change before it
// touches the file. Answers are only ever inserted as text — never executed.

import 'package:dio/dio.dart';

import '../../../core/services/rewards_entitlements.dart';
import '../../nova/services/nova_api.dart';
import '../editor/ace_editor.dart';
import 'nova_coder_client.dart';

enum XAiTask {
  generate('generate', 'Generate', 'Write new code from a description'),
  complete('complete', 'Complete', 'Continue the code at the cursor'),
  explain('explain', 'Explain', 'What does this code do?'),
  fix('fix', 'Fix', 'Fix bugs and the problems the editor found'),
  debug('debug', 'Debug', 'Find the cause of a bug or error, step by step'),
  refactor('refactor', 'Refactor', 'Cleaner code, same behaviour'),
  comment('comment', 'Comment', 'Add useful comments and docs'),
  tests('tests', 'Tests', 'Write unit tests'),
  optimize('optimize', 'Optimize', 'Faster, leaner code'),
  review('review', 'Review', 'Senior-engineer code review'),
  security('security', 'Security', 'Audit for vulnerabilities (OWASP)'),
  docs('docs', 'Docs', 'README-style documentation'),
  ask('ask', 'Ask', 'Any question about the code');

  const XAiTask(this.wire, this.label, this.hint);
  final String wire;
  final String label;
  final String hint;

  /// Tasks whose answer is code meant to go into the file.
  bool get editsCode => this == generate || this == complete || this == fix || this == debug ||
      this == refactor || this == comment || this == optimize;
}

class XAiRequest {
  XAiRequest({
    required this.task,
    required this.fileName,
    required this.language,
    this.instruction = '',
    this.code = '',
    this.selection = '',
    this.before = '',
    this.after = '',
    this.diagnostics = const [],
    this.files = const [],
  });

  final XAiTask task;
  final String fileName;
  final String language;
  final String instruction;
  final String code;
  final String selection;
  final String before;
  final String after;
  final List<AceAnnotation> diagnostics;
  final List<({String name, String snippet})> files;

  static const int maxCode = 24000;
  static const int maxSelection = 12000;

  Map<String, Object?> toJson() => {
        'task': task.wire,
        'fileName': fileName,
        'language': language,
        if (instruction.trim().isNotEmpty) 'instruction': instruction.trim(),
        if (code.isNotEmpty) 'code': code.length > maxCode ? code.substring(0, maxCode) : code,
        if (selection.isNotEmpty) 'selection': selection.length > maxSelection ? selection.substring(0, maxSelection) : selection,
        if (before.isNotEmpty) 'before': before.length > 4000 ? before.substring(before.length - 4000) : before,
        if (after.isNotEmpty) 'after': after.length > 4000 ? after.substring(0, 4000) : after,
        if (diagnostics.isNotEmpty)
          'diagnostics': [
            for (final d in diagnostics.take(30)) {'row': d.row, 'type': d.type, 'text': d.text}
          ],
        if (files.isNotEmpty)
          'files': [
            for (final f in files.take(6)) {'name': f.name, 'snippet': f.snippet.length > 3000 ? f.snippet.substring(0, 3000) : f.snippet}
          ],
      };
}

class XCoderAi {
  XCoderAi({NovaApiClient? client, NovaCoderClient? coder})
      : _client = client ?? NovaApiClient(),
        _coder = coder ?? NovaCoderClient();

  final NovaApiClient _client;
  final NovaCoderClient _coder;
  CancelToken? _cancel;

  static bool get available => RewardsEntitlements.isPremium;

  /// The engine that answered last ('NOVA Coder' or 'NOVA AI').
  String engine = 'NOVA Coder';

  /// Why the last answer came from NOVA AI instead of NOVA Coder (null when
  /// NOVA Coder answered).
  String? fallbackNote;

  /// NOVA Coder errors that NOVA AI must not paper over: the user has to act
  /// (buy Premium, wait for tomorrow's quota, send less) or stopped it.
  static const _noFallback = {'premium', 'quota', 'cancelled', 'too_large', 'bad_request'};

  static String defaultPrompt(XAiTask t) => switch (t) {
        XAiTask.generate => 'Write the code described.',
        XAiTask.complete => 'Continue the code at the cursor.',
        XAiTask.explain => 'Explain this code.',
        XAiTask.fix => 'Fix the bugs and the problems the editor found in this code.',
        XAiTask.debug => 'Help me debug this code.',
        XAiTask.refactor => 'Refactor this code.',
        XAiTask.comment => 'Add documentation comments to this code.',
        XAiTask.tests => 'Write unit tests for this code.',
        XAiTask.optimize => 'Optimize this code.',
        XAiTask.review => 'Review this code.',
        XAiTask.security => 'Audit this code for security issues.',
        XAiTask.docs => 'Write documentation for this code.',
        XAiTask.ask => 'Help me with this code.',
      };

  /// Runs a task. [onDelta] gets the growing answer while it streams.
  /// [context] is the project context (see the Worker's contextBlock).
  Future<NovaCodeResult> run(
    XAiRequest r, {
    void Function(String textSoFar)? onDelta,
    Map<String, Object?>? context,
    List<Map<String, String>> history = const [],
  }) async {
    _cancel?.cancel();
    final token = _cancel = CancelToken();
    try {
      final prompt = r.instruction.trim().isEmpty ? defaultPrompt(r.task) : r.instruction.trim();
      final task = switch (r.task) {
        XAiTask.ask => 'chat',
        XAiTask.complete => 'generate',
        _ => r.task.wire,
      };
      final buf = StringBuffer();
      fallbackNote = null;
      try {
        await for (final d in _coder.chatStream(
          messages: [...history, {'role': 'user', 'content': prompt}],
          task: task,
          context: context ?? _contextFrom(r),
          cancel: token,
        )) {
          if (d.done) break;
          buf.write(d.text);
          onDelta?.call(buf.toString());
        }
        engine = 'NOVA Coder';
        final reply = buf.toString().trim();
        if (reply.isEmpty) throw const CoderException('upstream', 'NOVA Coder sent an empty answer.');
        final b = NovaCodeResult.firstBlock(reply);
        return NovaCodeResult(reply: reply, code: b.$2, language: b.$1);
      } on CoderException catch (e) {
        // NOVA Coder couldn't answer (not deployed, account check failed,
        // Groq busy, offline…) and nothing was shown yet: answer with NOVA AI
        // instead of leaving the user with an error.
        if (_noFallback.contains(e.code) || buf.isNotEmpty) rethrow;
        engine = 'NOVA AI';
        fallbackNote = 'Answered by NOVA AI — NOVA Coder: ${e.message}';
        return await _client.code(r.toJson(), cancel: token);
      }
    } finally {
      if (identical(_cancel, token)) _cancel = null;
    }
  }

  static Map<String, Object?> _contextFrom(XAiRequest r) => {
        'activeFile': {
          'path': r.fileName,
          'language': r.language,
          if (r.code.isNotEmpty) 'content': r.code,
          if (r.selection.isNotEmpty) 'selection': r.selection,
        },
        if (r.diagnostics.isNotEmpty)
          'diagnostics': [
            for (final d in r.diagnostics) {'path': r.fileName, 'row': d.row, 'type': d.type, 'text': d.text}
          ],
        if (r.files.isNotEmpty) 'files': [for (final f in r.files) {'path': f.name, 'content': f.snippet}],
      };

  void cancel() {
    _cancel?.cancel();
    _cancel = null;
  }
}

enum DiffOp { same, add, remove }

class DiffLine {
  const DiffLine(this.op, this.text, {this.oldNo, this.newNo});
  final DiffOp op;
  final String text;
  final int? oldNo;
  final int? newNo;
}

/// Line diff (LCS). Large inputs fall back to a whole-block replace so the
/// phone never freezes.
List<DiffLine> lineDiff(String a, String b, {int maxCells = 1000000}) {
  final x = a.split('\n'), y = b.split('\n');
  // trim common prefix / suffix first — most edits are local
  var pre = 0;
  while (pre < x.length && pre < y.length && x[pre] == y[pre]) {
    pre++;
  }
  var suf = 0;
  while (suf < x.length - pre && suf < y.length - pre && x[x.length - 1 - suf] == y[y.length - 1 - suf]) {
    suf++;
  }
  final xs = x.sublist(pre, x.length - suf), ys = y.sublist(pre, y.length - suf);
  final out = <DiffLine>[];
  for (var i = 0; i < pre; i++) {
    out.add(DiffLine(DiffOp.same, x[i], oldNo: i + 1, newNo: i + 1));
  }
  final n = xs.length, m = ys.length;
  if (n * m > maxCells) {
    for (var i = 0; i < n; i++) {
      out.add(DiffLine(DiffOp.remove, xs[i], oldNo: pre + i + 1));
    }
    for (var j = 0; j < m; j++) {
      out.add(DiffLine(DiffOp.add, ys[j], newNo: pre + j + 1));
    }
  } else {
    // LCS table
    final t = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
    for (var i = n - 1; i >= 0; i--) {
      for (var j = m - 1; j >= 0; j--) {
        t[i][j] = xs[i] == ys[j] ? t[i + 1][j + 1] + 1 : (t[i + 1][j] >= t[i][j + 1] ? t[i + 1][j] : t[i][j + 1]);
      }
    }
    var i = 0, j = 0;
    while (i < n && j < m) {
      if (xs[i] == ys[j]) {
        out.add(DiffLine(DiffOp.same, xs[i], oldNo: pre + i + 1, newNo: pre + j + 1));
        i++;
        j++;
      } else if (t[i + 1][j] >= t[i][j + 1]) {
        out.add(DiffLine(DiffOp.remove, xs[i], oldNo: pre + i + 1));
        i++;
      } else {
        out.add(DiffLine(DiffOp.add, ys[j], newNo: pre + j + 1));
        j++;
      }
    }
    while (i < n) {
      out.add(DiffLine(DiffOp.remove, xs[i], oldNo: pre + i + 1));
      i++;
    }
    while (j < m) {
      out.add(DiffLine(DiffOp.add, ys[j], newNo: pre + j + 1));
      j++;
    }
  }
  for (var k = 0; k < suf; k++) {
    final oi = x.length - suf + k, ni = y.length - suf + k;
    out.add(DiffLine(DiffOp.same, x[oi], oldNo: oi + 1, newNo: ni + 1));
  }
  return out;
}

/// (+added, −removed)
(int, int) diffStats(List<DiffLine> d) {
  var a = 0, r = 0;
  for (final l in d) {
    if (l.op == DiffOp.add) a++;
    if (l.op == DiffOp.remove) r++;
  }
  return (a, r);
}
