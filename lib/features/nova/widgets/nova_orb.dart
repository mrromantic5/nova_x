// lib/features/nova/widgets/nova_orb.dart
//
// NOVA's luminous identity orb. Each assistant state has its own motion:
//   idle — slow breathing · activating — light burst · listening — audio-
//   reactive waveform ring · processing speech — rotating arcs · thinking —
//   orbiting particles · executing — progress sweep · speaking — outward
//   ripples · clarifying / permission — amber pulse with icon · error — red ·
//   disabled — dim and still.
// Honours the system "remove animations" setting (static rendering).

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/nova_models.dart';

class NovaOrb extends StatefulWidget {
  const NovaOrb({
    super.key,
    required this.state,
    required this.level,
    this.size = 116,
  });

  final NovaState state;
  final ValueListenable<double> level;
  final double size;

  static Color colorFor(NovaState s) => switch (s) {
        NovaState.idle => const Color(0xFF00D4FF),
        NovaState.activating => const Color(0xFF39E1FF),
        NovaState.listening => const Color(0xFF00D4FF),
        NovaState.processingSpeech => const Color(0xFF1E7BFF),
        NovaState.thinking => const Color(0xFF8B5CFF),
        NovaState.executing => const Color(0xFF00E0A4),
        NovaState.speaking => const Color(0xFF7C8CFF),
        NovaState.clarifying => const Color(0xFFFFC83D),
        NovaState.permissionRequired => const Color(0xFFFFAB00),
        NovaState.error => const Color(0xFFFF4D6A),
        NovaState.disabled => const Color(0xFF4A6A8A),
      };

  @override
  State<NovaOrb> createState() => _NovaOrbState();
}

class _NovaOrbState extends State<NovaOrb> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl =
      AnimationController(vsync: this, duration: const Duration(seconds: 4));
  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant NovaOrb oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncAnimation();
  }

  void _syncAnimation() {
    final still = _reduceMotion || widget.state == NovaState.disabled;
    if (still) {
      _ctrl.stop();
    } else if (!_ctrl.isAnimating) {
      _ctrl.repeat();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  IconData? get _icon => switch (widget.state) {
        NovaState.clarifying => Icons.help_outline_rounded,
        NovaState.permissionRequired => Icons.lock_outline_rounded,
        NovaState.error => Icons.priority_high_rounded,
        NovaState.disabled => Icons.mic_off_rounded,
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    final icon = _icon;
    return RepaintBoundary(
      child: SizedBox.square(
        dimension: widget.size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            AnimatedBuilder(
              animation: Listenable.merge([_ctrl, widget.level]),
              builder: (context, _) => CustomPaint(
                size: Size.square(widget.size),
                painter: _OrbPainter(
                  state: widget.state,
                  t: _reduceMotion ? 0.25 : _ctrl.value,
                  level: widget.level.value,
                  color: NovaOrb.colorFor(widget.state),
                ),
              ),
            ),
            if (icon != null)
              Icon(icon, color: Colors.white.withOpacity(0.92), size: widget.size * 0.26),
          ],
        ),
      ),
    );
  }
}

class _OrbPainter extends CustomPainter {
  _OrbPainter({required this.state, required this.t, required this.level, required this.color});

  final NovaState state;
  final double t; // 0..1, loops every 4 s
  final double level; // 0..1 microphone level
  final Color color;

  static const _cyan = Color(0xFF00D4FF);
  static const _violet = Color(0xFF7C4DFF);
  static const _blue = Color(0xFF1E7BFF);
  static const _deep = Color(0xFF081226);

  double _wave(double speed, [double phase = 0]) =>
      0.5 + 0.5 * math.sin(2 * math.pi * (t * speed + phase));

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide * 0.30;

    final energy = switch (state) {
      NovaState.idle => 0.35 + 0.25 * _wave(1),
      NovaState.activating => 0.75 + 0.25 * _wave(4),
      NovaState.listening => 0.35 + 0.65 * level,
      NovaState.processingSpeech => 0.55 + 0.15 * _wave(3),
      NovaState.thinking => 0.6 + 0.2 * _wave(2),
      NovaState.executing => 0.7,
      NovaState.speaking => 0.5 + 0.4 * _wave(5),
      NovaState.clarifying || NovaState.permissionRequired => 0.45 + 0.2 * _wave(1.5),
      NovaState.error => 0.45,
      NovaState.disabled => 0.0,
    };

    // Ambient glow.
    if (state != NovaState.disabled) {
      final glowR = r * (1.45 + 0.30 * energy);
      canvas.drawCircle(
        c,
        glowR,
        Paint()
          ..shader = RadialGradient(colors: [
            color.withOpacity(0.10 + 0.40 * energy),
            color.withOpacity(0.0),
          ]).createShader(Rect.fromCircle(center: c, radius: glowR)),
      );
    }

