// lib/features/devtools/screens/code_editor_screen.dart
//
// NOVA X Code Editor — premium, SaaS-grade multi-file project workspace.
//   • Ace editor (22 languages, lazy syntax modes, each its own accent colour)
//   • Multi-file projects with tabs (add / rename / delete / switch)
//   • Open files from device (native picker via the webview <input type=file>)
//   • Fetch any file by URL (view / copy / edit)
//   • RUN ▶ — serves the whole project from a real local HTTP server
//     (dart:io HttpServer on 127.0.0.1) so HTML+CSS+JS link together, then
//     opens a live preview. Copy, Save-to-device, open-in-browser.
//
// Self-contained: flutter_inappwebview + dio + path_provider (already in deps).

import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../browser/screens/browser_view.dart';

class CodeLang {
  final String label;
  final String mode;
  final Color  color;
  final String ext;
  const CodeLang(this.label, this.mode, this.color, this.ext);
}

const List<CodeLang> kLangs = [
  CodeLang('HTML',        'html',       Color(0xFFE44D26), 'html'),
  CodeLang('CSS',         'css',        Color(0xFF2965F1), 'css'),
  CodeLang('JavaScript',  'javascript', Color(0xFFF7DF1E), 'js'),
  CodeLang('TypeScript',  'typescript', Color(0xFF3178C6), 'ts'),
  CodeLang('JSON',        'json',       Color(0xFF8BC34A), 'json'),
  CodeLang('Dart',        'dart',       Color(0xFF0175C2), 'dart'),
  CodeLang('Python',      'python',     Color(0xFF3776AB), 'py'),
  CodeLang('Java',        'java',       Color(0xFFEA2D2E), 'java'),
  CodeLang('Kotlin',      'kotlin',     Color(0xFF7F52FF), 'kt'),
  CodeLang('PHP',         'php',        Color(0xFF777BB4), 'php'),
  CodeLang('C',           'c_cpp',      Color(0xFF5C6BC0), 'c'),
  CodeLang('C++',         'c_cpp',      Color(0xFF00599C), 'cpp'),
  CodeLang('C#',          'csharp',     Color(0xFF68217A), 'cs'),
  CodeLang('Go',          'golang',     Color(0xFF00ADD8), 'go'),
  CodeLang('Rust',        'rust',       Color(0xFFDEA584), 'rs'),
  CodeLang('Ruby',        'ruby',       Color(0xFFCC342D), 'rb'),
  CodeLang('Swift',       'swift',      Color(0xFFFA7343), 'swift'),
  CodeLang('SQL',         'sql',        Color(0xFFE38C00), 'sql'),
  CodeLang('XML',         'xml',        Color(0xFFFF6600), 'xml'),
  CodeLang('YAML',        'yaml',       Color(0xFFCB171E), 'yaml'),
  CodeLang('Markdown',    'markdown',   Color(0xFF42A5F5), 'md'),
  CodeLang('Shell',       'sh',         Color(0xFF4EAA25), 'sh'),
];

CodeLang _langForExt(String name) {
  final dot = name.lastIndexOf('.');
  final ext = dot >= 0 ? name.substring(dot + 1).toLowerCase() : '';
  for (final l in kLangs) {
    if (l.ext == ext) return l;
  }
  switch (ext) {
    case 'htm':  return kLangs[0];
    case 'mjs':  case 'cjs': case 'jsx': return kLangs[2];
    case 'tsx':  return kLangs[3];
    case 'yml':  return kLangs[19];
    case 'bash': case 'zsh': return kLangs[21];
    case 'txt':  return kLangs[20];
    default:     return kLangs[0];
  }
}

class _PFile {
  String name;
  String content;
  CodeLang lang;
  _PFile(this.name, this.content, this.lang);
}

