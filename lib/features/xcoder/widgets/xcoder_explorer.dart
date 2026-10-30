// lib/features/xcoder/widgets/xcoder_explorer.dart
//
// EXPLORER: project switcher, open editors and the file tree with a VS Code
// style context menu (new file/folder, rename, duplicate, delete, copy path,
// run, reveal in terminal).

import 'package:flutter/material.dart';

import '../workspace/xcoder_workspace.dart';
import 'xcoder_ui.dart';

class ExplorerActions {
  const ExplorerActions({
    required this.open,
    required this.newFile,
    required this.newFolder,
    required this.rename,
    required this.duplicate,
    required this.delete,
    required this.copyPath,
    required this.run,
    required this.refresh,
    required this.switchProject,
    required this.importFiles,
    required this.closeTab,
  });

  final void Function(String rel) open;
  final void Function(String folderRel) newFile;
  final void Function(String folderRel) newFolder;
  final void Function(XNode node) rename;
  final void Function(XNode node) duplicate;
  final void Function(XNode node) delete;
  final void Function(XNode node) copyPath;
  final void Function(String rel) run;
  final VoidCallback refresh;
  final VoidCallback switchProject;
  final void Function(String folderRel) importFiles;
  final void Function(String id) closeTab;
}

class XOpenEditor {
  const XOpenEditor(this.id, this.title, this.subtitle, this.dirty, this.active);
  final String id;
  final String title;
  final String subtitle;
  final bool dirty;
  final bool active;
}

class XExplorer extends StatefulWidget {
  const XExplorer({
    super.key,
    required this.project,
    required this.root,
    required this.openEditors,
    required this.activeRel,
    required this.actions,
    required this.onOpenEditor,
    required this.problemsByFile,
  });

  final XProject project;
  final XNode? root;
  final List<XOpenEditor> openEditors;
  final String? activeRel;
  final ExplorerActions actions;
  final void Function(String id) onOpenEditor;
  final Map<String, int> problemsByFile; // rel -> errors

  @override
  State<XExplorer> createState() => _XExplorerState();
}

class _XExplorerState extends State<XExplorer> {
  static final Map<String, Set<String>> _expandedByProject = {};
  Set<String> get _expanded => _expandedByProject.putIfAbsent(widget.project.path, () => {''});
  bool _editorsOpen = true;
  String _filter = '';

  @override
  void initState() {
    super.initState();
    // reveal the active file
    final a = widget.activeRel;
    if (a != null) {
      final parts = a.split('/');
      for (var i = 1; i < parts.length; i++) {
        _expanded.add(parts.take(i).join('/'));
      }
    }
  }

