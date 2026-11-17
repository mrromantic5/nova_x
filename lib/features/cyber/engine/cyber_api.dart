// lib/features/cyber/engine/cyber_api.dart
//
// NOVA Cyber — ownership verification through the NOVA X server
// (api.browser…/api/v1/cyber/*). The server creates the code, checks the
// proof itself and issues a short-lived pass for each full scan.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../../core/services/api_service.dart';

class CyberApiError implements Exception {
  CyberApiError(this.message, {this.status = 0});
  final String message;
  final int status;
  @override
  String toString() => message;
}

class VerifiedSite {
  VerifiedSite({required this.host, required this.method, required this.scope, this.verifiedAt, this.expiresAt, this.expired = false});
  final String host;
  final String method; // dns | file | meta
  final String scope; // domain | host
  final DateTime? verifiedAt;
  final DateTime? expiresAt;
  final bool expired;

  bool covers(String target) => target == host || (scope == 'domain' && target.endsWith('.$host'));

  factory VerifiedSite.fromJson(Map<String, dynamic> j) => VerifiedSite(
        host: '${j['host']}',
        method: '${j['method']}',
        scope: '${j['scope']}',
        verifiedAt: DateTime.tryParse('${j['verified_at'] ?? ''}'),
        expiresAt: DateTime.tryParse('${j['expires_at'] ?? ''}'),
        expired: j['expired'] == true,
      );
}

class Challenge {
  Challenge({required this.host, required this.token, required this.methods, this.expiresAt});
  final String host;
  final String token;
  final Map<String, Map<String, String>> methods;
  final DateTime? expiresAt;
}

class ScanPass {
  ScanPass({required this.host, required this.pass, required this.expiresAt, this.scansLeft});
  final String host;
  final String pass;
  final DateTime expiresAt;
  final int? scansLeft;
}

class CyberApi {
  CyberApi._();

  static Future<Map<String, dynamic>> _call(String method, String path, [Map<String, Object?>? body]) async {
    final token = await ApiService.getToken();
    if (token == null || token.isEmpty) {
      throw CyberApiError('Sign in to your NOVA X account to verify sites and run full scans.', status: 401);
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await client.openUrl(method, Uri.parse('${ApiService.baseUrl}/api/v1/cyber/$path')).timeout(const Duration(seconds: 20));
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      req.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (body != null) {
        req.headers.contentType = ContentType.json;
        req.write(jsonEncode(body));
      }
      // The server checks DNS/HTTPS itself, which can take a few seconds.
      final res = await req.close().timeout(const Duration(seconds: 60));
      final text = await res.transform(utf8.decoder).join();
      Map<String, dynamic> j;
      try {
        j = Map<String, dynamic>.from(jsonDecode(text) as Map);
      } catch (_) {
        throw CyberApiError('The NOVA X server gave an unexpected answer (HTTP ${res.statusCode}). Try again shortly.', status: res.statusCode);
      }
      if (res.statusCode >= 400) {
        throw CyberApiError('${j['message'] ?? 'Request failed (HTTP ${res.statusCode}).'}', status: res.statusCode);
      }
      return j;
    } on CyberApiError {
      rethrow;
    } on TimeoutException {
      throw CyberApiError('The NOVA X server didn\'t answer in time. Check your connection and try again.');
    } on SocketException {
      throw CyberApiError('Can\'t reach the NOVA X server. Check your internet connection.');
    } finally {
      client.close(force: true);
    }
  }

  static Future<Challenge> challenge(String host) async {
    final j = await _call('POST', 'challenge', {'host': host});
    final methods = <String, Map<String, String>>{};
    (j['methods'] as Map? ?? const {}).forEach((k, v) {
      methods['$k'] = {for (final e in (v as Map).entries) '${e.key}': '${e.value}'};
    });
    return Challenge(host: '${j['host']}', token: '${j['token']}', methods: methods, expiresAt: DateTime.tryParse('${j['expires_at'] ?? ''}'));
  }

