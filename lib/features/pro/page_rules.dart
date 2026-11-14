// lib/features/pro/page_rules.dart
//
// Rewrite Rules + Low-Data & Annoyance Mode.
//
//  • Redirect   https://www.reddit.com/*  →  https://old.reddit.com/$1
//  • Block      *://*.doubleclick.net/*   (requests never leave the phone)
//  • Site CSS   example.com  →  .ad, .promo { display:none }
//  • Site JS    example.com  →  your own script (only code you trust)
//  • Low-data   no images / video files / web fonts
//  • Annoyances hides cookie banners, sign-up pop-ups and sticky overlays,
//               stops videos that start playing by themselves
//
// Rules live on this phone (shared_preferences) and apply only inside NOVA
// X's own WebView; incognito tabs use them too (nothing is recorded).
// Android (3.13.0): requests are matched in shouldInterceptRequest (the PC
// uses the engine's blocked-URL list); redirects run before a page loads.
// Android WebView can't add a header to every request, so low-data mode
// blocks the files instead of sending "Save-Data".

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'pro_ui.dart';

enum PageRuleType { redirect, block, css, js }

extension PageRuleTypeX on PageRuleType {
  String get label => switch (this) {
        PageRuleType.redirect => 'Redirect',
        PageRuleType.block => 'Block requests',
        PageRuleType.css => 'Site style (CSS)',
        PageRuleType.js => 'Site script (JS)',
      };
  String get patternHint => switch (this) {
        PageRuleType.redirect => 'https://www.reddit.com/*',
        PageRuleType.block => '*://*.doubleclick.net/*',
        PageRuleType.css || PageRuleType.js => 'example.com  or  *.example.com  or  *',
      };
}

class PageRule {
  PageRule({
    String? id,
    required this.type,
    required this.pattern,
    this.value = '',
    this.enabled = true,
    this.note = '',
  }) : id = id ?? 'r${DateTime.now().microsecondsSinceEpoch}';

  final String id;
  PageRuleType type;
  String pattern;
  String value;
  bool enabled;
  String note;

  Map<String, Object?> toJson() =>
      {'id': id, 'type': type.name, 'pattern': pattern, 'value': value, 'enabled': enabled, 'note': note};

  static PageRule? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final type = PageRuleType.values.where((t) => t.name == raw['type']).firstOrNull;
    final pattern = raw['pattern'];
    if (type == null || pattern is! String || pattern.trim().isEmpty) return null;
    return PageRule(
      id: raw['id'] is String ? raw['id'] as String : null,
      type: type,
      pattern: pattern.trim(),
      value: raw['value'] is String ? raw['value'] as String : '',
      enabled: raw['enabled'] != false,
      note: raw['note'] is String ? raw['note'] as String : '',
    );
  }
}

class PageRules extends ChangeNotifier {
  PageRules._();
  static final PageRules instance = PageRules._();

  static const String _key = 'nova_pro_page_rules_v1';

  bool _loaded = false;
  Future<void>? _loading;

  final List<PageRule> rules = [];
  bool lowData = false;
  bool lowDataImages = true;
  bool lowDataVideo = true;
  bool lowDataFonts = true;
  bool annoyances = false;
  bool stopAutoplay = true;

