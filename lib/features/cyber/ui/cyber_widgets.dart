// lib/features/cyber/ui/cyber_widgets.dart
//
// NOVA Cyber — UI building blocks: severity colours, score ring, finding
// card (evidence, impact, platform-specific fixes), code blocks.
// Android (3.13.0): same widgets as NOVA X for PC, laid out for phones.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../engine/cyber_fixes.dart';
import '../engine/cyber_models.dart';
import 'cyber_palette.dart';

const TextStyle kMono = TextStyle(fontFamily: 'monospace', fontFamilyFallback: ['Roboto Mono', 'Courier New'], fontSize: 12.5, height: 1.5);

Color sevColor(Severity s, NovaPalette p) {
  switch (s) {
    case Severity.critical:
      return p.dark ? const Color(0xFFFF6B6B) : const Color(0xFFB42318);
    case Severity.high:
      return p.dark ? const Color(0xFFFF9F5A) : const Color(0xFFC4320A);
    case Severity.medium:
      return p.dark ? const Color(0xFFF5C451) : const Color(0xFFB54708);
    case Severity.low:
      return p.dark ? const Color(0xFF8FB3FF) : const Color(0xFF3E5BA9);
    case Severity.info:
      return p.textMuted;
  }
}

Color gradeColor(int score, NovaPalette p) {
  if (score >= 85) return p.success;
  if (score >= 55) return p.dark ? const Color(0xFFF5C451) : const Color(0xFFB54708);
  return p.dark ? const Color(0xFFFF6B6B) : const Color(0xFFB42318);
}

class SevPill extends StatelessWidget {
  const SevPill(this.s, {super.key, this.compact = false});
  final Severity s;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = NovaThemeScope.of(context);
    final c = sevColor(s, p);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 8, vertical: compact ? 1.5 : 3),
      decoration: BoxDecoration(color: c.withValues(alpha: p.dark ? 0.16 : 0.09), borderRadius: BorderRadius.circular(5), border: Border.all(color: c.withValues(alpha: 0.35))),
      child: Text(s.label.toUpperCase(), style: p.ui(size: compact ? 9.5 : 10.5, weight: FontWeight.w700, color: c, letterSpacing: 0.6)),
    );
  }
}

class Tag extends StatelessWidget {
  const Tag(this.text, {super.key, this.icon, this.color});
  final String text;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = NovaThemeScope.of(context);
    final c = color ?? p.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(color: p.surfaceAlt, borderRadius: BorderRadius.circular(5), border: Border.all(color: p.border)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 12, color: c), const SizedBox(width: 4)],
        Text(text, style: p.ui(size: 11, color: c, weight: FontWeight.w600)),
      ]),
    );
  }
}

/// Circular score gauge.
class ScoreRing extends StatelessWidget {
  const ScoreRing({super.key, required this.score, required this.grade, this.size = 132});
  final int score;
  final String grade;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = NovaThemeScope.of(context);
    final c = gradeColor(score, p);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: score / 100),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _RingPainter(v, c, p.border),
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('${(v * 100).round()}', style: p.title(size: size * 0.3, color: p.text).copyWith(height: 1)),
              const SizedBox(height: 2),
              Text('GRADE $grade', style: p.ui(size: 11, weight: FontWeight.w700, color: c, letterSpacing: 1)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.v, this.color, this.track);
  final double v;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2 - 7;
    final c = Offset(size.width / 2, size.height / 2);
    final bg = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8;
    canvas.drawCircle(c, r, bg);
    final fg = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 8;
    canvas.drawArc(Rect.fromCircle(center: c, radius: r), -math.pi / 2, 2 * math.pi * v, false, fg);
  }

  @override
  bool shouldRepaint(_RingPainter o) => o.v != v || o.color != color;
}

