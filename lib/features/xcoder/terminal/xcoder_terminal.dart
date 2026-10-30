// lib/features/xcoder/terminal/xcoder_terminal.dart
//
// The X Coder terminal. Runs in the project folder:
//  • X Coder commands: help, clear, cd, pwd, open, run, node, serve, history,
//    tree, find-in-files (search), env
//  • Everything else goes to Android's own shell (/system/bin/sh with the
//    built-in toybox tools: ls, cat, mkdir, rm, mv, cp, grep, sed, find, wc,
//    head, tail, sort, diff, md5sum, date, ping…), with pipes and redirects.
//
// It is an app-sandboxed shell, not root and not Termux: there is no
// apt/npm/pip/python/git on a stock phone, and `help` says so.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../run/js_runner.dart';
import '../workspace/xcoder_workspace.dart';

enum TermStyle { input, out, err, info, ok, warn, dim }

class TermLine {
  const TermLine(this.text, this.style);
  final String text;
  final TermStyle style;
}

/// What the terminal asks the IDE to do.
abstract class TerminalHost {
  Future<void> openFile(String rel, {int? line});
  Future<void> runFile(String? rel);
  Future<void> startPreview(String? rel);
  Future<void> refreshExplorer();
  Future<String?> currentFile();
}

class XTerminal extends ChangeNotifier {
  XTerminal(this.project, this.host);

  final XProject project;
  final TerminalHost host;

  final List<TermLine> lines = [];
  final List<String> history = [];
  String cwd = ''; // relative to the project
  Process? _proc;
  StreamSubscription<JsRunLine>? _js;
  bool get busy => _proc != null || _js != null;
  int _histCursor = -1;

  static const int _maxLines = 3000;
  static const Set<String> _unavailable = {
    'apt', 'apt-get', 'pkg', 'npm', 'npx', 'yarn', 'pnpm', 'pip', 'pip3', 'python', 'python3', 'git', 'php',
    'java', 'javac', 'gradle', 'flutter', 'dart', 'go', 'cargo', 'rustc', 'gcc', 'g++', 'clang', 'ruby', 'deno', 'bun',
    'su', 'sudo', 'ssh', 'vim', 'vi', 'nano', 'top', 'htop', 'less', 'more',
  };

  String get prompt => '${project.name}${cwd.isEmpty ? '' : '/$cwd'} \$ ';
  String get _absCwd => cwd.isEmpty ? project.path : '${project.path}/$cwd';

  void _add(String text, [TermStyle style = TermStyle.out]) {
    for (final l in const LineSplitter().convert(text.isEmpty ? ' ' : text)) {
      lines.add(TermLine(l, style));
    }
    if (lines.length > _maxLines) lines.removeRange(0, lines.length - _maxLines);
    notifyListeners();
  }

  void welcome() {
    if (lines.isNotEmpty) return;
    _add('X Coder terminal — ${project.name}', TermStyle.ok);
    _add('Type "help" for commands. Runs in the project folder with Android’s built-in shell tools.', TermStyle.dim);
  }

  void clear() {
    lines.clear();
    notifyListeners();
  }

  /// ↑ / ↓ in the input box.
  String? historyStep(int dir) {
    if (history.isEmpty) return null;
    if (_histCursor == -1) _histCursor = history.length;
    _histCursor = (_histCursor + dir).clamp(0, history.length);
    return _histCursor >= history.length ? '' : history[_histCursor];
  }

  /// Writes to the running program (stdin).
  void sendInput(String text) {
    final p = _proc;
    if (p == null) return;
    _add(text, TermStyle.input);
    try {
      p.stdin.writeln(text);
    } catch (_) {}
  }

  void interrupt() {
    if (_proc != null) {
      _proc!.kill(ProcessSignal.sigint);
      Future.delayed(const Duration(milliseconds: 600), () => _proc?.kill(ProcessSignal.sigkill));
      _add('^C', TermStyle.warn);
    }
    if (_js != null) {
      _js!.cancel();
      _js = null;
      _add('^C  (script stopped)', TermStyle.warn);
      notifyListeners();
    }
  }

