// lib/features/security/security_selftest.dart
//
// Security self-test (3.13.0, ported from NOVA X for PC) — proves on THIS
// phone that each protection really works, using the real code paths (no
// simulation):
//   1. NOVA Shield block lists loaded
//   2. Blocking decisions: a known ad server is blocked, a normal CDN is not
//   3. Live blocking: a real page requests a tracker → a real blocked request
//   4. Fingerprint protection active and stable
//   5. Password Guard stops a protected password leaving the page
//   6. Session Shield deletes a site's cookies
//   7. Download safety flags a risky app download
// Runs in a hidden WebView on https://example.com (a reserved test domain),
// with the same protections as a browser tab. Needs an internet connection.

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../cyber/ui/cyber_palette.dart';
import '../pro/pro_ui.dart';
import '../shield/engine/shield_engine.dart';
import 'download_safety.dart';
import 'password_guard.dart';
import 'session_shield.dart';
import 'web_protections.dart';

class SelfTestResult {
  SelfTestResult(this.name, this.passed, this.detail);
  final String name;
  final bool passed;
  final String detail;
}

class SecuritySelfTest {
  SecuritySelfTest._();

  static bool running = false;
  static const String testPage = 'https://example.com/';

  /// The self-test's own NOVA Shield counts key (never a real tab).
  static const int tabKey = -7031;

  static Future<dynamic> _js(InAppWebViewController c, String body) async {
    try {
      final r = await c.callAsyncJavaScript(functionBody: body);
      return r?.value;
    } catch (e) {
      return 'error: $e';
    }
  }

