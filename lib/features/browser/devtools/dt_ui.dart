// lib/features/browser/devtools/dt_ui.dart
//
// Shared widgets of NOVA X Dev Tools: toolbar, filter field, key/value rows,
// JSON tree, code block, score ring, empty states.

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../xcoder/widgets/xcoder_ui.dart';

export '../../xcoder/widgets/xcoder_ui.dart' show XC, XIconBtn, xToast, xConfirm, xPrompt, fileVisual;

String fmtBytes(num b) {
  if (b <= 0) return '—';
  if (b < 1024) return '$b B';
  if (b < 1048576) return '${(b / 1024).toStringAsFixed(1)} KB';
  return '${(b / 1048576).toStringAsFixed(2)} MB';
}

String fmtMs(num? ms) {
  if (ms == null) return '—';
  if (ms < 1000) return '${ms.round()} ms';
  return '${(ms / 1000).toStringAsFixed(2)} s';
}

void dtCopy(BuildContext context, String text, [String what = 'Copied']) {
  Clipboard.setData(ClipboardData(text: text));
  xToast(context, what);
}

class DtToolbar extends StatelessWidget {
  const DtToolbar({super.key, required this.children, this.height = 40});
  final List<Widget> children;
  final double height;

  @override
  Widget build(BuildContext context) => Container(
        height: height,
        decoration: const BoxDecoration(color: XC.bar, border: Border(bottom: BorderSide(color: XC.border))),
        child: Row(children: children),
      );
}

class DtFilter extends StatelessWidget {
  const DtFilter({super.key, required this.onChanged, this.hint = 'Filter', this.controller});
  final ValueChanged<String> onChanged;
  final String hint;
  final TextEditingController? controller;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
        child: TextField(
          controller: controller,
          onChanged: onChanged,
          style: XC.mono(12.5),
          decoration: InputDecoration(
            isDense: true,
            hintText: hint,
            hintStyle: XC.ui(12, color: XC.faint),
            prefixIcon: const Icon(Icons.filter_alt_outlined, size: 16, color: XC.faint),
            prefixIconConstraints: const BoxConstraints(minWidth: 30),
            filled: true,
            fillColor: XC.bg,
            contentPadding: const EdgeInsets.symmetric(vertical: 7),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
          ),
        ),
      );
}

class DtChip extends StatelessWidget {
  const DtChip(this.label, {super.key, required this.selected, required this.onTap, this.color});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 5),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: selected ? (color ?? XC.accent).withOpacity(0.18) : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: selected ? (color ?? XC.accent) : XC.border),
            ),
            child: Text(label, style: XC.ui(11.5, color: selected ? (color ?? XC.accent) : XC.dim, weight: FontWeight.w600)),
          ),
        ),
      );
}

class DtSection extends StatelessWidget {
  const DtSection(this.title, {super.key, this.trailing});
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Container(
        color: XC.bar,
        padding: const EdgeInsets.fromLTRB(12, 7, 6, 7),
        child: Row(children: [
          Expanded(child: Text(title.toUpperCase(), style: XC.ui(11, color: XC.dim, weight: FontWeight.w800))),
          if (trailing != null) trailing!,
        ]),
      );
}

class DtKV extends StatelessWidget {
  const DtKV(this.k, this.v, {super.key, this.mono = true, this.valueColor, this.onTap});
  final String k;
  final String v;
  final bool mono;
  final Color? valueColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        onLongPress: () => dtCopy(context, v, 'Copied $k'),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 128, child: Text(k, style: XC.mono(12, color: const Color(0xFF9CDCFE)))),
            Expanded(
              child: SelectableText(v.isEmpty ? '—' : v,
                  style: mono ? XC.mono(12, color: valueColor ?? XC.text) : XC.ui(12.5, color: valueColor ?? XC.text)),
            ),
          ]),
        ),
      );
}

class DtEmpty extends StatelessWidget {
  const DtEmpty(this.icon, this.title, {super.key, this.body = '', this.action});
  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 34, color: XC.faint),
            const SizedBox(height: 10),
            Text(title, style: XC.ui(14, color: XC.dim, weight: FontWeight.w700), textAlign: TextAlign.center),
            if (body.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(body, style: XC.ui(12.5, color: XC.faint), textAlign: TextAlign.center),
            ],
            if (action != null) ...[const SizedBox(height: 12), action!],
          ]),
        ),
      );
}