  Future<void> ensureLoaded() => _loaded ? Future<void>.value() : (_loading ??= _load());

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      decode(p.getString(_key));
    } catch (_) {}
    _loaded = true;
    notifyListeners();
  }

  /// Loads settings from JSON (public for tests and import).
  void decode(String? raw, {bool merge = false}) {
    if (!merge) rules.clear();
    if (raw == null || raw.isEmpty) return;
    try {
      final j = jsonDecode(raw);
      if (j is! Map) return;
      if (!merge) {
        lowData = j['lowData'] == true;
        lowDataImages = j['lowDataImages'] != false;
        lowDataVideo = j['lowDataVideo'] != false;
        lowDataFonts = j['lowDataFonts'] != false;
        annoyances = j['annoyances'] == true;
        stopAutoplay = j['stopAutoplay'] != false;
      }
      final list = j['rules'];
      if (list is List) {
        for (final r in list) {
          final rule = PageRule.fromJson(r);
          if (rule != null && rules.length < 500) rules.add(rule);
        }
      }
    } catch (_) {}
  }

  String encode() => jsonEncode({
        'v': 1,
        'lowData': lowData,
        'lowDataImages': lowDataImages,
        'lowDataVideo': lowDataVideo,
        'lowDataFonts': lowDataFonts,
        'annoyances': annoyances,
        'stopAutoplay': stopAutoplay,
        'rules': [for (final r in rules) r.toJson()],
      });

  Future<void> save() async {
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_key, encode());
    } catch (_) {}
  }

  // ── Matching (pure) ───────────────────────────────────────────────────────

  /// Where [url] should go instead, or null.
  String? redirectFor(String url) {
    if (!url.startsWith('http')) return null;
    for (final r in rules) {
      if (!r.enabled || r.type != PageRuleType.redirect || r.value.trim().isEmpty) continue;
      final to = applyRedirect(r.pattern, r.value.trim(), url);
      if (to != null && to != url && to.startsWith('http')) return to;
    }
    return null;
  }

  /// "https://a.com/*" + "https://b.com/$1" on "https://a.com/x" → "https://b.com/x".
  static String? applyRedirect(String pattern, String target, String url) {
    final parts = pattern.split('*');
    final re = RegExp('^${parts.map(RegExp.escape).join('(.*)')}\$', caseSensitive: false);
    final m = re.firstMatch(url);
    if (m == null) return null;
    var out = target;
    for (var i = m.groupCount; i >= 1; i--) {
      out = out.replaceAll('\$$i', m.group(i) ?? '');
    }
    return out;
  }

  /// Does a site pattern ("example.com", "*.example.com", "*") match [host]?
  static bool hostMatches(String pattern, String host) {
    final p = pattern.trim().toLowerCase();
    final h = host.toLowerCase();
    if (p.isEmpty || h.isEmpty) return false;
    if (p == '*') return true;
    if (p.startsWith('*.')) {
      final base = p.substring(2);
      return h == base || h.endsWith('.$base');
    }
    if (p.contains('*')) return proWildcard(p).hasMatch(h);
    return h == p || h == 'www.$p';
  }

  /// URL patterns the browser engine should block (rules + low-data).
  List<String> blockedPatterns() {
    final out = <String>[
      for (final r in rules)
        if (r.enabled && r.type == PageRuleType.block) r.pattern.trim(),
    ];
    if (lowData) {
      if (lowDataImages) {
        out.addAll(const ['*.jpg', '*.jpg?*', '*.jpeg', '*.jpeg?*', '*.png', '*.png?*', '*.gif', '*.gif?*', '*.webp', '*.webp?*', '*.avif', '*.avif?*', '*.bmp', '*.bmp?*']);
      }
      if (lowDataVideo) {
        out.addAll(const ['*.mp4', '*.mp4?*', '*.webm', '*.webm?*', '*.mov', '*.mov?*', '*.m4v', '*.m4v?*']);
      }
      if (lowDataFonts) {
        out.addAll(const ['*.woff', '*.woff?*', '*.woff2', '*.woff2?*', '*.ttf', '*.ttf?*', '*.otf', '*.otf?*']);
      }
    }
    return out.where((s) => s.isNotEmpty).toSet().toList();
  }

  List<PageRule> cssFor(String host) =>
      [for (final r in rules) if (r.enabled && r.type == PageRuleType.css && hostMatches(r.pattern, host)) r];

  List<PageRule> jsFor(String host) =>
      [for (final r in rules) if (r.enabled && r.type == PageRuleType.js && hostMatches(r.pattern, host)) r];

  void addBlock(String pattern, {String note = ''}) {
    if (rules.any((r) => r.type == PageRuleType.block && r.pattern == pattern)) return;
    rules.add(PageRule(type: PageRuleType.block, pattern: pattern, note: note));
    save();
  }

  // ── Applying to a tab ─────────────────────────────────────────────────────

  List<RegExp>? _compiled;
  String _compiledFor = '';

  /// Is [url] blocked by a rule or by low-data mode? (shouldInterceptRequest)
  bool blocks(String url) {
    if (!_loaded) return false;
    final patterns = blockedPatterns();
    if (patterns.isEmpty) return false;
    final key = patterns.join('\n');
    if (_compiled == null || _compiledFor != key) {
      _compiled = [for (final p in patterns) proWildcard(p)];
      _compiledFor = key;
    }
    final u = url.length > 2000 ? url.substring(0, 2000) : url;
    return _compiled!.any((re) => re.hasMatch(u));
  }

  /// Site styles, site scripts and the annoyance clean-up (page loaded).
  Future<void> applyPage(InAppWebViewController c, String url) async {
    await ensureLoaded();
    final host = Uri.tryParse(url)?.host ?? '';
    Future<void> run(String js) async {
      try {
        await c.evaluateJavascript(source: js);
      } catch (_) {}
    }

    final css = cssFor(host);
    if (css.isNotEmpty) {
      final all = css.map((r) => r.value).join('\n');
      await run('(function(){var s=document.getElementById("nova-rule-css");if(!s){s=document.createElement("style");'
          's.id="nova-rule-css";(document.head||document.documentElement).appendChild(s);}s.textContent=${proJsString(all)};})();');
    }
    if (lowData && lowDataImages) await run(_lowDataJs);
    if (annoyances) await run(annoyanceJs(stopAutoplay: stopAutoplay));
    for (final r in jsFor(host)) {
      if (r.value.trim().isEmpty) continue;
      await run('try{(function(){${r.value}\n})();}catch(e){console.warn("NOVA X site script: "+e);}');
    }
  }

  /// Hides broken-image boxes left by low-data mode.
  static const String _lowDataJs = r'''
(function(){
  if (document.getElementById('nova-lowdata-css')) return;
  var s=document.createElement('style'); s.id='nova-lowdata-css';
  s.textContent='img:not([src^="data:"]){visibility:hidden!important}';
  (document.head||document.documentElement).appendChild(s);
})();''';

  static const String _autoplayJs = r'''document.querySelectorAll('video').forEach(function(v){
      if(v.__novaUser) return;
      if(!v.paused && v.currentTime < 3){ try{ v.pause(); v.muted=true; }catch(_){} }
      if(!v.__novaHook){ v.__novaHook=1; ['pointerdown','keydown'].forEach(function(ev){ v.addEventListener(ev,function(){ v.__novaUser=1; },{once:true}); }); }
    });''';

  /// Cookie banners, sign-up pop-ups, sticky overlays and autoplay.
  static String annoyanceJs({required bool stopAutoplay}) => '''
(function(){
  if (window.__novaAnnoy) return; window.__novaAnnoy = 1;
  var SEL = ['#onetrust-banner-sdk','#onetrust-consent-sdk','.onetrust-pc-dark-filter','#CybotCookiebotDialog',
    '#CybotCookiebotDialogBodyUnderlay','.cc-window','.cc-banner','#cookie-banner','#cookieBanner','#cookie-notice',
    '#cookie-law-info-bar','.cookie-banner','.cookie-notice','.cookie-consent','#gdpr-consent','.gdpr-banner',
    '#usercentrics-root','#didomi-host','.didomi-popup-backdrop','.qc-cmp2-container','#qc-cmp2-container',
    '.fc-consent-root','#sp_message_container','[id^="sp_message_container"]','.truste_box_overlay','#truste-consent-track',
    '.osano-cm-window','#hs-eu-cookie-confirmation','.cmp-container','#consent-banner','.consent-banner',
    '.newsletter-popup','.newsletter-modal','#newsletter-popup','.signup-modal','.subscribe-popup','.pum-overlay',
    '.modal-backdrop.show.newsletter','.wisepops-root','.privy-popup-container','.klaviyo-form-overlay'];
  var WORDS = /(cookie|consent|gdpr|newsletter|subscribe|sign up for|join our|we use cookies|accept all)/i;
  function unlock(){
    [document.documentElement, document.body].forEach(function(e){
      if(!e) return; var cs=getComputedStyle(e);
      if(cs.overflow==='hidden'||cs.overflowY==='hidden'){ e.style.setProperty('overflow','auto','important'); }
      e.classList.remove('modal-open','no-scroll','noscroll','overflow-hidden');
    });
  }
  function sweep(){
    SEL.forEach(function(s){ try{ document.querySelectorAll(s).forEach(function(e){ e.style.setProperty('display','none','important'); }); }catch(_){} });
    var vw=innerWidth, vh=innerHeight;
    document.querySelectorAll('div,section,aside,dialog').forEach(function(e){
      try{
        var cs=getComputedStyle(e); if(cs.position!=='fixed'&&cs.position!=='sticky') return;
        var z=parseInt(cs.zIndex)||0; if(z<100) return;
        var r=e.getBoundingClientRect(); if(r.width*r.height < vw*vh*0.12) return;
        var t=(e.innerText||'').slice(0,600); if(!WORDS.test(t)) return;
        e.style.setProperty('display','none','important');
      }catch(_){}
    });
    unlock();
    ${stopAutoplay ? _autoplayJs : ''}
  }
  sweep();
  var n=0, mo=new MutationObserver(function(){ if(++n>400){ mo.disconnect(); return; } sweep(); });
  mo.observe(document.documentElement,{childList:true,subtree:true});
  setTimeout(function(){ mo.disconnect(); }, 20000);
})();''';
}
