// lib/features/customization/screens/speed_dial_editor_screen.dart
//
// Speed Dial editor — manage Quick Access shortcuts on the home page.
//   • Current items: tap × to remove
//   • Recommended sites: tap + to add
//   • Custom site form: enter name + URL to add anything

import 'package:flutter/material.dart';
import 'package:nova_x/core/services/rewards_entitlements.dart';
import 'package:nova_x/core/services/rewards_service.dart';
import 'package:nova_x/core/widgets/feature_lock.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nova_x/core/database/local_db.dart';
import 'package:nova_x/core/theme/app_theme.dart';

class SpeedDialEditorScreen extends StatefulWidget {
  const SpeedDialEditorScreen({super.key});
  @override
  State<SpeedDialEditorScreen> createState() => _SpeedDialEditorScreenState();
}

class _SpeedDialEditorScreenState extends State<SpeedDialEditorScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;
  late Animation<double>   _fadeAnim;

  List<Map<String, dynamic>> _current = [];

  static const List<Map<String, dynamic>> _recommended = [
    {'name': 'Reddit',         'url': 'https://reddit.com',         'domain': 'reddit.com'},
    {'name': 'Amazon',         'url': 'https://amazon.com',         'domain': 'amazon.com'},
    {'name': 'Netflix',        'url': 'https://netflix.com',        'domain': 'netflix.com'},
    {'name': 'Spotify',        'url': 'https://open.spotify.com',   'domain': 'open.spotify.com'},
    {'name': 'GitHub',         'url': 'https://github.com',         'domain': 'github.com'},
    {'name': 'Twitch',         'url': 'https://twitch.tv',          'domain': 'twitch.tv'},
    {'name': 'Pinterest',      'url': 'https://pinterest.com',      'domain': 'pinterest.com'},
    {'name': 'LinkedIn',       'url': 'https://linkedin.com',       'domain': 'linkedin.com'},
    {'name': 'Discord',        'url': 'https://discord.com',        'domain': 'discord.com'},
    {'name': 'Telegram',       'url': 'https://web.telegram.org',   'domain': 'telegram.org'},
    {'name': 'Stack Overflow', 'url': 'https://stackoverflow.com',  'domain': 'stackoverflow.com'},
    {'name': 'Quora',          'url': 'https://quora.com',          'domain': 'quora.com'},
    {'name': 'eBay',           'url': 'https://ebay.com',           'domain': 'ebay.com'},
    {'name': 'IMDb',           'url': 'https://imdb.com',           'domain': 'imdb.com'},
    {'name': 'Booking',        'url': 'https://booking.com',        'domain': 'booking.com'},
    {'name': 'AliExpress',     'url': 'https://aliexpress.com',     'domain': 'aliexpress.com'},
    {'name': 'ChatGPT',        'url': 'https://chat.openai.com',    'domain': 'chat.openai.com'},
    {'name': 'Claude',         'url': 'https://claude.ai',          'domain': 'claude.ai'},
    {'name': 'Weather',        'url': 'https://weather.com',        'domain': 'weather.com'},
    {'name': 'Yahoo',          'url': 'https://yahoo.com',          'domain': 'yahoo.com'},
  ];

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _animCtrl.forward();
    _current = LocalDB.getSpeedDial();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  bool _isAlreadyAdded(String url) =>
      _current.any((s) => s['url'] == url);

  Future<void> _addSite(Map<String, dynamic> site) async {
    if (_isAlreadyAdded(site['url'] as String)) {
      _snack('Already in your Quick Access');
      return;
    }
    HapticFeedback.lightImpact();
    setState(() => _current.add(Map<String, dynamic>.from(site)));
    await LocalDB.saveSpeedDial(_current);
    _snack('Added "${site['name']}" ✓');
  }

  Future<void> _removeSite(int index) async {
    HapticFeedback.lightImpact();
    final removed = _current[index];
    setState(() => _current.removeAt(index));
    await LocalDB.saveSpeedDial(_current);
    _snack('Removed "${removed['name']}"');
  }

  Future<void> _resetAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Reset Quick Access?',
            style: GoogleFonts.spaceGrotesk(
                color: AppTheme.textPrimary, fontWeight: FontWeight.bold)),
        content: Text('This will restore the default 10 shortcuts.',
            style: GoogleFonts.inter(color: AppTheme.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: Text('Cancel', style: GoogleFonts.inter(color: AppTheme.textHint))),
          TextButton(onPressed: () => Navigator.pop(context, true),
              child: Text('Reset', style: GoogleFonts.inter(color: AppTheme.danger))),
        ],
      ),
    );
    if (ok == true) {
      await LocalDB.resetSpeedDial();
      setState(() => _current = LocalDB.getSpeedDial());
      _snack('Quick Access reset to defaults');
    }
  }

  void _showAddCustomDialog() {
    final nameCtrl = TextEditingController();
    final urlCtrl  = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          decoration: const BoxDecoration(
            color: AppTheme.bgCard,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(color: AppTheme.textHint,
                  borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 20),
            Row(children: [
              const Icon(Icons.add_link_rounded, color: AppTheme.accentCyan, size: 22),
              const SizedBox(width: 10),
              Text('Add Custom Site',
                  style: GoogleFonts.spaceGrotesk(
                      color: AppTheme.textPrimary,
                      fontSize: 17, fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 4),
            Align(alignment: Alignment.centerLeft, child:
              Text('Pin any website to Quick Access',
                  style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 12))),
            const SizedBox(height: 18),
            _field('Site name (e.g. My Blog)', nameCtrl),
            const SizedBox(height: 12),
            _field('Site URL (e.g. https://example.com)', urlCtrl,
                inputType: TextInputType.url),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: () async {
                final name = nameCtrl.text.trim();
                var url    = urlCtrl.text.trim();
                if (name.isEmpty || url.isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                    content: Text('Please fill in both fields',
                        style: GoogleFonts.inter(color: Colors.white)),
                    backgroundColor: AppTheme.danger,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ));
                  return;
                }
                if (!url.startsWith('http://') && !url.startsWith('https://')) {
                  url = 'https://$url';
                }
                Navigator.pop(ctx);
                await _addSite({
                  'name':   name,
                  'url':    url,
                  'domain': LocalDB.extractDomain(url),
                });
              },
              child: Container(
                height: 52, width: double.infinity,
                decoration: BoxDecoration(
                  gradient: AppTheme.primaryGradient,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: AppTheme.glowShadow,
                ),
                child: Center(child: Text('Add to Quick Access',
                    style: GoogleFonts.spaceGrotesk(
                        color: Colors.white, fontSize: 14,
                        fontWeight: FontWeight.w700))),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _field(String hint, TextEditingController ctrl,
      {TextInputType inputType = TextInputType.text}) {
    return TextField(
      controller:   ctrl,
      keyboardType: inputType,
      autocorrect:  false,
      style: GoogleFonts.inter(color: AppTheme.textPrimary, fontSize: 13),
      decoration: InputDecoration(
        hintText:   hint,
        hintStyle:  GoogleFonts.inter(color: AppTheme.textHint, fontSize: 13),
        filled:     true,
        fillColor:  AppTheme.bgElevated,
        border:     OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppTheme.accentCyan)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.inter(color: Colors.white)),
      backgroundColor: AppTheme.bgElevated,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      duration: const Duration(seconds: 2),
    ));
  }

  // ═══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    if (!RewardsEntitlements.isUnlocked(RewardFeature.speeddial)) {
      return FeatureLockScreen(
        featureKey: RewardFeature.speeddial,
        onUnlocked: () => setState(() {}),
      );
    }
    final unaddedRecommended = _recommended
        .where((s) => !_isAlreadyAdded(s['url'] as String))
        .toList();

    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: CustomScrollView(slivers: [
          _buildAppBar(),
          SliverToBoxAdapter(child: _buildHeaderActions()),
          SliverToBoxAdapter(child: _buildSection(
              'YOUR QUICK ACCESS', '${_current.length} shortcuts')),
          _buildCurrentGrid(),
          SliverToBoxAdapter(child: _buildSection(
              'RECOMMENDED', '${unaddedRecommended.length} sites')),
          _buildRecommendedGrid(unaddedRecommended),
          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ]),
      ),
    );
  }

  // ── App bar ────────────────────────────────────────────────────────────────
  Widget _buildAppBar() {
    return SliverAppBar(
      backgroundColor: AppTheme.bgDark,
      elevation: 0,
      pinned: true,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded,
            color: AppTheme.textSecondary, size: 18),
        onPressed: () => Navigator.pop(context),
      ),
      title: Text('Quick Access',
          style: GoogleFonts.spaceGrotesk(
              color: AppTheme.textPrimary,
              fontSize: 18, fontWeight: FontWeight.w700)),
      centerTitle: false,
    );
  }

  // ── Header actions row ─────────────────────────────────────────────────────
  Widget _buildHeaderActions() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Row(children: [
        Expanded(child: GestureDetector(
          onTap: _showAddCustomDialog,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              gradient: AppTheme.primaryGradient,
              borderRadius: BorderRadius.circular(14),
              boxShadow: AppTheme.glowShadow,
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.add_link_rounded, color: Colors.white, size: 16),
              const SizedBox(width: 6),
              Text('Add Custom Site', style: GoogleFonts.inter(
                  color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
            ]),
          ),
        )),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: _resetAll,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.bgCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.divider),
            ),
            child: const Icon(Icons.restart_alt_rounded,
                color: AppTheme.warning, size: 18),
          ),
        ),
      ]),
    );
  }

  // ── Section header ─────────────────────────────────────────────────────────
  Widget _buildSection(String label, String count) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 22, 20, 12),
    child: Row(children: [
      Text(label, style: GoogleFonts.inter(
          color: AppTheme.textHint, fontSize: 10,
          fontWeight: FontWeight.w700, letterSpacing: 1.2)),
      const Spacer(),
      Text(count, style: GoogleFonts.inter(
          color: AppTheme.textHint, fontSize: 10)),
    ]),
  );

  // ── Current grid (tap × to remove) ─────────────────────────────────────────
  Widget _buildCurrentGrid() {
    if (_current.isEmpty) {
      return SliverToBoxAdapter(child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppTheme.bgCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.divider),
          ),
          child: Row(children: [
            const Icon(Icons.bookmark_outline_rounded,
                color: AppTheme.textHint, size: 18),
            const SizedBox(width: 12),
            Expanded(child: Text(
              'No shortcuts yet — add from recommended below',
              style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 13))),
          ]),
        ),
      ));
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4, mainAxisSpacing: 16,
          crossAxisSpacing: 12, childAspectRatio: 0.75,
        ),
        delegate: SliverChildBuilderDelegate(
          (_, i) => _siteTile(_current[i],
              actionIcon: Icons.close_rounded,
              actionColor: AppTheme.danger,
              onAction: () => _removeSite(i)),
          childCount: _current.length,
        ),
      ),
    );
  }

  // ── Recommended grid (tap + to add) ────────────────────────────────────────
  Widget _buildRecommendedGrid(List<Map<String, dynamic>> sites) {
    if (sites.isEmpty) {
      return SliverToBoxAdapter(child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppTheme.bgCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.divider),
          ),
          child: Row(children: [
            const Icon(Icons.check_circle_outline_rounded,
                color: AppTheme.success, size: 18),
            const SizedBox(width: 12),
            Expanded(child: Text(
              "You've added all the recommended sites",
              style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 13))),
          ]),
        ),
      ));
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4, mainAxisSpacing: 16,
          crossAxisSpacing: 12, childAspectRatio: 0.75,
        ),
        delegate: SliverChildBuilderDelegate(
          (_, i) => _siteTile(sites[i],
              actionIcon: Icons.add_rounded,
              actionColor: AppTheme.success,
              onAction: () => _addSite(sites[i])),
          childCount: sites.length,
        ),
      ),
    );
  }

  // ── Site tile (used by both grids) ─────────────────────────────────────────
  Widget _siteTile(Map<String, dynamic> site, {
    required IconData    actionIcon,
    required Color       actionColor,
    required VoidCallback onAction,
  }) {
    final domain  = site['domain'] as String? ?? '';
    final favicon = 'https://www.google.com/s2/favicons?domain=$domain&sz=64';
    final name    = site['name'] as String? ?? '';

    return Column(children: [
      Stack(clipBehavior: Clip.none, children: [
        // Favicon tile
        Container(
          width: 56, height: 56,
          decoration: BoxDecoration(
            color: AppTheme.bgCard,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppTheme.divider),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(17),
            child: Image.network(favicon,
              width: 56, height: 56, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Center(child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: GoogleFonts.spaceGrotesk(
                    color: AppTheme.accentCyan,
                    fontSize: 22, fontWeight: FontWeight.w800))),
            ),
          ),
        ),
        // × or + badge
        Positioned(top: -6, right: -6, child: GestureDetector(
          onTap: onAction,
          child: Container(
            width: 22, height: 22,
            decoration: BoxDecoration(
              color: actionColor,
              shape: BoxShape.circle,
              border: Border.all(color: AppTheme.bgDark, width: 2),
              boxShadow: [BoxShadow(color: actionColor.withOpacity(0.4),
                  blurRadius: 4)],
            ),
            child: Icon(actionIcon, color: Colors.white, size: 12),
          ),
        )),
      ]),
      const SizedBox(height: 6),
      Text(name,
          style: GoogleFonts.inter(
              color: AppTheme.textSecondary, fontSize: 10,
              fontWeight: FontWeight.w500),
          maxLines: 1, overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center),
    ]);
  }
}
