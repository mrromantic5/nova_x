// lib/features/settings/screens/settings_screen.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:nova_x/core/database/local_db.dart';
import 'package:nova_x/core/services/password_service.dart';
import '../../password/password_manager_screen.dart';
import 'package:nova_x/core/theme/app_theme.dart';
import '../../profile/screens/profile_screen.dart';
import '../../customization/screens/customization_screen.dart';
import '../../customization/screens/speed_dial_editor_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _engine = 'google';
  Map<String, dynamic> _profile = {};
  bool   _adBlock       = false;
  bool   _savePasswords = true;
  int    _savedPwCount  = 0;

  @override
  void initState() {
    super.initState();
    _engine       = LocalDB.getSearchEngine();
    _profile      = LocalDB.getProfile();
    _adBlock      = LocalDB.getAdBlockEnabled();
    _savePasswords= LocalDB.getSavePasswordsEnabled();
    _loadPwCount();
  }

  Future<void> _loadPwCount() async {
    final all = await PasswordService.getAllCredentials();
    if (mounted) setState(() => _savedPwCount = all.length);
  }

  Future<void> _setEngine(String e) async {
    await LocalDB.setSearchEngine(e);
    setState(() => _engine = e);
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(msg, style: GoogleFonts.inter(color: Colors.white)),
        backgroundColor: AppTheme.bgElevated,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));

  Future<void> _push(Widget screen) => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => screen),
  ).then((_) => setState(() {
    _profile = LocalDB.getProfile();
    _engine  = LocalDB.getSearchEngine();
    _adBlock = LocalDB.getAdBlockEnabled();
    _savePasswords = LocalDB.getSavePasswordsEnabled();
  }));

  VoidCallback _confirm(String title, String body, Future<void> Function() fn) {
    return () async {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: AppTheme.bgCard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(title,
              style: GoogleFonts.spaceGrotesk(
                  color: AppTheme.textPrimary, fontWeight: FontWeight.bold)),
          content: Text(body,
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

  Color _resolveAvatarColor() {
    final raw = _profile['avatarColor'];
    if (raw is int) {
      final colors = [
        AppTheme.primaryBlue, AppTheme.accentCyan,
        const Color(0xFFFF6B6B), const Color(0xFFFFAB00),
        AppTheme.accentPurple, const Color(0xFF00C853),
      ];
      return colors[raw % colors.length];
    }
    return switch (raw as String? ?? 'cyan') {
      'red'    => const Color(0xFFFF6B6B),
      'orange' => const Color(0xFFFFAB00),
      'purple' => AppTheme.accentPurple,
      'green'  => AppTheme.success,
      _        => AppTheme.accentCyan,
    };
  }

  @override
  Widget build(BuildContext context) {
    final name        = _profile['name']  as String? ?? 'Guest';
    final email       = _profile['email'] as String? ?? 'No email set';
    final avatarColor = _resolveAvatarColor();

    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      appBar: AppBar(
        backgroundColor: AppTheme.bgDark,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AppTheme.textSecondary, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Settings',
            style: GoogleFonts.spaceGrotesk(
                color: AppTheme.textPrimary,
                fontSize: 18, fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
        children: [

          // ── Profile card ───────────────────────────────────────────────
          GestureDetector(
            onTap: () => _push(const ProfileScreen()),
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 16),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppTheme.primaryBlue.withOpacity(0.2),
                    AppTheme.accentCyan.withOpacity(0.08),
                  ],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.primaryBlue.withOpacity(0.3)),
              ),
              child: Row(children: [
                Container(
                  width: 52, height: 52,
                  decoration: BoxDecoration(
                    color: avatarColor.withOpacity(0.2),
                    shape: BoxShape.circle,
                    border: Border.all(color: avatarColor, width: 2),
                  ),
                  child: Center(child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : 'N',
                    style: GoogleFonts.spaceGrotesk(
                        color: avatarColor, fontSize: 22, fontWeight: FontWeight.bold),
                  )),
                ),
                const SizedBox(width: 14),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: GoogleFonts.spaceGrotesk(
                        color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
                    Text(email, style: GoogleFonts.inter(
                        color: AppTheme.textHint, fontSize: 12)),
                  ],
                )),
                const Icon(Icons.chevron_right_rounded, color: AppTheme.textHint),
              ]),
            ),
          ),

          // ── Customization ──────────────────────────────────────────────
          _sectionHeader('Browser Customization'),
          _card([
            _navTile(Icons.palette_outlined,    'Background',
                'Change your home screen wallpaper',
                AppTheme.accentCyan,
                () => _push(const CustomizationScreen())),
            _navTile(Icons.grid_view_rounded,   'Quick Access',
                'Edit your speed-dial shortcuts',
                AppTheme.accentPurple,
                () => _push(const SpeedDialEditorScreen())),
          ]),

          // ── Search Engine ──────────────────────────────────────────────
          _sectionHeader('Search Engine'),
          _card([
            _engineTile('google',     'Google',     'google.com'),
            _engineTile('bing',       'Bing',        'bing.com'),
            _engineTile('duckduckgo', 'DuckDuckGo', 'duckduckgo.com'),
            _engineTile('yahoo',      'Yahoo',       'yahoo.com'),
          ]),

          // ── Security & Passwords ────────────────────────────────────────
          _sectionHeader('Security & Passwords'),
          _card([
            // Ad Blocker toggle
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              leading: Container(
                width: 34, height: 34,
                decoration: BoxDecoration(
                  color: (_adBlock ? AppTheme.success : AppTheme.textHint).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10)),
                child: Icon(Icons.shield_rounded,
                    color: _adBlock ? AppTheme.success : AppTheme.textHint, size: 17)),
              title: Text('Ad Blocker', style: GoogleFonts.inter(
                  color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w500)),
              subtitle: Text(_adBlock ? 'Blocking ads & trackers' : 'Ads not blocked',
                  style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 11)),
              trailing: Switch(
                value: _adBlock,
                onChanged: (v) async {
                  await LocalDB.setAdBlockEnabled(v);
                  setState(() => _adBlock = v);
                  _snack(v ? '🛡️ Ad Blocker enabled' : 'Ad Blocker disabled');
                },
                activeColor: AppTheme.success,
              ),
            ),
            // Save Passwords toggle
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              leading: Container(
                width: 34, height: 34,
                decoration: BoxDecoration(
                  color: AppTheme.accentCyan.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.key_rounded, color: AppTheme.accentCyan, size: 17)),
              title: Text('Save Passwords', style: GoogleFonts.inter(
                  color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w500)),
              subtitle: Text(_savePasswords ? 'Offer to save logins' : 'Never save passwords',
                  style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 11)),
              trailing: Switch(
                value: _savePasswords,
                onChanged: (v) async {
                  await LocalDB.setSavePasswordsEnabled(v);
                  setState(() => _savePasswords = v);
                },
                activeColor: AppTheme.accentCyan,
              ),
            ),
            // Saved Passwords management
            _navTile(Icons.password_rounded, 'Saved Passwords',
                '$_savedPwCount password${_savedPwCount == 1 ? '' : 's'} stored',
                AppTheme.accentPurple,
                () => _push(const PasswordManagerScreen()).then((_) => _loadPwCount())),
          ]),

          // ── Privacy & Data ──────────────────────────────────────────────
          _sectionHeader('Privacy & Data'),
          _card([
            _actionTile(
              Icons.history_rounded, 'Clear History',
              'Delete all visited pages', AppTheme.accentPurple,
              _confirm('Clear History', 'Delete all browsing history?',
                  () async { await LocalDB.clearHistory(); _snack('History cleared'); }),
            ),
            _actionTile(
              Icons.bookmark_border_rounded, 'Clear Bookmarks',
              'Remove all saved bookmarks', AppTheme.warning,
              _confirm('Clear Bookmarks', 'Remove all bookmarks?',
                  () async { await LocalDB.clearBookmarks(); _snack('Bookmarks cleared'); }),
            ),
            _actionTile(
              Icons.download_outlined, 'Clear Downloads',
              'Remove download records', AppTheme.primaryBlue,
              _confirm('Clear Downloads', 'Remove all download records?',
                  () async { await LocalDB.clearDownloads(); _snack('Downloads cleared'); }),
            ),
            _actionTile(
              Icons.manage_search_rounded, 'Clear Search History',
              'Remove recent searches', AppTheme.accentCyan,
              _confirm('Clear Search History', 'Remove all recent searches?',
                  () async { await LocalDB.clearSearchHistory(); _snack('Search history cleared'); }),
            ),
          ]),

          const SizedBox(height: 4),
          // Clear ALL browser data in one tap
          _actionTile(
            Icons.delete_sweep_rounded, 'Clear All Browser Data',
            'Cookies, cache, history, searches & downloads',
            AppTheme.danger,
            _confirm(
              'Clear All Browser Data',
              'This will delete your entire browsing history, cookies, cache, search history and download records. This cannot be undone.',
              () async {
                // Clear WebView cookies + cache
                await CookieManager.instance().deleteAllCookies();
                await InAppWebViewController.clearAllCache();
                // Clear local records
                await LocalDB.clearHistory();
                await LocalDB.clearBookmarks();
                await LocalDB.clearDownloads();
                await LocalDB.clearSearchHistory();
                _snack('🧹 All browser data cleared');
              },
            ),
          ),

          // ── About ──────────────────────────────────────────────────────
          _sectionHeader('About NOVA X'),
          _card([
            _infoTile(Icons.info_outline_rounded,   'Version',   '2.2.0'),
            _infoTile(Icons.person_outline_rounded, 'Developer', 'Kobby (Mr. Romantic)'),
            _infoTile(Icons.business_outlined,      'Company',   'Tech Lyfe Team'),
            _infoTile(Icons.code_rounded,           'Engine',    'NOVA X Engine v2.2'),
          ]),
        ],
      ),
    );
  }

  Widget _sectionHeader(String label) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
    child: Text(label.toUpperCase(),
        style: GoogleFonts.inter(
            color: AppTheme.textHint, fontSize: 11,
            fontWeight: FontWeight.w700, letterSpacing: 1.2)),
  );

  Widget _card(List<Widget> children) => Container(
    decoration: BoxDecoration(
      color: AppTheme.bgCard,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppTheme.divider),
    ),
    child: Column(children: children),
  );

  Widget _navTile(IconData icon, String title, String subtitle,
      Color color, VoidCallback onTap) =>
      ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        leading: Container(
          width: 34, height: 34,
          decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: color, size: 17),
        ),
        title: Text(title, style: GoogleFonts.inter(
            color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w500)),
        subtitle: Text(subtitle, style: GoogleFonts.inter(
            color: AppTheme.textHint, fontSize: 11)),
        trailing: const Icon(Icons.chevron_right_rounded,
            color: AppTheme.textHint, size: 18),
        onTap: onTap,
      );

  Widget _engineTile(String key, String name, String domain) {
    final active = _engine == key;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Container(
        width: 34, height: 34,
        decoration: BoxDecoration(
          color: active
              ? AppTheme.primaryBlue.withOpacity(0.15)
              : AppTheme.bgElevated,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Center(child: Text(name[0],
            style: TextStyle(
                color: active ? AppTheme.primaryBlue : AppTheme.textHint,
                fontSize: 16, fontWeight: FontWeight.bold))),
      ),
      title: Text(name, style: GoogleFonts.inter(
          color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w500)),
      subtitle: Text(domain, style: GoogleFonts.inter(
          color: AppTheme.textHint, fontSize: 11)),
      trailing: active
          ? const Icon(Icons.check_circle_rounded, color: AppTheme.primaryBlue, size: 20)
          : const Icon(Icons.circle_outlined, color: AppTheme.textHint, size: 20),
      onTap: () => _setEngine(key),
    );
  }

  Widget _actionTile(IconData icon, String title, String subtitle,
      Color color, VoidCallback onTap) =>
      ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        leading: Container(
          width: 34, height: 34,
          decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: color, size: 17),
        ),
        title: Text(title, style: GoogleFonts.inter(
            color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w500)),
        subtitle: Text(subtitle, style: GoogleFonts.inter(
            color: AppTheme.textHint, fontSize: 11)),
        trailing: const Icon(Icons.chevron_right_rounded,
            color: AppTheme.textHint, size: 18),
        onTap: onTap,
      );

  Widget _infoTile(IconData icon, String label, String value) =>
      ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        leading: Container(
          width: 34, height: 34,
          decoration: BoxDecoration(
              color: AppTheme.bgElevated,
              borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: AppTheme.textHint, size: 17),
        ),
        title: Text(label, style: GoogleFonts.inter(
            color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w500)),
        trailing: Text(value, style: GoogleFonts.inter(
            color: AppTheme.textHint, fontSize: 12)),
      );
}
