// lib/features/cyber/engine/cyber_models.dart
//
// NOVA Cyber — findings, reports and scoring.

import 'dart:convert';

enum Severity { critical, high, medium, low, info }

extension SeverityX on Severity {
  String get label => const ['Critical', 'High', 'Medium', 'Low', 'Info'][index];

  /// Points taken off the 100-point score for one finding.
  int get weight => const [30, 15, 6, 2, 0][index];

  static Severity parse(String s) =>
      Severity.values.firstWhere((v) => v.name == s, orElse: () => Severity.info);
}

enum CheckArea { transport, headers, cookies, content, dependencies, dns, exposure, injection, access, server, code }

extension CheckAreaX on CheckArea {
  String get label => const [
        'Transport & TLS',
        'Security headers',
        'Cookies & sessions',
        'Page content',
        'Libraries & CVEs',
        'DNS & email',
        'Exposed files & services',
        'Injection',
        'Access control',
        'Server configuration',
        'Source code',
      ][index];
}

/// Which scan level found it.
enum ScanLevel { quick, full, code }

/// One weakness (or a passed check, when [passed] is true).
class Finding {
  Finding({
    required this.id,
    required this.title,
    required this.severity,
    required this.area,
    this.passed = false,
    this.evidence = '',
    this.location = '',
    this.impact = '',
    this.fixSummary = '',
    this.refs = const [],
    this.confidence = 'firm',
    this.level = ScanLevel.quick,
    this.recheck,
  });

  /// Stable id (used for fixes and re-checks), e.g. "hdr.csp.unsafe_inline".
  final String id;
  final String title;
  final Severity severity;
  final CheckArea area;
  final bool passed;

  /// What was observed (request/response excerpt, header value…). Secrets
  /// are always redacted before they get here.
  final String evidence;

  /// URL / file:line where it was found.
  final String location;

  /// Why it matters (what an attacker can do).
  final String impact;

  /// One-line fix; full snippets come from the fix library by [id].
  final String fixSummary;

  /// CWE / OWASP / CVE references.
  final List<String> refs;

  /// "confirmed" (proved), "firm" (strong signal) or "tentative".
  final String confidence;
  final ScanLevel level;

  /// Re-runs just this check (set by the engine; not saved).
  final Future<List<Finding>> Function()? recheck;

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'severity': severity.name,
        'area': area.name,
        'passed': passed,
        'evidence': evidence,
        'location': location,
        'impact': impact,
        'fix': fixSummary,
        'refs': refs,
        'confidence': confidence,
        'level': level.name,
      };

  static Finding fromJson(Map<String, dynamic> j) => Finding(
        id: '${j['id']}',
        title: '${j['title']}',
        severity: SeverityX.parse('${j['severity']}'),
        area: CheckArea.values.firstWhere((a) => a.name == j['area'], orElse: () => CheckArea.server),
        passed: j['passed'] == true,
        evidence: '${j['evidence'] ?? ''}',
        location: '${j['location'] ?? ''}',
        impact: '${j['impact'] ?? ''}',
        fixSummary: '${j['fix'] ?? ''}',
        refs: [for (final r in (j['refs'] as List? ?? const [])) '$r'],
        confidence: '${j['confidence'] ?? 'firm'}',
        level: ScanLevel.values.firstWhere((l) => l.name == j['level'], orElse: () => ScanLevel.quick),
      );
}

/// What the site runs on (decides which fix snippets are shown first).
class TechProfile {
  final Set<String> stack = {}; // nginx, apache, iis, litespeed, cloudflare, php, express, nextjs, vercel, netlify, wordpress…
  final Map<String, String> versions = {}; // product → version
  String server = '';

  String get primary {
    for (final s in const ['cloudflare', 'vercel', 'netlify', 'nginx', 'apache', 'litespeed', 'iis']) {
      if (stack.contains(s)) return s;
    }
    if (stack.contains('express') || stack.contains('nextjs')) return 'express';
    if (stack.contains('php')) return 'php';
    return 'nginx';
  }

  Map<String, Object?> toJson() => {'stack': stack.toList(), 'versions': versions, 'server': server};
}

class ScanReport {
  ScanReport({required this.target, required this.level, required this.started});

