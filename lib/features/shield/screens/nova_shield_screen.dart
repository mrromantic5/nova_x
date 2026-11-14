// lib/features/shield/screens/nova_shield_screen.dart
import 'package:nova_x/core/services/rewards_entitlements.dart';
import 'package:nova_x/core/services/rewards_service.dart';
import 'package:nova_x/core/widgets/feature_lock.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nova_x/core/services/nova_shield_service.dart';
import 'package:nova_x/core/theme/app_theme.dart';
import 'package:nova_x/features/guide/guide_screen.dart';
import 'package:nova_x/features/security/security_center_screen.dart';
import 'package:nova_x/features/security/site_controls.dart';
import 'package:nova_x/features/shield/engine/shield_engine.dart';
import 'package:nova_x/features/shield/engine/shield_lists.dart';

class NovaShieldScreen extends StatefulWidget {
  const NovaShieldScreen({super.key});
  @override State<NovaShieldScreen> createState() => _NovaShieldScreenState();
}

class _NovaShieldScreenState extends State<NovaShieldScreen>
    with TickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late AnimationController _scoreCtrl;
  late Animation<double>   _scoreAnim;
  bool _loading = false;

  bool _updatingLists = false;

  @override
  void initState() {
    super.initState();
    // 3.13.0: real numbers only (blocked requests come from NOVA Shield).
    NovaShieldEngine.instance.ensureReady().then((_) { if (mounted) setState(() {}); });
    SiteControls.instance.ensureLoaded().then((_) { if (mounted) setState(() {}); });
    _pulseCtrl = AnimationController(vsync: this,
        duration: const Duration(seconds: 3))..repeat(reverse: true);
    _scoreCtrl = AnimationController(vsync: this,
        duration: const Duration(milliseconds: 1200));
    _scoreAnim = Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: _scoreCtrl, curve: Curves.easeOutCubic));
    _scoreCtrl.forward();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose(); _scoreCtrl.dispose(); super.dispose();
  }

  Future<void> _toggle(bool v) async {
    await NovaShieldService.setEnabled(v);
    setState(() {}); _scoreCtrl.forward(from: 0);
  }

  /// 3.9.0: NOVA Shield is free; the Pro layers unlock with coins or Premium.
  bool get _pro => RewardsEntitlements.isUnlocked(RewardFeature.shield);

  Future<void> _unlockPro() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (ctx) => FeatureLockScreen(
        featureKey: RewardFeature.shield,
        onUnlocked: () => Navigator.of(ctx).maybePop(),
      ),
    ));
    if (mounted) {
      setState(() {});
      _scoreCtrl.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled  = NovaShieldService.isEnabled;
    final stats    = NovaShieldService.stats;
    final engine   = NovaShieldEngine.instance;
    final fpOn     = SiteControls.instance.fingerprintDefault != FingerprintLevel.off;
    const scoreColor = AppTheme.accentCyan;

    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      body: Stack(children: [
        // Background glow
        Positioned(top: -80, left: -80, child: _glow(
            AppTheme.accentCyan.withOpacity(enabled ? 0.08 : 0.02), 350)),
        Positioned(bottom: 100, right: -100, child: _glow(
            AppTheme.accentPurple.withOpacity(enabled ? 0.06 : 0.01), 280)),

        CustomScrollView(slivers: [

          // ── App Bar ───────────────────────────────────────────────────────
          SliverAppBar(
            pinned: true, expandedHeight: 220,
            backgroundColor: AppTheme.bgDark, elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: Colors.white, size: 18),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              // Reset stats
              TextButton(
                onPressed: () async {
                  await NovaShieldService.resetStats();
                  await NovaShieldEngine.instance.resetLifetime();
                  setState(() {});
                },
                child: Text('Reset Stats', style: GoogleFonts.inter(
                    color: AppTheme.textHint, fontSize: 12)),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter, end: Alignment.bottomCenter,
                    colors: [Color(0xFF04080F), AppTheme.bgDark],
                  ),
                ),
                child: SafeArea(child: Padding(
                  padding: const EdgeInsets.fromLTRB(72, 16, 24, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(children: [
                        _tag('PRIVACY & SECURITY', AppTheme.accentCyan),
                      ]),
                      const SizedBox(height: 8),
                      ShaderMask(
                        shaderCallback: (r) => const LinearGradient(
                          colors: [AppTheme.accentCyan, AppTheme.accentPurple],
                        ).createShader(r),
                        child: Text('NOVA Shield',
                            style: GoogleFonts.spaceGrotesk(
                                color: Colors.white, fontSize: 30,
                                fontWeight: FontWeight.w900)),
                      ),
                      Text('Malware check  •  HTTPS upgrade  •  Ad & tracker blocking',
                          style: GoogleFonts.inter(
                              color: AppTheme.textHint, fontSize: 11)),
                    ],
                  ),
                )),
              ),
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
            sliver: SliverList(delegate: SliverChildListDelegate([

              // ── Real numbers (3.13.0: the old score wasn't a measurement) ──
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Row(children: [
                  Expanded(child: _bigNumber('${engine.blockedToday()}', 'ads & trackers\nblocked today', scoreColor)),
                  Expanded(child: _bigNumber('${stats.malwareBlocked}', 'dangerous sites\nstopped', AppTheme.danger)),
                ]),
              ),

              // ── Master toggle ──────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(20),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: enabled
                        ? [AppTheme.accentCyan.withOpacity(0.12),
                           AppTheme.accentPurple.withOpacity(0.08)]
                        : [AppTheme.bgCard, AppTheme.bgCard],
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: enabled
                        ? AppTheme.accentCyan.withOpacity(0.35)
                        : AppTheme.divider,
                    width: enabled ? 1.5 : 1,
                  ),
                ),
                child: Row(children: [
                  Container(width: 48, height: 48,
                    decoration: BoxDecoration(
                      gradient: enabled ? AppTheme.primaryGradient : null,
                      color: enabled ? null : AppTheme.bgElevated,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: enabled ? AppTheme.glowShadow : null,
                    ),
                    child: Icon(Icons.shield_rounded,
                        color: Colors.white, size: 24)),
                  const SizedBox(width: 14),
                  Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text('NOVA Shield', style: GoogleFonts.spaceGrotesk(
                        color: AppTheme.textPrimary, fontSize: 17,
                        fontWeight: FontWeight.w800)),
                    Text(enabled
                        ? 'Malware check${NovaShieldService.httpsOnlyEnabled ? ' and HTTPS upgrade' : ''} on'
                        : 'Malware check off',
                        style: GoogleFonts.inter(
                            color: enabled
                                ? AppTheme.accentCyan : AppTheme.textHint,
                            fontSize: 12)),
                  ])),
                  Switch(
                    value: enabled,
                    onChanged: _toggle,
                    activeColor: AppTheme.accentCyan,
                  ),
                ]),
              ),

              // ── Stats row ──────────────────────────────────────────────
              _sectionLabel('PROTECTION STATS'),
              const SizedBox(height: 10),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 2.2,
                children: [
                  _statCard('${stats.malwareBlocked}',   'Malware Blocked',   Icons.dangerous_rounded,       AppTheme.danger),
                  _statCard('${stats.httpsUpgrades}',    'HTTPS Upgrades',    Icons.lock_rounded,             AppTheme.success),
                  _statCard('${stats.dnsEncrypted}',     'Sites Checked',     Icons.dns_rounded,              AppTheme.accentCyan),
                  _statCard('${engine.lifetimeTotal}',   'Ads & Trackers Blocked', Icons.block_rounded,       AppTheme.accentPurple),
                ],
              ),
              const SizedBox(height: 24),

              if (!_pro) ...[
                _proBanner(),
                const SizedBox(height: 24),
              ],

              // ── DNS Provider ───────────────────────────────────────────
              _sectionLabel(_pro ? 'DNS PROVIDER' : 'DNS PROVIDER  ·  CHOICE IS PRO'),
              const SizedBox(height: 10),
              ...NovaShieldService.providers.entries.map((e) =>
                  _dnsProviderTile(e.key, e.value)),
              const SizedBox(height: 24),

              // ── Protection layers ──────────────────────────────────────
              _sectionLabel('PROTECTION LAYERS'),
              const SizedBox(height: 10),
              _card([
                _layerTile(
                  Icons.cloud_rounded, 'Malware check (encrypted DNS)',
                  'Each site you open is looked up over HTTPS with the provider above; known malware sites are stopped',
                  AppTheme.accentCyan, true, null, // always on when shield is on
                ),
                _divider(),
                _layerTile(
                  Icons.block_rounded, 'Ad & tracker blocking',
                  engine.enabled
                      ? '${engine.ruleCount} EasyList / EasyPrivacy domains · ${engine.lifetimeTotal} requests blocked so far'
                      : 'Blocks ad, tracker and cryptominer requests from other companies',
                  AppTheme.success, engine.enabled,
                  (v) async { await engine.setEnabled(v); setState(() {}); },
                ),
                _divider(),
                _layerTile(
                  Icons.lock_rounded, 'HTTPS Enforcement',
                  'Upgrades all HTTP connections to HTTPS automatically',
                  AppTheme.success, NovaShieldService.httpsOnlyEnabled,
                  (v) async { await NovaShieldService.setHttpsOnly(v); setState(() {}); },
                ),
                _divider(),
                _layerTile(
                  Icons.hide_source_rounded, 'WebRTC Leak Prevention',
                  'Prevents websites from discovering your real IP via WebRTC',
                  AppTheme.accentPurple, NovaShieldService.webrtcBlocking,
                  (v) async { await NovaShieldService.setWebrtcBlocking(v); setState(() {}); },
                  pro: true,
                ),
                _divider(),
                _layerTile(
                  Icons.fingerprint_rounded, 'Fingerprint protection',
                  'Each site sees slightly different canvas and audio values, so visits can’t be linked '
                      '(${SiteControls.instance.fingerprintDefault.label}; strict and per-site levels in the Security Center)',
                  AppTheme.warning, fpOn,
                  (v) async {
                    await SiteControls.instance.setFingerprintDefault(v ? FingerprintLevel.standard : FingerprintLevel.off);
                    setState(() {});
                  },
                ),
                _divider(),
                _layerTile(
                  Icons.link_off_rounded, 'Referrer Privacy',
                  'Hides which pages you came from — prevents cross-site tracking',
                  AppTheme.accentCyan, NovaShieldService.referrerSpoofing,
                  (v) async { await NovaShieldService.setReferrerSpoofing(v); setState(() {}); },
                  pro: true,
                ),
              ]),
              const SizedBox(height: 24),

              _listsCard(),
              const SizedBox(height: 20),

              // ── Footer note ────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.bgCard,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.divider),
                ),
                child: Row(children: [
                  const Icon(Icons.info_outline_rounded,
                      color: AppTheme.textHint, size: 16),
                  const SizedBox(width: 10),
                  Expanded(child: Text(
                    'NOVA Shield works only inside the NOVA X browser; other apps are never affected. '
                    'The malware check sends only the site’s name to the chosen DNS provider, over HTTPS. '
                    'Pages themselves load with Android’s normal network settings. No browsing data is sent to Tech Lyfe.',
                    style: GoogleFonts.inter(color: AppTheme.textHint,
                        fontSize: 11, height: 1.5),
                  )),
                ]),
              ),
            ])),
          ),
        ]),
      ]),
    );
  }

  // ── DNS provider tile ──────────────────────────────────────────────────────
  Widget _dnsProviderTile(DnsProvider provider, DnsProviderInfo info) {
    final selected = NovaShieldService.activeProvider == provider;
    final locked = !_pro && provider != DnsProvider.cloudflareMalware;
    return GestureDetector(
      onTap: () async {
        if (locked) {
          await _unlockPro();
          return;
        }
        await NovaShieldService.setProvider(provider);
        setState(() {}); _scoreCtrl.forward(from: 0);
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.accentCyan.withOpacity(0.08)
              : AppTheme.bgCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? AppTheme.accentCyan.withOpacity(0.4) : AppTheme.divider,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(children: [
          Container(width: 40, height: 40,
            decoration: BoxDecoration(
              gradient: selected ? AppTheme.primaryGradient : null,
              color: selected ? null : AppTheme.bgElevated,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.dns_rounded, color: Colors.white, size: 18)),
          const SizedBox(width: 12),
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(info.name, style: GoogleFonts.spaceGrotesk(
                  color: AppTheme.textPrimary, fontSize: 13,
                  fontWeight: FontWeight.w700)),
              const SizedBox(width: 8),
              _tag(info.badge, selected ? AppTheme.accentCyan : AppTheme.textHint),
            ]),
            Text(info.description, style: GoogleFonts.inter(
                color: AppTheme.textHint, fontSize: 11)),
          ])),
          if (selected)
            const Icon(Icons.check_circle_rounded,
                color: AppTheme.accentCyan, size: 20)
          else if (locked)
            const Icon(Icons.lock_rounded, color: Color(0xFFFFC83D), size: 18),
        ]),
      ),
    );
  }

  // ── Block lists (3.13.0) ──────────────────────────────────────────────────
  Widget _listsCard() {
    final lists = ShieldLists.instance.current;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.list_alt_rounded, color: AppTheme.accentCyan, size: 16),
          const SizedBox(width: 8),
          Expanded(child: Text('About the block lists', style: GoogleFonts.spaceGrotesk(
              color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w800))),
          const ReadMoreLink('shield', compact: true),
        ]),
        const SizedBox(height: 8),
        Text(
          lists == null
              ? 'Loading…'
              : '${lists.countOf(ShieldCategory.ads)} ad · ${lists.countOf(ShieldCategory.trackers)} tracker · '
                '${lists.countOf(ShieldCategory.miners)} cryptominer domains · '
                '${lists.updated == null ? 'snapshot built into NOVA X' : 'updated ${lists.updated!.toLocal().toString().substring(0, 10)}'}',
          style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 12, height: 1.4)),
        const SizedBox(height: 6),
        Text('Lists: EasyList and EasyPrivacy by The EasyList authors (https://easylist.to/), GPLv3 / CC BY-SA 3.0. '
            'Refreshed weekly when online. Only requests to other companies are blocked.',
            style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 11, height: 1.4)),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(
            onPressed: _updatingLists ? null : () async {
              setState(() => _updatingLists = true);
              final ok = await NovaShieldEngine.instance.updateListsNow();
              if (!mounted) return;
              setState(() => _updatingLists = false);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok
                  ? 'Block lists updated'
                  : (ShieldLists.instance.lastUpdateError ?? 'Lists are already up to date'))));
            },
            icon: _updatingLists
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.sync_rounded, size: 16),
            label: const Text('Update now'),
          ),
          OutlinedButton.icon(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SecurityCenterScreen())),
            icon: const Icon(Icons.health_and_safety_rounded, size: 16),
            label: const Text('Security Center'),
          ),
        ]),
      ]),
    );
  }

  Widget _bigNumber(String value, String label, Color color) => Column(children: [
        Text(value, style: GoogleFonts.spaceGrotesk(color: color, fontSize: 34, fontWeight: FontWeight.w900)),
        const SizedBox(height: 2),
        Text(label, textAlign: TextAlign.center,
            style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 11, height: 1.3)),
      ]);

  // ── NOVA Shield Pro (3.9.0) ─────────────────────────────────────────────────
  Widget _proBanner() => GestureDetector(
        onTap: _unlockPro,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(colors: [
              const Color(0xFFFFC83D).withOpacity(0.16),
              AppTheme.accentPurple.withOpacity(0.14),
            ]),
            border: Border.all(color: const Color(0xFFFFC83D).withOpacity(0.35)),
          ),
          child: Row(children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFFFFC83D).withOpacity(0.18),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.workspace_premium_rounded, color: Color(0xFFFFC83D), size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Upgrade to NOVA Shield Pro', style: GoogleFonts.spaceGrotesk(
                  color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w800)),
              const SizedBox(height: 3),
              Text('IP-leak (WebRTC) and referrer protection plus your choice of DNS. '
                  'Unlock with coins or NOVA X Premium.',
                  style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 11.5, height: 1.4)),
            ])),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right_rounded, color: Color(0xFFFFC83D)),
          ]),
        ),
      );

  Widget _lockedLayerTile(IconData icon, String title, String subtitle) => InkWell(
        onTap: _unlockPro,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(children: [
            Container(width: 36, height: 36,
              decoration: BoxDecoration(color: AppTheme.bgElevated, borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: AppTheme.textHint, size: 18)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: GoogleFonts.inter(
                  color: AppTheme.textSecondary, fontSize: 13, fontWeight: FontWeight.w700)),
              Text(subtitle, style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 10, height: 1.4)),
            ])),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFFFC83D).withOpacity(0.14),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFFFC83D).withOpacity(0.4)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.lock_rounded, color: Color(0xFFFFC83D), size: 11),
                const SizedBox(width: 3),
                Text('PRO', style: GoogleFonts.inter(
                    color: const Color(0xFFFFC83D), fontSize: 9, fontWeight: FontWeight.w800)),
              ]),
            ),
          ]),
        ),
      );

  // ── Helpers ────────────────────────────────────────────────────────────────
  Widget _card(List<Widget> children) => Container(
    decoration: BoxDecoration(color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.divider)),
    child: Column(children: children),
  );

  Widget _divider() => const Divider(
      color: Color(0xFF1A2535), height: 1, indent: 16, endIndent: 16);

  Widget _layerTile(IconData icon, String title, String subtitle,
      Color color, bool value, ValueChanged<bool>? onChanged, {bool pro = false}) =>
      (pro && !_pro)
          ? _lockedLayerTile(icon, title, subtitle)
          : Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(children: [
          Container(width: 36, height: 36,
            decoration: BoxDecoration(
              color: value ? color.withOpacity(0.15) : AppTheme.bgElevated,
              borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: value ? color : AppTheme.textHint, size: 18)),
          const SizedBox(width: 12),
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: GoogleFonts.inter(
                color: AppTheme.textPrimary, fontSize: 13,
                fontWeight: FontWeight.w700)),
            Text(subtitle, style: GoogleFonts.inter(
                color: AppTheme.textHint, fontSize: 10, height: 1.4)),
          ])),
          if (onChanged != null)
            Switch(value: value, onChanged: onChanged,
                activeColor: color, materialTapTargetSize:
                MaterialTapTargetSize.shrinkWrap)
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: color.withOpacity(0.3)),
              ),
              child: Text('ALWAYS ON', style: GoogleFonts.inter(
                  color: color, fontSize: 8, fontWeight: FontWeight.w800)),
            ),
        ]),
      );

  Widget _statCard(String value, String label, IconData icon, Color color) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Row(children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value, style: GoogleFonts.spaceGrotesk(
                color: color, fontSize: 20, fontWeight: FontWeight.w900)),
            Text(label, style: GoogleFonts.inter(
                color: color.withOpacity(0.7), fontSize: 9,
                fontWeight: FontWeight.w600)),
          ]),
        ]),
      );

  Widget _sectionLabel(String text) => Text(text, style: GoogleFonts.inter(
      color: AppTheme.textHint, fontSize: 10,
      fontWeight: FontWeight.w800, letterSpacing: 1.2));

  Widget _tag(String t, Color c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: c.withOpacity(0.12), borderRadius: BorderRadius.circular(6),
      border: Border.all(color: c.withOpacity(0.3)),
    ),
    child: Text(t, style: GoogleFonts.inter(
        color: c, fontSize: 8, fontWeight: FontWeight.w800, letterSpacing: .8)),
  );

  Widget _glow(Color c, double s) => Container(
    width: s, height: s,
    decoration: BoxDecoration(shape: BoxShape.circle,
        gradient: RadialGradient(colors: [c, Colors.transparent])));
}
