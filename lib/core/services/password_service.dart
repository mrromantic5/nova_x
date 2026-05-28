// lib/core/services/password_service.dart
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
// Use 'as fss' prefix to avoid AndroidOptions name conflict with flutter_inappwebview
import 'package:flutter_secure_storage/flutter_secure_storage.dart' as fss;
import 'dart:convert';

class PasswordService {
  // Prefix all calls with fss. to avoid AndroidOptions ambiguity
  static const _storage = fss.FlutterSecureStorage(
    aOptions: fss.AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _prefix = 'novax_pw_';

  // ── Save credentials ────────────────────────────────────────────────────────
  static Future<void> saveCredentials(
      String domain, String username, String password) async {
    final key   = _prefix + _sanitizeDomain(domain);
    final value = jsonEncode({'username': username, 'password': password});
    await _storage.write(key: key, value: value);
  }

  // ── Get credentials for domain ──────────────────────────────────────────────
  static Future<Map<String, String>?> getCredentials(String domain) async {
    try {
      final key = _prefix + _sanitizeDomain(domain);
      final raw = await _storage.read(key: key);
      if (raw == null) return null;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return {
        'username': map['username']?.toString() ?? '',
        'password': map['password']?.toString() ?? '',
      };
    } catch (_) {
      return null;
    }
  }

  // ── List all saved passwords ─────────────────────────────────────────────────
  static Future<List<Map<String, String>>> getAllCredentials() async {
    try {
      final all    = await _storage.readAll();
      final result = <Map<String, String>>[];
      for (final entry in all.entries) {
        if (!entry.key.startsWith(_prefix)) continue;
        try {
          final domain = entry.key.substring(_prefix.length);
          final map    = jsonDecode(entry.value) as Map<String, dynamic>;
          result.add({
            'domain':   domain,
            'username': map['username']?.toString() ?? '',
            'password': map['password']?.toString() ?? '',
          });
        } catch (_) {}
      }
      result.sort((a, b) => a['domain']!.compareTo(b['domain']!));
      return result;
    } catch (_) {
      return [];
    }
  }

  // ── Delete one domain ────────────────────────────────────────────────────────
  static Future<void> deleteCredentials(String domain) async =>
      _storage.delete(key: _prefix + _sanitizeDomain(domain));

  // ── Delete all ───────────────────────────────────────────────────────────────
  static Future<void> deleteAllCredentials() async {
    final all = await _storage.readAll();
    for (final key in all.keys) {
      if (key.startsWith(_prefix)) await _storage.delete(key: key);
    }
  }

  static String _sanitizeDomain(String domain) =>
      domain.replaceAll(RegExp(r'[^a-zA-Z0-9\.\-]'), '_');

  // ── JS: detect password form submission ─────────────────────────────────────
  static const String pwDetectJS = r'''
(function() {
  if (window.__novax_pw_hooked) return;
  window.__novax_pw_hooked = true;
  document.addEventListener('submit', function(e) {
    try {
      var form = e.target || e.srcElement;
      if (!form) return;
      var pwInput = form.querySelector('input[type="password"]');
      if (!pwInput || !pwInput.value) return;
      var userInput = form.querySelector(
        'input[type="email"], input[name*="user" i], input[name*="email" i], input[name*="login" i], input[type="text"]:not([type="password"])'
      );
      window.flutter_inappwebview.callHandler('novaxPwDetect', {
        username: userInput ? userInput.value : '',
        password: pwInput.value,
        domain: window.location.hostname
      });
    } catch(e) {}
  }, true);
})();
''';

  // ── JS: autofill fields ──────────────────────────────────────────────────────
  static String autofillJS(String username, String password) {
    final safeU = username.replaceAll("'", "\\'").replaceAll('`', '\\`');
    final safeP = password.replaceAll("'", "\\'").replaceAll('`', '\\`');
    return """
(function() {
  var filled = false;
  var inputs = document.querySelectorAll('input');
  for (var i = 0; i < inputs.length; i++) {
    var inp  = inputs[i];
    var name = (inp.name || inp.id || inp.placeholder || '').toLowerCase();
    if (!filled && (inp.type === 'email' ||
        name.includes('user') || name.includes('email') ||
        name.includes('login') || name.includes('account'))) {
      inp.value = '$safeU';
      inp.dispatchEvent(new Event('input',  {bubbles: true}));
      inp.dispatchEvent(new Event('change', {bubbles: true}));
      filled = true;
    }
    if (inp.type === 'password') {
      inp.value = '$safeP';
      inp.dispatchEvent(new Event('input',  {bubbles: true}));
      inp.dispatchEvent(new Event('change', {bubbles: true}));
    }
  }
})();
""";
  }

  // ── Ad blocker: 60+ domains using VALID flutter_inappwebview 6.x enum values ─
  // Valid ContentBlockerTriggerResourceType values in v6:
  //   SCRIPT, IMAGE, STYLE_SHEET, RAW (covers XHR/fetch), MEDIA, FONT,
  //   SVG_DOCUMENT, POPUP, DOCUMENT
  // NOT valid in v6: FETCH, XMLHTTPREQUEST, OTHER (those don't exist)
  static List<ContentBlocker> buildAdBlockers() {
    const patterns = [
      // Google advertising
      'doubleclick\\.net',
      'googlesyndication\\.com',
      'googleadservices\\.com',
      'adservice\\.google\\.com',
      'pagead2\\.googlesyndication\\.com',
      // Analytics / tag managers
      'google-analytics\\.com',
      'analytics\\.google\\.com',
      'googletagmanager\\.com',
      'googletagservices\\.com',
      // Major ad networks
      'adnxs\\.com',
      'advertising\\.com',
      'amazon-adsystem\\.com',
      'ads\\.yahoo\\.com',
      'pubmatic\\.com',
      'openx\\.net',
      'rubiconproject\\.com',
      'criteo\\.com',
      'criteo\\.net',
      'taboola\\.com',
      'outbrain\\.com',
      'media\\.net',
      // Trackers
      'scorecardresearch\\.com',
      'quantserve\\.com',
      'comscore\\.com',
      'demdex\\.net',
      'exelator\\.com',
      'krxd\\.net',
      'bluekai\\.com',
      'doubleverify\\.com',
      'integral-active\\.com',
      // Programmatic
      'indexww\\.com',
      'casalemedia\\.com',
      'contextweb\\.com',
      'cxense\\.com',
      'bidswitch\\.net',
      'adform\\.net',
      'adsrvr\\.org',
      'adtech\\.de',
      'lkqd\\.net',
      'moatads\\.com',
      'rfihub\\.com',
      'nexac\\.com',
      'sharethrough\\.com',
      'sovrn\\.com',
      'lijit\\.com',
      'triplelift\\.com',
      'undertone\\.com',
      'vertamedia\\.com',
      'teads\\.tv',
      'zedo\\.com',
      'stickyads\\.tv',
      // Social trackers
      'connect\\.facebook\\.net',
      'snap\\.licdn\\.com',
      'ads\\.linkedin\\.com',
      // Mobile ad SDKs
      'adcolony\\.com',
      'mopub\\.com',
      'applovin\\.com',
      'inmobi\\.com',
      'appnexus\\.com',
      // Misc
      'trustarc\\.com',
      'tremorhub\\.com',
      'onetag\\.net',
      'spotxchange\\.com',
      'smartadserver\\.com',
    ];

    return patterns.map((pattern) => ContentBlocker(
      trigger: ContentBlockerTrigger(
        urlFilter: pattern,
        // Only use resource types that EXIST in flutter_inappwebview 6.x
        resourceType: [
          ContentBlockerTriggerResourceType.SCRIPT,
          ContentBlockerTriggerResourceType.IMAGE,
          ContentBlockerTriggerResourceType.STYLE_SHEET,
          ContentBlockerTriggerResourceType.RAW,    // covers XHR + fetch
          ContentBlockerTriggerResourceType.MEDIA,
          ContentBlockerTriggerResourceType.FONT,
        ],
      ),
      action: ContentBlockerAction(
        type: ContentBlockerActionType.BLOCK,
      ),
    )).toList();
  }
}
