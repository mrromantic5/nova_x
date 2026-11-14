// lib/features/pro/security_lens.dart
//
// Security Lens — a passive security review of the page you are on, for
// developers, site owners and security researchers:
//   connection & certificate, security headers (CSP, HSTS, framing, MIME
//   sniffing, referrer, permissions), information leaks (server versions),
//   CORS, cookie flags, mixed content, scripts without integrity checks,
//   insecure forms and old libraries.
//
// Passive only: it reads what the page already sent plus ONE normal request
// for the same address (to read its headers and certificate) — no scanning,
// no attack traffic. Results can be copied or saved as Markdown.
// Android (3.13.0): cookie flags are read from the Set-Cookie headers of
// that request (Android WebView doesn't expose cookie flags).

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../cyber/ui/cyber_palette.dart';
import 'pro_tab.dart';
import 'pro_ui.dart';

class LensIssue {
  const LensIssue(this.level, this.area, this.title, this.detail, {this.fix = '', this.penalty = 0});
  final ProLevel level;
  final String area;
  final String title;
  final String detail;
  final String fix;
  final int penalty;
}

class LensCookie {
  const LensCookie(this.name, {this.secure = false, this.httpOnly = false, this.sameSite = ''});
  final String name;
  final bool secure;
  final bool httpOnly;
  final String sameSite;
}

class LensPage {
  const LensPage({
    this.mixed = const [],
    this.noSri = const [],
    this.insecureForms = 0,
    this.passwordOnHttp = false,
    this.inlineScripts = 0,
    this.jquery,
    this.generator,
  });
  final List<String> mixed;
  final List<String> noSri;
  final int insecureForms;
  final bool passwordOnHttp;
  final int inlineScripts;
  final String? jquery;
  final String? generator;

  factory LensPage.fromJson(Map<String, dynamic> j) => LensPage(
        mixed: [for (final x in (j['mixed'] as List? ?? const [])) '$x'],
        noSri: [for (final x in (j['noSri'] as List? ?? const [])) '$x'],
        insecureForms: (j['insecureForms'] as num?)?.toInt() ?? 0,
        passwordOnHttp: j['passwordOnHttp'] == true,
        inlineScripts: (j['inlineScripts'] as num?)?.toInt() ?? 0,
        jquery: j['jquery'] is String ? j['jquery'] as String : null,
        generator: j['generator'] is String ? j['generator'] as String : null,
      );
}

class LensCert {
  const LensCert({required this.subject, required this.issuer, required this.from, required this.until});
  final String subject;
  final String issuer;
  final DateTime from;
  final DateTime until;
}

class LensReport {
  LensReport({
    required this.url,
    required this.issues,
    required this.headers,
    this.cert,
    this.status,
    this.error,
  });
  final String url;
  final List<LensIssue> issues;
  final Map<String, String> headers;
  final LensCert? cert;
  final int? status;
  final String? error;
  final DateTime at = DateTime.now();

  int get score => (100 - issues.fold<int>(0, (a, i) => a + i.penalty)).clamp(0, 100);
  String get grade => score >= 90 ? 'A' : score >= 80 ? 'B' : score >= 65 ? 'C' : score >= 50 ? 'D' : 'F';
  ProLevel get level => score >= 80 ? ProLevel.good : score >= 65 ? ProLevel.medium : score >= 50 ? ProLevel.high : ProLevel.critical;

  String toMarkdown() {
    final b = StringBuffer()
      ..writeln('# Security Lens report')
      ..writeln()
      ..writeln('- **Page:** $url')
      ..writeln('- **Checked:** ${at.toIso8601String()}')
      ..writeln('- **Grade:** $grade ($score/100)')
      ..writeln('- **Method:** passive (page content + one normal request for headers/certificate)')
      ..writeln();
    if (cert != null) {
      b
        ..writeln('## Certificate')
        ..writeln('- Subject: ${cert!.subject}')
        ..writeln('- Issuer: ${cert!.issuer}')
        ..writeln('- Valid: ${cert!.from.toIso8601String().split('T').first} → ${cert!.until.toIso8601String().split('T').first}')
        ..writeln();
    }
    b.writeln('## Findings (${issues.length})');
    for (final i in issues) {
      b
        ..writeln()
        ..writeln('### [${i.level.label}] ${i.title}')
        ..writeln('*Area:* ${i.area}')
        ..writeln()
        ..writeln(i.detail);
      if (i.fix.isNotEmpty) b..writeln()..writeln('**Fix:** ${i.fix}');
    }
    if (headers.isNotEmpty) {
      b
        ..writeln()
        ..writeln('## Response headers')
        ..writeln('```');
      headers.forEach((k, v) => b.writeln('$k: $v'));
      b.writeln('```');
    }
    return b.toString();
  }
}

