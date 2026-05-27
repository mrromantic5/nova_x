// lib/features/auth/screens/otp_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nova_x/core/services/api_service.dart';
import 'package:nova_x/core/theme/app_theme.dart';
import '../../home/screens/home_screen.dart';

class OtpScreen extends StatefulWidget {
  final int    userId;
  final String email;
  const OtpScreen({super.key, required this.userId, required this.email});
  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;
  late Animation<double>   _fadeAnim;

  final List<TextEditingController> _ctrls =
      List.generate(4, (_) => TextEditingController());
  final List<FocusNode> _nodes = List.generate(4, (_) => FocusNode());

  bool _verifying = false;
  bool _resending  = false;
  String _error   = '';

  // Countdown timer for resend
  int _countdown  = 60;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _animCtrl.forward();
    _startCountdown();
    // Auto-focus first box
    WidgetsBinding.instance.addPostFrameCallback((_) => _nodes[0].requestFocus());
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in _ctrls) c.dispose();
    for (final n in _nodes) n.dispose();
    _animCtrl.dispose();
    super.dispose();
  }

  void _startCountdown() {
    _countdown = 60;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_countdown <= 0) { t.cancel(); return; }
      if (mounted) setState(() => _countdown--);
    });
  }

  String get _code => _ctrls.map((c) => c.text).join();

  Future<void> _verify() async {
    if (_code.length < 4) {
      setState(() => _error = 'Please enter all 4 digits');
      return;
    }
    setState(() { _verifying = true; _error = ''; });
    final res = await ApiService.verifyOtp(
        userId: widget.userId, code: _code);
    if (!mounted) return;
    setState(() => _verifying = false);
    if (res['success'] == true) {
      HapticFeedback.lightImpact();
      Navigator.pushAndRemoveUntil(context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
          (r) => false);
    } else {
      setState(() => _error = res['message'] as String? ?? 'Invalid code.');
      // Shake + clear boxes
      for (final c in _ctrls) c.clear();
      _nodes[0].requestFocus();
    }
  }

  Future<void> _resend() async {
    if (_countdown > 0) return;
    setState(() { _resending = true; _error = ''; });
    await ApiService.resendOtp(widget.userId);
    if (!mounted) return;
    setState(() => _resending = false);
    _startCountdown();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('New code sent to ${widget.email}',
          style: GoogleFonts.inter(color: Colors.white)),
      backgroundColor: AppTheme.success,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: Stack(children: [
          // Glow orbs
          Positioned(top: -80, right: -80, child: Container(
            width: 250, height: 250,
            decoration: BoxDecoration(shape: BoxShape.circle,
              gradient: RadialGradient(colors: [
                AppTheme.accentCyan.withOpacity(0.12), Colors.transparent])),
          )),
          Positioned(bottom: -60, left: -60, child: Container(
            width: 200, height: 200,
            decoration: BoxDecoration(shape: BoxShape.circle,
              gradient: RadialGradient(colors: [
                AppTheme.accentPurple.withOpacity(0.10), Colors.transparent])),
          )),

          SafeArea(child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(children: [
              const SizedBox(height: 40),

              // Icon
              Container(
                width: 80, height: 80,
                decoration: BoxDecoration(
                  gradient: AppTheme.primaryGradient,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: AppTheme.glowShadow,
                ),
                child: const Icon(Icons.mark_email_read_outlined,
                    color: Colors.white, size: 38),
              ),
              const SizedBox(height: 24),

              Text('Check your email', style: GoogleFonts.spaceGrotesk(
                  color: AppTheme.textPrimary, fontSize: 26,
                  fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text('We sent a 4-digit code to',
                  style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 14)),
              const SizedBox(height: 4),
              Text(widget.email, style: GoogleFonts.inter(
                  color: AppTheme.accentCyan, fontSize: 14,
                  fontWeight: FontWeight.w700)),

              const SizedBox(height: 44),

              // OTP input boxes
              Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(4, (i) {
                return Container(
                  width: 64, height: 72,
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    gradient: _ctrls[i].text.isNotEmpty
                        ? LinearGradient(colors: [
                            AppTheme.accentCyan.withOpacity(0.2),
                            AppTheme.accentPurple.withOpacity(0.1)])
                        : null,
                    color: _ctrls[i].text.isEmpty ? AppTheme.bgCard : null,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _ctrls[i].text.isNotEmpty
                          ? AppTheme.accentCyan
                          : _nodes[i].hasFocus
                              ? AppTheme.accentCyan.withOpacity(0.5)
                              : AppTheme.divider,
                      width: _ctrls[i].text.isNotEmpty ? 2 : 1.5,
                    ),
                    boxShadow: _ctrls[i].text.isNotEmpty
                        ? [BoxShadow(
                            color: AppTheme.accentCyan.withOpacity(0.25),
                            blurRadius: 12)]
                        : null,
                  ),
                  child: TextField(
                    controller: _ctrls[i],
                    focusNode:  _nodes[i],
                    textAlign:  TextAlign.center,
                    keyboardType:   TextInputType.number,
                    maxLength:      1,
                    style: GoogleFonts.spaceGrotesk(
                        color: AppTheme.textPrimary, fontSize: 28,
                        fontWeight: FontWeight.w800),
                    decoration: const InputDecoration(
                      counterText: '',
                      border: InputBorder.none,
                    ),
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (v) {
                      setState(() {});
                      if (v.isNotEmpty && i < 3) {
                        _nodes[i + 1].requestFocus();
                      }
                      if (v.isEmpty && i > 0) {
                        _nodes[i - 1].requestFocus();
                      }
                      // Auto-submit when all filled
                      if (_code.length == 4 && !_verifying) {
                        Future.delayed(const Duration(milliseconds: 100), _verify);
                      }
                    },
                  ),
                );
              })),

              const SizedBox(height: 16),

              // Error
              if (_error.isNotEmpty) Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppTheme.danger.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.danger.withOpacity(0.3)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.error_outline_rounded,
                      color: AppTheme.danger, size: 16),
                  const SizedBox(width: 8),
                  Text(_error, style: GoogleFonts.inter(
                      color: AppTheme.danger, fontSize: 13)),
                ]),
              ),

              const SizedBox(height: 32),

              // Verify button
              GestureDetector(
                onTap: _verifying ? null : _verify,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 56, width: double.infinity,
                  decoration: BoxDecoration(
                    gradient: AppTheme.primaryGradient,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: AppTheme.glowShadow,
                  ),
                  child: Center(child: _verifying
                      ? const SizedBox(width: 24, height: 24,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : Text('Verify & Continue', style: GoogleFonts.spaceGrotesk(
                          color: Colors.white, fontSize: 16,
                          fontWeight: FontWeight.w700))),
                ),
              ),

              const SizedBox(height: 24),

              // Resend
              GestureDetector(
                onTap: _countdown > 0 ? null : _resend,
                child: _resending
                    ? const SizedBox(width: 18, height: 18,
                        child: CircularProgressIndicator(
                            color: AppTheme.accentCyan, strokeWidth: 2))
                    : Text(
                        _countdown > 0
                            ? 'Resend code in ${_countdown}s'
                            : 'Resend code',
                        style: GoogleFonts.inter(
                            color: _countdown > 0
                                ? AppTheme.textHint
                                : AppTheme.accentCyan,
                            fontSize: 14,
                            fontWeight: _countdown > 0
                                ? FontWeight.w400
                                : FontWeight.w700,
                            decoration: _countdown > 0
                                ? null
                                : TextDecoration.underline,
                            decorationColor: AppTheme.accentCyan),
                      ),
              ),

              const SizedBox(height: 20),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Text('← Back',
                    style: GoogleFonts.inter(
                        color: AppTheme.textHint, fontSize: 13)),
              ),
              const SizedBox(height: 40),
            ]),
          )),
        ]),
      ),
    );
  }
}
