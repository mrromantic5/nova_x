// lib/features/auth/screens/auth_screen.dart
//
// NOVA X — premium SaaS-grade login / sign-up screen.
// On success → navigates to HomeScreen.
// "Continue as Guest" → navigates to HomeScreen without a token.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nova_x/core/services/api_service.dart';
import 'package:nova_x/core/theme/app_theme.dart';
import '../../home/screens/home_screen.dart';

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
  bool _obscurePass  = true;
  bool _obscurePass2 = true;
  String _error = '';

  // Login
  final _loginEmailCtrl = TextEditingController();
  final _loginPassCtrl  = TextEditingController();

  // Register
  final _regNameCtrl  = TextEditingController();
  final _regEmailCtrl = TextEditingController();
  final _regPassCtrl  = TextEditingController();
  final _regPass2Ctrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _tabs.addListener(() => setState(() => _error = ''));
  }

  @override
  void dispose() {
    _tabs.dispose();
    _loginEmailCtrl.dispose(); _loginPassCtrl.dispose();
    _regNameCtrl.dispose();    _regEmailCtrl.dispose();
    _regPassCtrl.dispose();    _regPass2Ctrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final email = _loginEmailCtrl.text.trim();
    final pass  = _loginPassCtrl.text;
    if (email.isEmpty || pass.isEmpty) {
      setState(() => _error = 'Please fill in all fields.');
      return;
    }
    setState(() { _loading = true; _error = ''; });
    final res = await ApiService.login(email: email, password: pass);
    if (!mounted) return;
    setState(() => _loading = false);
    if (res['success'] == true) {
      HapticFeedback.lightImpact();
      Navigator.pushReplacement(context,
          MaterialPageRoute(builder: (_) => const HomeScreen()));
    } else {
      setState(() => _error = res['message'] as String? ?? 'Login failed.');
    }
  }

  Future<void> _register() async {
    final name  = _regNameCtrl.text.trim();
    final email = _regEmailCtrl.text.trim();
    final pass  = _regPassCtrl.text;
    final pass2 = _regPass2Ctrl.text;
    if (name.isEmpty || email.isEmpty || pass.isEmpty) {
      setState(() => _error = 'Please fill in all fields.');
      return;
    }
    if (pass != pass2) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }
    if (pass.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters.');
      return;
    }
    setState(() { _loading = true; _error = ''; });
    final res = await ApiService.register(
        username: name, email: email, password: pass);
    if (!mounted) return;
    setState(() => _loading = false);
    if (res['success'] == true) {
      HapticFeedback.lightImpact();
      Navigator.pushReplacement(context,
          MaterialPageRoute(builder: (_) => const HomeScreen()));
    } else {
      setState(() => _error = res['message'] as String? ?? 'Registration failed.');
    }
  }

  void _continueAsGuest() {
    Navigator.pushReplacement(context,
        MaterialPageRoute(builder: (_) => const HomeScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      body: Stack(children: [
        // Background gradient orbs
        Positioned(top: -100, right: -100, child: Container(
          width: 300, height: 300,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [
              AppTheme.accentCyan.withOpacity(0.15), Colors.transparent]),
          ),
        )),
        Positioned(bottom: -80, left: -80, child: Container(
          width: 250, height: 250,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [
              AppTheme.accentPurple.withOpacity(0.12), Colors.transparent]),
          ),
        )),

        SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(children: [
              const SizedBox(height: 48),

              // Logo + branding
              Container(
                width: 72, height: 72,
                decoration: BoxDecoration(
                  gradient: AppTheme.primaryGradient,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: AppTheme.glowShadow,
                ),
                child: const Icon(Icons.public_rounded, color: Colors.white, size: 36),
              ),
              const SizedBox(height: 16),
              ShaderMask(
                shaderCallback: (b) => AppTheme.primaryGradient.createShader(b),
                child: Text('NOVA X', style: GoogleFonts.spaceGrotesk(
                    color: Colors.white, fontSize: 32,
                    fontWeight: FontWeight.w900, letterSpacing: 4)),
              ),
              const SizedBox(height: 6),
              Text('Your account, everywhere.',
                  style: GoogleFonts.inter(
                      color: AppTheme.textHint, fontSize: 13)),

              const SizedBox(height: 36),

              // Tab bar
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
                    gradient:     AppTheme.primaryGradient,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  indicatorPadding: const EdgeInsets.all(4),
                  dividerColor: Colors.transparent,
                  labelColor:      Colors.white,
                  unselectedLabelColor: AppTheme.textHint,
                  labelStyle: GoogleFonts.spaceGrotesk(
                      fontSize: 14, fontWeight: FontWeight.w700),
                  tabs: const [
                    Tab(text: 'Log In'),
                    Tab(text: 'Sign Up'),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              // Tab content
              SizedBox(
                height: 320,
                child: TabBarView(controller: _tabs, children: [
                  _buildLoginForm(),
                  _buildRegisterForm(),
                ]),
              ),

              // Error
              if (_error.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppTheme.danger.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: AppTheme.danger.withOpacity(0.3)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.error_outline_rounded,
                        color: AppTheme.danger, size: 16),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_error,
                        style: GoogleFonts.inter(
                            color: AppTheme.danger, fontSize: 12))),
                  ]),
                ),
              ],

              const SizedBox(height: 20),

              // Submit button
              GestureDetector(
                onTap: _loading ? null : (_tabs.index == 0 ? _login : _register),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 54,
                  decoration: BoxDecoration(
                    gradient: _loading ? null : AppTheme.primaryGradient,
                    color:    _loading ? AppTheme.bgCard : null,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: _loading ? null : AppTheme.glowShadow,
                  ),
                  child: Center(
                    child: _loading
                        ? const SizedBox(width: 24, height: 24,
                            child: CircularProgressIndicator(
                                color: AppTheme.accentCyan, strokeWidth: 2))
                        : Text(
                            _tabs.index == 0 ? 'Log In to NOVA X' : 'Create Account',
                            style: GoogleFonts.spaceGrotesk(
                                color: Colors.white,
                                fontSize: 15, fontWeight: FontWeight.w700)),
                  ),
                ),
              ),

              // Guest option
              if (widget.showGuestOption) ...[
                const SizedBox(height: 20),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Container(height: 1, width: 60,
                      color: AppTheme.divider),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text('or', style: GoogleFonts.inter(
                        color: AppTheme.textHint, fontSize: 12)),
                  ),
                  Container(height: 1, width: 60,
                      color: AppTheme.divider),
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

              const SizedBox(height: 32),
            ]),
          ),
        ),
      ]),
    );
  }

  // ── Login form ────────────────────────────────────────────────
  Widget _buildLoginForm() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _field('Email address', _loginEmailCtrl,
          icon: Icons.email_outlined,
          type: TextInputType.emailAddress),
      const SizedBox(height: 14),
      _field('Password', _loginPassCtrl,
          icon:    Icons.lock_outline_rounded,
          obscure: _obscurePass,
          toggleObscure: () => setState(() => _obscurePass = !_obscurePass)),
    ],
  );

  // ── Register form ─────────────────────────────────────────────
  Widget _buildRegisterForm() => Column(children: [
    _field('Username (display name)', _regNameCtrl,
        icon: Icons.person_outline_rounded),
    const SizedBox(height: 10),
    _field('Email address', _regEmailCtrl,
        icon: Icons.email_outlined,
        type: TextInputType.emailAddress),
    const SizedBox(height: 10),
    _field('Password (min 6 chars)', _regPassCtrl,
        icon:    Icons.lock_outline_rounded,
        obscure: _obscurePass,
        toggleObscure: () => setState(() => _obscurePass = !_obscurePass)),
    const SizedBox(height: 10),
    _field('Confirm password', _regPass2Ctrl,
        icon:    Icons.lock_outline_rounded,
        obscure: _obscurePass2,
        toggleObscure: () => setState(() => _obscurePass2 = !_obscurePass2)),
  ]);

  Widget _field(String hint, TextEditingController ctrl, {
    required IconData icon,
    TextInputType type = TextInputType.text,
    bool obscure = false,
    VoidCallback? toggleObscure,
  }) {
    return TextField(
      controller:     ctrl,
      keyboardType:   type,
      obscureText:    obscure,
      autocorrect:    false,
      style: GoogleFonts.inter(color: AppTheme.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        hintText:      hint,
        hintStyle:     GoogleFonts.inter(color: AppTheme.textHint, fontSize: 14),
        prefixIcon:    Icon(icon, color: AppTheme.textHint, size: 18),
        suffixIcon:    toggleObscure != null
            ? IconButton(
                icon: Icon(obscure
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                    color: AppTheme.textHint, size: 18),
                onPressed: toggleObscure)
            : null,
        filled:        true,
        fillColor:     AppTheme.bgCard,
        border:        OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppTheme.accentCyan, width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
    );
  }
}