class SecurityLens {
  SecurityLens._();

  static final RegExp _sessionName = RegExp(r'(sess|auth|token|sid|jwt|login|remember)', caseSensitive: false);

  /// Pure: everything found → issues (public for tests).
  static List<LensIssue> evaluate({
    required String url,
    required Map<String, String> headers,
    List<LensCookie> cookies = const [],
    LensPage page = const LensPage(),
    LensCert? cert,
    DateTime? now,
  }) {
    final out = <LensIssue>[];
    final h = {for (final e in headers.entries) e.key.toLowerCase(): e.value};
    final https = url.startsWith('https://');
    final today = now ?? DateTime.now();

    // Connection
    if (!https) {
      out.add(const LensIssue(ProLevel.critical, 'Connection', 'Page is not served over HTTPS',
          'Everything sent and received can be read or changed by anyone on the network.',
          fix: 'Serve the site over HTTPS and redirect HTTP to HTTPS.', penalty: 40));
    }
    if (cert != null) {
      final days = cert.until.difference(today).inDays;
      if (cert.until.isBefore(today)) {
        out.add(LensIssue(ProLevel.critical, 'Certificate', 'Certificate has expired',
            'It expired on ${cert.until.toIso8601String().split('T').first}.', fix: 'Renew the TLS certificate.', penalty: 30));
      } else if (days <= 14) {
        out.add(LensIssue(ProLevel.medium, 'Certificate', 'Certificate expires in $days day(s)',
            'Renew it before it expires to avoid browser warnings.', fix: 'Turn on automatic renewal.', penalty: 5));
      }
    }

    // Headers
    if (https) {
      final hsts = h['strict-transport-security'];
      if (hsts == null) {
        out.add(const LensIssue(ProLevel.medium, 'Headers', 'No HSTS (Strict-Transport-Security)',
            'Browsers may still try plain HTTP first, which allows downgrade attacks.',
            fix: 'Strict-Transport-Security: max-age=31536000; includeSubDomains', penalty: 10));
      } else {
        final m = RegExp(r'max-age=(\d+)').firstMatch(hsts);
        final age = m == null ? 0 : int.tryParse(m.group(1)!) ?? 0;
        if (age < 15552000) {
          out.add(LensIssue(ProLevel.low, 'Headers', 'HSTS max-age is short ($age s)',
              'A max-age of at least 6 months (15552000) is recommended.', fix: 'Use max-age=31536000.', penalty: 3));
        }
      }
    }
    final csp = h['content-security-policy'];
    if (csp == null) {
      out.add(const LensIssue(ProLevel.medium, 'Headers', 'No Content-Security-Policy',
          'A CSP limits where scripts can come from and greatly reduces the impact of XSS.',
          fix: "Start with: Content-Security-Policy: default-src 'self'; object-src 'none'; base-uri 'self'; frame-ancestors 'self'",
          penalty: 15));
    } else {
      if (csp.contains("'unsafe-inline'") && !csp.contains("'nonce-") && !csp.contains("'sha256-")) {
        out.add(const LensIssue(ProLevel.low, 'Headers', "CSP allows 'unsafe-inline'",
            'Inline scripts are allowed, which weakens XSS protection.', fix: 'Use nonces or hashes instead.', penalty: 5));
      }
      if (csp.contains("'unsafe-eval'")) {
        out.add(const LensIssue(ProLevel.low, 'Headers', "CSP allows 'unsafe-eval'",
            'eval() and similar functions are allowed.', fix: "Remove 'unsafe-eval' if the site doesn't need it.", penalty: 3));
      }
    }
    final xfo = h['x-frame-options'];
    if (xfo == null && !(csp ?? '').contains('frame-ancestors')) {
      out.add(const LensIssue(ProLevel.medium, 'Headers', 'Page can be framed by other sites',
          'Without X-Frame-Options or CSP frame-ancestors, the page can be embedded invisibly (clickjacking).',
          fix: "X-Frame-Options: DENY  or  CSP frame-ancestors 'self'", penalty: 8));
    }
    if ((h['x-content-type-options'] ?? '').toLowerCase() != 'nosniff') {
      out.add(const LensIssue(ProLevel.low, 'Headers', 'No X-Content-Type-Options: nosniff',
          'Browsers may guess file types, which can turn uploads into scripts.', fix: 'X-Content-Type-Options: nosniff', penalty: 5));
    }
    if (h['referrer-policy'] == null) {
      out.add(const LensIssue(ProLevel.low, 'Headers', 'No Referrer-Policy',
          'Full addresses (which can contain private data) may be sent to other sites.',
          fix: 'Referrer-Policy: strict-origin-when-cross-origin', penalty: 3));
    }
    if (h['permissions-policy'] == null) {
      out.add(const LensIssue(ProLevel.info, 'Headers', 'No Permissions-Policy',
          'You can switch off powerful features (camera, location…) the site doesn’t use.',
          fix: 'Permissions-Policy: camera=(), microphone=(), geolocation=()', penalty: 2));
    }
    final server = h['server'];
    if (server != null && RegExp(r'\d').hasMatch(server)) {
      out.add(LensIssue(ProLevel.low, 'Information leak', 'Server version shown: $server',
          'Version numbers help attackers find known weaknesses.', fix: 'Hide version numbers in the Server header.', penalty: 4));
    }
    final powered = h['x-powered-by'];
    if (powered != null) {
      out.add(LensIssue(ProLevel.low, 'Information leak', 'X-Powered-By: $powered',
          'Reveals the technology stack.', fix: 'Remove the X-Powered-By header.', penalty: 3));
    }
    final acao = h['access-control-allow-origin'];
    if (acao == '*' && (h['access-control-allow-credentials'] ?? '').toLowerCase() == 'true') {
      out.add(const LensIssue(ProLevel.high, 'CORS', 'CORS allows any site with credentials',
          'Access-Control-Allow-Origin: * together with credentials is unsafe (and rejected by browsers).',
          fix: 'Allow only the origins you trust.', penalty: 10));
    } else if (acao == '*') {
      out.add(const LensIssue(ProLevel.info, 'CORS', 'CORS open to any site (*)',
          'Fine for public content; make sure no private data is returned here.', penalty: 1));
    }

    // Cookies
    for (final c in cookies) {
      final sensitive = _sessionName.hasMatch(c.name);
      if (sensitive && !c.httpOnly) {
        out.add(LensIssue(ProLevel.medium, 'Cookies', 'Session cookie “${c.name}” readable by scripts',
            'Without HttpOnly, an XSS bug can steal the session.', fix: 'Set HttpOnly on session cookies.', penalty: 8));
      }
      if (https && !c.secure && sensitive) {
        out.add(LensIssue(ProLevel.medium, 'Cookies', 'Session cookie “${c.name}” not marked Secure',
            'It could be sent over plain HTTP.', fix: 'Set the Secure flag.', penalty: 6));
      }
      if (c.sameSite.toLowerCase() == 'none' && !c.secure) {
        out.add(LensIssue(ProLevel.low, 'Cookies', 'Cookie “${c.name}” is SameSite=None without Secure',
            'Browsers reject this combination.', fix: 'Add Secure or use SameSite=Lax.', penalty: 2));
      }
    }

    // Page content
    if (https && page.mixed.isNotEmpty) {
      out.add(LensIssue(ProLevel.medium, 'Content', 'Mixed content (${page.mixed.length})',
          'Some files load over HTTP on an HTTPS page: ${page.mixed.take(3).join(', ')}',
          fix: 'Load every resource over HTTPS.', penalty: 10));
    }
    if (page.passwordOnHttp || (!https && page.insecureForms > 0)) {
      out.add(const LensIssue(ProLevel.critical, 'Forms', 'Login form sends data without encryption',
          'Passwords typed here travel in plain text.', fix: 'Post forms to HTTPS addresses only.', penalty: 20));
    } else if (page.insecureForms > 0) {
      out.add(LensIssue(ProLevel.high, 'Forms', '${page.insecureForms} form(s) post to HTTP',
          'Form data would travel unencrypted.', fix: 'Post forms to HTTPS addresses only.', penalty: 10));
    }
    if (page.noSri.isNotEmpty) {
      out.add(LensIssue(ProLevel.low, 'Content', '${page.noSri.length} script(s) from other sites without integrity check',
          'If that other site is compromised, its scripts run here: ${page.noSri.take(3).join(', ')}',
          fix: 'Add integrity="sha384-…" crossorigin="anonymous" to third-party scripts.', penalty: 3));
    }
    final jq = page.jquery;
    if (jq != null && _older(jq, [3, 5, 0])) {
      out.add(LensIssue(ProLevel.medium, 'Libraries', 'Old jQuery ($jq)',
          'jQuery before 3.5.0 has known XSS issues (CVE-2020-11022 / CVE-2020-11023).',
          fix: 'Update jQuery to the latest 3.x.', penalty: 6));
    }
    if (page.generator != null && RegExp(r'\d').hasMatch(page.generator!)) {
      out.add(LensIssue(ProLevel.info, 'Information leak', 'Generator shown: ${page.generator}',
          'The page tells which CMS version it runs.', fix: 'Remove the generator meta tag.', penalty: 1));
    }
    const order = [ProLevel.critical, ProLevel.high, ProLevel.medium, ProLevel.low, ProLevel.info, ProLevel.good];
    out.sort((a, b) => order.indexOf(a.level).compareTo(order.indexOf(b.level)));
    return out;
  }

