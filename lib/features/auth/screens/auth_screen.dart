// lib/features/auth/screens/auth_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:rive/rive.dart' hide LinearGradient, RadialGradient;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nova_x/core/services/api_service.dart';
import 'package:nova_x/core/theme/app_theme.dart';
import '../../legal/screens/terms_screen.dart';
import '../../legal/screens/privacy_screen.dart';
import '../../home/screens/home_screen.dart';
import '../../permissions/screens/permission_slides_screen.dart';
import 'forgot_password_screen.dart';
import 'otp_screen.dart';

class AuthScreen extends StatefulWidget {
  final bool showGuestOption;
  const AuthScreen({super.key, this.showGuestOption = true});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  bool _loading = false;
  bool _obscure  = true;
  bool _obscure2 = true;
  bool _obscure3 = true;
  String _error = '';
  bool _agreed  = false;

  // ── Text controllers ────────────────────────────────────────────────────────
  final _loginEmailCtrl = TextEditingController();
  final _loginPassCtrl  = TextEditingController();
  final _regNameCtrl    = TextEditingController();
  final _regEmailCtrl   = TextEditingController();
  final _regPassCtrl    = TextEditingController();
  final _regPass2Ctrl   = TextEditingController();

  // ── Focus nodes ─────────────────────────────────────────────────────────────
  final _loginEmailFocus = FocusNode();
  final _loginPassFocus  = FocusNode();
  final _regNameFocus    = FocusNode();
  final _regEmailFocus   = FocusNode();
  final _regPassFocus    = FocusNode();
  final _regPass2Focus   = FocusNode();

  // ── Rive state ──────────────────────────────────────────────────────────────
  Artboard? _riveArtboard;
  RiveAnimationController? _currentController;
  String _currentBearState = '';
  String _activePassField  = '';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _tabs.addListener(_onTabChange);

    _loginEmailFocus.addListener(_onLoginEmailFocus);
    _loginPassFocus.addListener(_onLoginPassFocus);
    _loginEmailCtrl.addListener(_onEmailTyped);
    _loginPassCtrl.addListener(_onPasswordTyped);

