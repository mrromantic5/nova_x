// lib/features/xcoder/workspace/xcoder_workspace.dart
//
// X Coder projects are real folders on the phone:
//   <app documents>/xcoder/projects/<folder>/
// with an `.xcoder.json` file holding the project's name and editor state
// (open tabs, active tab). Files are read and written directly, so the
// terminal, the preview server and the editor all see the same files.
//
// The single-list workspace of earlier versions (nova_x_editor/workspace.json)
// is moved into a project called "My Workspace" the first time X Coder opens.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// Files bigger than this open read-only in a preview instead of the editor.
const int kXCoderMaxEditableBytes = 2 * 1024 * 1024;

/// Folders that are never listed, searched or zipped.
const Set<String> kXCoderIgnoredDirs = {'.git', 'node_modules', '.dart_tool', 'build', '.gradle', '__pycache__', '.idea'};

class XProject {
  XProject({required this.dir, required this.name, required this.updatedAt, List<String>? openTabs, this.activeTab})
      : openTabs = [...?openTabs];

  final Directory dir;
  String name;
  DateTime updatedAt;
  List<String> openTabs; // relative paths
  String? activeTab;

  String get path => dir.path;
  String get folder => dir.path.split('/').last;

  File get _meta => File('${dir.path}/.xcoder.json');

  Future<void> saveMeta() async {
    updatedAt = DateTime.now();
    try {
      await _meta.writeAsString(jsonEncode({
        'name': name,
        'updatedAt': updatedAt.millisecondsSinceEpoch,
        'openTabs': openTabs.take(30).toList(),
        'activeTab': activeTab,
      }));
    } catch (_) {}
  }

  static Future<XProject> load(Directory d) async {
    var name = d.path.split('/').last;
    var updated = DateTime.fromMillisecondsSinceEpoch(0);
    var tabs = <String>[];
    String? active;
    try {
      final f = File('${d.path}/.xcoder.json');
      if (await f.exists()) {
        final m = jsonDecode(await f.readAsString());
        if (m is Map) {
          if (m['name'] is String && (m['name'] as String).trim().isNotEmpty) name = m['name'] as String;
          if (m['updatedAt'] is int) updated = DateTime.fromMillisecondsSinceEpoch(m['updatedAt'] as int);
          if (m['openTabs'] is List) tabs = (m['openTabs'] as List).whereType<String>().toList();
          if (m['activeTab'] is String) active = m['activeTab'] as String;
        }
      } else {
        updated = (await d.stat()).modified;
      }
    } catch (_) {}
    return XProject(dir: d, name: name, updatedAt: updated, openTabs: tabs, activeTab: active);
  }

  /// Absolute path of [rel] inside the project, or null if it would escape it.
  String? resolve(String rel) {
    final clean = XWorkspace.normalize(rel);
    if (clean == null) return null;
    return clean.isEmpty ? dir.path : '${dir.path}/$clean';
  }

  String relative(String absolute) {
    final p = dir.path;
    if (absolute == p) return '';
    return absolute.startsWith('$p/') ? absolute.substring(p.length + 1) : absolute;
  }
}

/// A node of the explorer tree.
class XNode {
  XNode(this.rel, this.isDir, {this.size = 0, this.modified, List<XNode>? children}) : children = children ?? [];
  final String rel;
  final bool isDir;
  final int size;
  final DateTime? modified;
  final List<XNode> children;

  String get name => rel.split('/').last;
  String get ext {
    final n = name;
    final i = n.lastIndexOf('.');
    return i > 0 ? n.substring(i + 1).toLowerCase() : '';
  }
}

class XSearchHit {
  const XSearchHit(this.rel, this.row, this.column, this.line);
  final String rel;
  final int row;
  final int column;
  final String line;
}

class XWorkspace {
  XWorkspace._();
  static final XWorkspace instance = XWorkspace._();

  Directory? _root;

  Future<Directory> root() async {
    if (_root != null) return _root!;
    final docs = await getApplicationDocumentsDirectory();
    final d = Directory('${docs.path}/xcoder/projects');
    if (!await d.exists()) await d.create(recursive: true);
    _root = d;
    return d;
  }

