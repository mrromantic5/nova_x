// lib/features/profile/screens/profile_screen.dart
import 'dart:io';
import 'package:nova_x/core/services/rewards_service.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:nova_x/core/database/local_db.dart';
import 'package:nova_x/core/services/api_service.dart';
import 'package:nova_x/core/theme/app_theme.dart';
import '../../auth/screens/auth_screen.dart';

const List<String> _bizCategories = [
  'Technology', 'Food & Drinks', 'Fashion', 'Health & Beauty',
  'Finance', 'Education', 'Entertainment', 'Real Estate',
  'Retail', 'Services', 'Other',
];

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;

  bool _loggedIn = false;
  bool _loading = true;
  bool _savingProfile = false;
  bool _loadingBiz = false;

  Map<String, dynamic> _serverProfile = {};
  List<Map<String, dynamic>> _myBiz = [];

  String? _profileImgPath;
  String _avatarColor = 'cyan';

  final _nameCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _animCtrl.forward();
    _loadAll();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    _loggedIn = await ApiService.isLoggedIn();
    _profileImgPath = LocalDB.getProfileImagePath();
    if (_loggedIn) {
      final profile = await ApiService.getProfile();
      if (profile != null) {
        _serverProfile = profile;
        _avatarColor = (profile['avatar_color'] as String?) ?? 'cyan';
        _nameCtrl.text = (profile['username'] as String?) ?? '';
      }
      _myBiz = await ApiService.getMyBusinesses();
    }
    setState(() => _loading = false);
  }

  // ── Profile image (LOCAL only) ─────────────────────────────────
  Future<void> _pickProfileImage() async {
    final xFile = await ImagePicker().pickImage(
        source: ImageSource.gallery, imageQuality: 85, maxWidth: 512);
    if (xFile == null) return;
    final dir = await getApplicationDocumentsDirectory();
    final dest = '${dir.path}/profile_${DateTime.now().millisecondsSinceEpoch}.jpg';
    await File(xFile.path).copy(dest);
    await LocalDB.saveProfileImagePath(dest);
    if (mounted) setState(() => _profileImgPath = dest);
    _snack('Profile photo updated ✓');
  }

  Future<void> _removeProfileImage() async {
    await LocalDB.clearProfileImage();
    if (mounted) setState(() => _profileImgPath = null);
  }

  // ── Save profile to server ─────────────────────────────────────
  Future<void> _saveProfile() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _snack('Please enter a username');
      return;
    }
    setState(() => _savingProfile = true);
    final ok = await ApiService.updateProfile(
        username: name, avatarColor: _avatarColor);
    if (ok) RewardsService.earn(RewardTaskKey.completeProfile); // server verifies + once-ever
    if (mounted) setState(() => _savingProfile = false);
    _snack(ok ? 'Profile saved ✓' : 'Could not save. Try again.');
  }

  // ── Logout ─────────────────────────────────────────────────────
  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Log out?', style: GoogleFonts.spaceGrotesk(
            color: AppTheme.textPrimary, fontWeight: FontWeight.bold)),
        content: Text('You will need your email and password to log back in.',
            style: GoogleFonts.inter(color: AppTheme.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: GoogleFonts.inter(color: AppTheme.textHint)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Log Out', style: GoogleFonts.inter(color: AppTheme.danger)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ApiService.logout();
    if (mounted) {
      Navigator.pushReplacement(context,
          MaterialPageRoute(builder: (_) => const AuthScreen(showGuestOption: false)));
    }
  }

  // ── Business management ────────────────────────────────────────
  void _showAddBusiness() {
    if (_myBiz.length >= 2) {
      _snack('Maximum 2 businesses per account');
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddBizSheet(
        onAdded: () async {
          setState(() => _loadingBiz = true);
          _myBiz = await ApiService.getMyBusinesses();
          if (mounted) setState(() => _loadingBiz = false);
        },
      ),
    );
  }

  Future<void> _deleteBusiness(int id, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Delete business?', style: GoogleFonts.spaceGrotesk(
            color: AppTheme.textPrimary, fontWeight: FontWeight.bold)),
        content: Text('Remove "$name"? This cannot be undone.',
            style: GoogleFonts.inter(color: AppTheme.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: GoogleFonts.inter(color: AppTheme.textHint)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Delete', style: GoogleFonts.inter(color: AppTheme.danger)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final deleted = await ApiService.deleteBusiness(id);
    if (deleted) {
      _myBiz.removeWhere((b) => b['id'] == id);
      if (mounted) setState(() {});
      _snack('"$name" deleted');
    } else {
      _snack('Could not delete. Try again.');
    }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(msg, style: GoogleFonts.inter(color: Colors.white)),
    backgroundColor: AppTheme.bgElevated,
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  ));

  Color _colorFromName(String n) {
    switch (n) {
      case 'red':    return const Color(0xFFFF6B6B);
      case 'orange': return const Color(0xFFFFAB00);
      case 'purple': return AppTheme.accentPurple;
      case 'green':  return AppTheme.success;
      default:       return AppTheme.accentCyan;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: AppTheme.bgDark,
        appBar: AppBar(
          backgroundColor: AppTheme.bgDark, elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: AppTheme.textSecondary, size: 18),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: const Center(child: CircularProgressIndicator(
            color: AppTheme.accentCyan, strokeWidth: 2)),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: RefreshIndicator(
          onRefresh: _loadAll,
          color: AppTheme.accentCyan,
          backgroundColor: AppTheme.bgCard,
          child: CustomScrollView(slivers: [
          _buildAppBar(),
          SliverToBoxAdapter(
            child: _loggedIn ? _buildLoggedIn() : _buildNotLoggedIn(),
          ),
        ]),
        ),
      ),
    );
  }

  Widget _buildAppBar() => SliverAppBar(
    backgroundColor: AppTheme.bgDark, elevation: 0, floating: true,
    leading: GestureDetector(
      onTap: () => Navigator.pop(context),
      child: Container(
        margin: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppTheme.bgCard, borderRadius: BorderRadius.circular(10)),
        child: const Icon(Icons.arrow_back_ios_new_rounded,
            color: AppTheme.textSecondary, size: 16),
      ),
    ),
    title: Text(_loggedIn ? 'My Profile' : 'Account',
        style: GoogleFonts.spaceGrotesk(
            color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
    actions: _loggedIn
        ? [IconButton(
            icon: const Icon(Icons.logout_rounded, color: AppTheme.danger, size: 20),
            onPressed: _logout)]
        : null,
  );

  // ── NOT LOGGED IN ──────────────────────────────────────────────
  Widget _buildNotLoggedIn() => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(children: [
      const SizedBox(height: 24),
      Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [AppTheme.accentCyan.withOpacity(0.15),
                     AppTheme.accentPurple.withOpacity(0.08)],
            begin: Alignment.topLeft, end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppTheme.accentCyan.withOpacity(0.3)),
        ),
        child: Column(children: [
          ShaderMask(
            shaderCallback: (b) => AppTheme.primaryGradient.createShader(b),
            child: const Icon(Icons.account_circle_outlined,
                color: Colors.white, size: 64),
          ),
          const SizedBox(height: 16),
          Text('Join NOVA X', style: GoogleFonts.spaceGrotesk(
              color: AppTheme.textPrimary, fontSize: 22,
              fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(
            'Create a free account to sync your data,\nmanage your business, and access your\nprofile on any device.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
                color: AppTheme.textHint, fontSize: 13, height: 1.6)),
        ]),
      ),
      const SizedBox(height: 24),
      _benefit(Icons.sync_rounded,
          'Sync across devices', 'Your profile and data everywhere'),
      _benefit(Icons.business_center_outlined,
          'List your business', 'Reach all NOVA X users globally'),
      _benefit(Icons.lock_outline_rounded,
          'Secure account', 'Login anytime after reinstalling'),
      const SizedBox(height: 28),
      GestureDetector(
        onTap: () => Navigator.push(context, MaterialPageRoute(
            builder: (_) => const AuthScreen(showGuestOption: false)))
            .then((_) => _loadAll()),
        child: Container(
          height: 54, width: double.infinity,
          decoration: BoxDecoration(
            gradient: AppTheme.primaryGradient,
            borderRadius: BorderRadius.circular(16),
            boxShadow: AppTheme.glowShadow,
          ),
          child: Center(child: Text('Create Free Account',
              style: GoogleFonts.spaceGrotesk(
                  color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700))),
        ),
      ),
      const SizedBox(height: 14),
      GestureDetector(
        onTap: () => Navigator.push(context, MaterialPageRoute(
            builder: (_) => const AuthScreen(showGuestOption: false)))
            .then((_) => _loadAll()),
        child: Text('Already have an account? Log In',
            style: GoogleFonts.inter(
                color: AppTheme.accentCyan, fontSize: 13,
                decoration: TextDecoration.underline,
                decorationColor: AppTheme.accentCyan)),
      ),
    ]),
  );

  Widget _benefit(IconData icon, String title, String sub) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Row(children: [
      Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          color: AppTheme.accentCyan.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12)),
        child: Icon(icon, color: AppTheme.accentCyan, size: 18),
      ),
      const SizedBox(width: 14),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: GoogleFonts.inter(
            color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
        Text(sub, style: GoogleFonts.inter(
            color: AppTheme.textHint, fontSize: 11)),
      ]),
    ]),
  );

  // ── LOGGED IN ──────────────────────────────────────────────────
  Widget _buildLoggedIn() {
    final color = _colorFromName(_avatarColor);
    final name = ((_serverProfile['username'] as String?) ?? 'N');
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'N';
    return Column(children: [
      const SizedBox(height: 16),
      _buildAvatar(color, initial),
      const SizedBox(height: 28),
      _section('ACCOUNT DETAILS', _buildAccountDetails()),
      const SizedBox(height: 14),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _saveButton()),
      const SizedBox(height: 28),
      _section('YOUR STATS', _buildStats()),
      const SizedBox(height: 28),
      _section('NOVA X BUSINESS', _buildBizSection()),
      const SizedBox(height: 40),
    ]);
  }

  Widget _section(String label, Widget child) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: GoogleFonts.inter(
          color: AppTheme.textHint, fontSize: 10,
          fontWeight: FontWeight.w700, letterSpacing: 1.2)),
      const SizedBox(height: 12),
      child,
    ]),
  );

  Widget _buildAvatar(Color color, String initial) => Column(children: [
    Stack(alignment: Alignment.bottomRight, children: [
      GestureDetector(
        onTap: _pickProfileImage,
        child: Container(
          width: 100, height: 100,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 3),
            boxShadow: [BoxShadow(
                color: color.withOpacity(0.3), blurRadius: 20, spreadRadius: 2)],
          ),
          child: ClipOval(child: _profileImgPath != null
              ? Image.file(File(_profileImgPath!), fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _initBg(color, initial))
              : _initBg(color, initial)),
        ),
      ),
      GestureDetector(
        onTap: _pickProfileImage,
        child: Container(
          width: 30, height: 30,
          decoration: BoxDecoration(
            color: color, shape: BoxShape.circle,
            border: Border.all(color: AppTheme.bgDark, width: 2)),
          child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 14),
        ),
      ),
    ]),
    if (_profileImgPath != null) ...[
      const SizedBox(height: 6),
      GestureDetector(
        onTap: _removeProfileImage,
        child: Text('Remove photo', style: GoogleFonts.inter(
            color: AppTheme.danger, fontSize: 11,
            decoration: TextDecoration.underline,
            decorationColor: AppTheme.danger)),
      ),
    ],
    const SizedBox(height: 16),
    // Color picker
    Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: ['cyan', 'red', 'orange', 'purple', 'green'].map((c) {
        final active = c == _avatarColor;
        final cc = _colorFromName(c);
        return GestureDetector(
          onTap: () => setState(() => _avatarColor = c),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 32, height: 32,
            margin: const EdgeInsets.symmetric(horizontal: 5),
            decoration: BoxDecoration(
              color: cc,
              shape: BoxShape.circle,
              border: active ? Border.all(color: Colors.white, width: 2.5) : null,
              boxShadow: active
                  ? [BoxShadow(color: cc.withOpacity(0.5), blurRadius: 8)]
                  : null,
            ),
            child: active
                ? const Icon(Icons.check_rounded, color: Colors.white, size: 16)
                : null,
          ),
        );
      }).toList(),
    ),
  ]);

  Widget _initBg(Color color, String initial) => Container(
    color: color.withOpacity(0.15),
    child: Center(child: Text(initial, style: GoogleFonts.spaceGrotesk(
        color: color, fontSize: 40, fontWeight: FontWeight.w800))),
  );

  Widget _buildAccountDetails() => Container(
    decoration: BoxDecoration(
      color: AppTheme.bgCard,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppTheme.divider),
    ),
    child: Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        child: Row(children: [
          const Icon(Icons.person_outline_rounded, color: AppTheme.textHint, size: 18),
          const SizedBox(width: 12),
          Expanded(child: TextField(
            controller: _nameCtrl,
            style: GoogleFonts.inter(color: AppTheme.textPrimary, fontSize: 14),
            decoration: InputDecoration(
              border: InputBorder.none,
              hintText: 'Username',
              hintStyle: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 14),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 14)),
          )),
        ]),
      ),
      Divider(color: AppTheme.divider, height: 1),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(children: [
          const Icon(Icons.email_outlined, color: AppTheme.textHint, size: 18),
          const SizedBox(width: 12),
          Text((_serverProfile['email'] as String?) ?? '',
              style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 14)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppTheme.bgElevated,
              borderRadius: BorderRadius.circular(8)),
            child: Text('Email', style: GoogleFonts.inter(
                color: AppTheme.textHint, fontSize: 10)),
          ),
        ]),
      ),
    ]),
  );

  Widget _saveButton() => GestureDetector(
    onTap: _savingProfile ? null : _saveProfile,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: 52, width: double.infinity,
      decoration: BoxDecoration(
        gradient: AppTheme.primaryGradient,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppTheme.glowShadow,
      ),
      child: Center(child: _savingProfile
          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(
              color: Colors.white, strokeWidth: 2))
          : Text('Save Profile', style: GoogleFonts.spaceGrotesk(
              color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700))),
    ),
  );

  Widget _buildStats() => Row(children: [
    _statCard(Icons.bookmark_rounded,
        '${LocalDB.bookmarkCount}', 'Bookmarks', AppTheme.warning),
    const SizedBox(width: 10),
    _statCard(Icons.history_rounded,
        '${LocalDB.historyCount}', 'History', AppTheme.accentPurple),
    const SizedBox(width: 10),
    _statCard(Icons.business_center_outlined,
        '${_myBiz.length}/2', 'Businesses', AppTheme.accentCyan),
  ]);

  Widget _statCard(IconData icon, String val, String label, Color color) =>
      Expanded(child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color.withOpacity(0.18), color.withOpacity(0.06)],
            begin: Alignment.topCenter, end: Alignment.bottomCenter),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Column(children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 6),
          Text(val, style: GoogleFonts.spaceGrotesk(
              color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(label, style: GoogleFonts.inter(
              color: AppTheme.textHint, fontSize: 10)),
        ]),
      ));

  Widget _buildBizSection() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: AppTheme.accentCyan.withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.accentCyan.withOpacity(0.3))),
          child: Text('${_myBiz.length}/2 active', style: GoogleFonts.inter(
              color: AppTheme.accentCyan, fontSize: 10, fontWeight: FontWeight.w700)),
        ),
        const Spacer(),
        if (_myBiz.length < 2)
          GestureDetector(
            onTap: _showAddBusiness,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                gradient: AppTheme.primaryGradient,
                borderRadius: BorderRadius.circular(20),
                boxShadow: AppTheme.glowShadow),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.add_rounded, color: Colors.white, size: 14),
                const SizedBox(width: 4),
                Text('Add Business', style: GoogleFonts.inter(
                    color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
      ]),
      const SizedBox(height: 12),
      if (_loadingBiz)
        const Center(child: Padding(
          padding: EdgeInsets.all(20),
          child: CircularProgressIndicator(
              color: AppTheme.accentCyan, strokeWidth: 2)))
      else if (_myBiz.isEmpty)
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppTheme.bgCard, borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.divider)),
          child: Column(children: [
            const Icon(Icons.business_center_outlined,
                color: AppTheme.textHint, size: 36),
            const SizedBox(height: 10),
            Text('No businesses yet', style: GoogleFonts.spaceGrotesk(
                color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('Add your business to the global NOVA X directory',
                style: GoogleFonts.inter(
                    color: AppTheme.textHint, fontSize: 12, height: 1.4),
                textAlign: TextAlign.center),
          ]),
        )
      else
        ...(_myBiz.map((biz) => _bizCard(biz)).toList()),
    ],
  );

  Widget _bizCard(Map<String, dynamic> biz) {
    final imgUrl = biz['image_url'] as String?;
    final id = biz['id'] as int? ?? 0;
    final name = (biz['name'] as String?) ?? '';
    final cat = (biz['category'] as String?) ?? '';
    final loc = (biz['location'] as String?) ?? '';
    final sc = biz['search_count'] as int? ?? 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.bgCard, borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.divider)),
      child: Row(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: imgUrl != null
              ? Image.network(imgUrl, width: 60, height: 60, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _bizPlaceholder())
              : _bizPlaceholder(),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, style: GoogleFonts.spaceGrotesk(
              color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w700),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          if (cat.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 2),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.accentCyan.withOpacity(0.12),
                borderRadius: BorderRadius.circular(6)),
              child: Text(cat, style: GoogleFonts.inter(
                  color: AppTheme.accentCyan, fontSize: 9, fontWeight: FontWeight.w700)),
            ),
          if (loc.isNotEmpty)
            Padding(padding: const EdgeInsets.only(top: 2),
              child: Text(loc, style: GoogleFonts.inter(
                  color: AppTheme.textHint, fontSize: 10)),
            ),
          Text('$sc search${sc == 1 ? '' : 'es'}', style: GoogleFonts.inter(
              color: AppTheme.accentCyan, fontSize: 10, fontWeight: FontWeight.w600)),
        ])),
        GestureDetector(
          onTap: () => _deleteBusiness(id, name),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.danger.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.delete_outline_rounded,
                color: AppTheme.danger, size: 16),
          ),
        ),
      ]),
    );
  }

  Widget _bizPlaceholder() => Container(
    width: 60, height: 60,
    decoration: BoxDecoration(gradient: LinearGradient(colors: [
      AppTheme.accentCyan.withOpacity(0.3),
      AppTheme.accentPurple.withOpacity(0.3),
    ])),
    child: const Icon(Icons.business_rounded, color: Colors.white54, size: 28),
  );
}