  static Future<List<SelfTestResult>> run(void Function(String step) progress) async {
    if (running) return const [];
    running = true;
    final out = <SelfTestResult>[];
    final shield = NovaShieldEngine.instance;
    HeadlessInAppWebView? view;
    WebProtections? prot;
    try {
      progress('Loading protections…');
      await WebProtections.warmUp();

      // 1 + 2: lists and decisions (pure engine).
      out.add(SelfTestResult('Block lists loaded', shield.ruleCount > 10000 && shield.enabled,
          '${shield.ruleCount} domain rules · blocker ${shield.enabled ? 'on' : 'OFF (turn on the ad & tracker blocker)'}'));
      final ad = shield.check('https://securepubads.g.doubleclick.net/tag/js/gpt.js', testPage);
      final cdn = shield.check('https://cdn.jsdelivr.net/npm/x.js', testPage);
      out.add(SelfTestResult('Blocking decisions', ad != null && cdn == null,
          'Ad server: ${ad != null ? 'blocked (${ad.rule})' : 'NOT blocked'} · normal CDN: ${cdn == null ? 'allowed' : 'blocked'}'));

      // A hidden WebView with the same protections as a browser tab.
      progress('Opening a test page…');
      var url = testPage;
      prot = WebProtections(tabKey: tabKey, incognito: true, pageUrl: () => url);
      final scripts = prot.initialScripts();
      final created = Completer<InAppWebViewController>();
      final p = prot;
      view = HeadlessInAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(testPage)),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          useShouldInterceptRequest: true,
          cacheEnabled: false,
          // Not the WebView "incognito" setting: on Android it deletes every
          // cookie and site storage in NOVA X.
        ),
        initialUserScripts: UnmodifiableListView(scripts),
        onWebViewCreated: (c) async {
          await p.attach(c,
              hadCosmetic: scripts.any((u) => u.groupName == 'nova_shield_cosmetic'),
              hadFingerprint: scripts.any((u) => u.groupName == 'nova_fp'),
              hadGuard: scripts.any((u) => u.groupName == 'nova_pw_guard'));
          if (!created.isCompleted) created.complete(c);
        },
        shouldInterceptRequest: (c, r) => p.intercept(r),
        onLoadStart: (c, u) {
          if (u != null) url = u.toString();
        },
      );
      await view.run();
      final c = await created.future.timeout(const Duration(seconds: 15));
      // Wait for the page itself (not only the progress bar).
      final deadline = DateTime.now().add(const Duration(seconds: 25));
      var ready = false;
      while (DateTime.now().isBefore(deadline)) {
        try {
          final state = await c.evaluateJavascript(source: 'document.readyState + "|" + location.hostname');
          if ('$state' == 'complete|example.com') {
            ready = true;
            break;
          }
        } catch (_) {}
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
      if (!ready) {
        out.add(SelfTestResult('Test page', false,
            'https://example.com didn’t finish loading in 25 seconds. Check your connection, then run again.'));
        return out;
      }
      await Future<void>.delayed(const Duration(milliseconds: 600));

      // 3: a real request from the page → a real blocked request.
      progress('Sending a real tracker request…');
      final before = shield.countsFor(tabKey).total;
      await _js(c, r'''
        await new Promise(function (res) {
          var img = new Image(); img.onload = img.onerror = function () { res(); };
          img.src = 'https://securepubads.g.doubleclick.net/pagead/nova-selftest.gif?' + Date.now();
          setTimeout(res, 4000);
        });
        try { await fetch('https://www.google-analytics.com/g/collect?nova_selftest=' + Date.now(), { mode: 'no-cors' }); } catch (e) {}
        return 'done';''');
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final after = shield.countsFor(tabKey).total;
      out.add(SelfTestResult('Live blocking', after > before,
          after > before ? '${after - before} request(s) blocked inside the browser and counted' : 'No request was blocked (is the blocker on?)'));

      // 4: fingerprint protection.
      progress('Checking fingerprint protection…');
      final fp = await _js(c, r'''
        var c = document.createElement('canvas'); c.width = 200; c.height = 40;
        var x = c.getContext('2d'); x.font = '16px Arial'; x.fillStyle = '#f60'; x.fillRect(5, 5, 80, 20); x.fillStyle = '#069'; x.fillText('NOVA self-test', 4, 22);
        var a = c.toDataURL(), b = c.toDataURL();
        return JSON.stringify({ active: !!window.__novaFp, stable: a === b, native: HTMLCanvasElement.prototype.toDataURL.toString().indexOf('[native code]') > 0 });''');
      final fpj = _map(fp);
      out.add(SelfTestResult('Fingerprint protection', fpj['active'] == true && fpj['stable'] == true && fpj['native'] == true,
          fpj['active'] == true ? 'Active on this site, stable values, wrappers hidden' : 'Not active (off in the Security Center?)'));

      // 5: Password Guard (a temporary test password that belongs elsewhere).
      progress('Testing Password Guard…');
      final pw = 'NovaSelfTest-${Random.secure().nextInt(1 << 30)}!';
      await PasswordGuard.instance.addSelfTestEntry(pw, 'nova-selftest.invalid');
      final pg = await _js(c, '''
        var f = document.createElement('input'); f.type = 'password'; document.body.appendChild(f);
        f.value = ${jsonEncode(pw)};
        var blocked = false;
        try { await fetch('/nova-selftest-login', { method: 'POST', body: 'p=' + encodeURIComponent(f.value) }); }
        catch (e) { blocked = String(e).indexOf('Password Guard') >= 0; }
        return JSON.stringify({ present: !!window.__novaPwGuard, blocked: blocked, cleared: f.value === '' });''');
      PasswordGuard.instance.removeSelfTestEntry();
      shield.lockPosts(tabKey, false);
      final pgj = _map(pg);
      out.add(SelfTestResult('Password Guard', pgj['blocked'] == true,
          pgj['present'] != true
              ? 'Not active (off in the Security Center?)'
              : (pgj['blocked'] == true
                  ? 'Protected password stopped before it left the page${pgj['cleared'] == true ? ', field cleared' : ''}'
                  : 'The password was NOT stopped')));

      // 6: Session Shield deletes a site's cookies.
      progress('Testing Session Shield…');
      await _js(c, "document.cookie = 'nova_selftest=1; path=/; max-age=600'; return 'ok';");
      final had = '${await _js(c, 'return document.cookie;')}'.contains('nova_selftest');
      final deleted = await SessionShield.instance.wipe(['example.com']);
      final still = '${await _js(c, 'return document.cookie;')}'.contains('nova_selftest');
      out.add(SelfTestResult('Session Shield', had && !still,
          !had ? 'Couldn’t set a test cookie' : (!still ? 'Test cookie deleted ($deleted cookie(s) removed)' : 'The cookie was NOT deleted')));

      // 7: Download safety reads the source of an app download.
      final risky = DownloadSafety.sourceReasons('http://203.0.113.9/update.apk', '');
      final normal = DownloadSafety.sourceReasons('https://f-droid.org/F-Droid.apk', 'https://f-droid.org/');
      out.add(SelfTestResult('Download safety', risky.length >= 2 && normal.isEmpty,
          'Risky app download: ${risky.length} warning sign(s) · normal download: ${normal.isEmpty ? 'no warnings' : normal.join(', ')}'));
    } catch (e) {
      out.add(SelfTestResult('Self-test', false, 'Stopped: $e'));
    } finally {
      PasswordGuard.instance.removeSelfTestEntry();
      shield.lockPosts(tabKey, false);
      prot?.dispose();
      try {
        await view?.dispose();
      } catch (_) {}
      running = false;
    }
    return out;
  }

  static Map<String, dynamic> _map(dynamic v) {
    try {
      final d = v is String ? jsonDecode(v) : v;
      if (d is Map) return Map<String, dynamic>.from(d);
    } catch (_) {}
    return const {};
  }
}

