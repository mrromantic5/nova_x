// lib/features/map/map_premium_gate.dart
//
// Premium gate for NOVA Map. NOVA Map is a Premium-only feature: free users get
// a paywall (popup from entry points, full page if the screen is reached
// directly). Keeps the gate logic + paywall UI in one reusable place.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nova_x/core/theme/app_theme.dart';
import 'package:nova_x/core/services/rewards_entitlements.dart';
import 'package:nova_x/features/premium/screens/subscription_screen.dart';
import 'package:nova_x/features/map/screens/nova_map_screen.dart';

class MapGate {
  /// Opens NOVA Map for premium users, otherwise shows the paywall popup.
  static void open(BuildContext context) {
    if (RewardsEntitlements.isPremium) {
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => const NovaMapScreen()));
    } else {
      showPaywall(context);
    }
  }

  /// Premium paywall as a dialog popup (used from home entry points).
  static Future<void> showPaywall(BuildContext context) => showDialog(
        context: context,
        barrierColor: Colors.black.withOpacity(0.82),
        builder: (dctx) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 28),
          child: MapPaywallContent(
            onUpgrade: () {
              final nav = Navigator.of(dctx, rootNavigator: true);
              Navigator.of(dctx).pop();
              nav.push(MaterialPageRoute(
                  builder: (_) => const SubscriptionScreen()));
            },
            onMaybeLater: () => Navigator.of(dctx).pop(),
          ),
        ),
      );
}

/// Shared paywall card — used inside the popup dialog and the full-page gate.
class MapPaywallContent extends StatelessWidget {
  final VoidCallback onUpgrade;
  final VoidCallback? onMaybeLater;
  const MapPaywallContent({super.key, required this.onUpgrade, this.onMaybeLater});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.glassBorder),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 64, height: 64,
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [Color(0xFF00C853), Color(0xFF00D4FF)]),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.map_rounded, color: Colors.white, size: 32),
        ),
        const SizedBox(height: 18),
        Text('NOVA Map is Premium',
            textAlign: TextAlign.center,
            style: GoogleFonts.spaceGrotesk(
                color: AppTheme.textPrimary, fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        Text(
          'Verify your account with NOVA Premium to unlock live maps, '
          'nearby places, directions and voice navigation.',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
              color: AppTheme.textSecondary, fontSize: 13, height: 1.5),
        ),
        const SizedBox(height: 16),
        _perk(Icons.location_on_rounded, 'Live map & your location'),
        _perk(Icons.travel_explore_rounded, 'Nearby places search'),
        _perk(Icons.directions_rounded, 'Directions & voice navigation'),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: onUpgrade,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00C853),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: Text('Verify with Premium',
                style: GoogleFonts.inter(
                    color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
          ),
        ),
        if (onMaybeLater != null) ...[
          const SizedBox(height: 6),
          TextButton(
            onPressed: onMaybeLater,
            child: Text('Maybe later',
                style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 13)),
          ),
        ],
      ]),
    );
  }

  Widget _perk(IconData icon, String label) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Icon(icon, color: const Color(0xFF00C853), size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label,
                style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 13)),
          ),
        ]),
      );
}
