// lib/features/browser/browser_identity.dart
//
// 3.13.2: how NOVA X introduces itself to websites.
//
// Android's WebView marks itself as an "embedded web view" in two ways: a
// "; wv" token (plus "Version/4.0") in the user agent, and an
// X-Requested-With header carrying the app's package name. Some sites —
// Google sign-in in particular — treat that as "an app showing a web page"
// instead of a browser and refuse to sign in. A browser isn't an embedded
// web view, so NOVA X sends the same user agent Chrome on the phone would
// and no X-Requested-With header (browser_view.dart sets
// requestedWithHeaderOriginAllowList to an empty set). Pure string work is
// in [clean] so it is unit-tested (test/browser/browser_identity_test.dart).

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class BrowserIdentity {
  BrowserIdentity._();

  static String _mobile = '';
  static Future<void>? _loading;

  /// The phone's Chrome-style mobile user agent, or '' until [init] finished
  /// ('' makes the WebView use its default).
  static String get mobile => _mobile;

  /// Reads the WebView's own user agent once and cleans it.
  static Future<void> init() => _loading ??= () async {
        try {
          _mobile = clean(await InAppWebViewController.getDefaultUserAgent());
        } catch (_) {
          _mobile = '';
        }
      }();

  /// "Mozilla/5.0 (Linux; Android 14; Pixel 8; wv) AppleWebKit/537.36 (KHTML,
  /// like Gecko) Version/4.0 Chrome/130.0.0.0 Mobile Safari/537.36"
  /// → "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML,
  /// like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36"
  static String clean(String ua) {
    var s = ua.trim();
    if (s.isEmpty) return '';
    s = s.replaceAll(RegExp(r';\s*wv(?=\))'), '');
    s = s.replaceAll(RegExp(r'\s*;\s*wv\s*;'), ';');
    s = s.replaceAll(RegExp(r'Version/\d+(\.\d+)*\s+(?=Chrome/)'), '');
    s = s.replaceAll(RegExp(r'\s{2,}'), ' ');
    return s;
  }
}
