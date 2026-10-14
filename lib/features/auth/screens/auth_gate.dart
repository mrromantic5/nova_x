// lib/features/auth/screens/auth_gate.dart
//
// Boot sequence:
//   Splash (logo + spinner) → check onboarding_complete (SharedPrefs)
//   → OnboardingScreen  (first install / cleared data)
//   → AuthScreen        (returning user, not logged in)
//   → HomeScreen        (returning user, logged in)

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
    with SingleTickerProviderStateMixin {

  late final AnimationController _fadeCtrl;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();

    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor:          Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));

    // Logo fades in over 600 ms
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();

    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);

    _check();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    // Let splash render and logo fade in
    await Future.delayed(const Duration(milliseconds: 1400));
    if (!mounted) return;

    // ── Step 1: Has the user seen onboarding? ─────────────────────────────
    final prefs = await SharedPreferences.getInstance();
    final onboardingDone = prefs.getBool('onboarding_complete') ?? false;
    if (!mounted) return;

    Widget destination;
    if (!onboardingDone) {
      destination = const OnboardingScreen();
    } else {
      final loggedIn = await ApiService.isLoggedIn();
      destination = loggedIn ? const HomeScreen() : const AuthScreen();
    }

    if (!mounted) return;
    _navigate(destination);
  }

  void _navigate(Widget destination) {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => destination,
        transitionDuration: const Duration(milliseconds: 500),
        transitionsBuilder: (_, anim, __, child) => FadeTransition(
          opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── NOVA X gradient logo ─────────────────────────────────────
              ShaderMask(
                shaderCallback: (b) => AppTheme.primaryGradient.createShader(b),
                child: Text(
                  'NOVA X',
                  style: GoogleFonts.spaceGrotesk(
                    color:         Colors.white,
                    fontSize:      44,
                    fontWeight:    FontWeight.w900,
                    letterSpacing: 5,
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // ── Tagline ──────────────────────────────────────────────────
              Text(
                'The Future of Browsing',
                style: GoogleFonts.inter(
                  color:         Colors.white.withOpacity(0.45),
                  fontSize:      13,
                  fontWeight:    FontWeight.w400,
                  letterSpacing: 1.8,
                ),
              ),

              const SizedBox(height: 56),

              // ── Spinner ──────────────────────────────────────────────────
              SizedBox(
                width:  24,
                height: 24,
                child: CircularProgressIndicator(
                  color:       AppTheme.accentCyan,
                  strokeWidth: 2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
