// lib/core/widgets/update_dialog.dart
//
// NOVA X — "Update available" popup (3.9.0).
// ✕ and "Maybe later" close it (it comes back on the next app launch until
// the user updates); "Update now" opens NOVA X on Google Play. A forced
// update has neither ✕ nor "Maybe later" and can't be closed with Back.

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart' as ul;

import '../services/platform_api.dart';
import '../theme/app_theme.dart';

class UpdateDialog extends StatefulWidget {
  const UpdateDialog({super.key, required this.currentVersion, required this.release});

  final String currentVersion;
  final AppRelease release;

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> with SingleTickerProviderStateMixin {
  late final AnimationController _anim =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 520))..forward();
  bool _opening = false;

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  Future<void> _update() async {
    if (_opening) return;
    setState(() => _opening = true);
    final rel = widget.release;
    // Play Store app first, then the web page.
    final market = Uri.parse('market://details?id=com.tlyfe.nova_x');
    final web = Uri.parse(rel.playUrl);
    var ok = false;
    try {
      ok = await ul.launchUrl(market, mode: ul.LaunchMode.externalApplication);
    } catch (_) {}
    if (!ok) {
      try {
        ok = await ul.launchUrl(web, mode: ul.LaunchMode.externalApplication);
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() => _opening = false);
    if (ok && !rel.forceUpdate) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final rel = widget.release;
    final forced = rel.forceUpdate;
    final curved = CurvedAnimation(parent: _anim, curve: Curves.easeOutBack);

    return PopScope(
      canPop: !forced,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
          child: ScaleTransition(
            scale: Tween(begin: 0.9, end: 1.0).animate(curved),
            child: FadeTransition(
              opacity: _anim,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 420),
                decoration: BoxDecoration(
                  color: AppTheme.bgCard,
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: AppTheme.primaryBlue.withOpacity(0.35)),
                  boxShadow: [
                    BoxShadow(color: AppTheme.primaryBlue.withOpacity(0.25), blurRadius: 40, spreadRadius: 2),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: SingleChildScrollView(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      _header(rel, forced),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          if (rel.message.trim().isNotEmpty) ...[
                            Text(rel.message.trim(),
                                style: GoogleFonts.inter(
                                    color: AppTheme.textSecondary, fontSize: 13.5, height: 1.5)),
                            const SizedBox(height: 16),
                          ],
                          if (rel.whatsNew.isNotEmpty) ...[
                            Text("WHAT'S NEW",
                                style: GoogleFonts.inter(
                                    color: AppTheme.accentCyan,
                                    fontSize: 11,
                                    letterSpacing: 1.4,
                                    fontWeight: FontWeight.w700)),
                            const SizedBox(height: 10),
                            for (final line in rel.whatsNew) _bullet(line),
                            const SizedBox(height: 10),
                          ],
                          _infoRow(forced),
                          const SizedBox(height: 18),
                          _primaryButton(),
                          if (!forced) ...[
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: TextButton(
                                onPressed: () => Navigator.of(context).pop(),
                                style: TextButton.styleFrom(
                                  foregroundColor: AppTheme.textSecondary,
                                  padding: const EdgeInsets.symmetric(vertical: 13),
                                ),
                                child: Text('Maybe later',
                                    style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600)),
                              ),
                            ),
                          ],
                        ]),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(AppRelease rel, bool forced) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 26, 22, 22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.primaryBlue.withOpacity(0.55),
            AppTheme.accentPurple.withOpacity(0.35),
            AppTheme.bgCard,
          ],
        ),
      ),
      child: Stack(clipBehavior: Clip.none, children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(colors: [AppTheme.accentCyan, AppTheme.primaryBlue]),
              boxShadow: [BoxShadow(color: AppTheme.accentCyan.withOpacity(0.45), blurRadius: 22)],
            ),
            child: const Icon(Icons.rocket_launch_rounded, color: Colors.white, size: 28),
          ),
          const SizedBox(height: 16),
          Text(rel.title,
              style: GoogleFonts.spaceGrotesk(
                  color: Colors.white, fontSize: 21, fontWeight: FontWeight.w800, height: 1.2)),
          const SizedBox(height: 12),
          Row(children: [
            _chip(widget.currentVersion, AppTheme.textSecondary),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Icon(Icons.arrow_forward_rounded, color: AppTheme.accentCyan, size: 18),
            ),
            _chip(rel.version, AppTheme.accentCyan, filled: true),
            const Spacer(),
            if (forced)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppTheme.warning.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppTheme.warning.withOpacity(0.5)),
                ),
                child: Text('REQUIRED',
                    style: GoogleFonts.inter(
                        color: AppTheme.warning, fontSize: 10.5, fontWeight: FontWeight.w800, letterSpacing: 1)),
              ),
          ]),
        ]),
        if (!forced)
          Positioned(
            right: -10,
            top: -12,
            child: IconButton(
              tooltip: 'Close',
              onPressed: () => Navigator.of(context).pop(),
              icon: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.25),
                  shape: BoxShape.circle,
                  border: Border.all(color: AppTheme.glassBorder),
                ),
                child: const Icon(Icons.close_rounded, color: Colors.white, size: 18),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _chip(String text, Color color, {bool filled = false}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        decoration: BoxDecoration(
          color: filled ? color.withOpacity(0.16) : Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(filled ? 0.6 : 0.25)),
        ),
        child: Text('v$text',
            style: GoogleFonts.spaceGrotesk(color: color, fontWeight: FontWeight.w700, fontSize: 12.5)),
      );

  Widget _bullet(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            margin: const EdgeInsets.only(top: 2),
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: AppTheme.success.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_rounded, color: AppTheme.success, size: 13),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: GoogleFonts.inter(color: Colors.white, fontSize: 13.5, height: 1.4)),
          ),
        ]),
      );

  Widget _infoRow(bool forced) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: (forced ? AppTheme.warning : AppTheme.accentCyan).withOpacity(0.08),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(children: [
          Icon(forced ? Icons.shield_rounded : Icons.verified_rounded,
              color: forced ? AppTheme.warning : AppTheme.accentCyan, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              forced
                  ? 'This update contains important fixes. Please update to keep using NOVA X.'
                  : 'Free update from Google Play · your data, bookmarks and settings stay as they are.',
              style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 12, height: 1.35),
            ),
          ),
        ]),
      );

  Widget _primaryButton() => SizedBox(
        width: double.infinity,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(colors: [AppTheme.accentCyan, AppTheme.primaryBlue]),
            boxShadow: [BoxShadow(color: AppTheme.primaryBlue.withOpacity(0.4), blurRadius: 18, offset: const Offset(0, 6))],
          ),
          child: ElevatedButton.icon(
            onPressed: _opening ? null : _update,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              disabledBackgroundColor: Colors.transparent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            icon: _opening
                ? const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.system_update_rounded, size: 20),
            label: Text('Update now',
                style: GoogleFonts.spaceGrotesk(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white)),
          ),
        ),
      );
}