    _regNameFocus.addListener(_onRegNameFocus);
    _regEmailFocus.addListener(_onRegEmailFocus);
    _regPassFocus.addListener(_onRegPassFocus);
    _regPass2Focus.addListener(_onRegPass2Focus);
    _regEmailCtrl.addListener(_onEmailTyped);
    _regPassCtrl.addListener(_onPasswordTyped);
    _regPass2Ctrl.addListener(_onPasswordTyped);
  }

  // ── Permission-aware navigation ──────────────────────────────────────────────
  // Called after BOTH direct login success AND OTP verification success.
  // Checks whether permission slides have been shown before; if not, shows them.
  Future<void> _onAuthSuccess() async {
    final prefs = await SharedPreferences.getInstance();
    final permsDone = prefs.getBool('permissions_shown') ?? false;
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => permsDone
            ? const HomeScreen()
            : const PermissionSlidesScreen(),
        transitionDuration: const Duration(milliseconds: 450),
        transitionsBuilder: (_, anim, __, child) => FadeTransition(
          opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
          child: child,
        ),
      ),
      (route) => false,
    );
  }

  // ── Rive helpers ─────────────────────────────────────────────────────────────

  void _onRiveInit(Artboard artboard) {
    setState(() => _riveArtboard = artboard);
    _setAnimation('idle', loop: true);
  }

  void _setAnimation(String name, {bool loop = false, bool force = false}) {
    if (_riveArtboard == null) return;
    if (!force && _currentBearState == name) return;
    if (_currentController != null) {
      _riveArtboard!.removeController(_currentController!);
      _currentController = null;
    }
    _currentBearState = name;
    final ctrl = loop
        ? SimpleAnimation(name, autoplay: true) as RiveAnimationController
        : OneShotAnimation(name, autoplay: true) as RiveAnimationController;
    _currentController = ctrl;
    _riveArtboard!.addController(ctrl);
  }

  void _oneShotThenLoop(String oneShot, String fallback, {int delayMs = 900}) {
    _setAnimation(oneShot, loop: false, force: true);
    Future.delayed(Duration(milliseconds: delayMs), () {
      if (mounted) _setAnimation(fallback, loop: true, force: true);
    });
  }

  String get _restingState {
    final passVisible = !_isActivePassObscured && _activePassField.isNotEmpty;
    final hasText = _activePassCtrl?.text.isNotEmpty ?? false;
    if (passVisible && hasText) return 'hands_up';
    return 'idle';
  }

  bool get _isActivePassObscured {
    switch (_activePassField) {
      case 'login':    return _obscure;
      case 'regPass':  return _obscure2;
      case 'regPass2': return _obscure3;
      default:         return true;
    }
  }

  TextEditingController? get _activePassCtrl {
    switch (_activePassField) {
      case 'login':    return _loginPassCtrl;
      case 'regPass':  return _regPassCtrl;
      case 'regPass2': return _regPass2Ctrl;
      default:         return null;
    }
  }

  void _bearHandsUp() {
    if (_currentBearState != 'hands_up') _setAnimation('hands_up', loop: true);
  }

  void _reactFail({String? fallback}) {
    final after = fallback ?? _restingState;
    _setAnimation('fail', loop: false, force: true);
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) _setAnimation(after, loop: true, force: true);
    });
  }

  void _reactSuccess() {
    _oneShotThenLoop('success', 'idle', delayMs: 1800);
  }

  // ── Focus / typing reactions ──────────────────────────────────────────────────

  void _onTabChange() {
    setState(() => _error = '');
    _activePassField = '';
    _setAnimation('idle', loop: true, force: true);
  }

  void _onLoginEmailFocus() {
    if (_loginEmailFocus.hasFocus) {
      _activePassField = '';
      _setAnimation('look_idle', loop: true);
    } else if (!_loginPassFocus.hasFocus) {
      _setAnimation('idle', loop: true);
    }
  }

  void _onRegEmailFocus() {
    if (_regEmailFocus.hasFocus) {
      _activePassField = '';
      _setAnimation('look_idle', loop: true);
    } else if (!_regPassFocus.hasFocus && !_regPass2Focus.hasFocus &&
               !_regNameFocus.hasFocus) {
      _setAnimation('idle', loop: true);
    }
  }

  void _onRegNameFocus() {
    if (_regNameFocus.hasFocus) {
      _activePassField = '';
      _setAnimation('look_idle', loop: true);
    } else if (!_regEmailFocus.hasFocus && !_regPassFocus.hasFocus &&
               !_regPass2Focus.hasFocus) {
      _setAnimation('idle', loop: true);
    }
  }

  void _onEmailTyped() {
    final ctrl = _loginEmailFocus.hasFocus
        ? _loginEmailCtrl
        : (_regEmailFocus.hasFocus ? _regEmailCtrl : null);
    if (ctrl == null) return;
    final len = ctrl.text.length;
    if (len > 0 && len % 6 == 0) {
      _oneShotThenLoop('Look_down_left', 'look_idle', delayMs: 600);
    } else if (len > 0 && len % 3 == 0) {
      _oneShotThenLoop('Look_down_right', 'look_idle', delayMs: 600);
    }
  }

  void _onLoginPassFocus() {
    if (_loginPassFocus.hasFocus) {
      _activePassField = 'login';
      if (!_obscure) _bearHandsUp();
    } else {
      if (_obscure || _loginPassCtrl.text.isEmpty) {
        _activePassField = '';
        _oneShotThenLoop('hands_down', 'idle', delayMs: 900);
      }
    }
  }

  void _onRegPassFocus() {
    if (_regPassFocus.hasFocus) {
      _activePassField = 'regPass';
      if (!_obscure2) _bearHandsUp();
    } else {
      if (_obscure2 || _regPassCtrl.text.isEmpty) {
        if (!_regPass2Focus.hasFocus) {
          _activePassField = '';
          _oneShotThenLoop('hands_down', 'idle', delayMs: 900);
        }
      }
    }
  }

  void _onRegPass2Focus() {
    if (_regPass2Focus.hasFocus) {
      _activePassField = 'regPass2';
      if (!_obscure3) _bearHandsUp();
    } else {
      if (_obscure3 || _regPass2Ctrl.text.isEmpty) {
        if (!_regPassFocus.hasFocus) {
          _activePassField = '';
          _oneShotThenLoop('hands_down', 'idle', delayMs: 900);
        }
      }
    }
  }

  void _onPasswordTyped() {
    if (_activePassField.isEmpty) return;
    if (!_isActivePassObscured) _bearHandsUp();
  }

  // ── Eye toggles ───────────────────────────────────────────────────────────────

  void _toggleLoginPass() {
    setState(() => _obscure = !_obscure);
    if (_loginPassCtrl.text.isNotEmpty) {
      if (_obscure) {
        _oneShotThenLoop('hands_down', 'idle', delayMs: 700);
      } else {
        _bearHandsUp();
      }
    }
  }

  void _toggleRegPass() {
    setState(() => _obscure2 = !_obscure2);
    if (_regPassCtrl.text.isNotEmpty) {
      if (_obscure2) {
        _oneShotThenLoop('hands_down', 'idle', delayMs: 700);
      } else {
        _bearHandsUp();
      }
    }
  }

  void _toggleRegPass2() {
    setState(() => _obscure3 = !_obscure3);
    if (_regPass2Ctrl.text.isNotEmpty) {
      if (_obscure3) {
        _oneShotThenLoop('hands_down', 'idle', delayMs: 700);
      } else {
        _bearHandsUp();
      }
    }
  }

  // ── Auth actions ──────────────────────────────────────────────────────────────

  Future<void> _login() async {
    final email = _loginEmailCtrl.text.trim();
    final pass  = _loginPassCtrl.text;
    if (email.isEmpty || pass.isEmpty) {
      setState(() => _error = 'Please fill in all fields.');
      _reactFail(fallback: _restingState);
      return;
    }
    setState(() { _loading = true; _error = ''; });
    final res = await ApiService.login(email: email, password: pass);
    if (!mounted) return;
    setState(() => _loading = false);
    if (res['success'] == true) {
      HapticFeedback.lightImpact();
      _reactSuccess();
      await Future.delayed(const Duration(milliseconds: 600));
      if (!mounted) return;
      await _onAuthSuccess();          // ← permission-aware navigation
    } else if (res['needs_verification'] == true) {
      _reactFail(fallback: 'idle');
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => OtpScreen(
          userId: res['user_id'] as int? ?? 0,
          email:  email,
        ),
      ));
    } else {
      _reactFail(fallback: _restingState);
      setState(() => _error = res['message'] as String? ?? 'Login failed.');
    }
  }

  Future<void> _register() async {
    final name  = _regNameCtrl.text.trim();
    final email = _regEmailCtrl.text.trim();
    final pass  = _regPassCtrl.text;
    final pass2 = _regPass2Ctrl.text;
    if (!_agreed) {
      setState(() => _error = 'Please agree to the Terms of Service and Privacy Policy.');
      _reactFail(fallback: 'idle');
      return;
    }
    if (name.isEmpty || email.isEmpty || pass.isEmpty) {
      setState(() => _error = 'Please fill in all fields.');
      _reactFail(fallback: 'idle');
      return;
    }
    if (pass != pass2) {
      setState(() => _error = 'Passwords do not match.');
      _reactFail(fallback: _restingState);
      return;
    }
    if (pass.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters.');
      _reactFail(fallback: _restingState);
      return;
    }
    setState(() { _loading = true; _error = ''; });
    final res = await ApiService.register(
        username: name, email: email, password: pass);
    if (!mounted) return;
    setState(() => _loading = false);
    if (res['success'] == true) {
      HapticFeedback.lightImpact();
      _reactSuccess();
      await Future.delayed(const Duration(milliseconds: 600));
      if (!mounted) return;
      // Signup always goes to OTP first — permission slides fire after OTP verify
      Navigator.push(context, MaterialPageRoute(
        builder: (_) => OtpScreen(
          userId: res['user_id'] as int? ?? 0,
          email:  email,
        ),
      ));
    } else {
      _reactFail(fallback: 'idle');
      setState(() => _error = res['message'] as String? ?? 'Registration failed.');
    }
  }

  /// Reset by email code (ForgotPasswordScreen). When it returns without a
  /// session, the email is filled in here so the user can log in.
  Future<void> _openForgotPassword() async {
    FocusScope.of(context).unfocus();
    final email = await Navigator.push<String>(context, MaterialPageRoute(
      builder: (_) => ForgotPasswordScreen(initialEmail: _loginEmailCtrl.text.trim()),
    ));
    if (!mounted || email == null || email.isEmpty) return;
    setState(() {
      _loginEmailCtrl.text = email;
      _loginPassCtrl.clear();
      _error = '';
    });
  }

  void _continueAsGuest() => Navigator.pushReplacement(
      context, MaterialPageRoute(builder: (_) => const HomeScreen()));

  @override
  void dispose() {
    _tabs.dispose();
    _loginEmailCtrl.dispose(); _loginPassCtrl.dispose();
    _regNameCtrl.dispose();    _regEmailCtrl.dispose();
    _regPassCtrl.dispose();    _regPass2Ctrl.dispose();
    _loginEmailFocus.dispose(); _loginPassFocus.dispose();
    _regNameFocus.dispose();    _regEmailFocus.dispose();
    _regPassFocus.dispose();    _regPass2Focus.dispose();
    super.dispose();
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      body: Stack(children: [
        Positioned(top: -100, right: -100, child: Container(width: 300, height: 300,
          decoration: BoxDecoration(shape: BoxShape.circle,
            gradient: RadialGradient(colors: [
              AppTheme.accentCyan.withOpacity(0.15), Colors.transparent])))),
        Positioned(bottom: -80, left: -80, child: Container(width: 250, height: 250,
          decoration: BoxDecoration(shape: BoxShape.circle,
            gradient: RadialGradient(colors: [
              AppTheme.accentPurple.withOpacity(0.12), Colors.transparent])))),

        SafeArea(child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(children: [
            const SizedBox(height: 32),

            _buildBear(),

            ShaderMask(
              shaderCallback: (b) => AppTheme.primaryGradient.createShader(b),
              child: Text('NOVA X', style: GoogleFonts.spaceGrotesk(
                  color: Colors.white, fontSize: 32,
                  fontWeight: FontWeight.w900, letterSpacing: 4)),
            ),
            const SizedBox(height: 6),
            Text('Your browser. Your account. Everywhere.',
                style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 12),
                textAlign: TextAlign.center),
            const SizedBox(height: 28),

            Container(
              height: 48,
              decoration: BoxDecoration(
                color: AppTheme.bgCard,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.divider),
              ),
              child: TabBar(
                controller: _tabs,
                indicator: BoxDecoration(
                  gradient: AppTheme.primaryGradient,
                  borderRadius: BorderRadius.circular(12),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                indicatorPadding: const EdgeInsets.all(4),
                dividerColor: Colors.transparent,
                labelColor: Colors.white,
                unselectedLabelColor: AppTheme.textHint,
                labelStyle: GoogleFonts.spaceGrotesk(
                    fontSize: 14, fontWeight: FontWeight.w700),
                tabs: const [Tab(text: 'Log In'), Tab(text: 'Sign Up')],
              ),
            ),
            const SizedBox(height: 28),

            SizedBox(
              height: _tabs.index == 0 ? 160 : 336,
              child: TabBarView(controller: _tabs, children: [
                _loginForm(),
                _registerForm(),
              ]),
            ),

            if (_tabs.index == 0)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _loading ? null : _openForgotPassword,
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.accentCyan,
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                  ),
                  child: Text('Forgot password?',
                      style: GoogleFonts.inter(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                ),
              ),

            if (_error.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppTheme.danger.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.danger.withOpacity(0.3)),
                ),
                child: Row(children: [
                  const Icon(Icons.error_outline_rounded,
                      color: AppTheme.danger, size: 16),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_error, style: GoogleFonts.inter(
                      color: AppTheme.danger, fontSize: 12))),
                ]),
              ),
            ],

            const SizedBox(height: 20),

            GestureDetector(
              onTap: _loading ? null : (_tabs.index == 0 ? _login : _register),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: 54, width: double.infinity,
                decoration: BoxDecoration(
                  gradient: _loading ? null : AppTheme.primaryGradient,
                  color: _loading ? AppTheme.bgCard : null,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: _loading ? null : AppTheme.glowShadow,
                ),
                child: Center(child: _loading
                    ? const SizedBox(width: 24, height: 24,
                        child: CircularProgressIndicator(
                            color: AppTheme.accentCyan, strokeWidth: 2))
                    : Text(
                        _tabs.index == 0
                            ? 'Log In to NOVA X'
                            : 'Create Account — Free',
                        style: GoogleFonts.spaceGrotesk(
                            color: Colors.white, fontSize: 15,
                            fontWeight: FontWeight.w700))),
              ),
            ),

            if (_tabs.index == 1) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.accentCyan.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.accentCyan.withOpacity(0.2)),
                ),
                child: Row(children: [
                  const Icon(Icons.email_outlined,
                      color: AppTheme.accentCyan, size: 14),
                  const SizedBox(width: 8),
                  Expanded(child: Text(
                    'A 4-digit verification code will be sent to your email.',
                    style: GoogleFonts.inter(
                        color: AppTheme.accentCyan, fontSize: 11),
                  )),
                ]),
              ),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () => setState(() => _agreed = !_agreed),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 22, height: 22, margin: const EdgeInsets.only(top: 1),
                    decoration: BoxDecoration(
                      color: _agreed ? AppTheme.accentCyan : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: _agreed ? AppTheme.accentCyan : AppTheme.textHint,
                        width: 1.5,
                      ),
                    ),
                    child: _agreed
                        ? const Icon(Icons.check_rounded,
                            color: Colors.white, size: 14)
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text.rich(TextSpan(
                    style: GoogleFonts.inter(
                        color: AppTheme.textSecondary, fontSize: 12, height: 1.5),
                    children: [
                      const TextSpan(text: 'I have read and agree to the '),
                      WidgetSpan(child: GestureDetector(
                        onTap: () => Navigator.push(context,
                            MaterialPageRoute(builder: (_) => const TermsScreen())),
                        child: Text('Terms of Service',
                            style: GoogleFonts.inter(
                                color: AppTheme.accentCyan, fontSize: 12,
                                fontWeight: FontWeight.w700,
                                decoration: TextDecoration.underline,
                                decorationColor: AppTheme.accentCyan)),
                      )),
                      const TextSpan(text: ' and '),
                      WidgetSpan(child: GestureDetector(
                        onTap: () => Navigator.push(context,
                            MaterialPageRoute(builder: (_) => const PrivacyScreen())),
                        child: Text('Privacy Policy',
                            style: GoogleFonts.inter(
                                color: AppTheme.accentPurple, fontSize: 12,
                                fontWeight: FontWeight.w700,
                                decoration: TextDecoration.underline,
                                decorationColor: AppTheme.accentPurple)),
                      )),
                      const TextSpan(text: ' of NOVA X.'),
                    ],
                  ))),
                ]),
              ),
            ],

            if (widget.showGuestOption) ...[
              const SizedBox(height: 20),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Container(height: 1, width: 60, color: AppTheme.divider),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text('or', style: GoogleFonts.inter(
                      color: AppTheme.textHint, fontSize: 12)),
                ),
                Container(height: 1, width: 60, color: AppTheme.divider),
              ]),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: _continueAsGuest,
                child: Text('Continue as Guest',
                    style: GoogleFonts.inter(
                        color: AppTheme.accentCyan, fontSize: 13,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.underline,
                        decorationColor: AppTheme.accentCyan)),
              ),
            ],

            const SizedBox(height: 40),
          ]),
        )),
      ]),
    );
  }

  // ── Bear ──────────────────────────────────────────────────────────────────────

  Widget _buildBear() {
    return SizedBox(
      height: 180,
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (bounds) => const RadialGradient(
          center: Alignment.center,
          radius: 0.48,
          colors: [Colors.white, Colors.white, Colors.transparent],
          stops: [0.0, 0.72, 1.0],
        ).createShader(bounds),
        child: RiveAnimation.asset(
          'assets/bear.riv',
          fit: BoxFit.contain,
          onInit: _onRiveInit,
        ),
      ),
    );
  }

  // ── Forms ─────────────────────────────────────────────────────────────────────

  Widget _loginForm() => Column(children: [
    _field('Email address', _loginEmailCtrl,
        focusNode: _loginEmailFocus,
        icon: Icons.email_outlined,
        type: TextInputType.emailAddress),
    const SizedBox(height: 14),
    _field('Password', _loginPassCtrl,
        focusNode: _loginPassFocus,
        icon: Icons.lock_outline_rounded,
        obscure: _obscure,
        toggleObscure: _toggleLoginPass),
  ]);

  Widget _registerForm() => Column(children: [
    _field('Username (display name)', _regNameCtrl,
        focusNode: _regNameFocus,
        icon: Icons.person_outline_rounded),
    const SizedBox(height: 10),
    _field('Email address', _regEmailCtrl,
        focusNode: _regEmailFocus,
        icon: Icons.email_outlined,
        type: TextInputType.emailAddress),
    const SizedBox(height: 10),
    _field('Password (min 6 chars)', _regPassCtrl,
        focusNode: _regPassFocus,
        icon: Icons.lock_outline_rounded,
        obscure: _obscure2,
        toggleObscure: _toggleRegPass),
    const SizedBox(height: 10),
    _field('Confirm password', _regPass2Ctrl,
        focusNode: _regPass2Focus,
        icon: Icons.lock_outline_rounded,
        obscure: _obscure3,
        toggleObscure: _toggleRegPass2),
  ]);

  Widget _field(String hint, TextEditingController ctrl, {
    required FocusNode focusNode,
    required IconData icon,
    TextInputType type = TextInputType.text,
    bool obscure = false,
    VoidCallback? toggleObscure,
  }) =>
      TextField(
        controller: ctrl,
        focusNode: focusNode,
        keyboardType: type,
        obscureText: obscure,
        autocorrect: false,
        style: GoogleFonts.inter(color: AppTheme.textPrimary, fontSize: 14),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 14),
          prefixIcon: Icon(icon, color: AppTheme.textHint, size: 18),
          suffixIcon: toggleObscure != null
              ? IconButton(
                  icon: Icon(
                    obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    color: AppTheme.textHint, size: 18),
                  onPressed: toggleObscure)
              : null,
          filled: true,
          fillColor: AppTheme.bgCard,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppTheme.accentCyan, width: 1.5)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        ),
      );
}
