// lib/features/cyber/engine/checks_quick.dart
//
// NOVA Cyber — Quick scan (any site). Read-only: it only looks at what a
// normal visit returns (the page, its headers, cookies, scripts, the TLS
// certificate) and at public DNS. No test strings are sent.

import 'dart:convert';

import 'cyber_context.dart';
import 'cyber_http.dart';
import 'cyber_models.dart';
import 'cyber_osv.dart';

class QuickChecks {
  QuickChecks(this.c);
  final ScanContext c;

  Future<void> run() async {
    await transport();
    headers();
    cookies(c.home);
    content();
    await libraries();
    await dns();
    await securityTxt();
  }

  // ── Transport & TLS ────────────────────────────────────────────────────────

  Future<void> transport() async {
    final h = c.home;
    if (!c.https) {
      c.add(Finding(
        id: 'tls.none',
        title: 'The site doesn\'t use HTTPS',
        severity: Severity.critical,
        area: CheckArea.transport,
        evidence: 'https://${c.host}/ could not be opened; the site answered over plain HTTP.',
        location: c.base.toString(),
        impact: 'Everything visitors send — passwords, cookies, forms — travels in plain text. Anyone on the same Wi-Fi, '
            'the ISP or a compromised router can read and change pages.',
        fixSummary: 'Install a free TLS certificate (Let\'s Encrypt) and redirect all HTTP traffic to HTTPS.',
        refs: const ['CWE-319', 'OWASP A02:2021'],
        confidence: 'confirmed',
      ));
      return;
    }
    // Certificate
    final cert = h.certificate;
    if (cert != null) {
      final days = cert.endValidity.difference(DateTime.now()).inDays;
      final ev = 'Issuer: ${cert.issuer}\nSubject: ${cert.subject}\nValid until: ${cert.endValidity.toUtc().toIso8601String()} ($days days left)';
      if (days < 0) {
        c.add(Finding(id: 'tls.cert.expired', title: 'TLS certificate has expired', severity: Severity.critical, area: CheckArea.transport,
            evidence: ev, impact: 'Browsers show a full-page warning; users who click through can be intercepted.',
            fixSummary: 'Renew the certificate now and turn on automatic renewal.', refs: const ['CWE-298'], confidence: 'confirmed'));
      } else if (days < 14) {
        c.add(Finding(id: 'tls.cert.expiring', title: 'TLS certificate expires in $days days', severity: Severity.high, area: CheckArea.transport,
            evidence: ev, impact: 'When it expires, every visitor gets a security warning and the site is effectively down.',
            fixSummary: 'Renew now and check that automatic renewal works (certbot renew --dry-run).', refs: const ['CWE-298'], confidence: 'confirmed'));
      } else if (days < 30) {
        c.add(Finding(id: 'tls.cert.expiring', title: 'TLS certificate expires in $days days', severity: Severity.low, area: CheckArea.transport,
            evidence: ev, impact: 'Renewal should happen automatically about 30 days before expiry; this one hasn\'t been renewed yet.',
            fixSummary: 'Check automatic renewal.', confidence: 'confirmed'));
      } else {
        c.pass('tls.cert', 'Valid TLS certificate ($days days left)', CheckArea.transport, evidence: ev);
      }
    }
    // HTTP → HTTPS
    final plain = await c.http.get(Uri.parse('http://${c.host}/'));
    final loc = plain.location ?? '';
    final upgrades = plain.status >= 300 && plain.status < 400 && loc.startsWith('https://');
    if (plain.status == 0) {
      c.pass('tls.redirect', 'Plain HTTP is closed', CheckArea.transport);
    } else if (!upgrades) {
      c.add(Finding(
        id: 'tls.redirect',
        title: 'HTTP isn\'t redirected to HTTPS',
        severity: Severity.medium,
        area: CheckArea.transport,
        evidence: 'GET http://${c.host}/ → ${plain.status}${loc.isEmpty ? '' : ' Location: $loc'}',
        location: 'http://${c.host}/',
        impact: 'Visitors who type the address or follow old links stay on unencrypted HTTP, where traffic can be read or changed.',
        fixSummary: 'Answer every http:// request with a 301 redirect to the same https:// URL.',
        refs: const ['CWE-319'],
        confidence: 'confirmed',
      ));
    } else {
      c.pass('tls.redirect', 'HTTP redirects to HTTPS', CheckArea.transport, evidence: '${plain.status} → $loc');
    }
    // HSTS
    final hsts = h.header('strict-transport-security');
    if (hsts == null) {
      c.add(Finding(
        id: 'hdr.hsts',
        title: 'Strict-Transport-Security (HSTS) is missing',
        severity: Severity.medium,
        area: CheckArea.transport,
        evidence: 'No Strict-Transport-Security header on ${c.base}',
        impact: 'Without HSTS, an attacker on the network can downgrade a visitor to HTTP on the first request '
            '(SSL stripping) and capture cookies or credentials.',
        fixSummary: 'Send "Strict-Transport-Security: max-age=31536000; includeSubDomains" on HTTPS responses.',
        refs: const ['CWE-319', 'OWASP A05:2021'],
        confidence: 'confirmed',
      ));
    } else {
      final maxAge = int.tryParse(RegExp(r'max-age\s*=\s*"?(\d+)', caseSensitive: false).firstMatch(hsts)?.group(1) ?? '') ?? 0;
      if (maxAge < 15552000) {
        c.add(Finding(id: 'hdr.hsts.short', title: 'HSTS max-age is short (${(maxAge / 86400).round()} days)', severity: Severity.low,
            area: CheckArea.transport, evidence: 'Strict-Transport-Security: $hsts',
            impact: 'A short max-age lets the protection lapse for visitors who don\'t come back often.',
            fixSummary: 'Use max-age=31536000 (1 year) once the whole site works on HTTPS.', confidence: 'confirmed'));
      } else {
        c.pass('hdr.hsts', 'HSTS enabled', CheckArea.transport, evidence: hsts);
      }
      if (!hsts.toLowerCase().contains('includesubdomains')) {
        c.add(Finding(id: 'hdr.hsts.subdomains', title: 'HSTS doesn\'t cover subdomains', severity: Severity.info, area: CheckArea.transport,
            evidence: 'Strict-Transport-Security: $hsts',
            impact: 'Subdomains can still be reached over HTTP and used to set cookies for the main site.',
            fixSummary: 'Add includeSubDomains once every subdomain supports HTTPS.'));
      }
    }
  }

