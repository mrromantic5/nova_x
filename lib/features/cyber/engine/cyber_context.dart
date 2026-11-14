// lib/features/cyber/engine/cyber_context.dart
//
// NOVA Cyber — what every check gets: the HTTP client, the target, the
// home page response, the report being built, and small shared helpers.

import 'dart:math';

import 'cyber_http.dart';
import 'cyber_models.dart';

class ScanContext {
  ScanContext({required this.http, required this.base, required this.report, this.onLog, this.onFinding});

  final CyberHttp http;

  /// https://host (no path) — or http:// when the site has no HTTPS.
  Uri base;
  final ScanReport report;
  final void Function(String line)? onLog;
  final void Function(Finding f)? onFinding;

  late CyberResponse home;

  /// Pages and URLs found while crawling the home page (same host).
  final Set<Uri> links = {};
  final Set<Uri> scripts = {}; // all script URLs (any host)
  final List<Map<String, Object?>> forms = []; // {action, method, inputs:[{name,type,value}]}

  /// "Not found" fingerprint (soft-404 detection), set by the full scan.
  SoftNotFound? notFound;

  final Random _rand = Random.secure();

  String get host => base.host;
  bool get https => base.scheme == 'https';

  /// Random lower-case token (for unique markers / not-found paths).
  String nonce([int n = 10]) {
    const a = 'abcdefghijklmnopqrstuvwxyz0123456789';
    return String.fromCharCodes(Iterable.generate(n, (_) => a.codeUnitAt(_rand.nextInt(a.length))));
  }

  Uri url(String path, [Map<String, String>? query]) {
    final u = base.resolve(path);
    return query == null ? u : u.replace(queryParameters: {...u.queryParameters, ...query});
  }

  void log(String line) => onLog?.call(line);

  void add(Finding f) {
    report.findings.add(f);
    onFinding?.call(f);
  }

  void pass(String id, String title, CheckArea area, {String evidence = '', ScanLevel level = ScanLevel.quick}) =>
      add(Finding(id: id, title: title, severity: Severity.info, area: area, passed: true, evidence: evidence, level: level));
}

/// What this site answers for a page that doesn't exist (many sites answer
/// 200 with a normal page, which would otherwise look like "file found").
class SoftNotFound {
  SoftNotFound({required this.status, required this.length, required this.title, required this.redirect});

  final int status;
  final int length;
  final String title;
  final String? redirect;

  static String titleOf(String html) {
    final m = RegExp(r'<title[^>]*>([\s\S]{0,200}?)</title>', caseSensitive: false).firstMatch(html);
    return (m?.group(1) ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Does [r] look like the site's "not found" answer?
  bool matches(CyberResponse r) {
    if (r.status == 404 || r.status == 410 || r.status == 0) return true;
    if (r.status >= 300 && r.status < 400) return redirect != null && r.location != null && _sameRedirect(r.location!);
    if (r.status != status) return false;
    final len = r.body.length;
    final close = length == 0 ? len == 0 : (len - length).abs() <= max(64, (length * 0.08).round());
    return close && titleOf(r.body) == title;
  }

  bool _sameRedirect(String loc) {
    String norm(String s) => s.replaceAll(RegExp(r'nova-cyber-[a-z0-9]+'), '*').split('?').first;
    return norm(loc) == norm(redirect!);
  }
}

/// Header value helpers.
String lowerOr(String? s) => (s ?? '').toLowerCase();

String clip(String s, [int n = 300]) {
  final t = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  return t.length > n ? '${t.substring(0, n)}…' : t;
}

/// The lines around [needle] in [body] (for evidence).
String around(String body, String needle, [int radius = 90]) {
  final i = body.indexOf(needle);
  if (i < 0) return '';
  final s = max(0, i - radius);
  final e = min(body.length, i + needle.length + radius);
  return '${s > 0 ? '…' : ''}${body.substring(s, e).replaceAll(RegExp(r'\s+'), ' ')}${e < body.length ? '…' : ''}';
}

/// Registrable domain (good enough for DNS/email checks): last two labels,
/// or three for common second-level suffixes (co.uk, com.gh, com.ng…).
String registrableDomain(String host) {
  final p = host.split('.');
  if (p.length <= 2) return host;
  const second = {'co', 'com', 'org', 'net', 'gov', 'edu', 'ac', 'or', 'ne', 'go', 'gob', 'mil', 'nic', 'sch'};
  final n = second.contains(p[p.length - 2]) && p.last.length == 2 ? 3 : 2;
  return p.sublist(p.length - n).join('.');
}

/// Parses <form> elements (action, method, inputs) from HTML.
List<Map<String, Object?>> parseForms(String html, Uri page) {
  final out = <Map<String, Object?>>[];
  for (final m in RegExp(r'<form\b([^>]*)>([\s\S]*?)</form>', caseSensitive: false).allMatches(html).take(20)) {
    final attrs = m.group(1) ?? '';
    String attr(String a, String src) =>
        RegExp('\\b$a\\s*=\\s*(["\'])(.*?)\\1', caseSensitive: false).firstMatch(src)?.group(2) ??
        RegExp('\\b$a\\s*=\\s*([^\\s>]+)', caseSensitive: false).firstMatch(src)?.group(1) ??
        '';
    final action = attr('action', attrs);
    final inputs = <Map<String, String>>[];
    for (final i in RegExp(r'<(input|textarea|select)\b([^>]*)>', caseSensitive: false).allMatches(m.group(2) ?? '')) {
      final a = i.group(2) ?? '';
      final name = attr('name', a);
      if (name.isEmpty) continue;
      inputs.add({'name': name, 'type': attr('type', a).toLowerCase(), 'value': attr('value', a)});
    }
    Uri target;
    try {
      target = action.isEmpty ? page : page.resolve(action.replaceAll('&amp;', '&'));
    } catch (_) {
      target = page;
    }
    out.add({'action': target, 'method': (attr('method', attrs).isEmpty ? 'get' : attr('method', attrs)).toLowerCase(), 'inputs': inputs});
  }
  return out;
}
