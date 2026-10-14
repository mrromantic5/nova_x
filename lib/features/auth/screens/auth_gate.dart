// lib/features/auth/screens/auth_gate.dart
//
// Boot sequence:
//   Splash (premium animated) → check onboarding_complete (SharedPrefs)
//   → OnboardingScreen  (first install / cleared data)
//   → AuthScreen        (returning, not logged in)
//   → HomeScreen        (returning, logged in)

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nova_x/core/services/api_service.dart';
import 'package:nova_x/core/theme/app_theme.dart';
import '../../home/screens/home_screen.dart';
import '../../onboarding/screens/onboarding_screen.dart';
import 'auth_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate>
    with TickerProviderStateMixin {

  // ── Animation controllers ──────────────────────────────────────────────────
  late final AnimationController _logoCtrl;      // logo scale + fade in
  late final AnimationController _ringCtrl;      // pulsing outer ring
  late final AnimationController _shimmerCtrl;   // text shimmer sweep
  late final AnimationController _particleCtrl;  // floating particles
  late final AnimationController _exitCtrl;      // exit scale + fade out

  // ── Logo animations ────────────────────────────────────────────────────────
  late final Animation<double> _logoScale;
  late final Animation<double> _logoOpacity;
  late final Animation<double> _logoY;           // slides up slightly on enter
  late final Animation<double> _taglineOpacity;

  // ── Ring animations ────────────────────────────────────────────────────────
  late final Animation<double> _ringScale;
  late final Animation<double> _ringOpacity;

  // ── Shimmer ────────────────────────────────────────────────────────────────
  late final Animation<double> _shimmerSlide;

  // ── Exit ───────────────────────────────────────────────────────────────────
  late final Animation<double> _exitScale;
  late final Animation<double> _exitOpacity;

  bool _navigationScheduled = false;

  @override
  void initState() {
    super.initState();

    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor:           Colors.transparent,
      statusBarIconBrightness:  Brightness.light,
    ));

    _setupAnimations();
    _startSequence();
  }

  void _setupAnimations() {
    // ── Logo: enters over 900 ms ─────────────────────────────────────────────
    _logoCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _logoScale = Tween(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _logoCtrl, curve: Curves.elasticOut),
    );
    _logoOpacity = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _logoCtrl,
        curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
      ),
    );
    _logoY = Tween(begin: 30.0, end: 0.0).animate(
      CurvedAnimation(parent: _logoCtrl, curve: Curves.easeOutCubic),
    );
    _taglineOpacity = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _logoCtrl,
        curve: const Interval(0.55, 1.0, curve: Curves.easeOut),
      ),
    );

    // ── Pulsing ring: loops forever ──────────────────────────────────────────
    _ringCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
    _ringScale = Tween(begin: 0.85, end: 1.45).animate(
      CurvedAnimation(parent: _ringCtrl, curve: Curves.easeOut),
    );
    _ringOpacity = Tween(begin: 0.55, end: 0.0).animate(
      CurvedAnimation(parent: _ringCtrl, curve: Curves.easeIn),
    );

    // ── Shimmer sweep across text: loops ────────────────────────────────────
    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
    _shimmerSlide = Tween(begin: -1.5, end: 2.5).animate(
      CurvedAnimation(parent: _shimmerCtrl, curve: Curves.easeInOut),
    );

    // ── Particles: loops ─────────────────────────────────────────────────────
    _particleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat();

    // ── Exit: plays once when leaving ────────────────────────────────────────
    _exitCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _exitScale = Tween(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _exitCtrl, curve: Curves.easeIn),
    );
    _exitOpacity = Tween(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _exitCtrl, curve: Curves.easeIn),
    );
  }

  Future<void> _startSequence() async {
    // Small settle before kicking off animations
    await Future.delayed(const Duration(milliseconds: 120));
    if (!mounted) return;

    // Logo entrance
    _logoCtrl.forward();

    // Start background checks after logo is mostly in
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    _check();
  }

  Future<void> _check() async {
    // Give logo time to fully settle + let user appreciate the splash
    await Future.delayed(const Duration(milliseconds: 1200));
    if (!mounted || _navigationScheduled) return;
    _navigationScheduled = true;

    final prefs = await SharedPreferences.getInstance();
    final onboardingDone = prefs.getBool('onboarding_complete') ?? false;

    Widget destination;
    if (!onboardingDone) {
      destination = const OnboardingScreen();
    } else {
      final loggedIn = await ApiService.isLoggedIn();
      destination = loggedIn ? const HomeScreen() : const AuthScreen();
    }

    if (!mounted) return;
    await _playExit();
    if (!mounted) return;
    _navigate(destination);
  }

  // Cinematic exit: scale up + fade out
  Future<void> _playExit() async {
    await _exitCtrl.forward();
  }

  void _navigate(Widget destination) {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder:        (_, __, ___) => destination,
        transitionDuration: const Duration(milliseconds: 500),
        transitionsBuilder: (_, anim, __, child) {
          return FadeTransition(
            opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
            child: ScaleTransition(
              scale: Tween(begin: 0.96, end: 1.0).animate(
                CurvedAnimation(parent: anim, curve: Curves.easeOut),
              ),
              child: child,
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _logoCtrl.dispose();
    _ringCtrl.dispose();
    _shimmerCtrl.dispose();
    _particleCtrl.dispose();
    _exitCtrl.dispose();
    super.dispose();
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      body: AnimatedBuilder(
        animation: Listenable.merge([
          _logoCtrl,
          _ringCtrl,
          _shimmerCtrl,
          _particleCtrl,
          _exitCtrl,
        ]),
        builder: (ctx, _) {
          return FadeTransition(
            opacity: _exitOpacity,
            child: ScaleTransition(
              scale: _exitScale,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // ── Deep background glow ─────────────────────────────────
                  _buildBackgroundGlow(size),

                  // ── Floating particles ───────────────────────────────────
                  _buildParticles(size),

                  // ── Pulsing rings ────────────────────────────────────────
                  _buildPulsingRings(),

                  // ── Logo + text centred ──────────────────────────────────
                  _buildLogoBlock(),

                  // ── Bottom loader bar ────────────────────────────────────
                  Positioned(
                    bottom: 60,
                    child: _buildLoaderBar(),
                  ),

                  // ── Version tag ──────────────────────────────────────────
                  Positioned(
                    bottom: 28,
                    child: Text(
                      'v3.1.3',
                      style: GoogleFonts.inter(
                        color:    Colors.white.withOpacity(0.2),
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Background radial glow ─────────────────────────────────────────────────
  Widget _buildBackgroundGlow(Size size) {
    return Container(
      width:  size.width,
      height: size.height,
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0, -0.2),
          radius: 0.75,
          colors: [
            AppTheme.accentCyan.withOpacity(0.13 * _logoOpacity.value),
            AppTheme.accentPurple.withOpacity(0.07 * _logoOpacity.value),
            AppTheme.bgDark,
          ],
          stops: const [0.0, 0.45, 1.0],
        ),
      ),
    );
  }

  // ── Floating particles ─────────────────────────────────────────────────────
  Widget _buildParticles(Size size) {
    return Opacity(
      opacity: _logoOpacity.value,
      child: CustomPaint(
        size: size,
        painter: _ParticlePainter(
          progress:    _particleCtrl.value,
          accentColor: AppTheme.accentCyan,
        ),
      ),
    );
  }

  // ── Two staggered pulsing rings behind logo ────────────────────────────────
  Widget _buildPulsingRings() {
    return Opacity(
      opacity: _logoOpacity.value,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer ring (offset by half cycle)
          Transform.scale(
            scale: _ringScale.value,
            child: Container(
              width:  180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppTheme.accentCyan
                      .withOpacity(_ringOpacity.value * 0.6),
                  width: 1.5,
                ),
              ),
            ),
          ),
          // Inner ring (half phase ahead)
          Transform.scale(
            scale: 0.7 + (_ringScale.value - 0.85) * 0.5,
            child: Container(
              width:  180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppTheme.accentPurple
                      .withOpacity(_ringOpacity.value * 0.45),
                  width: 1.0,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Logo + tagline block ───────────────────────────────────────────────────
  Widget _buildLogoBlock() {
    return Transform.translate(
      offset: Offset(0, _logoY.value),
      child: Opacity(
        opacity: _logoOpacity.value.clamp(0.0, 1.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── NOVA X with shimmer ──────────────────────────────────────
            Transform.scale(
              scale: _logoScale.value,
              child: _buildShimmerLogo(),
            ),
            const SizedBox(height: 12),

            // ── Tagline fades in after logo ──────────────────────────────
            Opacity(
              opacity: _taglineOpacity.value.clamp(0.0, 1.0),
              child: Text(
                'The Future of Browsing',
                style: GoogleFonts.inter(
                  color:         Colors.white.withOpacity(0.55),
                  fontSize:      14,
                  fontWeight:    FontWeight.w400,
                  letterSpacing: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Shimmer overlay on "NOVA X" text ──────────────────────────────────────
  Widget _buildShimmerLogo() {
    return Stack(
      children: [
        // Base gradient text
        ShaderMask(
          shaderCallback: (bounds) => AppTheme.primaryGradient.createShader(bounds),
          child: Text(
            'NOVA X',
            style: GoogleFonts.spaceGrotesk(
              color:         Colors.white,
              fontSize:      52,
              fontWeight:    FontWeight.w900,
              letterSpacing: 6,
            ),
          ),
        ),
        // Shimmer sweep on top
        ClipRect(
          child: ShaderMask(
            blendMode: BlendMode.srcATop,
            shaderCallback: (bounds) => LinearGradient(
              begin: Alignment.centerLeft,
              end:   Alignment.centerRight,
              colors: const [
                Colors.transparent,
                Colors.white,
                Colors.transparent,
              ],
              stops: const [0.0, 0.5, 1.0],
              transform: _SlidingGradientTransform(
                slidePercent: _shimmerSlide.value,
              ),
            ).createShader(bounds),
            child: Text(
              'NOVA X',
              style: GoogleFonts.spaceGrotesk(
                color:         Colors.white.withOpacity(0.38),
                fontSize:      52,
                fontWeight:    FontWeight.w900,
                letterSpacing: 6,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Animated loading bar ───────────────────────────────────────────────────
  Widget _buildLoaderBar() {
    return Opacity(
      opacity: _taglineOpacity.value.clamp(0.0, 1.0),
      child: Column(
        children: [
          SizedBox(
            width:  140,
            height: 2,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(1),
              child: LinearProgressIndicator(
                backgroundColor: Colors.white.withOpacity(0.08),
                valueColor: AlwaysStoppedAnimation<Color>(
                  AppTheme.accentCyan.withOpacity(0.85),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Loading...',
            style: GoogleFonts.inter(
              color:         Colors.white.withOpacity(0.28),
              fontSize:      11,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Gradient transform for shimmer sweep ──────────────────────────────────────
class _SlidingGradientTransform extends GradientTransform {
  final double slidePercent;
  const _SlidingGradientTransform({required this.slidePercent});

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(bounds.width * slidePercent, 0, 0);
  }
}

// ── Floating particles painter ────────────────────────────────────────────────
class _ParticlePainter extends CustomPainter {
  final double progress;
  final Color  accentColor;

  _ParticlePainter({required this.progress, required this.accentColor});

  // Fixed seed positions so particles don't jump on rebuild
  static const _seeds = [
    (0.12, 0.22, 0.0),  // (x%, y%, phase offset)
    (0.85, 0.18, 0.3),
    (0.25, 0.72, 0.1),
    (0.78, 0.68, 0.6),
    (0.50, 0.12, 0.45),
    (0.92, 0.45, 0.2),
    (0.08, 0.55, 0.75),
    (0.60, 0.85, 0.55),
    (0.38, 0.40, 0.85),
    (0.70, 0.30, 0.15),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    for (final (px, py, phase) in _seeds) {
      final t = ((progress + phase) % 1.0);
      // Each particle drifts up slightly and fades in/out
      final opacity = math.sin(t * math.pi).clamp(0.0, 1.0) * 0.55;
      final yOffset = -30.0 * t;
      final radius  = 1.5 + t * 1.5;

      canvas.drawCircle(
        Offset(size.width * px, size.height * py + yOffset),
        radius,
        Paint()..color = accentColor.withOpacity(opacity),
      );
    }
  }

  @override
  bool shouldRepaint(_ParticlePainter old) =>
      old.progress != progress;
}
