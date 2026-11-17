// test/cyber/cyber_pipeline_test.dart (3.14.0)
//
// Findings pipeline ported from NOVA X for Windows: CVSS 3.1, attack chains,
// SARIF, extra dependency manifests and the monitoring models.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nova_x/features/cyber/engine/cyber_api.dart';
import 'package:nova_x/features/cyber/engine/cyber_code_scan.dart';
import 'package:nova_x/features/cyber/engine/cyber_models.dart';
import 'package:nova_x/features/cyber/engine/cyber_pipeline.dart';

void main() {
  group('CVSS 3.1 reference scores', () {
    const cases = {
      'CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H': 9.8,
      'CVSS:3.1/AV:N/AC:L/PR:N/UI:R/S:C/C:L/I:L/A:N': 6.1,
      'CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:N/A:N': 7.5,
      'CVSS:3.1/AV:N/AC:H/PR:N/UI:N/S:U/C:H/I:H/A:H': 8.1,
      'CVSS:3.1/AV:P/AC:L/PR:N/UI:N/S:U/C:H/I:N/A:N': 4.6,
      'CVSS:3.1/AV:N/AC:H/PR:N/UI:R/S:U/C:L/I:N/A:N': 3.1,
    };
    cases.forEach((v, score) {
      test('$score', () => expect(cvssScore(v), score));
    });
    test('invalid vector scores 0', () {
      expect(cvssScore('nonsense'), 0);
      expect(cvssRating(0), 'None');
      expect(cvssRating(9.8), 'Critical');
    });
  });

  group('pipeline', () {
    Finding f(String id, Severity s, {String loc = ''}) => Finding(id: id, title: id, severity: s, area: CheckArea.headers, location: loc, evidence: 'e-$id');

    test('duplicates merge and keep the worst severity', () {
      final out = deduplicate([f('x', Severity.low, loc: 'a'), f('x', Severity.high, loc: 'a'), f('x', Severity.low, loc: 'b')]);
      expect(out.length, 2);
      expect(out.first.severity, Severity.high);
    });

    test('chains are not counted in the score', () {
      final r = ScanReport(target: 'https://example.com', level: ScanLevel.quick, started: DateTime(2026, 11, 1));
      r.findings.add(Finding(id: 'chain.test', title: 'Chain', severity: Severity.critical, area: CheckArea.chain));
      expect(r.score, 100);
    });

    test('report keeps facts and CVSS through JSON', () {
      final r = ScanReport(target: 'code://my-app', level: ScanLevel.code, started: DateTime(2026, 11, 1));
      r.facts['Files read'] = '12';
      r.findings.add(Finding(id: 'code.secret.x', title: 'Secret', severity: Severity.high, area: CheckArea.code, cvss: 'CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:N/A:N'));
      final back = ScanReport.fromJson(jsonDecode(jsonEncode(r.toJson())) as Map<String, dynamic>);
      expect(back.facts['Files read'], '12');
      expect(back.findings.single.cvss, startsWith('CVSS:3.1/'));
      expect(back.displayName, 'my-app');
    });

    test('SARIF 2.1.0 has rules and results', () {
      final r = ScanReport(target: 'code://proj', level: ScanLevel.code, started: DateTime(2026, 11, 1));
      r.findings.add(Finding(
          id: 'code.sqli', title: 'SQL injection', severity: Severity.critical, area: CheckArea.code, location: '/src/db.php:42',
          cvss: 'CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H'));
      final j = jsonDecode(toSarif(r)) as Map<String, dynamic>;
      expect(j['version'], '2.1.0');
      final run = (j['runs'] as List).first as Map;
      expect(((run['tool'] as Map)['driver'] as Map)['rules'], isNotEmpty);
      final res = (run['results'] as List).single as Map;
      expect(res['ruleId'], 'code.sqli');
      expect(res['level'], 'error');
      final loc = ((res['locations'] as List).single as Map)['physicalLocation'] as Map;
      expect((loc['artifactLocation'] as Map)['uri'], 'src/db.php');
      expect((loc['region'] as Map)['startLine'], 42);
    });
  });

  group('extra dependency manifests', () {
    test('Cargo.lock', () {
      final p = parseExtraManifest('Cargo.lock', '[[package]]\nname = "serde"\nversion = "1.0.100"\n');
      expect(p.single.name, 'serde');
      expect(p.single.ecosystem, 'crates.io');
    });
    test('build.gradle', () {
      final p = parseExtraManifest('build.gradle', "implementation 'com.squareup.okhttp3:okhttp:4.9.0'");
      expect(p.single.name, 'com.squareup.okhttp3:okhttp');
      expect(p.single.version, '4.9.0');
    });
    test('go.sum', () {
      final p = parseExtraManifest('go.sum', 'golang.org/x/net v0.7.0 h1:abc=\ngolang.org/x/net v0.7.0/go.mod h1:def=\n');
      expect(p.length, 1);
      expect(p.single.ecosystem, 'Go');
    });
    test('Gemfile.lock and pom.xml', () {
      expect(parseExtraManifest('Gemfile.lock', 'GEM\n  specs:\n    rails (7.0.4)\n').single.name, 'rails');
      expect(
          parseExtraManifest('pom.xml', '<dependency><groupId>org.x</groupId><artifactId>y</artifactId><version>1.2</version></dependency>').single.name,
          'org.x:y');
    });
    test('lockfiles are read by the code scan', () async {
      final res = await CodeScanner.scanFiles([
        CodeFile('proj/Cargo.lock', utf8.encode('[[package]]\nname = "serde"\nversion = "1.0.100"\n')),
      ]);
      expect(res.files, 1);
      expect(res.manifests, isNotEmpty);
    }, skip: 'needs network for the OSV lookup');
  });

  group('monitoring models', () {
    test('overview fields parse', () {
      final m = SiteMonitor.fromJson({
        'host': 'example.com',
        'enabled': true,
        'interval_min': 5,
        'email_alerts': true,
        'status': 'up',
        'last_code': 200,
        'last_ms': 180,
        'security_headers': ['hsts', 'csp'],
        'exposed': [],
        'stats_24h': {'checks': 288, 'uptime': 99.9, 'avg_ms': 170},
        'stats_7d': {'checks': 2016, 'uptime': 99.5},
      });
      expect(m.status, 'up');
      expect(m.intervalMin, 5);
      expect(m.securityHeaders.length, 2);
      expect(m.day.uptime, 99.9);
      expect(m.week.checks, 2016);
    });
    test('events parse', () {
      final e = MonitorEvent.fromJson({'id': 7, 'host': 'example.com', 'kind': 'down', 'severity': 'critical', 'title': 'Down', 'read': false});
      expect(e.id, 7);
      expect(e.severity, 'critical');
      expect(e.read, isFalse);
    });
  });
}