  /// Safe relative path ('' = project root) or null when it tries to leave
  /// the project (`..`, absolute paths, control characters).
  static String? normalize(String rel) {
    var r = rel.replaceAll('\\', '/').trim();
    while (r.startsWith('./')) {
      r = r.substring(2);
    }
    if (r.startsWith('/')) return null;
    final parts = <String>[];
    for (final p in r.split('/')) {
      if (p.isEmpty || p == '.') continue;
      if (p == '..') return null;
      if (RegExp(r'[\x00-\x1f]').hasMatch(p)) return null;
      parts.add(p);
    }
    return parts.join('/');
  }

  /// Valid single file or folder name.
  static String? validName(String name) {
    final n = name.trim();
    if (n.isEmpty) return 'Enter a name.';
    if (n == '.' || n == '..') return 'That name is reserved.';
    if (n.contains('/') || n.contains('\\')) return 'Names can’t contain / or \\.';
    if (RegExp(r'[\x00-\x1f:*?"<>|]').hasMatch(n)) return 'Names can’t contain : * ? " < > |';
    if (n.length > 120) return 'That name is too long.';
    return null;
  }

  static String _slug(String name) {
    final s = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9._-]+'), '-').replaceAll(RegExp(r'-+'), '-');
    final t = s.replaceAll(RegExp(r'^-|-$'), '');
    return t.isEmpty ? 'project' : (t.length > 40 ? t.substring(0, 40) : t);
  }

  Future<List<XProject>> projects() async {
    final r = await root();
    final out = <XProject>[];
    await for (final e in r.list(followLinks: false)) {
      if (e is Directory) out.add(await XProject.load(e));
    }
    out.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return out;
  }

  Future<XProject> create(String name, {XTemplate template = XTemplate.web}) async {
    final r = await root();
    var slug = _slug(name);
    var d = Directory('${r.path}/$slug');
    var i = 2;
    while (await d.exists()) {
      d = Directory('${r.path}/$slug-${i++}');
    }
    await d.create(recursive: true);
    final files = template.files;
    for (final e in files.entries) {
      final f = File('${d.path}/${e.key}');
      await f.parent.create(recursive: true);
      await f.writeAsString(e.value);
    }
    final p = XProject(dir: d, name: name.trim().isEmpty ? slug : name.trim(), updatedAt: DateTime.now(),
        openTabs: template.open, activeTab: template.open.isEmpty ? null : template.open.first);
    await p.saveMeta();
    return p;
  }

  Future<void> deleteProject(XProject p) async {
    final r = await root();
    if (!p.dir.path.startsWith('${r.path}/')) return;
    await p.dir.delete(recursive: true);
  }

  /// Moves the old single-list workspace into a project (once).
  Future<XProject?> migrateLegacy() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final legacy = File('${docs.path}/nova_x_editor/workspace.json');
      if (!await legacy.exists()) return null;
      final data = jsonDecode(await legacy.readAsString());
      if (data is! List || data.isEmpty) {
        await legacy.rename('${legacy.path}.migrated');
        return null;
      }
      final p = await create('My Workspace', template: XTemplate.empty);
      final tabs = <String>[];
      for (final e in data) {
        if (e is! Map) continue;
        final name = normalize((e['name'] ?? '').toString());
        if (name == null || name.isEmpty) continue;
        final f = File('${p.path}/$name');
        await f.parent.create(recursive: true);
        await f.writeAsString((e['content'] ?? '').toString());
        if (tabs.length < 8) tabs.add(name);
      }
      p.openTabs = tabs;
      p.activeTab = tabs.isEmpty ? null : tabs.first;
      await p.saveMeta();
      await legacy.rename('${legacy.path}.migrated');
      return p;
    } catch (_) {
      return null;
    }
  }

  // ── Files ─────────────────────────────────────────────────────────────

  Future<XNode> tree(XProject p, {int maxEntries = 4000}) async {
    var count = 0;
    Future<XNode> walk(Directory d, String rel) async {
      final node = XNode(rel, true);
      final entries = <FileSystemEntity>[];
      try {
        await for (final e in d.list(followLinks: false)) {
          entries.add(e);
        }
      } catch (_) {}
      entries.sort((a, b) {
        final ad = a is Directory, bd = b is Directory;
        if (ad != bd) return ad ? -1 : 1;
        return a.path.toLowerCase().compareTo(b.path.toLowerCase());
      });
      for (final e in entries) {
        if (++count > maxEntries) break;
        final name = e.path.split('/').last;
        if (name == '.xcoder.json') continue;
        final r = rel.isEmpty ? name : '$rel/$name';
        if (e is Directory) {
          if (kXCoderIgnoredDirs.contains(name)) {
            node.children.add(XNode(r, true));
          } else {
            node.children.add(await walk(e, r));
          }
        } else if (e is File) {
          FileStat? st;
          try {
            st = await e.stat();
          } catch (_) {}
          node.children.add(XNode(r, false, size: st?.size ?? 0, modified: st?.modified));
        }
      }
      return node;
    }

    return walk(p.dir, '');
  }

  Future<List<String>> allFiles(XProject p, {int max = 3000}) async {
    final out = <String>[];
    void collect(XNode n) {
      for (final c in n.children) {
        if (out.length >= max) return;
        if (c.isDir) {
          collect(c);
        } else {
          out.add(c.rel);
        }
      }
    }

    collect(await tree(p, maxEntries: max * 2));
    return out;
  }

  /// Text of a file (UTF-8, invalid bytes replaced) or null.
  Future<String?> read(XProject p, String rel) async {
    final a = p.resolve(rel);
    if (a == null) return null;
    try {
      final f = File(a);
      if (!await f.exists()) return null;
      final bytes = await f.readAsBytes();
      return utf8.decode(bytes, allowMalformed: true);
    } catch (_) {
      return null;
    }
  }

  Future<bool> isProbablyText(XProject p, String rel) async {
    final a = p.resolve(rel);
    if (a == null) return false;
    try {
      final raf = await File(a).open();
      final head = await raf.read(4096);
      await raf.close();
      if (head.isEmpty) return true;
      var bad = 0;
      for (final b in head) {
        if (b == 0) return false;
        if (b < 9 || (b > 13 && b < 32)) bad++;
      }
      return bad / head.length < 0.05;
    } catch (_) {
      return false;
    }
  }

  Future<void> write(XProject p, String rel, String content) async {
    final a = p.resolve(rel);
    if (a == null || a == p.path) throw const FileSystemException('Invalid path');
    final f = File(a);
    await f.parent.create(recursive: true);
    // Write next to it, then replace: a crash mid-write never leaves half a file.
    final tmp = File('$a.xctmp');
    await tmp.writeAsString(content, flush: true);
    await tmp.rename(a);
  }

  Future<void> writeBytes(XProject p, String rel, Uint8List bytes) async {
    final a = p.resolve(rel);
    if (a == null || a == p.path) throw const FileSystemException('Invalid path');
    final f = File(a);
    await f.parent.create(recursive: true);
    await f.writeAsBytes(bytes, flush: true);
  }

  Future<void> createFolder(XProject p, String rel) async {
    final a = p.resolve(rel);
    if (a == null || a == p.path) throw const FileSystemException('Invalid path');
    await Directory(a).create(recursive: true);
  }

  Future<bool> exists(XProject p, String rel) async {
    final a = p.resolve(rel);
    if (a == null) return false;
    return await FileSystemEntity.type(a) != FileSystemEntityType.notFound;
  }

  Future<void> rename(XProject p, String from, String to) async {
    final a = p.resolve(from), b = p.resolve(to);
    if (a == null || b == null || a == p.path || b == p.path) throw const FileSystemException('Invalid path');
    if (await FileSystemEntity.type(b) != FileSystemEntityType.notFound) {
      throw const FileSystemException('A file or folder with that name already exists');
    }
    await Directory(b).parent.create(recursive: true);
    final t = await FileSystemEntity.type(a);
    if (t == FileSystemEntityType.directory) {
      await Directory(a).rename(b);
    } else {
      await File(a).rename(b);
    }
  }

  Future<void> delete(XProject p, String rel) async {
    final a = p.resolve(rel);
    if (a == null || a == p.path) throw const FileSystemException('Invalid path');
    final t = await FileSystemEntity.type(a);
    if (t == FileSystemEntityType.directory) {
      await Directory(a).delete(recursive: true);
    } else if (t != FileSystemEntityType.notFound) {
      await File(a).delete();
    }
  }

  Future<String> duplicate(XProject p, String rel) async {
    final a = p.resolve(rel);
    if (a == null) throw const FileSystemException('Invalid path');
    final dot = rel.lastIndexOf('.');
    final slash = rel.lastIndexOf('/');
    final hasExt = dot > slash + 1;
    final base = hasExt ? rel.substring(0, dot) : rel;
    final ext = hasExt ? rel.substring(dot) : '';
    var i = 1;
    var target = '$base copy$ext';
    while (await exists(p, target)) {
      target = '$base copy ${++i}$ext';
    }
    await File(a).copy(p.resolve(target)!);
    return target;
  }

  /// Text search across the project (skips big and binary files).
  Future<List<XSearchHit>> search(XProject p, String query,
      {bool regex = false, bool caseSensitive = false, bool wholeWord = false, int maxHits = 500, String? include}) async {
    if (query.isEmpty) return const [];
    RegExp re;
    try {
      var src = regex ? query : RegExp.escape(query);
      if (wholeWord) src = '\\b$src\\b';
      re = RegExp(src, caseSensitive: caseSensitive);
    } catch (_) {
      return const [];
    }
    final hits = <XSearchHit>[];
    final files = await allFiles(p);
    final inc = include?.trim().toLowerCase() ?? '';
    for (final rel in files) {
      if (hits.length >= maxHits) break;
      if (inc.isNotEmpty && !_globMatch(rel.toLowerCase(), inc)) continue;
      final a = p.resolve(rel)!;
      try {
        final f = File(a);
        if (await f.length() > kXCoderMaxEditableBytes) continue;
        if (!await isProbablyText(p, rel)) continue;
        final lines = const LineSplitter().convert(await f.readAsString());
        for (var i = 0; i < lines.length && hits.length < maxHits; i++) {
          final m = re.firstMatch(lines[i]);
          if (m != null) {
            final l = lines[i];
            hits.add(XSearchHit(rel, i, m.start, l.length > 240 ? l.substring(0, 240) : l));
          }
        }
      } catch (_) {}
    }
    return hits;
  }

  /// Replaces every match in the project. Returns (files changed, replacements).
  Future<(int, int)> replaceInFiles(XProject p, String query, String replacement,
      {bool regex = false, bool caseSensitive = false, bool wholeWord = false}) async {
    if (query.isEmpty) return (0, 0);
    var src = regex ? query : RegExp.escape(query);
    if (wholeWord) src = '\\b$src\\b';
    final re = RegExp(src, caseSensitive: caseSensitive);
    var files = 0, count = 0;
    for (final rel in await allFiles(p)) {
      final a = p.resolve(rel)!;
      try {
        final f = File(a);
        if (await f.length() > kXCoderMaxEditableBytes || !await isProbablyText(p, rel)) continue;
        final text = await f.readAsString();
        final n = re.allMatches(text).length;
        if (n == 0) continue;
        final out = regex
            ? text.replaceAllMapped(re, (m) => replacement.replaceAllMapped(RegExp(r'\$(\d)'), (g) {
                  final i = int.parse(g.group(1)!);
                  return i <= m.groupCount ? (m.group(i) ?? '') : g.group(0)!;
                }))
            : text.replaceAll(re, replacement);
        await write(p, rel, out);
        files++;
        count += n;
      } catch (_) {}
    }
    return (files, count);
  }

  static bool _globMatch(String path, String pattern) {
    // "*.js", "src/", "*.{js,ts}" — simple and forgiving.
    for (final raw in pattern.split(',')) {
      final pat = raw.trim();
      if (pat.isEmpty) continue;
      if (!pat.contains('*')) {
        if (path.contains(pat)) return true;
        continue;
      }
      final re = RegExp('^${RegExp.escape(pat).replaceAll(r'\*\*', '.*').replaceAll(r'\*', '[^/]*')}\$');
      if (re.hasMatch(path) || re.hasMatch(path.split('/').last)) return true;
    }
    return false;
  }

  /// Words from the project's files for autocompletion (identifiers ≥ 4 chars).
  Future<List<String>> projectWords(XProject p, {int maxFiles = 60}) async {
    final words = <String, int>{};
    final re = RegExp(r'[A-Za-z_$][A-Za-z0-9_$-]{3,40}');
    var n = 0;
    for (final rel in await allFiles(p)) {
      if (n++ > maxFiles) break;
      try {
        final f = File(p.resolve(rel)!);
        if (await f.length() > 300 * 1024 || !await isProbablyText(p, rel)) continue;
        for (final m in re.allMatches(await f.readAsString())) {
          final w = m.group(0)!;
          words[w] = (words[w] ?? 0) + 1;
        }
      } catch (_) {}
    }
    final list = words.keys.toList()..sort((a, b) => words[b]!.compareTo(words[a]!));
    return list.take(4000).toList();
  }

  /// The project as a .zip (stored, no compression — opens everywhere).
  Future<Uint8List> zip(XProject p) async {
    final w = ZipWriter();
    for (final rel in await allFiles(p, max: 5000)) {
      try {
        final f = File(p.resolve(rel)!);
        if (await f.length() > 20 * 1024 * 1024) continue;
        w.add('${p.folder}/$rel', await f.readAsBytes(), (await f.stat()).modified);
      } catch (_) {}
    }
    return w.finish();
  }
}

