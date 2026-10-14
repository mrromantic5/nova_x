// lib/features/onboarding/screens/onboarding_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nova_x/core/theme/app_theme.dart';
import '../../auth/screens/auth_screen.dart';
import '../models/onboarding_data.dart';
import '../widgets/onboarding_slide_widget.dart';
import '../widgets/page_indicator.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with SingleTickerProviderStateMixin {
  final PageController _pageCtrl = PageController();
  int _currentPage = 0;
  bool _isAnimating = false;

  static const _slides = kOnboardingSlides;
  static const _lastIndex = kOnboardingSlides.length - 1;

  // ── Complete onboarding and go to auth ─────────────────────────────────────
  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_complete', true);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const AuthScreen(),
        transitionsBuilder: (_, anim, __, child) {
          return FadeTransition(
            opacity: anim,
            child: ScaleTransition(
              scale: Tween(begin: 0.95, end: 1.0).animate(
                CurvedAnimation(parent: anim, curve: Curves.easeOut),
              ),
              child: child,
            ),
          );
        },
        transitionDuration: const Duration(milliseconds: 500),
      ),
    );
  }

  // ── Navigate forward ───────────────────────────────────────────────────────
  void _next() {
    if (_isAnimating) return;
    if (_currentPage == _lastIndex) {
      _finish();
      return;
    }
    _pageCtrl.nextPage(
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeInOutCubic,
    );
  }

  // ── Navigate backward ──────────────────────────────────────────────────────
  void _prev() {
    if (_isAnimating || _currentPage == 0) return;
    _pageCtrl.previousPage(
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeInOutCubic,
    );
  }

  // ── Skip to last slide ─────────────────────────────────────────────────────
  void _skip() {
    _pageCtrl.animateToPage(
      _lastIndex,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOutCubic,
    );
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  // ── Accent colour for current slide ───────────────────────────────────────
  Color get _accent => _slides[_currentPage].accentColor;

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor:      Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));

    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      body: Stack(
        children: [
          // ── Ambient glow that shifts with accent colour ─────────────────
          _buildAmbientGlow(),

          // ── Main content ────────────────────────────────────────────────
          SafeArea(
            child: Column(
              children: [
                // Skip button row
                _buildTopBar(),

                // Page slides
                Expanded(
                  child: AnimatedBuilder(
                    animation: _pageCtrl,
                    builder: (ctx, _) {
                      return PageView.builder(
                        controller: _pageCtrl,
                        physics: const BouncingScrollPhysics(),
                        onPageChanged: (i) {
                          setState(() => _currentPage = i);
                          HapticFeedback.selectionClick();
                        },
                        itemCount: _slides.length,
                        itemBuilder: (ctx, index) {
                          // Compute parallax offset
                          double offset = 0;
                          if (_pageCtrl.hasClients &&
                              _pageCtrl.page != null) {
                            offset = (_pageCtrl.page! - index).clamp(-1.0, 1.0);
                          }
                          return OnboardingSlideWidget(
                            key: ValueKey(index),
                            slide: _slides[index],
                            parallaxOffset: offset,
                          );
                        },
                      );
                    },
                  ),
                ),

                // Bottom controls
                _buildBottomControls(),

                const SizedBox(height: 32),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Ambient glow background ────────────────────────────────────────────────
  Widget _buildAmbientGlow() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0, -0.3),
          radius: 0.85,
          colors: [
            _accent.withOpacity(0.12),
            AppTheme.bgDark,
          ],
        ),
      ),
    );
  }

  // ── Top bar: Skip ──────────────────────────────────────────────────────────
  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // NOVA X logo mark
          ShaderMask(
            shaderCallback: (b) => AppTheme.primaryGradient.createShader(b),
            child: Text(
              'NOVA X',
              style: GoogleFonts.spaceGrotesk(
                color:      Colors.white,
                fontSize:   18,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
              ),
            ),
          ),

          // Skip button — hidden on last slide
          AnimatedOpacity(
            opacity: _currentPage < _lastIndex ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 300),
            child: TextButton(
              onPressed: _currentPage < _lastIndex ? _skip : null,
              style: TextButton.styleFrom(
                foregroundColor: Colors.white54,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              ),
              child: Text(
                'Skip',
                style: GoogleFonts.inter(
                  fontSize:   14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Bottom controls: Prev | Dots | Next / Get Started ─────────────────────
  Widget _buildBottomControls() {
    final isLast = _currentPage == _lastIndex;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // ── Prev button ────────────────────────────────────────────────
          AnimatedOpacity(
            opacity: _currentPage > 0 ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 300),
            child: _CircleNavButton(
              icon: Icons.arrow_back_ios_new_rounded,
              onTap: _currentPage > 0 ? _prev : null,
              color: Colors.white24,
            ),
          ),

          // ── Page dots ─────────────────────────────────────────────────
          PageIndicator(
            count:       _slides.length,
            current:     _currentPage,
            activeColor: _accent,
          ),

          // ── Next / Get Started ─────────────────────────────────────────
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (child, anim) => ScaleTransition(
              scale: anim,
              child: FadeTransition(opacity: anim, child: child),
            ),
            child: isLast
                ? _GetStartedButton(
                    key: const ValueKey('getstarted'),
                    accent: _accent,
                    onTap: _finish,
                  )
                : _CircleNavButton(
                    key: const ValueKey('next'),
                    icon: Icons.arrow_forward_ios_rounded,
                    onTap: _next,
                    color: _accent,
                    glowing: true,
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Circular nav button (prev / next) ─────────────────────────────────────────
class _CircleNavButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final Color color;
  final bool glowing;
  const _CircleNavButton({
    super.key,
    required this.icon,
    this.onTap,
    required this.color,
    this.glowing = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withOpacity(glowing ? 1.0 : 0.18),
          boxShadow: glowing
              ? [BoxShadow(color: color.withOpacity(0.4), blurRadius: 16, spreadRadius: 2)]
              : null,
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}

// ── Get Started pill button ────────────────────────────────────────────────────
class _GetStartedButton extends StatelessWidget {
  final Color accent;
  final VoidCallback onTap;

  const _GetStartedButton({
    super.key,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [accent, accent.withOpacity(0.7)],
            begin: Alignment.topLeft,
            end:   Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(32),
          boxShadow: [
            BoxShadow(
              color:      accent.withOpacity(0.45),
              blurRadius: 20,
              spreadRadius: 1,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Text(
          'Get Started',
          style: GoogleFonts.spaceGrotesk(
            color:      Colors.white,
            fontSize:   15,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}
