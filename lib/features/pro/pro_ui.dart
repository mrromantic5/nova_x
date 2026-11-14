// lib/features/pro/pro_ui.dart
//
// NOVA X Pro tools — shared look: page frame, cards, chips, rows, scores.
// Android (3.13.0): same building blocks as NOVA X for PC, laid out for
// phones (pages are full screens with an app bar; dialogs fill the screen).

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/widgets/nova_toast.dart';
import '../cyber/ui/cyber_palette.dart';
import '../guide/guide_screen.dart';

/// Risk / severity levels used across the tools.
enum ProLevel { good, info, low, medium, high, critical }

extension ProLevelX on ProLevel {
  String get label => switch (this) {
        ProLevel.good => 'Good',
        ProLevel.info => 'Info',
        ProLevel.low => 'Low',
        ProLevel.medium => 'Medium',
        ProLevel.high => 'High',
        ProLevel.critical => 'Critical',
      };

  Color color(NovaPalette p) => switch (this) {
        ProLevel.good => p.success,
        ProLevel.info => p.accent,
        ProLevel.low => const Color(0xFF7DD3FC),
        ProLevel.medium => p.warning,
        ProLevel.high => const Color(0xFFFF8A4C),
        ProLevel.critical => p.danger,
      };

  static ProLevel parse(Object? v) => ProLevel.values.where((l) => l.name == v).firstOrNull ?? ProLevel.info;
}

/// A NOVA X page (tab) in the chrome palette, with a header and a body.
class ProPage extends StatelessWidget {
  const ProPage({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
    this.actions = const [],
    this.maxWidth = 1280,
    this.guide,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;
  final List<Widget> actions;
  final double maxWidth;

  /// Feature Guide section for the "Read more" link in the header.
  final String? guide;

  @override
  Widget build(BuildContext context) {
    return NovaThemed(
      child: Builder(builder: (context) {
        final p = NovaThemeScope.of(context);
        return Scaffold(
          backgroundColor: p.bg,
          appBar: AppBar(
            backgroundColor: p.surface,
            surfaceTintColor: Colors.transparent,
            titleSpacing: 0,
            title: Row(children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(color: p.accentSoft, borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, color: p.accent, size: 19),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(title, style: p.ui(size: 16, weight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(subtitle, style: p.ui(size: 11, color: p.textMuted), maxLines: 1, overflow: TextOverflow.ellipsis),
                ]),
              ),
            ]),
            actions: [
              if (guide != null) Center(child: ReadMoreLink(guide!, compact: true)),
              ...actions,
              const SizedBox(width: 6),
            ],
          ),
          body: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: child),
          ),
        );
      }),
    );
  }
}

/// A rounded card with an optional title row.
class ProCard extends StatelessWidget {
  const ProCard({super.key, this.title, this.icon, this.trailing, required this.child, this.padding = const EdgeInsets.all(16), this.guide});

  /// Feature Guide section for a "Read more" link in the title row.
  final String? guide;
  final String? title;
  final IconData? icon;
  final Widget? trailing;
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final p = NovaThemeScope.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: p.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 10, 0),
            child: Row(children: [
              if (icon != null) ...[Icon(icon, size: 17, color: p.accent), const SizedBox(width: 8)],
              Expanded(child: Text(title!, style: p.ui(size: 13.5, weight: FontWeight.w700, color: p.text))),
              if (guide != null) ReadMoreLink(guide!, compact: true),
              if (trailing != null) trailing!,
            ]),
          ),
        Padding(padding: padding, child: child),
      ]),
    );
  }
}

/// A small coloured label.
class ProChip extends StatelessWidget {
  const ProChip(this.text, {super.key, this.color, this.icon});
  final String text;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final p = NovaThemeScope.of(context);
    final c = color ?? p.accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withValues(alpha: 0.45)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 12, color: c), const SizedBox(width: 4)],
        Text(text, style: p.ui(size: 11, weight: FontWeight.w700, color: c)),
      ]),
    );
  }
}