// ══════════════════════════════════════════════════════════════════
// Add Business Sheet — uploads image directly to server
// ══════════════════════════════════════════════════════════════════
class _AddBizSheet extends StatefulWidget {
  final VoidCallback onAdded;
  const _AddBizSheet({required this.onAdded});
  @override
  State<_AddBizSheet> createState() => _AddBizSheetState();
}

class _AddBizSheetState extends State<_AddBizSheet> {
  final _nameCtrl = TextEditingController();
  final _webCtrl  = TextEditingController();
  final _descCtrl = TextEditingController();
  final _locCtrl  = TextEditingController();
  String _category = _bizCategories.first;
  File? _imageFile;
  bool _submitting = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _webCtrl.dispose();
    _descCtrl.dispose();
    _locCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final xFile = await ImagePicker().pickImage(
        source: ImageSource.gallery, imageQuality: 80, maxWidth: 1200);
    if (xFile == null) return;
    if (mounted) setState(() => _imageFile = File(xFile.path));
  }

  Future<void> _submit() async {
    if (_nameCtrl.text.trim().isEmpty) {
      _snack('Business name is required');
      return;
    }
    setState(() => _submitting = true);
    final res = await ApiService.addBusiness(
      name:        _nameCtrl.text.trim(),
      description: _descCtrl.text.trim(),
      category:    _category,
      location:    _locCtrl.text.trim(),
      website:     _webCtrl.text.trim(),
      imageFile:   _imageFile,
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (res['success'] == true) {
      widget.onAdded();
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Business added successfully ✓',
            style: GoogleFonts.inter(color: Colors.white)),
        backgroundColor: AppTheme.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    } else {
      _snack((res['message'] as String?) ?? 'Failed. Please try again.');
    }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(msg, style: GoogleFonts.inter(color: Colors.white)),
    backgroundColor: AppTheme.danger,
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  ));

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      padding: EdgeInsets.only(
        left: 24, right: 24, top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 28),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: AppTheme.textHint,
              borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 20),
          Text('Add Your Business', style: GoogleFonts.spaceGrotesk(
              color: AppTheme.textPrimary, fontSize: 18,
              fontWeight: FontWeight.w700)),
          Text('Visible to all NOVA X users globally', style: GoogleFonts.inter(
              color: AppTheme.textHint, fontSize: 12)),
          const SizedBox(height: 20),
          // Image picker
          GestureDetector(
            onTap: _pickImage,
            child: Container(
              width: double.infinity, height: 130,
              decoration: BoxDecoration(
                color: AppTheme.bgElevated,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.divider)),
              clipBehavior: Clip.hardEdge,
              child: _imageFile != null
                  ? Image.file(_imageFile!, fit: BoxFit.cover)
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.add_photo_alternate_outlined,
                            color: AppTheme.accentCyan, size: 32),
                        const SizedBox(height: 8),
                        Text('Upload Business Image (optional)',
                            style: GoogleFonts.inter(
                                color: AppTheme.textHint, fontSize: 12)),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 14),
          _tf('Business Name *', _nameCtrl),
          const SizedBox(height: 10),
          _tf('Website URL (e.g. https://mybiz.com)', _webCtrl,
              type: TextInputType.url),
          const SizedBox(height: 10),
          _tf('Description', _descCtrl, maxLines: 3),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: AppTheme.bgElevated,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.divider)),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _category,
                dropdownColor: AppTheme.bgElevated,
                iconEnabledColor: AppTheme.textHint,
                style: GoogleFonts.inter(
                    color: AppTheme.textPrimary, fontSize: 13),
                isExpanded: true,
                items: _bizCategories.map((c) =>
                    DropdownMenuItem(value: c, child: Text(c))).toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _category = v);
                },
              ),
            ),
          ),
          const SizedBox(height: 10),
          _tf('Location (City, Country)', _locCtrl),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: _submitting ? null : _submit,
            child: Container(
              height: 52, width: double.infinity,
              decoration: BoxDecoration(
                gradient: AppTheme.primaryGradient,
                borderRadius: BorderRadius.circular(16),
                boxShadow: AppTheme.glowShadow),
              child: Center(child: _submitting
                  ? const SizedBox(width: 22, height: 22,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : Text('Submit Business', style: GoogleFonts.spaceGrotesk(
                      color: Colors.white, fontSize: 15,
                      fontWeight: FontWeight.w700))),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _tf(String hint, TextEditingController ctrl,
      {TextInputType type = TextInputType.text, int maxLines = 1}) =>
      TextField(
        controller: ctrl,
        keyboardType: type,
        maxLines: maxLines,
        style: GoogleFonts.inter(color: AppTheme.textPrimary, fontSize: 13),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 13),
          filled: true,
          fillColor: AppTheme.bgElevated,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppTheme.accentCyan)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
      );
}
