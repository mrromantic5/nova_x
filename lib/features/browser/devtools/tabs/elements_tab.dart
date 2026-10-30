// lib/features/browser/devtools/tabs/elements_tab.dart
//
// Elements: live DOM tree (incl. shadow roots), tap-to-inspect, search by
// text / CSS selector, and for the selected node: Styles (matched CSS rules,
// computed values, inline style editor), box model, attributes (edit / add /
// remove), HTML (edit outerHTML), accessibility, and actions (highlight,
// scroll into view, hide, delete, duplicate, copy selector / XPath / HTML,
// use in console as $0).

import 'package:flutter/material.dart';

import '../devtools_bridge.dart';
import '../dt_ui.dart';

class _Node {
  _Node(this.m);
  final Map<String, dynamic> m;
  List<_Node>? kids;
  bool open = false;
  bool loading = false;

  List<int> get path => (m['path'] as List? ?? const []).whereType<num>().map((e) => e.toInt()).toList();
  String get kind => m['k']?.toString() ?? '';
  String get tag => m['tag']?.toString() ?? '';
  int get kidCount => m['kids'] is num ? (m['kids'] as num).toInt() : 0;
  bool get expandable => kind == 'el' && kidCount > 0 && m['text'] == null;
  String get key => path.join('.');
}

class ElementsTab extends StatefulWidget {
  const ElementsTab({super.key, required this.bridge, this.initialPath, required this.onPick, required this.onUseInConsole});
  final DevtoolsBridge bridge;
  final List<int>? initialPath;
  final VoidCallback onPick;
  final void Function(String expr) onUseInConsole;

  @override
  State<ElementsTab> createState() => _ElementsTabState();
}

class _ElementsTabState extends State<ElementsTab> {
  List<_Node> _roots = [];
  String? _error;
  List<int>? _selected;
  Map<String, dynamic>? _details;
  bool _loadingDetails = false;
  int _detailTab = 0;
  final _search = TextEditingController();
  List<Map<String, dynamic>>? _hits;
  double _split = 0.5;

  DevtoolsBridge get _b => widget.bridge;

  @override
  void initState() {
    super.initState();
    _loadRoot().then((_) {
      final p = widget.initialPath;
      if (p != null) _reveal(p);
    });
  }