  /// Returns (verified, message).
  static Future<(bool, String)> verify(String host, String method) async {
    final j = await _call('POST', 'verify', {'host': host, 'method': method});
    return (j['verified'] == true, '${j['message'] ?? ''}');
  }

  static Future<ScanPass> authorize(String host) async {
    final j = await _call('POST', 'authorize', {'host': host});
    return ScanPass(
      host: '${j['host']}',
      pass: '${j['pass']}',
      expiresAt: DateTime.tryParse('${j['expires_at']}') ?? DateTime.now().add(const Duration(hours: 2)),
      scansLeft: (j['scans_left_today'] as num?)?.toInt(),
    );
  }

  static Future<(List<VerifiedSite>, int?)> domains() async {
    final j = await _call('GET', 'domains');
    return (
      [for (final d in (j['domains'] as List? ?? const [])) VerifiedSite.fromJson(Map<String, dynamic>.from(d as Map))],
      (j['scans_left_today'] as num?)?.toInt(),
    );
  }

  static Future<void> revoke(String host) => _call('POST', 'revoke', {'host': host});
}

// ── 24/7 monitoring (server-side, cron on the NOVA X server) ─────────────────

class MonitorStats {
  MonitorStats({this.checks = 0, this.uptime, this.avgMs});
  final int checks;
  final double? uptime; // percent
  final int? avgMs;

  factory MonitorStats.fromJson(Object? j) {
    final m = j is Map ? j : const {};
    return MonitorStats(checks: (m['checks'] as num?)?.toInt() ?? 0, uptime: (m['uptime'] as num?)?.toDouble(), avgMs: (m['avg_ms'] as num?)?.toInt());
  }
}

class SiteMonitor {
  SiteMonitor({
    required this.host,
    required this.enabled,
    required this.intervalMin,
    required this.emailAlerts,
    required this.status,
    this.statusSince,
    this.pausedReason,
    this.lastCode,
    this.lastMs,
    this.certExpiresAt,
    this.lastCheckAt,
    this.nextCheckAt,
    this.securityHeaders = const [],
    this.externalScripts = const [],
    this.exposed = const [],
    MonitorStats? day,
    MonitorStats? week,
  })  : day = day ?? MonitorStats(),
        week = week ?? MonitorStats();

  final String host;
  final bool enabled;
  final int intervalMin;
  final bool emailAlerts;
  final String status; // pending | up | warn | down | paused
  final DateTime? statusSince;
  final String? pausedReason;
  final int? lastCode;
  final int? lastMs;
  final DateTime? certExpiresAt;
  final DateTime? lastCheckAt;
  final DateTime? nextCheckAt;
  final List<String> securityHeaders;
  final List<String> externalScripts;
  final List<String> exposed;
  final MonitorStats day;
  final MonitorStats week;

  int? get certDaysLeft => certExpiresAt?.difference(DateTime.now()).inDays;

  factory SiteMonitor.fromJson(Map<String, dynamic> j) {
    List<String> list(Object? v) => [for (final x in (v as List? ?? const [])) '$x'];
    DateTime? at(Object? v) => v == null ? null : DateTime.tryParse('$v')?.toLocal();
    return SiteMonitor(
      host: '${j['host']}',
      enabled: j['enabled'] == true,
      intervalMin: (j['interval_min'] as num?)?.toInt() ?? 15,
      emailAlerts: j['email_alerts'] == true,
      status: '${j['status'] ?? 'pending'}',
      statusSince: at(j['status_since']),
      pausedReason: j['paused_reason'] as String?,
      lastCode: (j['last_code'] as num?)?.toInt(),
      lastMs: (j['last_ms'] as num?)?.toInt(),
      certExpiresAt: at(j['cert_expires_at']),
      lastCheckAt: at(j['last_check_at']),
      nextCheckAt: at(j['next_check_at']),
      securityHeaders: list(j['security_headers']),
      externalScripts: list(j['external_scripts']),
      exposed: list(j['exposed']),
      day: MonitorStats.fromJson(j['stats_24h']),
      week: MonitorStats.fromJson(j['stats_7d']),
    );
  }
}