/// Minimal ZIP writer (method 0 = stored). Enough for exporting projects.
class ZipWriter {
  final _out = BytesBuilder(copy: false);
  final _central = BytesBuilder(copy: false);
  int _count = 0;

  static final List<int> _crcTable = List<int>.generate(256, (n) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
    }
    return c;
  });

  static int crc32(List<int> data) {
    var c = 0xFFFFFFFF;
    for (final b in data) {
      c = _crcTable[(c ^ b) & 0xFF] ^ (c >> 8);
    }
    return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }

  static void _u16(BytesBuilder b, int v) => b.add([v & 0xFF, (v >> 8) & 0xFF]);
  static void _u32(BytesBuilder b, int v) => b.add([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]);

  void add(String name, List<int> data, [DateTime? time]) {
    final t = time ?? DateTime.now();
    final dosTime = (t.hour << 11) | (t.minute << 5) | (t.second ~/ 2);
    final dosDate = ((t.year - 1980).clamp(0, 127) << 9) | (t.month << 5) | t.day;
    final nameBytes = utf8.encode(name);
    final crc = crc32(data);
    final offset = _out.length;

    _u32(_out, 0x04034b50);
    _u16(_out, 20);
    _u16(_out, 0x0800); // UTF-8 names
    _u16(_out, 0);
    _u16(_out, dosTime);
    _u16(_out, dosDate);
    _u32(_out, crc);
    _u32(_out, data.length);
    _u32(_out, data.length);
    _u16(_out, nameBytes.length);
    _u16(_out, 0);
    _out.add(nameBytes);
    _out.add(data);

    _u32(_central, 0x02014b50);
    _u16(_central, 20);
    _u16(_central, 20);
    _u16(_central, 0x0800);
    _u16(_central, 0);
    _u16(_central, dosTime);
    _u16(_central, dosDate);
    _u32(_central, crc);
    _u32(_central, data.length);
    _u32(_central, data.length);
    _u16(_central, nameBytes.length);
    _u16(_central, 0);
    _u16(_central, 0);
    _u16(_central, 0);
    _u16(_central, 0);
    _u32(_central, 0);
    _u32(_central, offset);
    _central.add(nameBytes);
    _count++;
  }

  Uint8List finish() {
    final centralBytes = _central.takeBytes();
    final offset = _out.length;
    _out.add(centralBytes);
    _u32(_out, 0x06054b50);
    _u16(_out, 0);
    _u16(_out, 0);
    _u16(_out, _count);
    _u16(_out, _count);
    _u32(_out, centralBytes.length);
    _u32(_out, offset);
    _u16(_out, 0);
    return _out.takeBytes();
  }
}

