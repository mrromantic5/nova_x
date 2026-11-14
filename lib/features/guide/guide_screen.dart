// lib/features/guide/guide_screen.dart
//
// NOVA X Feature Guide page and the "Read more" link used next to features.
// A link opens the guide at that feature's section (scrolled into view and
// highlighted). Android (3.13.0): same guide as NOVA X for PC, phone layout;
// opened from the menu, Settings › Help and every "Read more" link.

import '../../core/widgets/windows_download_card.dart';
import 'package:flutter/material.dart';

import '../cyber/ui/cyber_palette.dart';
import 'guide_content.dart';

/// The section the guide should show (set by [ReadMoreLink]).
class GuideNav {
  GuideNav._();
  static final ValueNotifier<String?> target = ValueNotifier<String?>(null);
  static int _serial = 0;
  static final ValueNotifier<int> serial = ValueNotifier<int>(0);

  static void show(String? id) {
    target.value = id;
    serial.value = ++_serial; // the same section clicked twice still scrolls
  }
}

/// A small "Read more" link that opens the guide at [id].
class ReadMoreLink extends StatelessWidget {
  const ReadMoreLink(this.id, {super.key, this.label = 'Read more', this.compact = false});

  final String id;
  final String label;
  final bool compact;

  static void open(BuildContext context, String id) {
    GuideNav.show(id);
    // Close a dialog / sheet first, so the guide isn't opened behind it.
    final nav = Navigator.of(context);
    final route = ModalRoute.of(context);
    if (route is PopupRoute) nav.maybePop();
    nav.push(MaterialPageRoute(builder: (_) => FeatureGuideScreen(initialSection: id)));
  }

  @override
  Widget build(BuildContext context) {
    final p = NovaThemeScope.of(context);
    return Tooltip(
      message: 'How ${guideSection(id)?.title ?? 'this feature'} works',
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => open(context, id),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: compact ? 4 : 6, vertical: 3),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.menu_book_outlined, size: compact ? 13 : 14, color: p.accent),
            const SizedBox(width: 4),
            Text(label,
                style: p.ui(size: compact ? 11.5 : 12.5, color: p.accent, weight: FontWeight.w600)
                    .copyWith(decoration: TextDecoration.underline, decorationColor: p.accent.withValues(alpha: 0.5))),
          ]),
        ),
      ),
    );
  }
}

class FeatureGuideScreen extends StatefulWidget {
  const FeatureGuideScreen({super.key, this.initialSection});

  /// Section to scroll to and highlight when the guide opens.
  final String? initialSection;

  @override
  State<FeatureGuideScreen> createState() => _FeatureGuideScreenState();
}

class _FeatureGuideScreenState extends State<FeatureGuideScreen> {
  final Map<String, GlobalKey> _keys = {for (final s in kGuide) s.id: GlobalKey()};
  final ScrollController _scroll = ScrollController();
  final TextEditingController _search = TextEditingController();
  String _query = '';
  String? _highlight;

  @override
  void initState() {
    super.initState();
    GuideNav.serial.addListener(_jump);
    GuideNav.target.value = widget.initialSection;
    WidgetsBinding.instance.addPostFrameCallback((_) => _jump());
  }