/// Monospace block with a copy button.
class CodeBlock extends StatelessWidget {
  const CodeBlock(this.text, {super.key, this.maxHeight = 260, this.label});
  final String text;
  final double maxHeight;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final p = NovaThemeScope.of(context);
    final bg = p.dark ? const Color(0xFF0D1117) : const Color(0xFFF6F8FA);
    return Container(
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8), border: Border.all(color: p.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.border))),
          child: Row(children: [
            Text(label ?? '', style: p.ui(size: 11, color: p.textFaint, weight: FontWeight.w600)),
            const Spacer(),
            _CopyButton(text),
          ]),
        ),
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: SelectableText(text, style: kMono.copyWith(color: p.text)),
          ),
        ),
      ]),
    );
  }
}

class _CopyButton extends StatefulWidget {
  const _CopyButton(this.text);
  final String text;
  @override
  State<_CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<_CopyButton> {
  bool _done = false;
  @override
  Widget build(BuildContext context) {
    final p = NovaThemeScope.of(context);
    return TextButton.icon(
      style: TextButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: _done ? p.success : p.textMuted),
      onPressed: () async {
        await Clipboard.setData(ClipboardData(text: widget.text));
        setState(() => _done = true);
        await Future<void>.delayed(const Duration(milliseconds: 1400));
        if (mounted) setState(() => _done = false);
      },
      icon: Icon(_done ? Icons.check_rounded : Icons.content_copy_rounded, size: 14),
      label: Text(_done ? 'Copied' : 'Copy', style: p.ui(size: 11.5, weight: FontWeight.w600, color: _done ? p.success : p.textMuted)),
    );
  }
}

/// One finding, expandable.
class FindingCard extends StatefulWidget {
  const FindingCard({super.key, required this.f, required this.tech, this.onAskAi, this.initiallyOpen = false});
  final Finding f;
  final TechProfile tech;
  final void Function(Finding f)? onAskAi;
  final bool initiallyOpen;

  @override
  State<FindingCard> createState() => _FindingCardState();
}

class _FindingCardState extends State<FindingCard> {
  late bool _open = widget.initiallyOpen;
  String? _platform;
  bool _checking = false;
  String? _recheckResult;