  // ── Security headers ───────────────────────────────────────────────────────

  void headers() {
    final h = c.home;
    final isHtml = h.contentType.contains('html') || h.body.contains('<html');

    // Content-Security-Policy
    final csp = h.header('content-security-policy');
    final cspRo = h.header('content-security-policy-report-only');
    if (csp == null) {
      c.add(Finding(
        id: 'hdr.csp',
        title: 'No Content-Security-Policy',
        severity: isHtml ? Severity.medium : Severity.low,
        area: CheckArea.headers,
        evidence: cspRo != null ? 'Only a report-only policy is set: $cspRo' : 'No Content-Security-Policy header.',
        impact: 'A CSP is the main defence that stops injected scripts (XSS) from running and from sending data out. '
            'Without it, one XSS bug gives an attacker full control of the user\'s session.',
        fixSummary: 'Start with a strict policy (default-src \'self\'; object-src \'none\'; base-uri \'self\'; frame-ancestors \'self\') and add the sources you need.',
        refs: const ['CWE-693', 'OWASP A05:2021'],
        confidence: 'confirmed',
      ));
    } else {
      analyseCsp(csp);
    }

    // X-Content-Type-Options
    if (lowerOr(h.header('x-content-type-options')) != 'nosniff') {
      c.add(Finding(id: 'hdr.xcto', title: 'X-Content-Type-Options: nosniff is missing', severity: Severity.low, area: CheckArea.headers,
          evidence: 'X-Content-Type-Options: ${h.header('x-content-type-options') ?? '(missing)'}',
          impact: 'Browsers may guess ("sniff") file types, so an uploaded file can be run as a script or style.',
          fixSummary: 'Send "X-Content-Type-Options: nosniff".', refs: const ['CWE-693'], confidence: 'confirmed'));
    } else {
      c.pass('hdr.xcto', 'X-Content-Type-Options: nosniff', CheckArea.headers);
    }

    // Clickjacking
    final xfo = lowerOr(h.header('x-frame-options'));
    final fa = RegExp(r'frame-ancestors\s+([^;]+)', caseSensitive: false).firstMatch(csp ?? '')?.group(1)?.trim();
    final framedOk = xfo == 'deny' || xfo == 'sameorigin' || (fa != null && !fa.contains('*'));
    if (isHtml && !framedOk) {
      c.add(Finding(
        id: 'hdr.frame',
        title: 'Pages can be framed by any site (clickjacking)',
        severity: Severity.medium,
        area: CheckArea.headers,
        evidence: 'X-Frame-Options: ${h.header('x-frame-options') ?? '(missing)'}; CSP frame-ancestors: ${fa ?? '(missing)'}',
        impact: 'Another site can load your pages invisibly inside its own and trick users into clicking buttons '
            '(changing settings, approving payments, deleting data).',
        fixSummary: 'Send "Content-Security-Policy: frame-ancestors \'self\'" (and "X-Frame-Options: SAMEORIGIN" for old browsers).',
        refs: const ['CWE-1021'],
        confidence: 'confirmed',
      ));
    } else if (isHtml) {
      c.pass('hdr.frame', 'Framing restricted', CheckArea.headers);
    }

    // Referrer-Policy
    final rp = lowerOr(h.header('referrer-policy'));
    if (rp.isEmpty || rp.contains('unsafe-url') || rp.contains('no-referrer-when-downgrade')) {
      c.add(Finding(id: 'hdr.referrer', title: rp.isEmpty ? 'Referrer-Policy is missing' : 'Referrer-Policy leaks full URLs',
          severity: Severity.low, area: CheckArea.headers, evidence: 'Referrer-Policy: ${rp.isEmpty ? '(missing)' : rp}',
          impact: 'Full page addresses (which can contain reset tokens, search terms or IDs) are sent to other sites.',
          fixSummary: 'Send "Referrer-Policy: strict-origin-when-cross-origin".', refs: const ['CWE-200'], confidence: 'confirmed'));
    } else {
      c.pass('hdr.referrer', 'Referrer-Policy set ($rp)', CheckArea.headers);
    }

    // Permissions-Policy
    if (isHtml && h.header('permissions-policy') == null) {
      c.add(Finding(id: 'hdr.permissions', title: 'Permissions-Policy is missing', severity: Severity.low, area: CheckArea.headers,
          evidence: 'No Permissions-Policy header.',
          impact: 'Injected or third-party scripts and frames can ask for camera, microphone, location and other powerful features.',
          fixSummary: 'Send "Permissions-Policy: camera=(), microphone=(), geolocation=(), payment=()" (allow only what you use).',
          confidence: 'confirmed'));
    }

    // Cross-Origin-Opener-Policy
    if (isHtml && h.header('cross-origin-opener-policy') == null) {
      c.add(Finding(id: 'hdr.coop', title: 'Cross-Origin-Opener-Policy is missing', severity: Severity.info, area: CheckArea.headers,
          evidence: 'No Cross-Origin-Opener-Policy header.',
          impact: 'Pages opened from your site (or that open it) keep a handle to the window, which enables tab-nabbing and some cross-site leaks.',
          fixSummary: 'Send "Cross-Origin-Opener-Policy: same-origin" (or same-origin-allow-popups if you use OAuth pop-ups).'));
    }

    // Deprecated X-XSS-Protection
    final xxp = lowerOr(h.header('x-xss-protection'));
    if (xxp.startsWith('1')) {
      c.add(Finding(id: 'hdr.xxp', title: 'X-XSS-Protection is enabled (deprecated)', severity: Severity.info, area: CheckArea.headers,
          evidence: 'X-XSS-Protection: $xxp',
          impact: 'The old browser XSS filter is removed from modern browsers and could itself be abused in old ones.',
          fixSummary: 'Send "X-XSS-Protection: 0" and rely on a Content-Security-Policy.'));
    }

    serverDisclosure(h);
  }

