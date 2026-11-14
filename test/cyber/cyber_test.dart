// test/desktop/cyber_test.dart
//
// NOVA Cyber (PC): scoring, parsing and detection helpers. Network checks
// are exercised against real sites from the app.

import 'package:flutter_test/flutter_test.dart';
import 'package:nova_x/features/cyber/engine/checks_full.dart';
import 'package:nova_x/features/cyber/engine/cyber_code_scan.dart';
import 'package:nova_x/features/cyber/engine/cyber_context.dart';
import 'package:nova_x/features/cyber/engine/cyber_engine.dart';
import 'package:nova_x/features/cyber/engine/cyber_fixes.dart';
import 'package:nova_x/features/cyber/engine/cyber_http.dart';
import 'package:nova_x/features/cyber/engine/cyber_models.dart';
import 'package:nova_x/features/cyber/engine/cyber_osv.dart';

CyberResponse resp(int status, String body, {Map<String, List<String>> headers = const {}}) =>
    CyberResponse(url: Uri.parse('https://example.com/x'), method: 'GET', status: status, headers: headers, body: body, ms: 1);

void main() {
  group('score', () {
    ScanReport r(List<Severity> sev) {
      final rep = ScanReport(target: 'https://a.com/', level: ScanLevel.quick, started: DateTime(2026));
      for (var i = 0; i < sev.length; i++) {
        rep.findings.add(Finding(id: 'x$i', title: 't', severity: sev[i], area: CheckArea.headers));
      }
      return rep;
    }

    test('clean site scores 100 / A+', () {
      expect(r(const []).score, 100);
      expect(r(const []).grade, 'A+');
    });
    test('a critical caps the score at 39', () {
      expect(r(const [Severity.critical]).score, 39);
      expect(r(const [Severity.critical]).grade, 'F');
    });
    test('a high caps the score at 69', () => expect(r(const [Severity.high]).score, 69));
    test('weights add up', () => expect(r(const [Severity.medium, Severity.low, Severity.info]).score, 92));
    test('the same id counts once', () {
      final rep = r(const []);
      rep.findings.add(Finding(id: 'dup', title: 't', severity: Severity.medium, area: CheckArea.headers));
      rep.findings.add(Finding(id: 'dup', title: 't', severity: Severity.medium, area: CheckArea.headers));
      expect(rep.score, 94);
    });
    test('report round-trips through JSON', () {
      final rep = r(const [Severity.high, Severity.low]);
      rep.tech.stack.add('nginx');
      final back = ScanReport.fromJson(Map<String, dynamic>.from(rep.toJson()));
      expect(back.score, rep.score);
      expect(back.tech.stack, contains('nginx'));
      expect(back.findings.length, 2);
    });
  });

  group('secrets are redacted', () {
    test('env values', () {
      final t = redactSecrets('DB_PASSWORD=supersecretvalue\nAPP_ENV=production');
      expect(t, isNot(contains('supersecretvalue')));
      expect(t, contains('DB_PASSWORD=su…'));
    });
    test('AWS keys and private keys', () {
      expect(redactSecrets('AKIAIOSFODNN7EXAMPLE'), isNot(contains('IOSFODNN7EXAMPLE')));
      expect(redactSecrets('-----BEGIN RSA PRIVATE KEY-----\nabc\n-----END RSA PRIVATE KEY-----'), '[private key redacted]');
    });
  });

  group('targets', () {
    test('normalize', () {
      expect(normalizeTarget('Example.com/path?x')!.toString(), 'https://example.com/');
      expect(normalizeTarget('http://shop.example.com')!.scheme, 'http');
      expect(normalizeTarget('ftp://x.com'), isNull);
      expect(normalizeTarget(''), isNull);
    });
    test('own machine and private networks', () {
      expect(isOwnMachine('localhost'), isTrue);
      expect(isOwnMachine('127.0.0.1'), isTrue);
      expect(isOwnMachine('example.com'), isFalse);
      expect(isPrivateNetwork('192.168.1.20'), isTrue);
      expect(isPrivateNetwork('10.0.0.5'), isTrue);
      expect(isPrivateNetwork('8.8.8.8'), isFalse);
    });
    test('registrable domain', () {
      expect(registrableDomain('www.shop.example.com'), 'example.com');
      expect(registrableDomain('api.example.co.uk'), 'example.co.uk');
      expect(registrableDomain('t-lyfe.com.ng'), 't-lyfe.com.ng');
    });
  });

  group('soft-404', () {
    final nf = SoftNotFound(status: 200, length: 5000, title: 'Home', redirect: null);
    test('same page for a missing path is "not found"', () {
      expect(nf.matches(resp(200, '<title>Home</title>${'x' * 4980}')), isTrue);
    });
    test('a real file is not', () {
      expect(nf.matches(resp(200, 'DB_HOST=localhost\nDB_PASSWORD=x')), isFalse);
      expect(nf.matches(resp(404, '')), isTrue);
    });
  });

  group('exposed-file validators', () {
    bool valid(String path, CyberResponse r) => FullChecks.probes.firstWhere((p) => p.path == path).valid(r);
    test('.env needs real KEY=VALUE lines', () {
      expect(valid('/.env', resp(200, 'APP_KEY=base64:x\nDB_PASSWORD=y\n')), isTrue);
      expect(valid('/.env', resp(200, '<html><body>Welcome</body></html>')), isFalse);
    });
    test('.git/HEAD', () {
      expect(valid('/.git/HEAD', resp(200, 'ref: refs/heads/main\n')), isTrue);
      expect(valid('/.git/HEAD', resp(200, '<!doctype html>')), isFalse);
    });
    test('SQL dumps', () {
      expect(valid('/backup.sql', resp(200, '-- MySQL dump 10.13\nCREATE TABLE users (')), isTrue);
      expect(valid('/backup.sql', resp(200, '<html>CREATE TABLE in a blog post</html>')), isFalse);
    });
    test('phpinfo', () => expect(valid('/phpinfo.php', resp(200, '<title>phpinfo()</title> PHP Version 8.2.1')), isTrue));
  });

  group('forms', () {
    test('parse action, method and inputs', () {
      final forms = parseForms(
          '<form action="/login" method="POST"><input name="email" type="email"><input type="password" name="pw"></form>',
          Uri.parse('https://example.com/a/b'));
      expect(forms.single['action'].toString(), 'https://example.com/login');
      expect(forms.single['method'], 'post');
      expect((forms.single['inputs'] as List).length, 2);
    });
  });

  group('OSV helpers', () {
    test('CVSS 3.1 base scores', () {
      expect(Osv.cvss3Base('CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H'), 9.8);
      expect(Osv.cvss3Base('CVSS:3.1/AV:N/AC:L/PR:N/UI:R/S:C/C:L/I:L/A:N'), 6.1);
      expect(Osv.cvss3Base('CVSS:3.1/AV:N/AC:H/PR:N/UI:N/S:U/C:H/I:N/A:N'), 5.9);
      expect(Osv.cvss3Base('not a vector'), isNull);
    });
    test('version compare', () {
      expect(compareVersions('3.5.0', '3.4.9'), greaterThan(0));
      expect(compareVersions('1.10.0', '1.9.9'), greaterThan(0));
      expect(compareVersions('2.0', '2.0.0'), 0);
    });
  });

  group('code rules', () {
    bool hit(String id, String line) => codeRules.firstWhere((r) => r.id == id).pattern.hasMatch(line);
    test('injection', () {
      expect(hit('code.sqli.php', r'$r = mysqli_query($c, "SELECT * FROM u WHERE id=" . $_GET["id"]);'), isTrue);
      expect(hit('code.sqli.concat', 'q = "SELECT * FROM users WHERE name = \'" + name'), isTrue);
      expect(hit('code.sqli.concat', 'const q = "SELECT * FROM t WHERE id = ?";'), isFalse);
      expect(hit('code.cmd.php', r'system("ping " . $_GET["host"]);'), isTrue);
      expect(hit('code.xss.php', r'echo $_GET["q"];'), isTrue);
      expect(hit('code.xss.php', r'echo htmlspecialchars($_GET["q"]);'), isFalse);
    });
    test('secrets and TLS', () {
      expect(hit('code.secret.aws', 'key = "AKIAIOSFODNN7EXAMPLE"'), isTrue);
      expect(hit('code.secret.assign', r'$db_password = "Sup3rS3cretPass";'), isTrue);
      expect(hit('code.tls.disabled', 'rejectUnauthorized: false'), isTrue);
      expect(hit('code.deserialize.py', 'yaml.load(f, Loader=yaml.SafeLoader)'), isFalse);
    });
  });

  group('fix library', () {
    test('every finding family has a fix', () {
      for (final id in [
        'hdr.csp', 'hdr.csp.weak', 'hdr.hsts', 'tls.redirect', 'cookie.flags', 'exp.env', 'exp.git', 'exp.sqldump',
        'inj.xss.reflected', 'inj.sql.error', 'access.cors.reflect', 'net.port.6379', 'dep.jquery', 'dns.dmarc', 'wp.xmlrpc',
      ]) {
        expect(fixFor(id), isNotNull, reason: id);
      }
    });
    test('detected platform is shown first', () {
      final g = fixFor('hdr.hsts')!;
      expect(orderedPlatforms(g, 'apache', {'apache', 'php'}).first, 'apache');
    });
  });
}
