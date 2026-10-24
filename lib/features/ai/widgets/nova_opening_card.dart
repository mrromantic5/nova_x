// lib/features/ai/widgets/nova_opening_card.dart
//
// The "opening a page" reply inside the NOVA AI conversation (3.8.1): the
// page icon in a spinning NOVA ring, "Opening NOVA Music…" and a progress
// line that fills while NOVA gets the page ready. Shown as a normal chat
// bubble — no extra screen or popup — then the page opens.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_theme.dart';

class NovaOpeningCard extends StatefulWidget {
  const NovaOpeningCard({
    super.key,
    required this.label,
    required this.icon,
    this.duration = const Duration(milliseconds: 1500),
  });

  final String label;
  final IconData icon;

  /// How long the progress line takes to fill (matches the chat's delay).
  final Duration duration;

  @override
  State<NovaOpeningCard> createState() => _NovaOpeningCardState();
}

class _NovaOpeningCardState extends State<NovaOpeningCard> with TickerProviderStateMixin {
  late final AnimationController _spin =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();
  late final AnimationController _fill = AnimationController(vsync: this, duration: widget.duration)..forward();

  @override
  void dispose() {
    _spin.dispose();
    _fill.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppTheme.accentCyan.withOpacity(0.35)),
          boxShadow: [BoxShadow(color: AppTheme.accentCyan.withOpacity(0.10), blurRadius: 18)],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            width: 46,
            height: 46,
            child: AnimatedBuilder(
              animation: _spin,
              builder: (_, child) => CustomPaint(painter: _RingPainter(_spin.value), child: child),
              child: Center(
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [AppTheme.accentCyan, AppTheme.accentPurple],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Icon(widget.icon, color: Colors.white, size: 16),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Opening ${widget.label}…',
                  style: GoogleFonts.spaceGrotesk(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text('NOVA is getting it ready',
                  style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 11.5)),
              const SizedBox(height: 8),
              SizedBox(
                width: 150,
                child: AnimatedBuilder(
                  animation: _fill,
                  builder: (_, __) => ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: Curves.easeInOut.transform(_fill.value),
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
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 2;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white.withOpacity(0.07),
    );
    final start = t * 2 * math.pi;
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawArc(
      rect,
      start,
      math.pi * 1.2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 2.5
        ..shader = SweepGradient(
          colors: [AppTheme.accentCyan.withOpacity(0), AppTheme.accentCyan],
          stops: const [0.0, 0.6],
          transform: GradientRotation(start),
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.t != t;
}