  void analyseCsp(String csp) {
    final d = <String, String>{};
    for (final part in csp.split(';')) {
      final t = part.trim();
      if (t.isEmpty) continue;
      final sp = t.indexOf(RegExp(r'\s'));
      d[(sp < 0 ? t : t.substring(0, sp)).toLowerCase()] = sp < 0 ? '' : t.substring(sp + 1).trim();
    }
    final script = d['script-src'] ?? d['default-src'];
    final problems = <String>[];
    var sev = Severity.info;
    void bump(Severity s) {
      if (s.index < sev.index) sev = s;
    }

    if (script == null) {
      problems.add('No script-src or default-src: scripts from anywhere are allowed.');
      bump(Severity.medium);
    } else {
      final hasNonceOrHash = script.contains("'nonce-") || script.contains("'sha256-") || script.contains("'sha384-") || script.contains("'sha512-");
      final strictDynamic = script.contains("'strict-dynamic'");
      if (script.contains("'unsafe-inline'") && !hasNonceOrHash) {
        problems.add("script-src allows 'unsafe-inline': injected <script> tags and onclick= handlers run, so the policy doesn't stop XSS.");
        bump(Severity.medium);
      }
      if (script.contains("'unsafe-eval'")) {
        problems.add("script-src allows 'unsafe-eval': strings can be run as code (eval, new Function).");
        bump(Severity.low);
      }
      final tokens = script.split(RegExp(r'\s+'));
      if (!strictDynamic && tokens.any((t) => t == '*' || t == 'https:' || t == 'http:' || t == 'data:')) {
        problems.add('script-src allows any host or data: URLs (${tokens.where((t) => t == '*' || t == 'https:' || t == 'http:' || t == 'data:').join(' ')}).');
        bump(Severity.medium);
      }
      const bypassHosts = ['*.googleapis.com', 'ajax.googleapis.com', 'cdnjs.cloudflare.com', 'cdn.jsdelivr.net', 'unpkg.com', '*.cloudfront.net', 'raw.githubusercontent.com'];
      final risky = tokens.where((t) => bypassHosts.any((b) => t.contains(b.replaceFirst('*.', '')))).toList();
      if (!strictDynamic && !hasNonceOrHash && risky.isNotEmpty) {
        problems.add('script-src allows public CDNs (${risky.join(', ')}) that host libraries usable to bypass CSP (e.g. old AngularJS / JSONP).');
        bump(Severity.low);
      }
    }
    if (d['object-src'] == null && !(d['default-src'] ?? '').contains("'none'")) {
      problems.add("object-src isn't 'none' (plugins/embeds can run scripts).");
      bump(Severity.low);
    }
    if (d['base-uri'] == null) {
      problems.add('base-uri is missing (an injected <base> tag can redirect relative script URLs).');
      bump(Severity.low);
    }
    if (d['form-action'] == null) {
      problems.add('form-action is missing (injected forms can post data to other sites).');
    }
    if (d['frame-ancestors'] == null) {
      problems.add('frame-ancestors is missing (clickjacking protection relies on X-Frame-Options).');
    }
    if (problems.isEmpty) {
      c.pass('hdr.csp', 'Strong Content-Security-Policy', CheckArea.headers, evidence: clip(csp, 500));
    } else {
      c.add(Finding(
        id: 'hdr.csp.weak',
        title: 'Content-Security-Policy has weaknesses',
        severity: sev == Severity.info ? Severity.low : sev,
        area: CheckArea.headers,
        evidence: '${clip(csp, 400)}\n\n• ${problems.join('\n• ')}',
        impact: 'A weak CSP lets injected scripts run, which turns any XSS bug into account takeover.',
        fixSummary: "Use nonces or hashes instead of 'unsafe-inline', drop wildcards, add object-src 'none' and base-uri 'self'.",
        refs: const ['CWE-693'],
        confidence: 'confirmed',
      ));
    }
  }

  void serverDisclosure(CyberResponse r) {
    final t = c.report.tech;
    final server = r.header('server') ?? '';
    final powered = r.all('x-powered-by').join(', ');
    t.server = server;
    final ls = server.toLowerCase();
    for (final s in ['nginx', 'apache', 'litespeed', 'cloudflare', 'iis', 'openresty', 'caddy', 'gunicorn', 'envoy']) {
      if (ls.contains(s)) t.stack.add(s == 'openresty' ? 'nginx' : s);
    }
    if (r.header('cf-ray') != null) t.stack.add('cloudflare');
    if (r.header('x-vercel-id') != null) t.stack.add('vercel');
    if (r.header('x-nf-request-id') != null) t.stack.add('netlify');
    final lp = powered.toLowerCase();
    if (lp.contains('php')) t.stack.add('php');
    if (lp.contains('express')) t.stack.add('express');
    if (lp.contains('next.js')) t.stack.add('nextjs');
    if (lp.contains('asp.net')) t.stack.add('aspnet');
    final cookies = r.all('set-cookie').join(';').toLowerCase();
    if (cookies.contains('phpsessid')) t.stack.add('php');
    if (cookies.contains('laravel_session')) t.stack.addAll(['php', 'laravel']);
    if (cookies.contains('connect.sid')) t.stack.add('express');
    if (cookies.contains('asp.net_sessionid')) t.stack.add('aspnet');
    if (c.home.body.contains('/wp-content/') || c.home.body.contains('/wp-includes/')) t.stack.addAll(['wordpress', 'php']);
    final gen = RegExp(r'<meta[^>]+name=["\x27]generator["\x27][^>]+content=["\x27]([^"\x27]+)', caseSensitive: false).firstMatch(c.home.body)?.group(1);
    if (gen != null) {
      final wp = RegExp(r'WordPress\s+([\d.]+)', caseSensitive: false).firstMatch(gen)?.group(1);
      if (wp != null) t.versions['wordpress'] = wp;
    }

    final versioned = <String>[];
    final vRe = RegExp(r'([A-Za-z.\-]+)/(\d+(?:\.\d+){0,3})');
    for (final m in vRe.allMatches('$server $powered')) {
      versioned.add('${m[1]}/${m[2]}');
      t.versions[m[1]!.toLowerCase()] = m[2]!;
    }
    for (final hname in ['x-aspnet-version', 'x-aspnetmvc-version', 'x-generator', 'x-drupal-cache', 'x-runtime']) {
      final v = r.header(hname);
      if (v != null) versioned.add('$hname: $v');
    }
    if (versioned.isNotEmpty) {
      c.add(Finding(
        id: 'srv.version',
        title: 'Server software versions are public',
        severity: Severity.low,
        area: CheckArea.server,
        evidence: [if (server.isNotEmpty) 'Server: $server', if (powered.isNotEmpty) 'X-Powered-By: $powered', ...versioned.where((v) => v.contains(':'))].join('\n'),
        impact: 'Exact versions tell attackers which known exploits to try first.',
        fixSummary: 'Hide versions (nginx: server_tokens off; Apache: ServerTokens Prod; PHP: expose_php = Off; Express: app.disable("x-powered-by")).',
        refs: const ['CWE-200'],
        confidence: 'confirmed',
      ));
    }
    // End-of-life runtimes (no more security fixes).
    final php = t.versions['php'];
    if (php != null) {
      final parts = php.split('.').map((e) => int.tryParse(e) ?? 0).toList();
      final mm = parts[0] * 100 + (parts.length > 1 ? parts[1] : 0);
      if (mm < 801) {
        c.add(Finding(
          id: 'srv.eol.php',
          title: 'PHP $php no longer receives security fixes',
          severity: mm < 800 ? Severity.high : Severity.medium,
          area: CheckArea.server,
          evidence: 'X-Powered-By: $powered',
          impact: 'Vulnerabilities found in this PHP version are never fixed. PHP 7.x reached end of life in 2022 and 8.0 in 2023; '
              '8.1 security support ended on 31 Dec 2025.',
          fixSummary: 'Upgrade to a supported PHP release (8.3 or newer) and test your app on it.',
          refs: const ['CWE-1104'],
          confidence: 'confirmed',
        ));
      }
    }
  }