  static bool _older(String version, List<int> than) {
    final parts = version.split(RegExp(r'[^\d]+')).where((s) => s.isNotEmpty).map(int.parse).toList();
    for (var i = 0; i < than.length; i++) {
      final v = i < parts.length ? parts[i] : 0;
      if (v != than[i]) return v < than[i];
    }
    return false;
  }

  static const String pageJs = r'''
(function(){
  var https=location.protocol==='https:', host=location.hostname;
  var mixed=[], noSri=[], insecureForms=0, pwHttp=false, inline=0;
  try{ performance.getEntriesByType('resource').forEach(function(e){ if(https && e.name.indexOf('http:')===0) mixed.push(e.name); }); }catch(_){}
  document.querySelectorAll('img[src^="http:"],script[src^="http:"],link[href^="http:"][rel="stylesheet"],iframe[src^="http:"]').forEach(function(e){
    if(https) mixed.push(e.src||e.href); });
  document.querySelectorAll('script').forEach(function(s){
    if(!s.src){ if((s.textContent||'').trim()) inline++; return; }
    try{ var u=new URL(s.src); if(u.hostname!==host && !s.integrity) noSri.push(u.hostname); }catch(_){}
  });
  document.querySelectorAll('form').forEach(function(f){
    try{ var u=new URL(f.getAttribute('action')||location.href, location.href);
      if(u.protocol==='http:'){ insecureForms++; if(f.querySelector('input[type=password]')) pwHttp=true; } }catch(_){}
  });
  var jq=null; try{ jq=(window.jQuery&&window.jQuery.fn&&window.jQuery.fn.jquery)||null; }catch(_){}
  var gen=document.querySelector('meta[name="generator" i]');
  return JSON.stringify({mixed:Array.from(new Set(mixed)).slice(0,30),noSri:Array.from(new Set(noSri)).slice(0,30),
    insecureForms:insecureForms,passwordOnHttp:pwHttp,inlineScripts:inline,jquery:jq,generator:gen?gen.content:null});
})();''';