class ProLevelChip extends StatelessWidget {
  const ProLevelChip(this.level, {super.key});
  final ProLevel level;

  @override
  Widget build(BuildContext context) => ProChip(level.label, color: level.color(NovaThemeScope.of(context)));
}

/// "Label ........ value" row.
class ProKv extends StatelessWidget {
  const ProKv(this.label, this.value, {super.key, this.valueColor, this.mono = false});
  final String label;
  final String value;
  final Color? valueColor;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final p = NovaThemeScope.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 120, child: Text(label, style: p.ui(size: 12.5, color: p.textMuted))),
        Expanded(
          child: SelectableText(
            value,
            style: mono
                ? TextStyle(fontFamily: 'monospace', fontSize: 12.5, color: valueColor ?? p.text)
                : p.ui(size: 12.5, color: valueColor ?? p.text, weight: FontWeight.w600),
          ),
        ),
      ]),
    );
  }
}

/// One finding line: coloured dot, title, detail.
class ProFindingRow extends StatelessWidget {
  const ProFindingRow({super.key, required this.level, required this.title, this.detail, this.trailing});
  final ProLevel level;
  final String title;
  final String? detail;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = NovaThemeScope.of(context);
    final c = level.color(p);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Container(width: 9, height: 9, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: p.ui(size: 13, weight: FontWeight.w600, color: p.text)),
            if (detail != null && detail!.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(detail!, style: p.ui(size: 12, color: p.textMuted, height: 1.35)),
            ],
          ]),
        ),
        if (trailing != null) trailing!,
      ]),
    );
  }
}

/// A circular score (0–100) with a big label in the middle.
class ProScoreRing extends StatelessWidget {
  const ProScoreRing({super.key, required this.score, required this.label, required this.color, this.size = 96});
  final int score;
  final String label;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = NovaThemeScope.of(context);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(alignment: Alignment.center, children: [
        SizedBox(
          width: size,
          height: size,
          child: CircularProgressIndicator(
            value: (score.clamp(0, 100)) / 100,
            strokeWidth: 8,
            color: color,
            backgroundColor: p.border,
          ),
        ),
        Column(mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: p.title(size: size * 0.3, color: color)),
          Text('$score / 100', style: p.ui(size: 10.5, color: p.textMuted)),
        ]),
      ]),
    );
  }
}

/// Centered message for empty lists.
class ProEmpty extends StatelessWidget {
  const ProEmpty({super.key, required this.icon, required this.title, this.text, this.action});
  final IconData icon;
  final String title;
  final String? text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final p = NovaThemeScope.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 44, color: p.textFaint),
          const SizedBox(height: 12),
          Text(title, style: p.ui(size: 15, weight: FontWeight.w700, color: p.text), textAlign: TextAlign.center),
          if (text != null) ...[
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Text(text!, style: p.ui(size: 12.5, color: p.textMuted, height: 1.4), textAlign: TextAlign.center),
            ),
          ],
          if (action != null) ...[const SizedBox(height: 16), action!],
        ]),
      ),
    );
  }
}

/// A text field in the chrome palette.
class ProField extends StatelessWidget {
  const ProField({
    super.key,
    required this.controller,
    this.hint,
    this.label,
    this.maxLines = 1,
    this.minLines,
    this.mono = false,
    this.onChanged,
    this.onSubmitted,
    this.prefix,
    this.obscure = false,
    this.expands = false,
  });

  final TextEditingController controller;
  final String? hint;
  final String? label;
  final int? maxLines;
  final int? minLines;
  final bool mono;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final Widget? prefix;
  final bool obscure;

  /// Fill the parent's height (multi-line editors inside an Expanded).
  final bool expands;

