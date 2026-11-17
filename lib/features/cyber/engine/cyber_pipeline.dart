// lib/features/cyber/engine/cyber_pipeline.dart
//
// NOVA Cyber — findings pipeline. Every scan (website, code, mobile, binary)
// goes through the same steps before it is stored:
//
//   normalize → deduplicate → score (CVSS 3.1) → correlate (attack chains)
//
// plus triage (open / confirmed / false positive / accepted risk / fixed,
// with regression detection) and SARIF 2.1.0 export for CI and code-scanning
// dashboards. All pure except the triage store.

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:path_provider/path_provider.dart';

import 'cyber_models.dart';

// ── CVSS 3.1 ─────────────────────────────────────────────────────────────────

double _roundUp(double x) {
  final i = (x * 100000).round();
  return i % 10000 == 0 ? i / 100000.0 : (i ~/ 10000 + 1) / 10.0;
}

/// CVSS 3.1 base score for a vector like
/// "CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H". 0 for invalid vectors.
double cvssScore(String vector) {
  final m = <String, String>{};
  for (final part in vector.split('/')) {
    final kv = part.split(':');
    if (kv.length == 2) m[kv[0]] = kv[1];
  }
  const av = {'N': 0.85, 'A': 0.62, 'L': 0.55, 'P': 0.2};
  const ac = {'L': 0.77, 'H': 0.44};
  const ui = {'N': 0.85, 'R': 0.62};
  const cia = {'H': 0.56, 'L': 0.22, 'N': 0.0};
  final scope = m['S'];
  if (!av.containsKey(m['AV']) || !ac.containsKey(m['AC']) || !ui.containsKey(m['UI']) || (scope != 'U' && scope != 'C')) return 0;
  final changed = scope == 'C';
  final pr = switch (m['PR']) {
    'N' => 0.85,
    'L' => changed ? 0.68 : 0.62,
    'H' => changed ? 0.5 : 0.27,
    _ => -1.0,
  };
  final c = cia[m['C']], i = cia[m['I']], a = cia[m['A']];
  if (pr < 0 || c == null || i == null || a == null) return 0;
  final iss = 1 - (1 - c) * (1 - i) * (1 - a);
  final double impact = (changed ? 7.52 * (iss - 0.029) - 3.25 * math.pow(iss - 0.02, 15) : 6.42 * iss).toDouble();
  final expl = 8.22 * av[m['AV']]! * ac[m['AC']]! * pr * ui[m['UI']]!;
  if (impact <= 0) return 0;
  return _roundUp(math.min(changed ? 1.08 * (impact + expl) : impact + expl, 10.0));
}

String cvssRating(double s) => s == 0 ? 'None' : s < 4 ? 'Low' : s < 7 ? 'Medium' : s < 9 ? 'High' : 'Critical';

const _v = 'CVSS:3.1/';