  /// One normal request for the page address: headers + certificate.
  static Future<(Map<String, String>, LensCert?, int?, String?, List<LensCookie>)> fetchHeaders(String url) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10)
      ..userAgent = 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Mobile NOVA-X Security Lens';
    try {
      final req = await client.getUrl(Uri.parse(url)).timeout(const Duration(seconds: 12));
      req.followRedirects = true;
      req.maxRedirects = 5;
      final res = await req.close().timeout(const Duration(seconds: 15));
      final headers = <String, String>{};
      res.headers.forEach((name, values) => headers[name.toLowerCase()] = values.join(', '));
      LensCert? cert;
      final c = res.certificate;
      if (c != null) cert = LensCert(subject: c.subject, issuer: c.issuer, from: c.startValidity, until: c.endValidity);
      final cookies = <LensCookie>[];
      try {
        for (final k in res.cookies) {
          cookies.add(LensCookie(k.name, secure: k.secure, httpOnly: k.httpOnly, sameSite: k.sameSite?.name ?? ''));
        }
      } catch (_) {}
      final sub = res.listen((_) {});
      unawaited(sub.cancel());
      return (headers, cert, res.statusCode, null, cookies);
    } on HandshakeException catch (e) {
      return (<String, String>{}, null, null, 'Secure connection failed: ${e.message}', const <LensCookie>[]);
    } catch (e) {
      return (<String, String>{}, null, null, 'Couldn’t read the page headers ($e).', const <LensCookie>[]);
    } finally {
      client.close(force: true);
    }
  }

  static Future<LensReport> run(ProTab t) async {
    final url = t.url;
    final c = t.web;
    final (headers, cert, status, error, cookies) = await fetchHeaders(url);
    var page = const LensPage();
    if (c != null) {
      try {
        final r = await c.evaluateJavascript(source: pageJs);
        final d = r is String ? jsonDecode(r) : r;
        if (d is Map) page = LensPage.fromJson(Map<String, dynamic>.from(d));
      } catch (_) {}
    }
    final issues = evaluate(url: url, headers: headers, cookies: cookies, page: page, cert: cert);
    return LensReport(url: url, issues: issues, headers: headers, cert: cert, status: status, error: error);
  }
}

