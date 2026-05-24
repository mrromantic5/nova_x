import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nova_x/core/database/local_db.dart';
import 'package:nova_x/core/theme/app_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _engine = 'google';

  @override
  void initState() {
    super.initState();
    _engine = LocalDB.getSearchEngine();
  }

  Future<void> _setEngine(String e) async {
    await LocalDB.setSearchEngine(e);
    setState(() => _engine = e);
  }

  Future<void> _clearHistory() async {
    await LocalDB.clearHistory();
    _snack('History cleared');
  }

  Future<void> _clearBookmarks() async {
    await LocalDB.clearBookmarks();
    _snack('Bookmarks cleared');
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.inter(color: Colors.white)),
      backgroundColor: AppTheme.bgElevated,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      appBar: AppBar(
        backgroundColor: AppTheme.bgDark,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AppTheme.textSecondary, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Settings',
            style: GoogleFonts.spaceGrotesk(
                color: AppTheme.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
        children: [
          // ── Search engine ─────────────────────────────────────────
          _sectionHeader('Search Engine'),
          _card([
            _engineTile('google',     'Google',     'google.com'),
            _engineTile('bing',       'Bing',        'bing.com'),
            _engineTile('duckduckgo', 'DuckDuckGo',  'duckduckgo.com'),
            _engineTile('yahoo',      'Yahoo',        'yahoo.com'),
          ]),

          // ── Privacy ──────────────────────────────────────────────
          _sectionHeader('Privacy & Data'),
          _card([
            _actionTile(
              Icons.history_rounded,
              'Clear History',
              'Delete all visited pages',
              AppTheme.accentPurple,
              _confirmAction('Clear browsing history?', _clearHistory),
            ),
            _actionTile(
              Icons.bookmark_border_rounded,
              'Clear Bookmarks',
              'Remove all saved bookmarks',
              AppTheme.warning,
              _confirmAction('Remove all bookmarks?', _clearBookmarks),
            ),
          ]),

          // ── About ────────────────────────────────────────────────
          _sectionHeader('About'),
          _card([
            _infoTile(Icons.info_outline_rounded, 'Version', '2.0.0'),
            _infoTile(Icons.person_outline_rounded, 'Developer', 'Kobby (Mr. Romantic)'),
            _infoTile(Icons.business_outlined, 'Company', 'Tech Lyfe Team'),
            _infoTile(Icons.code_rounded, 'Engine', 'NOVA X Engine v2'),
          ]),
        ],
      ),
    );
  }

  Widget _sectionHeader(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 24, 4, 10),
      child: Text(label.toUpperCase(),
          style: GoogleFonts.inter(
              color: AppTheme.textHint,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2)),
    );
  }

  Widget _card(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(children: children),
    );
  }

  Widget _engineTile(String key, String name, String domain) {
    final active = _engine == key;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: active
              ? AppTheme.primaryBlue.withOpacity(0.15)
              : AppTheme.bgElevated,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Center(
          child: Text(name[0],
              style: TextStyle(
                  color: active ? AppTheme.primaryBlue : AppTheme.textHint,
                  fontSize: 16,
                  fontWeight: FontWeight.bold)),
        ),
      ),
      title: Text(name,
          style: GoogleFonts.inter(
              color: AppTheme.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w500)),
      subtitle: Text(domain,
          style: GoogleFonts.inter(
              color: AppTheme.textHint, fontSize: 11)),
      trailing: active
          ? const Icon(Icons.check_circle_rounded,
              color: AppTheme.primaryBlue, size: 20)
          : const Icon(Icons.circle_outlined,
              color: AppTheme.textHint, size: 20),
      onTap: () => _setEngine(key),
    );
  }

  Widget _actionTile(IconData icon, String title, String subtitle,
      Color color, VoidCallback onTap) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: color, size: 18),
      ),
      title: Text(title,
          style: GoogleFonts.inter(
              color: AppTheme.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w500)),
      subtitle: Text(subtitle,
          style: GoogleFonts.inter(
              color: AppTheme.textHint, fontSize: 11)),
      trailing: const Icon(Icons.chevron_right_rounded,
          color: AppTheme.textHint, size: 18),
      onTap: onTap,
    );
  }

  Widget _infoTile(IconData icon, String label, String value) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: AppTheme.bgElevated,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: AppTheme.textHint, size: 18),
      ),
      title: Text(label,
          style: GoogleFonts.inter(
              color: AppTheme.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w500)),
      trailing: Text(value,
          style: GoogleFonts.inter(
              color: AppTheme.textHint, fontSize: 13)),
    );
  }

  VoidCallback _confirmAction(String message, Future<void> Function() fn) {
    return () async {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: AppTheme.bgCard,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('Confirm',
              style: GoogleFonts.spaceGrotesk(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.bold)),
          content: Text(message,
              style: GoogleFonts.inter(color: AppTheme.textSecondary)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text('Cancel',
                    style: GoogleFonts.inter(color: AppTheme.textHint))),
            TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text('Confirm',
                    style: GoogleFonts.inter(color: AppTheme.danger))),
          ],
        ),
      );
      if (ok == true) await fn();
    };
  }
}
