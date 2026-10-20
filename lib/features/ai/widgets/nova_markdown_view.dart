// lib/features/ai/widgets/nova_markdown_view.dart
//
// Shows a NOVA AI answer the way modern AI apps do: clean paragraphs,
// headings, bullet and numbered lists, tables, quotes, bold/italic text,
// tappable links, and code in code-editor style blocks (language label,
// Copy button, syntax colours, sideways scrolling). Used by the NOVA AI chat
// and the NOVA assistant panel. Text is selectable.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_theme.dart';
import '../services/nova_code_highlighter.dart';
import '../services/nova_markdown_parser.dart';

class NovaMarkdownView extends StatefulWidget {
  const NovaMarkdownView({
    super.key,
    required this.text,
    this.fontSize = 15,
    this.color = AppTheme.textPrimary,
    this.onLink,
    this.selectable = true,
    this.centerShort = false,
  });

  final String text;
  final double fontSize;
  final Color color;

  /// Called with an http(s)/mailto address when a link is tapped. Without
  /// it, the address is copied.
  final ValueChanged<String>? onLink;
  final bool selectable;

  /// Centre a short one-paragraph answer (assistant panel).
  final bool centerShort;

  @override
  State<NovaMarkdownView> createState() => _NovaMarkdownViewState();
}

class _NovaMarkdownViewState extends State<NovaMarkdownView> {
  late List<MdBlock> _blocks = NovaMarkdown.parse(widget.text);
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void didUpdateWidget(NovaMarkdownView old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) _blocks = NovaMarkdown.parse(widget.text);
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  TextStyle get _base => GoogleFonts.inter(
        color: widget.color,
        fontSize: widget.fontSize,
        height: 1.55,
      );

  void _openLink(String url) {
    final onLink = widget.onLink;
    if (onLink != null) {
      onLink(url);
      return;
    }
    Clipboard.setData(ClipboardData(text: url));
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(const SnackBar(content: Text('Link copied'), duration: Duration(seconds: 2)));
  }

  TextSpan _inline(String text, TextStyle style) {
    final children = <InlineSpan>[];
    for (final s in NovaMarkdown.inline(text)) {
      TapGestureRecognizer? recognizer;
      final link = s.link;
      if (link != null) {
        recognizer = TapGestureRecognizer()..onTap = () => _openLink(link);
        _recognizers.add(recognizer);
      }
      var st = style;
      if (s.bold) st = st.copyWith(fontWeight: FontWeight.w700);
      if (s.italic) st = st.copyWith(fontStyle: FontStyle.italic);
      if (s.code) {
        st = st.copyWith(
          fontFamily: 'monospace',
          fontSize: (style.fontSize ?? widget.fontSize) * 0.9,
          color: const Color(0xFFFFB86B),
          backgroundColor: const Color(0x24FFFFFF),
        );
      }
      if (link != null) {
        st = st.copyWith(
          color: AppTheme.accentCyan,
          decoration: TextDecoration.underline,
          decorationColor: AppTheme.accentCyan.withValues(alpha: 0.6),
        );
      } else if (s.strike) {
        st = st.copyWith(decoration: TextDecoration.lineThrough);
      }
      children.add(TextSpan(text: s.text, style: st, recognizer: recognizer));
    }
    return TextSpan(style: style, children: children);
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();
    final base = _base;
    final blocks = _blocks;
    final center = widget.centerShort &&
        blocks.length == 1 &&
        blocks.first is MdParagraph &&
        widget.text.length <= 140;

    final children = <Widget>[];
    MdBlock? previous;
    for (final block in blocks) {
      if (previous != null) {
        final listRun = previous is MdListItem && block is MdListItem;
        children.add(SizedBox(height: listRun ? 5 : (block is MdHeading ? 14 : 10)));
      }
      children.add(_block(block, base, center));
      previous = block;
    }

    final column = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: center ? CrossAxisAlignment.center : CrossAxisAlignment.stretch,
      children: children,
    );
    return widget.selectable ? SelectionArea(child: column) : column;
  }

  Widget _block(MdBlock block, TextStyle base, bool center) {
    switch (block) {
      case MdParagraph(:final text):
        return Text.rich(_inline(text, base), textAlign: center ? TextAlign.center : TextAlign.start);

      case MdHeading(:final level, :final text):
        final scale = switch (level) { 1 => 1.32, 2 => 1.2, 3 => 1.08, _ => 1.0 };
        return Text.rich(_inline(
          text,
          base.copyWith(fontSize: widget.fontSize * scale, fontWeight: FontWeight.w700, height: 1.35),
        ));

      case MdListItem(:final ordered, :final marker, :final level, :final text):
        return Padding(
          padding: EdgeInsets.only(left: level * 18.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: ordered ? 28 : 20,
                child: Text(
                  marker,
                  style: ordered
                      ? base.copyWith(fontWeight: FontWeight.w600, color: AppTheme.textSecondary)
                      : base.copyWith(color: AppTheme.accentCyan, fontWeight: FontWeight.w700),
                ),
              ),
              Expanded(child: Text.rich(_inline(text, base))),
            ],
          ),
        );

      case MdQuote(:final text):
        return Container(
          padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
          decoration: const BoxDecoration(
            border: Border(left: BorderSide(color: AppTheme.accentPurple, width: 3)),
          ),
          child: Text.rich(_inline(text, base.copyWith(color: AppTheme.textSecondary, fontStyle: FontStyle.italic))),
        );

      case MdCode(:final language, :final code):
        return NovaCodeBlock(code: code, language: language);

      case MdTable(:final header, :final rows):
        return _table(header, rows, base);

      case MdRule():
        return const Divider(height: 8, thickness: 1, color: Color(0x22FFFFFF));
    }
  }

  Widget _table(List<String> header, List<List<String>> rows, TextStyle base) {
    final cellStyle = base.copyWith(fontSize: widget.fontSize * 0.93, height: 1.4);
    Widget cell(String text, {bool head = false}) => ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 240),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Text.rich(_inline(text, head ? cellStyle.copyWith(fontWeight: FontWeight.w700) : cellStyle)),
          ),
        );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0x26FFFFFF)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Table(
          defaultColumnWidth: const IntrinsicColumnWidth(),
          border: const TableBorder(
            horizontalInside: BorderSide(color: Color(0x1FFFFFFF)),
            verticalInside: BorderSide(color: Color(0x1FFFFFFF)),
          ),
          children: [
            TableRow(
              decoration: const BoxDecoration(color: Color(0x14FFFFFF)),
              children: [for (final h in header) cell(h, head: true)],
            ),
            for (final r in rows) TableRow(children: [for (final c in r) cell(c)]),
          ],
        ),
      ),
    );
  }
}

