// lib/features/permissions/screens/permission_slides_screen.dart
//
// Opera-style full-screen permission slides shown once after first login/signup.
// Slides: 1) Notifications  2) Microphone  3) Set as Default Browser
//
// NO external permission_handler dependency — uses only:
//   • firebase_messaging for notifications
//   • DefaultBrowserService (channel 'com.tlyfe.nova_x/default_browser')
//   • MethodChannel 'com.tlyfe.nova_x/permissions' for the microphone
// Both channels are implemented in android/.../MainActivity.kt.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nova_x/core/database/local_db.dart';
import 'package:nova_x/core/services/default_browser_service.dart';
import 'package:nova_x/core/theme/app_theme.dart';
import 'package:nova_x/features/home/screens/home_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Channel (implemented in MainActivity.kt)
// ─────────────────────────────────────────────────────────────────────────────
const _permChannel = MethodChannel('com.tlyfe.nova_x/permissions');

// ─────────────────────────────────────────────────────────────────────────────
// Slide data
// ─────────────────────────────────────────────────────────────────────────────
class _PermSlide {
  final String imagePath;
  final String title;
  final String body;
  final String primaryLabel;
  final Color  accentColor;

  const _PermSlide({
    required this.imagePath,
    required this.title,
    required this.body,
    required this.primaryLabel,
    required this.accentColor,
  });
}

const _slides = [
  _PermSlide(
    imagePath:    'assets/images/perm_notifications.png',
    title:        'Stay up to date',
    body:         'Enable notifications for AI responses,\nbrowsing alerts and the latest from NOVA X.',
    primaryLabel: 'Enable notifications',
    accentColor:  Color(0xFF00D4FF),
  ),
  _PermSlide(
    imagePath:    'assets/images/perm_microphone.png',
    title:        'Speak to browse',
    body:         'Allow microphone access to use voice\nsearch and hands-free Nova AI commands.',
    primaryLabel: 'Allow microphone',
    accentColor:  Color(0xFF7C3AED),
  ),
  _PermSlide(
    imagePath:    'assets/images/perm_default_browser.png',
    title:        'Always browse safely',
    body:         'Set NOVA X as your default browser to always\nprotect your data, block ads and save time.',
    primaryLabel: 'Set as default',
    accentColor:  Color(0xFF10B981),
  ),
];

// ─────────────────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────────────────
class PermissionSlidesScreen extends StatefulWidget {
  const PermissionSlidesScreen({super.key});

  @override
  State<PermissionSlidesScreen> createState() => _PermissionSlidesScreenState();
}

class _PermissionSlidesScreenState extends State<PermissionSlidesScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {

  static const _browserSlide = 2;

  final PageController _pageCtrl = PageController();
  int  _currentIndex = 0;
  bool _loading      = false;
  bool _finishing    = false;

  /// User tried "Set as default" but NOVA X is not the default yet.
  /// Shows "Try again" + a "Maybe later" link instead of trapping the user.
  bool _browserAttempted = false;

  late final List<AnimationController> _animCtrl;
  late final List<Animation<double>>   _fadeAnim;
  late final List<Animation<Offset>>   _slideAnim;

