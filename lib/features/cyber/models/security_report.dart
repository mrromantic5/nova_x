// lib/features/cyber/models/security_report.dart

enum Severity    { info, low, medium, high, critical }
enum CheckStatus { pass, warn, fail, info }
enum CheckCategory {
  reconnaissance, tls, headers, injection, authentication,
  disclosure, dns, cookies, content, waf,
}

class SecurityCheck {
  final String        id;
  final String        name;
  final CheckStatus   status;
  final Severity      severity;
  final CheckCategory category;
  final String        description;
  final String        detail;
  final String        recommendation;
  final String?       evidence;       // raw payload / response snippet
  final String?       cweId;          // CWE reference  e.g. "CWE-89"
  final String?       owaspRef;       // e.g. "A03:2021 – Injection"
  final int           score;
  final int           maxScore;

  const SecurityCheck({
    required this.id,
    required this.name,
    required this.status,
    required this.severity,
    required this.category,
    required this.description,
    required this.detail,
    required this.recommendation,
    this.evidence,
    this.cweId,
    this.owaspRef,
    required this.score,
    required this.maxScore,
  });
}

class TechStack {
  final String? server;
  final String? language;
  final String? framework;
  final String? cms;
  final String? cdn;
  final String? waf;
  final List<String> libraries;
  const TechStack({
    this.server, this.language, this.framework,
    this.cms, this.cdn, this.waf,
    this.libraries = const [],
  });
}

class DnsRecord {
  final String type;
  final String value;
  const DnsRecord(this.type, this.value);
}

class SecurityReport {
  final String             url;
  final String             domain;
  final int                score;
  final String             grade;
  final Severity           overallSeverity;
  final bool               isHttps;
  final List<SecurityCheck> checks;
  final Map<String, String> responseHeaders;
  final List<String>        rawCookies;
  final List<String>        scanLog;          // live progress messages
  final TechStack           techStack;
  final List<DnsRecord>     dnsRecords;
  final List<String>        exposedPaths;     // sensitive files found
  final List<String>        recommendations;
  final DateTime            analyzedAt;
  final int                 durationMs;
  final bool                scanSucceeded;
  final String?             errorMessage;
  final int                 httpStatus;

  const SecurityReport({
    required this.url,
    required this.domain,
    required this.score,
    required this.grade,
    required this.overallSeverity,
    required this.isHttps,
    required this.checks,
    required this.responseHeaders,
    required this.rawCookies,
    required this.scanLog,
    required this.techStack,
    required this.dnsRecords,
    required this.exposedPaths,
    required this.recommendations,
    required this.analyzedAt,
    required this.durationMs,
    required this.scanSucceeded,
    this.errorMessage,
    required this.httpStatus,
  });

  int get passCount     => checks.where((c) => c.status == CheckStatus.pass).length;
  int get warnCount     => checks.where((c) => c.status == CheckStatus.warn).length;
  int get failCount     => checks.where((c) => c.status == CheckStatus.fail).length;
  int get criticalCount => checks.where((c) => c.severity == Severity.critical).length;
  int get highCount     => checks.where((c) => c.severity == Severity.high).length;
  int get totalChecks   => checks.length;
}
