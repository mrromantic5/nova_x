// lib/features/shield/screens/nova_shield_screen.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nova_x/core/services/nova_shield_service.dart';
import 'package:nova_x/core/theme/app_theme.dart';

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

  @override
  void initState() {
    super.initState();
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

  @override
  Widget build(BuildContext context) {
    final score    = NovaShieldService.protectionScore;
    final level    = NovaShieldService.protectionLevel;
    final enabled  = NovaShieldService.isEnabled;
    final stats    = NovaShieldService.stats;
    final scoreColor = score >= 80 ? AppTheme.success
        : score >= 50 ? AppTheme.warning : AppTheme.danger;

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
                        const SizedBox(width: 8),
                        _tag('STRONGER THAN BRAVE', AppTheme.success),
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
                      Text('7-Layer Protection Engine  •  Encrypted DNS',
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

              // ── Protection score gauge ─────────────────────────────────
              Center(child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: AnimatedBuilder(
                  animation: _scoreAnim,
                  builder: (_, __) => Stack(
                    alignment: Alignment.center,
                    children: [
                      // Pulse ring
                      if (enabled) AnimatedBuilder(
                        animation: _pulseCtrl,
                        builder: (_, __) => Container(
                          width: 160 + _pulseCtrl.value * 20,
                          height: 160 + _pulseCtrl.value * 20,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: scoreColor.withOpacity(
                                  0.15 - _pulseCtrl.value * 0.12),
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                      // Score ring
                      CustomPaint(
                        size: const Size(150, 150),
                        painter: _ScoreRingPainter(
                          progress: _scoreAnim.value,
                          score: score,
                          color: scoreColor,
                        ),
                      ),
                      // Centre content
                      Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(enabled
                            ? Icons.shield_rounded
                            : Icons.shield_outlined,
                            color: enabled ? scoreColor : AppTheme.textHint,
                            size: 28),
                        const SizedBox(height: 4),
                        Text('${(score * _scoreAnim.value).round()}',
                            style: GoogleFonts.spaceGrotesk(
                                color: scoreColor, fontSize: 32,
                                fontWeight: FontWeight.w900)),
                        Text(enabled ? level : 'OFF',
                            style: GoogleFonts.inter(
                                color: scoreColor.withOpacity(0.7),
                                fontSize: 11, fontWeight: FontWeight.w700)),
                      ]),
                    ],
                  ),
                ),
              )),

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
                        ? 'All ${_countActive()} layers active'
                        : 'Protection disabled',
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
                  _statCard('${stats.dnsEncrypted}',     'DNS Encrypted',     Icons.dns_rounded,              AppTheme.accentCyan),
                  _statCard('${stats.webrtcBlocked}',    'IP Leaks Blocked',  Icons.hide_source_rounded,      AppTheme.accentPurple),
                ],
              ),
              const SizedBox(height: 24),

              // ── DNS Provider ───────────────────────────────────────────
              _sectionLabel('DNS PROVIDER'),
              const SizedBox(height: 10),
              ...NovaShieldService.providers.entries.map((e) =>
                  _dnsProviderTile(e.key, e.value)),
              const SizedBox(height: 24),

              // ── Protection layers ──────────────────────────────────────
              _sectionLabel('PROTECTION LAYERS'),
              const SizedBox(height: 10),
              _card([
                _layerTile(
                  Icons.cloud_rounded, 'DNS-over-HTTPS',
                  'All DNS queries encrypted via NOVA DNS',
                  AppTheme.accentCyan, true, null, // always on when shield is on
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
                ),
                _divider(),
                _layerTile(
                  Icons.fingerprint_rounded, 'Fingerprint Noise',
                  'Adds random noise to canvas, audio & screen to defeat fingerprinting',
                  AppTheme.warning, NovaShieldService.fingerprintProtection,
                  (v) async { await NovaShieldService.setFingerprintProtection(v); setState(() {}); },
                ),
                _divider(),
                _layerTile(
                  Icons.link_off_rounded, 'Referrer Privacy',
                  'Hides which pages you came from — prevents cross-site tracking',
                  AppTheme.accentCyan, NovaShieldService.referrerSpoofing,
                  (v) async { await NovaShieldService.setReferrerSpoofing(v); setState(() {}); },
                ),
              ]),
              const SizedBox(height: 24),

              // Comparison table removed — replaced with feature highlights
              _featureHighlightsCard(),
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
                    'NOVA Shield operates entirely within the NOVA X browser. '
                    'It does not encrypt system-wide traffic. '
                    'DNS queries are encrypted end-to-end — no browsing data is sent to Tech Lyfe.',
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
    return GestureDetector(
      onTap: () async {
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
                color: AppTheme.accentCyan, size: 20),
        ]),
      ),
    );
  }

  // ── Feature highlights card ──────────────────────────────────────────────
  Widget _featureHighlightsCard() {
    final features = [
      (Icons.dns_rounded,        'Encrypted DNS',         'All domain lookups encrypted end-to-end',          AppTheme.accentCyan),
      (Icons.dangerous_rounded,  'Malware Blocking',      'Real-time threat intelligence on every domain',     AppTheme.danger),
      (Icons.lock_rounded,       'HTTPS Enforcement',     'Every connection automatically upgraded to HTTPS',  AppTheme.success),
      (Icons.hide_source_rounded,'IP Leak Prevention',    'WebRTC configured to prevent IP address exposure',  AppTheme.accentPurple),
      (Icons.link_off_rounded,   'Referrer Privacy',      'Cross-site tracking via referrer headers blocked',  AppTheme.warning),
      (Icons.fingerprint_rounded,'Fingerprint Protection','Signals privacy preference to all websites',        AppTheme.accentCyan),
    ];
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Row(children: [
            const Icon(Icons.verified_rounded, color: AppTheme.accentCyan, size: 16),
            const SizedBox(width: 8),
            Text('NOVA Shield Features', style: GoogleFonts.spaceGrotesk(
                color: AppTheme.textPrimary, fontSize: 13,
                fontWeight: FontWeight.w800)),
          ]),
        ),
        const Divider(color: Color(0xFF1A2535), height: 1),
        ...features.map((f) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          child: Row(children: [
            Container(width: 36, height: 36,
              decoration: BoxDecoration(
                  color: f.$4.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10)),
              child: Icon(f.$1, color: f.$4, size: 18)),
            const SizedBox(width: 12),
            Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text(f.$2, style: GoogleFonts.inter(
                  color: AppTheme.textPrimary, fontSize: 13,
                  fontWeight: FontWeight.w700)),
              Text(f.$3, style: GoogleFonts.inter(
                  color: AppTheme.textHint, fontSize: 11)),
            ])),
            const Icon(Icons.check_circle_rounded,
                color: AppTheme.success, size: 16),
          ]),
        )).toList(),
      ]),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  // ── Helpers ────────────────────────────────────────────────────────────────
  int _countActive() {
    int n = 1; // DoH always active when shield is on
    if (NovaShieldService.httpsOnlyEnabled)     n++;
    if (NovaShieldService.webrtcBlocking)       n++;
    if (NovaShieldService.fingerprintProtection)n++;
    if (NovaShieldService.referrerSpoofing)     n++;
    return n;
  }

  Widget _card(List<Widget> children) => Container(
    decoration: BoxDecoration(color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.divider)),
    child: Column(children: children),
  );

  Widget _divider() => const Divider(
      color: Color(0xFF1A2535), height: 1, indent: 16, endIndent: 16);

  Widget _layerTile(IconData icon, String title, String subtitle,
      Color color, bool value, ValueChanged<bool>? onChanged) =>
      Padding(
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

// ── Score ring painter ────────────────────────────────────────────────────────
class _ScoreRingPainter extends CustomPainter {
  final double progress; final int score; final Color color;
  const _ScoreRingPainter(
      {required this.progress, required this.score, required this.color});
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width * 0.44;
    const sw = 8.0;
    const start = -math.pi / 2;
    const sweep = math.pi * 2;
    canvas.drawCircle(c, r,
        Paint()..color = color.withOpacity(0.1)
               ..style = PaintingStyle.stroke..strokeWidth = sw);
    canvas.drawArc(Rect.fromCircle(center: c, radius: r),
        start, sweep * progress * (score / 100), false,
        Paint()..shader = SweepGradient(
                startAngle: start, endAngle: start + sweep,
                colors: [color.withOpacity(0.4), color])
            .createShader(Rect.fromCircle(center: c, radius: r))
          ..style = PaintingStyle.stroke
          ..strokeWidth = sw..strokeCap = StrokeCap.round);
  }
  @override bool shouldRepaint(_ScoreRingPainter o) =>
      o.progress != progress || o.score != score;
}