class MonitorEvent {
  MonitorEvent({required this.id, required this.host, required this.kind, required this.severity, required this.title, required this.detail, this.createdAt, this.read = false, this.emailed = false});
  final int id;
  final String host;
  final String kind;
  final String severity; // critical | high | medium | low | info
  final String title;
  final String detail;
  final DateTime? createdAt;
  final bool read;
  final bool emailed;

  factory MonitorEvent.fromJson(Map<String, dynamic> j) => MonitorEvent(
        id: (j['id'] as num).toInt(),
        host: '${j['host']}',
        kind: '${j['kind']}',
        severity: '${j['severity']}',
        title: '${j['title']}',
        detail: '${j['detail'] ?? ''}',
        createdAt: DateTime.tryParse('${j['created_at'] ?? ''}')?.toLocal(),
        read: j['read'] == true,
        emailed: j['emailed'] == true,
      );
}

class MonitorOverview {
  MonitorOverview(this.monitors, this.verifiedHosts, this.unread, this.limit, this.intervals);
  final List<SiteMonitor> monitors;
  final List<String> verifiedHosts;
  final int unread;
  final int limit;
  final List<int> intervals;
}

/// Monitoring endpoints. Kept as top-level statics on [CyberMonitoring] so the
/// existing [CyberApi] stays unchanged.
class CyberMonitoring {
  CyberMonitoring._();

  static Future<MonitorOverview> overview() async {
    final j = await CyberApi._call('GET', 'monitors');
    return MonitorOverview(
      [for (final m in (j['monitors'] as List? ?? const [])) SiteMonitor.fromJson(Map<String, dynamic>.from(m as Map))],
      [for (final h in (j['verified_hosts'] as List? ?? const [])) '$h'],
      (j['unread_events'] as num?)?.toInt() ?? 0,
      (j['limit'] as num?)?.toInt() ?? 20,
      [for (final i in (j['intervals'] as List? ?? const [5, 15, 60])) (i as num).toInt()],
    );
  }

  static Future<SiteMonitor> save(String host, {bool? enabled, int? intervalMin, bool? emailAlerts}) async {
    final j = await CyberApi._call('POST', 'monitors', {
      'host': host,
      if (enabled != null) 'enabled': enabled,
      if (intervalMin != null) 'interval_min': intervalMin,
      if (emailAlerts != null) 'email_alerts': emailAlerts,
    });
    return SiteMonitor.fromJson(Map<String, dynamic>.from(j['monitor'] as Map));
  }

  static Future<void> remove(String host) => CyberApi._call('POST', 'monitors-remove', {'host': host});

  /// Runs a check on the server right now. Returns the updated monitor and how many alerts it raised.
  static Future<(SiteMonitor, int)> checkNow(String host) async {
    final j = await CyberApi._call('POST', 'monitors-check', {'host': host});
    return (SiteMonitor.fromJson(Map<String, dynamic>.from(j['monitor'] as Map)), (j['new_events'] as num?)?.toInt() ?? 0);
  }

  static Future<(List<MonitorEvent>, int)> events({bool unreadOnly = false, int limit = 100}) async {
    final j = await CyberApi._call('GET', 'monitor-events?limit=$limit${unreadOnly ? '&unread=1' : ''}');
    return (
      [for (final e in (j['events'] as List? ?? const [])) MonitorEvent.fromJson(Map<String, dynamic>.from(e as Map))],
      (j['unread'] as num?)?.toInt() ?? 0,
    );
  }

  static Future<void> markRead([List<int>? ids]) => CyberApi._call('POST', 'monitor-events-read', {if (ids != null) 'ids': ids});
}
