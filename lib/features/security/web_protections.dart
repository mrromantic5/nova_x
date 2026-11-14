// lib/features/security/web_protections.dart
//
// NOVA X protections for one WebView (3.13.0). The browser screen (and the
// security self-test) create one of these per WebView, so every protection
// runs through the same code:
//
//   NOVA Shield ......... third-party ad / tracker / miner requests blocked
//                         in shouldInterceptRequest, real counts, page
//                         clean-up (collapse + element hiding)
//   Rewrite rules ....... blocked URL patterns, low-data mode, redirects,
//                         site CSS / JS, annoyance clean-up
//   Password Guard ...... page script + "novaxPwGuard" handler; uploads from
//                         the tab are refused after an alert
//   Fingerprint ......... document-start script (all frames)
//   Site controls ....... per-site WebView settings and permissions
//   Session Shield ...... remembers visited hosts of protected sites
//
// Everything happens inside NOVA X's own WebView. Other apps are never
// touched (Google Play Device and Network Abuse policy).

import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../pro/page_rules.dart';
import '../shield/engine/shield_cosmetic.dart';
import '../shield/engine/shield_engine.dart';
import 'fingerprint_guard.dart';
import 'password_guard.dart';
import 'session_shield.dart';
import 'site_controls.dart';

class WebProtections {
  WebProtections({
    required this.tabKey,
    required this.incognito,
    required this.pageUrl,
    this.safeView = false,
    this.context,
    this.leave,
  });

  /// The tab's NOVA Shield counts key.
  final int tabKey;
  final bool incognito;

  /// Safe View: scripts off (Open Safely).
  final bool safeView;

  /// The address shown in the tab (requests are judged against it).
  final String Function() pageUrl;

  /// For Password Guard's alert (null in the self-test).
  final BuildContext? Function()? context;

  /// Takes the user away from a page Password Guard stopped.
  final Future<void> Function()? leave;

  static const String _cosmeticGroup = 'nova_shield_cosmetic';

  /// Loads everything the scripts need (call once at app start; cheap later).
  static Future<void> warmUp() async {
    await Future.wait([
      NovaShieldEngine.instance.ensureReady(),
      SiteControls.instance.ensureLoaded(),
      PasswordGuard.instance.ensureLoaded(),
      SessionShield.instance.ensureLoaded(),
      PageRules.instance.ensureLoaded(),
    ]);
  }

  /// Does a new WebView need shouldInterceptRequest? (Each checked request
  /// makes a round trip to the app, so it is only on when something uses it.)
  static bool needsIntercept() =>
      NovaShieldEngine.instance.enabled || PageRules.instance.blockedPatterns().isNotEmpty;

  /// Turns request checking on for [c] (after a Password Guard alert, or
  /// when the blocker is switched on).
  static Future<void> enableIntercept(InAppWebViewController c) async {
    try {
      final cur = await c.getSettings();
      if (cur == null || cur.useShouldInterceptRequest == true) return;
      cur.useShouldInterceptRequest = true;
      await c.setSettings(settings: cur);
    } catch (_) {}
  }

  /// Document-start scripts for a new WebView.
  List<UserScript> initialScripts() {
    final out = <UserScript>[];
    final fp = SiteControls.instance.loaded ? FingerprintGuard.script() : null;
    if (fp != null) {
      out.add(UserScript(groupName: 'nova_fp', source: fp, injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START, forMainFrameOnly: false));
    }
    final pg = PasswordGuard.instance.script();
    if (pg != null) {
      out.add(UserScript(groupName: 'nova_pw_guard', source: pg, injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START, forMainFrameOnly: false));
    }
    final cos = ShieldCosmetic.instance.script();
    if (cos != null && NovaShieldEngine.instance.enabled && !safeView) {
      out.add(UserScript(groupName: _cosmeticGroup, source: cos, injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START, forMainFrameOnly: true));
    }
    return out;
  }

  InAppWebViewController? _c;

  /// The WebView exists: JS handlers, and scripts that weren't ready when
  /// it was created.
  Future<void> attach(InAppWebViewController c, {required bool hadCosmetic, required bool hadFingerprint, required bool hadGuard}) async {
    _c = c;
    c.addJavaScriptHandler(
      handlerName: PasswordGuard.handlerName,
      callback: (args) async {
        try {
          if (args.isEmpty || args.first is! Map) return 'ok';
          final m = args.first as Map;
          final v = '${m['v'] ?? ''}';
          // The site is the tab's real address, never what the page says.
          final real = await c.getUrl();
          final host = real?.host ?? Uri.tryParse(pageUrl())?.host ?? '';
          final r = await PasswordGuard.instance.check(context?.call(), tabKey, host, v, leave: leave);
          // Uploads from this tab are refused from now on: requests must be checked.
          if (r == 'alert') await enableIntercept(c);
          return r;
        } catch (_) {
          return 'ok';
        }
      },
    );
    await warmUp();
    try {
      if (!hadFingerprint) {
        final fp = FingerprintGuard.script();
        if (fp != null) {
          await c.addUserScript(
              userScript: UserScript(groupName: 'nova_fp', source: fp, injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START, forMainFrameOnly: false));
        }
      }
      if (!hadGuard) {
        final pg = PasswordGuard.instance.script();
        if (pg != null) {
          await c.addUserScript(
              userScript: UserScript(groupName: 'nova_pw_guard', source: pg, injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START, forMainFrameOnly: false));
        }
      }
      if (!hadCosmetic && NovaShieldEngine.instance.enabled && !safeView) {
        await ShieldCosmetic.instance.load();
        final cos = ShieldCosmetic.instance.script();
        if (cos != null) {
          await c.addUserScript(
              userScript: UserScript(groupName: _cosmeticGroup, source: cos, injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START, forMainFrameOnly: true));
        }
      }
    } catch (_) {}
  }

