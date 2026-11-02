// test/auth/auth_lock_test.dart
//
// 3.11.5: the login / password-reset lock countdown kept on the phone.

import 'package:flutter_test/flutter_test.dart';
import 'package:nova_x/features/auth/services/auth_lock.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('countdown text', () {
    expect(AuthLock.clock(299), '4:59');
    expect(AuthLock.clock(600), '10:00');
    expect(AuthLock.clock(3725), '1:02:05');
    expect(AuthLock.clock(-3), '0:00');
  });

  test('a saved lock is per scope and per email (case-insensitive) and ends', () async {
    await AuthLock.save(AuthLock.login, 'Kobby@Mail.com', 300);
    final until = await AuthLock.until(AuthLock.login, ' kobby@mail.com ');
    expect(until, isNotNull);
    expect(AuthLock.secondsLeft(until), inInclusiveRange(299, 300));
    expect(await AuthLock.until(AuthLock.forgot, 'kobby@mail.com'), isNull);
    expect(await AuthLock.until(AuthLock.login, 'other@mail.com'), isNull);
    await AuthLock.clear(AuthLock.login, 'kobby@mail.com');
    expect(await AuthLock.until(AuthLock.login, 'kobby@mail.com'), isNull);
  });

  test('an expired lock is forgotten', () async {
    await AuthLock.save(AuthLock.forgot, 'a@b.co', -1);
    expect(await AuthLock.until(AuthLock.forgot, 'a@b.co'), isNull);
    expect(AuthLock.secondsLeft(null), 0);
  });
}
