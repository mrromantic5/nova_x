// lib/features/onboarding/widgets/onboarding_slide_widget.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rive/rive.dart' hide LinearGradient, RadialGradient;
import '../models/onboarding_data.dart';

class OnboardingSlideWidget extends StatefulWidget {
  final OnboardingSlide slide;
  final double parallaxOffset; // value from AnimatedBuilder for parallax

  const OnboardingSlideWidget({
    super.key,
    required this.slide,
    this.parallaxOffset = 0.0,
  });

  @override
  State<OnboardingSlideWidget> createState() => _OnboardingSlideWidgetState();
}

class _OnboardingSlideWidgetState extends State<OnboardingSlideWidget> {
  // ── Rive state (only used on slide 1) ─────────────────────────────────────
  Artboard? _artboard;
  RiveAnimationController? _ctrl;

  @override
  void dispose() {
    if (_artboard != null && _ctrl != null) {
      _artboard!.removeController(_ctrl!);
    }
    super.dispose();
  }

  void _onRiveInit(Artboard artboard) {
    _artboard = artboard;
    // Play wave once, then settle into idle
    final wave = OneShotAnimation('wave', autoplay: true);
    _ctrl = wave;
    artboard.addController(wave);
    Future.delayed(const Duration(milliseconds: 1800), () {
      if (!mounted || _artboard == null) return;
      _artboard!.removeController(_ctrl!);
      final idle = SimpleAnimation('idle', autoplay: true);
      _ctrl = idle;
      _artboard!.addController(idle);
    });
  }

  // ── Hero builder ───────────────────────────────────────────────────────────
  Widget _buildHero() {
    if (widget.slide.heroType == SlideHeroType.rive) {
      return _buildRiveHero();
    }
    return _buildImageHero();
  }

  Widget _buildRiveHero() {
    return Transform.translate(
      offset: Offset(widget.parallaxOffset * -40, 0),
      child: SizedBox(
        height: 260,
        child: ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (bounds) => const RadialGradient(
            center: Alignment.center,
            radius: 0.50,
            colors: [Colors.white, Colors.white, Colors.transparent],
            stops:  [0.0, 0.68, 1.0],
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

  Widget _buildImageHero() {
    final shader = widget.slide.shaderType;
    return Transform.translate(
      offset: Offset(widget.parallaxOffset * -40, 0),
      child: SizedBox(
        height: 280,
        child: ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (bounds) {
            if (shader == ShaderType.linearBottom) {
              return const LinearGradient(
                begin: Alignment.topCenter,
                end:   Alignment.bottomCenter,
                colors: [Colors.white, Colors.white, Colors.transparent],
                stops:  [0.0, 0.62, 1.0],
              ).createShader(bounds);
            }
            // Default: radial — fades all edges
            return const RadialGradient(
              center: Alignment.center,
              radius: 0.52,
              colors: [Colors.white, Colors.white, Colors.transparent],
              stops:  [0.0, 0.60, 1.0],
            ).createShader(bounds);
          },
          child: Image.asset(
            widget.slide.assetPath!,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // ── Hero ──────────────────────────────────────────────────────────
        _buildHero(),

        const SizedBox(height: 40),

        // ── Headline ──────────────────────────────────────────────────────
        Transform.translate(
          offset: Offset(widget.parallaxOffset * -20, 0),
          child: ShaderMask(
            shaderCallback: (bounds) => LinearGradient(
              colors: [
                widget.slide.accentColor,
                Colors.white,
              ],
              begin: Alignment.topLeft,
              end:   Alignment.bottomRight,
            ).createShader(bounds),
            child: Text(
              widget.slide.headline,
              textAlign: TextAlign.center,
              style: GoogleFonts.spaceGrotesk(
                color:      Colors.white,
                fontSize:   28,
                fontWeight: FontWeight.w800,
                height:     1.2,
              ),
            ),
          ),
        ),

        const SizedBox(height: 16),

        // ── Subheadline ───────────────────────────────────────────────────
        Transform.translate(
          offset: Offset(widget.parallaxOffset * -10, 0),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              widget.slide.subheadline,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                color:      Colors.white.withOpacity(0.65),
                fontSize:   15,
                fontWeight: FontWeight.w400,
                height:     1.6,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
