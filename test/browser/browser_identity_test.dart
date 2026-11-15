// test/browser/browser_identity_test.dart (3.13.2)
//
// NOVA X sends Chrome's user agent (no "; wv" web-view marker), so sites
// such as Google sign-in treat it as a browser.

import 'package:flutter_test/flutter_test.dart';
import 'package:nova_x/features/auth/services/google_web_signin.dart';
import 'package:nova_x/features/browser/browser_identity.dart';

void main() {
  test('web-view markers are removed', () {
    const wv = 'Mozilla/5.0 (Linux; Android 14; Pixel 8; wv) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Version/4.0 Chrome/130.0.6723.102 Mobile Safari/537.36';
    expect(
      BrowserIdentity.clean(wv),
      'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/130.0.6723.102 Mobile Safari/537.36',
    );
  });

  test('a Chrome user agent is left as it is', () {
    const chrome = 'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36';
    expect(BrowserIdentity.clean(chrome), chrome);
    expect(BrowserIdentity.clean(''), '');
  });

  test('Google sign-in page has the email filled in', () {
    final u = Uri.parse(GoogleWebSignIn.signInUrl('ama@gmail.com'));
    expect(u.host, 'accounts.google.com');
    expect(u.path, '/ServiceLogin');
    expect(u.queryParameters['Email'], 'ama@gmail.com');
    expect(u.queryParameters['continue'], 'https://www.google.com/');
  });

  test('Gmail addresses are Google accounts', () {
    expect(GoogleWebSignIn.isGoogleEmail('A@GMAIL.com'), isTrue);
    expect(GoogleWebSignIn.isGoogleEmail('x@googlemail.com'), isTrue);
    expect(GoogleWebSignIn.isGoogleEmail('x@yahoo.com'), isFalse);
  });
}