/// Base vectors for known finding ids (longest prefix wins). Hardening gaps
/// (missing ASLR, no canaries…) get no CVSS: they are not vulnerabilities by
/// themselves, they make other bugs easier to exploit.
const Map<String, String> _vectors = {
  // web — exposure
  'exp.git': '${_v}AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:L/A:N',
  'exp.svn': '${_v}AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:L/A:N',
  'exp.hg': '${_v}AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:L/A:N',
  'exp.env': '${_v}AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:N',
  'exp.aws': '${_v}AV:N/AC:L/PR:N/UI:N/S:C/C:H/I:H/A:H',
  'exp.sshkey': '${_v}AV:N/AC:L/PR:N/UI:N/S:C/C:H/I:H/A:H',
  'exp.sqldump': '${_v}AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:N/A:N',
  'exp.configbak': '${_v}AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:L/A:N',
  'exp.sourcebak': '${_v}AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:N/A:N',
  'exp.htpasswd': '${_v}AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:N/A:N',
  'exp.npmrc': '${_v}AV:N/AC:L/PR:N/UI:N/S:C/C:H/I:H/A:N',
  'exp.docker': '${_v}AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:N/A:N',
  'exp.phpinfo': '${_v}AV:N/AC:L/PR:N/UI:N/S:U/C:L/I:N/A:N',
  'exp.': '${_v}AV:N/AC:L/PR:N/UI:N/S:U/C:L/I:N/A:N',
  // web — injection & access
  'inj.sql': '${_v}AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H',
  'inj.ssti': '${_v}AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H',
  'inj.traversal': '${_v}AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:N/A:N',
  'inj.xss': '${_v}AV:N/AC:L/PR:N/UI:R/S:C/C:L/I:L/A:N',
  'access.cors': '${_v}AV:N/AC:L/PR:N/UI:R/S:U/C:H/I:N/A:N',
  'access.redirect': '${_v}AV:N/AC:L/PR:N/UI:R/S:C/C:L/I:L/A:N',
  'access.hostheader': '${_v}AV:N/AC:H/PR:N/UI:R/S:U/C:H/I:H/A:N',
  'access.login.ratelimit': '${_v}AV:N/AC:H/PR:N/UI:N/S:U/C:H/I:H/A:N',
  'access.dbadmin': '${_v}AV:N/AC:L/PR:N/UI:N/S:U/C:L/I:L/A:N',
  'access.adminlogin': '${_v}AV:N/AC:L/PR:N/UI:N/S:U/C:L/I:N/A:N',
  'api.graphql': '${_v}AV:N/AC:L/PR:N/UI:N/S:U/C:L/I:N/A:N',
  'api.docs': '${_v}AV:N/AC:L/PR:N/UI:N/S:U/C:L/I:N/A:N',
  'srv.trace': '${_v}AV:N/AC:H/PR:N/UI:R/S:U/C:L/I:N/A:N',
  'srv.': '${_v}AV:N/AC:L/PR:N/UI:N/S:U/C:L/I:N/A:N',
  // web — transport & headers
  'tls.none': '${_v}AV:N/AC:H/PR:N/UI:N/S:U/C:H/I:H/A:N',
  'tls.cert': '${_v}AV:N/AC:H/PR:N/UI:R/S:U/C:H/I:H/A:N',
  'tls.redirect': '${_v}AV:N/AC:H/PR:N/UI:R/S:U/C:L/I:L/A:N',
  'hdr.hsts': '${_v}AV:N/AC:H/PR:N/UI:R/S:U/C:L/I:L/A:N',
  'hdr.csp': '${_v}AV:N/AC:H/PR:N/UI:R/S:C/C:L/I:L/A:N',
  'hdr.frame': '${_v}AV:N/AC:L/PR:N/UI:R/S:U/C:N/I:L/A:N',
  'hdr.': '${_v}AV:N/AC:H/PR:N/UI:R/S:U/C:L/I:N/A:N',
  'cookie.': '${_v}AV:N/AC:H/PR:N/UI:R/S:U/C:L/I:L/A:N',
  'content.password': '${_v}AV:N/AC:H/PR:N/UI:R/S:U/C:H/I:N/A:N',
  'content.form.http': '${_v}AV:N/AC:H/PR:N/UI:R/S:U/C:H/I:N/A:N',
  'content.mixed.active': '${_v}AV:N/AC:H/PR:N/UI:R/S:U/C:L/I:L/A:N',
  'content.secret': '${_v}AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:L/A:N',
  'dns.takeover': '${_v}AV:N/AC:L/PR:N/UI:R/S:C/C:L/I:H/A:N',
  'dns.': '${_v}AV:N/AC:H/PR:N/UI:R/S:U/C:N/I:L/A:N',
  'wp.users': '${_v}AV:N/AC:L/PR:N/UI:N/S:U/C:L/I:N/A:N',
  'wp.xmlrpc': '${_v}AV:N/AC:L/PR:N/UI:N/S:U/C:L/I:L/A:L',
  // code
  'code.secret': '${_v}AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:L/A:N',
  'code.sqli': '${_v}AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H',
  'code.cmd': '${_v}AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H',
  'code.eval.php': '${_v}AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H',
  'code.eval': '${_v}AV:N/AC:H/PR:N/UI:R/S:U/C:L/I:L/A:N',
  'code.xss': '${_v}AV:N/AC:L/PR:N/UI:R/S:C/C:L/I:L/A:N',
  'code.deserialize': '${_v}AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H',
  'code.tls.disabled': '${_v}AV:N/AC:H/PR:N/UI:N/S:U/C:H/I:H/A:N',
  'code.crypto.password': '${_v}AV:N/AC:H/PR:N/UI:N/S:U/C:H/I:N/A:N',
  'code.jwt': '${_v}AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:N',
  'code.cors': '${_v}AV:N/AC:L/PR:N/UI:R/S:U/C:H/I:N/A:N',
  'code.debug': '${_v}AV:N/AC:L/PR:N/UI:N/S:U/C:L/I:N/A:N',
  // mobile
  'mobile.sig.none': '${_v}AV:N/AC:H/PR:N/UI:R/S:U/C:H/I:H/A:N',
  'mobile.sig.debug': '${_v}AV:N/AC:H/PR:N/UI:R/S:U/C:H/I:H/A:N',
  'mobile.sig.v1': '${_v}AV:N/AC:H/PR:N/UI:R/S:U/C:L/I:H/A:N',
  'mobile.sig.invalid': '${_v}AV:N/AC:L/PR:N/UI:R/S:U/C:H/I:H/A:H',
  'mobile.debuggable': '${_v}AV:P/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:N',
  'mobile.testonly': '${_v}AV:P/AC:L/PR:N/UI:N/S:U/C:L/I:L/A:N',
  'mobile.backup': '${_v}AV:P/AC:L/PR:N/UI:N/S:U/C:H/I:N/A:N',
  'mobile.cleartext': '${_v}AV:A/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:N',
  'mobile.tls.trustall': '${_v}AV:A/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:N',
  'mobile.nsc.usercerts': '${_v}AV:A/AC:H/PR:N/UI:R/S:U/C:H/I:H/A:N',
  'mobile.webview.sslerror': '${_v}AV:A/AC:H/PR:N/UI:R/S:U/C:H/I:H/A:N',
  'mobile.http_urls': '${_v}AV:A/AC:H/PR:N/UI:N/S:U/C:L/I:L/A:N',
  'mobile.exported.provider': '${_v}AV:L/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:N',
  'mobile.exported.components': '${_v}AV:L/AC:L/PR:N/UI:N/S:U/C:L/I:L/A:N',
  'mobile.applinks': '${_v}AV:L/AC:H/PR:N/UI:R/S:U/C:L/I:N/A:N',
  'mobile.assetlinks': '${_v}AV:L/AC:H/PR:N/UI:R/S:U/C:L/I:N/A:N',
  'mobile.webview.bridge': '${_v}AV:N/AC:H/PR:N/UI:R/S:U/C:H/I:H/A:N',
  'mobile.webview.fileaccess': '${_v}AV:L/AC:H/PR:N/UI:R/S:U/C:H/I:N/A:N',
  'mobile.webview.debug': '${_v}AV:P/AC:L/PR:N/UI:N/S:U/C:L/I:L/A:N',
  'mobile.crypto.weak': '${_v}AV:N/AC:H/PR:N/UI:N/S:U/C:H/I:N/A:N',
  'mobile.secret': '${_v}AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:L/A:N',
  'mobile.keyfiles': '${_v}AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:L/A:N',
  'mobile.firebase.open': '${_v}AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:N/A:N',
  // binary
  'bin.pe.tampered': '${_v}AV:N/AC:L/PR:N/UI:R/S:U/C:H/I:H/A:H',
  'bin.pe.unsigned': '${_v}AV:N/AC:H/PR:N/UI:R/S:U/C:L/I:H/A:N',
  'bin.pe.sig_invalid': '${_v}AV:N/AC:H/PR:N/UI:R/S:U/C:L/I:H/A:N',
};

