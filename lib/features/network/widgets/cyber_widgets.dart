// lib/features/network/widgets/cyber_widgets.dart
//
// NOVA Network look: dark cyber grid, neon cards, the speed gauge, live
// throughput chart, signal bars and grade badges.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_theme.dart';
import '../services/speed_math.dart';

class Cyber {
  Cyber._();

  static const Color bg = Color(0xFF040A16);
  static const Color panel = Color(0xFF0A1528);
  static const Color line = Color(0x2600D4FF);
  static const Color cyan = AppTheme.accentCyan;
  static const Color purple = AppTheme.accentPurple;
  static const Color green = Color(0xFF39FFB0);
  static const Color amber = Color(0xFFFFC53D);
  static const Color red = Color(0xFFFF4D6A);
  static const Color text = Color(0xFFE6F1FF);
  static const Color dim = Color(0xFF7D93B2);

  static TextStyle digits(double size, {Color color = text, FontWeight weight = FontWeight.w600}) =>
      GoogleFonts.getFont('Orbitron', fontSize: size, color: color, fontWeight: weight, letterSpacing: 0.5);

  static TextStyle label(double size, {Color color = dim, FontWeight weight = FontWeight.w500}) =>
      GoogleFonts.inter(fontSize: size, color: color, fontWeight: weight);

  static Color forLevel(int level) => switch (level) {
        3 => green,
        2 => cyan,
        1 => amber,
        _ => red,
      };

  static Color forGrade(String g) => switch (g) {
        'A+' || 'A' => green,
        'B' => cyan,
        'C' => amber,
        '—' => dim,
        _ => red,
      };
}

/// Animated grid with a slow scan line (background of the whole page).
class CyberBackground extends StatefulWidget {
  const CyberBackground({super.key, required this.child});
  final Widget child;

  @override
  State<CyberBackground> createState() => _CyberBackgroundState();
}

class _CyberBackgroundState extends State<CyberBackground> with SingleTickerProviderStateMixin {
  late final AnimationController _scan =
      AnimationController(vsync: this, duration: const Duration(seconds: 7))..repeat();

  @override
  void dispose() {
    _scan.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      const Positioned.fill(child: ColoredBox(color: Cyber.bg)),
      Positioned.fill(
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: _scan,
            builder: (_, __) => CustomPaint(painter: _GridPainter(_scan.value)),
          ),
        ),
      ),
      Positioned(
        top: -120,
        right: -100,
        child: _glow(320, Cyber.cyan.withValues(alpha: 0.16)),
      ),
      Positioned(
        bottom: -120,
        left: -120,
        child: _glow(320, Cyber.purple.withValues(alpha: 0.14)),
      ),
      Positioned.fill(child: widget.child),
    ]);
  }

  static Widget _glow(double size, Color c) => IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [c, Colors.transparent]),
          ),
        ),
      );
}

class _GridPainter extends CustomPainter {
  _GridPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = const Color(0x0F00D4FF)
      ..strokeWidth = 1;
    const step = 28.0;
    for (var x = 0.0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (var y = 0.0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final y = size.height * t;
    final scan = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0x0000D4FF), Color(0x1A00D4FF), Color(0x0000D4FF)],
      ).createShader(Rect.fromLTWH(0, y - 60, size.width, 120));
    canvas.drawRect(Rect.fromLTWH(0, y - 60, size.width, 120), scan);
  }

  @override
  bool shouldRepaint(_GridPainter old) => old.t != t;
}

/// Glassy card with a thin neon border.
class NeonCard extends StatelessWidget {
  const NeonCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.accent = Cyber.cyan});
  final Widget child;
  final EdgeInsets padding;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Cyber.panel.withValues(alpha: 0.92), const Color(0xEE07101F)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
        boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.06), blurRadius: 24, spreadRadius: -4)],
      ),
      child: child,
    );
  }
}

/// Section title: "▍ CONNECTION".
class CyberHeading extends StatelessWidget {
  const CyberHeading(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 4),
      child: Row(children: [
        Container(
          width: 3,
          height: 14,
          decoration: BoxDecoration(gradient: AppTheme.primaryGradient, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text.toUpperCase(),
              style: GoogleFonts.spaceGrotesk(
                  color: Cyber.dim, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 2)),
        ),
        if (trailing != null) trailing!,
      ]),
    );
  }
}

/// The speed dial: neon arc, tick labels, needle and the live number.
class SpeedGauge extends StatelessWidget {
  const SpeedGauge({
    super.key,
    required this.mbps,
    required this.scale,
    required this.color,
    this.center,
  });

  final double mbps;
  final List<double> scale;
  final Color color;

