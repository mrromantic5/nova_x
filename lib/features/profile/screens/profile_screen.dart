// lib/features/profile/screens/profile_screen.dart
import "package:flutter/material.dart";
import "package:google_fonts/google_fonts.dart";
import "package:nova_x/core/services/api_service.dart";
import "package:nova_x/core/theme/app_theme.dart";
import "../../auth/screens/auth_screen.dart";

export "profile_screen_impl.dart" if (dart.library.html) "profile_screen_impl.dart";

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      body: const Center(child: CircularProgressIndicator(color: AppTheme.accentCyan)),
    );
  }
}
