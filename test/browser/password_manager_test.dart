// test/browser/password_manager_test.dart
//
// 3.12.3: after NOVA X fills a saved password, the login must not be offered
// for saving again; a changed password is an update; "Never" is remembered.

import 'package:flutter_test/flutter_test.dart';
import 'package:nova_x/core/services/password_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('the saved (just filled) password is never offered again', () {
    final saved = {'username': 'tlyfecom', 'password': 'S3cret!'};
    expect(PasswordService.compare(saved, 'tlyfecom', 'S3cret!'), 'same');
    expect(PasswordService.compare(saved, 'TLYFECOM', 'S3cret!'), 'same');
    // the page's username field read differently, same password → still the same login
    expect(PasswordService.compare(saved, 'search text', 'S3cret!'), 'same');
  });

  test('a new password for the same user is an update; another user is new', () {
    final saved = {'username': 'tlyfecom', 'password': 'old'};
    expect(PasswordService.compare(saved, 'tlyfecom', 'new'), 'update');
    expect(PasswordService.compare(saved, '', 'new'), 'update');
    expect(PasswordService.compare(saved, 'someone', 'x'), 'new');
    expect(PasswordService.compare(null, 'me', 'x'), 'new');
  });

  test('"Never for this site" is remembered and can be undone', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await PasswordService.isNever('shop.test'), isFalse);
    await PasswordService.setNever('shop.test', true);
    expect(await PasswordService.isNever('shop.test'), isTrue);
    expect(await PasswordService.isNever('other.test'), isFalse);
    await PasswordService.setNever('shop.test', false);
    expect(await PasswordService.isNever('shop.test'), isFalse);
  });

  test('fill script keeps saved values as data', () {
    final js = PasswordService.autofillJS('a"b', 'p\\"</script>', submit: true);
    expect(js, contains(r'"a\"b"'));
    expect(js, contains('SUBMIT = true'));
    expect(PasswordService.autofillJS('u', 'p'), contains('SUBMIT = false'));
  });
}