  // ── Cookies ────────────────────────────────────────────────────────────────

  static final RegExp _sessionLike = RegExp(r'(sess|sid|auth|token|login|jwt|remember|csrf|xsrf|identity|account|user)', caseSensitive: false);

  void cookies(CyberResponse r, {ScanLevel level = ScanLevel.quick}) {
    final list = r.all('set-cookie');
    if (list.isEmpty) return;
    final bad = <String>[];
    var sev = Severity.info;
    for (final raw in list) {
      final name = raw.split('=').first.trim();
      final attrs = raw.toLowerCase();
      final session = _sessionLike.hasMatch(name);
      final issues = <String>[];
      if (c.https && !attrs.contains('; secure') && !attrs.contains(';secure')) {
        issues.add('no Secure');
        if (session && sev.index > Severity.medium.index) sev = Severity.medium;
      }
      if (session && !attrs.contains('httponly')) {
        issues.add('no HttpOnly');
        if (sev.index > Severity.medium.index) sev = Severity.medium;
      }
      final ss = RegExp(r'samesite\s*=\s*(\w+)').firstMatch(attrs)?.group(1);
      if (ss == null) {
        issues.add('no SameSite');
        if (session && sev.index > Severity.low.index) sev = Severity.low;
      } else if (ss == 'none' && !attrs.contains('secure')) {
        issues.add('SameSite=None without Secure (rejected by browsers)');
        if (sev.index > Severity.low.index) sev = Severity.low;
      }
      if (issues.isNotEmpty) bad.add('$name: ${issues.join(', ')}');
    }
    if (bad.isEmpty) {
      c.pass('cookie.flags', 'Cookies have Secure / HttpOnly / SameSite', CheckArea.cookies, level: level);
      return;
    }
    c.add(Finding(
      id: 'cookie.flags',
      title: 'Cookies are missing security flags',
      severity: sev == Severity.info ? Severity.low : sev,
      area: CheckArea.cookies,
      evidence: bad.join('\n'),
      location: r.url.toString(),
      impact: 'Without HttpOnly, an XSS bug can steal session cookies. Without Secure, they can leak over HTTP. '
          'Without SameSite, other sites can make requests that carry the user\'s session (CSRF).',
      fixSummary: 'Set session cookies with "Secure; HttpOnly; SameSite=Lax" (Strict for admin areas), and use the __Host- prefix.',
      refs: const ['CWE-1004', 'CWE-614', 'CWE-1275'],
      confidence: 'confirmed',
      level: level,
    ));
  }

  // ── Page content ───────────────────────────────────────────────────────────

