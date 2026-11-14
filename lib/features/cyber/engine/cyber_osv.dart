// lib/features/cyber/engine/cyber_osv.dart
//
// Known-vulnerability lookups from OSV.dev (Google's open vulnerability
// database: GitHub advisories, npm, Packagist, PyPI, Pub and more).
// Free, no key. Only package names and versions are sent.

import 'dart:convert';
import 'dart:io';

import 'cyber_models.dart';

class OsvPackage {
  const OsvPackage(this.name, this.ecosystem, this.version);
  final String name;
  final String ecosystem; // npm, Packagist, PyPI, Pub, Go, crates.io, Maven, NuGet, RubyGems
  final String version;
}

class OsvVuln {
  OsvVuln({required this.id, required this.summary, required this.aliases, required this.severity, this.fixedIn});
  final String id;
  final String summary;
  final List<String> aliases;
  final Severity severity;
  final String? fixedIn;
}

class Osv {
  static final Map<String, OsvVuln> _cache = {};

  static Future<String?> _post(String path, Object body) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.postUrl(Uri.https('api.osv.dev', path)).timeout(const Duration(seconds: 15));
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body));
      final res = await req.close().timeout(const Duration(seconds: 25));
      final text = await res.transform(utf8.decoder).join();
      return res.statusCode == 200 ? text : null;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  static Future<String?> _get(String path) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.getUrl(Uri.https('api.osv.dev', path)).timeout(const Duration(seconds: 15));
      final res = await req.close().timeout(const Duration(seconds: 25));
      final text = await res.transform(utf8.decoder).join();
      return res.statusCode == 200 ? text : null;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// Vulnerabilities per package name (only packages with results).
  static Future<Map<String, List<OsvVuln>>> query(List<OsvPackage> pkgs) async {
    final out = <String, List<OsvVuln>>{};
    if (pkgs.isEmpty) return out;
    for (var i = 0; i < pkgs.length; i += 500) {
      final chunk = pkgs.sublist(i, i + 500 > pkgs.length ? pkgs.length : i + 500);
      final raw = await _post('/v1/querybatch', {
        'queries': [
          for (final p in chunk) {'package': {'name': p.name, 'ecosystem': p.ecosystem}, 'version': p.version}
        ]
      });
      if (raw == null) continue;
      final results = (jsonDecode(raw)['results'] as List?) ?? const [];
      for (var k = 0; k < results.length && k < chunk.length; k++) {
        final vulns = (results[k]?['vulns'] as List?) ?? const [];
        if (vulns.isEmpty) continue;
        final list = <OsvVuln>[];
        for (final v in vulns.take(15)) {
          final id = '${v['id']}';
          final d = await details(id, chunk[k].name);
          if (d != null) list.add(d);
        }
        list.sort((a, b) => a.severity.index.compareTo(b.severity.index));
        out[chunk[k].name] = list;
      }
    }
    return out;
  }

  static Future<OsvVuln?> details(String id, String package) async {
    final hit = _cache[id];
    if (hit != null) return hit;
    final raw = await _get('/v1/vulns/${Uri.encodeComponent(id)}');
    if (raw == null) return OsvVuln(id: id, summary: 'See $id', aliases: const [], severity: Severity.medium);
    final j = jsonDecode(raw) as Map<String, dynamic>;
    final aliases = [for (final a in (j['aliases'] as List? ?? const [])) '$a'];
    String? fixed;
    for (final a in (j['affected'] as List? ?? const [])) {
      if (a is! Map || '${(a['package'] as Map?)?['name']}'.toLowerCase() != package.toLowerCase()) continue;
      for (final r in (a['ranges'] as List? ?? const [])) {
        for (final e in ((r as Map)['events'] as List? ?? const [])) {
          final f = (e as Map)['fixed'];
          if (f != null && (fixed == null || compareVersions('$f', fixed) > 0)) fixed = '$f';
        }
      }
    }
    final v = OsvVuln(
      id: aliases.firstWhere((a) => a.startsWith('CVE-'), orElse: () => id),
      summary: '${j['summary'] ?? (j['details'] ?? '').toString().split('\n').first}'.trim(),
      aliases: [id, ...aliases.where((a) => !a.startsWith('CVE-'))],
      severity: severityOf(j),
      fixedIn: fixed,
    );
    _cache[id] = v;
    return v;
  }

  static Severity severityOf(Map<String, dynamic> j) {
    final db = '${(j['database_specific'] as Map?)?['severity'] ?? ''}'.toUpperCase();
    switch (db) {
      case 'CRITICAL':
        return Severity.critical;
      case 'HIGH':
        return Severity.high;
      case 'MODERATE':
      case 'MEDIUM':
        return Severity.medium;
      case 'LOW':
        return Severity.low;
    }
    for (final s in (j['severity'] as List? ?? const [])) {
      final score = '${(s as Map)['score'] ?? ''}';
      final base = cvss3Base(score);
      if (base != null) {
        if (base >= 9) return Severity.critical;
        if (base >= 7) return Severity.high;
        if (base >= 4) return Severity.medium;
        return Severity.low;
      }
    }
    return Severity.medium;
  }

  /// CVSS v3.x base score from a vector string (FIRST specification).
  static double? cvss3Base(String vector) {
    if (!vector.startsWith('CVSS:3')) return null;
    final m = <String, String>{};
    for (final p in vector.split('/').skip(1)) {
      final kv = p.split(':');
      if (kv.length == 2) m[kv[0]] = kv[1];
    }
    const av = {'N': 0.85, 'A': 0.62, 'L': 0.55, 'P': 0.2};
    const ac = {'L': 0.77, 'H': 0.44};
    const ui = {'N': 0.85, 'R': 0.62};
    const cia = {'H': 0.56, 'L': 0.22, 'N': 0.0};
    final scopeChanged = m['S'] == 'C';
    final pr = scopeChanged ? const {'N': 0.85, 'L': 0.68, 'H': 0.5} : const {'N': 0.85, 'L': 0.62, 'H': 0.27};
    if ([m['AV'], m['AC'], m['PR'], m['UI'], m['C'], m['I'], m['A']].any((v) => v == null)) return null;
    final iss = 1 - (1 - cia[m['C']]!) * (1 - cia[m['I']]!) * (1 - cia[m['A']]!);
    final impact = scopeChanged ? 7.52 * (iss - 0.029) - 3.25 * _pow(iss - 0.02, 15) : 6.42 * iss;
    final expl = 8.22 * av[m['AV']]! * ac[m['AC']]! * pr[m['PR']]! * ui[m['UI']]!;
    if (impact <= 0) return 0;
    final raw = scopeChanged ? 1.08 * (impact + expl) : impact + expl;
    return _roundUp(raw > 10 ? 10 : raw);
  }

  static double _pow(double b, int e) {
    var r = 1.0;
    for (var i = 0; i < e; i++) {
      r *= b;
    }
    return r;
  }

  static double _roundUp(double x) {
    final i = (x * 100000).round();
    return i % 10000 == 0 ? i / 100000.0 : ((i / 10000).floor() + 1) / 10.0;
  }
}

/// Compares dotted versions ("1.10.2" > "1.9.9"). Non-numeric parts compare as text.
int compareVersions(String a, String b) {
  final pa = a.split(RegExp(r'[.\-+]'));
  final pb = b.split(RegExp(r'[.\-+]'));
  for (var i = 0; i < pa.length || i < pb.length; i++) {
    final x = i < pa.length ? pa[i] : '0';
    final y = i < pb.length ? pb[i] : '0';
    final nx = int.tryParse(x), ny = int.tryParse(y);
    final c = (nx != null && ny != null) ? nx.compareTo(ny) : x.compareTo(y);
    if (c != 0) return c;
  }
  return 0;
}
