// lib/core/theme/nova_tokens.dart
//
// 3.14.0: NOVA X shared colour tokens — the same values as the dark
// NovaPalette in NOVA X for Windows (lib/desktop/theme/nova_desktop_theme.dart),
// so the Android and Windows apps use one palette. AppTheme and the NOVA
// Cyber / Developer Hub / API Studio palette read from here; keep this file
// identical on both platforms when a colour changes.

import 'package:flutter/material.dart';

class NovaTokens {
  NovaTokens._();

  // Surfaces
  static const Color bg = Color(0xFF07101E);
  static const Color chrome = Color(0xFF050B16);
  static const Color surface = Color(0xFF0E1A2E);
  static const Color surfaceAlt = Color(0xFF0A1526);
  static const Color surfaceHigh = Color(0xFF172741);
  static const Color border = Color(0xFF1A2A44);
  static const Color borderStrong = Color(0xFF2A3D5E);

  // Text
  static const Color text = Color(0xFFE8EDF5);
  static const Color textMuted = Color(0xFFA3B1C6);
  static const Color textFaint = Color(0xFF61728D);

  // Accent and status
  static const Color accent = Color(0xFF00D4FF);
  static const Color accentSoft = Color(0xFF0C3550);
  static const Color onAccent = Color(0xFF00121A);
  static const Color danger = Color(0xFFFF5A5A);
  static const Color success = Color(0xFF2BD47A);
  static const Color warning = Color(0xFFFFB020);
  static const Color incognito = Color(0xFF9B7BFF);

  // Spacing and radius (same steps as Windows)
  static const double gap = 8;
  static const double pad = 16;
  static const double radius = 12;
  static const double radiusSmall = 8;
}