  void content() {
    final body = c.home.body;
    final page = c.home.url;

    // Links, scripts and forms for later checks.
    for (final m in RegExp(r'''<script\b[^>]*\bsrc\s*=\s*["']([^"']+)["']''', caseSensitive: false).allMatches(body)) {
      final u = Uri.tryParse(m[1]!.replaceAll('&amp;', '&'));
      if (u != null) c.scripts.add(page.resolveUri(u));
    }
    for (final m in RegExp(r'''<a\b[^>]*\bhref\s*=\s*["']([^"'#]+)''', caseSensitive: false).allMatches(body).take(400)) {
      final u = Uri.tryParse(m[1]!.replaceAll('&amp;', '&'));
      if (u == null) continue;
      final abs = page.resolveUri(u);
      if (abs.host == c.host && (abs.scheme == 'https' || abs.scheme == 'http')) c.links.add(abs);
    }
    c.forms.addAll(parseForms(body, page));

    // Mixed content
    if (c.https) {
      final active = <String>{};
      final passive = <String>{};
      for (final m in RegExp(r'''<(script|iframe|link|img|audio|video|source|embed|object)\b[^>]*\b(src|href|data)\s*=\s*["'](http://[^"']+)''', caseSensitive: false).allMatches(body)) {
        final tag = m[1]!.toLowerCase();
        (tag == 'img' || tag == 'audio' || tag == 'video' || tag == 'source' ? passive : active).add(m[3]!);
      }
      if (active.isNotEmpty) {
        c.add(Finding(id: 'content.mixed.active', title: 'Scripts, styles or frames load over HTTP (mixed content)', severity: Severity.high,
            area: CheckArea.content, evidence: active.take(8).join('\n'), location: page.toString(),
            impact: 'An attacker on the network can replace these files and take over the page, even though it\'s served over HTTPS.',
            fixSummary: 'Load every resource over https:// (or protocol-relative to your own host) and add "upgrade-insecure-requests" to your CSP.',
            refs: const ['CWE-311'], confidence: 'confirmed'));
      }
      if (passive.isNotEmpty) {
        c.add(Finding(id: 'content.mixed.passive', title: 'Images or media load over HTTP', severity: Severity.low, area: CheckArea.content,
            evidence: passive.take(8).join('\n'), location: page.toString(),
            impact: 'They can be swapped or tracked on the network, and browsers flag the page as not fully secure.',
            fixSummary: 'Serve them over HTTPS.', confidence: 'confirmed'));
      }
    }

    // Third-party scripts without Subresource Integrity
    final noSri = <String>{};
    for (final m in RegExp(r'<script\b([^>]*)>', caseSensitive: false).allMatches(body)) {
      final a = m[1]!;
      final src = RegExp(r'''src\s*=\s*["']([^"']+)''', caseSensitive: false).firstMatch(a)?.group(1);
      if (src == null) continue;
      final u = page.resolve(src.replaceAll('&amp;', '&'));
      if (u.host.isEmpty || u.host == c.host || u.host.endsWith('.${registrableDomain(c.host)}')) continue;
      if (!a.toLowerCase().contains('integrity=')) noSri.add(u.host + u.path);
    }
    if (noSri.isNotEmpty) {
      c.add(Finding(
        id: 'content.sri',
        title: '${noSri.length} third-party script${noSri.length == 1 ? '' : 's'} without integrity check',
        severity: Severity.low,
        area: CheckArea.content,
        evidence: noSri.take(10).join('\n'),
        location: page.toString(),
        impact: 'If that CDN or vendor is compromised, its script runs with full access to your users\' sessions (supply-chain attack).',
        fixSummary: 'Pin versions and add integrity="sha384-…" crossorigin="anonymous" to static CDN scripts; self-host critical ones.',
        refs: const ['CWE-829'],
        confidence: 'confirmed',
      ));
    }

    // Forms
    for (final f in c.forms) {
      final action = f['action'] as Uri;
      final inputs = (f['inputs'] as List).cast<Map<String, String>>();
      final hasPassword = inputs.any((i) => i['type'] == 'password');
      if (action.scheme == 'http') {
        c.add(Finding(id: 'content.form.http', title: 'A form sends data over plain HTTP', severity: hasPassword ? Severity.high : Severity.medium,
            area: CheckArea.content, evidence: 'action="$action"${hasPassword ? ' (contains a password field)' : ''}', location: page.toString(),
            impact: 'What users type is sent unencrypted and can be read on the network.',
            fixSummary: 'Make the form post to an https:// URL.', refs: const ['CWE-319'], confidence: 'confirmed'));
      }
      if (hasPassword && !c.https) {
        c.add(Finding(id: 'content.password.http', title: 'Password field on a page served over HTTP', severity: Severity.high,
            area: CheckArea.content, evidence: 'Password input on ${c.base}', impact: 'Passwords can be captured on the network.',
            fixSummary: 'Serve login pages only over HTTPS.', refs: const ['CWE-319'], confidence: 'confirmed'));
      }
      if (hasPassword && (f['method'] as String) == 'get') {
        c.add(Finding(id: 'content.password.get', title: 'Login form uses GET (password in the URL)', severity: Severity.medium,
            area: CheckArea.content, evidence: 'method="get" action="$action"', location: page.toString(),
            impact: 'Passwords end up in browser history, server logs and Referer headers.',
            fixSummary: 'Use method="post" for login forms.', refs: const ['CWE-598'], confidence: 'confirmed'));
      }
    }

    // Keys and secrets in the page source
    secretsIn(body, page.toString(), ScanLevel.quick);

    // Sensitive HTML comments
    final comments = <String>[];
    for (final m in RegExp(r'<!--([\s\S]*?)-->').allMatches(body)) {
      final t = m[1]!;
      if (RegExp(r'(password|passwd|api[_-]?key|secret|token|todo|fixme|hack|debug|internal|staging|admin)', caseSensitive: false).hasMatch(t) && t.length < 800) {
        comments.add(redactSecrets(clip(t, 160)));
      }
    }
    if (comments.isNotEmpty) {
      c.add(Finding(id: 'content.comments', title: 'HTML comments mention sensitive things', severity: Severity.info, area: CheckArea.content,
          evidence: comments.take(6).join('\n'), location: page.toString(),
          impact: 'Comments are visible to everyone and often reveal internal paths, credentials or unfinished security work.',
          fixSummary: 'Strip comments in production builds.', refs: const ['CWE-615']));
    }
  }

