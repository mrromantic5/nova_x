import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nova_x/core/database/local_db.dart';
import 'package:nova_x/core/theme/app_theme.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _nameCtrl  = TextEditingController();
  final _emailCtrl = TextEditingController();
  bool _saving = false;
  int  _avatarColor = 0; // 0–5 color preset

  final List<Color> _avatarColors = [
    AppTheme.primaryBlue,
    AppTheme.accentCyan,
    const Color(0xFFFF6B6B),
    const Color(0xFFFFAB00),
    AppTheme.accentPurple,
    const Color(0xFF00C853),
  ];

  Map<String, dynamic> _stats = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final p = LocalDB.getProfile();
    _nameCtrl.text  = p['name']  as String? ?? '';
    _emailCtrl.text = p['email'] as String? ?? '';
    _avatarColor    = (p['avatarColor'] as int?) ?? 0;
    _stats = {
      'bookmarks': LocalDB.getBookmarks().length,
      'history':   LocalDB.getHistory().length,
      'downloads': LocalDB.getDownloads().length,
    };
    setState(() {});
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _snack('Please enter your name');
      return;
    }
    setState(() => _saving = true);
    await LocalDB.saveProfile({
      'name':        name,
      'email':       _emailCtrl.text.trim(),
      'avatarColor': _avatarColor,
    });
    setState(() => _saving = false);
    _snack('✓ Profile saved!');
  }

  Future<void> _clearData() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Clear All Data',
            style: GoogleFonts.spaceGrotesk(
                color: AppTheme.textPrimary, fontWeight: FontWeight.bold)),
        content: Text('History, bookmarks, downloads and profile will be deleted.',
            style: GoogleFonts.inter(color: AppTheme.textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancel',
                  style: GoogleFonts.inter(color: AppTheme.textHint))),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('Clear All',
                  style: GoogleFonts.inter(color: AppTheme.danger))),
        ],
      ),
    );
    if (ok == true) {
      await LocalDB.clearHistory();
      await LocalDB.clearBookmarks();
      await LocalDB.clearDownloads();
      await LocalDB.clearProfile();
      await LocalDB.clearSearchHistory();
      _nameCtrl.clear();
      _emailCtrl.clear();
      setState(() { _avatarColor = 0; });
      _load();
      _snack('All data cleared');
    }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(msg, style: GoogleFonts.inter(color: Colors.white)),
    backgroundColor: AppTheme.bgElevated,
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  ));

  // ═══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final name = _nameCtrl.text.trim();
    final initial = name.isNotEmpty ? name[0].toUpperCase() : 'N';
    final color   = _avatarColors[_avatarColor % _avatarColors.length];

    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      appBar: AppBar(
        backgroundColor: AppTheme.bgDark,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AppTheme.textSecondary, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('My Profile',
            style: GoogleFonts.spaceGrotesk(
                color: AppTheme.textPrimary,
                fontSize: 18, fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          // ── Avatar ──────────────────────────────────────────────────
          Center(
            child: Column(children: [
              Container(
                width: 90, height: 90,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.2),
                  shape: BoxShape.circle,
                  border: Border.all(color: color, width: 2.5),
                ),
                child: Center(
                  child: Text(initial,
                      style: GoogleFonts.spaceGrotesk(
                          color: color, fontSize: 36, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 16),
              // Avatar color picker
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_avatarColors.length, (i) {
                  final c = _avatarColors[i];
                  return GestureDetector(
                    onTap: () => setState(() => _avatarColor = i),
                    child: Container(
                      width: 30, height: 30,
                      margin: const EdgeInsets.symmetric(horizontal: 5),
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: _avatarColor == i
                            ? Border.all(color: Colors.white, width: 2.5)
                            : null,
                      ),
                      child: _avatarColor == i
                          ? const Icon(Icons.check, color: Colors.white, size: 16)
                          : null,
                    ),
                  );
                }),
              ),
            ]),
          ),

          const SizedBox(height: 28),

          // ── Form ────────────────────────────────────────────────────
          _label('ACCOUNT DETAILS'),
          _card([
            _field(_nameCtrl,  'Full Name',  Icons.person_outline_rounded),
            const Divider(color: AppTheme.divider, height: 1),
            _field(_emailCtrl, 'Email Address', Icons.email_outlined),
          ]),

          const SizedBox(height: 24),

          // Save button
          GestureDetector(
            onTap: _saving ? null : _save,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 15),
              decoration: BoxDecoration(
                gradient: AppTheme.primaryGradient,
                borderRadius: BorderRadius.circular(16),
                boxShadow: AppTheme.glowShadow,
              ),
              child: Center(
                child: _saving
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : Text('Save Profile',
                        style: GoogleFonts.spaceGrotesk(
                            color: Colors.white,
                            fontSize: 15, fontWeight: FontWeight.w700)),
              ),
            ),
          ),

          const SizedBox(height: 28),

          // ── Stats ──────────────────────────────────────────────────
          _label('YOUR STATS'),
          Row(children: [
            _statCard('Bookmarks',  '${_stats['bookmarks'] ?? 0}',
                Icons.bookmark_outline_rounded, AppTheme.warning),
            const SizedBox(width: 10),
            _statCard('History',    '${_stats['history'] ?? 0}',
                Icons.history_rounded, AppTheme.accentPurple),
            const SizedBox(width: 10),
            _statCard('Downloads',  '${_stats['downloads'] ?? 0}',
                Icons.download_outlined, AppTheme.primaryBlue),
          ]),

          const SizedBox(height: 28),

          // ── Danger zone ─────────────────────────────────────────────
          _label('DANGER ZONE'),
          _card([
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: AppTheme.danger.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.delete_forever_outlined,
                    color: AppTheme.danger, size: 18),
              ),
              title: Text('Clear All Browser Data',
                  style: GoogleFonts.inter(
                      color: AppTheme.textPrimary,
                      fontSize: 14, fontWeight: FontWeight.w500)),
              subtitle: Text('History, bookmarks, downloads & profile',
                  style: GoogleFonts.inter(
                      color: AppTheme.textHint, fontSize: 11)),
              trailing: const Icon(Icons.chevron_right_rounded,
                  color: AppTheme.textHint, size: 18),
              onTap: _clearData,
            ),
          ]),
        ],
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 0, 2, 10),
    child: Text(text,
        style: GoogleFonts.inter(
            color: AppTheme.textHint,
            fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
  );

  Widget _card(List<Widget> children) => Container(
    decoration: BoxDecoration(
      color: AppTheme.bgCard,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppTheme.divider),
    ),
    child: Column(children: children),
  );

  Widget _field(TextEditingController ctrl, String hint, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(children: [
        Icon(icon, color: AppTheme.textHint, size: 18),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            controller: ctrl,
            style: GoogleFonts.inter(color: AppTheme.textPrimary, fontSize: 14),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              border: InputBorder.none,
              hintText: hint,
              hintStyle: GoogleFonts.inter(
                  color: AppTheme.textHint, fontSize: 14),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color.withOpacity(0.15), color.withOpacity(0.05)],
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
                  fontSize: 20, fontWeight: FontWeight.bold)),
          Text(label,
              style: GoogleFonts.inter(
                  color: AppTheme.textHint, fontSize: 10)),
        ]),
      ),
    );
  }
}
