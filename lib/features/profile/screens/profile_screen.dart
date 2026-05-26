// lib/features/profile/screens/profile_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:nova_x/core/database/local_db.dart';
import 'package:nova_x/core/theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Business categories
// ─────────────────────────────────────────────────────────────────────────────
const _bizCategories = [
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
  // Profile
  final _nameCtrl  = TextEditingController();
  final _emailCtrl = TextEditingController();
  String  _avatarColor   = 'cyan';
  String? _profileImgPath;
  bool    _savingProfile = false;

  // Stats
  int _bookmarks = 0, _history = 0, _downloads = 0;

  // Business
  List<Map<String, dynamic>> _userBiz = [];

  late AnimationController _animCtrl;
  late Animation<double>   _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _animCtrl.forward();
    _loadAll();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _animCtrl.dispose();
    super.dispose();
  }

  void _loadAll() {
    final p = LocalDB.getProfile();
    _nameCtrl.text  = p['name']  ?? '';
    _emailCtrl.text = p['email'] ?? '';
    _avatarColor    = p['avatarColor'] ?? 'cyan';
    _profileImgPath = LocalDB.getProfileImagePath();
    _bookmarks  = LocalDB.bookmarkCount;
    _history    = LocalDB.historyCount;
    _downloads  = LocalDB.downloadCount;
    final email = _emailCtrl.text;
    _userBiz = email.isNotEmpty ? LocalDB.getUserBusinesses(email) : [];
    if (mounted) setState(() {});
  }

  // ── Profile image ──────────────────────────────────────────────────────────
  Future<void> _pickProfileImage() async {
    final picker = ImagePicker();
    final xFile  = await picker.pickImage(
        source: ImageSource.gallery, imageQuality: 85, maxWidth: 512);
    if (xFile == null) return;
    final dir  = await getApplicationDocumentsDirectory();
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

  // ── Save profile ───────────────────────────────────────────────────────────
  Future<void> _saveProfile() async {
    final name  = _nameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    if (name.isEmpty) { _snack('Please enter your name'); return; }
    setState(() => _savingProfile = true);
    await LocalDB.saveProfile({'name': name, 'email': email, 'avatarColor': _avatarColor});
    // Refresh business list now email might have changed
    _userBiz = email.isNotEmpty ? LocalDB.getUserBusinesses(email) : [];
    if (mounted) setState(() => _savingProfile = false);
    _snack('Profile saved ✓');
  }

  // ── Clear all data ─────────────────────────────────────────────────────────
  Future<void> _confirmClearAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Clear all data?',
            style: GoogleFonts.spaceGrotesk(
                color: AppTheme.textPrimary, fontWeight: FontWeight.bold)),
        content: Text(
            'This will permanently delete your history, bookmarks, downloads and profile. This cannot be undone.',
            style: GoogleFonts.inter(color: AppTheme.textSecondary, height: 1.5)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: Text('Cancel', style: GoogleFonts.inter(color: AppTheme.textHint))),
          TextButton(onPressed: () => Navigator.pop(context, true),
              child: Text('Clear All', style: GoogleFonts.inter(color: AppTheme.danger))),
        ],
      ),
    );
    if (ok == true) {
      await LocalDB.clearAll();
      _loadAll();
      _snack('All data cleared');
    }
  }

  // ── Business: add ──────────────────────────────────────────────────────────
  void _showAddBusiness() {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) { _snack('Save your profile email first'); return; }
    if (_userBiz.length >= 2) { _snack('Maximum 2 businesses per account'); return; }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddBusinessSheet(
        ownerEmail: email,
        onSubmitted: () { _loadAll(); },
      ),
    );
  }

  // ── Business: delete ───────────────────────────────────────────────────────
  Future<void> _deleteBusiness(String id, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Delete business?',
            style: GoogleFonts.spaceGrotesk(color: AppTheme.textPrimary, fontWeight: FontWeight.bold)),
        content: Text('Remove "$name" from NOVA X Business? This cannot be undone.',
            style: GoogleFonts.inter(color: AppTheme.textSecondary, height: 1.5)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: Text('Cancel', style: GoogleFonts.inter(color: AppTheme.textHint))),
          TextButton(onPressed: () => Navigator.pop(context, true),
              child: Text('Delete', style: GoogleFonts.inter(color: AppTheme.danger))),
        ],
      ),
    );
    if (ok == true) {
      await LocalDB.deleteBusiness(id);
      _loadAll();
      _snack('"$name" removed');
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.inter(color: Colors.white)),
      backgroundColor: AppTheme.bgElevated,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  Color _colorFromName(String name) => switch (name) {
    'cyan'   => AppTheme.accentCyan,
    'red'    => const Color(0xFFFF6B6B),
    'orange' => const Color(0xFFFFAB00),
    'purple' => AppTheme.accentPurple,
    'green'  => AppTheme.success,
    _        => AppTheme.accentCyan,
  };

  // ═══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: CustomScrollView(slivers: [
          _buildAppBar(),
          SliverToBoxAdapter(child: Column(children: [
            const SizedBox(height: 8),
            _buildAvatarSection(),
            const SizedBox(height: 28),
            _buildSection('ACCOUNT DETAILS', _buildAccountDetails()),
            const SizedBox(height: 20),
            _buildSaveButton(),
            const SizedBox(height: 28),
            _buildSection('YOUR STATS', _buildStats()),
            const SizedBox(height: 28),
            _buildSection('NOVA X BUSINESS', _buildBusinessSection()),
            const SizedBox(height: 28),
            _buildSection('DANGER ZONE', _buildDangerZone()),
            const SizedBox(height: 40),
          ])),
        ]),
      ),
    );
  }

  // ── App bar ────────────────────────────────────────────────────────────────
  Widget _buildAppBar() {
    return SliverAppBar(
      expandedHeight: 0,
      floating: true,
      backgroundColor: AppTheme.bgDark,
      elevation: 0,
      leading: GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Container(
          margin: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppTheme.bgCard,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AppTheme.textSecondary, size: 16),
        ),
      ),
      title: Text('My Profile',
          style: GoogleFonts.spaceGrotesk(
              color: AppTheme.textPrimary,
              fontSize: 18, fontWeight: FontWeight.w700)),
      centerTitle: false,
    );
  }

  // ── Section wrapper ────────────────────────────────────────────────────────
  Widget _buildSection(String title, Widget child) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: GoogleFonts.inter(
                color: AppTheme.textHint, fontSize: 10,
                fontWeight: FontWeight.w700, letterSpacing: 1.2)),
        const SizedBox(height: 12),
        child,
      ]),
    );
  }

  // ── Avatar ────────────────────────────────────────────────────────────────
  Widget _buildAvatarSection() {
    final initials = _nameCtrl.text.trim().isNotEmpty
        ? _nameCtrl.text.trim()[0].toUpperCase()
        : 'N';
    final color = _colorFromName(_avatarColor);

    return Column(children: [
      // Avatar circle with edit overlay
      Stack(alignment: Alignment.bottomRight, children: [
        GestureDetector(
          onTap: _pickProfileImage,
          child: Container(
            width: 100, height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: color, width: 3),
              boxShadow: [BoxShadow(color: color.withOpacity(0.3),
                  blurRadius: 20, spreadRadius: 2)],
            ),
            child: ClipOval(
              child: _profileImgPath != null
                  ? Image.file(File(_profileImgPath!),
                      fit: BoxFit.cover, width: 100, height: 100,
                      errorBuilder: (_, __, ___) => _avatarFallback(color, initials))
                  : _avatarFallback(color, initials),
            ),
          ),
        ),
        // Camera edit button
        GestureDetector(
          onTap: _pickProfileImage,
          child: Container(
            width: 30, height: 30,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: AppTheme.bgDark, width: 2),
            ),
            child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 14),
          ),
        ),
      ]),

      const SizedBox(height: 8),

      // Remove photo link (only if photo set)
      if (_profileImgPath != null)
        GestureDetector(
          onTap: _removeProfileImage,
          child: Text('Remove photo',
              style: GoogleFonts.inter(
                  color: AppTheme.danger, fontSize: 11,
                  decoration: TextDecoration.underline,
                  decorationColor: AppTheme.danger)),
        ),

      const SizedBox(height: 16),

      // Color picker
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        for (final c in ['cyan', 'red', 'orange', 'purple', 'green'])
          GestureDetector(
            onTap: () => setState(() => _avatarColor = c),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 32, height: 32,
              margin: const EdgeInsets.symmetric(horizontal: 5),
              decoration: BoxDecoration(
                color: _colorFromName(c),
                shape: BoxShape.circle,
                border: _avatarColor == c
                    ? Border.all(color: Colors.white, width: 2.5)
                    : null,
                boxShadow: _avatarColor == c
                    ? [BoxShadow(color: _colorFromName(c).withOpacity(0.5),
                        blurRadius: 8, spreadRadius: 1)]
                    : null,
              ),
              child: _avatarColor == c
                  ? const Icon(Icons.check_rounded, color: Colors.white, size: 16)
                  : null,
            ),
          ),
      ]),
    ]);
  }

  Widget _avatarFallback(Color color, String initials) => Container(
    color: color.withOpacity(0.15),
    child: Center(
      child: Text(initials,
          style: GoogleFonts.spaceGrotesk(
              color: color, fontSize: 40, fontWeight: FontWeight.w800)),
    ),
  );

  // ── Account details ────────────────────────────────────────────────────────
  Widget _buildAccountDetails() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(children: [
        _inputField(Icons.person_outline_rounded, 'Full Name', _nameCtrl),
        Divider(color: AppTheme.divider, height: 1),
        _inputField(Icons.email_outlined, 'Email Address', _emailCtrl,
            inputType: TextInputType.emailAddress),
      ]),
    );
  }

  Widget _inputField(IconData icon, String hint, TextEditingController ctrl,
      {TextInputType inputType = TextInputType.text}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: Row(children: [
        Icon(icon, color: AppTheme.textHint, size: 18),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            controller: ctrl,
            keyboardType: inputType,
            style: GoogleFonts.inter(color: AppTheme.textPrimary, fontSize: 14),
            decoration: InputDecoration(
              border: InputBorder.none,
              hintText: hint,
              hintStyle: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 14),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ]),
    );
  }

  // ── Save button ────────────────────────────────────────────────────────────
  Widget _buildSaveButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GestureDetector(
        onTap: _savingProfile ? null : _saveProfile,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 52,
          decoration: BoxDecoration(
            gradient: AppTheme.primaryGradient,
            borderRadius: BorderRadius.circular(16),
            boxShadow: AppTheme.glowShadow,
          ),
          child: Center(
            child: _savingProfile
                ? const SizedBox(width: 22, height: 22,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : Text('Save Profile',
                    style: GoogleFonts.spaceGrotesk(
                        color: Colors.white,
                        fontSize: 15, fontWeight: FontWeight.w700)),
          ),
        ),
      ),
    );
  }

  // ── Stats ──────────────────────────────────────────────────────────────────
  Widget _buildStats() {
    return Row(children: [
      _statCard(Icons.bookmark_rounded, '$_bookmarks', 'Bookmarks', AppTheme.warning),
      const SizedBox(width: 10),
      _statCard(Icons.history_rounded,  '$_history',   'History',   AppTheme.accentPurple),
      const SizedBox(width: 10),
      _statCard(Icons.download_rounded, '$_downloads', 'Downloads', AppTheme.primaryBlue),
    ]);
  }

  Widget _statCard(IconData icon, String value, String label, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color.withOpacity(0.18), color.withOpacity(0.06)],
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Column(children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 8),
          Text(value,
              style: GoogleFonts.spaceGrotesk(
                  color: AppTheme.textPrimary,
                  fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(label,
              style: GoogleFonts.inter(
                  color: AppTheme.textHint, fontSize: 10)),
        ]),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // NOVA X BUSINESS SECTION
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildBusinessSection() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Header row
      Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: AppTheme.accentCyan.withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.accentCyan.withOpacity(0.3)),
          ),
          child: Text('${_userBiz.length}/2 businesses',
              style: GoogleFonts.inter(
                  color: AppTheme.accentCyan, fontSize: 10, fontWeight: FontWeight.w700)),
        ),
        const Spacer(),
        if (_userBiz.length < 2)
          GestureDetector(
            onTap: _showAddBusiness,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                gradient: AppTheme.primaryGradient,
                borderRadius: BorderRadius.circular(20),
                boxShadow: AppTheme.glowShadow,
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.add_rounded, color: Colors.white, size: 14),
                const SizedBox(width: 4),
                Text('Add Business',
                    style: GoogleFonts.inter(
                        color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
      ]),

      const SizedBox(height: 14),

      // Business cards
      if (_userBiz.isEmpty)
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppTheme.bgCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.divider),
          ),
          child: Center(child: Column(children: [
            Icon(Icons.business_center_outlined, color: AppTheme.textHint, size: 36),
            const SizedBox(height: 10),
            Text('No businesses yet',
                style: GoogleFonts.spaceGrotesk(
                    color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('Add your business to appear in\nNOVA X Business directory',
                style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 12, height: 1.4),
                textAlign: TextAlign.center),
          ])),
        )
      else
        Column(
          children: _userBiz.map((biz) => _buildBizCard(biz)).toList(),
        ),
    ]);
  }

  Widget _buildBizCard(Map<String, dynamic> biz) {
    final imgPath = biz['imagePath'] as String?;
    final category = biz['category'] as String? ?? 'Other';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Row(children: [
        // Image / placeholder
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: imgPath != null
              ? Image.file(File(imgPath),
                  width: 60, height: 60, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _bizPlaceholder(60))
              : _bizPlaceholder(60),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(biz['name'] ?? '',
                style: GoogleFonts.spaceGrotesk(
                    color: AppTheme.textPrimary,
                    fontSize: 14, fontWeight: FontWeight.w700),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 3),
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.accentCyan.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(category,
                    style: GoogleFonts.inter(
                        color: AppTheme.accentCyan, fontSize: 9, fontWeight: FontWeight.w700)),
              ),
              if ((biz['location'] as String? ?? '').isNotEmpty) ...[
                const SizedBox(width: 6),
                const Icon(Icons.location_on_outlined, color: AppTheme.textHint, size: 10),
                Flexible(
                  child: Text(biz['location'] ?? '',
                      style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 10),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ],
            ]),
            const SizedBox(height: 3),
            Text(biz['description'] ?? '',
                style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 11, height: 1.3),
                maxLines: 2, overflow: TextOverflow.ellipsis),
          ]),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () => _deleteBusiness(biz['id'], biz['name'] ?? ''),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.danger.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.delete_outline_rounded, color: AppTheme.danger, size: 16),
          ),
        ),
      ]),
    );
  }

  Widget _bizPlaceholder(double size) => Container(
    width: size, height: size,
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [AppTheme.accentCyan.withOpacity(0.3), AppTheme.accentPurple.withOpacity(0.3)],
        begin: Alignment.topLeft, end: Alignment.bottomRight,
      ),
    ),
    child: const Icon(Icons.business_rounded, color: Colors.white54, size: 28),
  );

  // ── Danger zone ────────────────────────────────────────────────────────────
  Widget _buildDangerZone() {
    return GestureDetector(
      onTap: _confirmClearAll,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.divider),
        ),
        child: Row(children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: AppTheme.danger.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.delete_sweep_rounded, color: AppTheme.danger, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Clear All Browser Data',
                style: GoogleFonts.inter(
                    color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
            Text('History, bookmarks, downloads & profile',
                style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 11)),
          ])),
          const Icon(Icons.chevron_right_rounded, color: AppTheme.textHint, size: 18),
        ]),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// ADD BUSINESS BOTTOM SHEET