/// Shared persistence for the code editor. Both the editor inside Developer
/// Tools and the standalone "X Code Editor" load and save the SAME workspace,
/// so a file saved in one is available in the other.
class CodeWorkspaceStore {
  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    final d = Directory('${dir.path}/nova_x_editor');
    if (!await d.exists()) await d.create(recursive: true);
    return File('${d.path}/workspace.json');
  }

  static Future<List<_PFile>> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return [];
      final data = jsonDecode(await f.readAsString());
      if (data is! List) return [];
      final out = <_PFile>[];
      for (final e in data) {
        if (e is Map) {
          final name = (e['name'] ?? 'untitled.txt').toString();
          out.add(_PFile(name, (e['content'] ?? '').toString(), _langForExt(name)));
        }
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(List<_PFile> files) async {
    try {
      final f = await _file();
      await f.writeAsString(jsonEncode(
          files.map((p) => {'name': p.name, 'content': p.content}).toList()));
    } catch (_) {}
  }

  /// Append (or replace by name) a single file into the shared workspace.
  static Future<void> addFile(String name, String content) async {
    final list = await load();
    final i = list.indexWhere((p) => p.name == name);
    if (i >= 0) {
      list[i].content = content;
    } else {
      list.add(_PFile(name, content, _langForExt(name)));
    }
    await save(list);
  }
}

class CodeEditorScreen extends StatefulWidget {
  final String? initialUrl;
  final String? initialContent;
  final CodeLang? initialLang;
  final String   initialFileName;
  /// When true, this editor loads/saves the shared workspace (so the editor in
  /// Developer Tools and the standalone X Code Editor stay in sync).
  final bool sharedWorkspace;
  const CodeEditorScreen({
    super.key,
    this.initialUrl,
    this.initialContent,
    this.initialLang,
    this.initialFileName = 'index.html',
    this.sharedWorkspace = false,
  });

  @override
  State<CodeEditorScreen> createState() => _CodeEditorScreenState();
}

class _CodeEditorScreenState extends State<CodeEditorScreen> {
  InAppWebViewController? _wvc;
  HttpServer? _server;
  bool _ready = false;
  bool _busy  = false;

  final List<_PFile> _files = [];
  int _active = 0;

  _PFile get _cur => _files[_active];

  @override
  void initState() {
    super.initState();
    if (widget.initialContent != null || widget.initialUrl != null) {
      // Single file opened from DevTools (URL fetch fills it on ready)
      final name = widget.initialFileName;
      _files.add(_PFile(name, widget.initialContent ?? '',
          widget.initialLang ?? _langForExt(name)));
    } else {
      _seedStarterProject();
    }
  }

  @override
  void dispose() {
    _server?.close(force: true);
    super.dispose();
  }

  void _seedStarterProject() {
    _files.addAll([
      _PFile('index.html', _starterHtml, kLangs[0]),
      _PFile('style.css',  _starterCss,  kLangs[1]),
      _PFile('script.js',  _starterJs,   kLangs[2]),
    ]);
  }

  static const String _starterHtml = r'''<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <link rel="stylesheet" href="style.css">
  <title>My Project</title>
</head>
<body>
  <main>
    <h1>Hello, NOVA X &#128075;</h1>
    <p>Edit the files, then tap <strong>Run</strong> to preview.</p>
    <button id="btn">Click me</button>
  </main>
  <script src="script.js"></script>
</body>
</html>
''';

  static const String _starterCss = r'''* { margin: 0; padding: 0; box-sizing: border-box; }
body {
  font-family: system-ui, -apple-system, sans-serif;
  background: #0a0a0a; color: #fff;
  display: grid; place-items: center; min-height: 100vh;
}
main { text-align: center; padding: 24px; }
h1 {
  font-size: 2rem;
  background: linear-gradient(135deg, #00d4ff, #7c4dff);
  -webkit-background-clip: text; background-clip: text; color: transparent;
}
p { margin-top: 12px; color: #94a3b8; }
button {
  margin-top: 20px; padding: 12px 28px; border: none; border-radius: 12px;
  background: linear-gradient(135deg, #00d4ff, #7c4dff); color: #fff;
  font-size: 15px; font-weight: 700; cursor: pointer;
}
''';

  static const String _starterJs = r'''document.getElementById('btn').addEventListener('click', function () {
  console.log('Button clicked!');
  alert('It works! \u{1F389}');
});
''';

