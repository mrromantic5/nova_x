// lib/core/services/password_service.dart
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
// Use 'as fss' prefix to avoid AndroidOptions name conflict with flutter_inappwebview
import 'package:flutter_secure_storage/flutter_secure_storage.dart' as fss;
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

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

  // ── "Never for this site" (3.12.3) ─────────────────────────────────────────
  static const _neverKey = 'nx_pw_never_sites';

  static Future<bool> isNever(String domain) async {
    try {
      return ((await SharedPreferences.getInstance()).getStringList(_neverKey) ?? const []).contains(domain);
    } catch (_) {
      return false;
    }
  }

  static Future<void> setNever(String domain, bool never) async {
    try {
      final p = await SharedPreferences.getInstance();
      final list = (p.getStringList(_neverKey) ?? <String>[]).where((d) => d != domain).toList();
      if (never) list.add(domain);
      await p.setStringList(_neverKey, list);
    } catch (_) {}
  }

  /// What a submitted login means for the saved password of [domain]:
  /// 'same' (nothing to do), 'update' (same user, new password), 'new'.
  static String compare(Map<String, String>? saved, String username, String password) {
    if (saved == null) return 'new';
    final su = (saved['username'] ?? '').trim(), sp = saved['password'] ?? '';
    // The saved password was used (e.g. NOVA X just filled it): nothing to ask,
    // even if the page's username field was read differently.
    if (sp == password) return 'same';
    if (su.toLowerCase() == username.trim().toLowerCase() || username.trim().isEmpty) return 'update';
    return 'new';
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
      // The username is the text/email/phone field just before the password.
      var all = Array.prototype.slice.call(form.querySelectorAll('input'));
      var userInput = null;
      for (var i = all.indexOf(pwInput) - 1; i >= 0; i--) {
        var t = (all[i].type || 'text').toLowerCase();
        if (['text', 'email', 'tel', 'number'].indexOf(t) >= 0 && all[i].value) { userInput = all[i]; break; }
      }
      if (!userInput) userInput = form.querySelector(
        'input[autocomplete="username"], input[type="email"], input[name*="user" i], input[name*="email" i], input[name*="login" i]'
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

  // ── JS: is there an empty, visible password field to fill? ─────────────────
  static const String hasLoginFieldJS = r"""
(function(){try{
  var f=document.querySelectorAll('input[type=password]');
  for(var i=0;i<f.length;i++){var el=f[i];
    if(el.disabled||el.readOnly||el.value) continue;
    var r=el.getBoundingClientRect(), s=getComputedStyle(el);
    if(r.width>0&&r.height>0&&s.visibility!=='hidden'&&s.display!=='none') return true;}
  return false;
}catch(e){return false;}})();
""";

  // ── JS: autofill fields ──────────────────────────────────────────────────────
  /// Fills the visible login form: the password field and the username/email
  /// field just before it (same form). Values are set through the native
  /// setter so React/Vue/Angular forms notice them. With [submit], the form
  /// is then sent (like "Sign in" in other browsers). Returns a JSON string
  /// {"filled":bool,"user":bool,"submitted":bool}.
  static String autofillJS(String username, String password, {bool submit = false}) {
    // 3.9.1: JSON-encoded, so a quote, backslash or line break in a saved
    // password can never break out of the string and run as page script.
    final safeU = jsonEncode(username);
    final safeP = jsonEncode(password);
    return """
(function() {
  try {
    var U = $safeU, P = $safeP, SUBMIT = ${submit ? 'true' : 'false'};
    function visible(el){var r=el.getBoundingClientRect(),s=getComputedStyle(el);return r.width>0&&r.height>0&&s.visibility!=='hidden'&&s.display!=='none';}
    var setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
    function put(el, v){ el.focus(); setter.call(el, v);
      el.dispatchEvent(new Event('input', {bubbles:true})); el.dispatchEvent(new Event('change', {bubbles:true})); el.blur(); }
    var pws = Array.prototype.filter.call(document.querySelectorAll('input[type=password]'), function(e){return visible(e)&&!e.disabled&&!e.readOnly;});
    if (!pws.length) return JSON.stringify({filled:false,user:false,submitted:false});
    var pw = pws[0];
    var scope = pw.form || document;
    var all = Array.prototype.slice.call(scope.querySelectorAll('input'));
    var idx = all.indexOf(pw), user = null;
    for (var i = idx - 1; i >= 0; i--) {
      var t = (all[i].type || 'text').toLowerCase();
      if (['text','email','tel','number'].indexOf(t) >= 0 && visible(all[i]) && !all[i].disabled && !all[i].readOnly) { user = all[i]; break; }
    }
    if (!user) user = scope.querySelector('input[autocomplete=username],input[type=email],input[name*=user i],input[name*=email i],input[name*=login i],input[id*=user i],input[id*=email i]');
    if (user && U) put(user, U);
    put(pw, P);
    var sent = false;
    if (SUBMIT && pw.form && (user || !U)) {
      var btn = pw.form.querySelector('button[type=submit],input[type=submit],button:not([type])');
      setTimeout(function(){ try { if (btn) btn.click(); else if (pw.form.requestSubmit) pw.form.requestSubmit(); else pw.form.submit(); } catch(e){} }, 250);
      sent = true;
    }
    return JSON.stringify({filled:true,user:!!(user&&U),submitted:sent});
  } catch (e) { return JSON.stringify({filled:false,user:false,submitted:false}); }
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
      // ── Extra networks & trackers (added) ──
      'adroll\\.com',
      'serving-sys\\.com',
      'yieldmo\\.com',
      'gumgum\\.com',
      'districtm\\.io',
      '3lift\\.com',
      'pubnative\\.net',
      'mgid\\.com',
      'revcontent\\.com',
      'propellerads\\.com',
      'popads\\.net',
      'adsterra\\.com',
      'hilltopads\\.com',
      'exoclick\\.com',
      'juicyads\\.com',
      'trafficjunky\\.com',
      'bidvertiser\\.com',
      'chartbeat\\.com',
      'hotjar\\.com',
      'mixpanel\\.com',
      'segment\\.io',
      'amplitude\\.com',
      'fullstory\\.com',
      'mouseflow\\.com',
      'securepubads\\.g\\.doubleclick\\.net',
      'imasdk\\.googleapis\\.com',
      'ad\\.doubleclick\\.net',
      'static\\.doubleclick\\.net',
      'stats\\.g\\.doubleclick\\.net',
      'ssl\\.google-analytics\\.com',
      'pixel\\.facebook\\.com',
      'ads\\.tiktok\\.com',
      'analytics\\.tiktok\\.com',
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

  // ── Cosmetic ad filtering: hide common ad containers (no blank gaps) ────────
  // Injected on page load when the ad blocker is ON. Conservative selectors to
  // avoid breaking real content; pairs with the network-level blockers above.
  static const String adCosmeticJS = '''
(function(){
  try {
    if (document.getElementById('nx-adblock-style')) return;
    var css = [
      '[id^="google_ads_"]','[id^="div-gpt-ad"]','[id^="ad-"]','[id\$="-ad"]',
      'ins.adsbygoogle','.adsbygoogle','.ad-container','.ad-wrapper','.ad-banner',
      '.ad-slot','.ad-unit','.advert','.advertisement','.sponsored-ad',
      '[class^="ad-"]','[class*=" ad-"]','[class\$="-ads"]','[class*="-ads-"]',
      'iframe[src*="doubleclick"]','iframe[src*="googlesyndication"]',
      'iframe[src*="/ads/"]','iframe[id^="google_ads"]',
      '.taboola','.trc_related_container','[id^="taboola"]','[id^="outbrain"]',
      '.OUTBRAIN','#disqus_ad','.adsbox','.banner-ads'
    ].join(',') + '{display:none !important;height:0 !important;min-height:0 !important;}';
    var s = document.createElement('style');
    s.id = 'nx-adblock-style';
    s.type = 'text/css';
    s.appendChild(document.createTextNode(css));
    (document.head || document.documentElement).appendChild(s);
  } catch(e){}
})();
''';
}
