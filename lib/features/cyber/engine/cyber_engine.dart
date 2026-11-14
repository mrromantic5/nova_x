// lib/features/cyber/engine/cyber_engine.dart
//
// NOVA Cyber — runs a scan, keeps history on this device, writes reports.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'checks_full.dart';
import 'checks_quick.dart';
import 'cyber_api.dart';
import 'cyber_context.dart';
import 'cyber_fixes.dart';
import 'cyber_http.dart';
import 'cyber_models.dart';

/// Hosts that are the user's own machine (full scan without server proof).
bool isOwnMachine(String host) {
  final h = host.toLowerCase();
  return h == 'localhost' || h.endsWith('.localhost') || h == '127.0.0.1' || h == '::1' || h == '[::1]' || h.startsWith('127.');
}

/// Private network addresses (full scan only after the user confirms it's their device).
bool isPrivateNetwork(String host) {
  final ip = InternetAddress.tryParse(host.replaceAll(RegExp(r'^\[|\]$'), ''));
  if (ip == null) return host.endsWith('.local') || host.endsWith('.lan') || host.endsWith('.test') || host.endsWith('.internal');
  if (ip.type == InternetAddressType.IPv4) {
    final b = ip.rawAddress;
    return b[0] == 10 || (b[0] == 172 && b[1] >= 16 && b[1] <= 31) || (b[0] == 192 && b[1] == 168);
  }
  return ip.address.toLowerCase().startsWith('fd') || ip.address.toLowerCase().startsWith('fc');
}

/// "Example.com/x" → Uri(https://example.com/). Null when invalid.
Uri? normalizeTarget(String input) {
  var s = input.trim();
  if (s.isEmpty) return null;
  if (!RegExp(r'^[a-z][a-z0-9+.-]*://', caseSensitive: false).hasMatch(s)) s = 'https://$s';
  final u = Uri.tryParse(s);
  if (u == null || u.host.isEmpty || !(u.scheme == 'https' || u.scheme == 'http')) return null;
  return Uri(scheme: u.scheme, host: u.host.toLowerCase(), port: u.hasPort ? u.port : null, path: '/');
}

class CyberEngine {
  CyberEngine._();
  static final CyberEngine instance = CyberEngine._();

  CyberHttp? _http;
  bool get running => _http != null;

  void stop() => _http?.cancel();

  /// Runs a scan. [pass] is required for a full scan of a public site.
  Future<ScanReport> scan(
    Uri target, {
    required ScanLevel level,
    ScanPass? pass,
    FullOptions options = const FullOptions(),
    void Function(String line)? onLog,
    void Function(Finding f)? onFinding,
    void Function(String phase, double progress)? onPhase,
  }) async {
    if (level == ScanLevel.full && pass == null && !isOwnMachine(target.host) && !isPrivateNetwork(target.host)) {
      throw StateError('A full scan needs a verified site.');
    }
    final report = ScanReport(target: target.toString(), level: level, started: DateTime.now());
    final http = CyberHttp(maxPerSecond: level == ScanLevel.full ? 6 : 8, budget: level == ScanLevel.full ? 900 : 120, onLog: onLog);
    _http = http;
    final ctx = ScanContext(http: http, base: target, report: report, onLog: onLog, onFinding: onFinding);
    void phase(String p, double v) {
      onPhase?.call(p, v);
      onLog?.call('— $p');
    }

    try {
      phase('Connecting', 0.03);
      var home = await http.get(target);
      if (home.status == 0 && target.scheme == 'https') {
        final httpUrl = target.replace(scheme: 'http');
        final alt = await http.get(httpUrl);
        if (alt.status != 0) {
          ctx.base = httpUrl;
          home = alt;
        }
      }
      if (home.status == 0) {
        final cert = (home.error ?? '').contains('CERTIFICATE') || (home.error ?? '').contains('HandshakeException');
        if (cert) {
          report.findings.add(Finding(
            id: 'tls.cert.invalid',
            title: 'TLS certificate is not trusted',
            severity: Severity.critical,
            area: CheckArea.transport,
            evidence: home.error ?? '',
            impact: 'Browsers block the site with a security warning; users who click through can be intercepted.',
            fixSummary: 'Install a valid certificate for this exact host name (including www) with the full chain.',
            refs: const ['CWE-295'],
            confidence: 'confirmed',
          ));
        }
        throw CyberStopped('Couldn\'t open ${target.host}: ${home.error ?? 'no answer'}.');
      }
      // Follow the site's own redirect to its canonical address (same site only).
      for (var i = 0; i < 3 && home.status >= 300 && home.status < 400 && home.location != null; i++) {
        final next = home.url.resolve(home.location!);
        if (next.host != ctx.base.host && registrableDomain(next.host) != registrableDomain(ctx.base.host)) break;
        if (level == ScanLevel.full && pass != null && next.host != ctx.base.host && !_covered(pass, next.host)) break;
        ctx.base = Uri(scheme: next.scheme, host: next.host, port: next.hasPort ? next.port : null, path: '/');
        home = await http.get(next);
      }
      ctx.home = home;
      final quick = QuickChecks(ctx);
      phase('Transport & TLS', 0.1);
      await quick.transport();
      phase('Security headers', 0.2);
      quick.headers();
      quick.cookies(home);
      phase('Page content', 0.28);
      quick.content();
      phase('Libraries & known vulnerabilities', 0.36);
      await quick.libraries();
      phase('DNS & email security', 0.46);
      await quick.dns();
      await quick.securityTxt();
      if (level == ScanLevel.full) {
        final full = FullChecks(ctx, quick, options);
        phase('Exposed files', 0.52);
        await full.notFoundBaseline();
        await full.crawl();
        await full.exposedFiles();
        await full.directoryListing();
        phase('Admin & API surfaces', 0.64);
        await full.adminSurfaces();
        await full.apiSurfaces();
        await full.sourceMaps();
        phase('Server configuration', 0.7);
        await full.methods();
        await full.cors();
        await full.hostHeader();
        phase('Injection tests', 0.76);
        await full.parameters();
        if (report.tech.stack.contains('wordpress')) {
          phase('WordPress', 0.86);
          await full.wordpress();
        }
        if (options.loginRateLimit) {
          phase('Login protection', 0.89);
          await full.loginRateLimit();
        }
        if (options.ports) {
          phase('Network services', 0.92);
          await full.ports();
        }
        if (options.subdomains) {
          phase('Subdomains', 0.96);
          await full.subdomains();
        }
      }
      phase('Done', 1);
    } on CyberStopped catch (e) {
      report.stoppedEarly = true;
      report.stopReason = e.reason;
      onLog?.call('Stopped: ${e.reason}');
    } finally {
      report.requests = http.sent;
      report.finished = DateTime.now();
      http.close();
      _http = null;
    }
    await CyberHistory.add(report);
    return report;
  }

