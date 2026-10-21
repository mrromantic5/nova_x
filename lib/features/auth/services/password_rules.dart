// lib/features/auth/services/password_rules.dart
//
// Rules for a new password (the same rules the NOVA X server checks in
// password_reset.php), a strength score for the meter, and small helpers for
// the reset-code and email fields. Pure Dart — unit-tested.

class PasswordCheck {
  const PasswordCheck(this.label, this.passed);
  final String label;
  final bool passed;
}

enum PasswordStrength { empty, weak, fair, good, strong }

class PasswordRules {
  PasswordRules._();

  static const int minLength = 8;
  static const int maxLength = 128;

  static final RegExp _letter = RegExp(r'\p{L}', unicode: true);
  static final RegExp _digit = RegExp(r'\d');
  static final RegExp _upper = RegExp(r'\p{Lu}', unicode: true);
  static final RegExp _lower = RegExp(r'\p{Ll}', unicode: true);
  static final RegExp _symbol = RegExp(r'[^\p{L}\d\s]', unicode: true);
  static final RegExp _email = RegExp(r"^[^\s@]+@[^\s@]+\.[^\s@]{2,}$");

  /// Number of characters as the server counts them (Unicode code points).
  static int length(String password) => password.runes.length;

  /// The checklist shown under the password field.
  static List<PasswordCheck> checks(String password) => [
        PasswordCheck('At least $minLength characters', length(password) >= minLength),
        PasswordCheck('A letter', _letter.hasMatch(password)),
        PasswordCheck('A number', _digit.hasMatch(password)),
      ];

  /// Why [password] can't be used, or null when it is fine.
  static String? problem(String password) {
    if (password.isEmpty) return 'Please enter a new password.';
    final len = length(password);
    if (len < minLength) return 'Use at least $minLength characters.';
    if (len > maxLength) return 'Use at most $maxLength characters.';
    if (!_letter.hasMatch(password)) return 'Add at least one letter.';
    if (!_digit.hasMatch(password)) return 'Add at least one number.';
    if (password.trim() != password) return 'The password cannot start or end with a space.';
    return null;
  }

  static PasswordStrength strength(String password) {
    if (password.isEmpty) return PasswordStrength.empty;
    if (problem(password) != null) return PasswordStrength.weak;
    var score = 0;
    final len = length(password);
    if (len >= 12) score++;
    if (len >= 16) score++;
    if (_upper.hasMatch(password) && _lower.hasMatch(password)) score++;
    if (_symbol.hasMatch(password)) score++;
    if (_common(password)) return PasswordStrength.fair;
    if (score >= 3) return PasswordStrength.strong;
    if (score >= 1) return PasswordStrength.good;
    return PasswordStrength.fair;
  }

  /// Obvious patterns that are easy to guess even when long enough.
  static bool _common(String password) {
    final p = password.toLowerCase();
    const weak = ['password', '12345678', 'qwerty', 'novax', 'nova123', 'abc123', 'iloveyou', 'letmein'];
    if (weak.any(p.contains)) return true;
    // One character repeated, e.g. "aaaaaaa1".
    return RegExp(r'^(.)\1{5,}').hasMatch(p);
  }

  static String strengthLabel(PasswordStrength s) => switch (s) {
        PasswordStrength.empty => '',
        PasswordStrength.weak => 'Too weak',
        PasswordStrength.fair => 'Fair',
        PasswordStrength.good => 'Good',
        PasswordStrength.strong => 'Strong',
      };

  /// Digits only, at most 6 (pasted text such as "Code: 123 456" works).
  static String normalizeCode(String input) {
    final digits = input.replaceAll(RegExp(r'\D'), '');
    return digits.length > 6 ? digits.substring(0, 6) : digits;
  }

  static bool isValidEmail(String email) {
    final e = email.trim();
    return e.length <= 255 && _email.hasMatch(e);
  }

  /// "kobby@example.com" → "ko•••@example.com" (shown on the code step).
  static String maskEmail(String email) {
    final e = email.trim();
    final at = e.indexOf('@');
    if (at <= 0) return e;
    final name = e.substring(0, at);
    final keep = name.length <= 2 ? 1 : 2;
    return '${name.substring(0, keep)}•••${e.substring(at)}';
  }

  /// "1:05" / "0:42" for countdowns.
  static String clock(int seconds) {
    final s = seconds < 0 ? 0 : seconds;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }
}
