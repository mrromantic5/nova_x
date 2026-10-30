// lib/features/xcoder/screens/xcoder_screen.dart
//
// X Coder — the NOVA X code editor (3.11.0), built to feel like VS Code on a
// phone:
//   • Projects are real folders; explorer with context menu; open editors
//   • Tabs, per-file undo history, unsaved-changes dots, auto save
//   • Ace editor bundled offline: highlighting for 45+ languages, live
//     suggestions (keywords, snippets, project words), linting with an error
//     gutter, bracket matching, folding, multi-cursor, find/replace (regex),
//     formatting, minimal outline (@ symbols)
//   • Command palette (files, > commands, : line, @ symbol), keyboard
//     shortcuts on hardware keyboards, extra-keys row on the phone keyboard
//   • Bottom panel: Problems · Terminal · Output · Find in files
//   • Terminal with Android's shell tools + `node` (V8) + `serve`
//   • ▶ Run: live preview server with console, JavaScript runner, Markdown
//   • NOVA (Premium): generate, fix with diagnostics, explain, refactor,
//     tests, review — every change shown as a diff first
//   • Export project as .zip, import files or a URL

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/services/rewards_entitlements.dart';
import '../../../core/services/subscription_service.dart';
import '../../ai/widgets/nova_markdown_view.dart';
import '../../premium/screens/subscription_screen.dart';
import '../../devguide/developer_guide_screen.dart';
import '../ai/nova_coder_client.dart';
import '../ai/xcoder_ai.dart';
import '../editor/ace_editor.dart';
import '../run/js_runner.dart';
import '../run/preview_server.dart';
import '../terminal/xcoder_terminal.dart';
import '../widgets/xcoder_agent_sheet.dart';
import '../widgets/xcoder_ai_sheet.dart';
import '../widgets/xcoder_explorer.dart';
import '../widgets/xcoder_keybar.dart';
import '../widgets/xcoder_palette.dart';
import '../widgets/xcoder_panels.dart';
import '../widgets/xcoder_settings.dart';
import '../widgets/xcoder_ui.dart';
import '../workspace/xcoder_workspace.dart';
import 'xcoder_preview_screen.dart';

/// Free plan: this many projects. Premium: unlimited projects + NOVA.
const int kXCoderFreeProjects = 2;

class XDoc {
  XDoc({required this.id, required this.rel, required this.name, required this.mode, this.readOnly = false});
  final String id;
  String? rel; // null = not saved in the project yet
  String name;
  String mode;
  bool dirty = false;
  bool readOnly;
  Timer? saveTimer;

  bool get untitled => rel == null;
}

class XCoderScreen extends StatefulWidget {
  const XCoderScreen({super.key, this.initialContent, this.initialUrl, this.initialFileName, this.initialMode});

  /// Opens this text in a new unsaved tab (e.g. a source from Dev Tools).
  final String? initialContent;

  /// Downloads this address into a new unsaved tab.
  final String? initialUrl;
  final String? initialFileName;
  final String? initialMode;

  @override
  State<XCoderScreen> createState() => _XCoderScreenState();
}

class _XCoderScreenState extends State<XCoderScreen> with WidgetsBindingObserver implements TerminalHost, XAiHost, XAgentHost {
  final _ws = XWorkspace.instance;
  final _ace = AceController();
  final _scaffold = GlobalKey<ScaffoldState>();
  StreamSubscription<AceEvent>? _aceSub;

  XSettings _settings = XSettings();
  XProject? _project;
  XNode? _tree;
  List<String> _files = const [];
  final List<XDoc> _docs = [];
  String? _activeId;
  final Map<String, List<AceAnnotation>> _ann = {};
  AceCursor _cursor = const AceCursor();
  Color _editorBg = XC.bg;
  bool _aceReady = false;
  bool _loading = true;
  int _docSeq = 0;
  final List<String> _recent = [];

  XTerminal? _term;
  XPanel? _panel;
  double _panelHeight = 260;
  bool _panelMax = false;
  final List<OutputLine> _output = [];
  final _saved = StreamController<void>.broadcast();
  String _searchSeed = '';
  bool _flutterTextFocused = false;

  XDoc? get _active => _docs.where((d) => d.id == _activeId).firstOrNull;