  @override
  void dispose() {
    _b.call('unhighlight');
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadRoot() async {
    final r = await _b.call('children', <int>[]);
    if (!mounted) return;
    if (!r.ok) {
      setState(() => _error = r.error);
      return;
    }
    final nodes = (r.map['nodes'] as List? ?? const []).whereType<Map>().map((m) => _Node(Map<String, dynamic>.from(m))).toList();
    setState(() {
      _error = null;
      _roots = nodes;
    });
    final html = nodes.where((n) => n.tag == 'html').firstOrNull;
    if (html != null) {
      await _expand(html);
      // open <body> by default
      final body = html.kids?.where((n) => n.tag == 'body').firstOrNull;
      if (body != null) await _expand(body);
    }
  }

  Future<void> _expand(_Node n) async {
    if (n.kids != null) {
      setState(() => n.open = true);
      return;
    }
    setState(() => n.loading = true);
    final r = await _b.call('children', n.path);
    if (!mounted) return;
    setState(() {
      n.loading = false;
      n.open = true;
      n.kids = (r.map['nodes'] as List? ?? const []).whereType<Map>().map((m) => _Node(Map<String, dynamic>.from(m))).toList();
    });
  }

  void _toggle(_Node n) {
    if (n.open) {
      setState(() => n.open = false);
    } else {
      _expand(n);
    }
  }

  /// Expands the tree down to [path] and selects it.
  Future<void> _reveal(List<int> path) async {
    var list = _roots;
    _Node? node = _roots.where((n) => n.tag == 'html').firstOrNull;
    if (node == null) return;
    for (var depth = 1; depth <= path.length; depth++) {
      await _expand(node!);
      list = node.kids ?? const [];
      final prefix = path.sublist(0, depth).join('.');
      final next = list.where((n) => n.key == prefix).firstOrNull;
      if (next == null) break;
      node = next;
    }
    if (node != null) _select(node.path);
  }

  Future<void> _select(List<int> path) async {
    setState(() {
      _selected = path;
      _loadingDetails = true;
    });
    _b.call('highlight', path);
    final r = await _b.call('details', path);
    if (!mounted) return;
    setState(() {
      _loadingDetails = false;
      _details = r.ok ? r.map : {'error': r.error};
    });
  }

  Future<void> _refresh() async {
    final sel = _selected;
    setState(() {
      _roots = [];
      _details = null;
    });
    await _loadRoot();
    if (sel != null) await _reveal(sel);
  }

  Future<void> _edit(Map<String, Object?> op) async {
    final sel = _selected;
    if (sel == null) return;
    final r = await _b.call('edit', {'path': sel, ...op});
    if (!mounted) return;
    if (!r.ok) {
      xToast(context, r.error ?? 'Couldn’t change the element', error: true);
      return;
    }
    final newPath = (r.map['path'] as List?)?.whereType<num>().map((e) => e.toInt()).toList();
    if (op['op'] == 'scroll' || op['op'] == 'click' || op['op'] == 'focus') return;
    await _refresh();
    if (newPath != null) await _reveal(newPath);
  }

  Future<void> _runSearch() async {
    final q = _search.text.trim();
    if (q.isEmpty) {
      setState(() => _hits = null);
      return;
    }
    // Looks like a CSS selector? query it; otherwise text search.
    final looksSelector = RegExp(r'^[#.\[]|^[a-z][a-z0-9-]*([#.\[:> ]|$)', caseSensitive: false).hasMatch(q) && !q.contains('  ');
    var r = looksSelector ? await _b.call('query', q) : await _b.call('search', q);
    if (looksSelector && (!r.ok || r.items.isEmpty)) r = await _b.call('search', q);
    if (!mounted) return;
    setState(() => _hits = r.items.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList());
  }

  // ── Tree rendering ────────────────────────────────────────────────────

  List<Widget> _rows(List<_Node> nodes, int depth) {
    final out = <Widget>[];
    for (final n in nodes) {
      out.add(_row(n, depth));
      if (n.open && n.kids != null) {
        out.addAll(_rows(n.kids!, depth + 1));
        if (n.kind == 'el') out.add(_closingTag(n, depth));
      }
    }
    return out;
  }

  Widget _closingTag(_Node n, int depth) => Padding(
        padding: EdgeInsets.only(left: 22.0 + depth * 12, top: 1, bottom: 1),
        child: Text('</${n.tag}>', style: XC.mono(12, color: const Color(0xFF569CD6))),
      );

  Widget _row(_Node n, int depth) {
    final sel = _selected != null && n.key == _selected!.join('.');
    final spans = <InlineSpan>[];
    const tagC = Color(0xFF569CD6), attrC = Color(0xFF9CDCFE), valC = Color(0xFFCE9178), txtC = Color(0xFFD4D4D4);
    switch (n.kind) {
      case 'el':
        spans.add(TextSpan(text: '<${n.tag}', style: XC.mono(12, color: tagC)));
        for (final a in (n.m['attrs'] as List? ?? const [])) {
          if (a is! List || a.length < 2) continue;
          spans.add(TextSpan(text: ' ${a[0]}', style: XC.mono(12, color: attrC)));
          final v = '${a[1]}';
          if (v.isNotEmpty) spans.add(TextSpan(text: '="${v.length > 60 ? '${v.substring(0, 60)}…' : v}"', style: XC.mono(12, color: valC)));
        }
        spans.add(TextSpan(text: '>', style: XC.mono(12, color: tagC)));
        final t = n.m['text'];
        if (t != null) {
          spans.add(TextSpan(text: '$t', style: XC.mono(12, color: txtC)));
          spans.add(TextSpan(text: '</${n.tag}>', style: XC.mono(12, color: tagC)));
        } else if (!n.open && n.kidCount > 0) {
          spans.add(TextSpan(text: '…</${n.tag}>', style: XC.mono(12, color: tagC)));
        }
        if (n.m['shadow'] == true) spans.add(TextSpan(text: '  #shadow-root', style: XC.mono(11, color: XC.faint)));
      case 'text':
        spans.add(TextSpan(text: '"${n.m['text']}"', style: XC.mono(12, color: txtC)));
      case 'comment':
        spans.add(TextSpan(text: '<!-- ${n.m['text']} -->', style: XC.mono(12, color: const Color(0xFF6A9955))));
      case 'doctype':
        spans.add(TextSpan(text: '${n.m['text']}', style: XC.mono(12, color: XC.faint)));
    }
    return Material(
      color: sel ? const Color(0xFF264F78) : Colors.transparent,
      child: InkWell(
        onTap: () {
          if (n.kind == 'el' || n.kind == 'text') _select(n.path);
        },
        onDoubleTap: n.expandable ? () => _toggle(n) : null,
        child: Padding(
          padding: EdgeInsets.only(left: 4.0 + depth * 12, right: 6, top: 2, bottom: 2),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 18,
              child: n.expandable
                  ? InkWell(
                      onTap: () => _toggle(n),
                      child: n.loading
                          ? const Padding(padding: EdgeInsets.all(3), child: SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.5)))
                          : Icon(n.open ? Icons.arrow_drop_down_rounded : Icons.arrow_right_rounded, size: 18, color: XC.dim),
                    )
                  : null,
            ),
            Expanded(child: Text.rich(TextSpan(children: spans), maxLines: n.kind == 'text' ? 3 : 2, overflow: TextOverflow.ellipsis)),
            if (n.m['inShadow'] == true) Text(' shadow', style: XC.ui(10, color: XC.faint)),
          ]),
        ),
      ),
    );
  }

  // ── Details ───────────────────────────────────────────────────────────

  Widget _detailsPane() {
    final d = _details;
    if (_selected == null) {
      return const DtEmpty(Icons.ads_click_rounded, 'Select an element', body: 'Tap a node in the tree, or use ⌖ and tap the page.');
    }
    if (_loadingDetails && d == null) return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    if (d == null) return const SizedBox.shrink();
    if (d['error'] != null) return DtEmpty(Icons.error_outline_rounded, '${d['error']}', action: TextButton(onPressed: _refresh, child: const Text('Refresh tree')));
    if (d['k'] != 'el') {
      return ListView(children: [DtSection('Text node'), DtCode('${d['text'] ?? ''}')]);
    }
    final tabs = ['Styles', 'Computed', 'Box', 'Attributes', 'HTML', 'A11y'];
    return Column(children: [
      Container(
        height: 34,
        color: XC.bar,
        child: Row(children: [
          Expanded(
            child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5), children: [
              for (var i = 0; i < tabs.length; i++) DtChip(tabs[i], selected: _detailTab == i, onTap: () => setState(() => _detailTab = i)),
            ]),
          ),
          PopupMenuButton<String>(
            color: XC.side,
            icon: const Icon(Icons.more_horiz_rounded, color: XC.dim, size: 20),
            onSelected: (v) async {
              switch (v) {
                case 'scroll':
                  _edit({'op': 'scroll'});
                case 'hide':
                  _edit({'op': 'hide'});
                case 'delete':
                  if (await xConfirm(context, 'Delete element?', 'It is removed from this page until you reload.')) _edit({'op': 'delete'});
                case 'duplicate':
                  _edit({'op': 'duplicate'});
                case 'click':
                  _edit({'op': 'click'});
                case 'selector':
                  if (mounted) dtCopy(context, '${d['selector']}', 'Copied selector');
                case 'xpath':
                  if (mounted) dtCopy(context, '${d['xpath']}', 'Copied XPath');
                case 'html':
                  if (mounted) dtCopy(context, '${d['outer']}', 'Copied HTML');
                case 'console':
                  widget.onUseInConsole('\$0');
              }
            },
            itemBuilder: (_) => [
              for (final (v, i, l) in const [
                ('scroll', Icons.center_focus_strong_outlined, 'Scroll into view'),
                ('click', Icons.touch_app_outlined, 'Click it'),
                ('hide', Icons.visibility_off_outlined, 'Hide (display: none)'),
                ('duplicate', Icons.copy_all_rounded, 'Duplicate'),
                ('delete', Icons.delete_outline_rounded, 'Delete'),
                ('selector', Icons.code_rounded, 'Copy selector'),
                ('xpath', Icons.route_outlined, 'Copy XPath'),
                ('html', Icons.html_rounded, 'Copy outerHTML'),
                ('console', Icons.terminal_rounded, 'Use in console (\$0)'),
              ])
                PopupMenuItem(
                  value: v,
                  height: 40,
                  child: Row(children: [Icon(i, size: 18, color: XC.dim), const SizedBox(width: 10), Text(l, style: XC.ui(13))]),
                ),
            ],
          ),
        ]),
      ),
      Expanded(child: switch (_detailTab) {
        0 => _styles(d),
        1 => _computed(d),
        2 => _box(d),
        3 => _attributes(d),
        4 => _html(d),
        _ => _a11y(d),
      }),
    ]);
  }

  Widget _styles(Map<String, dynamic> d) {
    final rules = (d['rules'] as List? ?? const []).whereType<Map>().toList();
    final inline = '${d['inline'] ?? ''}';
    return ListView(children: [
      DtSection('element.style',
          trailing: XIconBtn(Icons.edit_outlined, tooltip: 'Edit inline style', size: 16, onTap: () async {
            final v = await _multiline('Inline style', inline, hint: 'color: red;\npadding: 8px;');
            if (v != null) _edit({'op': 'style', 'value': v});
          })),
      _cssBlock(inline.isEmpty ? '' : inline),
      for (final r in rules) ...[
        Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
          child: Row(children: [
            Expanded(child: Text('${r['selector']}', style: XC.mono(12, color: const Color(0xFFD7BA7D)))),
            Text('${r['source']}', style: XC.ui(10.5, color: XC.faint)),
          ]),
        ),
        if ('${r['media']}'.isNotEmpty) Padding(padding: const EdgeInsets.only(left: 12), child: Text('${r['media']}', style: XC.mono(10.5, color: XC.faint))),
        _cssBlock('${r['css']}'),
      ],
      if (rules.isEmpty)
        Padding(
          padding: const EdgeInsets.all(14),
          child: Text('No matching rules from readable stylesheets. Stylesheets from other domains can’t be read by pages (CORS).',
              style: XC.ui(12, color: XC.faint)),
        ),
    ]);
  }

  Widget _cssBlock(String css) {
    final decls = css.split(';').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 2, 12, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (decls.isEmpty) Text('{ }', style: XC.mono(12, color: XC.faint)),
        for (final dcl in decls)
          Builder(builder: (_) {
            final i = dcl.indexOf(':');
            if (i < 0) return Text(dcl, style: XC.mono(12));
            return Text.rich(TextSpan(children: [
              TextSpan(text: dcl.substring(0, i), style: XC.mono(12, color: const Color(0xFF9CDCFE))),
              TextSpan(text: ': ', style: XC.mono(12)),
              TextSpan(text: dcl.substring(i + 1).trim(), style: XC.mono(12, color: const Color(0xFFCE9178))),
              TextSpan(text: ';', style: XC.mono(12)),
            ]));
          }),
      ]),
    );
  }

  Widget _computed(Map<String, dynamic> d) {
    final styles = (d['styles'] as List? ?? const []).whereType<List>().toList();
    return ListView(children: [
      for (final s in styles)
        if (s.length >= 2)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 150, child: Text('${s[0]}', style: XC.mono(12, color: const Color(0xFF9CDCFE)))),
              if (RegExp(r'^rgba?\(').hasMatch('${s[1]}')) ...[
                Container(width: 12, height: 12, margin: const EdgeInsets.only(right: 6, top: 2), decoration: BoxDecoration(color: _cssColor('${s[1]}'), border: Border.all(color: XC.border))),
              ],
              Expanded(child: SelectableText('${s[1]}', style: XC.mono(12))),
            ]),
          ),
    ]);
  }

  static Color? _cssColor(String s) {
    final m = RegExp(r'rgba?\((\d+),\s*(\d+),\s*(\d+)(?:,\s*([\d.]+))?').firstMatch(s);
    if (m == null) return null;
    final a = m.group(4) == null ? 1.0 : double.tryParse(m.group(4)!) ?? 1.0;
    return Color.fromRGBO(int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!), a);
  }

  Widget _box(Map<String, dynamic> d) {
    final b = Map<String, dynamic>.from(d['box'] as Map? ?? const {});
    List<num> four(String k) => (b[k] as List? ?? const [0, 0, 0, 0]).whereType<num>().toList();
    String n(num v) => v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(1);
    Widget layer(String label, Color color, List<num> v, Widget child) => Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(color: color, border: Border.all(color: Colors.black26, style: BorderStyle.solid)),
          child: Column(children: [
            Row(children: [Text(label, style: XC.mono(9.5, color: Colors.black87)), const Spacer(), Text(n(v[0]), style: XC.mono(10.5, color: Colors.black)), const Spacer(flex: 2)]),
            Row(children: [
              SizedBox(width: 28, child: Text(n(v[3]), style: XC.mono(10.5, color: Colors.black), textAlign: TextAlign.center)),
              Expanded(child: child),
              SizedBox(width: 28, child: Text(n(v[1]), style: XC.mono(10.5, color: Colors.black), textAlign: TextAlign.center)),
            ]),
            Text(n(v[2]), style: XC.mono(10.5, color: Colors.black)),
          ]),
        );
    return ListView(padding: const EdgeInsets.all(12), children: [
      layer('margin', const Color(0xFFF9CC9D), four('margin'),
          layer('border', const Color(0xFFFDDD9B), four('border'),
              layer('padding', const Color(0xFFC3D08B), four('padding'),
                  Container(
                    height: 44,
                    alignment: Alignment.center,
                    color: const Color(0xFF8CB6C0),
                    child: Text('${n(b['w'] as num? ?? 0)} × ${n(b['h'] as num? ?? 0)}', style: XC.mono(12, color: Colors.black, weight: FontWeight.w700)),
                  )))),
      const SizedBox(height: 12),
      DtKV('position', 'x ${b['x']}, y ${b['y']} (page)'),
      DtKV('size', '${b['w']} × ${b['h']} px'),
      DtKV('child elements', '${d['childElements']}'),
    ]);
  }

  Widget _attributes(Map<String, dynamic> d) {
    final attrs = (d['attrs'] as List? ?? const []).whereType<List>().toList();
    return ListView(children: [
      for (final a in attrs)
        if (a.length >= 2)
          ListTile(
            dense: true,
            title: Text('${a[0]}', style: XC.mono(12.5, color: const Color(0xFF9CDCFE))),
            subtitle: Text('${a[1]}', style: XC.mono(12, color: const Color(0xFFCE9178)), maxLines: 4, overflow: TextOverflow.ellipsis),
            onTap: () async {
              final v = await _multiline('Edit ${a[0]}', '${a[1]}');
              if (v != null) _edit({'op': 'setAttr', 'name': '${a[0]}', 'value': v});
            },
            trailing: XIconBtn(Icons.close_rounded, tooltip: 'Remove attribute', size: 16, onTap: () => _edit({'op': 'removeAttr', 'name': '${a[0]}'})),
          ),
      Padding(
        padding: const EdgeInsets.all(12),
        child: OutlinedButton.icon(
          onPressed: () async {
            final name = await xPrompt(context, title: 'Attribute name', hint: 'data-test', validate: (v) => RegExp(r'^[a-zA-Z_:][-a-zA-Z0-9_:.]*$').hasMatch(v.trim()) ? null : 'Not a valid attribute name');
            if (name == null || !mounted) return;
            final v = await _multiline('Value of $name', '');
            if (v != null) _edit({'op': 'setAttr', 'name': name, 'value': v});
          },
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Add attribute'),
        ),
      ),
      if (((d['listeners'] as List?) ?? const []).isNotEmpty) ...[
        const DtSection('Event handlers (on…)'),
        for (final l in (d['listeners'] as List)) DtKV('$l', 'handler'),
      ],
    ]);
  }

  Widget _html(Map<String, dynamic> d) {
    final outer = '${d['outer'] ?? ''}';
    final full = d['outerLength'] is num ? (d['outerLength'] as num).toInt() : outer.length;
    return ListView(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
        child: Row(children: [
          Expanded(child: Text(full > outer.length ? 'Showing ${outer.length} of $full characters' : '$full characters', style: XC.ui(11.5, color: XC.faint))),
          TextButton.icon(
            onPressed: full > outer.length
                ? null
                : () async {
                    final v = await _multiline('Edit as HTML', outer, mono: true);
                    if (v != null) _edit({'op': 'outer', 'html': v});
                  },
            icon: const Icon(Icons.edit_outlined, size: 16),
            label: const Text('Edit as HTML'),
          ),
        ]),
      ),
      DtCode(outer, label: 'HTML'),
    ]);
  }

  Widget _a11y(Map<String, dynamic> d) {
    final a = Map<String, dynamic>.from(d['a11y'] as Map? ?? const {});
    return ListView(children: [
      DtKV('role', '${a['role'] ?? ''}'.isEmpty ? '(generic)' : '${a['role']}'),
      DtKV('accessible name', '${a['name'] ?? ''}', valueColor: '${a['name'] ?? ''}'.isEmpty ? XC.warning : null),
      DtKV('focusable', '${a['focusable']}'),
      DtKV('aria-hidden', '${a['hidden']}'),
      DtKV('selector', '${d['selector']}'),
      DtKV('xpath', '${d['xpath']}'),
    ]);
  }

  Future<String?> _multiline(String title, String initial, {String hint = '', bool mono = true}) {
    final c = TextEditingController(text: initial);
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: XC.side,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(title, style: XC.ui(15, weight: FontWeight.w700)),
              const SizedBox(height: 10),
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.5),
                child: TextField(
                  controller: c,
                  autofocus: true,
                  maxLines: null,
                  minLines: 3,
                  keyboardType: TextInputType.multiline,
                  autocorrect: false,
                  enableSuggestions: false,
                  style: mono ? XC.mono(12.5) : XC.ui(13),
                  decoration: InputDecoration(
                    hintText: hint,
                    filled: true,
                    fillColor: XC.bg,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Apply')),
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hits = _hits;
    return Column(children: [
      DtToolbar(children: [
        XIconBtn(Icons.ads_click_rounded, tooltip: 'Select an element on the page', onTap: widget.onPick, color: XC.accent),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: TextField(
              controller: _search,
              style: XC.mono(12.5),
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _runSearch(),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Find by text or CSS selector',
                hintStyle: XC.ui(12, color: XC.faint),
                filled: true,
                fillColor: XC.bg,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
                suffixIcon: hits == null
                    ? null
                    : InkWell(
                        onTap: () => setState(() {
                          _hits = null;
                          _search.clear();
                        }),
                        child: const Icon(Icons.close_rounded, size: 16, color: XC.dim),
                      ),
                suffixIconConstraints: const BoxConstraints(minWidth: 30),
              ),
            ),
          ),
        ),
        XIconBtn(Icons.refresh_rounded, tooltip: 'Refresh tree', onTap: _refresh),
      ]),
      Expanded(
        child: _error != null
            ? DtEmpty(Icons.error_outline_rounded, 'Can’t read this page', body: _error!, action: TextButton(onPressed: _refresh, child: const Text('Retry')))
            : LayoutBuilder(builder: (ctx, c) {
                final top = (c.maxHeight * _split).clamp(80.0, c.maxHeight - 80 < 80 ? 80.0 : c.maxHeight - 80);
                return Column(children: [
                  SizedBox(
                    height: top,
                    child: hits != null
                        ? ListView(children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
                              child: Text('${hits.length} matching elements', style: XC.ui(11.5, color: XC.faint)),
                            ),
                            for (final h in hits)
                              ListTile(
                                dense: true,
                                title: Text('${h['label']}', style: XC.mono(12)),
                                subtitle: '${h['text'] ?? ''}'.isEmpty ? null : Text('${h['text']}', style: XC.ui(11.5, color: XC.faint), maxLines: 1),
                                onTap: () {
                                  final p = (h['path'] as List).whereType<num>().map((e) => e.toInt()).toList();
                                  setState(() => _hits = null);
                                  _reveal(p);
                                },
                              ),
                          ])
                        : (_roots.isEmpty
                            ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                            : SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: SizedBox(
                                  width: (MediaQuery.of(context).size.width * 1.6).clamp(400.0, 1600.0),
                                  child: ListView(padding: const EdgeInsets.symmetric(vertical: 4), children: _rows(_roots, 0)),
                                ),
                              )),
                  ),
                  GestureDetector(
                    onVerticalDragUpdate: (dd) => setState(() => _split = ((top + dd.delta.dy) / c.maxHeight).clamp(0.15, 0.85)),
                    child: Container(
                      height: 14,
                      color: XC.bar,
                      alignment: Alignment.center,
                      child: Container(width: 36, height: 3, decoration: BoxDecoration(color: XC.border, borderRadius: BorderRadius.circular(2))),
                    ),
                  ),
                  Expanded(child: _detailsPane()),
                ]);
              }),
      ),
    ]);
  }
}