  /// API keys / tokens in [text]. Public client keys are reported at a lower
  /// severity than server secrets.
  void secretsIn(String text, String where, ScanLevel level) {
    final found = <String>[];
    var sev = Severity.info;
    void hit(String kind, String value, Severity s) {
      final shown = value.length <= 8 ? value : '${value.substring(0, 6)}…[${value.length - 6} chars redacted]';
      found.add('$kind: $shown');
      if (s.index < sev.index) sev = s;
    }

    for (final m in RegExp(r'\b(AKIA|ASIA)[A-Z0-9]{16}\b').allMatches(text)) hit('AWS access key', m[0]!, Severity.high);
    for (final m in RegExp(r'\bsk_live_[0-9a-zA-Z]{20,}\b').allMatches(text)) hit('Stripe SECRET key', m[0]!, Severity.critical);
    for (final m in RegExp(r'\brk_live_[0-9a-zA-Z]{20,}\b').allMatches(text)) hit('Stripe restricted key', m[0]!, Severity.high);
    for (final m in RegExp(r'\bgh[pousr]_[A-Za-z0-9]{36,}\b').allMatches(text)) hit('GitHub token', m[0]!, Severity.critical);
    for (final m in RegExp(r'\bxox[baprs]-[A-Za-z0-9-]{10,}\b').allMatches(text)) hit('Slack token', m[0]!, Severity.high);
    for (final m in RegExp(r'\bsk-(proj-)?[A-Za-z0-9_-]{32,}\b').allMatches(text)) hit('OpenAI-style secret key', m[0]!, Severity.critical);
    for (final m in RegExp(r'\bgsk_[A-Za-z0-9]{40,}\b').allMatches(text)) hit('AI provider secret key', m[0]!, Severity.critical);
    for (final m in RegExp(r'-----BEGIN (RSA |EC |OPENSSH |)PRIVATE KEY-----').allMatches(text)) hit('Private key', m[0]!, Severity.critical);
    for (final m in RegExp(r'\bAIza[0-9A-Za-z_-]{35}\b').allMatches(text).take(3)) hit('Google API key (client key)', m[0]!, Severity.low);
    for (final m in RegExp(r'\bSG\.[A-Za-z0-9_-]{22}\.[A-Za-z0-9_-]{43}\b').allMatches(text)) hit('SendGrid key', m[0]!, Severity.critical);
    for (final m in RegExp(r'\b(mongodb(\+srv)?|postgres(ql)?|mysql)://[^\s"<>]+:[^\s"<>@]+@[^\s"<>]+').allMatches(text)) hit('Database URL with password', m[0]!, Severity.critical);
    if (found.isEmpty) return;
    c.add(Finding(
      id: level == ScanLevel.code ? 'code.secret' : 'content.secret',
      title: sev == Severity.low ? 'Client API key in the page (check its restrictions)' : 'Secret keys are exposed',
      severity: sev,
      area: level == ScanLevel.code ? CheckArea.code : CheckArea.content,
      evidence: found.take(10).join('\n'),
      location: where,
      impact: sev == Severity.low
          ? 'Google browser keys are meant to be public, but an unrestricted key can be used by anyone and billed to you.'
          : 'Anyone who views the page source can use these keys — to read data, send email, spend money or access your accounts.',
      fixSummary: sev == Severity.low
          ? 'In Google Cloud Console restrict the key to your domains (HTTP referrers) and to the APIs you use.'
          : 'Revoke these keys now, issue new ones, and keep them only on the server (environment variables).',
      refs: const ['CWE-798', 'CWE-200'],
      confidence: 'confirmed',
      level: level,
    ));
  }

  // ── Libraries with known vulnerabilities (OSV.dev) ─────────────────────────

  static final Map<String, List<RegExp>> _libPatterns = {
    'jquery': [RegExp(r'jquery[.-](\d+\.\d+\.\d+)(?:\.min)?\.js', caseSensitive: false), RegExp(r'jquery@(\d+\.\d+\.\d+)'), RegExp(r'/\*!? jQuery v(\d+\.\d+\.\d+)')],
    'jquery-ui': [RegExp(r'jquery-ui[.-](\d+\.\d+\.\d+)', caseSensitive: false), RegExp(r'jQuery UI - v(\d+\.\d+\.\d+)')],
    'bootstrap': [RegExp(r'bootstrap[@/-](\d+\.\d+\.\d+)', caseSensitive: false), RegExp(r'Bootstrap v(\d+\.\d+\.\d+)')],
    'angular': [RegExp(r'angular[.-](1\.\d+\.\d+)(?:\.min)?\.js', caseSensitive: false), RegExp(r'AngularJS v(1\.\d+\.\d+)')],
    'lodash': [RegExp(r'lodash[@.-](\d+\.\d+\.\d+)', caseSensitive: false), RegExp(r'lodash\.com.*?(\d+\.\d+\.\d+)')],
    'moment': [RegExp(r'moment[@.-](\d+\.\d+\.\d+)', caseSensitive: false), RegExp(r'//! moment\.js\s*\n//! version : (\d+\.\d+\.\d+)')],
    'vue': [RegExp(r'vue@(\d+\.\d+\.\d+)'), RegExp(r'Vue\.js v(\d+\.\d+\.\d+)')],
    'react': [RegExp(r'react@(\d+\.\d+\.\d+)'), RegExp(r'React v(\d+\.\d+\.\d+)')],
    'handlebars': [RegExp(r'handlebars[@.-]v?(\d+\.\d+\.\d+)', caseSensitive: false)],
    'dompurify': [RegExp(r'dompurify@(\d+\.\d+\.\d+)', caseSensitive: false), RegExp(r'DOMPurify (\d+\.\d+\.\d+)')],
    'underscore': [RegExp(r'underscore[@.-](\d+\.\d+\.\d+)', caseSensitive: false)],
    'axios': [RegExp(r'axios@(\d+\.\d+\.\d+)'), RegExp(r'axios v(\d+\.\d+\.\d+)')],
    'swiper': [RegExp(r'swiper@(\d+\.\d+\.\d+)')],
    'tinymce': [RegExp(r'tinymce/(\d+\.\d+\.\d+)')],
    'highlight.js': [RegExp(r'highlight\.js/(\d+\.\d+\.\d+)')],
  };

  Future<void> libraries() async {
    final found = <String, String>{}; // name → version
    void scan(String text) {
      _libPatterns.forEach((name, patterns) {
        if (found.containsKey(name)) return;
        for (final p in patterns) {
          final m = p.firstMatch(text);
          if (m != null) {
            found[name] = m.group(1)!;
            return;
          }
        }
      });
    }

    scan(c.home.body);
    scan(c.scripts.map((u) => u.toString()).join('\n'));
    // Read the banners of up to 12 scripts (as a browser would load them).
    for (final s in c.scripts.where((u) => u.scheme.startsWith('http')).take(12)) {
      if (found.length == _libPatterns.length) break;
      final r = await c.http.get(s, quiet: true);
      if (r.ok) scan(r.body.length > 4000 ? r.body.substring(0, 4000) : r.body);
    }
    found.forEach((k, v) => c.report.tech.versions[k] = v);
    if (found.isEmpty) return;
    c.log('Libraries: ${found.entries.map((e) => '${e.key} ${e.value}').join(', ')} — checking OSV.dev…');
    final results = await Osv.query([for (final e in found.entries) OsvPackage(e.key, 'npm', e.value)]);
    var clean = 0;
    for (final e in found.entries) {
      final vulns = results[e.key] ?? const <OsvVuln>[];
      if (vulns.isEmpty) {
        clean++;
        continue;
      }
      c.add(osvFinding('dep.${e.key}', '${e.key} ${e.value}', vulns, CheckArea.dependencies, c.home.url.toString(), ScanLevel.quick));
    }
    if (_isAngular1(found['angular'])) {
      c.add(Finding(id: 'dep.angularjs.eol', title: 'AngularJS 1.x is end-of-life', severity: Severity.medium, area: CheckArea.dependencies,
          evidence: 'AngularJS ${found['angular']}', impact: 'AngularJS stopped receiving security fixes in January 2022; its template syntax is a well-known XSS and CSP-bypass vector.',
          fixSummary: 'Migrate to a supported framework, or use a commercially supported AngularJS build.', refs: const ['CWE-1104'], confidence: 'confirmed'));
    }
    if (clean > 0 && clean == found.length) {
      c.pass('dep.clean', 'No known vulnerabilities in detected libraries', CheckArea.dependencies,
          evidence: found.entries.map((e) => '${e.key} ${e.value}').join(', '));
    }
  }

