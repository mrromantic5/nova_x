// lib/features/auth/services/google_web_signin.dart
//
// 3.13.2: signing the NOVA X browser in to Google after a NOVA X sign-up or
// log-in.
//
// Chrome can sign the web in to Google silently because it is part of
// Android's Google account system; no other app is allowed to turn an app
// sign-in into a google.com session. So NOVA X does the next best thing:
// right after the account is ready it offers to open Google's own sign-in
// page in a NOVA X tab with the email already filled in. The user confirms
// once and is then signed in to Google, Gmail, YouTube and Drive in NOVA X
// (the cookies stay, like in any browser).

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nova_x/core/theme/app_theme.dart';

import '../../browser/screens/browser_view.dart';

class GoogleWebSignIn {
  GoogleWebSignIn._();

  static const String _kPending = 'nx_google_web_pending';
  static const String _kDone = 'nx_google_web_done';

  /// True for addresses that are Google accounts whatever happens (Gmail).
  static bool isGoogleEmail(String email) {
    final e = email.trim().toLowerCase();
    return e.endsWith('@gmail.com') || e.endsWith('@googlemail.com');
  }

  /// Google's sign-in page with [email] filled in; afterwards it lands on
  /// google.com in the same tab.
  static String signInUrl(String email) {
    final q = <String, String>{
      'continue': 'https://www.google.com/',
      'hl': 'en',
      if (email.trim().isNotEmpty) 'Email': email.trim(),
    };
    return Uri.https('accounts.google.com', '/ServiceLogin', q).toString();
  }

  /// Remembers to offer the browser sign-in when the home screen opens.
  /// Called after Google sign-in, and after email sign-in with a Gmail address.
  static Future<void> offer(String email, {bool fromGoogle = false}) async {
    if (!fromGoogle && !isGoogleEmail(email)) return;
    final p = await SharedPreferences.getInstance();
    final done = p.getStringList(_kDone) ?? const <String>[];
    if (done.contains(email.trim().toLowerCase())) return;
    await p.setString(_kPending, email.trim());
  }

  /// Shows the offer once if one is waiting (home screen, after sign-in).
  static Future<void> showIfPending(BuildContext context) async {
    final p = await SharedPreferences.getInstance();
    final email = p.getString(_kPending);
    if (email == null || email.isEmpty) return;
    await p.remove(_kPending);
    if (!context.mounted) return;
    final go = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppTheme.bgCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 10, 22, 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 18),
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
              alignment: Alignment.center,
              child: const GoogleMark(size: 28),
            ),
            const SizedBox(height: 14),
            Text('Sign in to Google in NOVA X',
                textAlign: TextAlign.center,
                style: GoogleFonts.spaceGrotesk(color: Colors.white, fontSize: 19, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              'Use Gmail, YouTube, Drive and your Google account on websites, signed in as $email.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 13.5, height: 1.4),
            ),
            const SizedBox(height: 6),
            Text(
              'Google will ask you to confirm it\'s you once.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 12),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryBlue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () => Navigator.pop(c, true),
                child: Text('Sign in to Google', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 15)),
              ),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text('Not now', style: GoogleFonts.inter(color: AppTheme.textSecondary)),
            ),
            Text('You can do this later from your profile.',
                style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 11.5)),
          ]),
        ),
      ),
    );
    if (go == true && context.mounted) await open(context, email);
  }

  /// Opens Google's sign-in page in a NOVA X tab.
  static Future<void> open(BuildContext context, String email) async {
    final p = await SharedPreferences.getInstance();
    final key = email.trim().toLowerCase();
    final done = List<String>.from(p.getStringList(_kDone) ?? const <String>[]);
    if (key.isNotEmpty && !done.contains(key)) {
      done.add(key);
      await p.setStringList(_kDone, done);
    }
    if (!context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => BrowserView(initialQuery: signInUrl(email))));
  }
}

/// Google's four-colour "G", drawn (no image asset or network needed).
class GoogleMark extends StatelessWidget {
  const GoogleMark({super.key, this.size = 20});
  final double size;

  @override
  Widget build(BuildContext context) =>
      SizedBox(width: size, height: size, child: CustomPaint(painter: _GooglePainter()));
}

class _GooglePainter extends CustomPainter {
  static const _blue = Color(0xFF4285F4);
  static const _green = Color(0xFF34A853);
  static const _yellow = Color(0xFFFBBC05);
  static const _red = Color(0xFFEA4335);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final stroke = s * 0.2;
    final r = (s - stroke) / 2;
    final c = Offset(s / 2, s / 2);
    final rect = Rect.fromCircle(center: c, radius: r);
    Paint p(Color col) => Paint()
      ..color = col
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;
    const deg = 3.141592653589793 / 180;
    // Angles in Flutter go clockwise from 3 o'clock.
    canvas.drawArc(rect, -40 * deg, -100 * deg, false, p(_red)); // top
    canvas.drawArc(rect, -140 * deg, -85 * deg, false, p(_yellow)); // left
    canvas.drawArc(rect, 135 * deg, -95 * deg, false, p(_green)); // bottom
    canvas.drawArc(rect, 40 * deg, -40 * deg, false, p(_blue)); // lower right
    // The bar of the G.
    final bar = Paint()..color = _blue;
    canvas.drawRect(Rect.fromLTWH(s / 2, s / 2 - stroke / 2, r + stroke / 2, stroke), bar);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
