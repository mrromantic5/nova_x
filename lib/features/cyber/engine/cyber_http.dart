// lib/features/cyber/engine/cyber_http.dart
//
// NOVA Cyber — the only way the scanner talks to a site.
//
//  • Polite: at most [maxPerSecond] requests per second, 2 at a time, and a
//    request budget per scan.
//  • Stops by itself when the site pushes back (several 429 / 503 answers in
//    a row, or a firewall block page), so a scan never hammers a site.
//  • Never follows redirects on its own (redirects are evidence).
//  • Every request is logged for the activity panel and the report.
//  • Identifies itself: "NOVA-Cyber/2.0 (+authorised security check)".

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data' show BytesBuilder;

class CyberResponse {
  CyberResponse({
    required this.url,
    required this.method,
    required this.status,
    required this.headers,
    required this.body,
    required this.ms,
    this.certificate,
    this.error,
  });

  final Uri url;
  final String method;
  final int status; // 0 when the request failed
  final Map<String, List<String>> headers; // lower-case names
  final String body; // capped
  final int ms;
  final X509Certificate? certificate;
  final String? error;

  bool get ok => status >= 200 && status < 300;
  String? header(String name) {
    final v = headers[name.toLowerCase()];
    return v == null || v.isEmpty ? null : v.join(', ');
  }

  List<String> all(String name) => headers[name.toLowerCase()] ?? const [];
  String? get location => header('location');
  String get contentType => (header('content-type') ?? '').toLowerCase();
}

class CyberStopped implements Exception {
  CyberStopped(this.reason);
  final String reason;
  @override
  String toString() => reason;
}

class CyberHttp {
  CyberHttp({this.maxPerSecond = 5, this.budget = 600, this.onLog});

  final int maxPerSecond;
  final int budget;
  final void Function(String line)? onLog;

  static const String userAgent = 'Mozilla/5.0 (Linux; Android 14) NOVA-Cyber/2.0 (+authorised security check)';
  static const int maxBody = 512 * 1024;

  final HttpClient _client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 8)
    ..idleTimeout = const Duration(seconds: 10)
    ..userAgent = userAgent
    ..autoUncompress = true;

  int sent = 0;
  int _pushBack = 0;
  bool cancelled = false;
  String? stopReason;
  final List<DateTime> _recent = [];
  int _inFlight = 0;
  final List<Completer<void>> _waiting = [];

  void cancel([String reason = 'Stopped by you.']) {
    cancelled = true;
    stopReason ??= reason;
  }

  void close() => _client.close(force: true);

  Future<void> _slot() async {
    while (_inFlight >= 2) {
      final c = Completer<void>();
      _waiting.add(c);
      await c.future;
    }
    _inFlight++;
    // Rate limit: no more than maxPerSecond in any 1-second window.
    while (true) {
      final now = DateTime.now();
      _recent.removeWhere((t) => now.difference(t) > const Duration(seconds: 1));
      if (_recent.length < maxPerSecond) break;
      await Future<void>.delayed(const Duration(milliseconds: 60));
    }
    _recent.add(DateTime.now());
  }

  void _release() {
    _inFlight--;
    if (_waiting.isNotEmpty) _waiting.removeAt(0).complete();
  }

  /// Sends one request. Throws [CyberStopped] when the scan must stop.
  Future<CyberResponse> send(
    String method,
    Uri url, {
    Map<String, String> headers = const {},
    String? body,
    String? bodyType,
    Duration timeout = const Duration(seconds: 15),
    bool quiet = false,
  }) async {
    if (cancelled) throw CyberStopped(stopReason ?? 'Stopped.');
    if (sent >= budget) {
      cancel('The request budget for this scan ($budget) was used.');
      throw CyberStopped(stopReason!);
    }
    await _slot();
    sent++;
    final sw = Stopwatch()..start();
    try {
      final req = await _client.openUrl(method, url).timeout(timeout);
      req.followRedirects = false;
      req.persistentConnection = true;
      req.headers.set(HttpHeaders.acceptHeader, 'text/html,application/xhtml+xml,application/json;q=0.9,*/*;q=0.8');
      req.headers.set(HttpHeaders.acceptLanguageHeader, 'en');
      headers.forEach(req.headers.set);
      if (body != null) {
        final bytes = utf8.encode(body);
        req.headers.contentType = ContentType.parse(bodyType ?? 'application/x-www-form-urlencoded');
        req.contentLength = bytes.length;
        req.add(bytes);
      }
      final res = await req.close().timeout(timeout);
      final buf = BytesBuilder(copy: false);
      var total = 0;
      await for (final chunk in res.timeout(timeout)) {
        if (total < maxBody) buf.add(chunk);
        total += chunk.length;
        if (total > maxBody * 2) break;
      }
      final h = <String, List<String>>{};
      res.headers.forEach((name, values) => h[name.toLowerCase()] = List.of(values));
      final text = utf8.decode(buf.takeBytes(), allowMalformed: true);
      final r = CyberResponse(
        url: url,
        method: method,
        status: res.statusCode,
        headers: h,
        body: text.length > maxBody ? text.substring(0, maxBody) : text,
        ms: sw.elapsedMilliseconds,
        certificate: res.certificate,
      );
      if (!quiet) onLog?.call('$method ${_short(url)}  →  ${res.statusCode}  ${sw.elapsedMilliseconds} ms');
      _watchPushBack(r);
      return r;
    } on CyberStopped {
      rethrow;
    } catch (e) {
      final msg = e is TimeoutException ? 'timed out' : e.toString().split('\n').first;
      if (!quiet) onLog?.call('$method ${_short(url)}  →  error: $msg');
      return CyberResponse(url: url, method: method, status: 0, headers: const {}, body: '', ms: sw.elapsedMilliseconds, error: msg);
    } finally {
      _release();
    }
  }

  Future<CyberResponse> get(Uri url, {Map<String, String> headers = const {}, bool quiet = false}) =>
      send('GET', url, headers: headers, quiet: quiet);

  void _watchPushBack(CyberResponse r) {
    final blocked = r.status == 429 ||
        r.status == 503 && (r.header('retry-after') != null) ||
        (r.status == 403 && _looksLikeWafBlock(r));
    if (blocked) {
      _pushBack++;
      if (_pushBack >= 4) {
        cancel('The site started rate-limiting or blocking the scan (HTTP ${r.status}). '
            'Stopped to stay polite. Allow-list your IP in your firewall to scan everything.');
      }
    } else if (r.status != 0) {
      _pushBack = 0;
    }
  }

  static bool _looksLikeWafBlock(CyberResponse r) {
    final b = r.body.toLowerCase();
    return r.header('cf-mitigated') != null ||
        b.contains('attention required! | cloudflare') ||
        b.contains('request blocked') && (b.contains('waf') || b.contains('firewall')) ||
        b.contains('access denied') && b.contains('incident id') ||
        b.contains('sucuri website firewall') ||
        b.contains('mod_security') ||
        b.contains('the requested url was rejected');
  }

  static String _short(Uri u) {
    final s = u.toString();
    return s.length > 110 ? '${s.substring(0, 107)}…' : s;
  }
}