/// The self-test screen.
class SecuritySelfTestScreen extends StatefulWidget {
  const SecuritySelfTestScreen({super.key});

  @override
  State<SecuritySelfTestScreen> createState() => _SecuritySelfTestScreenState();
}

class _SecuritySelfTestScreenState extends State<SecuritySelfTestScreen> {
  List<SelfTestResult>? _results;
  String _step = '';
  bool _running = false;

  Future<void> _run() async {
    setState(() {
      _running = true;
      _results = null;
    });
    final r = await SecuritySelfTest.run((s) {
      if (mounted) setState(() => _step = s);
    });
    if (mounted) {
      setState(() {
        _results = r;
        _running = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ProPage(
      icon: Icons.fact_check_rounded,
      title: 'Security self-test',
      subtitle: 'Proves each protection works on this phone.',
      guide: 'self_test',
      child: Builder(builder: (context) {
        final p = NovaThemeScope.of(context);
        if (_running) {
          return Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 14),
              Text(_step, style: p.ui(color: p.textMuted)),
            ]),
          );
        }
        final r = _results;
        if (r == null) {
          return ProEmpty(
            icon: Icons.verified_user_outlined,
            title: 'Check your protections',
            text: 'Takes about 15 seconds. A hidden page opens example.com, makes a real tracker request and a protected-password '
                'upload, and checks that each one is stopped. Needs an internet connection.',
            action: FilledButton.icon(
              onPressed: _run,
              icon: const Icon(Icons.play_arrow_rounded, size: 18),
              label: const Text('Run self-test'),
            ),
          );
        }
        final passed = r.where((x) => x.passed).length;
        return ListView(padding: const EdgeInsets.all(16), children: [
          Text('$passed of ${r.length} checks passed', style: p.title(size: 20, color: passed == r.length ? p.success : p.warning)),
          const SizedBox(height: 12),
          ProCard(
            child: Column(children: [
              for (final x in r)
                ProFindingRow(level: x.passed ? ProLevel.good : ProLevel.critical, title: '${x.passed ? 'PASS' : 'FAIL'} · ${x.name}', detail: x.detail),
            ]),
          ),
          FilledButton.icon(
            onPressed: _run,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Run again'),
          ),
        ]);
      }),
    );
  }
}
