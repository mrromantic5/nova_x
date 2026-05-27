// lib/features/business/screens/business_screen.dart
//
// NOVA X Business — global directory backed by server.
// Fetches ranked businesses from /api/v1/businesses.
// Tap → opens the business website + bumps search_count server-side.

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nova_x/core/services/api_service.dart';
import 'package:nova_x/core/theme/app_theme.dart';
import '../../browser/screens/browser_view.dart';
import '../../profile/screens/profile_screen.dart';

const List<String> _cats = [
  'All', 'Technology', 'Food & Drinks', 'Fashion', 'Health & Beauty',
  'Finance', 'Education', 'Entertainment', 'Real Estate',
  'Retail', 'Services', 'Other',
];

const Map<String, Color> _catColors = {
  'All':             Color(0xFF00D4FF),
  'Technology':      Color(0xFF7C4DFF),
  'Food & Drinks':   Color(0xFFFF6B6B),
  'Fashion':         Color(0xFFFF4081),
  'Health & Beauty': Color(0xFF00C853),
  'Finance':         Color(0xFFFFAB00),
  'Education':       Color(0xFF1E7BFF),
  'Entertainment':   Color(0xFFFF6B6B),
  'Real Estate':     Color(0xFF00BCD4),
  'Retail':          Color(0xFFFF9800),
  'Services':        Color(0xFF4CAF50),
  'Other':           Color(0xFF9E9E9E),
};

const Map<String, IconData> _catIcons = {
  'All':             Icons.apps_rounded,
  'Technology':      Icons.computer_rounded,
  'Food & Drinks':   Icons.restaurant_rounded,
  'Fashion':         Icons.checkroom_rounded,
  'Health & Beauty': Icons.spa_rounded,
  'Finance':         Icons.account_balance_rounded,
  'Education':       Icons.school_rounded,
  'Entertainment':   Icons.movie_rounded,
  'Real Estate':     Icons.home_work_rounded,
  'Retail':          Icons.shopping_bag_rounded,
  'Services':        Icons.miscellaneous_services_rounded,
  'Other':           Icons.more_horiz_rounded,
};

class BusinessScreen extends StatefulWidget {
  const BusinessScreen({super.key});
  @override
  State<BusinessScreen> createState() => _BusinessScreenState();
}

