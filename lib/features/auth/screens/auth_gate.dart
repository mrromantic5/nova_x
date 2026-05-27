// lib/features/auth/screens/auth_gate.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nova_x/core/services/api_service.dart';
import 'package:nova_x/core/theme/app_theme.dart';
import '../../home/screens/home_screen.dart';
import 'auth_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;
    final loggedIn = await ApiService.isLoggedIn();
    if (!mounted) return;
    Navigator.pushReplacement(context, MaterialPageRoute(
        builder: (_) => loggedIn ? const HomeScreen() : const AuthScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      body: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        ShaderMask(
          shaderCallback: (b) => AppTheme.primaryGradient.createShader(b),
          child: Text('NOVA X', style: GoogleFonts.spaceGrotesk(
              color: Colors.white, fontSize: 40,
              fontWeight: FontWeight.w900, letterSpacing: 4)),
        ),
        const SizedBox(height: 12),
        Text('The Future of Browsing', style: GoogleFonts.inter(
            color: AppTheme.textHint, fontSize: 13)),
        const SizedBox(height: 48),
        const CircularProgressIndicator(
            color: AppTheme.accentCyan, strokeWidth: 2),
      ])),
    );
  }
}