  @override
  void initState() {
    super.initState();

    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor:          Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));

    _animCtrl = List.generate(_slides.length, (i) => AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    ));
    _fadeAnim = _animCtrl.map((c) =>
        CurvedAnimation(parent: c, curve: Curves.easeOut)
    ).toList();
    _slideAnim = _animCtrl.map((c) =>
        Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero)
            .animate(CurvedAnimation(parent: c, curve: Curves.easeOut))
    ).toList();

    _animCtrl[0].forward();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageCtrl.dispose();
    for (final c in _animCtrl) c.dispose();
    super.dispose();
  }

  // ── Navigation ─────────────────────────────────────────────────────────────
  void _advance() {
    if (_currentIndex < _slides.length - 1) {
      _pageCtrl.nextPage(
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeInOut,
      );
    } else {
      _finish();
    }
  }

  // Android 7–9 open the Settings app instead of a dialog; when the user
  // comes back, re-check and continue automatically if it worked.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _currentIndex == _browserSlide && _browserAttempted && !_loading) {
      _onReturnedFromSettings();
    }
  }

  Future<void> _onReturnedFromSettings() async {
    if (await DefaultBrowserService.checkAndAward()) _finish();
  }

  Future<void> _finish() async {
    if (_finishing) return;
    _finishing = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('permissions_shown', true);
    // These slides already asked about the default browser — don't show the
    // home screen's "Make NOVA X your browser?" popup straight after.
    await LocalDB.setAskedDefaultBrowser(true);
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const HomeScreen(),
        transitionDuration: const Duration(milliseconds: 500),
        transitionsBuilder: (_, anim, __, child) => FadeTransition(
          opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
          child: child,
        ),
      ),
      (route) => false,
    );
  }

  // ── Permission handlers — zero external packages ───────────────────────────
  Future<void> _handlePrimary(int index) async {
    if (_loading) return;

    // Default browser: stay on the slide until the system dialog is answered.
    if (index == _browserSlide) {
      await _setDefaultBrowser();
      return;
    }

    setState(() => _loading = true);
    try {
      switch (index) {
        case 0: await _requestNotifications(); break;
        case 1: await _requestMicrophone();    break;
      }
    } catch (_) {
      // Never block the user — if permission call fails just advance
    } finally {
      if (mounted) setState(() => _loading = false);
      _advance();
    }
  }

  // Slide 1 — Notifications via firebase_messaging (already in pubspec)
  Future<void> _requestNotifications() async {
    await FirebaseMessaging.instance.requestPermission(
      alert:         true,
      badge:         true,
      sound:         true,
      announcement:  false,
      carPlay:       false,
      criticalAlert: false,
      provisional:   false,
    );
  }

  // Slide 2 — Microphone via native MethodChannel (no permission_handler needed)
  // Add the handler to MainActivity.kt — snippet is in the file header above.
  Future<void> _requestMicrophone() async {
    try {
      await _permChannel.invokeMethod('requestMicrophone');
    } on MissingPluginException {
      // Channel not yet wired in MainActivity — safe to ignore, advance anyway
    }
  }

  // Slide 3 — Default browser.
  // Android 10+: request() completes only after the user answers the system
  // dialog. If NOVA X became the default we continue automatically; otherwise
  // the user can try again or choose "Maybe later".
  Future<void> _setDefaultBrowser() async {
    setState(() => _loading = true);
    bool isDefault = false;
    try {
      isDefault = await DefaultBrowserService.request();
    } catch (_) {
      isDefault = false;
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      _browserAttempted = !isDefault;
    });
    if (isDefault) _finish();
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageCtrl,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _slides.length,
            onPageChanged: (i) {
              setState(() => _currentIndex = i);
              _animCtrl[i].forward(from: 0);
            },
            itemBuilder: (_, i) => _SlidePage(
              slide:     _slides[i],
              fadeAnim:  _fadeAnim[i],
              slideAnim: _slideAnim[i],
            ),
          ),

          // Skip button
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 20, top: 12),
                child: TextButton(
                  onPressed: _loading ? null : _finish,
                  child: Text(
                    'Skip',
                    style: GoogleFonts.inter(
                      color:      Colors.white.withOpacity(0.55),
                      fontSize:   15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Bottom bar
          Positioned(
            left:   0,
            right:  0,
            bottom: 0,
            child:  _BottomBar(
              slides:       _slides,
              currentIndex: _currentIndex,
              loading:      _loading,
              browserAttempted: _browserAttempted,
              onPrimary:    () => _handlePrimary(_currentIndex),
              onSkip:       _advance,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Slide page
// ─────────────────────────────────────────────────────────────────────────────
class _SlidePage extends StatelessWidget {
  final _PermSlide        slide;
  final Animation<double> fadeAnim;
  final Animation<Offset> slideAnim;

  const _SlidePage({
    required this.slide,
    required this.fadeAnim,
    required this.slideAnim,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Hero image — top 55%, fades out at bottom edge
        Expanded(
          flex: 55,
          child: ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (bounds) => const LinearGradient(
              begin:  Alignment.topCenter,
              end:    Alignment.bottomCenter,
              stops:  [0.0, 0.65, 1.0],
              colors: [Colors.white, Colors.white, Colors.transparent],
            ).createShader(bounds),
            child: Image.asset(
              slide.imagePath,
              fit: BoxFit.contain,
              width: double.infinity,
            ),
          ),
        ),

        // Text content — bottom 45%, animates in
        Expanded(
          flex: 45,
          child: FadeTransition(
            opacity: fadeAnim,
            child: SlideTransition(
              position: slideAnim,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    Text(
                      slide.title,
                      style: GoogleFonts.spaceGrotesk(
                        color:      Colors.white,
                        fontSize:   30,
                        fontWeight: FontWeight.w800,
                        height:     1.15,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      slide.body,
                      style: GoogleFonts.inter(
                        color:      Colors.white.withOpacity(0.60),
                        fontSize:   15,
                        fontWeight: FontWeight.w400,
                        height:     1.65,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bottom bar: dots + button
// ─────────────────────────────────────────────────────────────────────────────
class _BottomBar extends StatelessWidget {
  final List<_PermSlide> slides;
  final int              currentIndex;
  final bool             loading;
  final bool             browserAttempted;
  final VoidCallback     onPrimary;
  final VoidCallback     onSkip;

  const _BottomBar({
    required this.slides,
    required this.currentIndex,
    required this.loading,
    required this.browserAttempted,
    required this.onPrimary,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    final accent = slides[currentIndex].accentColor;
    final isLast = currentIndex == slides.length - 1;
    final retry  = isLast && browserAttempted;
    final label  = retry ? 'Try again' : slides[currentIndex].primaryLabel;

    return Container(
      padding: EdgeInsets.only(
        left:   24,
        right:  24,
        top:    16,
        bottom: MediaQuery.of(context).padding.bottom + 24,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin:  Alignment.topCenter,
          end:    Alignment.bottomCenter,
          stops:  const [0.0, 0.25, 1.0],
          colors: [
            AppTheme.bgDark.withOpacity(0),
            AppTheme.bgDark,
            AppTheme.bgDark,
          ],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Animated pagination dots
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(slides.length, (i) {
              final active = i == currentIndex;
              return AnimatedContainer(
                duration:   const Duration(milliseconds: 280),
                curve:      Curves.easeInOut,
                margin:     const EdgeInsets.symmetric(horizontal: 4),
                width:      active ? 24 : 7,
                height:     7,
                decoration: BoxDecoration(
                  color: active
                      ? slides[currentIndex].accentColor
                      : Colors.white.withOpacity(0.22),
                  borderRadius: BorderRadius.circular(4),
                ),
              );
            }),
          ),

          const SizedBox(height: 22),

          // Primary button
          SizedBox(
            width:  double.infinity,
            height: 56,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [accent, Color.lerp(accent, Colors.white, 0.15)!],
                  begin:  Alignment.centerLeft,
                  end:    Alignment.centerRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color:      accent.withOpacity(0.35),
                    blurRadius: 20,
                    offset:     const Offset(0, 6),
                  ),
                ],
              ),
              child: Material(
                color:        Colors.transparent,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: loading ? null : onPrimary,
                  child: Center(
                    child: loading
                        ? const SizedBox(
                            width:  22,
                            height: 22,
                            child:  CircularProgressIndicator(
                              color:       Colors.white,
                              strokeWidth: 2.5,
                            ),
                          )
                        : Text(
                            label,
                            style: GoogleFonts.spaceGrotesk(
                              color:         Colors.white,
                              fontSize:      16,
                              fontWeight:    FontWeight.w700,
                              letterSpacing: 0.3,
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ),

          if (!isLast || retry) ...[
            const SizedBox(height: 14),
            GestureDetector(
              onTap: loading ? null : onSkip,
              child: Text(
                retry ? 'Maybe later' : 'Not now',
                style: GoogleFonts.inter(
                  color:      Colors.white.withOpacity(0.40),
                  fontSize:   14,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