    // State-specific motion around the core.
    switch (state) {
      case NovaState.listening:
        _bars(canvas, c, r);
        break;
      case NovaState.processingSpeech:
        _arcs(canvas, c, r, _blue, speed: 2, count: 3, sweep: 0.9);
        break;
      case NovaState.thinking:
        _particles(canvas, c, r);
        break;
      case NovaState.executing:
        _arcs(canvas, c, r, color, speed: 1.2, count: 1, sweep: math.pi * 0.9, width: 3.2);
        break;
      case NovaState.speaking:
        _ripples(canvas, c, r);
        break;
      case NovaState.activating:
        _burst(canvas, c, r);
        break;
      default:
        break;
    }

    // Rotating spectral ring.
    if (state != NovaState.disabled) {
      final ringR = r * 1.12;
      final rect = Rect.fromCircle(center: c, radius: ringR);
      canvas.drawCircle(
        c,
        ringR,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..shader = SweepGradient(
            colors: [
              color.withOpacity(0.9),
              _violet.withOpacity(0.7),
              _cyan.withOpacity(0.25),
              color.withOpacity(0.9),
            ],
            transform: GradientRotation(2 * math.pi * t),
          ).createShader(rect),
      );
    }

    // Core sphere.
    final coreR = r * (1.0 + 0.05 * energy);
    final core = Rect.fromCircle(center: c, radius: coreR);
    canvas.drawCircle(
      c,
      coreR,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.45),
          radius: 1.0,
          colors: state == NovaState.disabled
              ? [const Color(0xFF6B7F98), const Color(0xFF2A3A52), _deep]
              : [Colors.white.withOpacity(0.95), color, _deep],
          stops: const [0.0, 0.42, 1.0],
        ).createShader(core),
    );

    // Inner swirl highlight.
    if (state != NovaState.disabled) {
      canvas.drawCircle(
        c,
        coreR * 0.92,
        Paint()
          ..shader = SweepGradient(
            colors: [
              Colors.white.withOpacity(0.0),
              Colors.white.withOpacity(0.16),
              Colors.white.withOpacity(0.0),
            ],
            transform: GradientRotation(-2 * math.pi * t * 1.5),
          ).createShader(core),
      );
    }
  }

  void _bars(Canvas canvas, Offset c, double r) {
    const count = 56;
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.4;
    for (var i = 0; i < count; i++) {
      final a = 2 * math.pi * i / count;
      final wobble = 0.55 + 0.45 * math.sin(i * 0.9 + t * 2 * math.pi * 3);
      final h = r * (0.06 + level * 0.42 * wobble);
      final dir = Offset(math.cos(a), math.sin(a));
      paint.color = Color.lerp(_cyan, _violet, (i % 14) / 14)!.withOpacity(0.85);
      canvas.drawLine(c + dir * (r * 1.22), c + dir * (r * 1.22 + h), paint);
    }
  }

  void _arcs(Canvas canvas, Offset c, double r, Color col,
      {required double speed, required int count, required double sweep, double width = 2.6}) {
    final rect = Rect.fromCircle(center: c, radius: r * 1.32);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = width
      ..color = col.withOpacity(0.85);
    for (var k = 0; k < count; k++) {
      final start = 2 * math.pi * (t * speed + k / count);
      canvas.drawArc(rect, start, sweep, false, paint);
    }
  }

  void _particles(Canvas canvas, Offset c, double r) {
    for (var k = 0; k < 3; k++) {
      final a = 2 * math.pi * (t * 1.5 + k / 3);
      final p = c + Offset(math.cos(a), math.sin(a)) * (r * 1.34);
      canvas.drawCircle(p, 6, Paint()..color = _violet.withOpacity(0.25));
      canvas.drawCircle(p, 3.2, Paint()..color = Colors.white.withOpacity(0.9));
    }
  }

  void _ripples(Canvas canvas, Offset c, double r) {
    for (var k = 0; k < 3; k++) {
      final phase = (t * 2 + k / 3) % 1.0;
      canvas.drawCircle(
        c,
        r * (1.08 + phase * 0.62),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = color.withOpacity((1 - phase) * 0.5),
      );
    }
  }

  void _burst(Canvas canvas, Offset c, double r) {
    final phase = (t * 2) % 1.0;
    canvas.drawCircle(
      c,
      r * (1.0 + phase * 0.85),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Colors.white.withOpacity((1 - phase) * 0.6),
    );
  }

  @override
  bool shouldRepaint(covariant _OrbPainter old) =>
      old.t != t || old.level != level || old.state != state || old.color != color;
}