  Future<void> submit(String raw) async {
    final cmd = raw.trim();
    _histCursor = -1;
    if (busy) {
      sendInput(raw);
      return;
    }
    _add('$prompt$cmd', TermStyle.input);
    if (cmd.isEmpty) return;
    if (history.isEmpty || history.last != cmd) history.add(cmd);
    if (history.length > 200) history.removeAt(0);

    final args = splitArgs(cmd);
    if (args.isEmpty) return;
    final name = args.first;
    final rest = args.skip(1).toList();

    switch (name) {
      case 'help':
        _help();
      case 'clear' || 'cls':
        clear();
      case 'pwd':
        _add(_absCwd);
      case 'cd':
        _cd(rest.isEmpty ? '' : rest.first);
      case 'history':
        for (var i = 0; i < history.length; i++) {
          _add('${(i + 1).toString().padLeft(4)}  ${history[i]}', TermStyle.dim);
        }
      case 'open' || 'code':
        if (rest.isEmpty) {
          _add('usage: open <file>[:line]', TermStyle.warn);
        } else {
          final spec = rest.first;
          final m = RegExp(r'^(.*?):(\d+)$').firstMatch(spec);
          final rel = _rel(m == null ? spec : m.group(1)!);
          if (rel == null) {
            _add('open: path is outside the project', TermStyle.err);
          } else if (!await XWorkspace.instance.exists(project, rel)) {
            _add('open: $rel: no such file', TermStyle.err);
          } else {
            await host.openFile(rel, line: m == null ? null : int.parse(m.group(2)!) - 1);
          }
        }
      case 'run':
        await host.runFile(rest.isEmpty ? await host.currentFile() : _rel(rest.first));
      case 'serve' || 'preview':
        await host.startPreview(rest.isEmpty ? null : _rel(rest.first));
      case 'node' || 'js':
        await _node(rest);
      case 'search' || 'rg':
        await _search(rest);
      case 'tree':
        await _tree(rest.isEmpty ? cwd : (_rel(rest.first) ?? cwd));
      case 'env':
        _env().forEach((k, v) => _add('$k=$v'));
      case 'exit':
        _add('Close the panel to hide the terminal.', TermStyle.dim);
      default:
        if (_unavailable.contains(name)) {
          _add('$name: not available on this phone.', TermStyle.err);
          _add(_hintFor(name), TermStyle.dim);
          return;
        }
        await _shell(cmd);
    }
  }

  String _hintFor(String name) => switch (name) {
        'npm' || 'npx' || 'yarn' || 'pnpm' || 'deno' || 'bun' =>
          'Tip: "node file.js" runs JavaScript here (no npm packages). For packages, build on a computer or CI.',
        'python' || 'python3' || 'pip' || 'pip3' =>
          'Tip: edit Python here; run it on a computer or server. NOVA can explain or test the code (✨).',
        'git' => 'Tip: export the project as .zip (⋮ › Export) and push it from a computer.',
        'php' => 'Tip: preview HTML/JS here; upload .php files to a PHP server to run them.',
        _ => 'X Coder uses Android’s built-in shell tools only (type "help").',
      };

  Map<String, String> _env() => {
        'HOME': project.path,
        'PWD': _absCwd,
        'PATH': '/system/bin:/system/xbin:/vendor/bin',
        'TERM': 'dumb',
        'LANG': 'en_US.UTF-8',
        'TMPDIR': '${project.path}/.tmp',
        'PROJECT': project.path,
      };

  String? _rel(String p) {
    final joined = p.startsWith('/') ? p.substring(1) : (cwd.isEmpty ? p : '$cwd/$p');
    // allow `..` that stays inside the project
    final parts = <String>[];
    for (final s in joined.split('/')) {
      if (s.isEmpty || s == '.') continue;
      if (s == '..') {
        if (parts.isEmpty) return null;
        parts.removeLast();
        continue;
      }
      parts.add(s);
    }
    return parts.join('/');
  }

  void _cd(String target) {
    if (target.isEmpty || target == '~' || target == '/') {
      cwd = '';
      notifyListeners();
      return;
    }
    final rel = _rel(target);
    if (rel == null) {
      _add('cd: stays inside the project folder', TermStyle.err);
      return;
    }
    if (!Directory(rel.isEmpty ? project.path : '${project.path}/$rel').existsSync()) {
      _add('cd: $target: no such folder', TermStyle.err);
      return;
    }
    cwd = rel;
    notifyListeners();
  }

  void _help() {
    const help = <(String, String)>[
      ('X Coder', ''),
      ('open <file>[:line]', 'open a file in the editor'),
      ('run [file]', 'run the file (HTML → preview, JS → here)'),
      ('node <file.js> [args] · node -e "code"', 'run JavaScript (phone’s V8 engine, no npm modules)'),
      ('serve [file]', 'preview the site on http://127.0.0.1'),
      ('search <text> [--regex] [--case]', 'find in all project files'),
      ('tree [folder]', 'show the folder tree'),
      ('cd · pwd · clear · history · env', ''),
      ('Shell (Android toybox)', ''),
      ('ls -la · cat · head · tail · wc · grep -rn · find · sed', ''),
      ('mkdir -p · touch · cp -r · mv · rm -r · diff · sort · uniq', ''),
      ('md5sum · sha256sum · base64 · date · du -sh · ping -c 3', ''),
      ('pipes |, redirects > >>, && and ||', ''),
      ('Keys', ''),
      ('↑ ↓ history · Tab complete · ^C stop', ''),
    ];
    for (final (a, b) in help) {
      if (b.isEmpty && !a.contains(' ')) {
        _add(a, TermStyle.ok);
      } else if (b.isEmpty) {
        _add('  $a');
      } else {
        _add('  ${a.padRight(40)} $b');
      }
    }
    _add('Not on a stock phone: npm, pip, python, git, apt, su.', TermStyle.dim);
  }