/// A code block in code-editor style: language, Copy, colours, scrolling.
class NovaCodeBlock extends StatefulWidget {
  const NovaCodeBlock({super.key, required this.code, required this.language});

  final String code;
  final String language;

  static const Color background = Color(0xFF0A1322);
  static const Color headerColor = Color(0xFF101C30);

  static Color colorOf(CodeTok kind) => switch (kind) {
        CodeTok.keyword => const Color(0xFFC678DD),
        CodeTok.string => const Color(0xFF98C379),
        CodeTok.comment => const Color(0xFF7F8C98),
        CodeTok.number => const Color(0xFFD19A66),
        CodeTok.tag => const Color(0xFFE06C75),
        CodeTok.attr => const Color(0xFFE5C07B),
        CodeTok.func => const Color(0xFF61AFEF),
        CodeTok.type => const Color(0xFF56B6C2),
        CodeTok.punct => const Color(0xFFABB2BF),
        CodeTok.plain => const Color(0xFFD7DAE0),
      };

  @override
  State<NovaCodeBlock> createState() => _NovaCodeBlockState();
}

class _NovaCodeBlockState extends State<NovaCodeBlock> {
  bool _copied = false;
  late TextSpan _span = _build();

  @override
  void didUpdateWidget(NovaCodeBlock old) {
    super.didUpdateWidget(old);
    if (old.code != widget.code || old.language != widget.language) _span = _build();
  }

  TextSpan _build() {
    final tokens = NovaCodeHighlighter.highlight(widget.code, widget.language);
    return TextSpan(children: [
      for (final t in tokens)
        TextSpan(
          text: t.text,
          style: TextStyle(
            color: NovaCodeBlock.colorOf(t.kind),
            fontStyle: t.kind == CodeTok.comment ? FontStyle.italic : null,
          ),
        ),
    ]);
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    HapticFeedback.selectionClick();
    if (!mounted) return;
    setState(() => _copied = true);
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: NovaCodeBlock.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x1FFFFFFF)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            color: NovaCodeBlock.headerColor,
            padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    NovaCodeHighlighter.label(widget.language),
                    style: GoogleFonts.inter(
                      color: AppTheme.textSecondary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: _copy,
                  style: TextButton.styleFrom(
                    foregroundColor: _copied ? AppTheme.success : AppTheme.textSecondary,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: const Size(0, 34),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: Icon(_copied ? Icons.check_rounded : Icons.copy_rounded, size: 15),
                  label: Text(_copied ? 'Copied' : 'Copy',
                      style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Text.rich(
              _span,
              softWrap: false,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontFamilyFallback: ['RobotoMono', 'Droid Sans Mono', 'Courier'],
                fontSize: 13,
                height: 1.55,
                color: Color(0xFFD7DAE0),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