  static bool _covered(ScanPass pass, String host) => host == pass.host || host.endsWith('.${registrableDomain(pass.host)}');
}

// ── History (this device only) ───────────────────────────────────────────────

class CyberHistory {
  // Android (3.13.0): the app's private support folder (path_provider),
  // instead of %LOCALAPPDATA% on PC. Never shared with other apps.
  static Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}cyber${Platform.pathSeparator}history.json');
  }

  static List<ScanReport>? _cache;

  static Future<List<ScanReport>> all() async {
    if (_cache != null) return _cache!;
    try {
      final file = await _file();
      if (await file.exists()) {
        final j = jsonDecode(await file.readAsString());
        _cache = [for (final r in (j as List)) ScanReport.fromJson(Map<String, dynamic>.from(r as Map))];
        return _cache!;
      }
    } catch (_) {}
    return _cache = [];
  }

  static Future<void> add(ScanReport r) async {
    final list = await all();
    list.insert(0, r);
    if (list.length > 60) list.removeRange(60, list.length);
    await _save(list);
  }

  static Future<void> clear() async {
    _cache = [];
    await _save(const []);
  }

  static Future<void> _save(List<ScanReport> list) async {
    try {
      final file = await _file();
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode([for (final r in list) r.toJson()]));
    } catch (_) {}
  }

  /// Earlier reports for the same target (newest first).
  static Future<List<ScanReport>> forTarget(String target) async =>
      (await all()).where((r) => Uri.tryParse(r.target)?.host == Uri.tryParse(target)?.host).toList();
}

// ── Reports ──────────────────────────────────────────────────────────────────

class CyberReportWriter {
  static String markdown(ScanReport r) {
    final b = StringBuffer()
      ..writeln('# NOVA Cyber security report')
      ..writeln()
      ..writeln('| | |')
      ..writeln('|---|---|')
      ..writeln('| Target | ${r.target} |')
      ..writeln('| Scan | ${r.level == ScanLevel.full ? 'Full (ownership verified)' : 'Quick (read-only)'} |')
      ..writeln('| Date | ${r.started.toUtc().toIso8601String()} |')
      ..writeln('| Score | **${r.score}/100 (${r.grade})** |')
      ..writeln('| Findings | ${Severity.values.where((s) => s != Severity.info).map((s) => '${r.count(s)} ${s.label.toLowerCase()}').join(' · ')} |')
      ..writeln('| Requests | ${r.requests} |')
      ..writeln('| Platform | ${r.tech.stack.join(', ')} |');
    if (r.stoppedEarly) b.writeln('\n> Scan stopped early: ${r.stopReason}');
    b.writeln('\n## Findings\n');
    for (final f in r.issues) {
      b
        ..writeln('### [${f.severity.label}] ${f.title}')
        ..writeln()
        ..writeln('*${f.area.label}* · confidence: ${f.confidence}${f.refs.isEmpty ? '' : ' · ${f.refs.join(', ')}'}')
        ..writeln();
      if (f.location.isNotEmpty) b.writeln('**Where:** ${f.location}\n');
      b
        ..writeln('**Why it matters:** ${f.impact}\n')
        ..writeln('**Evidence:**\n\n```\n${f.evidence}\n```\n')
        ..writeln('**Fix:** ${f.fixSummary}\n');
      final g = fixFor(f.id);
      if (g != null) {
        for (final s in g.steps) {
          b.writeln('- $s');
        }
        for (final p in orderedPlatforms(g, r.tech.primary, r.tech.stack).take(2)) {
          b.writeln('\n${platformLabels[p] ?? p}:\n\n```\n${g.snippets[p]}\n```');
        }
        b.writeln();
      }
    }
    if (r.notes.isNotEmpty) {
      b.writeln('## Notes\n');
      for (final f in r.notes) {
        b.writeln('- **${f.title}** — ${f.fixSummary}');
      }
    }
    if (r.passes.isNotEmpty) {
      b.writeln('\n## Passed checks\n');
      for (final f in r.passes) {
        b.writeln('- ${f.title}');
      }
    }
    b.writeln('\n---\nGenerated by NOVA Cyber (NOVA X). Full scans run only on sites whose ownership was verified.');
    return b.toString();
  }