const _byTier = {
  Severity.critical: '${_v}AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H',
  Severity.high: '${_v}AV:N/AC:L/PR:N/UI:R/S:U/C:H/I:H/A:N',
  Severity.medium: '${_v}AV:N/AC:H/PR:N/UI:R/S:U/C:L/I:L/A:N',
  Severity.low: '${_v}AV:N/AC:H/PR:N/UI:R/S:U/C:L/I:N/A:N',
};

/// The base vector for a finding ('' = not applicable).
String vectorFor(Finding f) {
  if (f.passed || f.severity == Severity.info) return '';
  if (f.cvss.isNotEmpty) return f.cvss;
  String? best;
  var bestLen = 0;
  for (final e in _vectors.entries) {
    if (f.id.startsWith(e.key) && e.key.length > bestLen) {
      best = e.value;
      bestLen = e.key.length;
    }
  }
  if (best != null) return best;
  if (f.area == CheckArea.binary || f.id.startsWith('bin.')) return ''; // hardening gap
  return _byTier[f.severity] ?? '';
}

// ── Attack chains ────────────────────────────────────────────────────────────

class ChainRule {
  const ChainRule(this.id, this.title, this.severity, this.groups, this.impact, this.fix, this.vector);
  final String id;
  final String title;
  final Severity severity;