Future<void> showSecurityLens(BuildContext context, ProTab t) =>
    showProDialog<void>(context, (ctx) => _LensDialog(tab: t));

class _LensDialog extends StatefulWidget {
  const _LensDialog({required this.tab});
  final ProTab tab;

  @override
  State<_LensDialog> createState() => _LensDialogState();
}

class _LensDialogState extends State<_LensDialog> {
  LensReport? _r;

  @override
  void initState() {
    super.initState();
    SecurityLens.run(widget.tab).then((r) {
      if (mounted) setState(() => _r = r);
    });
  }

  Future<void> _save() async {
    final r = _r;
    if (r == null) return;
    final host = Uri.tryParse(r.url)?.host ?? 'site';
    try {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Security Lens report',
        fileName: 'security-lens-$host.md',
        bytes: Uint8List.fromList(utf8.encode(r.toMarkdown())),
      );
      if (path == null) return;
      proToast('Report saved');
    } catch (_) {
      proToast('Couldn’t save the report', ok: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = NovaThemeScope.of(context);
    final r = _r;
    return ProDialog(
      icon: Icons.policy_rounded,
      title: 'Security Lens',
      guide: 'security_lens',
      subtitle: '${widget.tab.host} · passive review',
      width: 860,
      actions: [
        if (r != null) ...[
          TextButton.icon(
              onPressed: () => proCopy(r.toMarkdown(), what: 'Report copied'),
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: const Text('Copy')),
          FilledButton.icon(onPressed: _save, icon: const Icon(Icons.save_alt_rounded, size: 18), label: const Text('Save .md')),
        ],
      ],
      child: r == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(20), children: [
              Row(children: [
                ProScoreRing(score: r.score, label: r.grade, color: r.level.color(p)),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Grade ${r.grade}', style: p.title(size: 22, color: r.level.color(p))),
                    const SizedBox(height: 4),
                    Text('${r.issues.length} finding(s)${r.status != null ? ' · HTTP ${r.status}' : ''}',
                        style: p.ui(size: 13, color: p.textMuted)),
                    const SizedBox(height: 8),
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      for (final l in [ProLevel.critical, ProLevel.high, ProLevel.medium, ProLevel.low])
                        if (r.issues.any((i) => i.level == l))
                          ProChip('${r.issues.where((i) => i.level == l).length} ${l.label}', color: l.color(p)),
                    ]),
                    if (r.error != null) ...[
                      const SizedBox(height: 8),
                      Text(r.error!, style: p.ui(size: 12, color: p.warning)),
                    ],
                  ]),
                ),
              ]),
              const SizedBox(height: 18),
              if (r.cert != null)
                ProCard(
                  title: 'Certificate',
                  icon: Icons.verified_rounded,
                  child: Column(children: [
                    ProKv('Issued to', r.cert!.subject, mono: true),
                    ProKv('Issued by', r.cert!.issuer, mono: true),
                    ProKv('Valid until', r.cert!.until.toLocal().toString().split('.').first),
                  ]),
                ),
              ProCard(
                title: 'Findings',
                icon: Icons.bug_report_outlined,
                child: r.issues.isEmpty
                    ? Text('No issues found by the passive checks.', style: p.ui(size: 12.5, color: p.success))
                    : Column(children: [
                        for (final i in r.issues)
                          ProFindingRow(
                            level: i.level,
                            title: i.title,
                            detail: '${i.area} · ${i.detail}${i.fix.isEmpty ? '' : '\nFix: ${i.fix}'}',
                          ),
                      ]),
              ),
              if (r.headers.isNotEmpty)
                ProCard(
                  title: 'Response headers',
                  icon: Icons.list_alt_rounded,
                  child: Column(children: [for (final e in r.headers.entries) ProKv(e.key, e.value, mono: true)]),
                ),
              Text('Passive review: NOVA X read this page and made one normal request for its address. '
                  'Only test sites you own or are allowed to test with active tools.',
                  style: p.ui(size: 11.5, color: p.textFaint)),
            ]),
    );
  }
}