// ═════════════════════════════════════════════════════════════════════════════
class _AddBusinessSheet extends StatefulWidget {
  final String ownerEmail;
  final VoidCallback onSubmitted;
  const _AddBusinessSheet({required this.ownerEmail, required this.onSubmitted});

  @override
  State<_AddBusinessSheet> createState() => _AddBusinessSheetState();
}

class _AddBusinessSheetState extends State<_AddBusinessSheet> {
  final _formKey     = GlobalKey<FormState>();
  final _nameCtrl    = TextEditingController();
  final _websiteCtrl = TextEditingController();
  final _descCtrl    = TextEditingController();
  final _locCtrl     = TextEditingController();
  String  _category  = _bizCategories.first;
  String? _imagePath;
  bool    _submitting = false;

  @override
  void dispose() {
    _nameCtrl.dispose(); _websiteCtrl.dispose();
    _descCtrl.dispose(); _locCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final xFile  = await picker.pickImage(source: ImageSource.gallery,
        imageQuality: 80, maxWidth: 800);
    if (xFile == null) return;
    final dir  = await getApplicationDocumentsDirectory();
    final dest = '${dir.path}/biz_${DateTime.now().millisecondsSinceEpoch}.jpg';
    await File(xFile.path).copy(dest);
    if (mounted) setState(() => _imagePath = dest);
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _submitting = true);