  /// Every group must match at least one open finding (by id prefix).
  final List<List<String>> groups;
  final String impact;
  final String fix;
  final String vector;
}

const List<ChainRule> chainRules = [
  ChainRule('chain.web.session_hijack', 'Script injection can steal sessions', Severity.high, [
    ['inj.xss', 'code.xss', 'hdr.csp', 'content.mixed.active'],
    ['cookie.flags'],
  ], 'Injected script runs (no effective CSP / an XSS) and session cookies are readable by script, so one malicious link can take over accounts.',
      'Fix the XSS / add a strict Content-Security-Policy, and set HttpOnly; Secure; SameSite on session cookies.', '${_v}AV:N/AC:L/PR:N/UI:R/S:C/C:H/I:L/A:N'),
  ChainRule('chain.web.leak_to_admin', 'Leaked credentials + reachable admin login', Severity.critical, [
    ['exp.git', 'exp.env', 'exp.configbak', 'exp.sourcebak', 'exp.sqldump', 'exp.htpasswd', 'content.secret'],
    ['access.adminlogin', 'access.dbadmin', 'wp.'],
  ], 'Secrets exposed on the site can be used directly against the admin or database login that is reachable from the internet.',
      'Remove the exposed files, rotate every secret in them, then restrict the admin/database panels to a VPN or IP allow-list.', '${_v}AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H'),
  ChainRule('chain.web.downgrade', 'HTTPS downgrade exposes logins', Severity.high, [
    ['tls.redirect', 'hdr.hsts', 'tls.none'],
    ['content.password', 'content.form.http', 'cookie.flags'],
  ], 'Without enforced HTTPS, an attacker on the network can strip TLS and capture passwords or session cookies.',
      'Redirect all HTTP to HTTPS, send HSTS (max-age ≥ 1 year) and mark cookies Secure.', '${_v}AV:A/AC:H/PR:N/UI:R/S:U/C:H/I:H/A:N'),
  ChainRule('chain.web.bruteforce', 'Admin login can be brute-forced', Severity.high, [
    ['access.adminlogin', 'access.dbadmin', 'wp.users'],
    ['access.login.ratelimit'],
  ], 'A public admin login with no rate limiting lets attackers guess passwords at full speed.',
      'Add rate limiting / lockout and MFA, and restrict the admin path by IP.', '${_v}AV:N/AC:H/PR:N/UI:N/S:U/C:H/I:H/A:N'),
  ChainRule('chain.mobile.mitm', 'Network attacker can steal app tokens', Severity.high, [
    ['mobile.cleartext', 'mobile.tls.trustall', 'mobile.nsc.usercerts', 'mobile.webview.sslerror', 'mobile.http_urls'],
    ['mobile.secret', 'mobile.webview.bridge', 'mobile.firebase.open'],
  ], 'The app\'s traffic can be intercepted on public Wi-Fi, and what travels over it (tokens, keys, bridged WebView content) is valuable.',
      'Enforce HTTPS with platform certificate checks, then move secrets server-side.', '${_v}AV:A/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:N'),
  ChainRule('chain.mobile.webview_rce', 'Injected web content can call native code', Severity.critical, [
    ['mobile.webview.bridge'],
    ['mobile.cleartext', 'mobile.webview.fileaccess', 'mobile.webview.sslerror', 'mobile.tls.trustall', 'mobile.http_urls'],
  ], 'Content that an attacker can inject into the WebView (over HTTP, a forged certificate or local files) reaches the JavaScript bridge into the app.',
      'Load only HTTPS content you control in bridged WebViews, keep certificate errors fatal, and disable file access.', '${_v}AV:A/AC:H/PR:N/UI:R/S:U/C:H/I:H/A:H'),
  ChainRule('chain.mobile.local_theft', 'Device access exposes app secrets', Severity.high, [
    ['mobile.debuggable', 'mobile.backup', 'mobile.exported.provider'],
    ['mobile.secret', 'mobile.keyfiles'],
  ], 'Someone with the phone (or another app, via an open provider) can pull the app\'s data, which contains credentials.',
      'Turn off debuggable/backup, protect providers, and keep secrets out of the app (Android Keystore + server tokens).', '${_v}AV:P/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:N'),
  ChainRule('chain.mobile.backend', 'App secrets open the backend', Severity.critical, [
    ['mobile.secret', 'mobile.keyfiles'],
    ['mobile.firebase.open', 'mobile.secret.dburl', 'mobile.secret.aws'],
  ], 'Credentials extracted from the APK give direct access to the backend data store.',
      'Close the database rules, rotate the leaked keys and issue per-user tokens from your server.', '${_v}AV:N/AC:L/PR:N/UI:N/S:C/C:H/I:H/A:N'),
  ChainRule('chain.bin.memory', 'Overflow-prone code without exploit mitigations', Severity.high, [
    ['bin.unsafe_funcs'],
    ['bin.pe.aslr', 'bin.pe.relocs', 'bin.pe.dep', 'bin.elf.nx', 'bin.elf.pie', 'bin.wx', 'bin.elf.canary'],
  ], 'Unbounded string functions make buffer overflows likely, and the missing mitigations make them straightforward to turn into code execution.',
      'Enable ASLR/DEP/CFG (or PIE/NX/canaries) first — it is a build flag — then replace the unsafe calls.', '${_v}AV:L/AC:H/PR:N/UI:R/S:U/C:H/I:H/A:H'),
];

