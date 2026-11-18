// lib/features/cyber/ui/cyber_palette.dart
//
// NOVA Cyber (3.13.0) — colours and text styles for the Cyber screens.
//
// The Cyber UI was built on NOVA X for PC with a small palette API
// (p.surface, p.text, p.ui(...), p.title(...)). This file gives Android the
// same API, mapped to the Android AppTheme (NOVA's dark brand look), so the
// Cyber screens look the same on both platforms and the shared widget code
// stays line-for-line comparable with the PC version.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/nova_tokens.dart';

class NovaPalette {
  const NovaPalette._();

  static const NovaPalette instance = NovaPalette._();

  bool get dark => true;
  // 3.14.0: one palette for Android and Windows (core/theme/nova_tokens.dart).
  Color get bg => NovaTokens.bg;
  Color get surface => NovaTokens.surface;
  Color get surfaceAlt => NovaTokens.surfaceAlt;
  Color get surfaceHigh => NovaTokens.surfaceHigh;
  Color get border => NovaTokens.border;
  Color get borderStrong => NovaTokens.borderStrong;
  Color get text => NovaTokens.text;
  Color get textMuted => NovaTokens.textMuted;
  Color get textFaint => NovaTokens.textFaint;
  Color get accent => NovaTokens.accent;
  Color get accentSoft => NovaTokens.accentSoft;
  Color get onAccent => NovaTokens.onAccent;
  Color get danger => NovaTokens.danger;
  Color get success => NovaTokens.success;
  Color get warning => NovaTokens.warning;

  TextStyle ui({double size = 13.5, FontWeight weight = FontWeight.w400, Color? color, double? height, double? letterSpacing}) =>
      GoogleFonts.inter(fontSize: size, fontWeight: weight, color: color ?? text, height: height, letterSpacing: letterSpacing);

  TextStyle title({double size = 18, FontWeight weight = FontWeight.w700, Color? color}) =>
      GoogleFonts.plusJakartaSans(fontSize: size, fontWeight: weight, color: color ?? text);

  /// Material theme for the Cyber screens and dialogs (buttons, chips,
  /// inputs, segmented buttons follow the NOVA cyan accent).
  ThemeData materialTheme(ThemeData base) {
    final scheme = base.colorScheme.copyWith(
      brightness: Brightness.dark,
      primary: accent,
      onPrimary: onAccent,
      secondary: accent,
      secondaryContainer: accentSoft,
      onSecondaryContainer: accent,
      surface: surface,
      onSurface: text,
      error: danger,
      outline: border,
      surfaceContainerHighest: surfaceHigh,
    );
    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      dividerColor: border,
      canvasColor: surface,
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? accent : null),
        checkColor: WidgetStatePropertyAll(onAccent),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceAlt,
        hintStyle: GoogleFonts.inter(color: textFaint),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: accent, width: 1.6)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: const Color(0xFF1D2B45),
        contentTextStyle: GoogleFonts.inter(color: Colors.white, fontSize: 13),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

/// Same call as on PC: `NovaThemeScope.of(context)`.
class NovaThemeScope {
  const NovaThemeScope._();
  static NovaPalette of(BuildContext context) => NovaPalette.instance;
}

/// Wraps a Cyber screen or dialog in the Cyber material theme.
class NovaThemed extends StatelessWidget {
  const NovaThemed({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Theme(data: NovaPalette.instance.materialTheme(Theme.of(context)), child: child);
}