/// Code / text block with copy.
class DtCode extends StatelessWidget {
  const DtCode(this.text, {super.key, this.maxLines, this.label});
  final String text;
  final int? maxLines;
  final String? label;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: const Color(0xFF070D18), borderRadius: BorderRadius.circular(8), border: Border.all(color: XC.border)),
        child: Stack(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 34, 10),
            child: SelectableText(text.isEmpty ? '(empty)' : text, style: XC.mono(11.5), maxLines: maxLines),
          ),
          Positioned(
            right: 0,
            top: 0,
            child: XIconBtn(Icons.copy_rounded, tooltip: 'Copy', onTap: () => dtCopy(context, text, label == null ? 'Copied' : 'Copied $label'), size: 16),
          ),
        ]),
      );
}

/// Pretty JSON text, or the original when it isn't JSON.
String prettyJson(String s) {
  try {
    return const JsonEncoder.withIndent('  ').convert(jsonDecode(s));
  } catch (_) {
    return s;
  }
}

/// Expandable JSON tree.
class JsonTree extends StatefulWidget {
  const JsonTree(this.value, {super.key, this.name, this.depth = 0, this.initiallyOpen = true});
  final Object? value;
  final String? name;
  final int depth;
  final bool initiallyOpen;

  @override
  State<JsonTree> createState() => _JsonTreeState();
}

class _JsonTreeState extends State<JsonTree> {
  late bool _open = widget.initiallyOpen && widget.depth < 2;

  @override
  Widget build(BuildContext context) {
    final v = widget.value;
    final name = widget.name;
    final pad = EdgeInsets.only(left: 10.0 + widget.depth * 14, right: 8, top: 2, bottom: 2);
    final key = name == null ? const <InlineSpan>[] : [TextSpan(text: '$name: ', style: XC.mono(12, color: const Color(0xFF9CDCFE)))];
    if (v is Map || v is List) {
      final entries = v is Map ? v.entries.map((e) => MapEntry(e.key.toString(), e.value)).toList() : [for (final (i, x) in (v as List).indexed) MapEntry('$i', x)];
      final summary = v is Map ? '{${v.length}}' : '[${(v as List).length}]';
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        InkWell(
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: pad,
            child: Text.rich(TextSpan(children: [
              WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Icon(_open ? Icons.arrow_drop_down_rounded : Icons.arrow_right_rounded, size: 18, color: XC.dim)),
              ...key,
              TextSpan(text: summary, style: XC.mono(12, color: XC.faint)),
            ])),
          ),
        ),
        if (_open)
          for (final e in entries.take(500)) JsonTree(e.value, name: e.key, depth: widget.depth + 1, initiallyOpen: false),
        if (_open && entries.length > 500)
          Padding(padding: pad.copyWith(left: pad.left + 14), child: Text('… ${entries.length - 500} more', style: XC.mono(11.5, color: XC.faint))),
      ]);
    }
    final (text, color) = switch (v) {
      null => ('null', const Color(0xFF569CD6)),
      String s => (jsonEncode(s), const Color(0xFFCE9178)),
      num n => ('$n', const Color(0xFFB5CEA8)),
      bool b => ('$b', const Color(0xFF569CD6)),
      _ => ('$v', XC.text),
    };
    return Padding(
      padding: pad.copyWith(left: pad.left + 18),
      child: SelectableText.rich(TextSpan(children: [...key, TextSpan(text: text, style: XC.mono(12, color: color))])),
    );
  }
}

/// Lighthouse-style score ring.
class ScoreRing extends StatelessWidget {
  const ScoreRing(this.score, {super.key, this.size = 64, this.label});
  final int score;
  final double size;
  final String? label;

  static Color colorFor(int s) => s >= 90 ? const Color(0xFF0CCE6B) : (s >= 50 ? const Color(0xFFFFA400) : const Color(0xFFFF4E42));

  @override
  Widget build(BuildContext context) {
    final c = colorFor(score);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _RingPainter(score / 100, c),
          child: Center(child: Text('$score', style: XC.ui(size * 0.3, color: c, weight: FontWeight.w800))),
        ),
      ),
      if (label != null) ...[
        const SizedBox(height: 6),
        Text(label!, style: XC.ui(11.5, color: XC.dim, weight: FontWeight.w600), textAlign: TextAlign.center),
      ],
    ]);
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.v, this.c);
  final double v;
  final Color c;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromLTWH(4, 4, size.width - 8, size.height - 8);
    final bg = Paint()
      ..color = c.withOpacity(0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6;
    final fg = Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    canvas.drawOval(r, bg);
    canvas.drawArc(r, -math.pi / 2, 2 * math.pi * v.clamp(0.0, 1.0), false, fg);
  }

  @override
  bool shouldRepaint(_RingPainter o) => o.v != v || o.c != c;
}

Color statusColor(int s) {
  if (s == 0) return XC.error;
  if (s >= 500) return XC.error;
  if (s >= 400) return const Color(0xFFFF8A65);
  if (s >= 300) return XC.warning;
  if (s >= 200) return XC.ok;
  return XC.dim;
}