/// Builds attack-chain findings from the open findings in [list]. Pure.
List<Finding> correlate(List<Finding> list, {ScanLevel level = ScanLevel.quick}) {
  final open = list.where((f) => !f.passed && f.severity != Severity.info && f.area != CheckArea.chain).toList();
  final out = <Finding>[];
  for (final c in chainRules) {
    final links = <Finding>[];
    var ok = true;
    for (final g in c.groups) {
      final hit = open.where((f) => g.any(f.id.startsWith)).toList();
      if (hit.isEmpty) {
        ok = false;
        break;
      }
      links.addAll(hit.take(3));
    }
    if (!ok) continue;
    out.add(Finding(
      id: c.id,
      title: c.title,
      severity: c.severity,
      area: CheckArea.chain,
      evidence: links.map((f) => '• [${f.severity.label}] ${f.title}').toSet().join('\n'),
      location: 'Combination of ${links.length} findings',
      impact: c.impact,
      fixSummary: c.fix,
      refs: const ['Attack chain'],
      confidence: 'firm',
      level: level,
      cvss: c.vector,
    ));
  }
  return out;
}

/// Merge findings with the same id + location (keeps the worst severity and
/// all evidence). Pure.
List<Finding> deduplicate(List<Finding> list) {
  final byKey = <String, Finding>{};
  final order = <String>[];
  for (final f in list) {
    final key = '${f.id}|${f.location}|${f.passed}';
    final prev = byKey[key];
    if (prev == null) {
      byKey[key] = f;
      order.add(key);
      continue;
    }
    final evidence = {...prev.evidence.split('\n'), ...f.evidence.split('\n')}.where((e) => e.isNotEmpty).join('\n');
    byKey[key] = prev.copyWith(severity: f.severity.index < prev.severity.index ? f.severity : prev.severity, evidence: evidence);
  }
  return [for (final k in order) byKey[k]!];
}

