// lib/features/password/password_prompts.dart
//
// 3.12.3: NOVA X Password Manager prompts in the browser.
//   • "Use saved password?" — the account for this site, Sign in / Fill only.
//     The fingerprint / face / screen lock is asked for before anything is
//     filled (BiometricService.confirm in the browser).
//   • "Save password?" / "Update password?" — after a login form is sent,
//     with "Never for this site".

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_theme.dart';

const _sheet = Color(0xFF14171F);
const _card = Color(0xFF1E222C);
const _primary = Color(0xFFA8C7FA);
const _onPrimary = Color(0xFF062E6F);

/// What the user chose on the "Use saved password?" sheet.
enum UsePasswordChoice { signIn, fillOnly }

/// What the user chose on the "Save password?" sheet.
enum SavePasswordChoice { save, never }

Color _siteColor(String domain) {
  const colors = [Color(0xFF29B6F6), Color(0xFF66BB6A), Color(0xFFFFA726), Color(0xFFAB47BC), Color(0xFFEF5350), Color(0xFF26A69A), Color(0xFF5C6BC0)];
  var h = 0;
  for (final c in domain.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return colors[h % colors.length];
}

String _initial(String domain) {
  final d = domain.replaceFirst(RegExp(r'^www\.'), '');
  return d.isEmpty ? '?' : d[0].toUpperCase();
}

Widget _handle() => Container(
      width: 40,
      height: 4,
      margin: const EdgeInsets.only(bottom: 22),
      decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
    );

Widget _accountCard({required String domain, required String username, required Widget password}) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
    decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(20)),
    child: Row(children: [
      CircleAvatar(
        radius: 20,
        backgroundColor: _siteColor(domain),
        child: Text(_initial(domain), style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17)),
      ),
      const SizedBox(width: 16),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(username.isEmpty ? '(no username)' : username,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(color: Colors.white, fontSize: 15.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          password,
        ]),
      ),
    ]),
  );
}

Widget _dots(int n) => Text('•' * n.clamp(8, 12),
    style: GoogleFonts.inter(color: Colors.white70, fontSize: 15, letterSpacing: 1.5, height: 1));

Widget _primaryButton(String label, VoidCallback onTap, {IconData? icon}) => SizedBox(
      width: double.infinity,
      height: 54,
      child: FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(backgroundColor: _primary, foregroundColor: _onPrimary, shape: const StadiumBorder()),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 19), const SizedBox(width: 8)],
          Text(label, style: GoogleFonts.inter(fontSize: 15.5, fontWeight: FontWeight.w700)),
        ]),
      ),
    );

/// "Use saved password?" — returns the choice, or null when dismissed.
Future<UsePasswordChoice?> showUseSavedPasswordSheet(
  BuildContext context, {
  required String domain,
  required String username,
  required int passwordLength,
}) {
  HapticFeedback.selectionClick();
  return showModalBottomSheet<UsePasswordChoice>(
    context: context,
    backgroundColor: _sheet,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (ctx) => SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 12, 22, 18),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _handle(),
          Text('Use saved password?', style: GoogleFonts.inter(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text('You’ll sign in to $domain',
              textAlign: TextAlign.center, style: GoogleFonts.inter(color: Colors.white70, fontSize: 13.5, fontWeight: FontWeight.w500)),
          const SizedBox(height: 22),
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => Navigator.pop(ctx, UsePasswordChoice.fillOnly),
              child: _accountCard(domain: domain, username: username, password: _dots(passwordLength)),
            ),
          ),
          const SizedBox(height: 22),
          _primaryButton('Sign in', () => Navigator.pop(ctx, UsePasswordChoice.signIn)),
          const SizedBox(height: 4),
          TextButton(
            onPressed: () => Navigator.pop(ctx, UsePasswordChoice.fillOnly),
            child: Text('Fill only', style: GoogleFonts.inter(color: _primary, fontSize: 14, fontWeight: FontWeight.w600)),
          ),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.fingerprint_rounded, color: AppTheme.textHint, size: 15),
            const SizedBox(width: 6),
            Flexible(
              child: Text('You’ll confirm it’s you with your fingerprint, face or screen lock.',
                  textAlign: TextAlign.center, style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 11.5)),
            ),
          ]),
        ]),
      ),
    ),
  );
}

/// "Save password?" / "Update password?" — returns the choice, or null for
/// "Not now" / dismissed.
Future<SavePasswordChoice?> showSavePasswordSheet(
  BuildContext context, {
  required String domain,
  required String username,
  required String password,
  bool update = false,
}) {
  HapticFeedback.selectionClick();
  return showModalBottomSheet<SavePasswordChoice>(
    context: context,
    backgroundColor: _sheet,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (ctx) => SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 12, 22, 18),
        child: _SaveBody(domain: domain, username: username, password: password, update: update),
      ),
    ),
  );
}

class _SaveBody extends StatefulWidget {
  const _SaveBody({required this.domain, required this.username, required this.password, required this.update});
  final String domain, username, password;
  final bool update;

  @override
  State<_SaveBody> createState() => _SaveBodyState();
}

class _SaveBodyState extends State<_SaveBody> {
  bool _show = false;

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      _handle(),
      Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(color: _primary.withOpacity(0.14), shape: BoxShape.circle),
        child: const Icon(Icons.key_rounded, color: _primary, size: 26),
      ),
      const SizedBox(height: 14),
      Text(widget.update ? 'Update password?' : 'Save password?',
          style: GoogleFonts.inter(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      Text(
        widget.update
            ? 'NOVA X will use the new password next time you sign in to ${widget.domain}'
            : 'Sign in to ${widget.domain} faster next time. Saved encrypted on this phone.',
        textAlign: TextAlign.center,
        style: GoogleFonts.inter(color: Colors.white70, fontSize: 13.5, height: 1.4),
      ),
      const SizedBox(height: 22),
      _accountCard(
        domain: widget.domain,
        username: widget.username,
        password: Row(children: [
          Expanded(
            child: _show
                ? Text(widget.password,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.robotoMono(color: Colors.white70, fontSize: 14))
                : _dots(widget.password.length),
          ),
          InkWell(
            onTap: () => setState(() => _show = !_show),
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(_show ? Icons.visibility_off_rounded : Icons.visibility_rounded, color: Colors.white54, size: 20),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 22),
      _primaryButton(widget.update ? 'Update' : 'Save', () => Navigator.pop(context, SavePasswordChoice.save)),
      const SizedBox(height: 6),
      Row(children: [
        Expanded(
          child: TextButton(
            onPressed: () => Navigator.pop(context, SavePasswordChoice.never),
            child: Text('Never for this site', style: GoogleFonts.inter(color: Colors.white70, fontSize: 13.5, fontWeight: FontWeight.w600)),
          ),
        ),
        Expanded(
          child: TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Not now', style: GoogleFonts.inter(color: _primary, fontSize: 13.5, fontWeight: FontWeight.w600)),
          ),
        ),
      ]),
    ]);
  }
}