  void _menu(XNode n, Offset at) async {
    final folder = n.isDir ? n.rel : (n.rel.contains('/') ? n.rel.substring(0, n.rel.lastIndexOf('/')) : '');
    final items = <PopupMenuEntry<String>>[
      if (!n.isDir) _item('open', Icons.open_in_new_rounded, 'Open'),
      if (!n.isDir) _item('run', Icons.play_arrow_rounded, 'Run / preview'),
      _item('newFile', Icons.note_add_outlined, 'New file…'),
      _item('newFolder', Icons.create_new_folder_outlined, 'New folder…'),
      _item('import', Icons.file_upload_outlined, 'Import files here…'),
      const PopupMenuDivider(),
      if (n.rel.isNotEmpty) _item('rename', Icons.drive_file_rename_outline_rounded, 'Rename…'),
      if (!n.isDir) _item('duplicate', Icons.copy_all_rounded, 'Duplicate'),
      _item('copyPath', Icons.link_rounded, 'Copy relative path'),
      if (n.rel.isNotEmpty) const PopupMenuDivider(),
      if (n.rel.isNotEmpty) _item('delete', Icons.delete_outline_rounded, 'Delete', color: XC.error),
    ];
    final v = await showMenu<String>(
      context: context,
      color: XC.side,
      position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx + 1, at.dy + 1),
      items: items,
    );
    final a = widget.actions;
    switch (v) {
      case 'open':
        a.open(n.rel);
      case 'run':
        a.run(n.rel);
      case 'newFile':
        a.newFile(folder);
      case 'newFolder':
        a.newFolder(folder);
      case 'import':
        a.importFiles(folder);
      case 'rename':
        a.rename(n);
      case 'duplicate':
        a.duplicate(n);
      case 'copyPath':
        a.copyPath(n);
      case 'delete':
        a.delete(n);
    }
  }

  PopupMenuItem<String> _item(String v, IconData i, String label, {Color color = XC.text}) => PopupMenuItem(
        value: v,
        height: 40,
        child: Row(children: [
          Icon(i, size: 18, color: color == XC.text ? XC.dim : color),
          const SizedBox(width: 12),
          Text(label, style: XC.ui(13.5, color: color)),
        ]),
      );

  List<Widget> _rows(XNode n, int depth) {
    final out = <Widget>[];
    final f = _filter.toLowerCase();
    for (final c in n.children) {
      if (f.isNotEmpty && !c.isDir && !c.rel.toLowerCase().contains(f)) continue;
      if (f.isNotEmpty && c.isDir && !_hasMatch(c, f)) continue;
      final open = c.isDir && (_expanded.contains(c.rel) || f.isNotEmpty);
      final v = fileVisual(c.name, dir: c.isDir, open: open);
      final active = !c.isDir && c.rel == widget.activeRel;
      final errs = widget.problemsByFile[c.rel] ?? (c.isDir ? _dirErrors(c.rel) : 0);
      out.add(GestureDetector(
        onLongPressStart: (d) => _menu(c, d.globalPosition),
        child: Material(
          color: active ? XC.tabActive : Colors.transparent,
          child: InkWell(
            onTap: () {
              if (c.isDir) {
                setState(() => open ? _expanded.remove(c.rel) : _expanded.add(c.rel));
              } else {
                widget.actions.open(c.rel);
              }
            },
            child: Padding(
              padding: EdgeInsets.only(left: 8.0 + depth * 14, right: 8, top: 6, bottom: 6),
              child: Row(children: [
                SizedBox(
                  width: 16,
                  child: c.isDir
                      ? Icon(open ? Icons.expand_more_rounded : Icons.chevron_right_rounded, size: 16, color: XC.dim)
                      : null,
                ),
                const SizedBox(width: 2),
                Icon(v.icon, size: 17, color: v.color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(c.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: XC.ui(13.5,
                          color: errs > 0 ? XC.error : (active ? Colors.white : XC.text),
                          weight: active ? FontWeight.w600 : FontWeight.w400)),
                ),
                if (errs > 0)
                  Text('$errs', style: XC.ui(11, color: XC.error, weight: FontWeight.w700))
                else if (kXCoderIgnoredDirs.contains(c.name))
                  Text('hidden', style: XC.ui(10.5, color: XC.faint)),
              ]),
            ),
          ),
        ),
      ));
      if (open && !kXCoderIgnoredDirs.contains(c.name)) out.addAll(_rows(c, depth + 1));
    }
    return out;
  }

  int _dirErrors(String rel) {
    var n = 0;
    widget.problemsByFile.forEach((k, v) {
      if (k.startsWith('$rel/')) n += v;
    });
    return n;
  }

  bool _hasMatch(XNode d, String f) =>
      d.children.any((c) => c.isDir ? _hasMatch(c, f) : c.rel.toLowerCase().contains(f));

  Widget _section(String title, {required bool open, required VoidCallback toggle, List<Widget> actions = const []}) => Container(
        color: XC.bar,
        height: 34,
        padding: const EdgeInsets.only(left: 4),
        child: Row(children: [
          InkWell(
            onTap: toggle,
            child: Row(children: [
              Icon(open ? Icons.expand_more_rounded : Icons.chevron_right_rounded, size: 18, color: XC.dim),
              Text(title, style: XC.ui(11.5, color: XC.dim, weight: FontWeight.w700)),
            ]),
          ),
          const Spacer(),
          ...actions,
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final root = widget.root;
    final a = widget.actions;
    return Container(
      color: XC.side,
      child: SafeArea(
        right: false,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // project header
          InkWell(
            onTap: a.switchProject,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 10),
              child: Row(children: [
                Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF00D4FF), Color(0xFF7C4DFF)]),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(widget.project.name.isEmpty ? 'X' : widget.project.name[0].toUpperCase(),
                      style: XC.ui(15, color: Colors.white, weight: FontWeight.w800)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(widget.project.name, style: XC.ui(15, weight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text('Switch project', style: XC.ui(11, color: XC.faint)),
                  ]),
                ),
                const Icon(Icons.unfold_more_rounded, color: XC.dim, size: 20),
              ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
            child: TextField(
              style: XC.ui(13),
              onChanged: (v) => setState(() => _filter = v.trim()),
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.filter_list_rounded, size: 18, color: XC.faint),
                hintText: 'Filter files',
                hintStyle: XC.ui(12.5, color: XC.faint),
                filled: true,
                fillColor: XC.bg,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
              ),
            ),
          ),
          if (widget.openEditors.isNotEmpty) ...[
            _section('OPEN EDITORS', open: _editorsOpen, toggle: () => setState(() => _editorsOpen = !_editorsOpen)),
            if (_editorsOpen)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 180),
                child: ListView(shrinkWrap: true, padding: EdgeInsets.zero, children: [
                  for (final e in widget.openEditors)
                    Material(
                      color: e.active ? XC.tabActive : Colors.transparent,
                      child: InkWell(
                        onTap: () => widget.onOpenEditor(e.id),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 4, 0, 4),
                          child: Row(children: [
                            Icon(fileVisual(e.title).icon, size: 16, color: fileVisual(e.title).color),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text.rich(
                                TextSpan(children: [
                                  TextSpan(text: e.title, style: XC.ui(13)),
                                  if (e.subtitle.isNotEmpty) TextSpan(text: '  ${e.subtitle}', style: XC.ui(11, color: XC.faint)),
                                ]),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (e.dirty) const Padding(padding: EdgeInsets.only(right: 4), child: Icon(Icons.circle, size: 8, color: XC.text)),
                            InkResponse(
                              onTap: () => a.closeTab(e.id),
                              radius: 16,
                              child: const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.close_rounded, size: 15, color: XC.dim)),
                            ),
                          ]),
                        ),
                      ),
                    ),
                ]),
              ),
          ],
          _section(widget.project.name.toUpperCase(), open: true, toggle: () => setState(() => _expanded.clear()), actions: [
            XIconBtn(Icons.note_add_outlined, tooltip: 'New file', onTap: () => a.newFile(''), size: 18),
            XIconBtn(Icons.create_new_folder_outlined, tooltip: 'New folder', onTap: () => a.newFolder(''), size: 18),
            XIconBtn(Icons.refresh_rounded, tooltip: 'Refresh', onTap: a.refresh, size: 18),
            XIconBtn(Icons.unfold_less_rounded, tooltip: 'Collapse all', onTap: () => setState(() => _expanded..clear()..add('')), size: 18),
          ]),
          Expanded(
            child: root == null
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2, color: XC.accent))
                : root.children.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            Text('This project is empty.', style: XC.ui(13, color: XC.dim)),
                            const SizedBox(height: 10),
                            FilledButton.tonalIcon(
                              onPressed: () => a.newFile(''),
                              icon: const Icon(Icons.note_add_outlined, size: 18),
                              label: const Text('New file'),
                            ),
                            TextButton.icon(
                              onPressed: () => a.importFiles(''),
                              icon: const Icon(Icons.file_upload_outlined, size: 18),
                              label: const Text('Import files'),
                            ),
                          ]),
                        ),
                      )
                    : GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onLongPressStart: (d) => _menu(root, d.globalPosition),
                        child: ListView(padding: const EdgeInsets.only(bottom: 40), children: _rows(root, 0)),
                      ),
          ),
        ]),
      ),
    );
  }
}
