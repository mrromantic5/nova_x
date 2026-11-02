// lib/features/auth/services/auth_lock.dart
//
// 3.11.5: remembers on the phone when the server locked an email (too many
// wrong passwords, or too many password-reset codes), so the countdown keeps
// running after the screen or the app is closed. The server is what really
// enforces the lock; this only keeps the screen honest.

import 'package:shared_preferences/shared_preferences.dart';

class AuthLock {
  AuthLock._();

  static const login = 'login';
  static const forgot = 'forgot';

  static String _key(String scope, String email) => 'nx_lock_${scope}_${email.trim().toLowerCase()}';

  /// When the lock ends, or null when [email] isn't locked.
  static Future<DateTime?> until(String scope, String email) async {
    if (email.trim().isEmpty) return null;
    try {
      final p = await SharedPreferences.getInstance();
      final ms = p.getInt(_key(scope, email));
      if (ms == null) return null;
      final t = DateTime.fromMillisecondsSinceEpoch(ms);
      if (!t.isAfter(DateTime.now())) {
        await p.remove(_key(scope, email));
        return null;
      }
      return t;
    } catch (_) {
      return null;
    }
  }

  static Future<DateTime> save(String scope, String email, int seconds) async {
    final t = DateTime.now().add(Duration(seconds: seconds));
    try {
      (await SharedPreferences.getInstance()).setInt(_key(scope, email), t.millisecondsSinceEpoch);
    } catch (_) {}
    return t;
  }

  static Future<void> clear(String scope, String email) async {
    try {
      (await SharedPreferences.getInstance()).remove(_key(scope, email));
    } catch (_) {}
  }

  /// Whole seconds left until [t] (0 when past or null).
  static int secondsLeft(DateTime? t) {
    if (t == null) return 0;
    final ms = t.difference(DateTime.now()).inMilliseconds;
    return ms <= 0 ? 0 : (ms / 1000).ceil();
  }

  /// "4:59", or "1:05:00" for an hour or more.
  static String clock(int seconds) {
    final s = seconds < 0 ? 0 : seconds;
    final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
    final mm = h > 0 ? m.toString().padLeft(2, '0') : '$m';
    return '${h > 0 ? '$h:' : ''}$mm:${sec.toString().padLeft(2, '0')}';
  }
}