  // ── Lifecycle ─────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    FocusManager.instance.addListener(_focusChanged);
    _aceSub = _ace.events.listen(_onAce);
    SubscriptionService.fetchStatus().then((_) {
      if (mounted) setState(() {});
    }).catchError((_) {});
    _boot();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    FocusManager.instance.removeListener(_focusChanged);
    _aceSub?.cancel();
    for (final d in _docs) {
      d.saveTimer?.cancel();
    }
    _term?.dispose();
    _ace.dispose();
    _saved.close();
    PreviewServer.instance.stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Leaving the app: save everything that has a file.
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) _saveAll(quiet: true);
  }

  void _focusChanged() {
    final f = FocusManager.instance.primaryFocus;
    final editing = f?.context?.findAncestorWidgetOfExactType<EditableText>() != null || f?.context?.widget is EditableText;
    if (editing != _flutterTextFocused && mounted) setState(() => _flutterTextFocused = editing);
  }

  Future<void> _boot() async {
    _settings = await XSettings.load();
    _ace.settings(_settings.toAce()); // applied once the editor page is ready
    await _ws.migrateLegacy();
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getString('xcoder_last_project');
    var projects = await _ws.projects();
    if (projects.isEmpty) {
      projects = [await _ws.create('My First Project')];
    }
    final p = projects.firstWhere((e) => e.path == last, orElse: () => projects.first);
    await _openProject(p, restoreTabs: widget.initialContent == null && widget.initialUrl == null);
    if (widget.initialContent != null || widget.initialUrl != null) {
      await _openIncoming();
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _openIncoming() async {
    var content = widget.initialContent ?? '';
    final name = (widget.initialFileName?.trim().isNotEmpty ?? false) ? widget.initialFileName!.trim() : 'untitled.txt';
    if (widget.initialUrl != null && content.isEmpty) {
      try {
        final r = await Dio(BaseOptions(responseType: ResponseType.plain, receiveTimeout: const Duration(seconds: 20)))
            .get<String>(widget.initialUrl!);
        content = r.data ?? '';
      } catch (e) {
        _log('error', 'Could not download ${widget.initialUrl}: $e');
      }
    }
    await _openUntitled(name, content, mode: widget.initialMode ?? aceModeFor(name), readOnly: false);
  }

  // ── Ace events ────────────────────────────────────────────────────────

  void _onAce(AceEvent e) {
    switch (e) {
      case AceReady():
        setState(() => _aceReady = true);
        _ace.settings(_settings.toAce());
      case AceChanged(:final id, :final dirty):
        final d = _docs.where((x) => x.id == id).firstOrNull;
        if (d == null) return;
        if (d.dirty != dirty) setState(() => d.dirty = dirty);
        if (dirty && _settings.autoSave && !d.untitled) {
          d.saveTimer?.cancel();
          d.saveTimer = Timer(const Duration(milliseconds: 1200), () => _save(d, quiet: true));
        }
      case AceCursorMoved(:final id, :final cursor):
        if (id == _activeId) setState(() => _cursor = cursor);
      case AceAnnotations(:final id, :final items):
        setState(() => _ann[id] = items);
      case AceKey(:final key):
        switch (key) {
          case 'save':
            final d = _active;
            if (d != null) _save(d);
          case 'palette':
            _palette('>');
          case 'quickOpen':
            _palette('');
          case 'run':
            _run();
          case 'terminal':
            _togglePanel(XPanel.terminal);
          case 'ai':
            _openAi();
          case 'agent':
            _openAgent();
          case 'aiComplete':
            _aiComplete();
          case 'guide':
            _openGuide();
          case 'findInFiles':
            _openSearch();
        }
      case AceTheme(:final background):
        if (background != null) setState(() => _editorBg = background);
    }
  }

  // ── Projects ──────────────────────────────────────────────────────────

  Future<void> _openProject(XProject p, {bool restoreTabs = true}) async {
    await _saveAll(quiet: true);
    for (final d in [..._docs]) {
      await _ace.close(d.id);
    }
    _docs.clear();
    _ann.clear();
    _activeId = null;
    final oldTerm = _term;
    // dispose after the terminal view has let go of it
    WidgetsBinding.instance.addPostFrameCallback((_) => oldTerm?.dispose());
    _project = p;
    _term = XTerminal(p, this);
    (await SharedPreferences.getInstance()).setString('xcoder_last_project', p.path);
    await _refreshTree();
    if (restoreTabs) {
      final tabs = [...p.openTabs];
      final active = p.activeTab;
      for (final t in tabs) {
        if (_files.contains(t)) await _openFile(t, focus: false, persist: false);
      }
      final target = active != null && _files.contains(active) ? active : (tabs.where(_files.contains).firstOrNull);
      if (target != null) await _openFile(target);
      if (_docs.isEmpty) {
        final first = _files.where((f) => f.toLowerCase() == 'index.html' || f.toLowerCase() == 'readme.md').firstOrNull ??
            _files.where((f) => !f.contains('/')).firstOrNull;
        if (first != null) await _openFile(first);
      }
    }
    _loadProjectWords();
    if (mounted) setState(() {});
  }

  Future<void> _loadProjectWords() async {
    final p = _project;
    if (p == null) return;
    final words = await _ws.projectWords(p);
    await _ace.projectWords(words);
  }

  Future<void> _refreshTree() async {
    final p = _project;
    if (p == null) return;
    final t = await _ws.tree(p);
    final files = <String>[];
    void walk(XNode n) {
      for (final c in n.children) {
        if (c.isDir) {
          walk(c);
        } else {
          files.add(c.rel);
        }
      }
    }

    walk(t);
    if (!mounted) return;
    setState(() {
      _tree = t;
      _files = files;
    });
  }

  Future<void> _persistTabs() async {
    final p = _project;
    if (p == null) return;
    p.openTabs = _docs.where((d) => d.rel != null).map((d) => d.rel!).toList();
    p.activeTab = _active?.rel;
    await p.saveMeta();
  }

  bool get _premium => RewardsEntitlements.isPremium;

  Future<void> _projectsSheet() async {
    final projects = await _ws.projects();
    if (!mounted) return;
    final picked = await showModalBottomSheet<Object>(
      context: context,
      backgroundColor: XC.side,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
              child: Row(children: [
                Text('Projects', style: XC.ui(17, weight: FontWeight.w800)),
                const SizedBox(width: 8),
                if (!_premium) Text('${projects.length}/$kXCoderFreeProjects on Free', style: XC.ui(12, color: XC.faint)),
                const Spacer(),
                FilledButton.icon(
                  onPressed: () => Navigator.pop(ctx, 'new'),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('New'),
                  style: FilledButton.styleFrom(backgroundColor: XC.status, visualDensity: VisualDensity.compact),
                ),
              ]),
            ),
            Flexible(
              child: ListView(shrinkWrap: true, children: [
                for (final p in projects)
                  ListTile(
                    leading: Icon(p.path == _project?.path ? Icons.folder_open_rounded : Icons.folder_rounded,
                        color: p.path == _project?.path ? XC.accent : XC.dim),
                    title: Text(p.name, style: XC.ui(14.5, weight: FontWeight.w600)),
                    subtitle: Text('Edited ${_ago(p.updatedAt)}', style: XC.ui(12, color: XC.faint)),
                    onTap: () => Navigator.pop(ctx, p),
                    trailing: PopupMenuButton<String>(
                      color: XC.side,
                      icon: const Icon(Icons.more_vert_rounded, color: XC.dim),
                      onSelected: (v) => Navigator.pop(ctx, '$v:${p.path}'),
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'rename', child: Text('Rename')),
                        PopupMenuItem(value: 'export', child: Text('Export as .zip')),
                        PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: XC.error))),
                      ],
                    ),
                  ),
              ]),
            ),
          ]),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    if (picked is XProject) {
      if (picked.path != _project?.path) await _openProject(picked);
      _scaffold.currentState?.closeDrawer();
      return;
    }
    final s = picked as String;
    if (s == 'new') {
      await _newProject(projects.length);
      return;
    }
    final i = s.indexOf(':');
    final action = s.substring(0, i);
    final p = projects.firstWhere((e) => e.path == s.substring(i + 1));
    switch (action) {
      case 'rename':
        final n = await xPrompt(context, title: 'Rename project', initial: p.name, validate: (v) => v.trim().isEmpty ? 'Enter a name.' : null);
        if (n != null) {
          p.name = n;
          await p.saveMeta();
          if (p.path == _project?.path) setState(() => _project!.name = n);
        }
      case 'export':
        await _export(p);
      case 'delete':
        if (!await xConfirm(context, 'Delete “${p.name}”?', 'All its files are deleted from this phone. This can’t be undone.')) return;
        await _ws.deleteProject(p);
        if (p.path == _project?.path) {
          var rest = await _ws.projects();
          if (rest.isEmpty) rest = [await _ws.create('My First Project')];
          await _openProject(rest.first);
        }
        if (mounted) xToast(context, 'Project deleted');
    }
  }

  Future<void> _newProject(int count) async {
    if (!_premium && count >= kXCoderFreeProjects) {
      final go = await xConfirm(context, 'More projects with Premium',
          'X Coder Free keeps $kXCoderFreeProjects projects. NOVA X Premium gives unlimited projects and NOVA AI in the editor.',
          action: 'See Premium', danger: false);
      if (go && mounted) await Navigator.push(context, MaterialPageRoute(builder: (_) => const SubscriptionScreen()));
      return;
    }
    if (!mounted) return;
    XTemplate template = XTemplate.web;
    final name = TextEditingController(text: 'My Project');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          backgroundColor: XC.side,
          title: Text('New project', style: XC.ui(17, weight: FontWeight.w800)),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextField(
                controller: name,
                autofocus: true,
                style: XC.ui(14),
                decoration: InputDecoration(
                  labelText: 'Name',
                  filled: true,
                  fillColor: XC.bg,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 12),
              for (final t in XTemplate.values)
                RadioListTile<XTemplate>(
                  value: t,
                  groupValue: template,
                  onChanged: (v) => set(() => template = v!),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  activeColor: XC.accent,
                  title: Text(t.label, style: XC.ui(14, weight: FontWeight.w600)),
                  subtitle: Text(t.description, style: XC.ui(12, color: XC.faint)),
                ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Create')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final p = await _ws.create(name.text.trim().isEmpty ? 'My Project' : name.text.trim(), template: template);
    await _openProject(p);
    _scaffold.currentState?.closeDrawer();
    if (mounted) xToast(context, 'Created ${p.name}');
  }

  Future<void> _export(XProject p) async {
    try {
      await _saveAll(quiet: true);
      final bytes = await _ws.zip(p);
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Export ${p.name}',
        fileName: '${p.folder}.zip',
        bytes: bytes,
        type: FileType.custom,
        allowedExtensions: const ['zip'],
      );
      if (mounted && path != null) xToast(context, 'Exported ${p.folder}.zip (${(bytes.length / 1024).toStringAsFixed(0)} KB)');
    } catch (e) {
      if (mounted) xToast(context, 'Export failed: $e', error: true);
    }
  }

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (t.millisecondsSinceEpoch == 0) return 'earlier';
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours} h ago';
    return '${d.inDays} d ago';
  }

  // ── Files & tabs ──────────────────────────────────────────────────────

  String _newId() => 'd${++_docSeq}';

  Future<void> _openFile(String rel, {int? line, bool focus = true, bool persist = true}) async {
    final p = _project;
    if (p == null) return;
    final existing = _docs.where((d) => d.rel == rel).firstOrNull;
    if (existing != null) {
      await _activate(existing.id);
      if (line != null) await _ace.gotoLine(line);
      return;
    }
    final abs = p.resolve(rel);
    if (abs == null) return;
    final f = File(abs);
    if (!await f.exists()) {
      if (mounted) xToast(context, '$rel no longer exists', error: true);
      await _refreshTree();
      return;
    }
    final ext = rel.contains('.') ? rel.split('.').last.toLowerCase() : '';
    if (const {'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'ico'}.contains(ext)) {
      if (focus && mounted) _showImage(rel, f);
      return;
    }
    final size = await f.length();
    if (size > kXCoderMaxEditableBytes) {
      if (mounted) xToast(context, '$rel is ${(size / 1048576).toStringAsFixed(1)} MB — too large to edit on the phone.', error: true);
      return;
    }
    if (!await _ws.isProbablyText(p, rel)) {
      if (mounted) xToast(context, '$rel is a binary file and can’t be edited.', error: true);
      return;
    }
    final text = await _ws.read(p, rel) ?? '';
    final d = XDoc(id: _newId(), rel: rel, name: rel.split('/').last, mode: aceModeFor(rel));
    _docs.add(d);
    await _ace.open(d.id, text, d.mode, name: d.name, focus: focus);
    if (focus) {
      _activeId = d.id;
      _touchRecent(rel);
      if (line != null) await _ace.gotoLine(line);
    }
    if (persist) await _persistTabs();
    if (mounted) setState(() {});
  }

  Future<void> _openUntitled(String name, String content, {required String mode, bool readOnly = false}) async {
    final d = XDoc(id: _newId(), rel: null, name: name, mode: mode, readOnly: readOnly);
    _docs.add(d);
    await _ace.open(d.id, content, mode, name: name);
    _activeId = d.id;
    if (content.isNotEmpty) {
      d.dirty = true;
    }
    if (mounted) setState(() {});
  }

  void _touchRecent(String rel) {
    _recent.remove(rel);
    _recent.insert(0, rel);
    if (_recent.length > 20) _recent.removeLast();
  }

  Future<void> _activate(String id) async {
    if (_activeId == id) return;
    await _ace.switchTo(id);
    final d = _docs.where((x) => x.id == id).firstOrNull;
    if (d?.rel != null) _touchRecent(d!.rel!);
    setState(() => _activeId = id);
    _persistTabs();
  }

  Future<void> _closeDoc(String id, {bool ask = true}) async {
    final d = _docs.where((x) => x.id == id).firstOrNull;
    if (d == null) return;
    if (d.dirty) {
      if (!d.untitled && _settings.autoSave) {
        await _save(d, quiet: true);
      } else if (ask) {
        final r = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: XC.side,
            title: Text('Save changes to ${d.name}?', style: XC.ui(16, weight: FontWeight.w700)),
            content: Text('Your changes will be lost if you don’t save them.', style: XC.ui(14, color: XC.dim)),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, 'discard'), child: const Text('Don’t save', style: TextStyle(color: XC.error))),
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: const Text('Save')),
            ],
          ),
        );
        if (r == null) return;
        if (r == 'save' && !await _save(d)) return;
      }
    }
    d.saveTimer?.cancel();
    final i = _docs.indexOf(d);
    _docs.remove(d);
    _ann.remove(id);
    await _ace.close(id);
    if (_activeId == id) {
      _activeId = null;
      if (_docs.isNotEmpty) await _activate(_docs[(i - 1).clamp(0, _docs.length - 1)].id);
    }
    await _persistTabs();
    if (mounted) setState(() {});
  }

  /// Saves one document. Returns false when nothing was saved.
  Future<bool> _save(XDoc d, {bool quiet = false}) async {
    d.saveTimer?.cancel();
    final p = _project;
    if (p == null) return false;
    if (d.untitled) {
      if (quiet) return false;
      final name = await xPrompt(context,
          title: 'Save as', initial: d.name, hint: 'path/in/project.ext', action: 'Save', validate: (v) {
        final n = XWorkspace.normalize(v);
        if (n == null || n.isEmpty) return 'Enter a file name inside the project.';
        return null;
      });
      if (name == null) return false;
      final rel = XWorkspace.normalize(name)!;
      if (await _ws.exists(p, rel) &&
          mounted &&
          !await xConfirm(context, 'Replace $rel?', 'A file with this name already exists in the project.', action: 'Replace')) {
        return false;
      }
      d.rel = rel;
      d.name = rel.split('/').last;
      final mode = aceModeFor(rel);
      if (mode != d.mode) {
        d.mode = mode;
        await _ace.setMode(mode, d.id);
      }
    }
    if (_settings.formatOnSave && d.id == _activeId && !quiet) await _ace.format();
    final text = await _ace.value(d.id);
    if (text == null) return false;
    try {
      await _ws.write(p, d.rel!, text);
      await _ace.markSaved(d.id);
      if (mounted) setState(() => d.dirty = false);
      _saved.add(null);
      if (!quiet && mounted) xToast(context, 'Saved ${d.rel}');
      if (!_files.contains(d.rel)) {
        await _refreshTree();
        await _persistTabs();
      }
      return true;
    } catch (e) {
      if (mounted) xToast(context, 'Couldn’t save ${d.name}: $e', error: true);
      return false;
    }
  }

  Future<void> _saveAll({bool quiet = false}) async {
    var n = 0;
    for (final d in [..._docs]) {
      if (d.dirty && !d.untitled) {
        if (await _save(d, quiet: true)) n++;
      }
    }
    if (!quiet && mounted) xToast(context, n == 0 ? 'Everything is saved' : 'Saved $n file${n == 1 ? '' : 's'}');
  }

  /// Reload open files from disk (after terminal commands, replace in files).
  Future<void> _reloadOpenFromDisk() async {
    final p = _project;
    if (p == null) return;
    for (final d in _docs) {
      if (d.rel == null || d.dirty) continue;
      final text = await _ws.read(p, d.rel!);
      if (text == null) continue;
      final cur = await _ace.value(d.id);
      if (cur != text) await _ace.setValue(text, id: d.id, keepUndo: d.id == _activeId, markSaved: true);
      if (d.id == _activeId) await _ace.markSaved(d.id);
    }
  }

  // ── Explorer actions ──────────────────────────────────────────────────

  late final ExplorerActions _explorerActions = ExplorerActions(
    open: (rel) {
      _scaffold.currentState?.closeDrawer();
      _openFile(rel);
    },
    newFile: (folder) => _newEntry(folder, isFolder: false),
    newFolder: (folder) => _newEntry(folder, isFolder: true),
    rename: _renameNode,
    duplicate: (n) async {
      final p = _project!;
      final t = await _ws.duplicate(p, n.rel);
      await _refreshTree();
      if (mounted) xToast(context, 'Created $t');
    },
    delete: _deleteNode,
    copyPath: (n) {
      Clipboard.setData(ClipboardData(text: n.rel));
      xToast(context, 'Copied ${n.rel}');
    },
    run: (rel) {
      _scaffold.currentState?.closeDrawer();
      runFile(rel);
    },
    refresh: _refreshTree,
    switchProject: _projectsSheet,
    importFiles: _importFiles,
    closeTab: (id) => _closeDoc(id),
  );

  Future<void> _newEntry(String folder, {required bool isFolder}) async {
    final p = _project;
    if (p == null) return;
    final name = await xPrompt(context,
        title: isFolder ? 'New folder' : 'New file',
        hint: isFolder ? 'folder name' : 'name.ext (e.g. app.js, styles/main.css)',
        action: 'Create', validate: (v) {
      final n = XWorkspace.normalize(v);
      if (n == null || n.isEmpty) return 'Enter a valid name.';
      for (final part in n.split('/')) {
        final e = XWorkspace.validName(part);
        if (e != null) return e;
      }
      return null;
    });
    if (name == null) return;
    final rel = XWorkspace.normalize(folder.isEmpty ? name : '$folder/$name')!;
    if (await _ws.exists(p, rel)) {
      if (mounted) xToast(context, '$rel already exists', error: true);
      return;
    }
    try {
      if (isFolder) {
        await _ws.createFolder(p, rel);
      } else {
        await _ws.write(p, rel, '');
      }
      await _refreshTree();
      if (!isFolder) {
        _scaffold.currentState?.closeDrawer();
        await _openFile(rel);
      }
    } catch (e) {
      if (mounted) xToast(context, 'Couldn’t create $rel: $e', error: true);
    }
  }

  Future<void> _renameNode(XNode n) async {
    final p = _project!;
    final name = await xPrompt(context, title: 'Rename', initial: n.name, action: 'Rename', validate: XWorkspace.validName);
    if (name == null || name == n.name) return;
    final parent = n.rel.contains('/') ? n.rel.substring(0, n.rel.lastIndexOf('/')) : '';
    final to = parent.isEmpty ? name : '$parent/$name';
    try {
      await _saveAll(quiet: true);
      await _ws.rename(p, n.rel, to);
      for (final d in _docs) {
        final r = d.rel;
        if (r == null) continue;
        if (r == n.rel || r.startsWith('${n.rel}/')) {
          d.rel = to + r.substring(n.rel.length);
          d.name = d.rel!.split('/').last;
          final m = aceModeFor(d.rel!);
          if (m != d.mode) {
            d.mode = m;
            await _ace.setMode(m, d.id);
          }
        }
      }
      await _refreshTree();
      await _persistTabs();
    } catch (e) {
      if (mounted) xToast(context, 'Rename failed: $e', error: true);
    }
  }

  Future<void> _deleteNode(XNode n) async {
    final p = _project!;
    if (!await xConfirm(context, 'Delete ${n.name}?',
        n.isDir ? 'The folder and everything in it are deleted from this phone.' : 'The file is deleted from this phone.')) {
      return;
    }
    try {
      for (final d in [..._docs]) {
        final r = d.rel;
        if (r != null && (r == n.rel || r.startsWith('${n.rel}/'))) {
          d.dirty = false;
          await _closeDoc(d.id, ask: false);
        }
      }
      await _ws.delete(p, n.rel);
      await _refreshTree();
    } catch (e) {
      if (mounted) xToast(context, 'Delete failed: $e', error: true);
    }
  }

  Future<void> _importFiles(String folder) async {
    final p = _project;
    if (p == null) return;
    try {
      final res = await FilePicker.platform.pickFiles(allowMultiple: true, withData: false);
      if (res == null) return;
      var n = 0;
      for (final f in res.files) {
        final src = f.path;
        if (src == null) continue;
        final rel = XWorkspace.normalize(folder.isEmpty ? f.name : '$folder/${f.name}');
        if (rel == null || rel.isEmpty) continue;
        final dst = p.resolve(rel)!;
        await File(dst).parent.create(recursive: true);
        await File(src).copy(dst);
        n++;
      }
      await _refreshTree();
      if (mounted) xToast(context, 'Imported $n file${n == 1 ? '' : 's'}');
      if (n == 1 && res.files.first.path != null) {
        final rel = XWorkspace.normalize(folder.isEmpty ? res.files.first.name : '$folder/${res.files.first.name}');
        if (rel != null) {
          _scaffold.currentState?.closeDrawer();
          await _openFile(rel);
        }
      }
    } catch (e) {
      if (mounted) xToast(context, 'Import failed: $e', error: true);
    }
  }

  Future<void> _importUrl() async {
    final url = await xPrompt(context, title: 'Download a file from a URL', hint: 'https://…', action: 'Download', validate: (v) {
      final u = Uri.tryParse(v.trim());
      return u == null || !(u.scheme == 'https' || u.scheme == 'http') ? 'Enter an http(s) address.' : null;
    });
    if (url == null || _project == null) return;
    try {
      final uri = Uri.parse(url);
      var name = uri.pathSegments.where((s) => s.isNotEmpty).lastOrNull ?? 'index.html';
      if (!name.contains('.')) name = '$name.html';
      final r = await Dio(BaseOptions(responseType: ResponseType.bytes, receiveTimeout: const Duration(seconds: 30)))
          .get<List<int>>(url);
      final bytes = r.data ?? const <int>[];
      if (bytes.length > kXCoderMaxEditableBytes) throw 'file is larger than 2 MB';
      final p = _project!;
      var rel = name;
      var i = 2;
      while (await _ws.exists(p, rel)) {
        final dot = name.lastIndexOf('.');
        rel = '${name.substring(0, dot)}-$i${name.substring(dot)}';
        i++;
      }
      await _ws.write(p, rel, utf8.decode(bytes, allowMalformed: true));
      await _refreshTree();
      await _openFile(rel);
    } catch (e) {
      if (mounted) xToast(context, 'Download failed: $e', error: true);
    }
  }

  void _showImage(String rel, File f) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(backgroundColor: XC.bar, title: Text(rel, style: XC.ui(14))),
          body: Center(child: InteractiveViewer(maxScale: 8, child: Image.file(f))),
        ),
      ),
    );
  }

  // ── Run ───────────────────────────────────────────────────────────────

  void _log(String level, String text) {
    if (!mounted) return;
    setState(() {
      _output.add(OutputLine(level, text, DateTime.now()));
      if (_output.length > 1000) _output.removeRange(0, _output.length - 1000);
    });
  }

  Future<void> _run() => runFile(_active?.rel);

  @override
  Future<void> runFile(String? rel) async {
    final p = _project;
    final d = _active;
    if (p == null) return;
    await _saveAll(quiet: true);
    if (rel == null) {
      if (d != null && d.untitled) {
        // run unsaved JS directly
        if (d.mode == 'javascript') {
          final code = await _ace.value(d.id) ?? '';
          _runJs(code, d.name);
          return;
        }
        if (mounted) xToast(context, 'Save the file in the project first (Ctrl+S or ⋮ › Save).');
        return;
      }
      // no file: preview the site if there's an index.html
      final index = _files.where((f) => f.toLowerCase().endsWith('index.html')).firstOrNull;
      if (index != null) return startPreview(index);
      if (mounted) xToast(context, 'Open a file to run it.');
      return;
    }
    final ext = rel.contains('.') ? rel.split('.').last.toLowerCase() : '';
    switch (ext) {
      case 'html' || 'htm' || 'svg':
        await startPreview(rel);
      case 'js' || 'mjs' || 'cjs':
        final code = await _ws.read(p, rel) ?? '';
        _runJs(code, rel);
      case 'md' || 'markdown':
        final text = d?.rel == rel ? (await _ace.value(d!.id) ?? '') : (await _ws.read(p, rel) ?? '');
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => Scaffold(
              backgroundColor: XC.bg,
              appBar: AppBar(backgroundColor: XC.bar, title: Text(rel, style: XC.ui(15, weight: FontWeight.w700))),
              body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: NovaMarkdownView(text: text)),
            ),
          ),
        );
      case 'json':
        final text = await _ws.read(p, rel) ?? '';
        try {
          final v = jsonDecode(text);
          _log('system', '✓ $rel is valid JSON (${v is List ? '${v.length} items' : v is Map ? '${v.length} keys' : v.runtimeType})');
        } on FormatException catch (e) {
          _log('error', '✗ $rel: ${e.message}${e.offset != null ? ' at character ${e.offset}' : ''}');
        }
        _showPanel(XPanel.output);
      case 'css' || 'scss':
        final index = _files.where((f) => f.toLowerCase().endsWith('.html')).firstOrNull;
        if (index != null) {
          await startPreview(index);
        } else if (mounted) {
          xToast(context, 'Add an HTML file that uses this stylesheet to preview it.');
        }
      case 'sh':
        _showPanel(XPanel.terminal);
        await _term?.submit('sh ${_shellQuote(rel)}');
      case 'php':
        if (mounted) xToast(context, 'PHP runs on a server — upload it, or preview the HTML parts here.');
      default:
        if (mounted) {
          final lang = kAceModeLabels[aceModeFor(rel)] ?? ext.toUpperCase();
          xToast(context, '$lang can’t run on the phone. Use NOVA to explain or test it, or run it on a computer.');
        }
    }
  }

  static String _shellQuote(String s) => "'${s.replaceAll("'", "'\\''")}'";

  void _runJs(String code, String name) {
    _showPanel(XPanel.output);
    _log('system', '▶ node $name');
    final sw = Stopwatch()..start();
    JsRunner.run(code, fileName: name).listen(
      (l) {
        if (l.text.isNotEmpty) _log(l.level, l.text);
      },
      onDone: () => _log('system', '■ finished in ${sw.elapsedMilliseconds} ms'),
    );
  }

  @override
  Future<void> startPreview(String? rel) async {
    final p = _project;
    if (p == null) return;
    await _saveAll(quiet: true);
    final target = rel ?? _files.where((f) => f.toLowerCase().endsWith('index.html')).firstOrNull ?? _active?.rel ?? '';
    final base = await PreviewServer.instance.start(p.path);
    final url = '$base${target.split('/').map(Uri.encodeComponent).join('/')}';
    _log('system', 'Preview: ${url.replaceFirst(RegExp(r'^http://127\.0\.0\.1:\d+'), 'localhost')}');
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => XPreviewScreen(
          url: url,
          title: target.isEmpty ? p.name : target.split('/').last,
          reloads: _saved.stream,
          onConsole: _log,
        ),
      ),
    );
  }

  // ── TerminalHost ──────────────────────────────────────────────────────

  @override
  Future<void> openFile(String rel, {int? line}) => _openFile(rel, line: line);

  @override
  Future<void> refreshExplorer() async {
    await _refreshTree();
    await _reloadOpenFromDisk();
  }

  @override
  Future<String?> currentFile() async => _active?.rel;

  @override
  Future<void> openGuide(String section) async => _openGuide(section);

  @override
  Future<void> askNova(String question, {bool agent = false}) async {
    if (agent) {
      _openAgent(question);
    } else if (_active == null) {
      _openAgent(question);
    } else {
      showXAiSheet(context, this, task: XAiTask.ask, prompt: question);
    }
  }

  // ── XAiHost ───────────────────────────────────────────────────────────

  @override
  String get fileName => _active?.rel ?? _active?.name ?? 'untitled';

  @override
  String get languageLabel => kAceModeLabels[_active?.mode ?? 'text'] ?? 'Plain Text';

  @override
  List<AceAnnotation> get fileProblems => _ann[_activeId] ?? const [];

  @override
  Future<Map<String, dynamic>> editorContext() => _ace.context();

  @override
  Future<List<({String name, String snippet})>> relatedFiles() async {
    final out = <({String name, String snippet})>[];
    for (final d in _docs) {
      if (d.id == _activeId || out.length >= 4) continue;
      final v = await _ace.value(d.id) ?? '';
      if (v.trim().isEmpty) continue;
      out.add((name: d.rel ?? d.name, snippet: v.length > 3000 ? v.substring(0, 3000) : v));
    }
    return out;
  }

  @override
  Future<void> insertCode(String code, {required bool replaceSelection}) =>
      _ace.insert(code, where: replaceSelection ? 'replaceSelection' : 'cursor');

  @override
  Future<void> replaceFile(String code) => _ace.insert(code, where: 'replaceAll');

  @override
  Future<void> createFile(String suggestedName, String content) async {
    final p = _project;
    if (p == null) return;
    final name = await xPrompt(context, title: 'New file from NOVA', initial: suggestedName, action: 'Create', validate: (v) {
      final n = XWorkspace.normalize(v);
      return n == null || n.isEmpty ? 'Enter a file name.' : null;
    });
    if (name == null) return;
    final rel = XWorkspace.normalize(name)!;
    if (await _ws.exists(p, rel) && mounted && !await xConfirm(context, 'Replace $rel?', 'The file already exists.', action: 'Replace')) {
      return;
    }
    await _ws.write(p, rel, content);
    await _refreshTree();
    await _openFile(rel);
  }

  // ── NOVA Coder context & agent host (3.11.1) ───────────────────────────

  @override
  String get projectName => _project?.name ?? 'Project';

  @override
  Future<List<String>> projectFiles() async => _files;

  @override
  Future<String?> readProjectFile(String rel) async {
    final clean = XWorkspace.normalize(rel);
    final p = _project;
    if (clean == null || clean.isEmpty || p == null) return null;
    final open = _docs.where((d) => d.rel == clean).firstOrNull;
    if (open != null) return _ace.value(open.id); // unsaved edits included
    if (!await _ws.exists(p, clean)) return null;
    if (!await _ws.isProbablyText(p, clean)) return '(binary file)';
    return _ws.read(p, clean);
  }

  @override
  Future<Map<String, Object?>> coderContext({required bool includeSelection, bool wholeFile = true}) async {
    final d = _active;
    final ctx = d == null ? const <String, dynamic>{} : await _ace.context();
    final value = (ctx['value'] as String?) ?? '';
    final others = <Map<String, String>>[];
    for (final o in _docs) {
      if (o.id == _activeId || others.length >= 6) continue;
      final v = await _ace.value(o.id) ?? '';
      if (v.trim().isEmpty) continue;
      others.add({'path': o.rel ?? o.name, 'content': v.length > 20000 ? v.substring(0, 20000) : v});
    }
    final term = _term?.lines ?? const <TermLine>[];
    final termTail = term.skip(term.length > 60 ? term.length - 60 : 0).map((l) => l.text).join('\n');
    final outTail = _output.skip(_output.length > 40 ? _output.length - 40 : 0).map((l) => '[${l.level}] ${l.text}').join('\n');
    return {
      'project': _project?.name ?? '',
      'tree': _files.take(2500).toList(),
      if (d != null)
        'activeFile': {
          'path': d.rel ?? d.name,
          'language': kAceModeLabels[d.mode] ?? d.mode,
          if (wholeFile) 'content': value.length > 60000 ? value.substring(0, 60000) : value,
          if (includeSelection && ((ctx['selection'] as String?) ?? '').isNotEmpty) 'selection': ctx['selection'],
          'cursorLine': _cursor.row,
        },
      if (others.isNotEmpty) 'files': others,
      'diagnostics': [
        for (final p in _problems.take(60)) {'path': p.rel ?? p.name, 'row': p.a.row, 'type': p.a.type, 'text': p.a.text}
      ],
      if (termTail.trim().isNotEmpty) 'terminal': termTail,
      if (outTail.trim().isNotEmpty) 'console': outTail,
    };
  }

  @override
  Future<List<String>> applyAgentEdits(List<AgentEdit> edits) async {
    final p = _project;
    if (p == null) return const ['✗ No project open'];
    final out = <String>[];
    for (final e in edits) {
      final rel = XWorkspace.normalize(e.path);
      if (rel == null || rel.isEmpty) {
        out.add('✗ ${e.path}: invalid path');
        continue;
      }
      try {
        final open = _docs.where((d) => d.rel == rel).firstOrNull;
        if (e.action == 'delete') {
          if (open != null) {
            open.dirty = false;
            await _closeDoc(open.id, ask: false);
          }
          await _ws.delete(p, rel);
          out.add('✓ $rel deleted');
          continue;
        }
        final text = e.content ?? '';
        if (open != null) {
          // through the editor, so Undo can revert it
          await _ace.setValue(text, id: open.id, keepUndo: open.id == _activeId);
          await _save(open, quiet: true);
        } else {
          await _ws.write(p, rel, text);
        }
        out.add('✓ $rel ${e.action == 'create' ? 'created' : 'updated'}');
      } catch (err) {
        out.add('✗ $rel: $err');
      }
    }
    await _refreshTree();
    _saved.add(null);
    final firstNew = edits.where((e) => e.action == 'create').firstOrNull;
    if (firstNew != null) await _openFile(XWorkspace.normalize(firstNew.path) ?? firstNew.path);
    return out;
  }

  @override
  Future<void> runInTerminal(String command) async {
    _showPanel(XPanel.terminal);
    await _term?.submit(command);
  }

  void _openAgent([String instruction = '']) => showXAgentSheet(context, this, instruction: instruction);

  void _openGuide([String section = 'xcoder']) => Navigator.push(
      context, MaterialPageRoute(builder: (_) => DeveloperGuideScreen(initialSection: section)));

  /// AI completion at the cursor (NOVA Coder Fast), inserted highlighted; Undo removes it.
  Future<void> _aiComplete() async {
    final d = _active;
    if (d == null) return;
    if (!XCoderAi.available) {
      _openAi(XAiTask.complete);
      return;
    }
    final c = await _ace.context();
    final before = '${c['before'] ?? ''}\n${((c['line'] as String?) ?? '').substring(0, ((c['column'] as num?) ?? 0).toInt().clamp(0, ((c['line'] as String?) ?? '').length))}';
    final line = (c['line'] as String?) ?? '';
    final col = ((c['column'] as num?) ?? 0).toInt().clamp(0, line.length);
    final after = '${line.substring(col)}\n${c['after'] ?? ''}';
    if (mounted) xToast(context, 'NOVA is completing…');
    try {
      final text = await NovaCoderClient().complete(
          path: d.rel ?? d.name, language: kAceModeLabels[d.mode] ?? d.mode, prefix: before, suffix: after);
      if (text.trim().isEmpty) {
        if (mounted) xToast(context, 'No suggestion here.');
        return;
      }
      await _ace.insert(text);
    } on CoderException catch (e) {
      if (mounted) xToast(context, e.message, error: true);
    }
  }

  void _fixTerminalError() {
    if (_active == null) {
      xToast(context, 'Open the file the error is about first.');
      return;
    }
    showXAiSheet(context, this, task: XAiTask.debug, prompt: 'Explain and fix the error in the terminal / console output.');
  }

  void _openAi([XAiTask task = XAiTask.ask]) {
    if (_active == null) {
      xToast(context, 'Open or create a file first.');
      return;
    }
    showXAiSheet(context, this, task: task);
  }

  // ── Panels, palette, search ───────────────────────────────────────────

  void _showPanel(XPanel p) => setState(() => _panel = p);

  void _togglePanel(XPanel p) => setState(() => _panel = _panel == p ? null : p);

  Future<void> _openSearch() async {
    final sel = await _ace.selection();
    setState(() {
      _searchSeed = sel.contains('\n') ? '' : sel;
      _panel = XPanel.search;
    });
  }

  List<XProblem> get _problems => [
        for (final d in _docs)
          for (final a in _ann[d.id] ?? const <AceAnnotation>[]) XProblem(d.rel, d.rel ?? d.name, a),
      ];

  late final List<XCommand> _commands = [
    XCommand('save', 'Save', Icons.save_outlined, () async {
      final d = _active;
      if (d != null) await _save(d);
    }, category: 'File', keys: 'Ctrl+S'),
    XCommand('saveAll', 'Save all', Icons.save_alt_rounded, () => _saveAll(), category: 'File'),
    XCommand('newFile', 'New file…', Icons.note_add_outlined, () => _newEntry('', isFolder: false), category: 'File'),
    XCommand('newFolder', 'New folder…', Icons.create_new_folder_outlined, () => _newEntry('', isFolder: true), category: 'File'),
    XCommand('untitled', 'New untitled file', Icons.edit_note_rounded,
        () => _openUntitled('untitled-${_docSeq + 1}.txt', '', mode: 'text'), category: 'File'),
    XCommand('import', 'Import files from the phone…', Icons.file_upload_outlined, () => _importFiles(''), category: 'File'),
    XCommand('importUrl', 'Download file from URL…', Icons.cloud_download_outlined, _importUrl, category: 'File'),
    XCommand('close', 'Close editor', Icons.close_rounded, () async {
      final d = _active;
      if (d != null) await _closeDoc(d.id);
    }, category: 'View'),
    XCommand('closeAll', 'Close all editors', Icons.clear_all_rounded, () async {
      for (final d in [..._docs]) {
        await _closeDoc(d.id);
      }
    }, category: 'View'),
    XCommand('run', 'Run / preview current file', Icons.play_arrow_rounded, _run, category: 'Run', keys: 'F5'),
    XCommand('preview', 'Preview website', Icons.public_rounded, () => startPreview(null), category: 'Run'),
    XCommand('terminal', 'Toggle terminal', Icons.terminal_rounded, () async => _togglePanel(XPanel.terminal), category: 'View', keys: 'Ctrl+`'),
    XCommand('problems', 'Show problems', Icons.error_outline_rounded, () async => _showPanel(XPanel.problems), category: 'View'),
    XCommand('output', 'Show output', Icons.list_alt_rounded, () async => _showPanel(XPanel.output), category: 'View'),
    XCommand('search', 'Find in files', Icons.manage_search_rounded, _openSearch, category: 'Search', keys: 'Ctrl+Shift+F'),
    XCommand('find', 'Find / replace in file', Icons.find_replace_rounded, () => _ace.cmd('searchBox', {'replace': true}),
        category: 'Search', keys: 'Ctrl+H'),
    XCommand('gotoLine', 'Go to line…', Icons.format_list_numbered_rounded, () => _palette(':'), category: 'Go', keys: 'Ctrl+G'),
    XCommand('gotoSymbol', 'Go to symbol in file…', Icons.data_object_rounded, () => _palette('@'), category: 'Go'),
    XCommand('outline', 'Outline', Icons.account_tree_outlined, _outline, category: 'View'),
    XCommand('format', 'Format document', Icons.auto_fix_high_rounded, _format, category: 'Edit', keys: 'Shift+Alt+F'),
    XCommand('comment', 'Toggle line comment', Icons.comment_outlined, () => _ace.cmd('toggleComment'), category: 'Edit', keys: 'Ctrl+/'),
    XCommand('duplicate', 'Duplicate line / selection', Icons.control_point_duplicate_rounded, () => _ace.cmd('duplicate'),
        category: 'Edit'),
    XCommand('moveUp', 'Move line up', Icons.arrow_upward_rounded, () => _ace.cmd('moveLines', {'up': true}), category: 'Edit',
        keys: 'Alt+↑'),
    XCommand('moveDown', 'Move line down', Icons.arrow_downward_rounded, () => _ace.cmd('moveLines', {'up': false}),
        category: 'Edit', keys: 'Alt+↓'),
    XCommand('deleteLine', 'Delete line', Icons.backspace_outlined, () => _ace.cmd('deleteLine'), category: 'Edit',
        keys: 'Ctrl+Shift+K'),
    XCommand('selectNext', 'Add selection to next match (multi-cursor)', Icons.select_all_rounded,
        () => _ace.cmd('selectNextOccurrence'), category: 'Selection', keys: 'Ctrl+D'),
    XCommand('selectAll', 'Select all', Icons.select_all_rounded, () => _ace.cmd('selectAll'), category: 'Selection'),
    XCommand('upper', 'Transform to uppercase', Icons.text_increase_rounded, () => _ace.cmd('upper'), category: 'Edit'),
    XCommand('lower', 'Transform to lowercase', Icons.text_decrease_rounded, () => _ace.cmd('lower'), category: 'Edit'),
    XCommand('sort', 'Sort lines', Icons.sort_by_alpha_rounded, () => _ace.cmd('sortLines'), category: 'Edit'),
    XCommand('trim', 'Trim trailing whitespace', Icons.cleaning_services_outlined, () => _ace.cmd('trimWhitespace'),
        category: 'Edit'),
    XCommand('fold', 'Fold all', Icons.unfold_less_rounded, () => _ace.cmd('foldAll'), category: 'View'),
    XCommand('unfold', 'Unfold all', Icons.unfold_more_rounded, () => _ace.cmd('unfoldAll'), category: 'View'),
    XCommand('wrap', 'Toggle word wrap', Icons.wrap_text_rounded, () async {
      _settings.wrap = !_settings.wrap;
      await _applySettings();
    }, category: 'View', keys: 'Alt+Z'),
    XCommand('language', 'Change language mode…', Icons.translate_rounded, _changeLanguage, category: 'View'),
    XCommand('settings', 'Editor settings', Icons.tune_rounded, _openSettings, category: 'Preferences'),
    XCommand('theme', 'Color theme…', Icons.palette_outlined, _openSettings, category: 'Preferences'),
    XCommand('projects', 'Switch project…', Icons.folder_copy_outlined, _projectsSheet, category: 'Project'),
    XCommand('newProject', 'New project…', Icons.create_new_folder_rounded, () async => _newProject((await _ws.projects()).length),
        category: 'Project'),
    XCommand('export', 'Export project as .zip', Icons.folder_zip_outlined, () async {
      final p = _project;
      if (p != null) await _export(p);
    }, category: 'Project'),
    XCommand('copyPath', 'Copy path of active file', Icons.link_rounded, () async {
      final r = _active?.rel;
      if (r != null) await Clipboard.setData(ClipboardData(text: r));
    }, category: 'File'),
    for (final t in XAiTask.values)
      XCommand('ai.${t.wire}', 'NOVA: ${t.label} — ${t.hint}', Icons.auto_awesome_rounded, () async => _openAi(t),
          category: 'NOVA', premium: true),
    XCommand('agent', 'NOVA Agent: change the project from a description…', Icons.smart_toy_outlined, () async => _openAgent(),
        category: 'NOVA', premium: true, keys: 'Ctrl+Shift+I'),
    XCommand('aiComplete', 'NOVA: Complete code at the cursor (AI)', Icons.bolt_rounded, _aiComplete,
        category: 'NOVA', premium: true, keys: 'Alt+\\'),
    XCommand('fixTerminal', 'NOVA: Explain & fix the last terminal / console error', Icons.bug_report_outlined,
        () async => _fixTerminalError(), category: 'NOVA', premium: true),
    XCommand('guide', 'Developer Guide', Icons.menu_book_rounded, () async => _openGuide(), category: 'Help', keys: 'F1'),
    XCommand('guideTerminal', 'Developer Guide: terminal commands', Icons.terminal_rounded, () async => _openGuide('terminal'),
        category: 'Help'),
  ];

  Future<void> _palette(String initial) async {
    final r = await showCommandPalette(
      context,
      commands: _commands,
      files: _files,
      symbols: _ace.outline,
      initial: initial,
      recentFiles: _recent,
    );
    if (r == null) return;
    if (r.command != null) {
      await r.command!.run();
    } else if (r.file != null) {
      await _openFile(r.file!);
    } else if (r.line != null) {
      await _ace.gotoLine(r.line!);
    } else if (r.symbolRow != null) {
      await _ace.gotoLine(r.symbolRow!);
    }
  }

  Future<void> _outline() async {
    final items = await _ace.outline();
    if (!mounted) return;
    final row = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: XC.side,
      builder: (ctx) => SafeArea(
        child: items.isEmpty
            ? Padding(padding: const EdgeInsets.all(30), child: Text('No symbols found in this file.', style: XC.ui(13, color: XC.dim)))
            : ListView(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                  child: Text('OUTLINE', style: XC.ui(11.5, color: XC.dim, weight: FontWeight.w800)),
                ),
                for (final s in items)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.only(left: 16.0 + (s.indent.clamp(0, 16) * 4), right: 16),
                    leading: const Icon(Icons.data_object_rounded, size: 16, color: XC.info),
                    title: Text(s.name, style: XC.mono(13)),
                    trailing: Text('${s.row + 1}', style: XC.mono(11, color: XC.faint)),
                    onTap: () => Navigator.pop(ctx, s.row),
                  ),
              ]),
      ),
    );
    if (row != null) await _ace.gotoLine(row);
  }

  Future<void> _format() async {
    final r = await _ace.format();
    if (!mounted) return;
    if (!r.ok) xToast(context, r.error ?? 'Couldn’t format', error: true);
  }

  Future<void> _changeLanguage() async {
    final d = _active;
    if (d == null) return;
    final modes = kAceModeLabels.entries.where((e) => e.key != 'plain_text').toList()..sort((a, b) => a.value.compareTo(b.value));
    final m = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: XC.side,
      builder: (ctx) => SafeArea(
        child: ListView(children: [
          for (final e in modes)
            ListTile(
              dense: true,
              title: Text(e.value, style: XC.ui(14)),
              trailing: d.mode == e.key ? const Icon(Icons.check_rounded, color: XC.accent) : null,
              onTap: () => Navigator.pop(ctx, e.key),
            ),
        ]),
      ),
    );
    if (m == null) return;
    d.mode = m;
    await _ace.setMode(m, d.id);
    setState(() {});
  }

  Future<void> _applySettings() async {
    await _settings.save();
    await _ace.settings(_settings.toAce());
    if (mounted) setState(() {});
  }

  Future<void> _openSettings() => showXSettings(context, _settings, (_) => _applySettings());

  Future<bool> _onWillLeave() async {
    await _saveAll(quiet: true);
    final unsaved = _docs.where((d) => d.dirty).toList();
    if (unsaved.isEmpty) return true;
    if (!mounted) return true;
    return xConfirm(context, 'Leave X Coder?',
        '${unsaved.map((d) => d.name).join(', ')} ${unsaved.length == 1 ? 'isn’t' : 'aren’t'} saved in the project and will be lost.',
        action: 'Leave');
  }

  // ── UI ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.of(context).viewInsets.bottom > 0;
    final showKeyBar = keyboard && _settings.keyBar && !_flutterTextFocused && _active != null && _panel != XPanel.terminal;
    final p = _project;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (_scaffold.currentState?.isDrawerOpen ?? false) {
          _scaffold.currentState?.closeDrawer();
          return;
        }
        if (_panel != null) {
          setState(() => _panel = null);
          return;
        }
        if (await _onWillLeave() && mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        key: _scaffold,
        backgroundColor: XC.bg,
        drawerEdgeDragWidth: 24,
        drawer: p == null
            ? null
            : Drawer(
                width: (MediaQuery.of(context).size.width * 0.86).clamp(260.0, 380.0),
                backgroundColor: XC.side,
                shape: const RoundedRectangleBorder(),
                child: XExplorer(
                  project: p,
                  root: _tree,
                  activeRel: _active?.rel,
                  actions: _explorerActions,
                  problemsByFile: {
                    for (final d in _docs)
                      if (d.rel != null && (_ann[d.id]?.any((a) => a.isError) ?? false))
                        d.rel!: _ann[d.id]!.where((a) => a.isError).length,
                  },
                  openEditors: [
                    for (final d in _docs)
                      XOpenEditor(d.id, d.name, d.rel != null && d.rel!.contains('/') ? d.rel!.substring(0, d.rel!.lastIndexOf('/')) : '',
                          d.dirty, d.id == _activeId),
                  ],
                  onOpenEditor: (id) {
                    _scaffold.currentState?.closeDrawer();
                    _activate(id);
                  },
                ),
              ),
        body: SafeArea(
          bottom: false,
          child: Column(children: [
            _titleBar(),
            _tabs(),
            Expanded(
              child: LayoutBuilder(builder: (ctx, c) {
                final maxPanel = c.maxHeight - 60;
                final panelH = _panel == null ? 0.0 : (_panelMax ? maxPanel : _panelHeight.clamp(120.0, maxPanel < 120 ? 120.0 : maxPanel));
                return Column(children: [
                  Expanded(
                    child: Stack(children: [
                      Positioned.fill(child: AceEditorView(controller: _ace, background: _editorBg)),
                      if (_active == null && !_loading) Positioned.fill(child: _welcome()),
                      if (_loading || !_aceReady)
                        const Positioned.fill(
                          child: ColoredBox(
                            color: XC.bg,
                            child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: XC.accent)),
                          ),
                        ),
                    ]),
                  ),
                  if (_panel != null) SizedBox(height: panelH, child: _bottomPanel()),
                ]);
              }),
            ),
            if (showKeyBar)
              XKeyBar(
                ace: _ace,
                onFind: () => _ace.cmd('searchBox', {'replace': true}),
                onComplete: () => _ace.exec('startAutocomplete'),
                onAi: () => _openAi(),
              ),
            if (!keyboard) _statusBar(),
            SizedBox(height: keyboard ? 0 : MediaQuery.of(context).padding.bottom),
          ]),
        ),
      ),
    );
  }

  Widget _titleBar() {
    final d = _active;
    final errors = _problems.where((p) => p.a.isError).length;
    return Container(
      height: 48,
      color: XC.bar,
      child: Row(children: [
        XIconBtn(Icons.menu_rounded, tooltip: 'Explorer', onTap: () => _scaffold.currentState?.openDrawer(), color: XC.text),
        Expanded(
          child: InkWell(
            onTap: () => _palette(''),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(color: XC.bg, borderRadius: BorderRadius.circular(8), border: Border.all(color: XC.border)),
              child: Row(children: [
                const Icon(Icons.search_rounded, size: 16, color: XC.faint),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    d == null ? (_project?.name ?? 'X Coder') : '${_project?.name ?? ''} › ${d.rel ?? d.name}',
                    style: XC.ui(12.5, color: XC.dim),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ]),
            ),
          ),
        ),
        XIconBtn(Icons.play_arrow_rounded, tooltip: 'Run (F5)', onTap: _run, color: XC.ok, size: 24),
        XIconBtn(Icons.auto_awesome_rounded, tooltip: 'NOVA Coder', onTap: () => _openAi(), color: const Color(0xFFFFD54F)),
        XIconBtn(Icons.smart_toy_outlined, tooltip: 'NOVA Agent', onTap: () => _openAgent(), color: XC.accent),
        PopupMenuButton<String>(
          color: XC.side,
          icon: Icon(Icons.more_vert_rounded, color: errors > 0 ? XC.warning : XC.dim),
          onSelected: (v) async {
            final c = _commands.where((c) => c.id == v).firstOrNull;
            if (v == 'palette') {
              await _palette('>');
            } else if (c != null) {
              await c.run();
            }
          },
          itemBuilder: (_) => [
            _menuItem('palette', Icons.keyboard_command_key_rounded, 'Command palette', 'Ctrl+Shift+P'),
            _menuItem('save', Icons.save_outlined, 'Save', 'Ctrl+S'),
            _menuItem('saveAll', Icons.save_alt_rounded, 'Save all', ''),
            _menuItem('search', Icons.manage_search_rounded, 'Find in files', ''),
            _menuItem('find', Icons.find_replace_rounded, 'Find / replace', ''),
            _menuItem('format', Icons.auto_fix_high_rounded, 'Format document', ''),
            _menuItem('outline', Icons.account_tree_outlined, 'Outline', ''),
            _menuItem('terminal', Icons.terminal_rounded, 'Terminal', ''),
            _menuItem('preview', Icons.public_rounded, 'Preview website', ''),
            const PopupMenuDivider(),
            _menuItem('import', Icons.file_upload_outlined, 'Import files', ''),
            _menuItem('importUrl', Icons.cloud_download_outlined, 'Download from URL', ''),
            _menuItem('export', Icons.folder_zip_outlined, 'Export project (.zip)', ''),
            _menuItem('projects', Icons.folder_copy_outlined, 'Projects', ''),
            _menuItem('settings', Icons.tune_rounded, 'Settings', ''),
            const PopupMenuDivider(),
            _menuItem('agent', Icons.smart_toy_outlined, 'NOVA Agent', ''),
            _menuItem('guide', Icons.menu_book_rounded, 'Developer Guide', 'F1'),
          ],
        ),
      ]),
    );
  }

  PopupMenuItem<String> _menuItem(String v, IconData i, String label, String keys) => PopupMenuItem(
        value: v,
        height: 42,
        child: Row(children: [
          Icon(i, size: 18, color: XC.dim),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: XC.ui(13.5))),
          if (keys.isNotEmpty) Text(keys, style: XC.ui(11, color: XC.faint)),
        ]),
      );

  Widget _tabs() {
    if (_docs.isEmpty) return const SizedBox.shrink();
    return Container(
      height: 38,
      decoration: const BoxDecoration(color: XC.bar, border: Border(bottom: BorderSide(color: XC.border))),
      child: ReorderableListView.builder(
        scrollDirection: Axis.horizontal,
        buildDefaultDragHandles: false,
        itemCount: _docs.length,
        onReorder: (a, b) {
          setState(() {
            if (b > a) b--;
            _docs.insert(b, _docs.removeAt(a));
          });
          _persistTabs();
        },
        itemBuilder: (_, i) {
          final d = _docs[i];
          final active = d.id == _activeId;
          final v = fileVisual(d.name);
          final errs = (_ann[d.id] ?? const []).where((a) => a.isError).length;
          return ReorderableDelayedDragStartListener(
            key: ValueKey(d.id),
            index: i,
            child: GestureDetector(
              onTap: () => _activate(d.id),
              onLongPress: null,
              child: Container(
                padding: const EdgeInsets.only(left: 10, right: 2),
                decoration: BoxDecoration(
                  color: active ? _editorBg : Colors.transparent,
                  border: Border(
                    top: BorderSide(color: active ? XC.accent : Colors.transparent, width: 2),
                    right: const BorderSide(color: XC.border),
                  ),
                ),
                child: Row(children: [
                  Icon(v.icon, size: 15, color: v.color),
                  const SizedBox(width: 6),
                  Text(d.name,
                      style: XC.ui(12.5,
                          color: errs > 0 ? XC.error : (active ? Colors.white : XC.dim),
                          weight: active ? FontWeight.w600 : FontWeight.w400).copyWith(
                        fontStyle: d.untitled ? FontStyle.italic : FontStyle.normal,
                      )),
                  InkResponse(
                    onTap: () => _closeDoc(d.id),
                    radius: 14,
                    child: Padding(
                      padding: const EdgeInsets.all(7),
                      child: d.dirty
                          ? const Icon(Icons.circle, size: 9, color: XC.text)
                          : Icon(Icons.close_rounded, size: 14, color: active ? XC.dim : XC.faint),
                    ),
                  ),
                ]),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _welcome() => ColoredBox(
        color: XC.bg,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              ShaderMask(
                shaderCallback: (r) => const LinearGradient(colors: [Color(0xFF00D4FF), Color(0xFF7C4DFF)]).createShader(r),
                child: Text('X Coder', style: XC.ui(34, color: Colors.white, weight: FontWeight.w900)),
              ),
              const SizedBox(height: 6),
              Text('Code anywhere. Works offline.', style: XC.ui(13.5, color: XC.dim)),
              const SizedBox(height: 26),
              _welcomeAction(Icons.note_add_outlined, 'New file', 'Ctrl+N', () => _newEntry('', isFolder: false)),
              _welcomeAction(Icons.folder_open_rounded, 'Open file…', 'Ctrl+P', () => _palette('')),
              _welcomeAction(Icons.folder_copy_outlined, 'Projects', '', _projectsSheet),
              _welcomeAction(Icons.file_upload_outlined, 'Import from phone', '', () => _importFiles('')),
              _welcomeAction(Icons.keyboard_command_key_rounded, 'All commands', 'Ctrl+Shift+P', () => _palette('>')),
              _welcomeAction(Icons.auto_awesome_rounded, 'Generate with NOVA', 'Premium', () async {
                await _openUntitled('untitled-${_docSeq + 1}.js', '', mode: 'javascript');
                if (mounted) showXAiSheet(context, this, task: XAiTask.generate);
              }),
            ]),
          ),
        ),
      );

  Widget _welcomeAction(IconData i, String label, String keys, VoidCallback onTap) => SizedBox(
        width: 300,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(children: [
              Icon(i, size: 19, color: XC.accent),
              const SizedBox(width: 12),
              Expanded(child: Text(label, style: XC.ui(14, color: XC.accent))),
              Text(keys, style: XC.ui(11.5, color: XC.faint)),
            ]),
          ),
        ),
      );

  Widget _bottomPanel() {
    final probs = _problems;
    final errs = probs.where((p) => p.a.isError).length;
    Widget tab(XPanel p, String label, {int? count}) {
      final on = _panel == p;
      return InkWell(
        onTap: () => setState(() => _panel = p),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: on ? XC.accent : Colors.transparent, width: 2))),
          child: Row(children: [
            Text(label, style: XC.ui(11.5, color: on ? XC.text : XC.faint, weight: FontWeight.w700)),
            if (count != null && count > 0) ...[
              const SizedBox(width: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(color: XC.border, borderRadius: BorderRadius.circular(8)),
                child: Text('$count', style: XC.ui(10, color: XC.text, weight: FontWeight.w700)),
              ),
            ],
          ]),
        ),
      );
    }

    final t = _term;
    return Container(
      decoration: const BoxDecoration(color: XC.side, border: Border(top: BorderSide(color: XC.border))),
      child: Column(children: [
        GestureDetector(
          onVerticalDragUpdate: (d) => setState(() {
            _panelMax = false;
            _panelHeight = (_panelHeight - d.delta.dy).clamp(120.0, 2000.0);
          }),
          child: Container(
            height: 36,
            color: XC.side,
            child: Row(children: [
              Expanded(
                child: ListView(scrollDirection: Axis.horizontal, children: [
                  tab(XPanel.problems, 'PROBLEMS', count: probs.length),
                  tab(XPanel.terminal, 'TERMINAL'),
                  tab(XPanel.output, 'OUTPUT', count: _output.where((l) => l.level == 'error').length),
                  tab(XPanel.search, 'SEARCH'),
                ]),
              ),
              if (_panel == XPanel.terminal && t != null) XIconBtn(Icons.delete_sweep_outlined, tooltip: 'Clear', onTap: t.clear, size: 18),
              XIconBtn(_panelMax ? Icons.keyboard_arrow_down_rounded : Icons.keyboard_arrow_up_rounded,
                  tooltip: _panelMax ? 'Restore' : 'Maximize', onTap: () => setState(() => _panelMax = !_panelMax), size: 20),
              XIconBtn(Icons.close_rounded, tooltip: 'Close panel', onTap: () => setState(() => _panel = null), size: 18),
            ]),
          ),
        ),
        Expanded(
          child: switch (_panel!) {
            XPanel.problems => ProblemsView(
                problems: probs,
                onOpen: (p) async {
                  final d = _docs.where((d) => d.rel == p.rel && d.name == p.name).firstOrNull ??
                      _docs.where((d) => (d.rel ?? d.name) == p.name).firstOrNull;
                  if (d != null) await _activate(d.id);
                  await _ace.gotoLine(p.a.row, p.a.column);
                },
                onFixWithNova: errs > 0 || probs.isNotEmpty ? () => _openAi(XAiTask.fix) : null,
              ),
            XPanel.terminal => t == null ? const SizedBox.shrink() : TerminalView(terminal: t, autofocus: true),
            XPanel.output => OutputView(lines: _output, onClear: () => setState(_output.clear)),
            XPanel.search => _project == null
                ? const SizedBox.shrink()
                : SearchView(
                    key: ValueKey('search:$_searchSeed'),
                    project: _project!,
                    initial: _searchSeed,
                    onOpen: (h) => _openFile(h.rel, line: h.row),
                    onReplaced: () async {
                      await _reloadOpenFromDisk();
                      await _refreshTree();
                    },
                  ),
          },
        ),
      ]),
    );
  }

  Widget _statusBar() {
    final probs = _problems;
    final errs = probs.where((p) => p.a.isError).length;
    final warns = probs.where((p) => p.a.isWarning).length;
    final d = _active;
    Widget item(String text, {IconData? icon, VoidCallback? onTap, Color color = Colors.white}) => InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 7),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (icon != null) Icon(icon, size: 13, color: color),
              if (icon != null && text.isNotEmpty) const SizedBox(width: 3),
              Text(text, style: XC.ui(11, color: color, weight: FontWeight.w500)),
            ]),
          ),
        );
    return Container(
      height: 24,
      color: XC.status,
      child: Row(children: [
        item(_project?.name ?? '', icon: Icons.folder_outlined, onTap: _projectsSheet),
        item('$errs', icon: Icons.cancel_outlined, onTap: () => _togglePanel(XPanel.problems)),
        item('$warns', icon: Icons.warning_amber_rounded, onTap: () => _togglePanel(XPanel.problems)),
        item('', icon: Icons.terminal_rounded, onTap: () => _togglePanel(XPanel.terminal)),
        const Spacer(),
        if (d != null) ...[
          item(_cursor.selected > 0 ? 'Ln ${_cursor.row + 1}, Col ${_cursor.column + 1} (${_cursor.selected})' : 'Ln ${_cursor.row + 1}, Col ${_cursor.column + 1}',
              onTap: () => _palette(':')),
          if (MediaQuery.of(context).size.width > 380)
            item(_settings.softTabs ? 'Spaces: ${_settings.tabSize}' : 'Tab: ${_settings.tabSize}', onTap: _openSettings),
          item(kAceModeLabels[d.mode] ?? d.mode, onTap: _changeLanguage),
        ],
        item('', icon: _premium ? Icons.auto_awesome_rounded : Icons.auto_awesome_outlined, onTap: () => _openAi()),
      ]),
    );
  }

}