class _BusinessScreenState extends State<BusinessScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _searchCtrl = TextEditingController();
  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;

  String _selectedCat = 'All';
  String _query = '';
  List<Map<String, dynamic>> _all = [];
  List<Map<String, dynamic>> _filtered = [];
  List<String> _suggestions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _animCtrl.forward();
    _load();
    _searchCtrl.addListener(_onSearch);
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_onSearch);
    _searchCtrl.dispose();
    _animCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    _all = await ApiService.getBusinesses();
    _filtered = _applyFilter(_all, _selectedCat, _query);
    if (mounted) setState(() => _loading = false);
  }

  List<Map<String, dynamic>> _applyFilter(
      List<Map<String, dynamic>> src, String cat, String q) {
    final q2 = q.toLowerCase().trim();
    return src.where((b) {
      final matchCat = cat == 'All' || b['category'] == cat;
      final name = (b['name'] as String?) ?? '';
      final desc = (b['description'] as String?) ?? '';
      final loc  = (b['location'] as String?) ?? '';
      final matchQ = q2.isEmpty ||
          name.toLowerCase().contains(q2) ||
          desc.toLowerCase().contains(q2) ||
          loc.toLowerCase().contains(q2);
      return matchCat && matchQ;
    }).toList();
  }

  void _onSearch() {
    final q = _searchCtrl.text;
    setState(() {
      _query = q;
      _filtered = _applyFilter(_all, _selectedCat, q);
      if (q.trim().isEmpty) {
        _suggestions = [];
      } else {
        final qLower = q.toLowerCase();
        _suggestions = _all
            .where((b) =>
                ((b['name'] as String?) ?? '').toLowerCase().contains(qLower))
            .map((b) => (b['name'] as String?) ?? '')
            .where((n) => n.isNotEmpty)
            .take(5)
            .toList();
      }
    });
  }

  void _switchCat(String cat) {
    setState(() {
      _selectedCat = cat;
      _filtered = _applyFilter(_all, cat, _query);
    });
  }

  void _openBusiness(Map<String, dynamic> biz) {
    final url = ((biz['website'] as String?) ?? '').trim();
    if (url.isEmpty) {
      _snack('No website listed for this business');
      return;
    }
    Navigator.push(context, MaterialPageRoute(
        builder: (_) => BrowserView(initialQuery: url)))
        .then((_) => _load());
  }

  void _goAddBusiness() {
    Navigator.push(context, MaterialPageRoute(
        builder: (_) => const ProfileScreen())).then((_) => _load());
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg, style: GoogleFonts.inter(color: Colors.white)),
        backgroundColor: AppTheme.bgElevated,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));

  // ═══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: Stack(children: [
          _glow(top: -80, right: -80, color: AppTheme.accentCyan),
          _glow(bottom: 100, left: -60, color: AppTheme.accentPurple),
          SafeArea(child: Column(children: [
            _buildHeader(),
            _buildSearchBar(),
            if (_suggestions.isNotEmpty) _buildSuggestions(),
            _buildCategoryBar(),
            Expanded(child: _buildBody()),
          ])),
        ]),
      ),
    );
  }

  Widget _glow({double? top, double? bottom, double? left, double? right,
      required Color color}) =>
      Positioned(
        top: top, bottom: bottom, left: left, right: right,
        child: Container(
          width: 220, height: 220,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [
              color.withOpacity(0.12), Colors.transparent,
            ]),
          ),
        ),
      );

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(children: [
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: AppTheme.bgCard,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.arrow_back_ios_new_rounded,
                color: AppTheme.textSecondary, size: 15),
          ),
        ),
        const SizedBox(width: 14),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ShaderMask(
            shaderCallback: (b) => AppTheme.primaryGradient.createShader(b),
            child: Text('NOVA X BUSINESS', style: GoogleFonts.spaceGrotesk(
                color: Colors.white, fontSize: 18,
                fontWeight: FontWeight.w800, letterSpacing: 1)),
          ),
          Text(
            '${_all.length} global listing${_all.length == 1 ? '' : 's'} · ranked by popularity',
            style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 11),
          ),
        ]),
        const Spacer(),
        GestureDetector(
          onTap: _goAddBusiness,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              gradient: AppTheme.primaryGradient,
              borderRadius: BorderRadius.circular(20),
              boxShadow: AppTheme.glowShadow,
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.add_rounded, color: Colors.white, size: 14),
              const SizedBox(width: 4),
              Text('Add Yours', style: GoogleFonts.inter(
                  color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.bgCard.withOpacity(0.8),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppTheme.divider),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(children: [
              const Icon(Icons.search_rounded,
                  color: AppTheme.accentCyan, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: 'Search businesses by name or location…',
                    hintStyle: GoogleFonts.inter(
                        color: Colors.white38, fontSize: 14),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              if (_query.isNotEmpty)
                GestureDetector(
                  onTap: () {
                    _searchCtrl.clear();
                    FocusScope.of(context).unfocus();
                  },
                  child: const Icon(Icons.close_rounded,
                      color: AppTheme.textHint, size: 18),
                ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _buildSuggestions() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      decoration: BoxDecoration(
        color: AppTheme.bgElevated,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(
        children: _suggestions.map((s) => ListTile(
          dense: true,
          leading: const Icon(Icons.business_rounded,
              color: AppTheme.accentCyan, size: 16),
          title: Text(s, style: GoogleFonts.inter(
              color: AppTheme.textPrimary, fontSize: 13)),
          onTap: () {
            _searchCtrl.text = s;
            FocusScope.of(context).unfocus();
          },
        )).toList(),
      ),
    );
  }

  Widget _buildCategoryBar() {
    return Container(
      height: 90,
      margin: const EdgeInsets.only(top: 16),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: _cats.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) {
          final cat = _cats[i];
          final active = cat == _selectedCat;
          final color = _catColors[cat] ?? AppTheme.accentCyan;
          final icon = _catIcons[cat] ?? Icons.category_rounded;
          final cnt = cat == 'All'
              ? _all.length
              : _all.where((b) => b['category'] == cat).length;
          return GestureDetector(
            onTap: () => _switchCat(cat),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 72,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                gradient: active
                    ? LinearGradient(
                        colors: [color.withOpacity(0.3), color.withOpacity(0.1)],
                        begin: Alignment.topCenter, end: Alignment.bottomCenter)
                    : null,
                color: active ? null : AppTheme.bgCard,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: active ? color : AppTheme.divider,
                    width: active ? 1.5 : 1),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: active ? color : AppTheme.textHint, size: 20),
                  const SizedBox(height: 5),
                  Text(cat == 'All' ? 'All' : cat.split(' ').first,
                      style: GoogleFonts.inter(
                          color: active ? color : AppTheme.textHint,
                          fontSize: 9, fontWeight: FontWeight.w600),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center),
                  Text('$cnt', style: GoogleFonts.inter(
                      color: active ? color.withOpacity(0.8) : AppTheme.textHint,
                      fontSize: 8)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(
          color: AppTheme.accentCyan, strokeWidth: 2));
    }
    if (_all.isEmpty) return _buildEmptyAll();
    if (_filtered.isEmpty) return _buildEmptyFilter();

    return RefreshIndicator(
      onRefresh: _load,
      color: AppTheme.accentCyan,
      backgroundColor: AppTheme.bgCard,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
        itemCount: _filtered.length,
        itemBuilder: (_, i) {
          final biz = _filtered[i];
          final searchCount = (biz['search_count'] as int?) ?? 0;
          final isTrending = i == 0
              && _query.isEmpty
              && _selectedCat == 'All'
              && searchCount > 0;
          return i == 0
              ? _buildHeroCard(biz, isTrending: isTrending)
              : _buildCompactCard(biz, rank: i + 1);
        },
      ),
    );
  }

  Widget _buildHeroCard(Map<String, dynamic> biz, {required bool isTrending}) {
    final imgUrl = biz['image_url'] as String?;
    final cat = (biz['category'] as String?) ?? 'Other';
    final color = _catColors[cat] ?? AppTheme.accentCyan;
    final website = ((biz['website'] as String?) ?? '').trim();
    final hasUrl = website.isNotEmpty;
    final searchCount = (biz['search_count'] as int?) ?? 0;
    final location = (biz['location'] as String?) ?? '';
    final description = (biz['description'] as String?) ?? '';

    return GestureDetector(
      onTap: () => _openBusiness(biz),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
              color: isTrending
                  ? AppTheme.warning.withOpacity(0.4)
                  : AppTheme.divider),
          boxShadow: AppTheme.cardShadow,
        ),
        clipBehavior: Clip.hardEdge,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Stack(children: [
            SizedBox(
              height: 180, width: double.infinity,
              child: imgUrl != null
                  ? Image.network(imgUrl, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _imagePlaceholder(180, color))
                  : _imagePlaceholder(180, color),
            ),
            Positioned(top: 12, left: 12, child: _catBadge(cat, color)),
            if (isTrending)
              Positioned(top: 12, right: 12, child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [Color(0xFFFF8800), Color(0xFFFFAB00)]),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(
                      color: AppTheme.warning.withOpacity(0.4), blurRadius: 8)],
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Text('🔥', style: TextStyle(fontSize: 11)),
                  const SizedBox(width: 4),
                  Text('TRENDING', style: GoogleFonts.inter(
                      color: Colors.white, fontSize: 9,
                      fontWeight: FontWeight.w800, letterSpacing: 0.5)),
                ]),
              ))
            else
              Positioned(top: 12, right: 12, child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 6, height: 6,
                    decoration: const BoxDecoration(
                        color: AppTheme.success, shape: BoxShape.circle)),
                  const SizedBox(width: 4),
                  Text('Active', style: GoogleFonts.inter(
                      color: Colors.white, fontSize: 9,
                      fontWeight: FontWeight.w700)),
                ]),
              )),
          ]),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(
                    (biz['name'] as String?) ?? '',
                    style: GoogleFonts.spaceGrotesk(
                        color: AppTheme.textPrimary,
                        fontSize: 18, fontWeight: FontWeight.w700))),
                if (searchCount > 0) ...[
                  const SizedBox(width: 8),
                  Row(children: [
                    const Icon(Icons.visibility_outlined,
                        color: AppTheme.textHint, size: 12),
                    const SizedBox(width: 3),
                    Text('$searchCount', style: GoogleFonts.inter(
                        color: AppTheme.textHint, fontSize: 11,
                        fontWeight: FontWeight.w600)),
                  ]),
                ],
              ]),
              const SizedBox(height: 4),
              if (location.isNotEmpty)
                Row(children: [
                  const Icon(Icons.location_on_rounded,
                      color: AppTheme.textHint, size: 12),
                  const SizedBox(width: 4),
                  Text(location, style: GoogleFonts.inter(
                      color: AppTheme.textHint, fontSize: 11)),
                ]),
              if (description.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(description, style: GoogleFonts.inter(
                    color: AppTheme.textSecondary, fontSize: 13, height: 1.5),
                    maxLines: 3, overflow: TextOverflow.ellipsis),
              ],
              const SizedBox(height: 14),
              if (hasUrl)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    gradient: AppTheme.primaryGradient,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: AppTheme.glowShadow,
                  ),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(Icons.open_in_browser_rounded,
                        color: Colors.white, size: 16),
                    const SizedBox(width: 6),
                    Text('Visit Website', style: GoogleFonts.inter(
                        color: Colors.white, fontSize: 13,
                        fontWeight: FontWeight.w700)),
                  ]),
                ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _buildCompactCard(Map<String, dynamic> biz, {required int rank}) {
    final imgUrl = biz['image_url'] as String?;
    final cat = (biz['category'] as String?) ?? 'Other';
    final color = _catColors[cat] ?? AppTheme.accentCyan;
    final searchCount = (biz['search_count'] as int?) ?? 0;
    final location = (biz['location'] as String?) ?? '';
    final description = (biz['description'] as String?) ?? '';
    final showRank = _query.isEmpty && _selectedCat == 'All';

    return GestureDetector(
      onTap: () => _openBusiness(biz),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppTheme.divider),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Stack(children: [
            Container(
              width: 70, height: 70,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(14)),
              clipBehavior: Clip.hardEdge,
              child: imgUrl != null
                  ? Image.network(imgUrl, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _imagePlaceholder(70, color))
                  : _imagePlaceholder(70, color),
            ),
            if (showRank)
              Positioned(top: -6, left: -6, child: Container(
                width: 22, height: 22,
                decoration: BoxDecoration(
                  color: AppTheme.bgDark, shape: BoxShape.circle,
                  border: Border.all(color: color, width: 1.5),
                ),
                child: Center(child: Text('$rank',
                    style: GoogleFonts.spaceGrotesk(
                        color: color, fontSize: 10, fontWeight: FontWeight.w800))),
              )),
          ]),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text((biz['name'] as String?) ?? '',
                  style: GoogleFonts.spaceGrotesk(
                      color: AppTheme.textPrimary,
                      fontSize: 14, fontWeight: FontWeight.w700),
                  maxLines: 1, overflow: TextOverflow.ellipsis)),
              _catBadge(cat, color, small: true),
            ]),
            const SizedBox(height: 3),
            Row(children: [
              if (location.isNotEmpty) ...[
                const Icon(Icons.location_on_rounded,
                    color: AppTheme.textHint, size: 10),
                const SizedBox(width: 2),
                Flexible(child: Text(location,
                    style: GoogleFonts.inter(
                        color: AppTheme.textHint, fontSize: 10),
                    maxLines: 1, overflow: TextOverflow.ellipsis)),
              ],
              if (searchCount > 0) ...[
                if (location.isNotEmpty)
                  const Text('  ·  ',
                      style: TextStyle(color: AppTheme.textHint, fontSize: 10)),
                const Icon(Icons.visibility_outlined,
                    color: AppTheme.textHint, size: 10),
                const SizedBox(width: 2),
                Text('$searchCount', style: GoogleFonts.inter(
                    color: AppTheme.textHint, fontSize: 10)),
              ],
            ]),
            const SizedBox(height: 4),
            if (description.isNotEmpty)
              Text(description, style: GoogleFonts.inter(
                  color: AppTheme.textSecondary, fontSize: 11.5, height: 1.4),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 6),
            Row(children: [
              const Icon(Icons.open_in_new_rounded,
                  color: AppTheme.accentCyan, size: 11),
              const SizedBox(width: 4),
              Text('Visit website', style: GoogleFonts.inter(
                  color: AppTheme.accentCyan, fontSize: 11,
                  fontWeight: FontWeight.w600)),
            ]),
          ])),
        ]),
      ),
    );
  }

  Widget _buildEmptyAll() {
    return Center(child: Padding(
      padding: const EdgeInsets.all(40),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ShaderMask(
          shaderCallback: (b) => AppTheme.primaryGradient.createShader(b),
          child: const Icon(Icons.business_center_outlined,
              color: Colors.white, size: 60),
        ),
        const SizedBox(height: 20),
        Text('No businesses listed yet',
            style: GoogleFonts.spaceGrotesk(
                color: AppTheme.textPrimary, fontSize: 20,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text('Create an account and be the first to list one!',
            style: GoogleFonts.inter(
                color: AppTheme.textHint, fontSize: 13, height: 1.5),
            textAlign: TextAlign.center),
        const SizedBox(height: 24),
        GestureDetector(
          onTap: _goAddBusiness,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
            decoration: BoxDecoration(
              gradient: AppTheme.primaryGradient,
              borderRadius: BorderRadius.circular(24),
              boxShadow: AppTheme.glowShadow,
            ),
            child: Text('List Your Business',
                style: GoogleFonts.spaceGrotesk(
                    color: Colors.white, fontSize: 15,
                    fontWeight: FontWeight.w700)),
          ),
        ),
      ]),
    ));
  }

  Widget _buildEmptyFilter() {
    return Center(child: Padding(
      padding: const EdgeInsets.all(40),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.search_off_rounded,
            color: AppTheme.textHint, size: 48),
        const SizedBox(height: 16),
        Text('No results found', style: GoogleFonts.spaceGrotesk(
            color: AppTheme.textPrimary, fontSize: 17,
            fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text('Try a different search term or category',
            style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 13)),
      ]),
    ));
  }

  Widget _imagePlaceholder(double height, Color color) => Container(
    height: height,
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [color.withOpacity(0.3),
                 AppTheme.accentPurple.withOpacity(0.2)],
        begin: Alignment.topLeft, end: Alignment.bottomRight,
      ),
    ),
    child: Center(child: Icon(Icons.business_rounded,
        color: Colors.white38, size: height * 0.35)),
  );

  Widget _catBadge(String cat, Color color, {bool small = false}) => Container(
    padding: EdgeInsets.symmetric(
        horizontal: small ? 6 : 8, vertical: small ? 2 : 4),
    decoration: BoxDecoration(
      color: color.withOpacity(0.15),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withOpacity(0.3)),
    ),
    child: Text(cat, style: GoogleFonts.inter(
        color: color, fontSize: small ? 9 : 10,
        fontWeight: FontWeight.w700)),
  );
}
