// lib/features/xcoder/widgets/xcoder_palette.dart
//
// Command palette (like VS Code's Ctrl+Shift+P / Ctrl+P):
//   text       → go to file
//   > text     → run a command
//   : 42       → go to line
//   @ text     → go to symbol in the file

import 'package:flutter/material.dart';

import 'xcoder_ui.dart';

class XCommand {
  const XCommand(this.id, this.title, this.icon, this.run, {this.category = '', this.keys = '', this.premium = false});
  final String id;
  final String title;
  final IconData icon;
  final String category;
  final String keys;
  final bool premium;
  final Future<void> Function() run;
}

class PaletteResult {
  const PaletteResult.command(this.command)
      : file = null,
        line = null,
        symbolRow = null;
  const PaletteResult.file(this.file)
      : command = null,
        line = null,
        symbolRow = null;
  const PaletteResult.line(this.line)
      : command = null,
        file = null,
        symbolRow = null;
  const PaletteResult.symbol(this.symbolRow)
      : command = null,
        file = null,
        line = null;
  final XCommand? command;
  final String? file;
  final int? line;
  final int? symbolRow;
}

/// Simple fuzzy score: all query chars in order; bonus for word starts and runs.
int fuzzyScore(String text, String query) {
  if (query.isEmpty) return 1;
  final t = text.toLowerCase(), q = query.toLowerCase();
  final direct = t.indexOf(q);
  if (direct >= 0) return 1000 - direct * 2 - t.length ~/ 8 + (direct == 0 || '/._- '.contains(t[direct - 1]) ? 200 : 0);
  var score = 0, ti = 0, run = 0;
  for (var qi = 0; qi < q.length; qi++) {
    final c = q[qi];
    var found = false;
    while (ti < t.length) {
      if (t[ti] == c) {
        found = true;
        run++;
        score += 10 + run * 5 + (ti == 0 || '/._- '.contains(t[ti - 1]) ? 25 : 0);
        ti++;
        break;
      }
      run = 0;
      ti++;
    }
    if (!found) return 0;
  }
  return score - t.length ~/ 4;
}

Future<PaletteResult?> showCommandPalette(
  BuildContext context, {
  required List<XCommand> commands,
  required List<String> files,
  required Future<List<({int row, String name, int indent})>> Function() symbols,
  String initial = '',
  List<String> recentFiles = const [],
}) {
  return showGeneralDialog<PaletteResult>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 120),
    pageBuilder: (ctx, _, __) => _Palette(commands: commands, files: files, symbols: symbols, initial: initial, recent: recentFiles),
  );
}

class _Palette extends StatefulWidget {
  const _Palette({required this.commands, required this.files, required this.symbols, required this.initial, required this.recent});
  final List<XCommand> commands;
  final List<String> files;
  final Future<List<({int row, String name, int indent})>> Function() symbols;
  final String initial;
  final List<String> recent;

  @override
  State<_Palette> createState() => _PaletteState();
}

class _PaletteState extends State<_Palette> {
  late final TextEditingController _q = TextEditingController(text: widget.initial)
    ..selection = TextSelection.collapsed(offset: widget.initial.length);
  List<({int row, String name, int indent})>? _symbols;
  int _sel = 0;

  @override
  void initState() {
    super.initState();
    _q.addListener(() => setState(() => _sel = 0));
  }