/// Starter projects.
enum XTemplate {
  web('Website', 'HTML, CSS and JavaScript'),
  javascript('JavaScript', 'A script you run with ▶ or `node main.js`'),
  python('Python', 'Edit Python code (run it on a computer or server)'),
  php('PHP', 'A PHP page and API endpoint'),
  markdown('Notes', 'Markdown notes and docs'),
  empty('Empty', 'Start from nothing');

  const XTemplate(this.label, this.description);
  final String label;
  final String description;

  List<String> get open => switch (this) {
        XTemplate.web => ['index.html', 'style.css', 'script.js'],
        XTemplate.javascript => ['main.js'],
        XTemplate.python => ['main.py'],
        XTemplate.php => ['index.php'],
        XTemplate.markdown => ['README.md'],
        XTemplate.empty => const [],
      };

  Map<String, String> get files => switch (this) {
        XTemplate.web => {
            'index.html': _html,
            'style.css': _css,
            'script.js': _js,
            'README.md': '# My site\n\nTap ▶ Run to preview. Edit `index.html`, `style.css` and `script.js`.\n',
          },
        XTemplate.javascript => {
            'main.js': "// Run it: open the terminal and type  node main.js  (or tap ▶ Run)\n"
                "function greet(name) {\n  return `Hello, \${name}!`;\n}\n\nconsole.log(greet('X Coder'));\n"
                "console.table([{ lang: 'JavaScript', fun: true }]);\n",
            'README.md': '# JavaScript project\n\nRun `node main.js` in the terminal. X Coder runs JavaScript in the phone\'s built-in V8 engine (no npm modules).\n',
          },
        XTemplate.python => {
            'main.py': 'def greet(name: str) -> str:\n    return f"Hello, {name}!"\n\n\nif __name__ == "__main__":\n    print(greet("X Coder"))\n',
            'requirements.txt': '',
            'README.md': '# Python project\n\nRun with `python main.py` on a computer or server.\n',
          },
        XTemplate.php => {
            'index.php': "<?php\n\$name = htmlspecialchars(\$_GET['name'] ?? 'X Coder', ENT_QUOTES);\n?>\n<!doctype html>\n<html><body>\n  <h1>Hello, <?= \$name ?>!</h1>\n</body></html>\n",
            'api.php': "<?php\nheader('Content-Type: application/json');\necho json_encode(['ok' => true, 'time' => time()]);\n",
          },
        XTemplate.markdown => {'README.md': '# Notes\n\n- [ ] First task\n\n```js\nconsole.log("code blocks are highlighted");\n```\n'},
        XTemplate.empty => {},
      };

