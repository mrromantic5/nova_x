import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // ── Brand ────────────────────────────────────────────────────────────────
  static const Color primaryBlue  = Color(0xFF1E7BFF);
  static const Color accentCyan   = Color(0xFF00D4FF);
  static const Color accentPurple = Color(0xFF7C4DFF);

  // ── Background layers ────────────────────────────────────────────────────
  static const Color bgDark     = Color(0xFF07101E); // deepest canvas
  static const Color bgCard     = Color(0xFF0F1E35); // card surface
  static const Color bgElevated = Color(0xFF162846); // raised element
  static const Color bgInput    = Color(0xFF0D1A2D); // input fields

  // ── Text ────────────────────────────────────────────────────────────────
  static const Color textPrimary   = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFB0C4DE);
  static const Color textHint      = Color(0xFF4A6A8A);

  // ── UI chrome ────────────────────────────────────────────────────────────
  static const Color divider   = Color(0xFF152236);
  static const Color success   = Color(0xFF00C853);
  static const Color warning   = Color(0xFFFFAB00);
  static const Color danger    = Color(0xFFFF4444);
  static const Color secure    = Color(0xFF00C853);

  // ── Glass ────────────────────────────────────────────────────────────────
  static const Color glassWhite  = Color(0x14FFFFFF);
  static const Color glassBorder = Color(0x22FFFFFF);

  // ── Gradients ────────────────────────────────────────────────────────────
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primaryBlue, accentCyan],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static const LinearGradient bgGradient = LinearGradient(
    colors: [Color(0xFF07101E), Color(0xFF0A1628)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  static const LinearGradient cardGradient = LinearGradient(
    colors: [Color(0xFF0F1E35), Color(0xFF0D1928)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ── Shadows ──────────────────────────────────────────────────────────────
  static List<BoxShadow> get cardShadow => [
    BoxShadow(
      color: Colors.black.withOpacity(0.35),
      blurRadius: 24,
      offset: const Offset(0, 8),
    ),
  ];

  static List<BoxShadow> get glowShadow => [
    BoxShadow(
      color: primaryBlue.withOpacity(0.3),
      blurRadius: 20,
      offset: const Offset(0, 4),
    ),
  ];

  // ── ThemeData ────────────────────────────────────────────────────────────
  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bgDark,
      primaryColor: primaryBlue,
      colorScheme: const ColorScheme.dark(
        primary: primaryBlue,
        secondary: accentCyan,
        surface: bgCard,
        error: danger,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: bgDark,
        elevation: 0,
        centerTitle: false,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        titleTextStyle: GoogleFonts.spaceGrotesk(
          color: textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
        iconTheme: const IconThemeData(color: textSecondary),
      ),
      textTheme: TextTheme(
        displayLarge: GoogleFonts.spaceGrotesk(
          color: textPrimary, fontWeight: FontWeight.bold),
        titleLarge: GoogleFonts.spaceGrotesk(
          color: textPrimary, fontWeight: FontWeight.w600),
        titleMedium: GoogleFonts.spaceGrotesk(
          color: textPrimary, fontWeight: FontWeight.w500),
        bodyLarge:  GoogleFonts.inter(color: textSecondary),
        bodyMedium: GoogleFonts.inter(color: textSecondary),
        bodySmall:  GoogleFonts.inter(color: textHint),
      ),
      dividerColor: divider,
      useMaterial3: true,
    );
  }
}
