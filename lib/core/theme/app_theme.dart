import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static const Color primaryBlue = Color(0xFF1677FF);
  static const Color accentCyan = Color(0xFF00E5FF);
  static const Color darkBackground = Color(0xFF081120);
  
  static const Color glassWhite = Colors.white10;
  static const Color glassBorder = Colors.white24;

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: darkBackground,
      primaryColor: primaryBlue,
      colorScheme: const ColorScheme.dark(
        primary: primaryBlue,
        secondary: accentCyan,
        background: darkBackground,
      ),
      textTheme: TextTheme(
        displayLarge: GoogleFonts.spaceGrotesk(color: Colors.white, fontWeight: FontWeight.bold),
        titleLarge: GoogleFonts.spaceGrotesk(color: Colors.white, fontWeight: FontWeight.w600),
        bodyLarge: GoogleFonts.inter(color: Colors.white70),
        bodyMedium: GoogleFonts.inter(color: Colors.white60),
      ),
      useMaterial3: true,
    );
  }
}