  @override
  void dispose() {
    GuideNav.serial.removeListener(_jump);
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  void _jump() {
    final id = GuideNav.target.value;
    if (id == null || !mounted) return;
    if (_query.isNotEmpty) {
      _search.clear();
      setState(() => _query = '');
    }
    setState(() => _highlight = id);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _keys[id]?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic, alignment: 0.02);
      }
    });
    Future<void>.delayed(const Duration(seconds: 3), () {
      if (mounted && _highlight == id) setState(() => _highlight = null);
    });
  }

  List<GuideSection> get _visible {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return kGuide;
    final words = q.split(RegExp(r'\s+'));
    return kGuide.where((s) => words.every(s.searchText.contains)).toList();
  }

  @override
  Widget build(BuildContext context) {
    return NovaThemed(
      child: Builder(builder: (context) {
        final p = NovaThemeScope.of(context);
        final visible = _visible;
        return Scaffold(
          backgroundColor: p.bg,
          appBar: AppBar(
            backgroundColor: p.surface,
            surfaceTintColor: Colors.transparent,
            title: Text('Feature Guide', style: p.ui(size: 17, weight: FontWeight.w700)),
            actions: [
              IconButton(
                tooltip: 'Contents',
                icon: Icon(Icons.toc_rounded, color: p.textMuted),
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  backgroundColor: p.surface,
                  isScrollControlled: true,
                  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                  builder: (ctx) => SizedBox(
                    height: MediaQuery.sizeOf(ctx).height * 0.75,
                    child: NovaThemed(child: _index(p, visible, onPick: () => Navigator.pop(ctx))),
                  ),
                ),
              ),
            ],
          ),
          body: LayoutBuilder(builder: (context, box) {
            final wide = box.maxWidth >= 900;
            return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (wide) SizedBox(width: 280, child: _index(p, visible)),
              if (wide) VerticalDivider(width: 1, color: p.border),
              Expanded(child: _content(p, visible, wide)),
            ]);
          }),
        );
      }),
    );
  }

  Widget _index(NovaPalette p, List<GuideSection> visible, {VoidCallback? onPick}) {
    return Container(
      color: p.surface,
      child: ListView(padding: const EdgeInsets.fromLTRB(12, 18, 12, 24), children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
          child: Text('Contents', style: p.ui(size: 12, color: p.textFaint, weight: FontWeight.w700)),
        ),
        for (final cat in GuideCategory.order)
          if (visible.any((s) => s.category == cat)) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
              child: Text(cat.toUpperCase(),
                  style: p.ui(size: 10.5, color: p.textFaint, weight: FontWeight.w700, letterSpacing: 0.8)),
            ),
            for (final s in visible.where((s) => s.category == cat))
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () {
                  onPick?.call();
                  GuideNav.show(s.id);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                  decoration: BoxDecoration(
                    color: _highlight == s.id ? p.accentSoft : null,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(children: [
                    Icon(s.icon, size: 16, color: _highlight == s.id ? p.accent : p.textMuted),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(s.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: p.ui(size: 13, color: _highlight == s.id ? p.accent : p.text)),
                    ),
                  ]),
                ),
              ),
          ],
      ]),
    );
  }

  Widget _content(NovaPalette p, List<GuideSection> visible, bool wide) {
    return CustomScrollView(controller: _scroll, slivers: [
      SliverToBoxAdapter(
        child: Container(
          padding: EdgeInsets.fromLTRB(wide ? 32 : 16, 18, wide ? 32 : 16, 16),
          decoration: BoxDecoration(color: p.surface, border: Border(bottom: BorderSide(color: p.border))),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 860),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(color: p.accentSoft, borderRadius: BorderRadius.circular(12)),
                    child: Icon(Icons.menu_book_rounded, color: p.accent),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('NOVA X Feature Guide', style: p.title(size: wide ? 22 : 19)),
                      const SizedBox(height: 2),
                      Text('What each feature does, how it works and how to get the most from it.',
                          style: p.ui(size: 13, color: p.textMuted)),
                    ]),
                  ),
                ]),
                const SizedBox(height: 16),
                TextField(
                  controller: _search,
                  onChanged: (v) => setState(() => _query = v),
                  style: p.ui(size: 14),
                  decoration: InputDecoration(
                    hintText: 'Search (e.g. "password", "ads")',
                    hintStyle: p.ui(size: 14, color: p.textFaint),
                    prefixIcon: Icon(Icons.search_rounded, color: p.textFaint),
                    filled: true,
                    fillColor: p.surfaceAlt,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
      if (visible.isEmpty)
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(40),
            child: Center(child: Text('Nothing matches "$_query".', style: p.ui(color: p.textMuted))),
          ),
        ),
      SliverPadding(
        padding: EdgeInsets.fromLTRB(wide ? 24 : 12, 12, wide ? 24 : 12, 60),
        sliver: SliverToBoxAdapter(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 860),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (final cat in GuideCategory.order)
                  if (visible.any((s) => s.category == cat)) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 18, 4, 10),
                      child: Text(cat, style: p.title(size: 15).copyWith(color: p.textMuted)),
                    ),
                    for (final s in visible.where((s) => s.category == cat)) _section(p, s),
                  ],
                // 3.13.1: the Windows version.
                if (_query.isEmpty)
                  const WindowsDownloadCard(
                    reason: 'Everything in this guide, plus PC-only tools, on Windows.',
                    margin: EdgeInsets.fromLTRB(0, 18, 0, 0),
                  ),
              ]),
            ),
          ),
        ),
      ),
    ]);
  }

  Widget _section(NovaPalette p, GuideSection s) {
    final lit = _highlight == s.id;
    Widget list(String heading, IconData icon, List<String> items, {bool numbered = false, Color? color}) {
      if (items.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 15, color: color ?? p.accent),
            const SizedBox(width: 6),
            Text(heading, style: p.ui(size: 13, weight: FontWeight.w700, color: p.text)),
          ]),
          const SizedBox(height: 6),
          for (var i = 0; i < items.length; i++)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(
                  width: 22,
                  child: Text(numbered ? '${i + 1}.' : '•',
                      style: p.ui(size: 13.5, color: color ?? p.accent, weight: FontWeight.w700)),
                ),
                Expanded(child: SelectableText(items[i], style: p.ui(size: 13.5, color: p.text).copyWith(height: 1.45))),
              ]),
            ),
        ]),
      );
    }

    return AnimatedContainer(
      key: _keys[s.id],
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: lit ? p.accent : p.border, width: lit ? 2 : 1),
        boxShadow: lit ? [BoxShadow(color: p.accent.withValues(alpha: 0.18), blurRadius: 18)] : null,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(s.icon, color: p.accent),
          const SizedBox(width: 10),
          Expanded(child: Text(s.title, style: p.title(size: 17))),
        ]),
        const SizedBox(height: 8),
        SelectableText(s.summary, style: p.ui(size: 14, color: p.text).copyWith(height: 1.45)),
        if (s.where.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(color: p.surfaceAlt, borderRadius: BorderRadius.circular(8)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.place_outlined, size: 15, color: p.textMuted),
              const SizedBox(width: 6),
              Expanded(child: Text('Where: ${s.where}', style: p.ui(size: 12.5, color: p.textMuted))),
            ]),
          ),
        ],
        list('How it works', Icons.settings_suggest_outlined, s.how),
        list('How to use it', Icons.directions_outlined, s.steps, numbered: true),
        list('Tips', Icons.lightbulb_outline_rounded, s.tips, color: p.warning),
        list('Good to know', Icons.info_outline_rounded, s.limits, color: p.textMuted),
      ]),
    );
  }
}
