// test/auth/password_reset_test.dart
//
// Forgot password: the new-password rules (same as the server's
// password_reset.php), the strength meter, code/email helpers and the
// parsing of the server's answers.

import 'package:flutter_test/flutter_test.dart';
import 'package:nova_x/core/services/api_service.dart';
import 'package:nova_x/features/auth/services/password_rules.dart';

void main() {
  group('PasswordRules.problem (same rules as the server)', () {
    test('accepts good passwords', () {
      for (final p in ['abcdefg1', 'Ɛkuɔ12345', 'Pässwörd9', '密码密码密码密码1', '${'a' * 127}1']) {
        expect(PasswordRules.problem(p), isNull, reason: p);
      }
    });

    test('explains what is missing', () {
      expect(PasswordRules.problem(''), 'Please enter a new password.');
      expect(PasswordRules.problem('abc1'), 'Use at least 8 characters.');
      expect(PasswordRules.problem('${'a' * 128}1'), 'Use at most 128 characters.');
      expect(PasswordRules.problem('abcdefgh'), 'Add at least one number.');
      expect(PasswordRules.problem('12345678'), 'Add at least one letter.');
      expect(PasswordRules.problem(' abcdefg1'), 'The password cannot start or end with a space.');
    });

    test('length counts characters, not bytes', () {
      expect(PasswordRules.problem('😀😀😀😀😀😀a1'), isNull);
    });

    test('checklist', () {
      final checks = PasswordRules.checks('abc');
      expect(checks.map((c) => c.passed).toList(), [false, true, false]);
      expect(PasswordRules.checks('abcdefg1').every((c) => c.passed), isTrue);
    });
  });

  group('strength meter', () {
    test('levels', () {
      expect(PasswordRules.strength(''), PasswordStrength.empty);
      expect(PasswordRules.strength('abc'), PasswordStrength.weak);
      expect(PasswordRules.strength('abcdefg1'), PasswordStrength.fair);
      expect(PasswordRules.strength('Abcdefgh1234'), PasswordStrength.good);
      expect(PasswordRules.strength('Abcdefgh1234!'), PasswordStrength.strong);
    });

    test('common patterns are never strong', () {
      expect(PasswordRules.strength('Password1234!'), PasswordStrength.fair);
      expect(PasswordRules.strength('aaaaaaaaaaaa1!B'), PasswordStrength.fair);
    });
  });

  group('helpers', () {
    test('codes: digits only, at most 6', () {
      expect(PasswordRules.normalizeCode('Code: 123 456'), '123456');
      expect(PasswordRules.normalizeCode('1234567'), '123456');
      expect(PasswordRules.normalizeCode('abc'), '');
    });

    test('emails', () {
      expect(PasswordRules.isValidEmail(' kobby@example.com '), isTrue);
      expect(PasswordRules.isValidEmail('kobby@example'), isFalse);
      expect(PasswordRules.isValidEmail('no at.com'), isFalse);
      expect(PasswordRules.maskEmail('kobby@example.com'), 'ko•••@example.com');
      expect(PasswordRules.maskEmail('ab@x.io'), 'a•••@x.io');
    });

    test('clock', () {
      expect(PasswordRules.clock(65), '1:05');
      expect(PasswordRules.clock(9), '0:09');
      expect(PasswordRules.clock(-3), '0:00');
    });
  });

  group('server answers', () {
    test('code sent', () {
      final r = PasswordResetResult.fromJson(true, 200, {
        'status': 'success',
        'message': 'If an account exists…',
        'resend_after': 60,
        'expires_in': 900,
      });
      expect(r.ok, isTrue);
      expect(r.resendAfter, 60);
      expect(r.expiresIn, 900);
      expect(r.expired, isFalse);
    });

    test('wrong code, expired, too many requests', () {
      final wrong = PasswordResetResult.fromJson(false, 400, {'status': 'invalid_code', 'attempts_left': 3, 'message': 'x'});
      expect(wrong.attemptsLeft, 3);
      expect(wrong.expired, isFalse);
      expect(PasswordResetResult.fromJson(false, 410, {'status': 'expired', 'message': 'x'}).expired, isTrue);
      final limited = PasswordResetResult.fromJson(false, 429, {'status': 'error', 'retry_after': '42', 'message': 'x'});
      expect(limited.rateLimited, isTrue);
      expect(limited.retryAfter, 42);
    });

    test('reset token', () {
      final r = PasswordResetResult.fromJson(true, 200, {'status': 'success', 'reset_token': 'a' * 64});
      expect(r.resetToken, 'a' * 64);
    });
  });
}