  // ── Ace editor document ────────────────────────────────────────────────────
  static const String _editorHtml = r'''
<!DOCTYPE html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
<style>
  html,body{margin:0;padding:0;height:100%;background:#07101E;overflow:hidden;}
  #editor{position:absolute;top:0;right:0;bottom:0;left:0;font-size:13px;}
  .ace_gutter{background:#0B1626 !important;}
</style></head>
<body>
<div id="editor"></div>
<input type="file" id="fileInput" style="display:none">
<script src="https://cdnjs.cloudflare.com/ajax/libs/ace/1.32.7/ace.min.js"></script>
<script src="https://cdnjs.cloudflare.com/ajax/libs/ace/1.32.7/ext-language_tools.min.js"></script>
<script>
  var editor;
  function nxInit(){
    try{
      ace.config.set('basePath','https://cdnjs.cloudflare.com/ajax/libs/ace/1.32.7/');
      editor = ace.edit('editor');
      editor.setTheme('ace/theme/dracula');
      editor.session.setMode('ace/mode/html');
      editor.setOptions({
        fontSize:'13px', showPrintMargin:false, useWorker:false, wrap:true,
        enableBasicAutocompletion:true, enableLiveAutocompletion:true,
        enableSnippets:true, tabSize:2, highlightActiveLine:true, showGutter:true
      });
      var fi=document.getElementById('fileInput');
      fi.addEventListener('change', function(e){
        var f=e.target.files[0]; if(!f) return;
        var r=new FileReader();
        r.onload=function(){
          editor.setValue(String(r.result), -1);
          try{ window.flutter_inappwebview.callHandler('nxFile', f.name); }catch(_){}
        };
        r.readAsText(f);
      });
      try{ window.flutter_inappwebview.callHandler('nxReady',''); }catch(_){}
      editor.session.on('change', function(){
        if (window.__nxT) clearTimeout(window.__nxT);
        window.__nxT = setTimeout(function(){
          try{ window.flutter_inappwebview.callHandler('nxChanged',''); }catch(_){}
        }, 800);
      });
    }catch(err){ try{ window.flutter_inappwebview.callHandler('nxErr', String(err)); }catch(_){} }
  }
  function nxSetMode(m){ if(editor) editor.session.setMode('ace/mode/'+m); }
  function nxSetValue(c){ if(editor) editor.setValue(c, -1); }
  function nxGetValue(){ return editor ? editor.getValue() : ''; }
  function nxOpenFile(){ document.getElementById('fileInput').click(); }
  if (window.ace) { nxInit(); } else { window.addEventListener('load', nxInit); }
</script></body></html>
''';

  // ── Editor <-> webview ─────────────────────────────────────────────────────
  Future<String> _getCode() async {
    final r = await _wvc?.evaluateJavascript(source: 'nxGetValue()');
    return r?.toString() ?? '';
  }

  Future<void> _setCode(String code) async {
    await _wvc?.evaluateJavascript(source: 'nxSetValue(${jsonEncode(code)})');
  }

  Future<void> _setMode(String mode) async {
    await _wvc?.evaluateJavascript(source: 'nxSetMode(${jsonEncode(mode)})');
  }

  Future<void> _syncActive() async {
    if (_ready && _active < _files.length) _cur.content = await _getCode();
  }

  /// Persist to the shared workspace (no-op when not in shared mode).
  Future<void> _persist() async {
    if (!widget.sharedWorkspace) return;
    await CodeWorkspaceStore.save(_files);
  }

  Future<void> _onReady() async {
    setState(() => _ready = true);
    // Shared mode: replace the seeded starter with the saved workspace (if any).
    if (widget.sharedWorkspace &&
        widget.initialContent == null && widget.initialUrl == null) {
      final loaded = await CodeWorkspaceStore.load();
      if (loaded.isNotEmpty) {
        setState(() { _files..clear()..addAll(loaded); _active = 0; });
      } else {
        await CodeWorkspaceStore.save(_files); // persist the starter once
      }
    }
    await _setMode(_cur.lang.mode);
    await _setCode(_cur.content);
    if (widget.initialUrl != null && widget.initialUrl!.isNotEmpty) {
      await _fetchUrl(widget.initialUrl!);
    }
  }

