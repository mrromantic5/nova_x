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