class CyberPipeline {
  /// normalize → dedupe → CVSS → chains. Returns a new list. Pure.
  static List<Finding> process(List<Finding> input, {ScanLevel level = ScanLevel.quick}) {
    final base = deduplicate(input.where((f) => f.area != CheckArea.chain).toList());
    final scored = [
      for (final f in base)
        () {
          final v = vectorFor(f);
          if (v.isEmpty) return f;
          final s = cvssScore(v);
          final tag = 'CVSS ${s.toStringAsFixed(1)}';
          return f.copyWith(cvss: v, refs: f.refs.any((r) => r.startsWith('CVSS ')) ? f.refs : [...f.refs, tag]);
        }(),
    ];
    final chains = correlate(scored, level: level).map((c) => c.copyWith(refs: [...c.refs, 'CVSS ${cvssScore(c.cvss).toStringAsFixed(1)}']));
    return [...scored, ...chains];
  }

  /// Runs [process] on a report in place.
  static void apply(ScanReport r) {
    final out = process(r.findings, level: r.level);
    r.findings
      ..clear()
      ..addAll(out);
  }
}

// ── Triage ───────────────────────────────────────────────────────────────────

enum TriageStatus { open, confirmed, falsePositive, acceptedRisk, fixed }

extension TriageStatusX on TriageStatus {
  String get label => const ['Open', 'Confirmed', 'False positive', 'Accepted risk', 'Fixed'][index];
}

class TriageEntry {
  TriageEntry(this.status, this.note, this.at);
  final TriageStatus status;
  final String note;
  final DateTime at;
}

/// Per-target triage decisions, kept on this device only (never sent).
class CyberTriage {
  /// Android: the app's private support folder, set by [init] (path_provider)
  /// before the first report opens. Tests use the system temp folder.
  static String? _base;

  static Future<void> init() async {
    if (_base != null) return;
    try {
      _base = (await getApplicationSupportDirectory()).path;
      _cache = null;
    } catch (_) {}
  }

  static File get _file {
    final sep = Platform.pathSeparator;
    return File('${_base ?? Directory.systemTemp.path}${sep}cyber${sep}triage.json');
  }

  static Map<String, TriageEntry>? _cache;

  static String key(ScanReport r, Finding f) => '${r.displayName}|${f.id}';

  static Map<String, TriageEntry> _all() {
    if (_cache != null) return _cache!;
    final m = <String, TriageEntry>{};
    try {
      if (_file.existsSync()) {
        final j = jsonDecode(_file.readAsStringSync()) as Map;
        j.forEach((k, v) {
          if (v is Map) {
            m['$k'] = TriageEntry(
              TriageStatus.values.firstWhere((s) => s.name == v['status'], orElse: () => TriageStatus.open),
              '${v['note'] ?? ''}',
              DateTime.tryParse('${v['at']}') ?? DateTime.now(),
            );
          }
        });
      }
    } catch (_) {}
    return _cache = m;
  }

  static TriageEntry? get(ScanReport r, Finding f) => _all()[key(r, f)];

  /// True when the finding was marked fixed before this scan but is still here.
  static bool isRegression(ScanReport r, Finding f) {
    final e = get(r, f);
    return e != null && e.status == TriageStatus.fixed && r.started.isAfter(e.at);
  }

