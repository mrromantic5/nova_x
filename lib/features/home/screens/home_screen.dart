// lib/features/home/screens/home_screen.dart
//
// NOVA X home screen — v2.2
//   • Header: [logo.png] [NOVA X] on left, [AI, Profile, Settings] on right
//   • Background: persisted user choice (asset or device file), no random fetch
//   • Speed dial: read from LocalDB, + button opens editor
//   • Profile avatar shows uploaded photo or coloured initial
//   • Business name search opens the business's website
//   • Dynamic time-based subtitle (changes every 3 hours)

import 'dart:io';
import 'dart:math';
import 'dart:ui';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:nova_x/core/database/local_db.dart';
import 'package:nova_x/core/services/lens_service.dart';
import 'package:nova_x/features/cyber/screens/cyber_screen.dart';
import 'package:nova_x/features/shield/screens/nova_shield_screen.dart';
import 'package:nova_x/core/services/nova_shield_service.dart';
import 'package:nova_x/features/map/screens/nova_map_screen.dart';
import 'package:nova_x/core/services/api_service.dart';
import 'package:nova_x/core/theme/app_theme.dart';
import 'package:nova_x/core/services/news_service.dart';
import '../../browser/screens/browser_view.dart';
import '../../ai/screens/ai_assistant_screen.dart';
import '../../bookmarks/screens/bookmarks_screen.dart';
import '../../history/screens/history_screen.dart';
import '../../settings/screens/settings_screen.dart';
import '../../profile/screens/profile_screen.dart';
import '../../downloads/screens/downloads_screen.dart';
import '../../business/screens/business_screen.dart';
import '../../customization/screens/customization_screen.dart';
import '../../customization/screens/speed_dial_editor_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _searchCtrl  = TextEditingController();
  final FocusNode             _searchFocus = FocusNode();
  final ScrollController      _scrollCtrl  = ScrollController();
  late AnimationController    _animCtrl;
  late Animation<double>      _fadeAnim;

  // Profile
  String? _profileImgPath;
  String  _profileName = '';

  // Background
  String? _backgroundPath;

  // Speed Dial
  bool _searching   = false;
  bool _lensLoading  = false;
  int  _notifBadge   = 0;   // unread advert count
  List<AdvertModel> _adverts = [];  // true while uploading image to Google
  List<Map<String, dynamic>> _speedDial = [];

  // News
  String                               _selectedCategory = 'For You';
  List<NewsArticle>                    _news             = [];
  final Map<String, List<NewsArticle>> _newsCache        = {};
  bool _loadingNews = false;

  // Search UI state
  List<String> _suggestions = [];
  List<String> _searchHist  = [];
  bool _showSuggest = false;
  bool _isListening = false;

  // Voice
  final SpeechToText _speech      = SpeechToText();
  bool               _speechAvail = false;

  late final String _subtitle;

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

  // ── Dynamic subtitle ───────────────────────────────────────────────────────
  String _buildSubtitle() {
    final h   = DateTime.now().hour;
    final day = DateTime.now().day;
    final rng = Random(day * 8 + h ~/ 3);
    List<String> msgs;
    if (h >= 5 && h < 12) {
      msgs = [
        'Where would you like to go today?',
        "How's your morning going? ☕",
        'Any plans this morning?',
        'Ready to explore the web? 🚀',
        'Start your day with something great!',
        'Coffee and browsing — perfect combo ☕',
        "Morning! What's on your mind?",
        'Rise and browse! 🌄',
      ];
    } else if (h >= 12 && h < 17) {
      msgs = [
        'Having a productive afternoon? 💪',
        'Where would you like to go today?',
        "Afternoon browse? Let's go!",
        "What's on your agenda today?",
        'Keep the momentum going! 🔥',
        'Halfway through the day — explore!',
        'What did you miss this morning?',
        'Power through! The web awaits 💻',
      ];
    } else if (h >= 17 && h < 21) {
      msgs = [
        'Wind down with some browsing 🌆',
        "What's on your evening agenda?",
        'Evening already? Time flies! ⏰',
        'Relax and explore the web 🌅',
        "What's interesting tonight?",
        'Treat yourself to some browsing time 🌇',
        'Unwind and discover something new!',
        "Evening vibes — let's surf 🌊",
      ];
    } else {
      msgs = [
        'Burning the midnight oil? 🌙',
        'Late night browsing session? 🦉',
        'Night owl mode activated! 🌙',
        'The web never sleeps 💫',
        "What are you curious about tonight? ✨",
        'Shh… the world is sleeping 🤫',
        'Stars are out — so is the internet 🌟',
        "Still up? Let's explore 🔦",
      ];
    }
    return msgs[rng.nextInt(msgs.length)];
  }

  @override
  void initState() {
    super.initState();
    _loadNotifBadge();
    AdvertService.init();
    _subtitle = _buildSubtitle();
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800));
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _animCtrl.forward();
    _loadAll();
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

  void _loadAll() {
    final p = LocalDB.getProfile();
    _profileName    = p['name']  as String? ?? '';
    _profileImgPath = LocalDB.getProfileImagePath();
    _backgroundPath = LocalDB.getBackgroundImage();
    _speedDial      = LocalDB.getSpeedDial();
    if (mounted) setState(() {});
  }

  Future<void> _initSpeech() async {
    _speechAvail = await _speech.initialize(
        onError: (_) => setState(() => _isListening = false));
  }

  Future<void> _toggleListen() async {
    if (!_speechAvail) { _showSnack('Microphone not available'); return; }
    HapticFeedback.mediumImpact();
    if (_isListening) {
      _speech.stop(); setState(() => _isListening = false);
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
        localeId: 'en_US', cancelOnError: true, partialResults: false,
      );
    }
  }

  void _onFocusChanged() {
    if (_searchFocus.hasFocus) {
      setState(() { _showSuggest = true; _searchHist = LocalDB.getSearchHistory(); });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollCtrl.hasClients) {
          _scrollCtrl.animateTo(80,
              duration: const Duration(milliseconds: 350), curve: Curves.easeOut);
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

  Future<void> _refreshAll() async {
    _loadAll();
    _searchHist = LocalDB.getSearchHistory();
    _newsCache.clear();
    await _fetchNews(forceRefresh: true);
  }

  Future<void> _fetchNews({bool forceRefresh = false}) async {
    if (!mounted) return;
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

  // ── Visual / Lens search ────────────────────────────────────────────────────
  void _showLensSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(color: AppTheme.divider,
                borderRadius: BorderRadius.circular(2))),

          // Header
          Row(children: [
            Container(width: 44, height: 44,
              decoration: BoxDecoration(
                gradient: AppTheme.primaryGradient,
                borderRadius: BorderRadius.circular(14)),
              child: const Icon(Icons.image_search_rounded,
                  color: Colors.white, size: 22)),
            const SizedBox(width: 14),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Visual Search', style: GoogleFonts.spaceGrotesk(
                  color: AppTheme.textPrimary, fontSize: 18,
                  fontWeight: FontWeight.w800)),
              Text('Search by image using Google',
                  style: GoogleFonts.inter(
                      color: AppTheme.textHint, fontSize: 12)),
            ]),
          ]),
          const SizedBox(height: 24),

          // Camera option
          _lensOption(
            Icons.camera_alt_rounded,
            'Take a Photo',
            'Use camera to capture and search',
            AppTheme.accentCyan,
            () async {
              Navigator.pop(context);
              await _doLensSearch(fromCamera: true);
            },
          ),
          const SizedBox(height: 12),

          // Gallery option
          _lensOption(
            Icons.photo_library_rounded,
            'Choose from Gallery',
            'Pick an existing photo and search',
            AppTheme.accentPurple,
            () async {
              Navigator.pop(context);
              await _doLensSearch(fromCamera: false);
            },
          ),
          const SizedBox(height: 16),

          // Info note
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.bgElevated,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.divider),
            ),
            child: Row(children: [
              const Icon(Icons.info_outline_rounded,
                  color: AppTheme.textHint, size: 14),
              const SizedBox(width: 8),
              Expanded(child: Text(
                'Identifies objects, products, landmarks, '
                'text in images and finds visually similar pages.',
                style: GoogleFonts.inter(
                    color: AppTheme.textHint, fontSize: 11, height: 1.5),
              )),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _lensOption(IconData icon, String title, String subtitle,
      Color color, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: color.withOpacity(0.07),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withOpacity(0.25)),
          ),
          child: Row(children: [
            Container(width: 44, height: 44,
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: color, size: 22)),
            const SizedBox(width: 14),
            Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: GoogleFonts.spaceGrotesk(
                  color: AppTheme.textPrimary, fontSize: 15,
                  fontWeight: FontWeight.w700)),
              Text(subtitle, style: GoogleFonts.inter(
                  color: AppTheme.textHint, fontSize: 12)),
            ])),
            Icon(Icons.arrow_forward_ios_rounded,
                color: color, size: 14),
          ]),
        ),
      );

  Future<void> _doLensSearch({required bool fromCamera}) async {
    setState(() => _lensLoading = true);
    _snack('📷 Preparing image…');

    final html = await LensService.buildSearchPage(fromCamera: fromCamera);

    setState(() => _lensLoading = false);

    if (html == null) return;

    if (mounted) {
      Navigator.push(context, MaterialPageRoute(
          builder: (_) => BrowserView(
            initialQuery: 'https://www.google.com',
            htmlContent: html,
          )));
    }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(msg, style: GoogleFonts.inter(color: Colors.white)),
      backgroundColor: AppTheme.bgElevated,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));

  Future<void> _go(String query) async {
    if (_searching) return;
    final q = query.trim();
    if (q.isEmpty) return;

    _searchCtrl.clear();
    _searchFocus.unfocus();
    setState(() { _showSuggest = false; _suggestions = []; _searching = true; });
    LocalDB.addSearchQuery(q);
    _searchHist = LocalDB.getSearchHistory();

    // Server-side business lookup (bumps search_count)
    final biz = await ApiService.searchBusiness(q);
    if (!mounted) return;
    setState(() => _searching = false);

    final website = ((biz?['website'] as String?) ?? '').trim();
    if (biz != null && website.isNotEmpty) {
      final bizId = biz['id'] as int?;
      if (bizId != null) ApiService.recordBusinessVisit(bizId);
      HapticFeedback.lightImpact();
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => BrowserView(initialQuery: website)));
      return;
    }

    HapticFeedback.lightImpact();
    Navigator.push(context,
        MaterialPageRoute(
            builder: (_) => BrowserView(initialQuery: LocalDB.buildSearchUrl(q))));
  }

  void _push(Widget screen) => Navigator.push(context,
      PageRouteBuilder(
        pageBuilder: (_, a, __) => screen,
        transitionsBuilder: (_, a, __, child) => SlideTransition(
          position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
              .animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
          child: child,
        ),
        transitionDuration: const Duration(milliseconds: 280),
      )).then((_) => _loadAll());

  void _showSnack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(msg, style: GoogleFonts.inter(color: Colors.white)),
          backgroundColor: AppTheme.bgElevated,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));

  String _greeting() {
    final h = DateTime.now().hour;
    final name = _profileName.split(' ').first;
    final disp = name.isNotEmpty ? ', $name' : '';
    if (h >= 5  && h < 12) return '☀️ Good morning$disp!';
    if (h >= 12 && h < 17) return '🌤️ Good afternoon$disp!';
    if (h >= 17 && h < 21) return '🌆 Good evening$disp!';
    return '🌙 Good night$disp!';
  }

  Color _avatarColor() {
    final p = LocalDB.getProfile();
    return switch (p['avatarColor'] ?? 'cyan') {
      'red'    => const Color(0xFFFF6B6B),
      'orange' => const Color(0xFFFFAB00),
      'purple' => AppTheme.accentPurple,
      'green'  => AppTheme.success,
      _        => AppTheme.accentCyan,
    };
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ── Notification badge ─────────────────────────────────────────────────
  Future<void> _loadNotifBadge() async {
    await AdvertService.init();
    final ads = await AdvertService.fetchAdverts();
    if (!mounted) return;
    setState(() {
      _adverts    = ads;
      _notifBadge = AdvertService.getUnreadCount(ads);
    });
  }

  Future<void> _openNotifications() async {
    await Navigator.push(context, MaterialPageRoute(
        builder: (_) => const NotificationsScreen()));
    // After returning, reload badge (user may have read some)
    _loadNotifBadge();
  }

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
                child: RefreshIndicator(
                  onRefresh: _refreshAll,
                  color: AppTheme.accentCyan,
                  backgroundColor: AppTheme.bgCard,
                  child: SingleChildScrollView(
                    controller: _scrollCtrl,
                    physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
            ),
              _buildBottomNav(),
            ]),
          ),
        ),
        if (_isListening) _buildListeningOverlay(),
      ]),
    );
  }

  // ── Background — persisted user choice ─────────────────────────────────────
  Widget _buildBackground() {
    final bg = _backgroundPath ?? 'assets/backgrounds/default.jpg';
    Widget layer;
    if (bg == null || bg.isEmpty) {
      layer = Container(decoration: const BoxDecoration(gradient: AppTheme.bgGradient));
    } else if (bg.startsWith('assets/')) {
      layer = Image.asset(bg,
          fit: BoxFit.cover, width: double.infinity, height: double.infinity,
          errorBuilder: (_, __, ___) =>
              Container(decoration: const BoxDecoration(gradient: AppTheme.bgGradient)));
    } else {
      layer = Image.file(File(bg),
          fit: BoxFit.cover, width: double.infinity, height: double.infinity,
          errorBuilder: (_, __, ___) =>
              Container(decoration: const BoxDecoration(gradient: AppTheme.bgGradient)));
    }

    return Positioned.fill(child: Stack(children: [
      Positioned.fill(child: layer),
      Container(decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [Color(0xD507101E), Color(0x9507101E), Color(0xEE07101E)],
          stops: [0.0, 0.45, 1.0],
        ),
      )),
    ]));
  }

  // ── Header: [logo + NOVA X] on left, [AI, Profile, Settings] on right ─────
  Widget _buildHeader() {
    final imgPath = _profileImgPath;
    final color   = _avatarColor();
    final initial = _profileName.isNotEmpty ? _profileName[0].toUpperCase() : 'N';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Row(children: [
        // Logo
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            gradient: LinearGradient(
              colors: [AppTheme.accentCyan.withOpacity(0.15),
                       AppTheme.accentPurple.withOpacity(0.10)],
            ),
          ),
          clipBehavior: Clip.hardEdge,
          child: Image.asset(
            'assets/images/logo.png',
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => ShaderMask(
              shaderCallback: (b) => AppTheme.primaryGradient.createShader(b),
              child: const Icon(Icons.public_rounded,
                  color: Colors.white, size: 22),
            ),
          ),
        ),
        const SizedBox(width: 10),
        ShaderMask(
          shaderCallback: (b) => AppTheme.primaryGradient.createShader(b),
          child: Text('NOVA X', style: GoogleFonts.spaceGrotesk(
              fontSize: 22, fontWeight: FontWeight.w800,
              color: Colors.white, letterSpacing: 2)),
        ),
        const Spacer(),
        // AI
        _hBtn(Icons.psychology_outlined, () => _push(const AiAssistantScreen())),
        const SizedBox(width: 8),
        // Profile (replaces the old incognito slot)
        GestureDetector(
          onTap: () => _push(const ProfileScreen()),
          child: Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: color, width: 2),
              boxShadow: [BoxShadow(color: color.withOpacity(0.35),
                  blurRadius: 10, spreadRadius: 1)],
            ),
            child: ClipOval(
              child: imgPath != null
                  ? Image.file(File(imgPath), fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _avatarPlaceholder(color, initial))
                  : _avatarPlaceholder(color, initial),
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Settings
        _hBtn(Icons.settings_outlined, () => _push(const SettingsScreen())),
      ]),
    );
  }

  Widget _avatarPlaceholder(Color color, String initial) => Container(
    color: color.withOpacity(0.15),
    child: Center(child: Text(initial, style: GoogleFonts.spaceGrotesk(
        color: color, fontSize: 18, fontWeight: FontWeight.w800))),
  );

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

  // ── Greeting + Search ──────────────────────────────────────────────────────
  Widget _buildGreetingAndSearch() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_greeting(), style: GoogleFonts.spaceGrotesk(
            color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(_subtitle, style: GoogleFonts.inter(
            color: AppTheme.textHint, fontSize: 13)),
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
                  Icon(_isListening ? Icons.hearing : Icons.search,
                      color: _isListening ? Colors.redAccent : AppTheme.accentCyan,
                      size: 22),
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
                            : 'Search, URL or business name…',
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
                            ? Colors.red.withOpacity(0.2) : Colors.transparent,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                          _isListening ? Icons.mic : Icons.mic_none_rounded,
                          color: _isListening ? Colors.redAccent : AppTheme.textHint,
                          size: 20),
                    ),
                  ),
                  const SizedBox(width: 4),
                  // ── Lens / Camera search button ──────────────────
                  GestureDetector(
                    onTap: _showLensSheet,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.all(8),
                      child: _lensLoading
                          ? const SizedBox(width: 20, height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppTheme.accentCyan))
                          : const Icon(Icons.image_search_rounded,
                              color: AppTheme.accentCyan, size: 22),
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
                      child: const Icon(Icons.arrow_forward,
                          color: Colors.white, size: 16),
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
                  child: Column(children: [
                    if (_searchCtrl.text.isEmpty && _searchHist.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Recent', style: GoogleFonts.inter(
                                color: AppTheme.textHint, fontSize: 11,
                                fontWeight: FontWeight.w600, letterSpacing: 0.8)),
                            GestureDetector(
                              onTap: () async {
                                await LocalDB.clearSearchHistory();
                                setState(() => _searchHist = []);
                              },
                              child: Text('Clear', style: GoogleFonts.inter(
                                  color: AppTheme.danger, fontSize: 11)),
                            ),
                          ],
                        ),
                      ),
                      ..._searchHist.take(5).map((h) => _sugTile(
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
                      ..._suggestions.map((s) => _sugTile(
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
                  ]),
                ),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _sugTile(IconData icon, String text, {Widget? trailing}) =>
      GestureDetector(
        onTap: () => _go(text),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(children: [
            Icon(icon, color: AppTheme.textHint, size: 16),
            const SizedBox(width: 12),
            Expanded(child: Text(text, style: GoogleFonts.inter(
                color: AppTheme.textSecondary, fontSize: 14),
                maxLines: 1, overflow: TextOverflow.ellipsis)),
            if (trailing != null) trailing,
          ]),
        ),
      );

  Widget _buildSection(String title, Widget child) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: Text(title, style: GoogleFonts.spaceGrotesk(
            color: AppTheme.textHint, fontSize: 11,
            fontWeight: FontWeight.w700, letterSpacing: 1.2)),
      ),
      child,
    ],
  );

  // ── Speed Dial — last cell is + button to edit ─────────────────────────────
  Widget _buildSpeedDial() {
    final itemCount = _speedDial.length + 1; // +1 for the (+) tile
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 5, mainAxisSpacing: 14,
          crossAxisSpacing: 14, childAspectRatio: 0.8,
        ),
        itemCount: itemCount,
        itemBuilder: (_, i) {
          // Last cell = (+) editor
          if (i == _speedDial.length) return _dialAddTile();
          final site   = _speedDial[i];
          final domain = site['domain'] as String? ?? '';
          return GestureDetector(
            onTap: () => _go(site['url'] as String),
            onLongPress: () => _push(const SpeedDialEditorScreen()),
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
                  child: Image.network(
                    'https://www.google.com/s2/favicons?domain=$domain&sz=64',
                    width: 52, height: 52, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Center(child: Text(
                      (site['name'] as String? ?? '?')[0],
                      style: GoogleFonts.spaceGrotesk(
                          color: AppTheme.accentCyan,
                          fontSize: 20, fontWeight: FontWeight.w800))),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(site['name'] as String? ?? '',
                  style: GoogleFonts.inter(
                      color: AppTheme.textSecondary, fontSize: 9.5,
                      fontWeight: FontWeight.w500),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center),
            ]),
          );
        },
      ),
    );
  }

  /// The (+) tile that opens the speed-dial editor.
  Widget _dialAddTile() {
    return GestureDetector(
      onTap: () => _push(const SpeedDialEditorScreen()),
      child: Column(children: [
        Container(
          width: 52, height: 52,
          decoration: BoxDecoration(
            color: AppTheme.accentCyan.withOpacity(0.10),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: AppTheme.accentCyan.withOpacity(0.4),
                width: 1.5,
                style: BorderStyle.solid),
          ),
          child: const Icon(Icons.add_rounded,
              color: AppTheme.accentCyan, size: 28),
        ),
        const SizedBox(height: 6),
        Text('Add',
            style: GoogleFonts.inter(
                color: AppTheme.accentCyan, fontSize: 9.5,
                fontWeight: FontWeight.w600),
            maxLines: 1, textAlign: TextAlign.center),
      ]),
    );
  }

  // ── Feature row ────────────────────────────────────────────────────────────
  Widget _buildFeatureRow() {
    final items = [
      {'icon': Icons.psychology_outlined,      'label': 'AI Chat',
       'color': AppTheme.accentCyan,
       'fn': () => _push(const AiAssistantScreen())},
      {'icon': Icons.bookmark_border_rounded,  'label': 'Bookmarks',
       'color': const Color(0xFFFFAB00),
       'fn': () => _push(const BookmarksScreen())},
      {'icon': Icons.download_outlined,        'label': 'Downloads',
       'color': AppTheme.primaryBlue,
       'fn': () => _push(const DownloadsScreen())},
      {'icon': Icons.business_center_outlined, 'label': 'Business',
       'color': AppTheme.accentPurple,
       'fn': () => _push(const BusinessScreen())},
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: List.generate(items.length, (i) {
          final color = items[i]['color'] as Color;
          return Expanded(
            child: GestureDetector(
              onTap: items[i]['fn'] as VoidCallback,
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
                  Icon(items[i]['icon'] as IconData, color: color, size: 22),
                  const SizedBox(height: 6),
                  Text(items[i]['label'] as String,
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

  // ── News section ───────────────────────────────────────────────────────────
  Widget _buildNewsSection() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: Row(children: [
          Text('Latest News', style: GoogleFonts.spaceGrotesk(
              color: AppTheme.textHint, fontSize: 11,
              fontWeight: FontWeight.w700, letterSpacing: 1.2)),
          const Spacer(),
          GestureDetector(
            onTap: () { _newsCache.remove(_selectedCategory); _fetchNews(forceRefresh: true); },
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
                Text('Refresh', style: GoogleFonts.inter(
                    color: AppTheme.accentCyan, fontSize: 10, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
        ]),
      ),
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
                      width: active ? 1.5 : 1),
                ),
                child: Text(cat, style: GoogleFonts.inter(
                    color: active ? color : AppTheme.textSecondary,
                    fontSize: 12,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500)),
              ),
            );
          },
        ),
      ),
      const SizedBox(height: 16),
      _buildNewsBody(),
    ],
  );

  Widget _buildNewsBody() {
    if (_loadingNews) return Column(children: [
      const SizedBox(height: 20),
      Center(child: CircularProgressIndicator(
          color: _catColor[_selectedCategory] ?? AppTheme.accentCyan, strokeWidth: 2)),
      const SizedBox(height: 12),
      Text('Fetching news…',
          style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 12)),
      const SizedBox(height: 20),
    ]);

    if (_news.isEmpty) return Padding(
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

    return Column(children: [
      if (_news.first.imageUrl.isNotEmpty) _heroNewsCard(_news.first),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(children: List.generate(
          _news.length > 1 ? _news.length - 1 : 0,
          (i) {
            final a = _news[i + 1];
            return Column(children: [
              if (i == 0 && _news.first.imageUrl.isNotEmpty) const SizedBox(height: 4),
              _compactNewsCard(a),
              if (i < _news.length - 2)
                Divider(color: AppTheme.divider.withOpacity(0.6), height: 1),
            ]);
          },
        )),
      ),
    ]);
  }

  Widget _heroNewsCard(NewsArticle a) {
    final color = _catColor[_selectedCategory] ?? AppTheme.accentCyan;
    return GestureDetector(
      onTap: () => _go(a.url),
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
            Stack(children: [
              SizedBox(
                height: 200, width: double.infinity,
                child: Image.network(a.imageUrl, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(height: 200,
                    color: AppTheme.bgElevated,
                    child: Center(child: Icon(Icons.image_not_supported_outlined,
                        color: AppTheme.textHint, size: 36)))),
              ),
              Positioned.fill(child: Container(decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  colors: [Colors.transparent, AppTheme.bgCard.withOpacity(0.7)],
                  stops: const [0.5, 1.0],
                )))),
              Positioned(top: 12, left: 12, child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(20)),
                child: Text(_selectedCategory, style: GoogleFonts.inter(
                    color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
              )),
            ]),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(a.title, style: GoogleFonts.spaceGrotesk(
                    color: AppTheme.textPrimary, fontSize: 15,
                    fontWeight: FontWeight.w700, height: 1.4),
                    maxLines: 3, overflow: TextOverflow.ellipsis),
                if (a.description.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(a.description, style: GoogleFonts.inter(
                      color: AppTheme.textSecondary, fontSize: 12, height: 1.4),
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
                const SizedBox(height: 10),
                Row(children: [
                  Container(width: 6, height: 6,
                      decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Expanded(child: Text(a.source, style: GoogleFonts.inter(
                      color: color, fontSize: 11, fontWeight: FontWeight.w600),
                      maxLines: 1, overflow: TextOverflow.ellipsis)),
                  if (a.timeAgo.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Text(a.timeAgo, style: GoogleFonts.inter(
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

  Widget _compactNewsCard(NewsArticle a) => GestureDetector(
    onTap: () => _go(a.url),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 13),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Flexible(child: Text(a.source, style: GoogleFonts.inter(
                color: _catColor[_selectedCategory] ?? AppTheme.accentCyan,
                fontSize: 10.5, fontWeight: FontWeight.w600),
                maxLines: 1, overflow: TextOverflow.ellipsis)),
            if (a.timeAgo.isNotEmpty)
              Text('  ·  ${a.timeAgo}', style: GoogleFonts.inter(
                  color: AppTheme.textHint, fontSize: 10.5)),
          ]),
          const SizedBox(height: 5),
          Text(a.title, style: GoogleFonts.inter(
              color: AppTheme.textPrimary, fontSize: 13.5,
              fontWeight: FontWeight.w500, height: 1.4),
              maxLines: 2, overflow: TextOverflow.ellipsis),
        ])),
        if (a.imageUrl.isNotEmpty) ...[
          const SizedBox(width: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(a.imageUrl, width: 78, height: 62,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink()),
          ),
        ],
      ]),
    ),
  );

  // ── Bottom nav ─────────────────────────────────────────────────────────────
  Widget _buildBottomNav() => Container(
    margin: const EdgeInsets.fromLTRB(20, 0, 20, 14),
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
    decoration: BoxDecoration(
      color: AppTheme.bgCard,
      borderRadius: BorderRadius.circular(32),
      border: Border.all(color: AppTheme.divider),
      boxShadow: AppTheme.cardShadow,
    ),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
      _navBtn(Icons.home_rounded,            'Home',     null,                                  true),
      _navBtn(Icons.bookmark_rounded,        'Saved',    () => _push(const BookmarksScreen()),  false),
      _navBtn(Icons.download_rounded,        'Downloads',() => _push(const DownloadsScreen()),   false),
      _navBtn(Icons.business_center_rounded, 'Business', () => _push(const BusinessScreen()),    false),
      _notifNavBtn(),
      _navBtn(Icons.more_horiz_rounded,      'Menu',     _showMenu,                             false),
    ]),
  );

  Widget _navBtn(IconData icon, String label, VoidCallback? onTap, bool active) =>
      GestureDetector(
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
            Text(label, style: GoogleFonts.inter(
                color: active ? Colors.white : AppTheme.textHint, fontSize: 9,
                fontWeight: active ? FontWeight.w700 : FontWeight.w400)),
          ]),
        ),
      );

  // Bell icon with badge count overlay
  Widget _notifNavBtn() => GestureDetector(
    onTap: _openNotifications,
    child: SizedBox(
      width: 56,
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Stack(clipBehavior: Clip.none, children: [
          Icon(Icons.notifications_rounded,
              color: _notifBadge > 0
                  ? AppTheme.accentCyan : AppTheme.textHint,
              size: 24),
          if (_notifBadge > 0)
            Positioned(
              top: -4, right: -6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: AppTheme.danger,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppTheme.bgCard, width: 1.5),
                ),
                constraints: const BoxConstraints(minWidth: 16),
                child: Text(
                  _notifBadge > 99 ? '99+' : '$_notifBadge',
                  style: GoogleFonts.inter(
                      color: Colors.white, fontSize: 9,
                      fontWeight: FontWeight.w900),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ]),
        const SizedBox(height: 3),
        Text('Notifications', style: GoogleFonts.inter(
            color: _notifBadge > 0
                ? AppTheme.accentCyan : AppTheme.textHint,
            fontSize: 9.5, fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis),
      ]),
    ),
  );


  Widget _buildListeningOverlay() => Positioned(
    bottom: 100, left: 0, right: 0,
    child: Center(child: Container(
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
        Text('Listening… tap mic to stop', style: GoogleFonts.inter(
            color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
      ]),
    )),
  );

  void _showMenu() => showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _MenuSheet(
      onPush: _push,
      onIncognito: () => Navigator.push(context, MaterialPageRoute(
          builder: (_) => const BrowserView(
              initialQuery: 'https://www.google.com', incognito: true))),
    ),
  );
}

