// lib/core/widgets/feature_lock.dart
//
// Premium lock UI shown when a user opens a feature they haven't unlocked.
//   • FeatureLockScreen  — full-screen gate (wrap a screen's build)
//   • showFeatureUnlockSheet — bottom sheet (for panels like Dev Tools)
// Both share the same redeem flow against RewardsService.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../services/rewards_service.dart';
import '../services/rewards_entitlements.dart';
import '../../features/rewards/screens/rewards_screen.dart';

const Color kGold     = Color(0xFFFFC83D);
const Color kGoldSoft = Color(0xFFFFE08A);

// Fallback costs (mirror rewards.php) so the sheet shows even if state fails.
const Map<String, List<int>> _fallbackCost = {
  'customization': [30, 7], 'shield': [60, 7], 'cyber': [120, 7],
  'devtools': [100, 7], 'speeddial': [25, 7], 'cookie': [30, 7],
  'business': [150, 30],
};

IconData _featureIcon(String key) {
  switch (key) {
    case 'customization': return Icons.palette_rounded;
    case 'shield':        return Icons.shield_rounded;
    case 'cyber':         return Icons.security_rounded;
    case 'devtools':      return Icons.code_rounded;
    case 'speeddial':     return Icons.dashboard_customize_rounded;
    case 'cookie':        return Icons.cookie_rounded;
    case 'business':      return Icons.storefront_rounded;
    default:              return Icons.lock_rounded;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
class FeatureLockScreen extends StatelessWidget {
  final String featureKey;
  final VoidCallback onUnlocked;
  const FeatureLockScreen({
    super.key, required this.featureKey, required this.onUnlocked,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      appBar: AppBar(
        backgroundColor: Colors.transparent, elevation: 0,
        title: Text(RewardFeature.label(featureKey),
            style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700)),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: _UnlockBody(
            featureKey: featureKey,
            onUnlocked: onUnlocked,
            compact: false,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
Future<void> showFeatureUnlockSheet(
    BuildContext context, String featureKey, {VoidCallback? onUnlocked}) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => Container(
      decoration: const BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
          24, 16, 24, 24 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 18),
          decoration: BoxDecoration(color: AppTheme.textHint,
              borderRadius: BorderRadius.circular(2))),
        _UnlockBody(
          featureKey: featureKey,
          onUnlocked: () { Navigator.pop(context); if (onUnlocked != null) onUnlocked(); },
          compact: true,
        ),
      ]),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
class _UnlockBody extends StatefulWidget {
  final String featureKey;
  final VoidCallback onUnlocked;
  final bool compact;
  const _UnlockBody({
    required this.featureKey, required this.onUnlocked, required this.compact,
  });
  @override
  State<_UnlockBody> createState() => _UnlockBodyState();
}

class _UnlockBodyState extends State<_UnlockBody> {
  int? _balance;
  int _cost = 0;
  int _days = 0;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final fb = _fallbackCost[widget.featureKey] ?? [0, 7];
    _cost = fb[0];
    _days = fb[1];
    _loadState();
  }

  Future<void> _loadState() async {
    // Confirm against the server first — if the user really has access
    // (e.g. an active trial not yet in the local cache), unlock immediately
    // so they're never wrongly asked to pay.
    await RewardsEntitlements.refresh();
    if (!mounted) return;
    if (RewardsEntitlements.isUnlocked(widget.featureKey)) {
      widget.onUnlocked();
      return;
    }
    final s = await RewardsService.fetchState();
    if (!mounted || s == null) return;
    final cat = s.catalog[widget.featureKey];
    setState(() {
      _balance = s.balance;
      if (cat != null) { _cost = cat.cost; _days = cat.days; }
    });
  }

  Future<void> _unlock() async {
    setState(() => _busy = true);
    final r = await RewardsService.redeem(widget.featureKey);
    if (!mounted) return;
    setState(() => _busy = false);

    if (r.success) {
      await RewardsEntitlements.setExpiry(widget.featureKey, r.expiresAt);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(r.message.isNotEmpty ? r.message : 'Unlocked! 🎉',
            style: GoogleFonts.inter(color: Colors.white)),
        backgroundColor: AppTheme.success,
        behavior: SnackBarBehavior.floating,
      ));
      widget.onUnlocked();
    } else {
      final goEarn = r.reason == 'insufficient';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(r.message.isNotEmpty ? r.message : 'Could not unlock.',
            style: GoogleFonts.inter(color: Colors.white)),
        backgroundColor: AppTheme.danger,
        behavior: SnackBarBehavior.floating,
        action: goEarn
            ? SnackBarAction(label: 'EARN', textColor: kGold, onPressed: () {
                Navigator.push(context, MaterialPageRoute(
                    builder: (_) => const RewardsScreen()));
              })
            : null,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final canAfford = _balance == null || _balance! >= _cost;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 92, height: 92,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(colors: [kGold, Color(0xFFFFA000)]),
          boxShadow: [BoxShadow(color: kGold.withOpacity(.35),
              blurRadius: 30, spreadRadius: 2)],
        ),
        child: Icon(_featureIcon(widget.featureKey),
            color: Colors.black87, size: 46),
      ),
      const SizedBox(height: 18),
      Text('${RewardFeature.label(widget.featureKey)} is locked',
          textAlign: TextAlign.center,
          style: GoogleFonts.spaceGrotesk(
              color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      Text('Unlock it with points to use it for $_days days.',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 13.5)),
      const SizedBox(height: 20),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.bgElevated, borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kGold.withOpacity(.3)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.monetization_on_rounded, color: kGold, size: 22),
          const SizedBox(width: 8),
          Text('$_cost points',
              style: GoogleFonts.spaceGrotesk(
                  color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(width: 10),
          Container(width: 1, height: 18, color: AppTheme.divider),
          const SizedBox(width: 10),
          Text('$_days days',
              style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 13)),
        ]),
      ),
      if (_balance != null) ...[
        const SizedBox(height: 10),
        Text('Your balance: $_balance points',
            style: GoogleFonts.inter(
                color: canAfford ? AppTheme.textSecondary : AppTheme.danger,
                fontSize: 12.5)),
      ],
      const SizedBox(height: 22),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _busy ? null : _unlock,
          style: ElevatedButton.styleFrom(
            backgroundColor: kGold, foregroundColor: Colors.black87,
            padding: const EdgeInsets.symmetric(vertical: 15),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          child: _busy
              ? const SizedBox(width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black54))
              : Text(canAfford ? 'Unlock for $_cost points' : 'Get more points',
                  style: GoogleFonts.spaceGrotesk(
                      fontWeight: FontWeight.w700, fontSize: 15)),
        ),
      ),
      const SizedBox(height: 10),
      TextButton(
        onPressed: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const RewardsScreen())),
        child: Text('Open Rewards to earn points',
            style: GoogleFonts.inter(color: kGold, fontSize: 13)),
      ),
    ]);
  }
}
