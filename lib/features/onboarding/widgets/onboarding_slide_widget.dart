// lib/features/onboarding/widgets/onboarding_slide_widget.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rive/rive.dart' hide LinearGradient, RadialGradient, Image;
import 'package:nova_x/core/theme/app_theme.dart';
import '../models/onboarding_data.dart';

class OnboardingSlideWidget extends StatefulWidget {
  final OnboardingSlide slide;
  final double parallaxOffset;

  const OnboardingSlideWidget({
    super.key,
    required this.slide,
    this.parallaxOffset = 0.0,
  });

  @override
  State<OnboardingSlideWidget> createState() => _OnboardingSlideWidgetState();
}

class _OnboardingSlideWidgetState extends State<OnboardingSlideWidget>
    with SingleTickerProviderStateMixin {

  // ── Rive state ─────────────────────────────────────────────────────────────
  Artboard? _artboard;
  RiveAnimationController? _ctrl;
  bool _waveStarted = false;

  // ── Glow pulse (bear slide only) ───────────────────────────────────────────
  late final AnimationController _glowCtrl;
  late final Animation<double> _glowAnim;

  @override
  void initState() {
    super.initState();
    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
    _glowAnim = Tween(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _glowCtrl, curve: Curves.easeInOut),
    );
    if (widget.slide.heroType == SlideHeroType.rive) {
      _glowCtrl.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _glowCtrl.dispose();
    if (_artboard != null && _ctrl != null) {
      try { _artboard!.removeController(_ctrl!); } catch (_) {}
    }
    super.dispose();
  }

  void _onRiveInit(Artboard artboard) {
    _artboard = artboard;
    if (_waveStarted) return;
    _waveStarted = true;

    // Try every capitalisation variant — Rive names are case-sensitive
    const waveNames = ['Wave', 'wave', 'Waving', 'waving', 'WAVE'];
    bool waveFound = false;

    for (final name in waveNames) {
      try {
        final wave = OneShotAnimation(name, autoplay: true);
        _ctrl = wave;
        artboard.addController(wave);
        waveFound = true;
        break;
      } catch (_) {}
    }

    // After wave duration, switch to idle
    final waitMs = waveFound ? 2200 : 100;
    Future.delayed(Duration(milliseconds: waitMs), () {
      if (!mounted || _artboard == null) return;
      if (_ctrl != null) {
        try { _artboard!.removeController(_ctrl!); } catch (_) {}
      }
      const idleNames = ['idle', 'Idle', 'IDLE', 'walk', 'Walk'];
      for (final name in idleNames) {
        try {
          final idle = SimpleAnimation(name, autoplay: true);
          _ctrl = idle;
          _artboard!.addController(idle);
          break;
        } catch (_) {}
      }
    });
  }

  // ── Hero dispatcher ────────────────────────────────────────────────────────
  Widget _buildHero() {
    return widget.slide.heroType == SlideHeroType.rive
        ? _buildRiveHero()
        : _buildImageHero();
  }

  // ── Bear hero ──────────────────────────────────────────────────────────────
  // Radial ShaderMask dissolves the square edges of the Rive artboard into the
  // dark background, keeping the white circle + bear fully visible at centre.
  // radius 0.50 fills to the shorter axis, stops [0, 0.80, 1.0] means the
  // inner 80% is fully opaque — the bear + white circle stay intact — and only
  // the outermost 20% ring fades out, removing the hard square corners.
  Widget _buildRiveHero() {
    return Transform.translate(
      offset: Offset(widget.parallaxOffset * -40, 0),
      child: SizedBox(
        width: 300,
        height: 300,
        child: ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (bounds) => const RadialGradient(
            center: Alignment.center,
            radius: 0.50,
            colors: [Colors.white, Colors.white, Colors.transparent],
            stops: [0.0, 0.80, 1.0],
          ).createShader(bounds),
          child: RiveAnimation.asset(
            widget.slide.riveAsset!,
            fit: BoxFit.contain,
            onInit: _onRiveInit,
          ),
        ),
      ),
    );
  }

  // ── Image hero: radial round fade on ALL image slides ─────────────────────
  Widget _buildImageHero() {
    return Transform.translate(
      offset: Offset(widget.parallaxOffset * -40, 0),
      child: SizedBox(
        height: 300,
        child: ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (bounds) => const RadialGradient(
            center: Alignment.center,
            radius: 0.50,
            colors: [Colors.white, Colors.white, Colors.transparent],
            stops: [0.0, 0.72, 1.0],
          ).createShader(bounds),
          child: Image.asset(
            widget.slide.assetPath!,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }

  // ── Main build ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildHero(),

        const SizedBox(height: 40),

        // Headline with accent→white gradient
        Transform.translate(
          offset: Offset(widget.parallaxOffset * -20, 0),
          child: ShaderMask(
            shaderCallback: (bounds) => LinearGradient(
              colors: [widget.slide.accentColor, Colors.white],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ).createShader(bounds),
            child: Text(
              widget.slide.headline,
              textAlign: TextAlign.center,
              style: GoogleFonts.spaceGrotesk(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w800,
                height: 1.2,
              ),
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Subheadline
        Transform.translate(
          offset: Offset(widget.parallaxOffset * -10, 0),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              widget.slide.subheadline,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                color: Colors.white.withOpacity(0.65),
                fontSize: 15,
                fontWeight: FontWeight.w400,
                height: 1.6,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