    final biz = {
      'owner':       widget.ownerEmail,
      'name':        _nameCtrl.text.trim(),
      'imagePath':   _imagePath ?? '',
      'website':     _websiteCtrl.text.trim(),
      'description': _descCtrl.text.trim(),
      'category':    _category,
      'location':    _locCtrl.text.trim(),
    };

    final ok = await LocalDB.addBusiness(biz);
    if (mounted) {
      setState(() => _submitting = false);
      if (ok) {
        widget.onSubmitted();
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Business added to NOVA X ✓',
              style: GoogleFonts.inter(color: Colors.white)),
          backgroundColor: AppTheme.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Maximum 2 businesses reached',
              style: GoogleFonts.inter(color: Colors.white)),
          backgroundColor: AppTheme.danger,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.only(
        left: 24, right: 24, top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 28,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Handle
            Center(child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(color: AppTheme.textHint,
                  borderRadius: BorderRadius.circular(2)),
            )),
            const SizedBox(height: 20),

            // Title
            Row(children: [
              ShaderMask(
                shaderCallback: (b) => AppTheme.primaryGradient.createShader(b),
                child: const Icon(Icons.business_center_rounded,
                    color: Colors.white, size: 22),
              ),
              const SizedBox(width: 10),
              Text('Add Your Business',
                  style: GoogleFonts.spaceGrotesk(
                      color: AppTheme.textPrimary,
                      fontSize: 18, fontWeight: FontWeight.w700)),
            ]),

