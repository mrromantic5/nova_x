// lib/features/rewards/screens/rewards_screen.dart
//
// NOVA X Rewards — premium golden dashboard.
//   • Total points + today's gains
//   • Earn / Redeem toggle
//   • 9 task cards (state-aware claim buttons)
//   • 7 redeemable feature cards (Unlock / Active · Nd left)

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/rewards_service.dart';
import '../../../core/services/rewards_entitlements.dart';

const Color _gold     = Color(0xFFFFC83D);
const Color _goldDeep = Color(0xFFFFA000);
const Color _goldSoft = Color(0xFFFFE08A);

class RewardsScreen extends StatefulWidget {
  const RewardsScreen({super.key});
  @override
  State<RewardsScreen> createState() => _RewardsScreenState();
}

class _RewardsScreenState extends State<RewardsScreen>
    with SingleTickerProviderStateMixin {
  RewardsState? _state;
  bool _loading = true;
  bool _earnTab = true;
  String? _busyKey; // task/feature currently being claimed/redeemed

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await RewardsService.fetchState();
    if (!mounted) return;
    setState(() { _state = s; _loading = false; });
  }

  // ── Task ordering for the Earn tab ──────────────────────────────────────
  static const _taskOrder = [
    RewardTaskKey.dailyClaim,
    RewardTaskKey.dailyStreak,
    RewardTaskKey.browse10min,
    RewardTaskKey.businessClicks,
    RewardTaskKey.readNews,
    RewardTaskKey.openNotifications,
    RewardTaskKey.useAi,
    RewardTaskKey.visualSearch,
    RewardTaskKey.defaultBrowser,
    RewardTaskKey.completeProfile,
  ];

  static const _featureOrder = [
    RewardFeature.customization, RewardFeature.shield, RewardFeature.cyber,
    RewardFeature.devtools, RewardFeature.speeddial, RewardFeature.cookie,
    RewardFeature.business,
  ];

  // These tasks cannot be claimed by a button — they auto-award only when the
  // user genuinely performs the action in the app. Card shows Locked → Claimed.
  static const _autoTasks = {
    RewardTaskKey.readNews,
    RewardTaskKey.useAi,
    RewardTaskKey.visualSearch,
    RewardTaskKey.defaultBrowser,
    RewardTaskKey.completeProfile,
  };

  // ── Claim / redeem ──────────────────────────────────────────────────────
  Future<void> _doClaim(String taskKey) async {
    if (_busyKey != null) return;
    setState(() => _busyKey = taskKey);
    final RewardResult r = taskKey == RewardTaskKey.dailyClaim
        ? await RewardsService.claimDaily()
        : await RewardsService.earn(taskKey);
    if (!mounted) return;
    setState(() => _busyKey = null);
    _toast(r.message, r.success);
    if (r.success && taskKey == RewardTaskKey.dailyClaim) _celebrate(r.points);
    await _load();
  }

  Future<void> _doRedeem(String featureKey, int cost) async {
    if (_busyKey != null) return;
    setState(() => _busyKey = featureKey);
    final r = await RewardsService.redeem(featureKey);
    if (!mounted) return;
    setState(() => _busyKey = null);
    if (r.success) await RewardsEntitlements.setExpiry(featureKey, r.expiresAt);
    _toast(r.message, r.success);
    await _load();
  }

  void _toast(String msg, bool ok) {
    if (msg.isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.inter(color: Colors.white)),
      backgroundColor: ok ? AppTheme.success : AppTheme.bgElevated,
      behavior: SnackBarBehavior.floating,
    ));
  }

  void _celebrate(int pts) {
    showDialog(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: AppTheme.bgCard, borderRadius: BorderRadius.circular(24),
            border: Border.all(color: _gold.withOpacity(.4)),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('🎉', style: TextStyle(fontSize: 56)),
            const SizedBox(height: 12),
            Text('+$pts points!',
                style: GoogleFonts.spaceGrotesk(
                    color: _gold, fontSize: 26, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text('See you tomorrow — be early to grab a slot! ⏰',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(color: AppTheme.textSecondary)),
            const SizedBox(height: 18),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                  backgroundColor: _gold, foregroundColor: Colors.black87),
              child: Text('Awesome',
                  style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700)),
            ),
          ]),
        ),
      ),
    );
  }

  // ── Build ───────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      appBar: AppBar(
        backgroundColor: Colors.transparent, elevation: 0,
        title: Text('Rewards',
            style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w800)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _gold))
          : RefreshIndicator(
              color: _gold,
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  _dashboard(),
                  const SizedBox(height: 18),
                  _toggle(),
                  const SizedBox(height: 16),
                  if (_earnTab) ..._earnCards() else ..._redeemCards(),
                ],
              ),
            ),
    );
  }

  // ── Dashboard header ────────────────────────────────────────────────────
  Widget _dashboard() {
    final bal = _state?.balance ?? 0;
    final today = _state?.todayGained ?? 0;
    final life = _state?.lifetimeEarned ?? 0;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2A2410), Color(0xFF1A1606)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _gold.withOpacity(.35)),
        boxShadow: [BoxShadow(color: _gold.withOpacity(.12),
            blurRadius: 28, spreadRadius: 1)],
      ),
      child: Column(children: [
        Row(children: [
          Container(
            width: 54, height: 54,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(colors: [_goldSoft, _goldDeep]),
              boxShadow: [BoxShadow(color: _gold.withOpacity(.5), blurRadius: 18)],
            ),
            child: const Icon(Icons.monetization_on_rounded,
                color: Colors.white, size: 30),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Total points',
                  style: GoogleFonts.inter(
                      color: AppTheme.textSecondary, fontSize: 12.5)),
              const SizedBox(height: 2),
              Text('$bal',
                  style: GoogleFonts.spaceGrotesk(
                      color: Colors.white, fontSize: 34, fontWeight: FontWeight.w800,
                      height: 1.05)),
            ]),
          ),
          if (today > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: _gold.withOpacity(.18),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _gold.withOpacity(.4)),
              ),
              child: Text('+$today today',
                  style: GoogleFonts.spaceGrotesk(
                      color: _gold, fontWeight: FontWeight.w700, fontSize: 13)),
            ),
        ]),
        const SizedBox(height: 16),
        Row(children: [
          _miniStat('Today', '+$today'),
          const SizedBox(width: 12),
          _miniStat('Lifetime', '$life'),
        ]),
      ]),
    );
  }

  Widget _miniStat(String label, String value) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(.05),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(children: [
            Text(value,
                style: GoogleFonts.spaceGrotesk(
                    color: _goldSoft, fontSize: 18, fontWeight: FontWeight.w700)),
            Text(label,
                style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 11.5)),
          ]),
        ),
      );

  // ── Earn / Redeem toggle ────────────────────────────────────────────────
  Widget _toggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppTheme.bgCard, borderRadius: BorderRadius.circular(14),
      ),
      child: Row(children: [
        _toggleBtn('Earn', _earnTab, () => setState(() => _earnTab = true)),
        _toggleBtn('Redeem', !_earnTab, () => setState(() => _earnTab = false)),
      ]),
    );
  }

  Widget _toggleBtn(String label, bool active, VoidCallback onTap) => Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              gradient: active
                  ? const LinearGradient(colors: [_gold, _goldDeep])
                  : null,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Center(
              child: Text(label,
                  style: GoogleFonts.spaceGrotesk(
                      color: active ? Colors.black87 : AppTheme.textSecondary,
                      fontWeight: FontWeight.w700, fontSize: 14.5)),
            ),
          ),
        ),
      );

  // ── Earn cards ──────────────────────────────────────────────────────────
  List<Widget> _earnCards() {
    final tasks = _state?.tasks ?? {};
    final out = <Widget>[];
    for (final key in _taskOrder) {
      final t = tasks[key];
      if (t == null) continue;
      out.add(_taskCard(key, t));
      out.add(const SizedBox(height: 12));
    }
    return out;
  }

  Map<String, dynamic> _meta(String key) {
    switch (key) {
      case RewardTaskKey.dailyClaim:
        return {'icon': Icons.bolt_rounded, 'title': 'Daily reward',
          'sub': 'First 5 people each day win 5 points'};
      case RewardTaskKey.dailyStreak:
        return {'icon': Icons.local_fire_department_rounded, 'title': 'Daily streak',
          'sub': 'Finish all daily tasks for a bonus'};
      case RewardTaskKey.browse10min:
        return {'icon': Icons.public_rounded, 'title': 'Browse 10 minutes',
          'sub': 'Browse with NOVA X today'};
      case RewardTaskKey.businessClicks:
        return {'icon': Icons.storefront_rounded, 'title': 'Explore businesses',
          'sub': 'Open 3 different businesses'};
      case RewardTaskKey.readNews:
        return {'icon': Icons.article_rounded, 'title': 'Read the news',
          'sub': 'Read up to 3 articles (1 pt each)'};
      case RewardTaskKey.openNotifications:
        return {'icon': Icons.notifications_rounded, 'title': 'Check notifications',
          'sub': 'Open 5 notifications'};
      case RewardTaskKey.useAi:
        return {'icon': Icons.auto_awesome_rounded, 'title': 'Use NOVA AI',
          'sub': 'Ask the AI assistant something'};
      case RewardTaskKey.visualSearch:
        return {'icon': Icons.center_focus_strong_rounded, 'title': 'Visual search',
          'sub': 'Search the web with an image'};
      case RewardTaskKey.completeProfile:
        return {'icon': Icons.person_rounded, 'title': 'Complete your profile',
          'sub': 'One-time reward'};
      case RewardTaskKey.defaultBrowser:
        return {'icon': Icons.public_rounded, 'title': 'Make NOVA X your default browser',
          'sub': 'One-time reward — set it in the popup or Settings'};
      default:
        return {'icon': Icons.star_rounded, 'title': key, 'sub': ''};
    }
  }

  Widget _taskCard(String key, RewardTask t) {
    final meta = _meta(key);
    final busy = _busyKey == key;

    // Progress / sub-status text
    String? progress;
    double? bar;
    if (key == RewardTaskKey.dailyClaim) {
      final left = t.i('slots_left');
      progress = t.done ? 'Claimed — slot #${t.i('my_slot')}' : '$left of 5 slots left today';
    } else if (key == RewardTaskKey.browse10min) {
      final sec = t.i('progress_sec'); bar = (sec / 600).clamp(0, 1).toDouble();
      progress = '${(sec / 60).floor()}/10 min';
    } else if (key == RewardTaskKey.businessClicks) {
      progress = '${t.i('count')}/${t.i('target', 3)} opened';
    } else if (key == RewardTaskKey.readNews) {
      progress = '${t.i('count')}/${t.i('max', 3)} read today';
    } else if (key == RewardTaskKey.openNotifications) {
      progress = '${t.i('count')}/${t.i('target', 5)} opened';
    }

    final done = t.done;
    final claimable = t.claimable;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bgCard, borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: claimable ? _gold.withOpacity(.45) : AppTheme.glassBorder),
      ),
      child: Column(children: [
        Row(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: _gold.withOpacity(.14), borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(meta['icon'] as IconData, color: _gold, size: 23),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(meta['title'] as String,
                  style: GoogleFonts.spaceGrotesk(
                      color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(meta['sub'] as String,
                  style: GoogleFonts.inter(
                      color: AppTheme.textHint, fontSize: 12), maxLines: 2,
                  overflow: TextOverflow.ellipsis),
            ]),
          ),
          const SizedBox(width: 8),
          Row(children: [
            const Icon(Icons.monetization_on_rounded, color: _gold, size: 17),
            const SizedBox(width: 3),
            Text('${t.points}',
                style: GoogleFonts.spaceGrotesk(
                    color: _gold, fontWeight: FontWeight.w800, fontSize: 15)),
          ]),
        ]),
        if (bar != null) ...[
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: bar, minHeight: 6,
              backgroundColor: AppTheme.bgElevated,
              valueColor: const AlwaysStoppedAnimation(_gold),
            ),
          ),
        ],
        const SizedBox(height: 12),
        Row(children: [
          if (progress != null)
            Expanded(
              child: Text(progress,
                  style: GoogleFonts.inter(
                      color: AppTheme.textSecondary, fontSize: 12.5)),
            )
          else
            const Spacer(),
          if (_autoTasks.contains(key))
            _autoStatus(done)
          else
            _claimButton(key, done, claimable, busy),
        ]),
      ]),
    );
  }

  // Non-tappable status for auto-award tasks (earned by doing the real action).
  Widget _autoStatus(bool done) {
    if (done) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: AppTheme.success.withOpacity(.15),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.check_circle_rounded, color: AppTheme.success, size: 16),
          const SizedBox(width: 5),
          Text('Claimed',
              style: GoogleFonts.spaceGrotesk(
                  color: AppTheme.success, fontWeight: FontWeight.w700, fontSize: 13)),
        ]),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: AppTheme.bgElevated, borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.lock_outline_rounded, color: AppTheme.textHint, size: 15),
        const SizedBox(width: 5),
        Text('Locked',
            style: GoogleFonts.spaceGrotesk(
                color: AppTheme.textHint, fontWeight: FontWeight.w700, fontSize: 13)),
      ]),
    );
  }

  Widget _claimButton(String key, bool done, bool claimable, bool busy) {
    if (done) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: AppTheme.success.withOpacity(.15),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.check_circle_rounded, color: AppTheme.success, size: 16),
          const SizedBox(width: 5),
          Text('Claimed',
              style: GoogleFonts.spaceGrotesk(
                  color: AppTheme.success, fontWeight: FontWeight.w700, fontSize: 13)),
        ]),
      );
    }
    final enabled = claimable && !busy;
    return GestureDetector(
      onTap: enabled ? () => _doClaim(key) : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
        decoration: BoxDecoration(
          gradient: enabled
              ? const LinearGradient(colors: [_gold, _goldDeep]) : null,
          color: enabled ? null : AppTheme.bgElevated,
          borderRadius: BorderRadius.circular(20),
        ),
        child: busy
            ? const SizedBox(width: 15, height: 15,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black54))
            : Text(claimable ? 'Claim' : 'Locked',
                style: GoogleFonts.spaceGrotesk(
                    color: enabled ? Colors.black87 : AppTheme.textHint,
                    fontWeight: FontWeight.w700, fontSize: 13.5)),
      ),
    );
  }

  // ── Redeem cards ────────────────────────────────────────────────────────
  List<Widget> _redeemCards() {
    final cat = _state?.catalog ?? {};
    final out = <Widget>[
      Padding(
        padding: const EdgeInsets.only(bottom: 6, left: 4),
        child: Text('Unlock premium features with your points.',
            style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 13)),
      ),
    ];
    for (final key in _featureOrder) {
      final item = cat[key];
      if (item == null) continue;
      out.add(_featureCard(key, item));
      out.add(const SizedBox(height: 12));
    }
    return out;
  }

  IconData _featIcon(String key) {
    switch (key) {
      case RewardFeature.customization: return Icons.palette_rounded;
      case RewardFeature.shield:        return Icons.shield_rounded;
      case RewardFeature.cyber:         return Icons.security_rounded;
      case RewardFeature.devtools:      return Icons.code_rounded;
      case RewardFeature.speeddial:     return Icons.dashboard_customize_rounded;
      case RewardFeature.cookie:        return Icons.cookie_rounded;
      case RewardFeature.business:      return Icons.storefront_rounded;
      default:                          return Icons.star_rounded;
    }
  }

  Widget _featureCard(String key, FeatureCatalogItem item) {
    final unlocked = RewardsEntitlements.isUnlocked(key);
    final status = RewardsEntitlements.statusLabel(key);
    final busy = _busyKey == key;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bgCard, borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: unlocked ? AppTheme.success.withOpacity(.4) : AppTheme.glassBorder),
      ),
      child: Row(children: [
        Container(
          width: 46, height: 46,
          decoration: BoxDecoration(
            color: (unlocked ? AppTheme.success : _gold).withOpacity(.14),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(_featIcon(key),
              color: unlocked ? AppTheme.success : _gold, size: 24),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(RewardFeature.label(key),
                style: GoogleFonts.spaceGrotesk(
                    color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 3),
            Row(children: [
              const Icon(Icons.monetization_on_rounded, color: _gold, size: 15),
              const SizedBox(width: 3),
              Text('${item.cost}',
                  style: GoogleFonts.spaceGrotesk(
                      color: _gold, fontWeight: FontWeight.w700, fontSize: 13)),
              Text('  ·  ${item.days} days',
                  style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 12)),
            ]),
          ]),
        ),
        const SizedBox(width: 8),
        if (unlocked)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.success.withOpacity(.15),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(status,
                style: GoogleFonts.spaceGrotesk(
                    color: AppTheme.success, fontWeight: FontWeight.w700, fontSize: 12.5)),
          )
        else
          GestureDetector(
            onTap: busy ? null : () => _doRedeem(key, item.cost),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [_gold, _goldDeep]),
                borderRadius: BorderRadius.circular(20),
              ),
              child: busy
                  ? const SizedBox(width: 15, height: 15,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black54))
                  : Text('Unlock',
                      style: GoogleFonts.spaceGrotesk(
                          color: Colors.black87, fontWeight: FontWeight.w700, fontSize: 13.5)),
            ),
          ),
      ]),
    );
  }
}
