// lib/features/password/password_manager_screen.dart
import 'package:flutter/material.dart';
import 'package:nova_x/core/services/biometric_service.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nova_x/core/services/password_service.dart';
import 'package:nova_x/core/theme/app_theme.dart';

class PasswordManagerScreen extends StatefulWidget {
  const PasswordManagerScreen({super.key});
  @override
  State<PasswordManagerScreen> createState() => _PasswordManagerScreenState();
}

class _PasswordManagerScreenState extends State<PasswordManagerScreen> {
  List<Map<String, String>> _creds = [];
  bool _loading = true;
  bool _unlocked = false;
  final Set<int> _revealed = {};
  String _search = '';

  @override
  void initState() {
    super.initState();
    _gate();
  }

  Future<void> _gate() async {
    final ok = await BiometricService.verify('Verify it\'s you to view saved passwords');
    if (!mounted) return;
    if (!ok) { Navigator.pop(context); return; }
    setState(() => _unlocked = true);
    _load();
  }

  Future<void> _load() async {
    final all = await PasswordService.getAllCredentials();
    if (mounted) setState(() { _creds = all; _loading = false; });
  }

  Future<void> _delete(String domain) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Delete password?', style: GoogleFonts.spaceGrotesk(
            color: AppTheme.textPrimary, fontWeight: FontWeight.bold)),
        content: Text('Remove saved password for "$domain"?',
            style: GoogleFonts.inter(color: AppTheme.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: Text('Cancel', style: GoogleFonts.inter(color: AppTheme.textHint))),
          TextButton(onPressed: () => Navigator.pop(context, true),
              child: Text('Delete', style: GoogleFonts.inter(color: AppTheme.danger))),
        ],
      ),
    );
    if (ok == true) {
      await PasswordService.deleteCredentials(domain);
      _load();
      _snack('Password deleted');
    }
  }

  Future<void> _deleteAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Delete all passwords?', style: GoogleFonts.spaceGrotesk(
            color: AppTheme.textPrimary, fontWeight: FontWeight.bold)),
        content: Text('This will remove all ${_creds.length} saved passwords.',
            style: GoogleFonts.inter(color: AppTheme.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: Text('Cancel', style: GoogleFonts.inter(color: AppTheme.textHint))),
          TextButton(onPressed: () => Navigator.pop(context, true),
              child: Text('Delete All', style: GoogleFonts.inter(color: AppTheme.danger))),
        ],
      ),
    );
    if (ok == true) {
      await PasswordService.deleteAllCredentials();
      _load();
      _snack('All passwords deleted');
    }
  }

  void _copy(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    _snack('$label copied to clipboard');
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(msg, style: GoogleFonts.inter(color: Colors.white)),
    backgroundColor: AppTheme.bgElevated,
    behavior: SnackBarBehavior.floating,
    duration: const Duration(seconds: 2),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  ));

  List<Map<String, String>> get _filtered => _search.isEmpty
      ? _creds
      : _creds.where((c) =>
          (c['domain'] ?? '').toLowerCase().contains(_search.toLowerCase()) ||
          (c['username'] ?? '').toLowerCase().contains(_search.toLowerCase())).toList();

  @override
  Widget build(BuildContext context) {
    if (!_unlocked) {
      return const Scaffold(
        backgroundColor: AppTheme.bgDark,
        body: Center(
          child: Icon(Icons.lock_rounded, color: AppTheme.textHint, size: 48),
        ),
      );
    }
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
        title: Text('Saved Passwords', style: GoogleFonts.spaceGrotesk(
            color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
        actions: [
          if (_creds.isNotEmpty)
            TextButton(
              onPressed: _deleteAll,
              child: Text('Clear all', style: GoogleFonts.inter(
                  color: AppTheme.danger, fontSize: 13, fontWeight: FontWeight.w600)),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.accentCyan))
          : Column(children: [
              // Search bar
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: TextField(
                  onChanged: (v) => setState(() => _search = v),
                  style: GoogleFonts.inter(color: AppTheme.textPrimary, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Search passwords…',
                    hintStyle: GoogleFonts.inter(color: AppTheme.textHint),
                    prefixIcon: const Icon(Icons.search_rounded,
                        color: AppTheme.textHint, size: 18),
                    filled: true, fillColor: AppTheme.bgCard,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(
                            color: AppTheme.accentCyan, width: 1.5)),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                  ),
                ),
              ),

              if (_creds.isEmpty)
                Expanded(child: Center(child: Column(
                  mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      width: 72, height: 72,
                      decoration: BoxDecoration(
                        color: AppTheme.bgCard,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppTheme.divider),
                      ),
                      child: const Icon(Icons.key_off_rounded,
                          color: AppTheme.textHint, size: 32),
                    ),
                    const SizedBox(height: 16),
                    Text('No saved passwords', style: GoogleFonts.spaceGrotesk(
                        color: AppTheme.textPrimary, fontSize: 18,
                        fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Text('Passwords are saved when you log in\nto websites in NOVA X',
                        style: GoogleFonts.inter(color: AppTheme.textHint,
                            fontSize: 13, height: 1.5),
                        textAlign: TextAlign.center),
                  ],
                )))
              else
                Expanded(child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                  itemCount: _filtered.length,
                  itemBuilder: (_, i) {
                    final cred     = _filtered[i];
                    final domain   = cred['domain']   ?? '';
                    final username = cred['username'] ?? '';
                    final password = cred['password'] ?? '';
                    final revealed = _revealed.contains(i);

                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: AppTheme.bgCard,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppTheme.divider),
                      ),
                      child: Column(children: [
                        // Domain header
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 14, 12, 0),
                          child: Row(children: [
                            Container(
                              width: 38, height: 38,
                              decoration: BoxDecoration(
                                gradient: AppTheme.primaryGradient,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Center(child: Text(
                                domain.isNotEmpty ? domain[0].toUpperCase() : '?',
                                style: GoogleFonts.spaceGrotesk(
                                    color: Colors.white, fontSize: 16,
                                    fontWeight: FontWeight.w800),
                              )),
                            ),
                            const SizedBox(width: 12),
                            Expanded(child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(domain, style: GoogleFonts.inter(
                                    color: AppTheme.textPrimary, fontSize: 14,
                                    fontWeight: FontWeight.w600)),
                                if (username.isNotEmpty)
                                  Text(username, style: GoogleFonts.inter(
                                      color: AppTheme.textHint, fontSize: 11)),
                              ],
                            )),
                            // Delete
                            IconButton(
                              icon: const Icon(Icons.delete_outline_rounded,
                                  color: AppTheme.danger, size: 18),
                              onPressed: () => _delete(domain),
                            ),
                          ]),
                        ),

                        // Credentials detail
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                          child: Column(children: [
                            // Username row
                            if (username.isNotEmpty) _credRow(
                              Icons.person_outline_rounded,
                              'Username',
                              username,
                              false,
                              () => _copy(username, 'Username'),
                            ),
                            const SizedBox(height: 8),
                            // Password row
                            _credRow(
                              Icons.lock_outline_rounded,
                              'Password',
                              revealed ? password : '•' * 10,
                              true,
                              () => _copy(password, 'Password'),
                              onToggle: () => setState(() {
                                if (revealed) {
                                  _revealed.remove(i);
                                } else {
                                  _revealed.add(i);
                                }
                              }),
                              revealed: revealed,
                            ),
                          ]),
                        ),
                      ]),
                    );
                  },
                )),
            ]),
    );
  }

  Widget _credRow(IconData icon, String label, String value, bool isPassword,
      VoidCallback onCopy, {VoidCallback? onToggle, bool revealed = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.bgElevated,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Row(children: [
        Icon(icon, color: AppTheme.textHint, size: 15),
        const SizedBox(width: 8),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: GoogleFonts.inter(
              color: AppTheme.textHint, fontSize: 10, fontWeight: FontWeight.w600)),
          Text(value, style: GoogleFonts.inter(
              color: AppTheme.textPrimary, fontSize: 13),
              overflow: TextOverflow.ellipsis),
        ])),
        if (isPassword && onToggle != null)
          GestureDetector(
            onTap: onToggle,
            child: Icon(
                revealed ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                color: AppTheme.textHint, size: 16),
          ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: onCopy,
          child: const Icon(Icons.copy_rounded,
              color: AppTheme.accentCyan, size: 16),
        ),
      ]),
    );
  }
}