  static bool _isAngular1(String? v) => v != null && v.startsWith('1.');

  // ── DNS & email (public DNS over HTTPS) ────────────────────────────────────

  Future<Map<String, dynamic>?> doh(String name, String type) async {
    final r = await c.http.send('GET', Uri.https('cloudflare-dns.com', '/dns-query', {'name': name, 'type': type}),
        headers: {'accept': 'application/dns-json'}, quiet: true);
    c.http.sent--; // DNS lookups aren't requests to the site (budget)
    if (!r.ok) return null;
    try {
      final j = jsonDecode(r.body);
      return j is Map<String, dynamic> ? j : null;
    } catch (_) {
      return null;
    }
  }

  static List<String> txtOf(Map<String, dynamic>? j) => [
        for (final a in (j?['Answer'] as List? ?? const []))
          if (a is Map && a['type'] == 16) (RegExp(r'"((?:[^"\\]|\\.)*)"').allMatches('${a['data']}').map((m) => m[1]).join())
      ];

  Future<void> dns() async {
    final domain = registrableDomain(c.host);
    c.log('DNS checks for $domain…');
    // SPF
    final spf = txtOf(await doh(domain, 'TXT')).where((t) => t.toLowerCase().startsWith('v=spf1')).toList();
    final mx = await doh(domain, 'MX');
    final hasMx = (mx?['Answer'] as List?)?.isNotEmpty ?? false;
    if (spf.isEmpty) {
      c.add(Finding(id: 'dns.spf', title: 'No SPF record — anyone can send email as @$domain', severity: hasMx ? Severity.medium : Severity.low,
          area: CheckArea.dns, evidence: 'No "v=spf1" TXT record on $domain.',
          impact: 'Attackers can send phishing email that appears to come from your domain.',
          fixSummary: hasMx ? 'Publish an SPF record listing your mail providers, ending in -all.' : 'If the domain sends no email, publish "v=spf1 -all".',
          refs: const ['CWE-290'], confidence: 'confirmed'));
    } else if (spf.length > 1) {
      c.add(Finding(id: 'dns.spf.multiple', title: 'More than one SPF record (SPF fails)', severity: Severity.medium, area: CheckArea.dns,
          evidence: spf.join('\n'), impact: 'Receivers treat multiple SPF records as an error, so the protection doesn\'t work.',
          fixSummary: 'Merge them into one record.', confidence: 'confirmed'));
    } else {
      final s = spf.first.toLowerCase();
      if (s.contains('+all')) {
        c.add(Finding(id: 'dns.spf.all', title: 'SPF allows every server in the world (+all)', severity: Severity.high, area: CheckArea.dns,
            evidence: spf.first, impact: 'The record explicitly authorises anyone to send as your domain.',
            fixSummary: 'End the record with -all (or ~all while testing).', confidence: 'confirmed'));
      } else if (s.contains('?all') || !s.contains('all')) {
        c.add(Finding(id: 'dns.spf.soft', title: 'SPF doesn\'t reject other senders', severity: Severity.low, area: CheckArea.dns,
            evidence: spf.first, impact: 'Spoofed email is not rejected by SPF.', fixSummary: 'End the record with -all.', confidence: 'confirmed'));
      } else {
        c.pass('dns.spf', 'SPF record present', CheckArea.dns, evidence: spf.first);
      }
    }
    // DMARC
    final dmarc = txtOf(await doh('_dmarc.$domain', 'TXT')).where((t) => t.toLowerCase().startsWith('v=dmarc1')).toList();
    if (dmarc.isEmpty) {
      c.add(Finding(id: 'dns.dmarc', title: 'No DMARC policy', severity: Severity.medium, area: CheckArea.dns,
          evidence: 'No TXT record at _dmarc.$domain',
          impact: 'Without DMARC, mailboxes don\'t know to reject email that fails SPF/DKIM, so spoofing your domain works.',
          fixSummary: 'Publish "v=DMARC1; p=quarantine; rua=mailto:dmarc@$domain" and move to p=reject.', refs: const ['CWE-290'], confidence: 'confirmed'));
    } else {
      final p = RegExp(r'\bp\s*=\s*(\w+)', caseSensitive: false).firstMatch(dmarc.first)?.group(1)?.toLowerCase();
      if (p == null || p == 'none') {
        c.add(Finding(id: 'dns.dmarc.none', title: 'DMARC is in monitor-only mode (p=none)', severity: Severity.low, area: CheckArea.dns,
            evidence: dmarc.first, impact: 'Spoofed email is reported but still delivered.',
            fixSummary: 'After checking reports, change to p=quarantine and then p=reject.', confidence: 'confirmed'));
      } else {
        c.pass('dns.dmarc', 'DMARC enforced (p=$p)', CheckArea.dns, evidence: dmarc.first);
      }
    }
    // CAA
    final caa = await doh(domain, 'CAA');
    if (((caa?['Answer'] as List?) ?? const []).isEmpty) {
      c.add(Finding(id: 'dns.caa', title: 'No CAA record', severity: Severity.info, area: CheckArea.dns,
          evidence: 'No CAA record on $domain',
          impact: 'Any certificate authority may issue certificates for your domain; CAA limits this to the ones you use.',
          fixSummary: 'Add e.g. "0 issue \\"letsencrypt.org\\"" for the CAs you use.'));
    } else {
      c.pass('dns.caa', 'CAA record present', CheckArea.dns);
    }
    // DNSSEC
    final a = await doh(domain, 'A');
    if (a != null && a['AD'] != true) {
      c.add(Finding(id: 'dns.dnssec', title: 'DNSSEC isn\'t enabled', severity: Severity.info, area: CheckArea.dns,
          evidence: 'Validating resolver did not mark $domain as authenticated (AD=false).',
          impact: 'DNS answers for your domain can be forged by attackers who can poison resolvers.',
          fixSummary: 'Enable DNSSEC at your DNS provider and add the DS record at your registrar.'));
    } else if (a != null) {
      c.pass('dns.dnssec', 'DNSSEC enabled', CheckArea.dns);
    }
    // Dangling CNAME on the scanned host
    await takeover(c.host);
  }