  /// Widget in the middle (GO button, or the number).
  final Widget? center;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: SpeedMath.gaugeFraction(mbps, scale)),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      builder: (_, f, __) => AspectRatio(
        aspectRatio: 1,
        child: CustomPaint(
          painter: _GaugePainter(fraction: f, scale: scale, color: color),
          child: Center(child: center),
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter({required this.fraction, required this.scale, required this.color});
  final double fraction;
  final List<double> scale;
  final Color color;

  static const double _start = math.pi * 0.75; // 135°
  static const double _sweep = math.pi * 1.5; // 270°

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 18;
    final rect = Rect.fromCircle(center: c, radius: r);

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFF16233A);
    canvas.drawArc(rect, _start, _sweep, false, track);

    if (fraction > 0) {
      final glow = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 26
        ..strokeCap = StrokeCap.round
        ..color = color.withValues(alpha: 0.18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
      canvas.drawArc(rect, _start, _sweep * fraction, false, glow);
      final arc = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 16
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          startAngle: _start,
          endAngle: _start + _sweep,
          colors: [const Color(0xFF1E7BFF), color, Cyber.green],
          stops: const [0, 0.55, 1],
          transform: const GradientRotation(0),
        ).createShader(rect);
      canvas.drawArc(rect, _start, _sweep * fraction, false, arc);
    }

    // Tick labels
    final segments = scale.length - 1;
    for (var i = 0; i < scale.length; i++) {
      final a = _start + _sweep * (i / segments);
      final on = i / segments <= fraction + 0.001;
      final v = scale[i];
      final label = v >= 1000 ? '${(v / 1000).toStringAsFixed(v % 1000 == 0 ? 0 : 1)}k' : v.toStringAsFixed(0);
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: GoogleFonts.spaceGrotesk(
            color: on ? Cyber.text : Cyber.dim,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final p = c + Offset(math.cos(a), math.sin(a)) * (r - 34);
      tp.paint(canvas, p - Offset(tp.width / 2, tp.height / 2));
      final tick = Paint()
        ..color = on ? color.withValues(alpha: 0.8) : const Color(0x33FFFFFF)
        ..strokeWidth = 2;
      canvas.drawLine(c + Offset(math.cos(a), math.sin(a)) * (r + 12),
          c + Offset(math.cos(a), math.sin(a)) * (r + 4), tick);
    }

    // Needle
    if (fraction > 0) {
      final a = _start + _sweep * fraction;
      final tip = c + Offset(math.cos(a), math.sin(a)) * (r - 50);
      final base = c + Offset(math.cos(a), math.sin(a)) * (r * 0.18);
      final needle = Paint()
        ..shader = LinearGradient(colors: [Colors.white.withValues(alpha: 0.0), Colors.white])
            .createShader(Rect.fromPoints(base, tip))
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(base, tip, needle);
      canvas.drawCircle(tip, 3, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.fraction != fraction || old.color != color || old.scale != scale;
}

/// Live throughput chart (download cyan, upload purple).
class LiveChart extends StatelessWidget {
  const LiveChart({super.key, required this.down, required this.up, this.height = 70});
  final List<double> down;
  final List<double> up;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(painter: _ChartPainter(down, up)),
    );
  }
}

class _ChartPainter extends CustomPainter {
  _ChartPainter(this.down, this.up);
  final List<double> down;
  final List<double> up;

  @override
  void paint(Canvas canvas, Size size) {
    final maxV = [...down, ...up, 1.0].reduce(math.max) * 1.15;
    final base = Paint()
      ..color = const Color(0x1400D4FF)
      ..strokeWidth = 1;
    for (var i = 1; i < 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), base);
    }
    void series(List<double> v, Color color, double from, double to) {
      if (v.length < 2) return;
      final w = (to - from) * size.width;
      final path = Path();
      for (var i = 0; i < v.length; i++) {
        final x = from * size.width + w * i / (v.length - 1);
        final y = size.height - (v[i] / maxV) * size.height;
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      final fill = Path.from(path)
        ..lineTo(to * size.width, size.height)
        ..lineTo(from * size.width, size.height)
        ..close();
      canvas.drawPath(
        fill,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [color.withValues(alpha: 0.35), color.withValues(alpha: 0.0)],
          ).createShader(Offset.zero & size),
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round,
      );
    }

    final split = up.isEmpty ? 1.0 : 0.5;
    series(down, Cyber.cyan, 0, split);
    if (up.isNotEmpty) series(up, Cyber.purple, 0.5, 1);
  }

  @override
  bool shouldRepaint(_ChartPainter old) => old.down.length != down.length || old.up.length != up.length;
}

/// Simple bar chart for the history (newest on the right).
class HistoryBars extends StatelessWidget {
  const HistoryBars({super.key, required this.values, this.height = 90, this.color = Cyber.cyan});
  final List<double> values;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final maxV = values.isEmpty ? 1.0 : values.reduce(math.max).clamp(1.0, double.infinity);
    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final v in values)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Container(
                  height: math.max(3.0, height * v / maxV),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [color.withValues(alpha: 0.25), color],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 0–4 signal bars.
class SignalBars extends StatelessWidget {
  const SignalBars({super.key, required this.level, this.color = Cyber.cyan});
  final int level;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 1; i <= 4; i++)
          Container(
            width: 5,
            height: 4.0 + i * 4,
            margin: const EdgeInsets.only(right: 2),
            decoration: BoxDecoration(
              color: i <= level ? color : const Color(0x33FFFFFF),
              borderRadius: BorderRadius.circular(1.5),
            ),
          ),
      ],
    );
  }
}

/// Small rounded badge: "Great", "A+".
class GradeBadge extends StatelessWidget {
  const GradeBadge(this.text, this.color, {super.key});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(text, style: GoogleFonts.spaceGrotesk(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }
}

/// Label/value row used in the info cards.
class InfoRow extends StatelessWidget {
  const InfoRow(this.label, this.value, {super.key, this.icon, this.trailing, this.valueColor});
  final String label;
  final String value;
  final IconData? icon;
  final Widget? trailing;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(children: [
        if (icon != null) ...[
          Icon(icon, size: 16, color: Cyber.cyan.withValues(alpha: 0.8)),
          const SizedBox(width: 10),
        ],
        Text(label, style: Cyber.label(13)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(color: valueColor ?? Cyber.text, fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 8), trailing!],
      ]),
    );
  }
}