  final String target;
  final ScanLevel level;
  final DateTime started;
  DateTime? finished;
  final List<Finding> findings = [];
  final TechProfile tech = TechProfile();
  int requests = 0;
  bool stoppedEarly = false;
  String stopReason = '';

  List<Finding> get issues => findings.where((f) => !f.passed && f.severity != Severity.info).toList()
    ..sort((a, b) => a.severity.index.compareTo(b.severity.index));
  List<Finding> get notes => findings.where((f) => !f.passed && f.severity == Severity.info).toList();
  List<Finding> get passes => findings.where((f) => f.passed).toList();

  int count(Severity s) => findings.where((f) => !f.passed && f.severity == s).length;

  /// 100 minus weighted findings (each finding id counted once), floored at 0.
  /// Any critical caps the score at 39; any high caps it at 69.
  int get score {
    final seen = <String>{};
    var s = 100;
    for (final f in findings) {
      if (f.passed || !seen.add(f.id)) continue;
      s -= f.severity.weight;
    }
    if (count(Severity.critical) > 0 && s > 39) s = 39;
    if (count(Severity.high) > 0 && s > 69) s = 69;
    return s.clamp(0, 100);
  }

  String get grade {
    final s = score;
    if (s >= 95) return 'A+';
    if (s >= 85) return 'A';
    if (s >= 70) return 'B';
    if (s >= 55) return 'C';
    if (s >= 40) return 'D';
    return 'F';
  }

  /// Score lost per area (for the breakdown).
  Map<CheckArea, int> get lostByArea {
    final m = <CheckArea, int>{};
    final seen = <String>{};
    for (final f in findings) {
      if (f.passed || !seen.add(f.id)) continue;
      m[f.area] = (m[f.area] ?? 0) + f.severity.weight;
    }
    return m;
  }

  Map<String, Object?> toJson() => {
        'target': target,
        'level': level.name,
        'started': started.toIso8601String(),
        'finished': finished?.toIso8601String(),
        'score': score,
        'grade': grade,
        'requests': requests,
        'stopped': stoppedEarly,
        'stopReason': stopReason,
        'tech': tech.toJson(),
        'findings': [for (final f in findings) f.toJson()],
      };

  static ScanReport fromJson(Map<String, dynamic> j) {
    final r = ScanReport(
      target: '${j['target']}',
      level: ScanLevel.values.firstWhere((l) => l.name == j['level'], orElse: () => ScanLevel.quick),
      started: DateTime.tryParse('${j['started']}') ?? DateTime.now(),
    );
    r.finished = DateTime.tryParse('${j['finished'] ?? ''}');
    r.requests = (j['requests'] as num?)?.toInt() ?? 0;
    r.stoppedEarly = j['stopped'] == true;
    r.stopReason = '${j['stopReason'] ?? ''}';
    final tech = j['tech'];
    if (tech is Map) {
      r.tech.stack.addAll([for (final s in (tech['stack'] as List? ?? const [])) '$s']);
      r.tech.server = '${tech['server'] ?? ''}';
      final v = tech['versions'];
      if (v is Map) v.forEach((k, val) => r.tech.versions['$k'] = '$val');
    }
    for (final f in (j['findings'] as List? ?? const [])) {
      if (f is Map) r.findings.add(Finding.fromJson(Map<String, dynamic>.from(f)));
    }
    return r;
  }

  String toJsonString() => jsonEncode(toJson());
}

/// Hides secret values in evidence: keeps the key name and the first 2
/// characters only ("DB_PASSWORD=se…[redacted 14 chars]").
String redactSecrets(String text) {
  var t = text.replaceAllMapped(
    RegExp(r'''^(\s*[A-Za-z_][A-Za-z0-9_.-]*\s*[=:]\s*)(["']?)([^\r\n"']{3,})\2''', multiLine: true),
    (m) => '${m[1]}${m[2]}${m[3]!.substring(0, 2)}…[redacted ${m[3]!.length - 2} chars]${m[2]}',
  );
  t = t.replaceAllMapped(RegExp(r'(AKIA|ASIA)[A-Z0-9]{16}'), (m) => '${m[1]}…[redacted]');
  t = t.replaceAllMapped(RegExp(r'-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----'),
      (_) => '[private key redacted]');
  return t;
}