  Future<void> _tree(String rel) async {
    final root = await XWorkspace.instance.tree(project, maxEntries: 1500);
    XNode? find(XNode n, String r) {
      if (n.rel == r) return n;
      for (final c in n.children) {
        if (c.isDir && (r == c.rel || r.startsWith('${c.rel}/'))) return find(c, r);
      }
      return null;
    }

    final start = rel.isEmpty ? root : find(root, rel);
    if (start == null) {
      _add('tree: $rel: no such folder', TermStyle.err);
      return;
    }
    var files = 0, dirs = 0;
    void walk(XNode n, String prefix) {
      for (var i = 0; i < n.children.length; i++) {
        final c = n.children[i];
        final last = i == n.children.length - 1;
        _add('$prefix${last ? '└── ' : '├── '}${c.name}${c.isDir ? '/' : ''}', c.isDir ? TermStyle.info : TermStyle.out);
        if (c.isDir) {
          dirs++;
          walk(c, '$prefix${last ? '    ' : '│   '}');
        } else {
          files++;
        }
      }
    }

    _add(rel.isEmpty ? '.' : rel, TermStyle.info);
    walk(start, '');
    _add('$dirs folders, $files files', TermStyle.dim);
  }

  Future<void> _search(List<String> a) async {
    final regex = a.remove('--regex');
    final cs = a.remove('--case');
    if (a.isEmpty) {
      _add('usage: search <text> [--regex] [--case]', TermStyle.warn);
      return;
    }
    final hits = await XWorkspace.instance.search(project, a.join(' '), regex: regex, caseSensitive: cs, maxHits: 200);
    for (final h in hits) {
      _add('${h.rel}:${h.row + 1}:${h.column + 1}  ${h.line.trim()}');
    }
    _add('${hits.length} result${hits.length == 1 ? '' : 's'}${hits.length >= 200 ? ' (first 200)' : ''}', TermStyle.dim);
  }

  Future<void> _node(List<String> a) async {
    String code;
    var file = 'eval.js';
    var args = <String>[];
    if (a.isEmpty) {
      _add('usage: node <file.js> [args…]   or   node -e "console.log(1+1)"', TermStyle.warn);
      return;
    }
    if (a.first == '-e' || a.first == '-p') {
      final src = a.skip(1).join(' ');
      code = a.first == '-p' ? 'console.log(eval(${jsonEncode(src)}))' : src;
    } else {
      final rel = _rel(a.first);
      if (rel == null) {
        _add('node: path is outside the project', TermStyle.err);
        return;
      }
      final text = await XWorkspace.instance.read(project, rel);
      if (text == null) {
        _add('node: cannot find $rel', TermStyle.err);
        return;
      }
      code = text;
      file = rel;
      args = a.skip(1).toList();
    }
    final sw = Stopwatch()..start();
    final done = Completer<void>();
    _js = JsRunner.run(code, fileName: file, args: args).listen(
      (l) {
        if (l.text.isEmpty) return;
        _add(l.text, switch (l.level) {
          'error' => TermStyle.err,
          'warn' => TermStyle.warn,
          'info' => TermStyle.info,
          'debug' => TermStyle.dim,
          _ => TermStyle.out,
        });
      },
      onDone: () {
        _js = null;
        _add('[done in ${sw.elapsedMilliseconds} ms]', TermStyle.dim);
        if (!done.isCompleted) done.complete();
      },
    );
    notifyListeners();
    await done.future;
  }

