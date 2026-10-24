// lib/features/nova/widgets/nova_launch_screen.dart
//
// The short "NOVA is opening …" transition shown when NOVA opens a NOVA X
// page (typed in NOVA AI, said to NOVA, or handed over from the floating
// assistant). About 1.4 s: the page icon inside rotating NOVA rings, the
// page name and a progress line, then a fade/scale into the page.
// Respects "reduce motion" (shorter, no rotation).

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_theme.dart';

class NovaLaunchScreen extends StatefulWidget {
  const NovaLaunchScreen({
    super.key,
    required this.label,
    required this.icon,
    required this.builder,
    this.duration = const Duration(milliseconds: 1400),
    this.routeName,
  });

  /// "NOVA Music", "your bookmarks"…
  final String label;
  final IconData icon;

  /// The page to open afterwards.
  final WidgetBuilder builder;
  final Duration duration;
  final String? routeName;

  @override
  State<NovaLaunchScreen> createState() => _NovaLaunchScreenState();
}

class _NovaLaunchScreenState extends State<NovaLaunchScreen> with TickerProviderStateMixin {
  late final AnimationController _spin =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();
  late final AnimationController _progress = AnimationController(vsync: this, duration: widget.duration);
  bool _left = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
      if (reduce) {
        _spin.stop();
        _progress.duration = const Duration(milliseconds: 500);
      }
      _progress.forward().whenComplete(_open);
    });
  }

  void _open() {
    if (!mounted || _left) return;
    _left = true;
    Navigator.of(context).pushReplacement(PageRouteBuilder<void>(
      settings: RouteSettings(name: widget.routeName),
      transitionDuration: const Duration(milliseconds: 320),
      pageBuilder: (ctx, _, __) => widget.builder(ctx),
      transitionsBuilder: (_, a, __, child) {
        final c = CurvedAnimation(parent: a, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: c,
          child: ScaleTransition(scale: Tween(begin: 0.96, end: 1.0).animate(c), child: child),
        );
      },
    ));
  }

  @override
  void dispose() {
    _spin.dispose();
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      body: Stack(children: [
        // Soft cyan/purple glow behind everything.
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, -0.15),
                radius: 0.9,
                colors: [AppTheme.accentCyan.withOpacity(0.16), AppTheme.bgDark],
              ),
            ),
          ),
        ),
        Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(
              width: 150,
              height: 150,
              child: AnimatedBuilder(
                animation: Listenable.merge([_spin, _progress]),
                builder: (_, __) => CustomPaint(
                  painter: _RingsPainter(_spin.value, _progress.value),
                  child: Center(
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          colors: [AppTheme.accentCyan, AppTheme.accentPurple],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.accentCyan.withOpacity(0.35 + 0.25 * math.sin(_spin.value * 2 * math.pi).abs()),
                            blurRadius: 26,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Icon(widget.icon, color: Colors.white, size: 30),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 26),
            Text('NOVA',
                style: GoogleFonts.spaceGrotesk(
                    color: AppTheme.accentCyan, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 4)),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text('Opening ${widget.label}',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.spaceGrotesk(
                      color: AppTheme.textPrimary, fontSize: 20, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: 180,
              child: AnimatedBuilder(
                animation: _progress,
                builder: (_, __) => ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: Curves.easeInOut.transform(_progress.value),
                    minHeight: 3,
                    backgroundColor: Colors.white.withOpacity(0.08),
                    valueColor: const AlwaysStoppedAnimation(AppTheme.accentCyan),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

class _RingsPainter extends CustomPainter {
  _RingsPainter(this.t, this.p);
  final double t; // spin 0..1
  final double p; // progress 0..1

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 6;
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white.withOpacity(0.06);
    canvas.drawCircle(c, r, track);
    canvas.drawCircle(c, r - 14, track);

    // Outer arc: spins; inner arc: counter-spins and grows with progress.
    void arc(double radius, double start, double sweep, List<Color> colors, double width) {
      final rect = Rect.fromCircle(center: c, radius: radius);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = width
        ..shader = SweepGradient(
          startAngle: start,
          endAngle: start + sweep,
          colors: colors,
          transform: GradientRotation(start),
        ).createShader(rect);
      canvas.drawArc(rect, start, sweep, false, paint);
    }

    final a = t * 2 * math.pi;
    arc(r, a, math.pi * 1.1, [AppTheme.accentCyan.withOpacity(0.0), AppTheme.accentCyan], 3);
    arc(r - 14, -a * 1.4, math.pi * (0.35 + 1.5 * p),
        [AppTheme.accentPurple.withOpacity(0.0), AppTheme.accentPurple], 2.5);

    // Orbiting dot.
    final dot = Offset(c.dx + r * math.cos(a + math.pi * 1.1), c.dy + r * math.sin(a + math.pi * 1.1));
    canvas.drawCircle(dot, 4, Paint()..color = AppTheme.accentCyan);
    canvas.drawCircle(dot, 9, Paint()..color = AppTheme.accentCyan.withOpacity(0.18));
  }

  @override
  bool shouldRepaint(_RingsPainter old) => old.t != t || old.p != p;
}
