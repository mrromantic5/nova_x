import 'dart:math';
import 'dart:ui';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nova_x/core/database/local_db.dart';
import 'package:nova_x/core/theme/app_theme.dart';
import '../../browser/screens/browser_view.dart';
import '../../ai/screens/ai_assistant_screen.dart';
import '../../bookmarks/screens/bookmarks_screen.dart';
import '../../history/screens/history_screen.dart';
import '../../settings/screens/settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  final int _bgIndex = Random().nextInt(10) + 1;
  List<Map<String, dynamic>> _news = [];
  bool _loadingNews = false;

  // Speed dial — 8 popular sites
  final List<Map<String, dynamic>> _speedDial = [
    {'name': 'Google',    'url': 'https://google.com',           'color': const Color(0xFF4285F4), 'letter': 'G'},
    {'name': 'YouTube',   'url': 'https://m.youtube.com',        'color': const Color(0xFFFF0000), 'letter': 'Y'},
    {'name': 'Facebook',  'url': 'https://m.facebook.com',       'color': const Color(0xFF1877F2), 'letter': 'f'},
    {'name': 'WhatsApp',  'url': 'https://web.whatsapp.com',     'color': const Color(0xFF25D366), 'letter': 'W'},
    {'name': 'Instagram', 'url': 'https://instagram.com',        'color': const Color(0xFFE1306C), 'letter': 'I'},
    {'name': 'X',         'url': 'https://x.com',                'color': const Color(0xFF1DA1F2), 'letter': 'X'},
    {'name': 'Wikipedia', 'url': 'https://en.m.wikipedia.org',   'color': const Color(0xFF636466), 'letter': 'W'},
    {'name': 'Gmail',     'url': 'https://mail.google.com',      'color': const Color(0xFFEA4335), 'letter': 'M'},
  ];

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _fadeAnim  = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
            begin: const Offset(0, 0.06), end: Offset.zero)
        .animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut));
    _animCtrl.forward();
    _fetchNews();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _animCtrl.dispose();
    super.dispose();
  }

  // ── News fetch (Google News RSS via rss2json) ─────────────────────────────
  Future<void> _fetchNews() async {
    if (!mounted) return;
    setState(() => _loadingNews = true);
    try {
      final res = await Dio(BaseOptions(connectTimeout: const Duration(seconds: 8)))
          .get('https://api.rss2json.com/v1/api.json', queryParameters: {
        'rss_url': 'https://news.google.com/rss?hl=en&gl=US&ceid=US:en',
        'count': '8',
      });
      if (res.data?['status'] == 'ok') {
        final items = (res.data['items'] as List?) ?? [];
        if (mounted) {
          setState(() {
            _news = items.map<Map<String, dynamic>>((i) => {
              'title':     i['title']     ?? '',
              'link':      i['link']      ?? '',
              'thumbnail': i['thumbnail'] ?? '',
              'author':    i['author']    ?? 'News',
              'pubDate':   i['pubDate']   ?? '',
            }).toList();
          });
        }
      }
    } catch (_) {
      // News is optional — fail silently
    } finally {
      if (mounted) setState(() => _loadingNews = false);
    }
  }

  // ── Navigate to browser ───────────────────────────────────────────────────
  void _go(String query) {
    final q = query.trim();
    if (q.isEmpty) return;
    _searchController.clear();
    HapticFeedback.lightImpact();
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => BrowserView(initialQuery: q)));
  }

  void _push(Widget screen) =>
      Navigator.push(context, _slide(screen));

  PageRouteBuilder _slide(Widget page) => PageRouteBuilder(
        pageBuilder: (_, a, __) => page,
        transitionsBuilder: (_, a, __, child) => SlideTransition(
          position:
              Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
                  .animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
          child: child,
        ),
        transitionDuration: const Duration(milliseconds: 300),
      );

  // ═══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          _buildBackground(),
          SafeArea(
            child: FadeTransition(
              opacity: _fadeAnim,
              child: SlideTransition(
                position: _slideAnim,
                child: Column(
                  children: [
                    _buildHeader(),
                    Expanded(
                      child: _buildScrollBody(),
                    ),
                    _buildBottomNav(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Background ────────────────────────────────────────────────────────────
  Widget _buildBackground() {
    return Positioned.fill(
      child: Stack(children: [
        Image.network(
          'https://api.browser.t-lyfe.com.ng/images/background$_bgIndex.jpg',
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          errorBuilder: (_, __, ___) => Container(
            decoration: const BoxDecoration(gradient: AppTheme.bgGradient),
          ),
        ),
        // Multi-stop overlay for text readability
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xD007101E),
                Color(0x9007101E),
                Color(0xE007101E),
              ],
              stops: [0.0, 0.45, 1.0],
            ),
          ),
        ),
      ]),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Row(children: [
        // Logo
        Container(
          width: 38, height: 38,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            boxShadow: AppTheme.glowShadow,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.asset('assets/images/logo.png',
                errorBuilder: (_, __, ___) => Container(
                  decoration: const BoxDecoration(gradient: AppTheme.primaryGradient),
                  child: const Icon(Icons.language, color: Colors.white, size: 20),
                )),
          ),
        ),
        const SizedBox(width: 10),
        ShaderMask(
          shaderCallback: (b) => AppTheme.primaryGradient.createShader(b),
          child: Text('NOVA X',
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: 2)),
        ),
        const Spacer(),
        _headerBtn(Icons.psychology_outlined, 'AI',
            () => _push(const AiAssistantScreen())),
        const SizedBox(width: 8),
        _headerBtn(Icons.settings_outlined, '',
            () => _push(const SettingsScreen())),
      ]),
    );
  }

  Widget _headerBtn(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.glassWhite,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.glassBorder),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: AppTheme.accentCyan, size: 18),
          if (label.isNotEmpty) ...[
            const SizedBox(width: 5),
            Text(label,
                style: GoogleFonts.inter(
                    color: AppTheme.accentCyan,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ],
        ]),
      ),
    );
  }

  // ── Scrollable body ────────────────────────────────────────────────────────
  Widget _buildScrollBody() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 28),
        _buildHeroSearch(),
        const SizedBox(height: 28),
        _buildSection('Quick Access', _buildSpeedDial()),
        const SizedBox(height: 22),
        _buildSection('Features', _buildFeatureRow()),
        const SizedBox(height: 22),
        _buildSection('Latest News', _buildNewsBody()),
        const SizedBox(height: 16),
      ]),
    );
  }

  // ── Hero search bar ─────────────────────────────────────────────────────
  Widget _buildHeroSearch() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(children: [
        Text('Where to next?',
            style: GoogleFonts.spaceGrotesk(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5)),
        const SizedBox(height: 16),
        ClipRRect(
          borderRadius: BorderRadius.circular(32),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0x22FFFFFF),
                borderRadius: BorderRadius.circular(32),
                border: Border.all(color: const Color(0x33FFFFFF)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
              child: Row(children: [
                const Icon(Icons.search, color: AppTheme.accentCyan, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    style: GoogleFonts.inter(color: Colors.white, fontSize: 15),
                    onSubmitted: _go,
                    textInputAction: TextInputAction.go,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: 'Search or type a URL…',
                      hintStyle: GoogleFonts.inter(
                          color: Colors.white38, fontSize: 15),
                      isDense: true,
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => _go(_searchController.text),
                  child: Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      gradient: AppTheme.primaryGradient,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: AppTheme.glowShadow,
                    ),
                    child: const Icon(Icons.arrow_forward,
                        color: Colors.white, size: 16),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  // ── Section wrapper ─────────────────────────────────────────────────────
  Widget _buildSection(String title, Widget child) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
        child: Text(title,
            style: GoogleFonts.spaceGrotesk(
                color: AppTheme.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2)),
      ),
      child,
    ]);
  }

  // ── Speed dial ──────────────────────────────────────────────────────────
  Widget _buildSpeedDial() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          mainAxisSpacing: 14,
          crossAxisSpacing: 14,
          childAspectRatio: 0.82,
        ),
        itemCount: _speedDial.length,
        itemBuilder: (_, i) => _buildDialItem(_speedDial[i]),
      ),
    );
  }

  Widget _buildDialItem(Map<String, dynamic> site) {
    final color = site['color'] as Color;
    return GestureDetector(
      onTap: () => _go(site['url']),
      child: Column(children: [
        Container(
          width: 58, height: 58,
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color.withOpacity(0.28), width: 1.2),
          ),
          child: Center(
            child: Text(site['letter'],
                style: TextStyle(
                    color: color,
                    fontSize: 24,
                    fontWeight: FontWeight.w800)),
          ),
        ),
        const SizedBox(height: 7),
        Text(site['name'],
            style: GoogleFonts.inter(
                color: AppTheme.textSecondary,
                fontSize: 10.5,
                fontWeight: FontWeight.w500),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center),
      ]),
    );
  }

  // ── Feature row ──────────────────────────────────────────────────────────
  Widget _buildFeatureRow() {
    final items = [
      {
        'icon':  Icons.psychology_outlined,
        'label': 'AI Chat',
        'color': AppTheme.accentCyan,
        'onTap': () => _push(const AiAssistantScreen()),
      },
      {
        'icon':  Icons.bookmark_border_rounded,
        'label': 'Bookmarks',
        'color': const Color(0xFFFFAB00),
        'onTap': () => _push(const BookmarksScreen()),
      },
      {
        'icon':  Icons.history_rounded,
        'label': 'History',
        'color': AppTheme.accentPurple,
        'onTap': () => _push(const HistoryScreen()),
      },
      {
        'icon':  Icons.tune_rounded,
        'label': 'Settings',
        'color': AppTheme.success,
        'onTap': () => _push(const SettingsScreen()),
      },
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: List.generate(items.length, (i) {
          final item = items[i];
          final color = item['color'] as Color;
          return Expanded(
            child: GestureDetector(
              onTap: item['onTap'] as VoidCallback,
              child: Container(
                margin: EdgeInsets.only(right: i < items.length - 1 ? 10 : 0),
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [color.withOpacity(0.18), color.withOpacity(0.06)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: color.withOpacity(0.25)),
                ),
                child: Column(children: [
                  Icon(item['icon'] as IconData, color: color, size: 24),
                  const SizedBox(height: 7),
                  Text(item['label'] as String,
                      style: GoogleFonts.inter(
                          color: AppTheme.textSecondary,
                          fontSize: 10,
                          fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ]),
              ),
            ),
          );
        }),
      ),
    );
  }

  // ── News section ─────────────────────────────────────────────────────────
  Widget _buildNewsBody() {
    if (_loadingNews) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(
          child: CircularProgressIndicator(
              color: AppTheme.accentCyan, strokeWidth: 2),
        ),
      );
    }
    if (_news.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: GestureDetector(
          onTap: _fetchNews,
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.bgCard.withOpacity(0.6),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.divider),
            ),
            child: Row(children: [
              const Icon(Icons.refresh, color: AppTheme.textHint, size: 18),
              const SizedBox(width: 12),
              Text('Tap to load news',
                  style: GoogleFonts.inter(
                      color: AppTheme.textHint, fontSize: 14)),
            ]),
          ),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: _news.length,
      separatorBuilder: (_, __) =>
          const Divider(color: AppTheme.divider, height: 1),
      itemBuilder: (_, i) => _buildNewsCard(_news[i]),
    );
  }

  Widget _buildNewsCard(Map<String, dynamic> item) {
    final thumb = item['thumbnail'] as String? ?? '';
    return GestureDetector(
      onTap: () => _go(item['link']),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 13),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text(item['title'],
                  style: GoogleFonts.inter(
                      color: AppTheme.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      height: 1.45),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 6),
              Text(item['author'],
                  style: GoogleFonts.inter(
                      color: AppTheme.textHint, fontSize: 11)),
            ]),
          ),
          if (thumb.isNotEmpty) ...[
            const SizedBox(width: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(thumb,
                  width: 72,
                  height: 56,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink()),
            ),
          ],
        ]),
      ),
    );
  }

  // ── Bottom navigation ────────────────────────────────────────────────────
  Widget _buildBottomNav() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: AppTheme.divider),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _navBtn(Icons.home_rounded,       'Home',      null,                             true),
          _navBtn(Icons.bookmark_rounded,   'Saved',     () => _push(const BookmarksScreen()), false),
          _navBtn(Icons.history_rounded,    'History',   () => _push(const HistoryScreen()),   false),
          _navBtn(Icons.more_horiz_rounded, 'Menu',      _showMenu,                        false),
        ],
      ),
    );
  }

  Widget _navBtn(IconData icon, String label, VoidCallback? onTap, bool active) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: active
            ? BoxDecoration(
                gradient: AppTheme.primaryGradient,
                borderRadius: BorderRadius.circular(24),
                boxShadow: AppTheme.glowShadow,
              )
            : null,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon,
              color: active ? Colors.white : AppTheme.textHint,
              size: 22),
          const SizedBox(height: 3),
          Text(label,
              style: GoogleFonts.inter(
                  color: active ? Colors.white : AppTheme.textHint,
                  fontSize: 10,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w400)),
        ]),
      ),
    );
  }

  // ── Slide-up menu sheet ──────────────────────────────────────────────────
  void _showMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _MenuSheet(onNavigate: _go, onPush: _push),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// Bottom sheet menu