            const SizedBox(height: 4),
            Text('This will appear in the NOVA X Business directory',
                style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 12)),

            const SizedBox(height: 22),

            // Business image
            GestureDetector(
              onTap: _pickImage,
              child: Container(
                width: double.infinity, height: 140,
                decoration: BoxDecoration(
                  color: AppTheme.bgElevated,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.divider, style: BorderStyle.solid),
                ),
                clipBehavior: Clip.hardEdge,
                child: _imagePath != null
                    ? Stack(fit: StackFit.expand, children: [
                        Image.file(File(_imagePath!), fit: BoxFit.cover),
                        Positioned(bottom: 8, right: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(8)),
                            child: Text('Change',
                                style: GoogleFonts.inter(color: Colors.white, fontSize: 11)),
                          ),
                        ),
                      ])
                    : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        const Icon(Icons.add_photo_alternate_outlined,
                            color: AppTheme.accentCyan, size: 32),
                        const SizedBox(height: 8),
                        Text('Upload Business Image (optional)',
                            style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 12)),
                      ]),
              ),
            ),

            const SizedBox(height: 16),

            // Name
            _field('Business Name *', _nameCtrl,
                validator: (v) => (v?.trim().isEmpty ?? true) ? 'Required' : null),

            const SizedBox(height: 12),

            // Website
            _field('Website URL (e.g. https://yourbiz.com)', _websiteCtrl,
                inputType: TextInputType.url),

            const SizedBox(height: 12),

            // Description
            _field('Description *', _descCtrl, maxLines: 3,
                validator: (v) => (v?.trim().isEmpty ?? true) ? 'Required' : null),

            const SizedBox(height: 12),

            // Category dropdown
            Text('Category',
                style: GoogleFonts.inter(
                    color: AppTheme.textHint, fontSize: 11, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: AppTheme.bgElevated,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.divider),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _category,
                  dropdownColor: AppTheme.bgElevated,
                  iconEnabledColor: AppTheme.textHint,
                  style: GoogleFonts.inter(color: AppTheme.textPrimary, fontSize: 13),
                  isExpanded: true,
                  items: _bizCategories
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (v) { if (v != null) setState(() => _category = v); },
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Location
            _field('Location (City, Country)', _locCtrl),

            const SizedBox(height: 24),

            // Submit
            GestureDetector(
              onTap: _submitting ? null : _submit,
              child: Container(
                height: 52,
                decoration: BoxDecoration(
                  gradient: AppTheme.primaryGradient,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: AppTheme.glowShadow,
                ),
                child: Center(
                  child: _submitting
                      ? const SizedBox(width: 22, height: 22,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text('Submit Business',
                          style: GoogleFonts.spaceGrotesk(
                              color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _field(String hint, TextEditingController ctrl,
      {TextInputType inputType = TextInputType.text,
      int maxLines = 1, String? Function(String?)? validator}) {
    return TextFormField(
      controller:   ctrl,
      maxLines:     maxLines,
      keyboardType: inputType,
      validator:    validator,
      style: GoogleFonts.inter(color: AppTheme.textPrimary, fontSize: 13),
      decoration: InputDecoration(
        hintText:      hint,
        hintStyle:     GoogleFonts.inter(color: AppTheme.textHint, fontSize: 13),
        filled:        true,
        fillColor:     AppTheme.bgElevated,
        border:        OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppTheme.accentCyan)),
        errorBorder:   OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppTheme.danger)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }
}