// ═════════════════════════════════════════════════════════════════════════════
class _MenuSheet extends StatelessWidget {
  final void Function(Widget) onPush;
  final VoidCallback onIncognito;
  const _MenuSheet({required this.onPush, required this.onIncognito});

  // ── Notification badge ─────────────────────────────────────────────────
  Future<void> _loadNotifBadge() async {
    await AdvertService.init();
    final ads = await AdvertService.fetchAdverts();
    if (!mounted) return;
    setState(() {
      _adverts    = ads;
      _notifBadge = AdvertService.getUnreadCount(ads);
    });
  }

  Future<void> _openNotifications() async {
    await Navigator.push(context, MaterialPageRoute(
        builder: (_) => const NotificationsScreen()));
    // After returning, reload badge (user may have read some)
    _loadNotifBadge();
  }

  @override
  Widget build(BuildContext context) {
    final items = [
      {'icon': Icons.psychology_outlined,      'label': 'AI Chat',     'color': AppTheme.accentCyan,
       'fn': () { Navigator.pop(context); onPush(const AiAssistantScreen()); }},
      {'icon': Icons.bookmark_border_rounded,  'label': 'Bookmarks',   'color': const Color(0xFFFFAB00),
       'fn': () { Navigator.pop(context); onPush(const BookmarksScreen()); }},
      {'icon': Icons.download_outlined,        'label': 'Downloads',   'color': AppTheme.primaryBlue,
       'fn': () { Navigator.pop(context); onPush(const DownloadsScreen()); }},
      {'icon': Icons.history_rounded,          'label': 'History',     'color': AppTheme.accentPurple,
       'fn': () { Navigator.pop(context); onPush(const HistoryScreen()); }},
      {'icon': Icons.business_center_outlined, 'label': 'Business',    'color': const Color(0xFFFF6B6B),
       'fn': () { Navigator.pop(context); onPush(const BusinessScreen()); }},
      {'icon': Icons.palette_outlined,         'label': 'Customize',   'color': AppTheme.accentCyan,
       'fn': () { Navigator.pop(context); onPush(const CustomizationScreen()); }},
      {'icon': Icons.person_outline_rounded,   'label': 'Profile',     'color': AppTheme.success,
       'fn': () { Navigator.pop(context); onPush(const ProfileScreen()); }},
      {'icon': Icons.settings_outlined,        'label': 'Settings',    'color': AppTheme.primaryBlue,
       'fn': () { Navigator.pop(context); onPush(const SettingsScreen()); }},
      {'icon': Icons.map_rounded,               'label': 'NOVA Map',   'color': const Color(0xFF00C853),
       'fn': () { Navigator.pop(context); onPush(const NovaMapScreen()); }},
      {'icon': Icons.shield_rounded,            'label': 'NOVA Shield','color': AppTheme.accentCyan,
       'fn': () { Navigator.pop(context); onPush(const NovaShieldScreen()); }},
      {'icon': Icons.security_rounded,          'label': 'NOVA Cyber', 'color': const Color(0xFF7C4DFF),
       'fn': () { Navigator.pop(context); onPush(const CyberScreen()); }},
      {'icon': Icons.person_off_outlined,       'label': 'Incognito',  'color': AppTheme.accentPurple,
       'fn': () { Navigator.pop(context); onIncognito(); }},
    ];
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 20),
          decoration: BoxDecoration(color: AppTheme.textHint,
              borderRadius: BorderRadius.circular(2))),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 4,
          mainAxisSpacing: 14, crossAxisSpacing: 14, childAspectRatio: 0.85,
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
                    style: GoogleFonts.inter(color: AppTheme.textSecondary,
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
}