  @override
  Widget build(BuildContext context) {
    final p = NovaThemeScope.of(context);
    return TextField(
      controller: controller,
      expands: expands && !obscure,
      textAlignVertical: expands ? TextAlignVertical.top : null,
      maxLines: expands && !obscure ? null : (obscure ? 1 : maxLines),
      minLines: expands && !obscure ? null : minLines,
      obscureText: obscure,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      style: mono ? TextStyle(fontFamily: 'monospace', fontSize: 13, color: p.text) : p.ui(size: 13.5, color: p.text),
      decoration: InputDecoration(
        isDense: true,
        hintText: hint,
        labelText: label,
        prefixIcon: prefix,
        hintStyle: p.ui(size: 13, color: p.textFaint),
        labelStyle: p.ui(size: 12.5, color: p.textMuted),
        filled: true,
        fillColor: p.surfaceAlt,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: p.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: p.border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: p.accent)),
      ),
    );
  }
}

/// Copies [text] and shows a short confirmation.
Future<void> proCopy(String text, {String what = 'Copied'}) async {
  await Clipboard.setData(ClipboardData(text: text));
  NovaToast.show(what, kind: NovaToastKind.success);
}

void proToast(String text, {bool ok = true}) =>
    NovaToast.show(text, kind: ok ? NovaToastKind.success : NovaToastKind.warning);

/// A wide dialog in the chrome palette (title row with icon + close).
class ProDialog extends StatelessWidget {
  const ProDialog({
    super.key,
    required this.icon,
    required this.title,
    required this.child,
    this.subtitle,
    this.actions = const [],
    this.width = 760,
    this.height,
    this.guide,
  });

  /// Feature Guide section for the "Read more" link in the title row.
  final String? guide;

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget child;
  final List<Widget> actions;
  final double width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final p = NovaThemeScope.of(context);
    final screen = MediaQuery.sizeOf(context);
    return Dialog(
      backgroundColor: p.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: SizedBox(
        width: width.clamp(280.0, math.max(280.0, screen.width - 20)),
        height: (height ?? screen.height * 0.85).clamp(260.0, math.max(260.0, screen.height - 48)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 4, 10),
            child: Row(children: [
              Icon(icon, color: p.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: p.title(size: 17)),
                  if (subtitle != null)
                    Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: p.ui(size: 12, color: p.textMuted)),
                ]),
              ),
              if (guide != null) ReadMoreLink(guide!, compact: true),
              IconButton(onPressed: () => Navigator.of(context).pop(), icon: Icon(Icons.close_rounded, color: p.textMuted)),
            ]),
          ),
          Divider(height: 1, color: p.border),
          Expanded(child: child),
          if (actions.isNotEmpty) ...[
            Divider(height: 1, color: p.border),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Wrap(alignment: WrapAlignment.end, spacing: 8, runSpacing: 8, children: actions),
            ),
          ],
        ]),
      ),
    );
  }
}

/// Opens a [ProDialog]-style dialog in the chrome palette.
Future<T?> showProDialog<T>(BuildContext context, Widget Function(BuildContext ctx) builder) {
  return showDialog<T>(context: context, builder: (ctx) => NovaThemed(child: Builder(builder: builder)));
}

/// Wildcard pattern ("*" = anything) → RegExp, case-insensitive.
RegExp proWildcard(String pattern) {
  final esc = pattern.split('*').map(RegExp.escape).join('.*');
  return RegExp('^$esc\$', caseSensitive: false);
}

/// The registrable-looking part of a host ("a.b.example.co.uk" → "example.co.uk").
String proBaseDomain(String host) {
  final h = host.toLowerCase().replaceAll(RegExp(r'\.$'), '');
  if (RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(h) || h.contains(':')) return h;
  final parts = h.split('.');
  if (parts.length <= 2) return h;
  const twoLevel = {'co', 'com', 'net', 'org', 'gov', 'edu', 'ac', 'or', 'ne', 'go'};
  final sld = parts[parts.length - 2];
  if (twoLevel.contains(sld) && parts.last.length == 2 && parts.length >= 3) {
    return parts.sublist(parts.length - 3).join('.');
  }
  return parts.sublist(parts.length - 2).join('.');
}

/// Escapes text for a JavaScript single-quoted string.
String proJsString(String s) => "'${s.replaceAll(r'\', r'\\').replaceAll("'", r"\'").replaceAll('\n', r'\n').replaceAll('\r', '').replaceAll('</', r'<\/')}'";