  Future<void> _shell(String cmd) async {
    try {
      await Directory('${project.path}/.tmp').create(recursive: true);
    } catch (_) {}
    final sw = Stopwatch()..start();
    try {
      final p = await Process.start('/system/bin/sh', ['-c', cmd],
          workingDirectory: _absCwd, environment: _env(), includeParentEnvironment: false);
      _proc = p;
      notifyListeners();
      // Whole lines only: output arrives in chunks that can end mid-line.
      Future<void> pipe(Stream<List<int>> s, TermStyle style) {
        var pending = '';
        return s.transform(const Utf8Decoder(allowMalformed: true)).listen((chunk) {
          final text = pending + _stripAnsi(chunk);
          final cut = text.lastIndexOf('\n');
          if (cut < 0) {
            pending = text;
            return;
          }
          pending = text.substring(cut + 1);
          _add(text.substring(0, cut), style);
        }, onDone: () {
          if (pending.isNotEmpty) _add(pending, style);
        }).asFuture<void>();
      }

      final outDone = pipe(p.stdout, TermStyle.out);
      final errDone = pipe(p.stderr, TermStyle.err);
      final killer = Timer(const Duration(minutes: 5), () {
        p.kill(ProcessSignal.sigkill);
        _add('Stopped after 5 minutes.', TermStyle.warn);
      });
      final code = await p.exitCode;
      killer.cancel();
      await Future.wait<void>([outDone, errDone]).timeout(const Duration(seconds: 2), onTimeout: () => <void>[]);
      _proc = null;
      if (code != 0) _add('[exit $code · ${sw.elapsedMilliseconds} ms]', TermStyle.dim);
      notifyListeners();
      if (RegExp(r'\b(mkdir|touch|rm|mv|cp|echo|cat|sed|tee|unzip|tar)\b|>').hasMatch(cmd)) {
        await host.refreshExplorer();
      }
    } catch (e) {
      _proc = null;
      _add('Could not run: $e', TermStyle.err);
    }
  }

  static String _stripAnsi(String s) => s.replaceAll(RegExp(r'\x1B\[[0-9;?]*[A-Za-z]'), '').replaceAll('\r', '');

  /// Tab completion: completes the last word against files and folders.
  Future<String?> complete(String input) async {
    final i = input.lastIndexOf(' ');
    final head = input.substring(0, i + 1);
    final word = input.substring(i + 1);
    if (i < 0) {
      const cmds = ['help', 'clear', 'open', 'run', 'node', 'serve', 'search', 'tree', 'history', 'ls', 'cat', 'mkdir',
          'touch', 'rm', 'mv', 'cp', 'grep', 'find', 'cd', 'pwd', 'wc', 'head', 'tail', 'echo', 'diff', 'sed'];
      final m = cmds.where((c) => c.startsWith(word)).toList();
      if (m.length == 1) return '${m.first} ';
      if (m.length > 1) _add(m.join('  '), TermStyle.dim);
      return null;
    }
    final slash = word.lastIndexOf('/');
    final dirPart = slash >= 0 ? word.substring(0, slash + 1) : '';
    final namePart = slash >= 0 ? word.substring(slash + 1) : word;
    final rel = _rel(dirPart.isEmpty ? '.' : dirPart);
    if (rel == null) return null;
    final d = Directory(rel.isEmpty ? project.path : '${project.path}/$rel');
    if (!d.existsSync()) return null;
    final names = <String>[];
    for (final e in d.listSync()) {
      final n = e.path.split('/').last;
      if (n.startsWith(namePart) && n != '.xcoder.json') names.add(e is Directory ? '$n/' : n);
    }
    if (names.isEmpty) return null;
    if (names.length == 1) return '$head$dirPart${names.first}${names.first.endsWith('/') ? '' : ' '}';
    var prefix = names.first;
    for (final n in names) {
      var k = 0;
      while (k < prefix.length && k < n.length && prefix[k] == n[k]) {
        k++;
      }
      prefix = prefix.substring(0, k);
    }
    _add(names.join('  '), TermStyle.dim);
    return prefix.length > namePart.length ? '$head$dirPart$prefix' : null;
  }

  /// Splits a command line like a shell would (quotes, escapes).
  static List<String> splitArgs(String s) {
    final out = <String>[];
    final b = StringBuffer();
    String? quote;
    var any = false;
    for (var i = 0; i < s.length; i++) {
      final c = s[i];
      if (quote != null) {
        if (c == quote) {
          quote = null;
        } else if (c == '\\' && quote == '"' && i + 1 < s.length) {
          b.write(s[++i]);
        } else {
          b.write(c);
        }
      } else if (c == '"' || c == "'") {
        quote = c;
        any = true;
      } else if (c == '\\' && i + 1 < s.length) {
        b.write(s[++i]);
        any = true;
      } else if (c == ' ' || c == '\t') {
        if (b.isNotEmpty || any) {
          out.add(b.toString());
          b.clear();
          any = false;
        }
      } else {
        b.write(c);
      }
    }
    if (b.isNotEmpty || any) out.add(b.toString());
    return out;
  }

  @override
  void dispose() {
    _proc?.kill(ProcessSignal.sigkill);
    _js?.cancel();
    super.dispose();
  }
}
