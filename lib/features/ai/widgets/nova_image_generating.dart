// lib/features/ai/widgets/nova_image_generating.dart
//
// The placeholder shown in NOVA AI while an image is being created
// (/image …): a shimmering canvas with NOVA's sparkle, the prompt, and
// stages that move on while the image service works. Replaced by the image
// as soon as it arrives.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_theme.dart';

class NovaImageGenerating extends StatefulWidget {
  const NovaImageGenerating({super.key, required this.prompt});
  final String prompt;

  @override
  State<NovaImageGenerating> createState() => _NovaImageGeneratingState();
}

class _NovaImageGeneratingState extends State<NovaImageGenerating> with SingleTickerProviderStateMixin {
  static const _stages = [
    'Understanding your idea',
    'Composing the scene',
    'Painting light and colour',
    'Adding fine detail',
    'Finishing touches',
  ];

  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat();
  Timer? _stageTimer;
  int _stage = 0;
  final Stopwatch _elapsed = Stopwatch()..start();

  @override
  void initState() {
    super.initState();
    _stageTimer = Timer.periodic(const Duration(milliseconds: 2600), (_) {
      if (mounted && _stage < _stages.length - 1) setState(() => _stage++);
    });
  }

  @override
  void dispose() {
    _stageTimer?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width * 0.78;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        width: width,
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppTheme.accentCyan.withOpacity(0.25)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          AspectRatio(
            aspectRatio: 1,
            child: AnimatedBuilder(
              animation: _c,
              builder: (_, __) => CustomPaint(
                painter: _CanvasPainter(_c.value),
                child: Center(
                  child: Transform.scale(
                    scale: 1 + 0.08 * math.sin(_c.value * 2 * math.pi),
                    child: Container(
                      width: 62,
                      height: 62,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black.withOpacity(0.25),
                        boxShadow: [
                          BoxShadow(color: AppTheme.accentCyan.withOpacity(0.45), blurRadius: 28),
                        ],
                      ),
                      child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 30),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text('Creating your image',
                    style: GoogleFonts.spaceGrotesk(
                        color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
                const Spacer(),
                AnimatedBuilder(
                  animation: _c,
                  builder: (_, __) => Text('${_elapsed.elapsed.inSeconds}s',
                      style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 11)),
                ),
              ]),
              const SizedBox(height: 4),
              Text('“${widget.prompt}”',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 12, height: 1.35)),
              const SizedBox(height: 10),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Row(
                  key: ValueKey(_stage),
                  children: [
                    const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 1.6, color: AppTheme.accentCyan),
                    ),
                    const SizedBox(width: 8),
                    Text('${_stages[_stage]}…',
                        style: GoogleFonts.inter(color: AppTheme.accentCyan, fontSize: 11.5)),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: const LinearProgressIndicator(
                  minHeight: 3,
                  backgroundColor: Color(0x14FFFFFF),
                  valueColor: AlwaysStoppedAnimation(AppTheme.accentCyan),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Moving colour fields and a diagonal shimmer, like a picture forming.
class _CanvasPainter extends CustomPainter {
  _CanvasPainter(this.t);
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = const Color(0xFF0E1420));
    final a = t * 2 * math.pi;
    void blob(double cx, double cy, double r, Color color) {
      final center = Offset(size.width * cx, size.height * cy);
      canvas.drawCircle(
        center,
        size.shortestSide * r,
        Paint()
          ..shader = RadialGradient(colors: [color.withOpacity(0.55), color.withOpacity(0.0)])
              .createShader(Rect.fromCircle(center: center, radius: size.shortestSide * r)),
      );
    }

    blob(0.3 + 0.12 * math.cos(a), 0.35 + 0.1 * math.sin(a), 0.55, AppTheme.accentCyan);
    blob(0.72 + 0.1 * math.sin(a * 1.3), 0.6 + 0.12 * math.cos(a), 0.5, AppTheme.accentPurple);
    blob(0.5 + 0.15 * math.sin(a * 0.7), 0.85 + 0.05 * math.cos(a * 1.7), 0.4, const Color(0xFFFFC83D));

    // Shimmer band sweeping across.
    final x = (t * 1.6 - 0.3) * size.width;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white.withOpacity(0), Colors.white.withOpacity(0.10), Colors.white.withOpacity(0)],
          stops: const [0.35, 0.5, 0.65],
        ).createShader(Rect.fromLTWH(x - size.width, 0, size.width * 2, size.height)),
    );
  }

  @override
  bool shouldRepaint(_CanvasPainter old) => old.t != t;
}