  @override
  Widget build(BuildContext context) {
    final p = NovaThemeScope.of(context);
    final f = widget.f;
    final c = sevColor(f.severity, p);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _open ? c.withValues(alpha: 0.45) : p.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(width: 3, height: 40, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    SevPill(f.severity, compact: true),
                    if (f.level == ScanLevel.full) const Tag('Verified test', icon: Icons.verified_user_outlined),
                    if (f.confidence == 'confirmed') const Tag('Confirmed'),
                    if (f.confidence == 'tentative') const Tag('Review'),
                  ]),
                  const SizedBox(height: 6),
                  Text(f.title, style: p.ui(size: 14, weight: FontWeight.w600, color: p.text)),
                  const SizedBox(height: 3),
                  Text(
                    [f.area.label, if (f.location.isNotEmpty) f.location].join('  ·  '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: p.ui(size: 11.5, color: p.textFaint),
                  ),
                ]),
              ),
              const SizedBox(width: 6),
              Icon(_open ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: p.textFaint),
            ]),
          ),
        ),
        if (_open) _body(p, f),
      ]),
    );
  }

  Widget _body(NovaPalette p, Finding f) {
    final g = fixFor(f.id);
    final platforms = g == null ? const <String>[] : orderedPlatforms(g, widget.tech.primary, widget.tech.stack);
    final sel = _platform != null && platforms.contains(_platform) ? _platform! : (platforms.isEmpty ? null : platforms.first);
    Widget section(String title, Widget child) => Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title.toUpperCase(), style: p.ui(size: 10.5, weight: FontWeight.w700, color: p.textFaint, letterSpacing: 0.9)),
            const SizedBox(height: 6),
            child,
          ]),
        );
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 0, 14, 16),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: p.border))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (f.impact.isNotEmpty) section('Why it matters', Text(f.impact, style: p.ui(size: 13.5, color: p.text, height: 1.5))),
        if (f.evidence.isNotEmpty) section('Evidence', CodeBlock(f.evidence, label: f.location.isEmpty ? 'Observed' : f.location, maxHeight: 200)),
        section(
          'How to fix',
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(f.fixSummary, style: p.ui(size: 13.5, color: p.text, weight: FontWeight.w600, height: 1.45)),
            if (g != null) ...[
              const SizedBox(height: 8),
              for (var i = 0; i < g.steps.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(width: 22, child: Text('${i + 1}.', style: p.ui(size: 13, color: p.accent, weight: FontWeight.w700))),
                    Expanded(child: Text(g.steps[i], style: p.ui(size: 13, color: p.text, height: 1.45))),
                  ]),
                ),
              if (platforms.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final k in platforms)
                    ChoiceChip(
                      label: Text('${platformLabels[k] ?? k}${k == widget.tech.primary ? '  •  detected' : ''}', style: p.ui(size: 11.5, weight: FontWeight.w600)),
                      selected: k == sel,
                      onSelected: (_) => setState(() => _platform = k),
                      visualDensity: VisualDensity.compact,
                      showCheckmark: false,
                      selectedColor: p.accentSoft,
                      side: BorderSide(color: k == sel ? p.accent : p.border),
                    ),
                ]),
                const SizedBox(height: 8),
                if (sel != null) CodeBlock(g.snippets[sel]!, label: platformLabels[sel] ?? sel),
              ],
              if (g.verify.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(g.verify, style: p.ui(size: 12, color: p.textMuted))),
            ],
          ]),
        ),
        if (f.refs.isNotEmpty)
          section('References', Wrap(spacing: 6, runSpacing: 6, children: [for (final r in f.refs) Tag(r)])),
        const SizedBox(height: 14),
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          if (widget.onAskAi != null)
            OutlinedButton.icon(
              onPressed: () => widget.onAskAi!(f),
              icon: const Icon(Icons.auto_awesome_outlined, size: 16),
              label: const Text('Fix my code with NOVA AI'),
            ),
          if (f.recheck != null)
            OutlinedButton.icon(
              onPressed: _checking
                  ? null
                  : () async {
                      setState(() {
                        _checking = true;
                        _recheckResult = null;
                      });
                      try {
                        final still = await f.recheck!();
                        _recheckResult = still.isEmpty ? 'Fixed — the issue is no longer present.' : 'Still present.';
                      } catch (e) {
                        _recheckResult = 'Couldn\'t re-check: $e';
                      }
                      if (mounted) setState(() => _checking = false);
                    },
              icon: _checking
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Re-check'),
            ),
          if (_recheckResult != null)
            Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(_recheckResult!.startsWith('Fixed') ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                  size: 16, color: _recheckResult!.startsWith('Fixed') ? p.success : p.warning),
              const SizedBox(width: 4),
              Flexible(child: Text(_recheckResult!, style: p.ui(size: 12.5, color: p.textMuted))),
            ]),
        ]),
      ]),
    );
  }
}

/// Small labelled number.
class Metric extends StatelessWidget {
  const Metric({super.key, required this.value, required this.label, this.color});
  final String value;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = NovaThemeScope.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text(value, style: p.title(size: 22, color: color ?? p.text).copyWith(height: 1.1)),
      const SizedBox(height: 2),
      Text(label, style: p.ui(size: 11.5, color: p.textFaint, weight: FontWeight.w600)),
    ]);
  }
}

/// Section frame used across the screen.
class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.title, this.trailing, this.padding = const EdgeInsets.all(16)});
  final Widget child;
  final String? title;
  final Widget? trailing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final p = NovaThemeScope.of(context);
    return Container(
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: p.border)),
      padding: padding,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        if (title != null) ...[
          Row(children: [
            Text(title!, style: p.ui(size: 13, weight: FontWeight.w700, color: p.text)),
            const Spacer(),
            if (trailing != null) trailing!,
          ]),
          const SizedBox(height: 12),
        ],
        child,
      ]),
    );
  }
}