  /// Services where a CNAME pointing at an unclaimed resource can be taken over.
  static const Map<String, String> takeoverFingerprints = {
    'github.io': "There isn't a GitHub Pages site here",
    'herokuapp.com': 'no-such-app',
    'herokudns.com': 'no-such-app',
    's3.amazonaws.com': 'NoSuchBucket',
    'amazonaws.com': 'NoSuchBucket',
    'cloudfront.net': 'The request could not be satisfied',
    'azurewebsites.net': '404 Web Site not found',
    'cloudapp.net': '404 Web Site not found',
    'trafficmanager.net': '404 Web Site not found',
    'blob.core.windows.net': 'The specified container does not exist',
    'myshopify.com': 'Sorry, this shop is currently unavailable',
    'netlify.app': 'Not Found - Request ID',
    'vercel.app': 'DEPLOYMENT_NOT_FOUND',
    'surge.sh': 'project not found',
    'bitbucket.io': 'Repository not found',
    'ghost.io': 'Domain error',
    'pantheonsite.io': '404 error unknown site',
    'readthedocs.io': 'unknown to Read the Docs',
    'wordpress.com': 'Do you want to register',
    'fly.dev': '404 Not Found',
    'firebaseapp.com': 'Site Not Found',
    'web.app': 'Site Not Found',
  };

  Future<void> takeover(String host, {ScanLevel level = ScanLevel.quick}) async {
    final j = await doh(host, 'CNAME');
    final cname = [
      for (final a in (j?['Answer'] as List? ?? const []))
        if (a is Map && a['type'] == 5) '${a['data']}'.replaceFirst(RegExp(r'\.$'), '')
    ];
    if (cname.isEmpty) return;
    final target = cname.last.toLowerCase();
    final targetA = await doh(target, 'A');
    final nx = targetA != null && targetA['Status'] == 3; // NXDOMAIN
    String? fingerprint;
    for (final e in takeoverFingerprints.entries) {
      if (target.endsWith(e.key)) fingerprint = e.value;
    }
    if (!nx && fingerprint == null) return;
    var proven = nx;
    var evidence = '$host CNAME $target${nx ? ' (target does not exist: NXDOMAIN)' : ''}';
    if (!nx && fingerprint != null) {
      final r = await c.http.get(Uri.https(host, '/'), quiet: true);
      final r2 = r.status == 0 ? await c.http.get(Uri.http(host, '/'), quiet: true) : r;
      if (r2.body.contains(fingerprint)) {
        proven = true;
        evidence += '\nThe service answers: "$fingerprint"';
      }
    }
    if (!proven) return;
    c.add(Finding(
      id: 'dns.takeover',
      title: 'Subdomain can be taken over: $host',
      severity: Severity.high,
      area: CheckArea.dns,
      evidence: evidence,
      location: host,
      impact: 'The DNS record points to a hosting resource that no longer exists. Anyone can create that resource and serve '
          'their own content (phishing, cookie theft) on your domain.',
      fixSummary: 'Delete the DNS record, or re-create the resource it points to under your own account.',
      refs: const ['CWE-350'],
      confidence: nx ? 'firm' : 'confirmed',
      level: level,
    ));
  }

  // ── security.txt ───────────────────────────────────────────────────────────

  Future<void> securityTxt() async {
    final r = await c.http.get(c.url('/.well-known/security.txt'), quiet: true);
    final text = r.body;
    if (r.status == 200 && text.toLowerCase().contains('contact:') && !text.contains('<html')) {
      final exp = RegExp(r'^Expires:\s*(.+)$', multiLine: true, caseSensitive: false).firstMatch(text)?.group(1);
      final dt = exp == null ? null : DateTime.tryParse(exp.trim());
      if (dt != null && dt.isBefore(DateTime.now())) {
        c.add(Finding(id: 'policy.securitytxt.expired', title: 'security.txt has expired', severity: Severity.info, area: CheckArea.server,
            evidence: 'Expires: $exp', impact: 'Researchers may ignore an expired file.', fixSummary: 'Update the Expires date.'));
      } else {
        c.pass('policy.securitytxt', 'security.txt published', CheckArea.server);
      }
    } else {
      c.add(Finding(id: 'policy.securitytxt', title: 'No security.txt', severity: Severity.info, area: CheckArea.server,
          evidence: 'GET /.well-known/security.txt → ${r.status}',
          impact: 'People who find a vulnerability have no official way to tell you, so reports go nowhere (or public).',
          fixSummary: 'Publish /.well-known/security.txt with Contact: and Expires: (see securitytxt.org).'));
    }
  }
}

/// Builds a finding from OSV results.
Finding osvFinding(String id, String what, List<OsvVuln> vulns, CheckArea area, String location, ScanLevel level) {
  var sev = Severity.low;
  for (final v in vulns) {
    if (v.severity.index < sev.index) sev = v.severity;
  }
  final fixed = vulns.map((v) => v.fixedIn).whereType<String>().toList()..sort(compareVersions);
  return Finding(
    id: id,
    title: '$what has ${vulns.length} known vulnerabilit${vulns.length == 1 ? 'y' : 'ies'}',
    severity: sev,
    area: area,
    evidence: vulns.take(8).map((v) => '${v.id}${v.aliases.isEmpty ? '' : ' (${v.aliases.take(2).join(', ')})'} — ${v.severity.label}: ${v.summary}').join('\n'),
    location: location,
    impact: 'Published vulnerabilities come with public details (often exploit code) that attackers scan for automatically.',
    fixSummary: fixed.isEmpty ? 'Update to the latest version.' : 'Update to ${fixed.last} or newer.',
    refs: [for (final v in vulns.take(6)) v.id],
    confidence: 'confirmed',
    level: level,
  );
}