  static const _html = '''<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>My App</title>
  <link rel="stylesheet" href="style.css">
</head>
<body>
  <main class="card">
    <h1>Hello, X Coder 👋</h1>
    <p>Edit <code>index.html</code>, <code>style.css</code> and <code>script.js</code>, then tap ▶ Run.</p>
    <button id="btn">Click me</button>
    <p id="out"></p>
  </main>
  <script src="script.js"></script>
</body>
</html>
''';

  static const _css = '''* { box-sizing: border-box; }
body {
  margin: 0;
  min-height: 100vh;
  display: grid;
  place-items: center;
  font-family: system-ui, -apple-system, Segoe UI, Roboto, sans-serif;
  background: radial-gradient(circle at top, #12305a, #07101e);
  color: #e8f1ff;
}
.card {
  width: min(92vw, 420px);
  padding: 28px;
  border-radius: 20px;
  background: rgba(255, 255, 255, 0.06);
  border: 1px solid rgba(255, 255, 255, 0.12);
  text-align: center;
}
button {
  padding: 12px 22px;
  border: 0;
  border-radius: 12px;
  background: linear-gradient(135deg, #00d4ff, #7c4dff);
  color: #fff;
  font-weight: 700;
}
''';

  static const _js = '''const btn = document.getElementById('btn');
const out = document.getElementById('out');
let clicks = 0;

btn.addEventListener('click', () => {
  clicks++;
  out.textContent = `Clicked \${clicks} time\${clicks === 1 ? '' : 's'}`;
  console.log('clicked', clicks);
});
''';
}