// ══════════════════════════════════════════════════════════════════════════════
class _MenuSheet extends StatelessWidget {
  final void Function(String) onNavigate;
  final void Function(Widget) onPush;

  const _MenuSheet({required this.onNavigate, required this.onPush});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Handle bar
        Container(
          width: 40, height: 4,
          margin: const EdgeInsets.only(bottom: 24),
          decoration: BoxDecoration(
            color: AppTheme.textHint,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        // Feature grid
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 4,
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          childAspectRatio: 0.88,
          children: [
            _menuTile(context, Icons.psychology_outlined, 'AI Chat',
                AppTheme.accentCyan,
                () { Navigator.pop(context); onPush(const AiAssistantScreen()); }),
            _menuTile(context, Icons.download_outlined, 'Downloads',
                AppTheme.primaryBlue,
                () => Navigator.pop(context)),
            _menuTile(context, Icons.share_outlined, 'Share App',
                const Color(0xFF00C853),
                () { Navigator.pop(context); _shareApp(context); }),
            _menuTile(context, Icons.info_outline, 'About',
                const Color(0xFFFFAB00),
                () { Navigator.pop(context); _showAbout(context); }),
            _menuTile(context, Icons.bookmark_border_rounded, 'Bookmarks',
                const Color(0xFFFFAB00),
                () { Navigator.pop(context); onPush(const BookmarksScreen()); }),
            _menuTile(context, Icons.history_rounded, 'History',
                AppTheme.accentPurple,
                () { Navigator.pop(context); onPush(const HistoryScreen()); }),
            _menuTile(context, Icons.settings_outlined, 'Settings',
                const Color(0xFF00C853),
                () { Navigator.pop(context); onPush(const SettingsScreen()); }),
            _menuTile(context, Icons.feedback_outlined, 'Feedback',
                AppTheme.textHint,
                () => Navigator.pop(context)),
          ],
        ),
      ]),
    );
  }

  Widget _menuTile(BuildContext ctx, IconData icon, String label, Color color,
      VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(children: [
        Container(
          width: 54, height: 54,
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withOpacity(0.25)),
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        const SizedBox(height: 7),
        Text(label,
            style: GoogleFonts.inter(
                color: AppTheme.textSecondary, fontSize: 10.5,
                fontWeight: FontWeight.w500),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
      ]),
    );
  }

  void _shareApp(BuildContext ctx) {
    Clipboard.setData(
        const ClipboardData(text: 'Check out NOVA X Browser!'));
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(
        content: Text('Link copied!',
            style: GoogleFonts.inter(color: Colors.white)),
        backgroundColor: AppTheme.bgElevated,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _showAbout(BuildContext ctx) {
    showDialog(
      context: ctx,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('NOVA X Browser',
            style: GoogleFonts.spaceGrotesk(
                color: AppTheme.textPrimary, fontWeight: FontWeight.bold)),
        content: Text(
            'Version 2.0.0\n\nBuilt with ❤️ by Tech Lyfe Team.\nCEO: Kobby (Mr. Romantic)',
            style: GoogleFonts.inter(
                color: AppTheme.textSecondary, height: 1.5)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(_),
            child: Text('Close',
                style: GoogleFonts.inter(color: AppTheme.accentCyan)),
          ),
        ],
      ),
    );
  }
}
