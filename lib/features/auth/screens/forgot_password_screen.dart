// lib/features/auth/screens/forgot_password_screen.dart
//
// "Forgot password?" from the login screen. Three steps on one screen:
//   1. Email      → the server emails a 6-digit code (valid 15 minutes)
//   2. Code       → 6 boxes, paste/auto-fill, resend timer, tries left
//   3. New password → strength meter and checklist (server rules)
// Then the user is signed in (other devices are signed out by the server and
// a "password changed" email is sent). Server: backend/api.browser/password_reset.php.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nova_x/core/services/api_service.dart';
import 'package:nova_x/core/theme/app_theme.dart';

import '../../home/screens/home_screen.dart';
import '../../permissions/screens/permission_slides_screen.dart';
import '../services/password_rules.dart';

enum _Step { email, code, password, done }

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialEmail = ''});

  /// The email typed on the login screen (if any).
  final String initialEmail;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  _Step _step = _Step.email;

  final _emailCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _pass2Ctrl = TextEditingController();
  final _emailFocus = FocusNode();
  final _codeFocus = FocusNode();
  final _passFocus = FocusNode();
  final _pass2Focus = FocusNode();

  bool _busy = false;
  bool _obscure = true;
  bool _obscure2 = true;
  String _error = '';
  String _info = '';

  String _email = '';
  String? _resetToken;
  bool _signedIn = false;

  DateTime? _resendAt;
  DateTime? _codeExpiresAt;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _emailCtrl.text = widget.initialEmail.trim();
    _codeCtrl.addListener(_onCodeChanged);
    _passCtrl.addListener(_refresh);
    _pass2Ctrl.addListener(_refresh);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _emailFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _codeCtrl.removeListener(_onCodeChanged);
    for (final c in [_emailCtrl, _codeCtrl, _passCtrl, _pass2Ctrl]) {
      c.dispose();
    }
    for (final f in [_emailFocus, _codeFocus, _passFocus, _pass2Focus]) {
      f.dispose();
    }
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  // ── Timers ──────────────────────────────────────────────────────────────────

  int _secondsUntil(DateTime? t) {
    if (t == null) return 0;
    final s = t.difference(DateTime.now()).inMilliseconds / 1000;
    return s <= 0 ? 0 : s.ceil();
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_secondsUntil(_resendAt) == 0 && _secondsUntil(_codeExpiresAt) == 0) _ticker?.cancel();
      setState(() {});
    });
  }

  // ── Step 1: email ───────────────────────────────────────────────────────────

  Future<void> _sendCode({bool resend = false}) async {
    final email = (resend ? _email : _emailCtrl.text).trim();
    if (!PasswordRules.isValidEmail(email)) {
      setState(() => _error = 'Please enter a valid email address.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = '';
      _info = '';
    });
    final r = await ApiService.requestPasswordReset(email);
    if (!mounted) return;
    setState(() => _busy = false);

    if (r.ok) {
      HapticFeedback.lightImpact();
      setState(() {
        _email = email;
        _resendAt = DateTime.now().add(Duration(seconds: r.resendAfter ?? 60));
        _codeExpiresAt = DateTime.now().add(Duration(seconds: r.expiresIn ?? 900));
        _info = resend ? 'A new code is on its way to ${PasswordRules.maskEmail(email)}.' : '';
        _codeCtrl.clear();
        _step = _Step.code;
      });
      _startTicker();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _codeFocus.requestFocus();
      });
      return;
    }
    if (r.rateLimited && r.retryAfter != null) {
      _resendAt = DateTime.now().add(Duration(seconds: r.retryAfter!));
      _startTicker();
    }
    setState(() => _error = r.message.isEmpty ? 'Something went wrong. Please try again.' : r.message);
  }

  /// "I already have a code" — e.g. after reopening this screen.
  void _haveCode() {
    final email = _emailCtrl.text.trim();
    if (!PasswordRules.isValidEmail(email)) {
      setState(() => _error = 'Enter your email first.');
      return;
    }
    setState(() {
      _email = email;
      _error = '';
      _info = '';
      _codeExpiresAt = null; // unknown: the code from the latest email
      _codeCtrl.clear();
      _step = _Step.code;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _codeFocus.requestFocus();
    });
  }

  // ── Step 2: code ────────────────────────────────────────────────────────────

  void _onCodeChanged() {
    final clean = PasswordRules.normalizeCode(_codeCtrl.text);
    if (clean != _codeCtrl.text) {
      _codeCtrl.value = TextEditingValue(text: clean, selection: TextSelection.collapsed(offset: clean.length));
      return;
    }
    if (_error.isNotEmpty && clean.isNotEmpty) _error = '';
    setState(() {});
    if (clean.length == 6 && !_busy) _verifyCode();
  }

  Future<void> _pasteCode() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final code = PasswordRules.normalizeCode(data?.text ?? '');
    if (!mounted) return;
    if (code.length != 6) {
      setState(() => _error = 'No 6-digit code found on the clipboard.');
      return;
    }
    _codeCtrl.text = code;
  }

  Future<void> _verifyCode() async {
    final code = PasswordRules.normalizeCode(_codeCtrl.text);
    if (code.length != 6) {
      setState(() => _error = 'Enter all 6 digits.');
      return;
    }
    setState(() {
      _busy = true;
      _error = '';
      _info = '';
    });
    final r = await ApiService.verifyPasswordResetCode(email: _email, code: code);
    if (!mounted) return;
    setState(() => _busy = false);

    if (r.ok && r.resetToken != null) {
      HapticFeedback.lightImpact();
      _ticker?.cancel();
      setState(() {
        _resetToken = r.resetToken;
        _step = _Step.password;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _passFocus.requestFocus();
      });
      return;
    }
    HapticFeedback.mediumImpact();
    setState(() {
      _error = r.message.isEmpty ? "That code isn't right." : r.message;
      _codeCtrl.clear();
      if (r.expired) _codeExpiresAt = DateTime.now(); // ask for a new one
    });
    _codeFocus.requestFocus();
  }

  // ── Step 3: new password ────────────────────────────────────────────────────

  Future<void> _resetPassword() async {
    final pass = _passCtrl.text;
    final problem = PasswordRules.problem(pass);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    if (pass != _pass2Ctrl.text) {
      setState(() => _error = 'The passwords do not match.');
      return;
    }
    final token = _resetToken;
    if (token == null) {
      _restart('Your reset session has expired. Ask for a new code.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = '';
    });
    final r = await ApiService.resetPassword(email: _email, resetToken: token, password: pass);
    if (!mounted) return;
    setState(() => _busy = false);

    if (r.ok) {
      HapticFeedback.heavyImpact();
      _passCtrl.clear();
      _pass2Ctrl.clear();
      setState(() {
        _signedIn = _hasSession(r);
        _step = _Step.done;
      });
      return;
    }
    if (r.expired) {
      _restart(r.message.isEmpty ? 'Your reset session has expired. Ask for a new code.' : r.message);
      return;
    }
    setState(() => _error = r.message.isEmpty ? 'Something went wrong. Please try again.' : r.message);
  }

  /// The server signed the user in (API v2.8 returns a new session).
  static bool _hasSession(PasswordResetResult r) =>
      r.data['access_token'] is String && r.data['user'] is Map;

  void _restart(String message) {
    _ticker?.cancel();
    setState(() {
      _resetToken = null;
      _codeCtrl.clear();
      _emailCtrl.text = _email.isEmpty ? _emailCtrl.text : _email;
      _step = _Step.email;
      _error = message;
      _info = '';
    });
  }

  // ── Step 4: done ────────────────────────────────────────────────────────────

  Future<void> _continue() async {
    if (!_signedIn) {
      Navigator.of(context).pop(_email);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final permsDone = prefs.getBool('permissions_shown') ?? false;
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => permsDone ? const HomeScreen() : const PermissionSlidesScreen(),
        transitionDuration: const Duration(milliseconds: 450),
        transitionsBuilder: (_, anim, __, child) => FadeTransition(
          opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
          child: child,
        ),
      ),
      (route) => false,
    );
  }

  /// System back: step back instead of leaving half-way.
  void _back() {
    switch (_step) {
      case _Step.email:
        Navigator.of(context).pop();
      case _Step.code:
        setState(() {
          _step = _Step.email;
          _error = '';
          _info = '';
        });
      case _Step.password:
        setState(() {
          _resetToken = null;
          _step = _Step.code;
          _error = '';
          _codeCtrl.clear();
        });
      case _Step.done:
        _continue();
    }
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _step == _Step.email && !_busy,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_busy) _back();
      },
      child: Scaffold(
        backgroundColor: AppTheme.bgDark,
        body: Stack(children: [
          Positioned(
            top: -100,
            right: -100,
            child: _glow(300, AppTheme.accentCyan.withValues(alpha: 0.15)),
          ),
          Positioned(
            bottom: -80,
            left: -80,
            child: _glow(250, AppTheme.accentPurple.withValues(alpha: 0.12)),
          ),
          SafeArea(
            child: Column(children: [
              _topBar(),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 320),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, anim) => FadeTransition(
                      opacity: anim,
                      child: SlideTransition(
                        position: Tween(begin: const Offset(0.06, 0), end: Offset.zero).animate(anim),
                        child: child,
                      ),
                    ),
                    child: KeyedSubtree(key: ValueKey(_step), child: _stepBody()),
                  ),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _glow(double size, Color color) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, Colors.transparent]),
        ),
      );

  Widget _topBar() {
    final index = switch (_step) {
      _Step.email => 0,
      _Step.code => 1,
      _Step.password => 2,
      _Step.done => 3,
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 24, 0),
      child: Row(children: [
        IconButton(
          tooltip: 'Back',
          onPressed: _busy ? null : _back,
          icon: const Icon(Icons.arrow_back_rounded, color: AppTheme.textSecondary),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Row(children: [
            for (var i = 0; i < 3; i++) ...[
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  height: 4,
                  decoration: BoxDecoration(
                    gradient: i <= index ? AppTheme.primaryGradient : null,
                    color: i <= index ? null : AppTheme.bgCard,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              if (i < 2) const SizedBox(width: 6),
            ],
          ]),
        ),
      ]),
    );
  }

  Widget _stepBody() => switch (_step) {
        _Step.email => _emailStep(),
        _Step.code => _codeStep(),
        _Step.password => _passwordStep(),
        _Step.done => _doneStep(),
      };

  // ── Shared pieces ───────────────────────────────────────────────────────────

  Widget _header(IconData icon, String title, Widget subtitle) => Column(children: [
        const SizedBox(height: 20),
        Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            gradient: AppTheme.primaryGradient,
            borderRadius: BorderRadius.circular(24),
            boxShadow: AppTheme.glowShadow,
          ),
          child: Icon(icon, color: Colors.white, size: 36),
        ),
        const SizedBox(height: 24),
        Text(title,
            textAlign: TextAlign.center,
            style: GoogleFonts.spaceGrotesk(color: AppTheme.textPrimary, fontSize: 26, fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        subtitle,
        const SizedBox(height: 28),
      ]);

  Widget _subtitle(String text) => Text(text,
      textAlign: TextAlign.center,
      style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 14, height: 1.5));

  Widget _banner(String text, {required bool error}) {
    final color = error ? AppTheme.danger : AppTheme.accentCyan;
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(error ? Icons.error_outline_rounded : Icons.info_outline_rounded, color: color, size: 17),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: GoogleFonts.inter(color: color, fontSize: 12.5, height: 1.45))),
      ]),
    );
  }

  Widget _messages() => Column(children: [
        if (_error.isNotEmpty) _banner(_error, error: true),
        if (_info.isNotEmpty) _banner(_info, error: false),
      ]);

  Widget _primaryButton(String label, VoidCallback? onTap) {
    final enabled = onTap != null && !_busy;
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 54,
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: enabled || _busy ? AppTheme.primaryGradient : null,
          color: enabled || _busy ? null : AppTheme.bgCard,
          borderRadius: BorderRadius.circular(16),
          boxShadow: enabled ? AppTheme.glowShadow : null,
        ),
        child: Center(
          child: _busy
              ? const SizedBox(
                  width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : Text(label,
                  style: GoogleFonts.spaceGrotesk(
                    color: enabled ? Colors.white : AppTheme.textHint,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  )),
        ),
      ),
    );
  }

  Widget _link(String label, VoidCallback? onTap, {Color color = AppTheme.accentCyan}) => TextButton(
        onPressed: _busy ? null : onTap,
        style: TextButton.styleFrom(foregroundColor: color, disabledForegroundColor: AppTheme.textHint),
        child: Text(label, style: GoogleFonts.inter(fontSize: 13.5, fontWeight: FontWeight.w600)),
      );

  InputDecoration _decoration(String hint, IconData icon, {Widget? suffix}) => InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 14),
        prefixIcon: Icon(icon, color: AppTheme.textHint, size: 18),
        suffixIcon: suffix,
        filled: true,
        fillColor: AppTheme.bgCard,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppTheme.accentCyan, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      );

  // ── Step widgets ────────────────────────────────────────────────────────────

  Widget _emailStep() {
    final wait = _secondsUntil(_resendAt);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _header(
        Icons.lock_reset_rounded,
        'Forgot password?',
        _subtitle("Enter the email of your NOVA X account. We'll send you a 6-digit code to reset your password."),
      ),
      TextField(
        controller: _emailCtrl,
        focusNode: _emailFocus,
        keyboardType: TextInputType.emailAddress,
        textInputAction: TextInputAction.send,
        autocorrect: false,
        autofillHints: const [AutofillHints.email],
        onSubmitted: (_) => _sendCode(),
        onChanged: (_) {
          if (_error.isNotEmpty) setState(() => _error = '');
        },
        style: GoogleFonts.inter(color: AppTheme.textPrimary, fontSize: 14),
        decoration: _decoration('Email address', Icons.email_outlined),
      ),
      _messages(),
      const SizedBox(height: 22),
      _primaryButton(
        wait > 0 ? 'Send code in ${PasswordRules.clock(wait)}' : 'Send reset code',
        wait > 0 ? null : () => _sendCode(),
      ),
      const SizedBox(height: 10),
      Center(child: _link('I already have a code', _haveCode)),
      const SizedBox(height: 18),
      _securityNote(),
    ]);
  }

  Widget _codeStep() {
    final resendIn = _secondsUntil(_resendAt);
    final expiresIn = _secondsUntil(_codeExpiresAt);
    final code = _codeCtrl.text;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _header(
        Icons.mark_email_read_outlined,
        'Check your email',
        Text.rich(
          TextSpan(
            style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 14, height: 1.5),
            children: [
              const TextSpan(text: 'Enter the 6-digit code we sent to\n'),
              TextSpan(
                text: _email,
                style: GoogleFonts.inter(color: AppTheme.accentCyan, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          textAlign: TextAlign.center,
        ),
      ),
      // Six boxes over one real text field (keyboard, paste and SMS/email auto-fill work).
      GestureDetector(
        onTap: () => _codeFocus.requestFocus(),
        child: Stack(alignment: Alignment.center, children: [
          Opacity(
            opacity: 0,
            child: TextField(
              controller: _codeCtrl,
              focusNode: _codeFocus,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
              showCursor: false,
              enableInteractiveSelection: false,
              decoration: const InputDecoration(border: InputBorder.none, counterText: ''),
            ),
          ),
          IgnorePointer(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [for (var i = 0; i < 6; i++) _codeBox(i < code.length ? code[i] : '', i == code.length)],
            ),
          ),
        ]),
      ),
      const SizedBox(height: 14),
      if (_codeExpiresAt != null) Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.timer_outlined, size: 15, color: expiresIn > 0 ? AppTheme.textHint : AppTheme.warning),
        const SizedBox(width: 6),
        Text(
          expiresIn > 0 ? 'Code expires in ${PasswordRules.clock(expiresIn)}' : 'Code expired — send a new one',
          style: GoogleFonts.inter(
            color: expiresIn > 0 ? AppTheme.textHint : AppTheme.warning,
            fontSize: 12.5,
          ),
        ),
      ]),
      _messages(),
      const SizedBox(height: 22),
      _primaryButton('Verify code', code.length == 6 ? _verifyCode : null),
      const SizedBox(height: 10),
      Wrap(alignment: WrapAlignment.center, spacing: 4, children: [
        _link('Paste code', _pasteCode),
        _link(
          resendIn > 0 ? 'Resend in ${PasswordRules.clock(resendIn)}' : 'Resend code',
          resendIn > 0 ? null : () => _sendCode(resend: true),
        ),
        _link('Change email', () {
          setState(() {
            _step = _Step.email;
            _error = '';
            _info = '';
          });
        }, color: AppTheme.textSecondary),
      ]),
      const SizedBox(height: 8),
      Text(
        "Can't find it? Check your spam or promotions folder. The newest code is the only one that works.",
        textAlign: TextAlign.center,
        style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 12, height: 1.5),
      ),
    ]);
  }

  Widget _codeBox(String digit, bool active) {
    final filled = digit.isNotEmpty;
    final focused = active && _codeFocus.hasFocus;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: 46,
      height: 58,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: filled
            ? LinearGradient(colors: [
                AppTheme.accentCyan.withValues(alpha: 0.20),
                AppTheme.accentPurple.withValues(alpha: 0.10),
              ])
            : null,
        color: filled ? null : AppTheme.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: filled
              ? AppTheme.accentCyan
              : focused
                  ? AppTheme.accentCyan.withValues(alpha: 0.6)
                  : AppTheme.divider,
          width: filled || focused ? 2 : 1.5,
        ),
      ),
      child: Text(digit,
          style: GoogleFonts.spaceGrotesk(color: AppTheme.textPrimary, fontSize: 24, fontWeight: FontWeight.w800)),
    );
  }

  Widget _passwordStep() {
    final pass = _passCtrl.text;
    final strength = PasswordRules.strength(pass);
    final matches = pass.isNotEmpty && pass == _pass2Ctrl.text;
    final ready = PasswordRules.problem(pass) == null && matches;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _header(
        Icons.password_rounded,
        'Create a new password',
        _subtitle("Choose a strong password you don't use for other accounts."),
      ),
      TextField(
        controller: _passCtrl,
        focusNode: _passFocus,
        obscureText: _obscure,
        autocorrect: false,
        enableSuggestions: false,
        autofillHints: const [AutofillHints.newPassword],
        textInputAction: TextInputAction.next,
        onSubmitted: (_) => _pass2Focus.requestFocus(),
        style: GoogleFonts.inter(color: AppTheme.textPrimary, fontSize: 14),
        decoration: _decoration('New password', Icons.lock_outline_rounded,
            suffix: _eye(_obscure, () => setState(() => _obscure = !_obscure))),
      ),
      const SizedBox(height: 12),
      _strengthMeter(strength),
      const SizedBox(height: 12),
      TextField(
        controller: _pass2Ctrl,
        focusNode: _pass2Focus,
        obscureText: _obscure2,
        autocorrect: false,
        enableSuggestions: false,
        autofillHints: const [AutofillHints.newPassword],
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _resetPassword(),
        style: GoogleFonts.inter(color: AppTheme.textPrimary, fontSize: 14),
        decoration: _decoration('Confirm new password', Icons.lock_outline_rounded,
            suffix: _eye(_obscure2, () => setState(() => _obscure2 = !_obscure2))),
      ),
      const SizedBox(height: 14),
      for (final c in PasswordRules.checks(pass)) _check(c.label, c.passed),
      _check('Both passwords match', matches),
      _messages(),
      const SizedBox(height: 22),
      _primaryButton('Reset password', ready ? _resetPassword : null),
      const SizedBox(height: 14),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.devices_other_rounded, size: 16, color: AppTheme.textHint),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            "For your security, you'll be signed out of NOVA X on your other devices.",
            style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 12, height: 1.5),
          ),
        ),
      ]),
    ]);
  }

  Widget _eye(bool obscure, VoidCallback onTap) => IconButton(
        tooltip: obscure ? 'Show password' : 'Hide password',
        icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
            color: AppTheme.textHint, size: 18),
        onPressed: onTap,
      );

  Widget _strengthMeter(PasswordStrength s) {
    final level = switch (s) {
      PasswordStrength.empty => 0,
      PasswordStrength.weak => 1,
      PasswordStrength.fair => 2,
      PasswordStrength.good => 3,
      PasswordStrength.strong => 4,
    };
    final color = switch (s) {
      PasswordStrength.weak => AppTheme.danger,
      PasswordStrength.fair => AppTheme.warning,
      PasswordStrength.good => AppTheme.accentCyan,
      PasswordStrength.strong => AppTheme.success,
      PasswordStrength.empty => AppTheme.divider,
    };
    return Row(children: [
      for (var i = 1; i <= 4; i++) ...[
        Expanded(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            height: 5,
            decoration: BoxDecoration(
              color: i <= level ? color : AppTheme.bgCard,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
        const SizedBox(width: 5),
      ],
      SizedBox(
        width: 64,
        child: Text(PasswordRules.strengthLabel(s),
            textAlign: TextAlign.right,
            style: GoogleFonts.inter(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
      ),
    ]);
  }

  Widget _check(String label, bool ok) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Icon(
              ok ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
              key: ValueKey(ok),
              size: 17,
              color: ok ? AppTheme.success : AppTheme.textHint,
            ),
          ),
          const SizedBox(width: 8),
          Text(label,
              style: GoogleFonts.inter(color: ok ? AppTheme.textSecondary : AppTheme.textHint, fontSize: 12.5)),
        ]),
      );

  Widget _doneStep() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SizedBox(height: 40),
        Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.6, end: 1),
            duration: const Duration(milliseconds: 500),
            curve: Curves.elasticOut,
            builder: (_, v, child) => Transform.scale(scale: v, child: child),
            child: Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(colors: [AppTheme.success, AppTheme.accentCyan]),
                boxShadow: [BoxShadow(color: AppTheme.success.withValues(alpha: 0.35), blurRadius: 30)],
              ),
              child: const Icon(Icons.check_rounded, color: Colors.white, size: 52),
            ),
          ),
        ),
        const SizedBox(height: 28),
        Text('Password updated',
            textAlign: TextAlign.center,
            style: GoogleFonts.spaceGrotesk(color: AppTheme.textPrimary, fontSize: 26, fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        _subtitle(_signedIn
            ? "You're signed in. We signed you out on your other devices and emailed you a confirmation."
            : 'Your password has been changed. Log in with your new password.'),
        const SizedBox(height: 32),
        _primaryButton(_signedIn ? 'Continue to NOVA X' : 'Back to log in', _continue),
      ]);

  Widget _securityNote() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.divider),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.shield_outlined, color: AppTheme.accentCyan, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'The code works once and expires after 15 minutes. NOVA X will never ask you for it by '
              'phone, chat or email.',
              style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 12, height: 1.5),
            ),
          ),
        ]),
      );
}