  // ── Requests ──────────────────────────────────────────────────────────────

  /// shouldInterceptRequest: null lets the request through.
  Future<WebResourceResponse?> intercept(WebResourceRequest r) async {
    if (r.isForMainFrame == true) return null;
    final shield = NovaShieldEngine.instance;
    if (shield.refusedUpload(tabKey, r.method ?? 'GET')) {
      return NovaShieldEngine.blockedResponse();
    }
    final url = r.url.toString();
    final type = NovaShieldEngine.requestType(r);
    final e = shield.check(url, pageUrl(), type: type);
    if (e != null) {
      shield.record(tabKey, e);
      _queueCollapse(e);
      return NovaShieldEngine.blockedResponse();
    }
    if (PageRules.instance.blocks(url)) return NovaShieldEngine.blockedResponse();
    return null;
  }

  // Blocked ad frames / images / videos: their empty boxes are removed from
  // the page (batched, a few times a second at most).
  final List<String> _collapseQueue = [];
  Timer? _collapseTimer;
  static const Set<String> _collapsible = {'image', 'media', 'document', 'other'};

  void _queueCollapse(ShieldEvent e) {
    if (e.url.isEmpty || !_collapsible.contains(e.type)) return;
    _collapseQueue.add(e.url);
    if (_collapseTimer?.isActive ?? false) return;
    _collapseTimer = Timer(const Duration(milliseconds: 250), () {
      final urls = LinkedHashSet<String>.of(_collapseQueue).toList();
      _collapseQueue.clear();
      final c = _c;
      if (c != null && urls.isNotEmpty) unawaited(ShieldCosmetic.collapse(c, urls));
    });
  }

  // ── Page lifecycle ────────────────────────────────────────────────────────

  bool _shieldOff(String host) => !NovaShieldEngine.instance.enabled || safeView || NovaShieldEngine.instance.isPaused(host);

  /// Before a main-frame navigation: the site's WebView settings. Returns
  /// the rewrite-rule redirect for [url], if any.
  Future<String?> beforeNavigation(InAppWebViewController c, String url, {required bool desktopMode}) async {
    final to = PageRules.instance.redirectFor(url);
    if (to != null) return to;
    final host = Uri.tryParse(url)?.host ?? '';
    if (host.isNotEmpty) await SiteControls.instance.apply(c, host, desktopMode: desktopMode, safeView: safeView);
    return null;
  }

  Future<void> onLoadStart(InAppWebViewController c, String url, {required bool desktopMode}) async {
    final host = Uri.tryParse(url)?.host ?? '';
    NovaShieldEngine.instance.pageStarted(tabKey, url);
    if (host.isEmpty) return;
    unawaited(ShieldCosmetic.instance.applyOnLoadStart(c, host, off: _shieldOff(host)));
    await SiteControls.instance.apply(c, host, desktopMode: desktopMode, safeView: safeView);
    if (!incognito) unawaited(SessionShield.instance.noteVisit(host));
  }

  Future<void> onLoadStop(InAppWebViewController c, String url) async {
    final host = Uri.tryParse(url)?.host ?? '';
    if (host.isEmpty) return;
    await ShieldCosmetic.instance.applyOnLoadStop(c, host, off: _shieldOff(host));
    if (!SiteControls.instance.forHost(host).autoplay) {
      try {
        await c.evaluateJavascript(source: SiteControls.noAutoplayJs);
      } catch (_) {}
    }
    if (SiteControls.instance.forHost(host).blockPopups) {
      try {
        await c.evaluateJavascript(source: SiteControls.noPopupsJs);
      } catch (_) {}
    }
    if (!safeView) await PageRules.instance.applyPage(c, url);
  }

  void dispose() {
    _collapseTimer?.cancel();
    NovaShieldEngine.instance.forgetTab(tabKey);
    _c = null;
  }

  // ── Permissions (Site Control Center) ─────────────────────────────────────

  /// The saved choice for a camera / microphone request on [host]:
  /// allow, block, or ask (null).
  static bool? mediaChoice(String host, {required bool camera, required bool microphone}) {
    final s = SiteControls.instance.forHost(host);
    final choices = [if (camera) s.camera, if (microphone) s.microphone];
    if (choices.isEmpty) return null;
    if (choices.any((c) => c == SiteChoice.block)) return false;
    if (choices.every((c) => c == SiteChoice.allow)) return true;
    return null;
  }

  /// The saved choice for location on [host] (null = ask).
  static bool? locationChoice(String host) => switch (SiteControls.instance.forHost(host).location) {
        SiteChoice.allow => true,
        SiteChoice.block => false,
        SiteChoice.ask => null,
      };

  /// Pop-ups refused on [host]?
  static bool popupsBlocked(String host) => SiteControls.instance.forHost(host).blockPopups;

  /// For tests / the self-test: a JSON summary of what is active.
  String describe() => jsonEncode({
        'shield': NovaShieldEngine.instance.enabled,
        'rules': NovaShieldEngine.instance.ruleCount,
        'guard': PasswordGuard.instance.enabled,
        'fingerprint': SiteControls.instance.fingerprintDefault.name,
      });
}