  static void set(ScanReport r, Finding f, TriageStatus s, {String note = ''}) {
    final all = _all();
    if (s == TriageStatus.open && note.isEmpty) {
      all.remove(key(r, f));
    } else {
      all[key(r, f)] = TriageEntry(s, note, DateTime.now());
    }
    try {
      _file.parent.createSync(recursive: true);
      _file.writeAsStringSync(jsonEncode({
        for (final e in all.entries) e.key: {'status': e.value.status.name, 'note': e.value.note, 'at': e.value.at.toIso8601String()}
      }));
    } catch (_) {}
  }
}

// ── SARIF ────────────────────────────────────────────────────────────────────

/// SARIF 2.1.0 (GitHub code scanning, Azure DevOps, VS Code SARIF viewer…).
String toSarif(ScanReport r) {
  final issues = r.findings.where((f) => !f.passed).toList();
  final rules = <String, Map<String, Object?>>{};
  for (final f in issues) {
    final score = f.cvss.isEmpty ? null : cvssScore(f.cvss);
    rules.putIfAbsent(f.id, () => {
          'id': f.id,
          'name': f.id.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_'),
          'shortDescription': {'text': f.title},
          'fullDescription': {'text': f.impact.isEmpty ? f.title : f.impact},
          'help': {'text': f.fixSummary.isEmpty ? f.title : f.fixSummary},
          'defaultConfiguration': {'level': _sarifLevel(f.severity)},
          'properties': {
            'tags': ['security', f.area.label, ...f.refs.where((x) => x.startsWith('CWE-') || x.startsWith('OWASP'))],
            if (score != null) 'security-severity': score.toStringAsFixed(1),
          },
        });
  }
  final results = <Map<String, Object?>>[];
  for (final f in issues) {
    final loc = RegExp(r'^(.+?):(\d+)\b').firstMatch(f.location);
    results.add({
      'ruleId': f.id,
      'level': _sarifLevel(f.severity),
      'message': {'text': f.evidence.isEmpty ? f.title : '${f.title}\n${f.evidence.split('\n').take(5).join('\n')}'},
      'locations': [
        if (loc != null && !loc[1]!.contains('://'))
          {
            'physicalLocation': {
              'artifactLocation': {'uri': loc[1]!.replaceFirst(RegExp(r'^/'), '')},
              'region': {'startLine': int.parse(loc[2]!)},
            }
          }
        else
          {
            'logicalLocations': [
              {'name': f.location.isEmpty ? r.displayName : f.location, 'kind': 'resource'}
            ]
          }
      ],
      'partialFingerprints': {'novaCyber/v1': '${r.displayName}|${f.id}|${f.location}'},
      'properties': {
        'severity': f.severity.name,
        'confidence': f.confidence,
        if (f.cvss.isNotEmpty) 'cvssVector': f.cvss,
        if (f.cvss.isNotEmpty) 'cvssScore': cvssScore(f.cvss),
      },
    });
  }
  return const JsonEncoder.withIndent('  ').convert({
    r'$schema': 'https://json.schemastore.org/sarif-2.1.0.json',
    'version': '2.1.0',
    'runs': [
      {
        'tool': {
          'driver': {'name': 'NOVA Cyber', 'version': '2.1.0', 'rules': rules.values.toList()}
        },
        'automationDetails': {'id': 'nova-cyber/${r.level.name}/${r.displayName}'},
        'invocations': [
          {
            'executionSuccessful': !r.stoppedEarly,
            'startTimeUtc': r.started.toUtc().toIso8601String(),
            if (r.finished != null) 'endTimeUtc': r.finished!.toUtc().toIso8601String(),
          }
        ],
        'results': results,
      }
    ],
  });
}

String _sarifLevel(Severity s) => switch (s) {
      Severity.critical || Severity.high => 'error',
      Severity.medium => 'warning',
      Severity.low || Severity.info => 'note',
    };
