// lib/features/devguide/developer_guide_screen.dart
//
// NOVA X Developer Guide (3.11.1): how to use every developer feature —
// X Coder, NOVA Coder & Agent, the terminal (every command), shortcuts,
// Dev Tools, the browser's developer features, NOVA Cyber, NOVA Shield,
// NOVA Network, NOVA Capture, offline use and troubleshooting.
// Works offline (the content is in the app). Tabs at the top jump to each
// section; search filters sections.

import 'package:flutter/material.dart';

import '../ai/widgets/nova_markdown_view.dart';
import '../xcoder/widgets/xcoder_ui.dart';
import 'guide_content.dart';

class DeveloperGuideScreen extends StatefulWidget {
  const DeveloperGuideScreen({super.key, this.initialSection});

  /// Section id to open at (e.g. 'terminal', 'devtools').
  final String? initialSection;

  @override
  State<DeveloperGuideScreen> createState() => _DeveloperGuideScreenState();
}

class _DeveloperGuideScreenState extends State<DeveloperGuideScreen> {
  final _scroll = ScrollController();
  final _tabsScroll = ScrollController();
  final Map<String, GlobalKey> _keys = {for (final s in kGuideSections) s.id: GlobalKey()};
  final Map<String, GlobalKey> _tabKeys = {for (final s in kGuideSections) s.id: GlobalKey()};
  String _active = kGuideSections.first.id;
  String _query = '';
  bool _searching = false;
  bool _jumping = false;

  List<GuideSection> get _visible {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return kGuideSections;
    return kGuideSections.where((s) => s.title.toLowerCase().contains(q) || s.body.toLowerCase().contains(q)).toList();
  }

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    final start = widget.initialSection;
    if (start != null && _keys.containsKey(start)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _jump(start, animate: false));
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    _tabsScroll.dispose();
    super.dispose();
  }

  Future<void> _jump(String id, {bool animate = true}) async {
    final ctx = _keys[id]?.currentContext;
    if (ctx == null) return;
    setState(() => _active = id);
    _revealTab(id);
    _jumping = true;
    await Scrollable.ensureVisible(ctx,
        duration: animate ? const Duration(milliseconds: 380) : Duration.zero, curve: Curves.easeInOutCubic, alignment: 0.0);
    _jumping = false;
  }

  void _revealTab(String id) {
    final ctx = _tabKeys[id]?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 250), alignment: 0.4);
    }
  }

  /// The section whose top passed under the tab bar becomes the active tab.
  void _onScroll() {
    if (_jumping) return;
    String? current;
    for (final s in _visible) {
      final box = _keys[s.id]?.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.attached) continue;
      final y = box.localToGlobal(Offset.zero).dy;
      if (y <= 190) current = s.id;
    }
    current ??= _visible.isEmpty ? null : _visible.first.id;
    if (current != null && current != _active) {
      setState(() => _active = current!);
      _revealTab(current);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sections = _visible;
    return Scaffold(
      backgroundColor: XC.bg,
      appBar: AppBar(
        backgroundColor: XC.bar,
        elevation: 0,
        titleSpacing: 0,
        title: _searching
            ? TextField(
                autofocus: true,
                style: XC.ui(15),
                decoration: InputDecoration(border: InputBorder.none, hintText: 'Search the guide (e.g. curl, cookies, LCP)', hintStyle: XC.ui(14, color: XC.faint)),
                onChanged: (v) => setState(() => _query = v),
              )
            : Row(children: [
                const Icon(Icons.menu_book_rounded, color: XC.accent, size: 20),
                const SizedBox(width: 8),
                Text('Developer Guide', style: XC.ui(17, weight: FontWeight.w800)),
              ]),
        actions: [
          IconButton(
            icon: Icon(_searching ? Icons.close_rounded : Icons.search_rounded, color: XC.dim),
            onPressed: () => setState(() {
              _searching = !_searching;
              if (!_searching) _query = '';
            }),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: Container(
            height: 50,
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: XC.border))),
            child: ListView(
              controller: _tabsScroll,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              children: [
                for (final s in sections)
                  Padding(
                    key: _tabKeys[s.id],
                    padding: const EdgeInsets.only(right: 6),
                    child: InkWell(
                      onTap: () => _jump(s.id),
                      borderRadius: BorderRadius.circular(18),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: _active == s.id ? s.color.withOpacity(0.18) : XC.side,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: _active == s.id ? s.color : XC.border),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(s.icon, size: 15, color: _active == s.id ? s.color : XC.dim),
                          const SizedBox(width: 6),
                          Text(s.tab, style: XC.ui(12.5, color: _active == s.id ? Colors.white : XC.dim, weight: FontWeight.w600)),
                        ]),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      body: sections.isEmpty
          ? Center(child: Text('Nothing found for “$_query”.', style: XC.ui(14, color: XC.dim)))
          : SingleChildScrollView(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (_query.isEmpty) _hero(),
                for (final s in sections) _section(s),
                const SizedBox(height: 12),
                Text('NOVA X Developer Guide · works offline', textAlign: TextAlign.center, style: XC.ui(11.5, color: XC.faint)),
              ]),
            ),
    );
  }

  Widget _hero() => Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [const Color(0xFF1565C0).withOpacity(0.35), const Color(0xFF7C4DFF).withOpacity(0.25)]),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: XC.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Build, debug and ship from your phone', style: XC.ui(18, weight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text('Everything NOVA X offers developers, in one place. Tap a tab above to jump to it.', style: XC.ui(13, color: XC.dim)),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final s in kGuideSections.skip(1))
              ActionChip(
                avatar: Icon(s.icon, size: 16, color: s.color),
                label: Text(s.tab),
                labelStyle: XC.ui(12, color: XC.text),
                backgroundColor: XC.side,
                side: const BorderSide(color: XC.border),
                onPressed: () => _jump(s.id),
              ),
          ]),
        ]),
      );

  Widget _section(GuideSection s) => Container(
        key: _keys[s.id],
        margin: const EdgeInsets.only(bottom: 18),
        decoration: BoxDecoration(color: XC.side, borderRadius: BorderRadius.circular(16), border: Border.all(color: XC.border)),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [s.color.withOpacity(0.18), Colors.transparent]),
              border: const Border(bottom: BorderSide(color: XC.border)),
            ),
            child: Row(children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: s.color.withOpacity(0.18), borderRadius: BorderRadius.circular(10)),
                child: Icon(s.icon, color: s.color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s.title, style: XC.ui(17, weight: FontWeight.w800)),
                  if (s.subtitle.isNotEmpty) Text(s.subtitle, style: XC.ui(12, color: XC.dim)),
                ]),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
            child: NovaMarkdownView(text: s.body, fontSize: 14),
          ),
        ]),
      );
}
