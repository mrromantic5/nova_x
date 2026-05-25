import 'dart:math';
import 'dart:ui';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:nova_x/core/database/local_db.dart';
import 'package:nova_x/core/theme/app_theme.dart';
import 'package:nova_x/core/services/news_service.dart';
import '../../browser/screens/browser_view.dart';
import '../../ai/screens/ai_assistant_screen.dart';
import '../../bookmarks/screens/bookmarks_screen.dart';
import '../../history/screens/history_screen.dart';
import '../../settings/screens/settings_screen.dart';
import '../../profile/screens/profile_screen.dart';
import '../../downloads/screens/downloads_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  // Controllers
  final TextEditingController _searchCtrl  = TextEditingController();
  final FocusNode             _searchFocus = FocusNode();
  final ScrollController      _scrollCtrl  = ScrollController();
  late AnimationController    _animCtrl;
  late Animation<double>      _fadeAnim;

  // State
  final int _bgIndex = Random().nextInt(10) + 1;

  // News state — categorised with cache so switching tabs is instant
  String                         _selectedCategory = 'For You';
  List<NewsArticle>              _news             = [];
  final Map<String, List<NewsArticle>> _newsCache  = {};
  bool _loadingNews = false;

  List<String> _suggestions = [];
  List<String> _searchHist  = [];
  bool _showSuggest  = false;
  bool _isListening  = false;

  // Voice search
  final SpeechToText _speech    = SpeechToText();
  bool               _speechAvail = false;

  // Speed dial
  final List<Map<String, dynamic>> _speedDial = [
    {'name': 'Google',    'url': 'https://google.com',                    'domain': 'google.com'},
    {'name': 'YouTube',   'url': 'https://m.youtube.com',                 'domain': 'youtube.com'},
    {'name': 'Facebook',  'url': 'https://m.facebook.com',                'domain': 'facebook.com'},
    {'name': 'WhatsApp',  'url': 'https://web.whatsapp.com',              'domain': 'whatsapp.com'},
    {'name': 'Instagram', 'url': 'https://instagram.com',                 'domain': 'instagram.com'},
    {'name': 'ChatXAP',   'url': 'https://c.x.t-lyfe.com.ng/login.html', 'domain': 'c.x.t-lyfe.com.ng'},
    {'name': 'X',         'url': 'https://x.com',                         'domain': 'x.com'},
    {'name': 'TikTok',    'url': 'https://www.tiktok.com',                'domain': 'tiktok.com'},
    {'name': 'Wikipedia', 'url': 'https://en.m.wikipedia.org',            'domain': 'wikipedia.org'},
    {'name': 'Gmail',     'url': 'https://mail.google.com',               'domain': 'mail.google.com'},
  ];

  // ── Category accent colours (one per tab) ──────────────────────────────
  static const Map<String, Color> _catColor = {
    'For You':       Color(0xFF00D4FF),
    'World':         Color(0xFF1E7BFF),
    'Sports':        Color(0xFF00C853),
    'Tech':          Color(0xFF7C4DFF),
    'Entertainment': Color(0xFFFF6B6B),
    'Business':      Color(0xFFFFAB00),
    'Health':        Color(0xFFFF4081),
    'Science':       Color(0xFF00BCD4),
  };

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800));
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _animCtrl.forward();
    _initSpeech();
    _fetchNews();
    _searchHist = LocalDB.getSearchHistory();
    _searchCtrl.addListener(_onSearchChanged);
    _searchFocus.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_onSearchChanged);
    _searchFocus.removeListener(_onFocusChanged);
    _searchCtrl.dispose();
    _searchFocus.dispose();
    _scrollCtrl.dispose();
    _animCtrl.dispose();
    _speech.stop();
    super.dispose();
  }

  // ── Speech ────────────────────────────────────────────────────────────────
  Future<void> _initSpeech() async {
    _speechAvail = await _speech.initialize(
      onError: (_) => setState(() => _isListening = false),
    );
  }

  Future<void> _toggleListen() async {
    if (!_speechAvail) { _showSnack('Microphone not available'); return; }
    HapticFeedback.mediumImpact();
    if (_isListening) {
      _speech.stop();
      setState(() => _isListening = false);
    } else {
      setState(() { _isListening = true; _showSuggest = false; });
      _searchFocus.unfocus();
      await _speech.listen(
        onResult: (r) {
          if (r.finalResult && r.recognizedWords.isNotEmpty) {
            setState(() => _isListening = false);
            _go(r.recognizedWords);
          }
        },
        localeId: 'en_US',
        cancelOnError: true,
        partialResults: false,
      );
    }
  }

  // ── Search suggestions ────────────────────────────────────────────────────
  void _onFocusChanged() {
    if (_searchFocus.hasFocus) {
      setState(() { _showSuggest = true; _searchHist = LocalDB.getSearchHistory(); });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollCtrl.hasClients) {
          _scrollCtrl.animateTo(80,
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOut);
        }
      });
    } else {
      Future.delayed(const Duration(milliseconds: 150),
          () { if (mounted) setState(() => _showSuggest = false); });
    }
  }

  void _onSearchChanged() {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) { setState(() => _suggestions = []); return; }
    _fetchSuggestions(q);
  }

  Future<void> _fetchSuggestions(String query) async {
    try {
      final res = await Dio(BaseOptions(connectTimeout: const Duration(seconds: 5)))
          .get('https://suggestqueries.google.com/complete/search',
              queryParameters: {'output': 'firefox', 'q': query});
      if (res.data is List && (res.data as List).length >= 2) {
        final list = ((res.data as List)[1] as List).cast<String>();
        if (mounted) setState(() => _suggestions = list.take(6).toList());
      }
    } catch (_) {}
  }

  // ── News ──────────────────────────────────────────────────────────────────
  Future<void> _fetchNews({bool forceRefresh = false}) async {
    if (!mounted) return;

    // Serve from cache instantly (no flicker when switching tabs)
    if (!forceRefresh && _newsCache.containsKey(_selectedCategory)) {
      setState(() => _news = _newsCache[_selectedCategory]!);
      return;
    }

    setState(() => _loadingNews = true);

    final articles = await NewsService.fetchNews(_selectedCategory);

    if (mounted) {
      _newsCache[_selectedCategory] = articles;
      setState(() { _news = articles; _loadingNews = false; });
    }
  }

  void _switchCategory(String cat) {
    if (_selectedCategory == cat) return;
    setState(() { _selectedCategory = cat; _news = []; });
    _fetchNews();
  }

  // ── Navigation ────────────────────────────────────────────────────────────
  void _go(String query) {
    final q = query.trim();
    if (q.isEmpty) return;
    LocalDB.addSearchQuery(q);
    _searchCtrl.clear();
    _searchFocus.unfocus();
    setState(() { _showSuggest = false; _suggestions = []; });
    HapticFeedback.lightImpact();
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => BrowserView(initialQuery: q)));
  }

  void _push(Widget screen) => Navigator.push(context,
      PageRouteBuilder(
        pageBuilder: (_, a, __) => screen,
        transitionsBuilder: (_, a, __, child) => SlideTransition(
          position: Tween<Offset>(
                  begin: const Offset(1, 0), end: Offset.zero)
              .animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
          child: child,
        ),
        transitionDuration: const Duration(milliseconds: 280),
      ));

  void _showSnack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(msg, style: GoogleFonts.inter(color: Colors.white)),
          backgroundColor: AppTheme.bgElevated,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));

  String _greeting() {
    final h = DateTime.now().hour;
    final profile = LocalDB.getProfile();
    final name = (profile['name'] as String? ?? '').split(' ').first;
    final display = name.isNotEmpty ? ', $name' : '';
    if (h >= 5  && h < 12) return '☀️ Good morning$display!';
    if (h >= 12 && h < 17) return '🌤️ Good afternoon$display!';
    if (h >= 17 && h < 21) return '🌆 Good evening$display!';
    return '🌙 Good night$display!';
  }

  // ═══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      resizeToAvoidBottomInset: false,
      extendBodyBehindAppBar: true,
      body: Stack(children: [
        _buildBackground(),
        SafeArea(
          child: FadeTransition(
            opacity: _fadeAnim,
            child: Column(children: [
              _buildHeader(),
              Expanded(
                child: SingleChildScrollView(
                  controller: _scrollCtrl,
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    const SizedBox(height: 20),
                    _buildGreetingAndSearch(),
                    const SizedBox(height: 24),
                    _buildSection('Quick Access', _buildSpeedDial()),
                    const SizedBox(height: 20),
                    _buildSection('Features', _buildFeatureRow()),
                    const SizedBox(height: 20),
                    _buildNewsSection(),
                    const SizedBox(height: 12),
                  ]),
                ),
              ),
              _buildBottomNav(),
            ]),
          ),
        ),
        if (_isListening) _buildListeningOverlay(),
      ]),
    );
  }

  // ── Background ────────────────────────────────────────────────────────────
  Widget _buildBackground() {
    return Positioned.fill(child: Stack(children: [
      Image.network(
        'https://api.browser.t-lyfe.com.ng/images/background$_bgIndex.jpg',
        fit: BoxFit.cover, width: double.infinity, height: double.infinity,
        errorBuilder: (_, __, ___) =>
            Container(decoration: const BoxDecoration(gradient: AppTheme.bgGradient)),
      ),
      Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Color(0xD507101E), Color(0x9507101E), Color(0xEE07101E)],
            stops: [0.0, 0.45, 1.0],
          ),
        ),
      ),
    ]));
  }

  // ── Header ────────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Row(children: [
        GestureDetector(
          onTap: () => _push(const ProfileScreen()),
          child: Container(
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
                    child: const Icon(Icons.language, color: Colors.white, size: 20))),
            ),
          ),
        ),
        const SizedBox(width: 10),
        ShaderMask(
          shaderCallback: (b) => AppTheme.primaryGradient.createShader(b),
          child: Text('NOVA X',
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 22, fontWeight: FontWeight.w800,
                  color: Colors.white, letterSpacing: 2)),
        ),
        const Spacer(),
        _hBtn(Icons.psychology_outlined,    () => _push(const AiAssistantScreen())),
        const SizedBox(width: 8),
        _hBtn(Icons.person_outline_rounded, () => _push(const ProfileScreen())),
        const SizedBox(width: 8),
        _hBtn(Icons.settings_outlined,      () => _push(const SettingsScreen())),
      ]),
    );
  }

  Widget _hBtn(IconData icon, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 36, height: 36,
      decoration: BoxDecoration(
        color: AppTheme.glassWhite,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.glassBorder),
      ),
      child: Icon(icon, color: AppTheme.accentCyan, size: 18),
    ),
  );

  // ── Greeting + Search ─────────────────────────────────────────────────────
  Widget _buildGreetingAndSearch() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_greeting(),
            style: GoogleFonts.spaceGrotesk(
                color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text('Where would you like to go today?',
            style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 13)),
        const SizedBox(height: 16),
        ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Column(children: [
              Container(
                decoration: BoxDecoration(
                  color: const Color(0x22FFFFFF),
                  borderRadius: BorderRadius.only(
                    topLeft:     const Radius.circular(28),
                    topRight:    const Radius.circular(28),
                    bottomLeft:  Radius.circular(_showSuggest ? 0 : 28),
                    bottomRight: Radius.circular(_showSuggest ? 0 : 28),
                  ),
                  border: Border.all(color: const Color(0x33FFFFFF)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(children: [
                  Icon(
                    _isListening ? Icons.hearing : Icons.search,
                    color: _isListening ? Colors.redAccent : AppTheme.accentCyan,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      focusNode:  _searchFocus,
                      style: GoogleFonts.inter(color: Colors.white, fontSize: 15),
                      onSubmitted: _go,
                      textInputAction: TextInputAction.go,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        hintText: _isListening
                            ? 'Listening… speak now'
                            : 'Search or type a URL…',
                        hintStyle: GoogleFonts.inter(
                            color: _isListening
                                ? Colors.redAccent.withOpacity(0.7)
                                : Colors.white38,
                            fontSize: 15),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: _toggleListen,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _isListening
                            ? Colors.red.withOpacity(0.2)
                            : Colors.transparent,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _isListening ? Icons.mic : Icons.mic_none_rounded,
                        color: _isListening ? Colors.redAccent : AppTheme.textHint,
                        size: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: () => _go(_searchCtrl.text),
                    child: Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        gradient: AppTheme.primaryGradient,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: AppTheme.glowShadow,
                      ),
                      child: const Icon(Icons.arrow_forward, color: Colors.white, size: 16),
                    ),
                  ),
                ]),
              ),
              if (_showSuggest)
                Container(
                  decoration: BoxDecoration(
                    color: AppTheme.bgCard.withOpacity(0.97),
                    borderRadius: const BorderRadius.only(
                      bottomLeft:  Radius.circular(20),
                      bottomRight: Radius.circular(20),
                    ),
                    border: Border(
                      left:   BorderSide(color: AppTheme.glassBorder),
                      right:  BorderSide(color: AppTheme.glassBorder),
                      bottom: BorderSide(color: AppTheme.glassBorder),
                    ),
                  ),
                  child: Column(
                    children: [
                      if (_searchCtrl.text.isEmpty && _searchHist.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Recent',
                                  style: GoogleFonts.inter(
                                      color: AppTheme.textHint, fontSize: 11,
                                      fontWeight: FontWeight.w600, letterSpacing: 0.8)),
                              GestureDetector(
                                onTap: () async {
                                  await LocalDB.clearSearchHistory();
                                  setState(() => _searchHist = []);
                                },
                                child: Text('Clear',
                                    style: GoogleFonts.inter(
                                        color: AppTheme.danger, fontSize: 11)),
                              ),
                            ],
                          ),
                        ),
                        ..._searchHist.take(5).map((h) => _suggestionTile(
                          Icons.history_rounded, h,
                          trailing: GestureDetector(
                            onTap: () async {
                              await LocalDB.removeSearchQuery(h);
                              setState(() => _searchHist = LocalDB.getSearchHistory());
                            },
                            child: const Icon(Icons.close, color: AppTheme.textHint, size: 14),
                          ),
                        )),
                      ],
                      if (_searchCtrl.text.isNotEmpty)
                        ..._suggestions.map((s) => _suggestionTile(
                          Icons.trending_up_rounded, s,
                          trailing: GestureDetector(
                            onTap: () {
                              _searchCtrl.text = s;
                              _searchCtrl.selection = TextSelection.fromPosition(
                                  TextPosition(offset: s.length));
                            },
                            child: const Icon(Icons.north_west_rounded,
                                color: AppTheme.textHint, size: 14),
                          ),
                        )),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _suggestionTile(IconData icon, String text, {Widget? trailing}) {
    return GestureDetector(
      onTap: () => _go(text),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(children: [
          Icon(icon, color: AppTheme.textHint, size: 16),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text,
                style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 14),
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          if (trailing != null) trailing,
        ]),
      ),
    );
  }

  // ── Section wrapper ────────────────────────────────────────────────────────
  Widget _buildSection(String title, Widget child) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: Text(title,
            style: GoogleFonts.spaceGrotesk(
                color: AppTheme.textHint, fontSize: 11,
                fontWeight: FontWeight.w700, letterSpacing: 1.2)),
      ),
      child,
    ],
  );

  // ── Speed dial ─────────────────────────────────────────────────────────────
  Widget _buildSpeedDial() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 5, mainAxisSpacing: 14,
          crossAxisSpacing: 14, childAspectRatio: 0.8,
        ),
        itemCount: _speedDial.length,
        itemBuilder: (_, i) => _dialItem(_speedDial[i]),
      ),
    );
  }

  Widget _dialItem(Map<String, dynamic> site) {
    final domain  = site['domain'] as String;
    final favicon = 'https://www.google.com/s2/favicons?domain=$domain&sz=64';
    return GestureDetector(
      onTap: () => _go(site['url']),
      child: Column(children: [
        Container(
          width: 52, height: 52,
          decoration: BoxDecoration(
            color: AppTheme.bgCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.divider),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(15),
            child: Image.network(favicon,
              width: 52, height: 52, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Center(
                child: Text((site['name'] as String)[0],
                    style: GoogleFonts.spaceGrotesk(
                        color: AppTheme.accentCyan,
                        fontSize: 20, fontWeight: FontWeight.w800)),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(site['name'],
            style: GoogleFonts.inter(
                color: AppTheme.textSecondary, fontSize: 9.5,
                fontWeight: FontWeight.w500),
            maxLines: 1, overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center),
      ]),
    );
  }

  // ── Feature row ────────────────────────────────────────────────────────────
  Widget _buildFeatureRow() {
    final items = [
      {'icon': Icons.psychology_outlined,     'label': 'AI Chat',   'color': AppTheme.accentCyan,
       'fn': () => _push(const AiAssistantScreen())},
      {'icon': Icons.bookmark_border_rounded, 'label': 'Bookmarks', 'color': const Color(0xFFFFAB00),
       'fn': () => _push(const BookmarksScreen())},
      {'icon': Icons.download_outlined,       'label': 'Downloads', 'color': AppTheme.primaryBlue,
       'fn': () => _push(const DownloadsScreen())},
      {'icon': Icons.history_rounded,         'label': 'History',   'color': AppTheme.accentPurple,
       'fn': () => _push(const HistoryScreen())},
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: List.generate(items.length, (i) {
          final item  = items[i];
          final color = item['color'] as Color;
          return Expanded(
            child: GestureDetector(
              onTap: item['fn'] as VoidCallback,
              child: Container(
                margin: EdgeInsets.only(right: i < items.length - 1 ? 10 : 0),
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [color.withOpacity(0.18), color.withOpacity(0.06)],
                    begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: color.withOpacity(0.25)),
                ),
                child: Column(children: [
                  Icon(item['icon'] as IconData, color: color, size: 22),
                  const SizedBox(height: 6),
                  Text(item['label'] as String,
                      style: GoogleFonts.inter(
                          color: AppTheme.textSecondary,
                          fontSize: 9.5, fontWeight: FontWeight.w600),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ]),
              ),
            ),
          );
        }),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // NEWS SECTION — Chrome Discover style
  // ══════════════════════════════════════════════════════════════════════════

  Widget _buildNewsSection() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // ── Section header ──────────────────────────────────────────────────
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: Row(children: [
          Text('Latest News',
              style: GoogleFonts.spaceGrotesk(
                  color: AppTheme.textHint, fontSize: 11,
                  fontWeight: FontWeight.w700, letterSpacing: 1.2)),
          const Spacer(),
          GestureDetector(
            onTap: () {
              _newsCache.remove(_selectedCategory);
              _fetchNews(forceRefresh: true);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.bgCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.divider),
              ),
              child: Row(children: [
                const Icon(Icons.refresh_rounded, color: AppTheme.accentCyan, size: 13),
                const SizedBox(width: 4),
                Text('Refresh',
                    style: GoogleFonts.inter(
                        color: AppTheme.accentCyan,
                        fontSize: 10, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
        ]),
      ),

      // ── Category chips ──────────────────────────────────────────────────
      SizedBox(
        height: 34,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: NewsService.categoryLabels.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            final cat    = NewsService.categoryLabels[i];
            final active = cat == _selectedCategory;
            final color  = _catColor[cat] ?? AppTheme.accentCyan;
            return GestureDetector(
              onTap: () => _switchCategory(cat),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: active ? color.withOpacity(0.2) : AppTheme.bgCard,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: active ? color : AppTheme.divider,
                    width: active ? 1.5 : 1,
                  ),
                ),
                child: Text(cat,
                    style: GoogleFonts.inter(
                        color: active ? color : AppTheme.textSecondary,
                        fontSize: 12,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w500)),
              ),
            );
          },
        ),
      ),

      const SizedBox(height: 16),

      // ── News body ───────────────────────────────────────────────────────
      _buildNewsBody(),
    ]);
  }

  Widget _buildNewsBody() {
    if (_loadingNews) {
      return Column(children: [
        const SizedBox(height: 20),
        Center(child: CircularProgressIndicator(
            color: _catColor[_selectedCategory] ?? AppTheme.accentCyan,
            strokeWidth: 2)),
        const SizedBox(height: 12),
        Text('Fetching ${_selectedCategory.toLowerCase()} news…',
            style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 12)),
        const SizedBox(height: 20),
      ]);
    }

    if (_news.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: GestureDetector(
          onTap: () => _fetchNews(forceRefresh: true),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppTheme.bgCard.withOpacity(0.7),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.divider),
            ),
            child: Row(children: [
              const Icon(Icons.cloud_off_rounded, color: AppTheme.textHint, size: 18),
              const SizedBox(width: 12),
              Text('Tap to reload news',
                  style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 14)),
            ]),
          ),
        ),
      );
    }

    return Column(children: [
      // Hero card — first article, full-width image
      if (_news.first.imageUrl.isNotEmpty)
        _buildHeroCard(_news.first),

      // Remaining articles — compact card style
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          children: List.generate(
            _news.length > 1 ? _news.length - 1 : 0,
            (i) {
              final article = _news[i + 1];
              return Column(children: [
                if (i == 0 && _news.first.imageUrl.isNotEmpty)
                  const SizedBox(height: 4),
                _buildCompactCard(article),
                if (i < _news.length - 2)
                  Divider(color: AppTheme.divider.withOpacity(0.6), height: 1),
              ]);
            },
          ),
        ),
      ),
    ]);
  }

  // ── Hero card (large image + title + source) ───────────────────────────────
  Widget _buildHeroCard(NewsArticle article) {
    final color = _catColor[_selectedCategory] ?? AppTheme.accentCyan;
    return GestureDetector(
      onTap: () => _go(article.url),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Container(
          decoration: BoxDecoration(
            color: AppTheme.bgCard,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.divider),
            boxShadow: AppTheme.cardShadow,
          ),
          clipBehavior: Clip.hardEdge,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Image
            Stack(children: [
              SizedBox(
                height: 200,
                width: double.infinity,
                child: Image.network(
                  article.imageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    height: 200,
                    color: AppTheme.bgElevated,
                    child: Center(
                      child: Icon(Icons.image_not_supported_outlined,
                          color: AppTheme.textHint, size: 36)),
                  ),
                ),
              ),
              // Gradient overlay on image
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, AppTheme.bgCard.withOpacity(0.7)],
                      stops: const [0.5, 1.0],
                    ),
                  ),
                ),
              ),
              // Category badge on image
              Positioned(
                top: 12, left: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(_selectedCategory,
                      style: GoogleFonts.inter(
                          color: Colors.white, fontSize: 10,
                          fontWeight: FontWeight.w700)),
                ),
              ),
            ]),

            // Title + meta
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(article.title,
                    style: GoogleFonts.spaceGrotesk(
                        color: AppTheme.textPrimary, fontSize: 15,
                        fontWeight: FontWeight.w700, height: 1.4),
                    maxLines: 3, overflow: TextOverflow.ellipsis),
                if (article.description.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(article.description,
                      style: GoogleFonts.inter(
                          color: AppTheme.textSecondary, fontSize: 12, height: 1.4),
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
                const SizedBox(height: 10),
                Row(children: [
                  Container(
                    width: 6, height: 6,
                    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(article.source,
                        style: GoogleFonts.inter(
                            color: color, fontSize: 11, fontWeight: FontWeight.w600),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  if (article.timeAgo.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Text(article.timeAgo,
                        style: GoogleFonts.inter(
                            color: AppTheme.textHint, fontSize: 11)),
                  ],
                  const SizedBox(width: 8),
                  Icon(Icons.open_in_new_rounded, color: AppTheme.textHint, size: 13),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  // ── Compact card (thumbnail right, title + source left) ───────────────────
  Widget _buildCompactCard(NewsArticle article) {
    final thumb = article.imageUrl;
    return GestureDetector(
      onTap: () => _go(article.url),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 13),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Text content
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Source + time row
              Row(children: [
                Flexible(
                  child: Text(article.source,
                      style: GoogleFonts.inter(
                          color: _catColor[_selectedCategory] ?? AppTheme.accentCyan,
                          fontSize: 10.5, fontWeight: FontWeight.w600),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                if (article.timeAgo.isNotEmpty) ...[
                  Text('  ·  ${article.timeAgo}',
                      style: GoogleFonts.inter(
                          color: AppTheme.textHint, fontSize: 10.5)),
                ],
              ]),
              const SizedBox(height: 5),
              Text(article.title,
                  style: GoogleFonts.inter(
                      color: AppTheme.textPrimary, fontSize: 13.5,
                      fontWeight: FontWeight.w500, height: 1.4),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
            ]),
          ),

          // Thumbnail
          if (thumb.isNotEmpty) ...[
            const SizedBox(width: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                thumb, width: 78, height: 62, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          ],
        ]),
      ),
    );
  }

  // ── Bottom navigation ──────────────────────────────────────────────────────
  Widget _buildBottomNav() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: AppTheme.divider),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
        _navBtn(Icons.home_rounded,       'Home',      null,                              true),
        _navBtn(Icons.bookmark_rounded,   'Saved',     () => _push(const BookmarksScreen()), false),
        _navBtn(Icons.download_rounded,   'Downloads', () => _push(const DownloadsScreen()),  false),
        _navBtn(Icons.history_rounded,    'History',   () => _push(const HistoryScreen()),    false),
        _navBtn(Icons.more_horiz_rounded, 'Menu',      _showMenu,                         false),
      ]),
    );
  }

  Widget _navBtn(IconData icon, String label, VoidCallback? onTap, bool active) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: active ? BoxDecoration(
          gradient: AppTheme.primaryGradient,
          borderRadius: BorderRadius.circular(24),
          boxShadow: AppTheme.glowShadow,
        ) : null,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: active ? Colors.white : AppTheme.textHint, size: 20),
          const SizedBox(height: 2),
          Text(label,
              style: GoogleFonts.inter(
                  color: active ? Colors.white : AppTheme.textHint,
                  fontSize: 9,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w400)),
        ]),
      ),
    );
  }

  // ── Listening overlay ──────────────────────────────────────────────────────
  Widget _buildListeningOverlay() {
    return Positioned(
      bottom: 100, left: 0, right: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.red.withOpacity(0.9),
            borderRadius: BorderRadius.circular(30),
            boxShadow: [BoxShadow(color: Colors.red.withOpacity(0.4),
                blurRadius: 20, offset: const Offset(0, 4))],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.mic, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Text('Listening… tap mic to stop',
                style: GoogleFonts.inter(
                    color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }

  // ── Menu sheet ─────────────────────────────────────────────────────────────
  void _showMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _MenuSheet(onPush: _push),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
class _MenuSheet extends StatelessWidget {
  final void Function(Widget) onPush;
  const _MenuSheet({required this.onPush});

  @override
  Widget build(BuildContext context) {
    final items = [
      {'icon': Icons.psychology_outlined,     'label': 'AI Chat',   'color': AppTheme.accentCyan,
       'fn': () { Navigator.pop(context); onPush(const AiAssistantScreen()); }},
      {'icon': Icons.bookmark_border_rounded, 'label': 'Bookmarks', 'color': const Color(0xFFFFAB00),
       'fn': () { Navigator.pop(context); onPush(const BookmarksScreen()); }},
      {'icon': Icons.download_outlined,       'label': 'Downloads', 'color': AppTheme.primaryBlue,
       'fn': () { Navigator.pop(context); onPush(const DownloadsScreen()); }},
      {'icon': Icons.history_rounded,         'label': 'History',   'color': AppTheme.accentPurple,
       'fn': () { Navigator.pop(context); onPush(const HistoryScreen()); }},
      {'icon': Icons.person_outline_rounded,  'label': 'Profile',   'color': const Color(0xFFFF6B6B),
       'fn': () { Navigator.pop(context); onPush(const ProfileScreen()); }},
      {'icon': Icons.settings_outlined,       'label': 'Settings',  'color': AppTheme.success,
       'fn': () { Navigator.pop(context); onPush(const SettingsScreen()); }},
      {'icon': Icons.info_outline_rounded,    'label': 'About',     'color': AppTheme.textHint,
       'fn': () { Navigator.pop(context); _about(context); }},
      {'icon': Icons.share_outlined,          'label': 'Share',     'color': AppTheme.primaryBlue,
       'fn': () { Navigator.pop(context); Clipboard.setData(const ClipboardData(text: 'NOVA X Browser')); }},
    ];

    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 40, height: 4,
          margin: const EdgeInsets.only(bottom: 20),
          decoration: BoxDecoration(
              color: AppTheme.textHint, borderRadius: BorderRadius.circular(2)),
        ),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 4,
          mainAxisSpacing: 14, crossAxisSpacing: 14,
          childAspectRatio: 0.85,
          children: items.map((item) {
            final color = item['color'] as Color;
            return GestureDetector(
              onTap: item['fn'] as VoidCallback,
              child: Column(children: [
                Container(
                  width: 52, height: 52,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: color.withOpacity(0.25)),
                  ),
                  child: Icon(item['icon'] as IconData, color: color, size: 22),
                ),
                const SizedBox(height: 6),
                Text(item['label'] as String,
                    style: GoogleFonts.inter(
                        color: AppTheme.textSecondary,
                        fontSize: 10, fontWeight: FontWeight.w500),
                    textAlign: TextAlign.center,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ]),
            );
          }).toList(),
        ),
      ]),
    );
  }

  void _about(BuildContext ctx) => showDialog(
    context: ctx,
    builder: (_) => AlertDialog(
      backgroundColor: AppTheme.bgCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text('NOVA X Browser',
          style: GoogleFonts.spaceGrotesk(
              color: AppTheme.textPrimary, fontWeight: FontWeight.bold)),
      content: Text(
          'Version 2.1.0\nBuilt with ❤️ by Tech Lyfe Team.\nCEO: Kobby (Mr. Romantic)',
          style: GoogleFonts.inter(color: AppTheme.textSecondary, height: 1.5)),
      actions: [TextButton(
        onPressed: () => Navigator.pop(_),
        child: Text('Close', style: GoogleFonts.inter(color: AppTheme.accentCyan)),
      )],
    ),
  );
}