  static String html(ScanReport r) {
    String esc(String s) => const HtmlEscape().convert(s);
    const colors = {'critical': '#b42318', 'high': '#c4320a', 'medium': '#b54708', 'low': '#475467', 'info': '#667085'};
    final rows = StringBuffer();
    for (final f in r.issues) {
      rows.write('<section class="f"><div class="h"><span class="sev" style="background:${colors[f.severity.name]}">${f.severity.label}</span>'
          '<h3>${esc(f.title)}</h3></div><p class="meta">${esc(f.area.label)} · confidence ${esc(f.confidence)}${f.refs.isEmpty ? '' : ' · ${esc(f.refs.join(', '))}'}</p>'
          '${f.location.isEmpty ? '' : '<p><b>Where:</b> ${esc(f.location)}</p>'}<p><b>Why it matters:</b> ${esc(f.impact)}</p>'
          '<pre>${esc(f.evidence)}</pre><p><b>Fix:</b> ${esc(f.fixSummary)}</p>');
      final g = fixFor(f.id);
      if (g != null) {
        rows.write('<ul>${g.steps.map((s) => '<li>${esc(s)}</li>').join()}</ul>');
        for (final p in orderedPlatforms(g, r.tech.primary, r.tech.stack).take(2)) {
          rows.write('<p class="meta">${esc(platformLabels[p] ?? p)}</p><pre>${esc(g.snippets[p]!)}</pre>');
        }
      }
      rows.write('</section>');
    }
    return '''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>NOVA Cyber report — ${esc(Uri.tryParse(r.target)?.host ?? r.target)}</title>
<style>
body{font:15px/1.55 -apple-system,Segoe UI,Roboto,sans-serif;color:#101828;max-width:920px;margin:40px auto;padding:0 20px;background:#fff}
h1{font-size:26px;margin:0 0 4px}.sub{color:#667085;margin:0 0 24px}
.score{display:flex;gap:24px;align-items:center;border:1px solid #eaecf0;border-radius:12px;padding:20px;margin-bottom:28px}
.big{font-size:44px;font-weight:700}.grade{font-size:20px;font-weight:600;color:#475467}
.counts span{display:inline-block;margin-right:14px;color:#475467}
.f{border:1px solid #eaecf0;border-radius:12px;padding:16px 18px;margin:14px 0}.h{display:flex;gap:10px;align-items:center}
.h h3{margin:0;font-size:16px}.sev{color:#fff;font-size:12px;font-weight:600;border-radius:6px;padding:2px 8px}
.meta{color:#667085;font-size:13px;margin:6px 0}pre{background:#f9fafb;border:1px solid #eaecf0;border-radius:8px;padding:10px;white-space:pre-wrap;word-break:break-word;font:12.5px/1.5 Consolas,monospace}
footer{color:#98a2b3;font-size:12px;margin-top:40px}
</style></head><body>
<h1>Security report</h1><p class="sub">${esc(r.target)} · ${r.level == ScanLevel.full ? 'Full scan (ownership verified)' : 'Quick scan (read-only)'} · ${esc(r.started.toUtc().toIso8601String())}</p>
<div class="score"><div><div class="big">${r.score}</div><div class="grade">Grade ${r.grade}</div></div>
<div class="counts">${Severity.values.where((s) => s != Severity.info).map((s) => '<span><b>${r.count(s)}</b> ${s.label.toLowerCase()}</span>').join()}<br><span>${r.requests} requests · ${esc(r.tech.stack.join(', '))}</span></div></div>
${r.stoppedEarly ? '<p><b>Stopped early:</b> ${esc(r.stopReason)}</p>' : ''}
$rows
${r.passes.isEmpty ? '' : '<h2>Passed checks</h2><ul>${r.passes.map((f) => '<li>${esc(f.title)}</li>').join()}</ul>'}
<footer>Generated by NOVA Cyber (NOVA X).</footer></body></html>''';
  }
}