  List<Widget> _items(BuildContext context) {
    final q = _q.text;
    if (q.startsWith('>')) {
      final s = q.substring(1).trim();
      final list = widget.commands
          .map((c) => (c, fuzzyScore('${c.category} ${c.title}', s)))
          .where((e) => e.$2 > 0)
          .toList()
        ..sort((a, b) => b.$2.compareTo(a.$2));
      return [
        for (final (i, e) in list.take(60).indexed)
          _row(
            i,
            icon: e.$1.icon,
            title: e.$1.title,
            subtitle: e.$1.category,
            trailing: e.$1.premium ? '✨ Premium' : e.$1.keys,
            onTap: () => Navigator.pop(context, PaletteResult.command(e.$1)),
          ),
      ];
    }
    if (q.startsWith(':')) {
      final n = int.tryParse(q.substring(1).trim());
      return [
        _row(0,
            icon: Icons.format_list_numbered_rounded,
            title: n == null ? 'Type a line number' : 'Go to line $n',
            onTap: n == null ? null : () => Navigator.pop(context, PaletteResult.line(n - 1))),
      ];
    }
    if (q.startsWith('@')) {
      final s = q.substring(1).trim();
      if (_symbols == null) {
        widget.symbols().then((v) {
          if (mounted) setState(() => _symbols = v);
        });
        return [_row(0, icon: Icons.hourglass_empty_rounded, title: 'Reading symbols…')];
      }
      final list = _symbols!.where((e) => fuzzyScore(e.name, s) > 0).take(120).toList();
      if (list.isEmpty) return [_row(0, icon: Icons.info_outline, title: 'No symbols found')];
      return [
        for (final (i, e) in list.indexed)
          _row(i,
              icon: Icons.data_object_rounded,
              title: '${'  ' * (e.indent ~/ 2).clamp(0, 6)}${e.name}',
              trailing: 'Ln ${e.row + 1}',
              onTap: () => Navigator.pop(context, PaletteResult.symbol(e.row))),
      ];
    }
    // files
    final base = q.isEmpty
        ? [...widget.recent.where(widget.files.contains), ...widget.files.where((f) => !widget.recent.contains(f))]
        : (widget.files.map((f) => (f, fuzzyScore(f, q))).where((e) => e.$2 > 0).toList()..sort((a, b) => b.$2.compareTo(a.$2)))
            .map((e) => e.$1)
            .toList();
    if (base.isEmpty) {
      return [_row(0, icon: Icons.search_off_rounded, title: 'No matching files', subtitle: 'Type > for commands, : for a line, @ for symbols')];
    }
    return [
      for (final (i, f) in base.take(80).indexed)
        () {
          final v = fileVisual(f.split('/').last);
          final slash = f.lastIndexOf('/');
          return _row(i,
              icon: v.icon,
              iconColor: v.color,
              title: f.substring(slash + 1),
              subtitle: slash > 0 ? f.substring(0, slash) : '',
              trailing: q.isEmpty && widget.recent.contains(f) ? 'recent' : '',
              onTap: () => Navigator.pop(context, PaletteResult.file(f)));
        }(),
    ];
  }

  Widget _row(int i,
      {required IconData icon, required String title, String subtitle = '', String trailing = '', Color? iconColor, VoidCallback? onTap}) {
    final selected = i == _sel;
    return Material(
      color: selected ? XC.hover : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(children: [
            Icon(icon, size: 18, color: iconColor ?? XC.dim),
            const SizedBox(width: 12),
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: title, style: XC.ui(14)),
                  if (subtitle.isNotEmpty) TextSpan(text: '   $subtitle', style: XC.ui(12, color: XC.faint)),
                ]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (trailing.isNotEmpty) Text(trailing, style: XC.ui(11, color: XC.faint)),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _items(context);
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
          child: Material(
            color: XC.side,
            elevation: 16,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 640, maxHeight: MediaQuery.of(context).size.height * 0.62),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: TextField(
                    controller: _q,
                    autofocus: true,
                    style: XC.mono(14),
                    textInputAction: TextInputAction.go,
                    decoration: InputDecoration(
                      isDense: true,
                      prefixIcon: const Icon(Icons.search_rounded, color: XC.dim, size: 20),
                      hintText: 'Search files · > commands · : line · @ symbol',
                      hintStyle: XC.ui(13, color: XC.faint),
                      filled: true,
                      fillColor: XC.bg,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: XC.accent)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: XC.border)),
                    ),
                    onSubmitted: (_) {
                      // Enter picks the first row
                      final first = items.isEmpty ? null : items.first;
                      if (first is Material && first.child is InkWell) (first.child as InkWell).onTap?.call();
                    },
                  ),
                ),
                Flexible(child: ListView(shrinkWrap: true, padding: const EdgeInsets.only(bottom: 6), children: items)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