  // ── File operations ────────────────────────────────────────────────────────
  Future<void> _switchTo(int i) async {
    if (i == _active) return;
    await _syncActive();
    await _persist();
    setState(() => _active = i);
    await _setMode(_cur.lang.mode);
    await _setCode(_cur.content);
  }

  Future<void> _applyLang(CodeLang l) async {
    setState(() => _cur.lang = l);
    await _setMode(l.mode);
  }

  void _addFileDialog() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('New file', style: GoogleFonts.spaceGrotesk(
            color: AppTheme.textPrimary, fontWeight: FontWeight.w700)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: GoogleFonts.jetBrainsMono(color: AppTheme.textPrimary),
          decoration: InputDecoration(
            hintText: 'e.g. about.html, app.js, theme.css',
            hintStyle: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 13),
            enabledBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: AppTheme.divider)),
            focusedBorder: const UnderlineInputBorder(
                borderSide: BorderSide(color: AppTheme.accentCyan)),
          ),
          onSubmitted: (_) => _commitNewFile(ctrl.text),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context),
              child: Text('Cancel', style: GoogleFonts.inter(color: AppTheme.textHint))),
          ElevatedButton(
            onPressed: () => _commitNewFile(ctrl.text),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentCyan, foregroundColor: Colors.black87),
            child: Text('Create', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  Future<void> _commitNewFile(String raw) async {
    var name = raw.trim();
    if (name.isEmpty) return;
    if (!name.contains('.')) name = '$name.txt';
    if (_files.any((f) => f.name == name)) { Navigator.pop(context); _snack('"$name" already exists', error: true); return; }
    Navigator.pop(context);
    await _syncActive();
    setState(() {
      _files.add(_PFile(name, '', _langForExt(name)));
      _active = _files.length - 1;
    });
    await _setMode(_cur.lang.mode);
    await _setCode('');
    await _persist();
  }

  Future<void> _deleteFile(int i) async {
    if (_files.length == 1) { _snack('Keep at least one file', error: true); return; }
    setState(() {
      _files.removeAt(i);
      if (_active >= _files.length) _active = _files.length - 1;
      else if (i < _active) _active--;
    });
    await _setMode(_cur.lang.mode);
    await _setCode(_cur.content);
    await _persist();
  }

  void _renameDialog(int i) {
    final ctrl = TextEditingController(text: _files[i].name);
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('Rename', style: GoogleFonts.spaceGrotesk(
            color: AppTheme.textPrimary, fontWeight: FontWeight.w700)),
        content: TextField(
          controller: ctrl, autofocus: true,
          style: GoogleFonts.jetBrainsMono(color: AppTheme.textPrimary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context),
              child: Text('Cancel', style: GoogleFonts.inter(color: AppTheme.textHint))),
          ElevatedButton(
            onPressed: () {
              final n = ctrl.text.trim();
              if (n.isNotEmpty) {
                setState(() { _files[i].name = n; _files[i].lang = _langForExt(n); });
                if (i == _active) _setMode(_cur.lang.mode);
                _persist();
              }
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentCyan, foregroundColor: Colors.black87),
            child: Text('Save', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  void _fileMenu(int i) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (_) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 8),
        ListTile(
          leading: const Icon(Icons.drive_file_rename_outline_rounded, color: AppTheme.accentCyan),
          title: Text('Rename', style: GoogleFonts.inter(color: AppTheme.textPrimary)),
          onTap: () { Navigator.pop(context); _renameDialog(i); },
        ),
        ListTile(
          leading: const Icon(Icons.delete_outline_rounded, color: AppTheme.danger),
          title: Text('Delete', style: GoogleFonts.inter(color: AppTheme.textPrimary)),
          onTap: () { Navigator.pop(context); _deleteFile(i); },
        ),
        const SizedBox(height: 6),
      ])),
    );
  }

  // ── URL fetch / device upload ──────────────────────────────────────────────
  Future<void> _fetchUrl(String url) async {
    var u = url.trim();
    if (u.isEmpty) return;
    if (!u.startsWith('http://') && !u.startsWith('https://')) u = 'https://$u';
    setState(() => _busy = true);
    try {
      final res = await Dio().get<String>(u, options: Options(
          responseType: ResponseType.plain, followRedirects: true,
          validateStatus: (s) => s != null && s < 500));
      final body = res.data ?? '';
      await _setCode(body);
      _cur.content = body;
      await _persist();
      _snack('Loaded ${body.length} chars');
    } catch (e) {
      _snack('Could not fetch: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // Open a real file from the device using the system file picker.
  Future<void> _openFromDevice() async {
    try {
      final res = await FilePicker.platform.pickFiles(withData: false);
      if (res == null || res.files.isEmpty) return;
      final pf = res.files.first;
      final path = pf.path;
      if (path == null) { _snack('Could not read that file', error: true); return; }
      String content;
      try {
        content = await File(path).readAsString();
      } catch (_) {
        content = utf8.decode(await File(path).readAsBytes(), allowMalformed: true);
      }
      final name = pf.name.isNotEmpty ? pf.name : 'file.txt';
      await _syncActive();
      setState(() {
        final existing = _files.indexWhere((f) => f.name == name);
        if (existing >= 0) {
          _files[existing].content = content;
          _active = existing;
        } else {
          _files.add(_PFile(name, content, _langForExt(name)));
          _active = _files.length - 1;
        }
      });
      await _setMode(_cur.lang.mode);
      await _setCode(content);
      await _persist();
      _snack('Opened $name');
    } catch (e) {
      _snack('Open failed: $e', error: true);
    }
  }

  // ── Copy / Save / Run ──────────────────────────────────────────────────────
  Future<void> _copy() async {
    final code = await _getCode();
    await Clipboard.setData(ClipboardData(text: code));
    _snack('Copied ${code.length} chars');
  }

  Future<void> _saveProject() async {
    await _syncActive();
    await _persist();
    try {
      final base = await getExternalStorageDirectory()
          ?? await getApplicationDocumentsDirectory();
      final dir = Directory('${base.path}/nova_x_project');
      if (!await dir.exists()) await dir.create(recursive: true);
      for (final f in _files) {
        await File('${dir.path}/${f.name}').writeAsString(f.content);
      }
      _snack('Saved ${_files.length} files to ${dir.path}');
    } catch (e) {
      _snack('Save failed: $e', error: true);
    }
  }

  // Push the current file(s) into the shared X Code Editor workspace so a file
  // opened transiently (URL fetch / page source) becomes available there too.
  Future<void> _saveToWorkspace() async {
    await _syncActive();
    try {
      for (final f in _files) {
        await CodeWorkspaceStore.addFile(f.name, f.content);
      }
      _snack('Saved to X Code Editor workspace');
    } catch (e) {
      _snack('Save failed: $e', error: true);
    }
  }

  String? _indexName() {
    for (final f in _files) { if (f.name.toLowerCase() == 'index.html') return f.name; }
    for (final f in _files) { if (f.name.toLowerCase().endsWith('.html')) return f.name; }
    return null;
  }

  ContentType _ctypeFor(String name) {
    final e = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    switch (e) {
      case 'html': case 'htm':  return ContentType.html;
      case 'css':               return ContentType('text', 'css', charset: 'utf-8');
      case 'js': case 'mjs':    return ContentType('application', 'javascript', charset: 'utf-8');
      case 'json':              return ContentType('application', 'json', charset: 'utf-8');
      case 'svg':               return ContentType('image', 'svg+xml', charset: 'utf-8');
      case 'xml':               return ContentType('application', 'xml', charset: 'utf-8');
      default:                  return ContentType('text', 'plain', charset: 'utf-8');
    }
  }

  Future<void> _run() async {
    await _syncActive();
    await _persist();
    final index = _indexName();
    if (index == null) { _snack('Add an .html file to run a preview', error: true); return; }
    setState(() => _busy = true);
    try {
      final snapshot = { for (final f in _files) f.name: f.content };
      await _server?.close(force: true);
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final idx = index;
      _server!.listen((req) async {
        try {
          var p = Uri.decodeComponent(req.uri.path);
          if (p == '/' || p.isEmpty) p = '/$idx';
          var name = p.startsWith('/') ? p.substring(1) : p;
          final content = snapshot[name];
          final res = req.response;
          res.headers.set('Access-Control-Allow-Origin', '*');
          if (content == null) {
            res.statusCode = HttpStatus.notFound;
            res.headers.contentType = ContentType.text;
            res.write('404 - $name not found');
          } else {
            res.headers.contentType = _ctypeFor(name);
            res.write(content);
          }
          await res.close();
        } catch (_) {
          try { await req.response.close(); } catch (_) {}
        }
      });
      final port = _server!.port;
      if (!mounted) return;
      setState(() => _busy = false);
      await Navigator.push(context, MaterialPageRoute(
        builder: (_) => _PreviewScreen(url: 'http://127.0.0.1:$port/$idx'),
      ));
    } catch (e) {
      if (mounted) setState(() => _busy = false);
      _snack('Could not start preview: $e', error: true);
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.inter(color: Colors.white, fontSize: 13)),
      backgroundColor: error ? AppTheme.danger : AppTheme.bgElevated,
      behavior: SnackBarBehavior.floating,
    ));
  }

  void _pickLanguage() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bgCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          Padding(padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Text('Language', style: GoogleFonts.spaceGrotesk(
                color: AppTheme.textPrimary, fontSize: 17, fontWeight: FontWeight.w700))),
          ...kLangs.map((l) => ListTile(
                dense: true,
                leading: Container(width: 14, height: 14, decoration: BoxDecoration(
                    color: l.color, borderRadius: BorderRadius.circular(4))),
                title: Text(l.label, style: GoogleFonts.inter(
                    color: AppTheme.textPrimary, fontSize: 14.5)),
                trailing: l.label == _cur.lang.label
                    ? const Icon(Icons.check_rounded, color: AppTheme.accentCyan, size: 18) : null,
                onTap: () { Navigator.pop(context); _applyLang(l); },
              )),
        ],
      )),
    );
  }

  // ── UI ─────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      appBar: AppBar(
        backgroundColor: AppTheme.bgCard,
        elevation: 0,
        titleSpacing: 8,
        title: GestureDetector(
          onTap: _pickLanguage,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.code_rounded, color: AppTheme.accentCyan, size: 20),
            const SizedBox(width: 8),
            Text(widget.sharedWorkspace ? 'X Code Editor' : 'Code Editor',
                style: GoogleFonts.spaceGrotesk(
                color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
          ]),
        ),
        actions: [
          // RUN
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: ElevatedButton.icon(
              onPressed: _ready && !_busy ? _run : null,
              icon: const Icon(Icons.play_arrow_rounded, size: 20),
              label: Text('Run', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.success, foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
          PopupMenuButton<String>(
            color: AppTheme.bgElevated,
            icon: const Icon(Icons.more_vert_rounded, color: AppTheme.textSecondary),
            onSelected: (v) {
              if (v == 'open') _openFromDevice();
              if (v == 'copy') _copy();
              if (v == 'save') _saveProject();
              if (v == 'workspace') _saveToWorkspace();
              if (v == 'lang') _pickLanguage();
            },
            itemBuilder: (_) => [
              _mi('open', Icons.folder_open_rounded, 'Open file from device', AppTheme.accentCyan),
              _mi('copy', Icons.copy_rounded, 'Copy current file', AppTheme.textSecondary),
              _mi('save', Icons.save_alt_rounded, 'Save project to device', AppTheme.accentPurple),
              if (!widget.sharedWorkspace)
                _mi('workspace', Icons.bookmark_add_rounded, 'Save to X Code Editor', const Color(0xFF00D4FF)),
              _mi('lang', Icons.palette_rounded, 'Change language', _cur.lang.color),
            ],
          ),
        ],
      ),
      body: Column(children: [
        _fileTabs(),
        Container(height: 3, color: _cur.lang.color),
        Expanded(child: Stack(children: [
          InAppWebView(
            initialData: InAppWebViewInitialData(
                data: _editorHtml, baseUrl: WebUri('https://localhost/')),
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true, transparentBackground: true,
              useWideViewPort: false, supportZoom: false,
            ),
            onWebViewCreated: (c) {
              _wvc = c;
              c.addJavaScriptHandler(handlerName: 'nxReady', callback: (_) { _onReady(); return null; });
              c.addJavaScriptHandler(handlerName: 'nxErr', callback: (a) {
                _snack('Editor error: ${a.isNotEmpty ? a[0] : ''}', error: true); return null; });
              // Debounced autosave: persist the active file to the shared
              // workspace shortly after the user stops typing.
              c.addJavaScriptHandler(handlerName: 'nxChanged', callback: (_) async {
                if (!_ready) return null;
                await _syncActive();
                await _persist();
                return null;
              });
            },
          ),
          if (!_ready || _busy)
            Container(color: AppTheme.bgDark.withOpacity(0.6),
                child: const Center(child: CircularProgressIndicator(color: AppTheme.accentCyan))),
        ])),
      ]),
    );
  }

  PopupMenuItem<String> _mi(String v, IconData ic, String t, Color c) => PopupMenuItem(
        value: v,
        child: Row(children: [
          Icon(ic, size: 18, color: c), const SizedBox(width: 10),
          Text(t, style: GoogleFonts.inter(color: AppTheme.textPrimary)),
        ]),
      );

  Widget _fileTabs() {
    return Container(
      height: 44,
      color: AppTheme.bgCard,
      child: Row(children: [
        Expanded(
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            itemCount: _files.length,
            itemBuilder: (_, i) {
              final f = _files[i];
              final active = i == _active;
              return GestureDetector(
                onTap: () => _switchTo(i),
                onLongPress: () => _fileMenu(i),
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 3),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: active ? AppTheme.bgElevated : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(
                        color: active ? f.lang.color.withOpacity(0.6) : Colors.transparent),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(width: 8, height: 8, decoration: BoxDecoration(
                        color: f.lang.color, borderRadius: BorderRadius.circular(2))),
                    const SizedBox(width: 7),
                    Text(f.name, style: GoogleFonts.jetBrainsMono(
                        color: active ? AppTheme.textPrimary : AppTheme.textHint,
                        fontSize: 12.5,
                        fontWeight: active ? FontWeight.w600 : FontWeight.w400)),
                  ]),
                ),
              );
            },
          ),
        ),
        IconButton(
          icon: const Icon(Icons.add_rounded, color: AppTheme.accentCyan),
          tooltip: 'New file',
          onPressed: _addFileDialog,
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Live preview screen (served by the local HTTP server)
// ─────────────────────────────────────────────────────────────────────────────
class _PreviewScreen extends StatefulWidget {
  final String url;
  const _PreviewScreen({required this.url});
  @override
  State<_PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<_PreviewScreen> {
  InAppWebViewController? _wvc;
  bool _loading = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      appBar: AppBar(
        backgroundColor: AppTheme.bgCard,
        elevation: 0,
        title: Row(children: [
          Container(width: 8, height: 8, decoration: const BoxDecoration(
              color: AppTheme.success, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text('Live Preview', style: GoogleFonts.spaceGrotesk(
              color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
        ]),
        actions: [
          IconButton(
            tooltip: 'Reload',
            icon: const Icon(Icons.refresh_rounded, color: AppTheme.textSecondary),
            onPressed: () => _wvc?.reload(),
          ),
          IconButton(
            tooltip: 'Open in browser',
            icon: const Icon(Icons.open_in_new_rounded, color: AppTheme.textSecondary),
            onPressed: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => BrowserView(initialQuery: widget.url))),
          ),
        ],
      ),
      body: Stack(children: [
        InAppWebView(
          initialUrlRequest: URLRequest(url: WebUri(widget.url)),
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            useWideViewPort: true,
            loadWithOverviewMode: true,
            mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
            clearCache: true,
          ),
          onWebViewCreated: (c) => _wvc = c,
          onLoadStop: (_, __) { if (mounted) setState(() => _loading = false); },
        ),
        if (_loading)
          Container(color: AppTheme.bgDark,
              child: const Center(child: CircularProgressIndicator(color: AppTheme.success))),
      ]),
    );
  }
}
