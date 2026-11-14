// lib/features/cyber/engine/checks_full.dart
//
// NOVA Cyber — Full scan. Runs ONLY on sites the user has proved they own
// (server-checked, see cyber_api.dart). Everything here detects a weakness
// and proves it with harmless evidence; nothing changes or deletes data:
//
//  • exposed files and services   — validated by content, soft-404 aware
//  • injection                    — unique inert markers and comparisons
//  • access control & config      — CORS, Host header, HTTP methods, open redirects
//  • network services             — TCP connect to well-known ports (no commands)
//  • platform checks              — WordPress, GraphQL, API docs, source maps
//  • subdomains                   — from public certificate logs, takeover check
//
// Secret values found in exposed files are never shown (redacted).

import 'dart:convert';
import 'dart:io';

import 'checks_quick.dart';
import 'cyber_context.dart';
import 'cyber_http.dart';
import 'cyber_models.dart';
import 'cyber_osv.dart';

class FullOptions {
  const FullOptions({this.ports = true, this.loginRateLimit = false, this.subdomains = true});
  final bool ports;

  /// Sends 6 failed sign-ins with a made-up account to see if the login is rate-limited.
  final bool loginRateLimit;
  final bool subdomains;
}

class FullChecks {
  FullChecks(this.c, this.quick, this.options);
  final ScanContext c;
  final QuickChecks quick;
  final FullOptions options;

  Future<void> run() async {
    await notFoundBaseline();
    await crawl();
    await exposedFiles();
    await directoryListing();
    await adminSurfaces();
    await apiSurfaces();
    await sourceMaps();
    await methods();
    await cors();
    await hostHeader();
    await parameters();
    if (c.report.tech.stack.contains('wordpress')) await wordpress();
    if (options.loginRateLimit) await loginRateLimit();
    if (options.ports) await ports();
    if (options.subdomains) await subdomains();
  }

  // ── Soft-404 fingerprint ───────────────────────────────────────────────────

  Future<void> notFoundBaseline() async {
    final r = await c.http.get(c.url('/nova-cyber-${c.nonce()}/${c.nonce(6)}.txt'), quiet: true);
    c.notFound = SoftNotFound(status: r.status, length: r.body.length, title: SoftNotFound.titleOf(r.body), redirect: r.location);
    if (r.status == 200) c.log('Note: this site answers 200 for pages that don\'t exist — results are validated by content.');
  }

  bool _real(CyberResponse r) => r.status == 200 && !(c.notFound?.matches(r) ?? false);

  /// A few same-host pages (for parameters, forms and cookies).
  Future<void> crawl() async {
    final pages = c.links.where((u) => u.path != '/' || u.hasQuery).take(12).toList();
    for (final u in pages) {
      final r = await c.http.get(u);
      if (!r.ok || !r.contentType.contains('html')) continue;
      c.forms.addAll(parseForms(r.body, u));
      for (final m in RegExp(r'''<a\b[^>]*\bhref\s*=\s*["']([^"'#]+\?[^"'#]+)''', caseSensitive: false).allMatches(r.body).take(80)) {
        final link = Uri.tryParse(m[1]!.replaceAll('&amp;', '&'));
        if (link == null) continue;
        final abs = u.resolveUri(link);
        if (abs.host == c.host) c.links.add(abs);
      }
      if (r.all('set-cookie').isNotEmpty) quick.cookies(r, level: ScanLevel.full);
    }
  }

  // ── Exposed files ──────────────────────────────────────────────────────────

  static final List<_Probe> probes = [
    _Probe('/.env', 'exp.env', 'Environment file (.env) is public', Severity.critical, _isEnv,
        'It normally holds database passwords, API keys and app secrets.', ['CWE-538', 'CWE-200']),
    _Probe('/.env.local', 'exp.env', 'Environment file (.env.local) is public', Severity.critical, _isEnv, 'Holds local secrets.', ['CWE-538']),
    _Probe('/.env.production', 'exp.env', 'Environment file (.env.production) is public', Severity.critical, _isEnv, 'Holds production secrets.', ['CWE-538']),
    _Probe('/.env.backup', 'exp.env', 'Environment backup (.env.backup) is public', Severity.critical, _isEnv, 'Holds secrets.', ['CWE-538']),
    _Probe('/.git/HEAD', 'exp.git', 'Git repository is downloadable (.git)', Severity.critical,
        (r) => RegExp(r'^(ref: refs/|[0-9a-f]{40}\s*$)').hasMatch(r.body.trim()),
        'The full source code and its history (often including old passwords and keys) can be rebuilt from it.', ['CWE-527']),
    _Probe('/.git/config', 'exp.git', 'Git config is public', Severity.critical, (r) => r.body.contains('[core]'),
        'Shows repository settings and remote URLs, sometimes with credentials.', ['CWE-527']),
    _Probe('/.svn/entries', 'exp.svn', 'Subversion metadata is public (.svn)', Severity.high,
        (r) => RegExp(r'^\d+\s*$', multiLine: true).hasMatch(r.body) && r.body.contains('dir'), 'Source code can be downloaded.', ['CWE-527']),
    _Probe('/.hg/requires', 'exp.hg', 'Mercurial repository is public (.hg)', Severity.high, (r) => r.body.contains('revlogv1') || r.body.contains('store'),
        'Source code can be downloaded.', ['CWE-527']),
    _Probe('/.DS_Store', 'exp.dsstore', '.DS_Store file lists folder contents', Severity.low, (r) => r.body.contains('Bud1'),
        'Reveals names of files and folders, including ones not linked anywhere.', ['CWE-538']),
    _Probe('/wp-config.php.bak', 'exp.configbak', 'WordPress config backup is public', Severity.critical, _isPhpConfig,
        'Contains the database password and secret keys in plain text.', ['CWE-530']),
    _Probe('/wp-config.php~', 'exp.configbak', 'WordPress config backup is public', Severity.critical, _isPhpConfig, 'Contains the database password.', ['CWE-530']),
    _Probe('/wp-config.old', 'exp.configbak', 'WordPress config backup is public', Severity.critical, _isPhpConfig, 'Contains the database password.', ['CWE-530']),
    _Probe('/config.php.bak', 'exp.configbak', 'Config backup (config.php.bak) is public', Severity.critical, _isPhpConfig,
        'Backup copies are served as text, exposing source and credentials.', ['CWE-530']),
    _Probe('/.config.php.swp', 'exp.configbak', 'Editor swap file of config.php is public', Severity.high, (r) => r.body.contains('b0VIM'), 'Contains the file\'s source.', ['CWE-530']),
    _Probe('/index.php.bak', 'exp.sourcebak', 'Source backup (index.php.bak) is public', Severity.high, (r) => r.body.contains('<?php'),
        'Server-side code is readable.', ['CWE-530']),
    _Probe('/backup.sql', 'exp.sqldump', 'Database dump is public (backup.sql)', Severity.critical, _isSql, 'Anyone can download your database.', ['CWE-530'], range: true),
    _Probe('/dump.sql', 'exp.sqldump', 'Database dump is public (dump.sql)', Severity.critical, _isSql, 'Anyone can download your database.', ['CWE-530'], range: true),
    _Probe('/database.sql', 'exp.sqldump', 'Database dump is public (database.sql)', Severity.critical, _isSql, 'Anyone can download your database.', ['CWE-530'], range: true),
    _Probe('/db.sql', 'exp.sqldump', 'Database dump is public (db.sql)', Severity.critical, _isSql, 'Anyone can download your database.', ['CWE-530'], range: true),
    _Probe('/backup.zip', 'exp.archive', 'Site backup archive is public (backup.zip)', Severity.critical, _isArchive, 'Full source and data backups can be downloaded.', ['CWE-530'], range: true),
    _Probe('/site.zip', 'exp.archive', 'Site archive is public (site.zip)', Severity.critical, _isArchive, 'Full source can be downloaded.', ['CWE-530'], range: true),
    _Probe('/www.zip', 'exp.archive', 'Site archive is public (www.zip)', Severity.critical, _isArchive, 'Full source can be downloaded.', ['CWE-530'], range: true),
    _Probe('/backup.tar.gz', 'exp.archive', 'Backup archive is public (backup.tar.gz)', Severity.critical, _isArchive, 'Full backups can be downloaded.', ['CWE-530'], range: true),
    _Probe('/phpinfo.php', 'exp.phpinfo', 'phpinfo() page is public', Severity.high, _isPhpinfo,
        'Shows PHP version, modules, paths and environment variables (sometimes secrets).', ['CWE-200']),
    _Probe('/info.php', 'exp.phpinfo', 'phpinfo() page is public', Severity.high, _isPhpinfo, 'Shows server internals.', ['CWE-200']),
    _Probe('/server-status', 'exp.serverstatus', 'Apache server-status is public', Severity.medium, (r) => r.body.contains('Apache Server Status'),
        'Shows live requests (URLs, client IPs, sometimes tokens in query strings).', ['CWE-200']),
    _Probe('/server-info', 'exp.serverstatus', 'Apache server-info is public', Severity.medium, (r) => r.body.contains('Apache Server Information'),
        'Shows full server configuration.', ['CWE-200']),
    _Probe('/.htpasswd', 'exp.htpasswd', '.htpasswd is public', Severity.high, (r) => RegExp(r'^[^:\s]+:\$(apr1|2y|2a|1)\$', multiLine: true).hasMatch(r.body),
        'Password hashes can be downloaded and cracked offline.', ['CWE-522']),
    _Probe('/.npmrc', 'exp.npmrc', '.npmrc with registry token is public', Severity.critical, (r) => r.body.contains('_authToken'),
        'Package registry tokens allow publishing malicious versions of your packages.', ['CWE-522']),
    _Probe('/web.config', 'exp.webconfig', 'web.config is public', Severity.medium, (r) => r.body.contains('<configuration'), 'Shows server configuration and sometimes connection strings.', ['CWE-538']),
    _Probe('/docker-compose.yml', 'exp.docker', 'docker-compose.yml is public', Severity.medium, (r) => RegExp(r'^services:', multiLine: true).hasMatch(r.body),
        'Shows internal services, images and often passwords in environment variables.', ['CWE-538']),
    _Probe('/.aws/credentials', 'exp.aws', 'AWS credentials file is public', Severity.critical, (r) => r.body.contains('aws_access_key_id'),
        'Gives control of your AWS account.', ['CWE-522']),
    _Probe('/.ssh/id_rsa', 'exp.sshkey', 'SSH private key is public', Severity.critical, (r) => r.body.contains('PRIVATE KEY-----'),
        'Lets anyone log in to servers that trust this key.', ['CWE-522']),
    _Probe('/composer.lock', 'exp.manifest', 'Dependency lock file is public (composer.lock)', Severity.low, (r) => r.body.contains('"packages"'),
        'Exact library versions help attackers pick known exploits.', ['CWE-200'], deps: 'Packagist'),
    _Probe('/package-lock.json', 'exp.manifest', 'Dependency lock file is public (package-lock.json)', Severity.low, (r) => r.body.contains('"lockfileVersion"'),
        'Exact library versions help attackers pick known exploits.', ['CWE-200'], deps: 'npm'),
    _Probe('/package.json', 'exp.manifest', 'package.json is public', Severity.info, (r) => r.body.contains('"dependencies"') || r.body.contains('"scripts"'),
        'Shows libraries and build scripts.', ['CWE-200']),
    _Probe('/storage/logs/laravel.log', 'exp.logs', 'Application log is public (laravel.log)', Severity.high, _isLog,
        'Logs reveal stack traces, paths, SQL and sometimes tokens or personal data.', ['CWE-532']),
    _Probe('/error_log', 'exp.logs', 'PHP error log is public', Severity.medium, _isLog, 'Reveals paths and internal errors.', ['CWE-532']),
    _Probe('/wp-content/debug.log', 'exp.logs', 'WordPress debug log is public', Severity.medium, _isLog, 'Reveals paths and internal errors.', ['CWE-532']),
    _Probe('/debug.log', 'exp.logs', 'Debug log is public', Severity.medium, _isLog, 'Reveals internal errors.', ['CWE-532']),
    _Probe('/actuator/env', 'exp.debug', 'Spring Boot actuator /env is public', Severity.critical, (r) => r.body.contains('"propertySources"'),
        'Shows all configuration including secrets.', ['CWE-215']),
    _Probe('/actuator', 'exp.debug', 'Spring Boot actuator endpoints are public', Severity.medium, (r) => r.body.contains('"_links"') && r.body.contains('actuator'),
        'Management endpoints can reveal configuration and runtime data.', ['CWE-215']),
    _Probe('/_profiler', 'exp.debug', 'Symfony profiler is public', Severity.high, (r) => r.body.contains('Symfony Profiler'),
        'Shows every request with headers, sessions and SQL.', ['CWE-215']),
    _Probe('/telescope', 'exp.debug', 'Laravel Telescope is public', Severity.high, (r) => r.body.contains('Telescope'),
        'Shows requests, queries, jobs and exceptions.', ['CWE-215']),
    _Probe('/_debugbar/open', 'exp.debug', 'Laravel Debugbar is public', Severity.high, (r) => r.body.contains('"__meta"') || r.body.contains('debugbar'),
        'Shows queries, sessions and request data.', ['CWE-215']),
    _Probe('/elmah.axd', 'exp.debug', 'ELMAH error log is public', Severity.high, (r) => r.body.contains('Error Log for'), 'Shows exceptions with cookies and server variables.', ['CWE-215']),
    _Probe('/trace.axd', 'exp.debug', 'ASP.NET trace is public', Severity.high, (r) => r.body.contains('Application Trace'), 'Shows request details and session data.', ['CWE-215']),
  ];

  static bool _isEnv(CyberResponse r) {
    final lines = r.body.split('\n').where((l) => RegExp(r'^\s*[A-Z][A-Z0-9_]{2,}\s*=').hasMatch(l)).length;
    return lines >= 2 && !r.body.contains('<html');
  }

  static bool _isPhpConfig(CyberResponse r) =>
      r.body.contains('<?php') && (r.body.contains('DB_PASSWORD') || r.body.contains('DB_PASS') || r.body.contains('password'));
  static bool _isSql(CyberResponse r) =>
      RegExp(r'(CREATE TABLE|INSERT INTO|-- MySQL dump|PostgreSQL database dump)', caseSensitive: false).hasMatch(r.body) && !r.body.contains('<html');
  static bool _isArchive(CyberResponse r) {
    final ct = r.contentType;
    final b = r.body;
    final magic = b.startsWith('PK\u0003\u0004') || (b.isNotEmpty && b.codeUnitAt(0) == 0x1f);
    final binaryType = (ct.contains('zip') || ct.contains('gzip') || ct.contains('octet-stream') || ct.contains('x-tar')) && !ct.contains('html');
    return binaryType || (magic && !b.contains('<html'));
  }

  static bool _isPhpinfo(CyberResponse r) => r.body.contains('phpinfo()') && r.body.contains('PHP Version');
  static bool _isLog(CyberResponse r) =>
      RegExp(r'(Stack trace:|PHP (Fatal|Warning|Notice|Parse) error|\[\d{4}-\d{2}-\d{2}[ T][\d:]+\] \w+\.(ERROR|WARNING|INFO))').hasMatch(r.body) && !r.body.contains('<html');

  Future<void> exposedFiles() async {
    c.log('Checking ${probes.length} sensitive paths…');
    final reported = <String>{};
    for (final p in probes) {
      if (reported.contains(p.id) && p.id != 'exp.manifest') continue;
      final r = await c.http.get(c.url(p.path), headers: p.range ? const {'range': 'bytes=0-4095'} : const {});
      final ok = (r.status == 200 || r.status == 206) && !(r.status == 200 && (c.notFound?.matches(r) ?? false)) && p.valid(r);
      if (!ok) continue;
      reported.add(p.id);
      final shown = p.id.startsWith('exp.archive')
          ? 'HTTP ${r.status}, Content-Type: ${r.contentType}, ${r.header('content-length') ?? '?'} bytes'
          : redactSecrets(clip(r.body, 400));
      c.add(Finding(
        id: p.id,
        title: p.title,
        severity: p.severity,
        area: CheckArea.exposure,
        evidence: 'GET ${p.path} → ${r.status}\n$shown',
        location: c.url(p.path).toString(),
        impact: p.impact,
        fixSummary: 'Remove the file from the web root and block the pattern in the server configuration (see fix).',
        refs: p.refs,
        confidence: 'confirmed',
        level: ScanLevel.full,
        recheck: () async {
          final again = await c.http.get(c.url(p.path));
          final still = (again.status == 200 || again.status == 206) && !(c.notFound?.matches(again) ?? false) && p.valid(again);
          return still ? [c.report.findings.firstWhere((f) => f.id == p.id)] : <Finding>[];
        },
      ));
      if (p.deps != null) await _depsFromLock(p, r);
    }
  }

  Future<void> _depsFromLock(_Probe p, CyberResponse r) async {
    final pkgs = <OsvPackage>[];
    try {
      final j = jsonDecode(r.body);
      if (p.deps == 'Packagist') {
        for (final x in [...(j['packages'] as List? ?? const [])]) {
          pkgs.add(OsvPackage('${x['name']}', 'Packagist', '${x['version']}'.replaceFirst(RegExp(r'^v'), '')));
        }
      } else {
        final packages = j['packages'];
        if (packages is Map) {
          packages.forEach((k, v) {
            final name = '$k'.split('node_modules/').last;
            if (name.isNotEmpty && v is Map && v['version'] != null) pkgs.add(OsvPackage(name, 'npm', '${v['version']}'));
          });
        }
      }
    } catch (_) {
      return;
    }
    if (pkgs.isEmpty) return;
    c.log('Checking ${pkgs.length} server-side packages from ${p.path} against OSV.dev…');
    final res = await Osv.query(pkgs.take(800).toList());
    for (final e in res.entries.take(25)) {
      final pkg = pkgs.firstWhere((x) => x.name == e.key);
      c.add(osvFinding('dep.server.${e.key}', '${e.key} ${pkg.version}', e.value, CheckArea.dependencies, c.url(p.path).toString(), ScanLevel.full));
    }
  }

  Future<void> directoryListing() async {
    final dirs = ['/uploads/', '/images/', '/files/', '/backup/', '/backups/', '/assets/', '/wp-content/uploads/', '/static/', '/tmp/', '/logs/'];
    final open = <String>[];
    for (final d in dirs) {
      final r = await c.http.get(c.url(d), quiet: true);
      if (r.status == 200 && RegExp(r'(<title>Index of /|<h1>Index of /|Directory listing for /|\[To Parent Directory\])', caseSensitive: false).hasMatch(r.body)) {
        open.add(d);
      }
    }
    if (open.isEmpty) {
      c.pass('exp.listing', 'No open directory listings found', CheckArea.exposure, level: ScanLevel.full);
      return;
    }
    c.add(Finding(
      id: 'exp.listing',
      title: 'Directory listing is enabled',
      severity: open.any((d) => d.contains('backup') || d.contains('logs') || d.contains('tmp')) ? Severity.high : Severity.medium,
      area: CheckArea.exposure,
      evidence: open.map((d) => 'GET $d → "Index of $d"').join('\n'),
      location: c.url(open.first).toString(),
      impact: 'Anyone can browse every file in these folders, including ones you never linked (backups, private uploads).',
      fixSummary: 'Turn off auto-indexing (Apache: Options -Indexes; nginx: autoindex off).',
      refs: const ['CWE-548'],
      confidence: 'confirmed',
      level: ScanLevel.full,
    ));
  }

  Future<void> adminSurfaces() async {
    final panels = <String, String>{
      '/phpmyadmin/': 'phpMyAdmin',
      '/pma/': 'phpMyAdmin',
      '/adminer.php': 'Adminer',
      '/admin/': 'Admin',
      '/administrator/': 'Joomla administrator',
      '/wp-login.php': 'WordPress login',
      '/user/login': 'Login',
      '/cpanel': 'cPanel',
    };
    final dbTools = <String>[];
    final logins = <String>[];
    for (final e in panels.entries) {
      final r = await c.http.get(c.url(e.key), quiet: true);
      if (!_real(r)) continue;
      final b = r.body.toLowerCase();
      if ((e.value == 'phpMyAdmin' && b.contains('phpmyadmin')) || (e.value == 'Adminer' && b.contains('adminer'))) {
        dbTools.add('${e.key} (${e.value})');
      } else if (b.contains('type="password"') || b.contains("type='password'")) {
        logins.add('${e.key} (${e.value})');
      }
    }
    if (dbTools.isNotEmpty) {
      c.add(Finding(
        id: 'access.dbadmin',
        title: 'Database admin tool is reachable from the internet',
        severity: Severity.high,
        area: CheckArea.access,
        evidence: dbTools.join('\n'),
        location: c.base.toString(),
        impact: 'Database tools are targeted by automated password guessing and have had serious vulnerabilities; '
            'one weak password exposes the entire database.',
        fixSummary: 'Remove it from the public site, or allow only your IP / VPN (and put it behind a second login).',
        refs: const ['CWE-284'],
        confidence: 'confirmed',
        level: ScanLevel.full,
      ));
    }
    if (logins.isNotEmpty) {
      c.add(Finding(
        id: 'access.adminlogin',
        title: 'Admin login pages are public',
        severity: Severity.low,
        area: CheckArea.access,
        evidence: logins.join('\n'),
        location: c.base.toString(),
        impact: 'Public admin logins receive constant automated password guessing.',
        fixSummary: 'Require two-factor authentication, limit login attempts, and restrict admin paths by IP where possible.',
        refs: const ['CWE-307'],
        level: ScanLevel.full,
      ));
    }
  }

  Future<void> apiSurfaces() async {
    // GraphQL introspection
    for (final path in ['/graphql', '/api/graphql', '/v1/graphql']) {
      final r = await c.http.send('POST', c.url(path),
          body: jsonEncode({'query': 'query NovaCyberIntrospection { __schema { queryType { name } types { name } } }'}), bodyType: 'application/json');
      if (r.status == 200 && r.body.contains('"__schema"') && r.body.contains('"types"')) {
        final types = RegExp(r'"name"\s*:\s*"([A-Za-z_]\w*)"').allMatches(r.body).map((m) => m[1]!).where((n) => !n.startsWith('__')).toSet();
        c.add(Finding(
          id: 'api.graphql.introspection',
          title: 'GraphQL introspection is enabled',
          severity: Severity.medium,
          area: CheckArea.access,
          evidence: 'POST $path {__schema…} → 200, ${types.length} types (e.g. ${types.take(8).join(', ')})',
          location: c.url(path).toString(),
          impact: 'The whole API schema — every query, mutation and field, including admin-only ones — is listed for attackers.',
          fixSummary: 'Disable introspection in production and enforce authorization on every resolver.',
          refs: const ['CWE-200'],
          confidence: 'confirmed',
          level: ScanLevel.full,
        ));
        break;
      }
    }
    // API documentation
    final docs = <String>[];
    for (final path in ['/swagger.json', '/openapi.json', '/v2/api-docs', '/v3/api-docs', '/swagger/v1/swagger.json', '/api-docs', '/swagger-ui.html', '/swagger-ui/']) {
      final r = await c.http.get(c.url(path), quiet: true);
      if (_real(r) && (r.body.contains('"swagger"') || r.body.contains('"openapi"') || r.body.contains('swagger-ui'))) docs.add(path);
    }
    if (docs.isNotEmpty) {
      c.add(Finding(
        id: 'api.docs',
        title: 'API documentation is public',
        severity: Severity.low,
        area: CheckArea.access,
        evidence: docs.join('\n'),
        location: c.url(docs.first).toString(),
        impact: 'Lists every endpoint and parameter, making it easy to look for unprotected ones.',
        fixSummary: 'Serve API docs only to signed-in developers, or not in production.',
        refs: const ['CWE-200'],
        level: ScanLevel.full,
      ));
    }
  }

  Future<void> sourceMaps() async {
    final exposed = <String>[];
    for (final s in c.scripts.where((u) => u.host == c.host && u.path.endsWith('.js')).take(8)) {
      final r = await c.http.get(s.replace(path: '${s.path}.map', query: ''), quiet: true);
      if (r.status == 200 && r.body.contains('"sources"') && r.body.contains('"mappings"')) exposed.add('${s.path}.map');
    }
    if (exposed.isEmpty) return;
    c.add(Finding(
      id: 'exp.sourcemap',
      title: 'JavaScript source maps are public',
      severity: Severity.low,
      area: CheckArea.exposure,
      evidence: exposed.join('\n'),
      location: c.url(exposed.first).toString(),
      impact: 'The original front-end source (with comments, internal API routes and sometimes keys) can be read.',
      fixSummary: 'Don\'t deploy .map files (or upload them only to your error tracker).',
      refs: const ['CWE-540'],
      confidence: 'confirmed',
      level: ScanLevel.full,
    ));
  }

  // ── Server configuration ───────────────────────────────────────────────────

  Future<void> methods() async {
    final o = await c.http.send('OPTIONS', c.url('/'));
    final allow = (o.header('allow') ?? o.header('access-control-allow-methods') ?? '').toUpperCase();
    final risky = ['PUT', 'DELETE', 'TRACE', 'CONNECT', 'PROPFIND'].where(allow.contains).toList();
    final marker = 'nova-cyber-${c.nonce()}';
    final t = await c.http.send('TRACE', c.url('/'), headers: {'x-nova-cyber-trace': marker});
    if (t.status == 200 && t.body.contains(marker)) {
      c.add(Finding(
        id: 'srv.trace',
        title: 'HTTP TRACE is enabled',
        severity: Severity.medium,
        area: CheckArea.server,
        evidence: 'TRACE / with header X-Nova-Cyber-Trace: $marker → 200 and the header was echoed back.',
        location: c.base.toString(),
        impact: 'TRACE echoes request headers, which can expose HttpOnly cookies and auth headers in cross-site tracing attacks.',
        fixSummary: 'Disable TRACE (Apache: TraceEnable off; nginx rejects it by default; IIS: remove the verb).',
        refs: const ['CWE-693'],
        confidence: 'confirmed',
        level: ScanLevel.full,
      ));
    }
    if (risky.where((m) => m != 'TRACE').isNotEmpty) {
      c.add(Finding(
        id: 'srv.methods',
        title: 'Server advertises write methods (${risky.join(', ')})',
        severity: Severity.low,
        area: CheckArea.server,
        evidence: 'OPTIONS / → Allow: $allow',
        location: c.base.toString(),
        impact: 'If any path accepts PUT/DELETE without authentication, files can be uploaded or removed.',
        fixSummary: 'Allow only GET, POST and HEAD on the web root; enable other methods only on authenticated API routes.',
        refs: const ['CWE-650'],
        level: ScanLevel.full,
      ));
    }
  }

  Future<void> cors() async {
    final evil = 'https://nova-cyber-${c.nonce()}.example';
    final targets = <Uri>{c.url('/'), ...c.links.where((u) => u.path.contains('/api')).take(3)};
    for (final u in targets) {
      final r = await c.http.get(u, headers: {'origin': evil});
      final acao = r.header('access-control-allow-origin');
      final creds = lowerOr(r.header('access-control-allow-credentials')) == 'true';
      if (acao == evil) {
        c.add(Finding(
          id: 'access.cors.reflect',
          title: creds ? 'CORS trusts any website, with cookies' : 'CORS trusts any website',
          severity: creds ? Severity.high : Severity.medium,
          area: CheckArea.access,
          evidence: 'GET ${u.path} with Origin: $evil\n→ Access-Control-Allow-Origin: $acao${creds ? '\n→ Access-Control-Allow-Credentials: true' : ''}',
          location: u.toString(),
          impact: creds
              ? 'Any website a signed-in user visits can read your API responses as that user (account data, tokens).'
              : 'Any website can read these responses from a visitor\'s browser.',
          fixSummary: 'Allow only your own origins from a fixed list; never reflect the Origin header with credentials.',
          refs: const ['CWE-942'],
          confidence: 'confirmed',
          level: ScanLevel.full,
        ));
        return;
      }
      final rn = await c.http.get(u, headers: {'origin': 'null'}, quiet: true);
      if (rn.header('access-control-allow-origin') == 'null' && lowerOr(rn.header('access-control-allow-credentials')) == 'true') {
        c.add(Finding(
          id: 'access.cors.null',
          title: 'CORS trusts the "null" origin with cookies',
          severity: Severity.high,
          area: CheckArea.access,
          evidence: 'GET ${u.path} with Origin: null → Access-Control-Allow-Origin: null, Allow-Credentials: true',
          location: u.toString(),
          impact: 'Sandboxed iframes on any site send Origin: null, so any site can read responses as the user.',
          fixSummary: 'Remove "null" from allowed origins.',
          refs: const ['CWE-942'],
          confidence: 'confirmed',
          level: ScanLevel.full,
        ));
        return;
      }
    }
    c.pass('access.cors', 'CORS doesn\'t trust arbitrary origins', CheckArea.access, level: ScanLevel.full);
  }

  Future<void> hostHeader() async {
    final fake = 'nova-cyber-${c.nonce()}.example';
    final r = await c.http.get(c.url('/'), headers: {'x-forwarded-host': fake});
    final inLoc = (r.location ?? '').contains(fake);
    final inBody = r.body.contains(fake);
    if (!inLoc && !inBody) return;
    c.add(Finding(
      id: 'access.hostheader',
      title: 'The site trusts the X-Forwarded-Host header',
      severity: Severity.medium,
      area: CheckArea.access,
      evidence: 'GET / with X-Forwarded-Host: $fake → ${inLoc ? 'Location: ${r.location}' : around(r.body, fake)}',
      location: c.base.toString(),
      impact: 'Links the site builds (password-reset emails, redirects, cached pages) can be made to point to an attacker\'s domain.',
      fixSummary: 'Build absolute URLs from a configured base URL; only trust forwarding headers from your own proxy.',
      refs: const ['CWE-644'],
      confidence: 'confirmed',
      level: ScanLevel.full,
    ));
  }

  // ── Parameters: reflection, injection, redirects ───────────────────────────

  static const List<String> _dbErrors = [
    'you have an error in your sql syntax',
    'warning: mysql',
    'mysqli_sql_exception',
    'unclosed quotation mark after the character string',
    'quoted string not properly terminated',
    'pg::syntaxerror',
    'pg_query(): query failed',
    'syntax error at or near',
    'sqlite3::sqlexception',
    'sqlite_error',
    'ora-00933',
    'ora-01756',
    'sqlstate[42000]',
    'sqlstate[hy000]',
    'microsoft ole db provider for sql server',
    'odbc sql server driver',
    'jdbc.sqlserverexception',
    'org.hibernate.exception',
  ];

  static const Set<String> _redirectParams = {
    'next', 'url', 'redirect', 'redirect_uri', 'redirect_url', 'return', 'returnto', 'return_to', 'returnurl', 'continue',
    'dest', 'destination', 'goto', 'target', 'r', 'u', 'callback', 'forward', 'to', 'out', 'link'
  };
  static const Set<String> _fileParams = {'file', 'path', 'page', 'template', 'include', 'doc', 'document', 'folder', 'dir', 'view', 'lang', 'load'};

  /// (page, parameter name, original value) to test.
  List<(Uri, String, String)> _targets() {
    final out = <(Uri, String, String)>[];
    final seen = <String>{};
    void add(Uri u, String name, String value) {
      final key = '${u.path}|$name';
      if (seen.add(key)) out.add((u, name, value));
    }

    for (final u in c.links) {
      u.queryParameters.forEach((k, v) => add(u.replace(fragment: ''), k, v));
    }
    for (final f in c.forms) {
      if ((f['method'] as String) != 'get') continue;
      final action = f['action'] as Uri;
      if (action.host != c.host) continue;
      for (final i in (f['inputs'] as List).cast<Map<String, String>>()) {
        if (const {'password', 'file', 'hidden', 'submit'}.contains(i['type'])) continue;
        add(action, i['name']!, i['value']!.isEmpty ? 'test' : i['value']!);
      }
    }
    for (final p in const ['q', 's', 'search', 'query', 'id', 'page', 'redirect', 'next', 'url']) {
      add(c.url('/'), p, p == 'id' || p == 'page' ? '1' : 'test');
    }
    return out.take(24).toList();
  }

  Uri _with(Uri u, String name, String value) => u.replace(queryParameters: {...u.queryParameters, name: value});

  Future<void> parameters() async {
    final targets = _targets();
    c.log('Testing ${targets.length} parameters with harmless markers…');
    final xss = <String>[], xssPartial = <String>[], sqlErr = <String>[], sqlBool = <String>[], ssti = <String>[], redir = <String>[], trav = <String>[];
    for (final (page, name, value) in targets) {
      final base = await c.http.get(_with(page, name, value), quiet: true);
      if (base.status == 0) continue;

      // Reflection (XSS): unique marker with characters that must be encoded.
      final m = 'nxc${c.nonce(6)}';
      final probe = '$m\'"<nxcx>';
      final rx = await c.http.get(_with(page, name, probe), quiet: true);
      if (rx.body.contains('$m\'"<nxcx>') || rx.body.contains('$m"<nxcx>') || rx.body.contains('<nxcx>') && rx.body.contains(m)) {
        final ctx = _context(rx.body, m);
        xss.add('${page.path}?$name= → reflected unencoded in $ctx\n  ${around(rx.body, m, 60)}');
      } else if (rx.body.contains('$m\'"') || rx.body.contains('$m"')) {
        xssPartial.add('${page.path}?$name= → quotes reflected unencoded (${_context(rx.body, m)})');
      }

      // Template injection: arithmetic that only a template engine evaluates.
      final t = 'nxc${c.nonce(4)}';
      final rt = await c.http.get(_with(page, name, '$t{{191*7}}$t'), quiet: true);
      if (rt.body.contains('${t}1337$t') && !base.body.contains('${t}1337$t')) {
        ssti.add('${page.path}?$name= → "{{191*7}}" was evaluated to 1337');
      }

      // SQL errors: a lone quote should never produce a database error.
      final rq = await c.http.get(_with(page, name, "$value'"), quiet: true);
      final lowB = base.body.toLowerCase(), lowQ = rq.body.toLowerCase();
      final err = _dbErrors.firstWhere((e) => lowQ.contains(e) && !lowB.contains(e), orElse: () => '');
      if (err.isNotEmpty) {
        final at = lowQ.indexOf(err);
        sqlErr.add('${page.path}?$name= → database error after adding a quote: "${around(rq.body, rq.body.substring(at, at + err.length), 50)}"');
      }

      // Numeric expression evaluated by the server (id=5 vs id=6-1 vs id=6).
      final n = int.tryParse(value);
      if (n != null && n > 0 && base.ok) {
        final same = await c.http.get(_with(page, name, '${n + 1}-1'), quiet: true);
        final other = await c.http.get(_with(page, name, '${n + 1}'), quiet: true);
        if (_similar(base.body, same.body) && !_similar(base.body, other.body) && same.status == base.status) {
          final again = await c.http.get(_with(page, name, '${n + 2}-2'), quiet: true);
          if (_similar(base.body, again.body)) sqlBool.add('${page.path}?$name= → "${n + 1}-1" returns the same page as "$n" (the input is evaluated)');
        }
      }

      // Open redirect
      if (_redirectParams.contains(name.toLowerCase())) {
        final dest = 'https://nova-cyber-${c.nonce(6)}.example/';
        for (final v in [dest, '//${Uri.parse(dest).host}/']) {
          final rr = await c.http.get(_with(page, name, v), quiet: true);
          final loc = rr.location ?? '';
          final refresh = RegExp(r'''http-equiv=["']?refresh["']?[^>]*url=([^"'>\s]+)''', caseSensitive: false).firstMatch(rr.body)?.group(1) ?? '';
          final to = loc.isNotEmpty ? loc : refresh;
          if (to.contains(Uri.parse(dest).host) && (Uri.tryParse(to.startsWith('//') ? 'https:$to' : to)?.host == Uri.parse(dest).host)) {
            redir.add('${page.path}?$name=$v → ${rr.status} redirect to $to');
            break;
          }
        }
      }

      // Path traversal (only for file-like parameters): read-only check for a
      // well-known system file signature; contents are never shown.
      if (_fileParams.contains(name.toLowerCase())) {
        for (final v in const ['../../../../../../etc/passwd', r'..\..\..\..\..\..\windows\win.ini']) {
          final rp = await c.http.get(_with(page, name, v), quiet: true);
          final unix = RegExp(r'root:[x*]?:0:0:').hasMatch(rp.body) && !RegExp(r'root:[x*]?:0:0:').hasMatch(base.body);
          final win = rp.body.contains('[fonts]') && rp.body.contains('[extensions]') && !base.body.contains('[fonts]');
          if (unix || win) {
            trav.add('${page.path}?$name= → server file contents returned (${unix ? '/etc/passwd' : 'win.ini'} signature; content not shown)');
            break;
          }
        }
      }
    }

    void report(List<String> list, String id, String title, Severity sev, String impact, String fix, List<String> refs, {String confidence = 'firm'}) {
      if (list.isEmpty) return;
      c.add(Finding(
        id: id,
        title: title,
        severity: sev,
        area: CheckArea.injection,
        evidence: list.take(8).join('\n'),
        location: c.base.toString(),
        impact: impact,
        fixSummary: fix,
        refs: refs,
        confidence: confidence,
        level: ScanLevel.full,
      ));
    }

    report(xss, 'inj.xss.reflected', 'Reflected cross-site scripting (XSS)', Severity.high,
        'An attacker can craft a link that runs their JavaScript on your site in the victim\'s browser — stealing sessions, '
            'changing account details or showing fake login forms.',
        'HTML-encode every value you output for its context (HTML, attribute, JavaScript, URL) and add a strict CSP.',
        const ['CWE-79', 'OWASP A03:2021']);
    report(xssPartial, 'inj.xss.partial', 'Input is reflected without full encoding', Severity.low,
        'Quotes are not encoded; in some contexts (attributes, inline scripts) this becomes XSS.',
        'Encode quotes as well as < and > when outputting user input.', const ['CWE-79'],
        confidence: 'tentative');
    report(ssti, 'inj.ssti', 'Server-side template injection', Severity.critical,
        'Template expressions from users are executed on the server. Depending on the engine this allows reading files or running commands.',
        'Never build templates from user input; pass input only as template variables.', const ['CWE-1336', 'OWASP A03:2021'],
        confidence: 'confirmed');
    report(sqlErr, 'inj.sql.error', 'SQL injection (database error on a quote)', Severity.high,
        'User input reaches SQL queries unescaped. Attackers can read or change the whole database.',
        'Use prepared statements / parameterised queries for every query.', const ['CWE-89', 'OWASP A03:2021']);
    report(sqlBool, 'inj.sql.expression', 'Input is evaluated by the server (likely SQL injection)', Severity.high,
        'Arithmetic in the parameter changes the result, which means the value is inserted into a query or expression without binding.',
        'Use prepared statements and validate numeric parameters as integers.', const ['CWE-89', 'CWE-95']);
    report(redir, 'access.redirect.open', 'Open redirect', Severity.medium,
        'Links on your domain can send users to any site, which makes phishing links look trustworthy and can leak OAuth tokens.',
        'Allow only relative paths or a fixed list of destinations.', const ['CWE-601'],
        confidence: 'confirmed');
    report(trav, 'inj.traversal', 'Path traversal (server files can be read)', Severity.critical,
        'Attackers can read any file the web server can — configuration, source code, keys.',
        'Never use user input in file paths; map allowed names to files on the server.', const ['CWE-22', 'OWASP A01:2021'],
        confidence: 'confirmed');
    if (xss.isEmpty && ssti.isEmpty && sqlErr.isEmpty && sqlBool.isEmpty && trav.isEmpty) {
      c.pass('inj.none', 'No injection found in ${targets.length} parameters', CheckArea.injection, level: ScanLevel.full);
    }
  }

  static String _context(String body, String marker) {
    final i = body.indexOf(marker);
    if (i < 0) return 'the page';
    final before = body.substring(0, i);
    final lastScriptOpen = before.toLowerCase().lastIndexOf('<script');
    final lastScriptClose = before.toLowerCase().lastIndexOf('</script');
    if (lastScriptOpen > lastScriptClose) return 'a <script> block';
    final lastTagOpen = before.lastIndexOf('<');
    final lastTagClose = before.lastIndexOf('>');
    if (lastTagOpen > lastTagClose) return 'an HTML attribute';
    return 'the HTML body';
  }

  static bool _similar(String a, String b) {
    if (a.isEmpty && b.isEmpty) return true;
    final la = a.length, lb = b.length;
    if ((la - lb).abs() > (la > lb ? la : lb) * 0.02 + 32) return false;
    String strip(String s) => s.replaceAll(RegExp(r'(nonce|csrf|token|_ga|timestamp|time)[^"&\s]*'), '').replaceAll(RegExp(r'\d{6,}'), '');
    return strip(a).length == strip(b).length || (strip(a).length - strip(b).length).abs() < 16;
  }

  // ── WordPress ──────────────────────────────────────────────────────────────

  Future<void> wordpress() async {
    final users = await c.http.get(c.url('/wp-json/wp/v2/users'));
    if (users.status == 200 && users.body.trim().startsWith('[') && users.body.contains('"slug"')) {
      final slugs = RegExp(r'"slug"\s*:\s*"([^"]+)"').allMatches(users.body).map((m) => m[1]!).toList();
      c.add(Finding(
        id: 'wp.users',
        title: 'WordPress lists user names publicly',
        severity: Severity.medium,
        area: CheckArea.access,
        evidence: 'GET /wp-json/wp/v2/users → ${slugs.length} accounts: ${slugs.take(10).join(', ')}',
        location: c.url('/wp-json/wp/v2/users').toString(),
        impact: 'Login names (often the admin) are half of what password-guessing attacks need.',
        fixSummary: 'Restrict the users endpoint to signed-in users (security plugin or a small filter on rest_endpoints).',
        refs: const ['CWE-200'],
        confidence: 'confirmed',
        level: ScanLevel.full,
      ));
    }
    final x = await c.http.get(c.url('/xmlrpc.php'));
    if (x.body.contains('XML-RPC server accepts POST requests only')) {
      c.add(Finding(
        id: 'wp.xmlrpc',
        title: 'WordPress XML-RPC is enabled',
        severity: Severity.medium,
        area: CheckArea.access,
        evidence: 'GET /xmlrpc.php → "XML-RPC server accepts POST requests only."',
        location: c.url('/xmlrpc.php').toString(),
        impact: 'XML-RPC lets attackers try hundreds of passwords in one request (system.multicall) and is used for DDoS pingbacks.',
        fixSummary: 'Disable XML-RPC unless the Jetpack/mobile app needs it.',
        refs: const ['CWE-307'],
        confidence: 'confirmed',
        level: ScanLevel.full,
      ));
    }
    // Plugin versions referenced by the page (?ver=) → check readme "Stable tag".
    final plugins = <String>{};
    for (final m in RegExp(r'/wp-content/plugins/([a-z0-9_-]+)/').allMatches(c.home.body)) {
      plugins.add(m[1]!);
    }
    final versions = <String>[];
    for (final p in plugins.take(15)) {
      final r = await c.http.get(c.url('/wp-content/plugins/$p/readme.txt'), quiet: true);
      final v = RegExp(r'Stable tag:\s*([\d.]+)', caseSensitive: false).firstMatch(r.body)?.group(1);
      if (v != null) versions.add('$p $v');
    }
    final wpv = c.report.tech.versions['wordpress'];
    if (wpv != null || versions.isNotEmpty) {
      c.add(Finding(
        id: 'wp.inventory',
        title: 'WordPress core and plugin versions are visible',
        severity: Severity.info,
        area: CheckArea.dependencies,
        evidence: [if (wpv != null) 'WordPress $wpv', ...versions].join('\n'),
        impact: 'Most WordPress compromises come from outdated plugins. Compare these versions with the latest releases.',
        fixSummary: 'Turn on automatic updates for plugins and remove plugins you don\'t use.',
        level: ScanLevel.full,
      ));
    }
  }

  // ── Login rate limiting (opt-in) ───────────────────────────────────────────

  Future<void> loginRateLimit() async {
    final form = c.forms.firstWhere(
        (f) => (f['method'] as String) == 'post' && (f['inputs'] as List).cast<Map<String, String>>().any((i) => i['type'] == 'password'),
        orElse: () => const {});
    if (form.isEmpty) {
      c.log('Login rate limit: no login form found on the scanned pages.');
      return;
    }
    final action = form['action'] as Uri;
    final inputs = (form['inputs'] as List).cast<Map<String, String>>();
    final user = 'nova-cyber-check-${c.nonce(8)}@invalid.example';
    final statuses = <int>[];
    var limited = false;
    for (var i = 0; i < 6; i++) {
      final fields = <String, String>{};
      for (final f in inputs) {
        final t = f['type'];
        if (t == 'password') {
          fields[f['name']!] = 'Wrong-${c.nonce(12)}';
        } else if (t == 'email' || RegExp(r'(user|email|login|name)', caseSensitive: false).hasMatch(f['name']!)) {
          fields[f['name']!] = user;
        } else {
          fields[f['name']!] = f['value'] ?? '';
        }
      }
      final r = await c.http.send('POST', action,
          body: fields.entries.map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}').join('&'));
      statuses.add(r.status);
      final b = r.body.toLowerCase();
      if (r.status == 429 || b.contains('too many') || b.contains('captcha') || b.contains('locked') || b.contains('try again later') || b.contains('recaptcha') || b.contains('turnstile')) {
        limited = true;
        break;
      }
    }
    if (limited) {
      c.pass('access.login.ratelimit', 'Login slows down repeated failures', CheckArea.access, level: ScanLevel.full);
      return;
    }
    c.add(Finding(
      id: 'access.login.ratelimit',
      title: 'Login doesn\'t limit repeated failed attempts',
      severity: Severity.medium,
      area: CheckArea.access,
      evidence: '6 failed sign-ins for a made-up account ($user) → ${statuses.join(', ')}; no 429, CAPTCHA or lockout message.',
      location: action.toString(),
      impact: 'Attackers can try leaked passwords against your users (credential stuffing) at full speed.',
      fixSummary: 'Limit attempts per account and per IP (e.g. 5 per 15 minutes), add a CAPTCHA after failures, and offer 2FA.',
      refs: const ['CWE-307', 'OWASP A07:2021'],
      confidence: 'firm',
      level: ScanLevel.full,
    ));
  }

  // ── Network services ───────────────────────────────────────────────────────

  static const Map<int, (String, Severity)> servicePorts = {
    21: ('FTP', Severity.medium),
    23: ('Telnet', Severity.high),
    445: ('SMB (Windows file sharing)', Severity.high),
    1433: ('Microsoft SQL Server', Severity.high),
    1521: ('Oracle database', Severity.high),
    2375: ('Docker API (no TLS)', Severity.critical),
    2379: ('etcd', Severity.critical),
    3306: ('MySQL / MariaDB', Severity.high),
    3389: ('Remote Desktop (RDP)', Severity.high),
    5432: ('PostgreSQL', Severity.high),
    5601: ('Kibana', Severity.high),
    5900: ('VNC', Severity.high),
    6379: ('Redis', Severity.critical),
    8080: ('HTTP (alternate port)', Severity.info),
    8443: ('HTTPS (alternate port)', Severity.info),
    9000: ('Admin / PHP-FPM port', Severity.medium),
    9200: ('Elasticsearch', Severity.critical),
    11211: ('Memcached', Severity.high),
    27017: ('MongoDB', Severity.critical),
  };

  Future<void> ports() async {
    if (c.report.tech.stack.contains('cloudflare') || c.report.tech.stack.contains('vercel') || c.report.tech.stack.contains('netlify')) {
      c.log('Ports: the site is behind a CDN/proxy, so its address is the provider\'s — port check skipped.');
      return;
    }
    List<InternetAddress> addrs;
    try {
      addrs = await InternetAddress.lookup(c.host);
    } catch (_) {
      return;
    }
    if (addrs.isEmpty) return;
    final ip = addrs.first;
    c.log('Checking ${servicePorts.length} service ports on ${ip.address} (connect only)…');
    final open = <int>[];
    await Future.wait([
      for (final p in servicePorts.keys)
        () async {
          try {
            final s = await Socket.connect(ip, p, timeout: const Duration(seconds: 3));
            s.destroy();
            open.add(p);
          } catch (_) {}
        }(),
    ]);
    open.sort();
    for (final p in open) {
      final (name, sev) = servicePorts[p]!;
      if (sev == Severity.info) continue;
      c.add(Finding(
        id: 'net.port.$p',
        title: '$name is reachable from the internet (port $p)',
        severity: sev,
        area: CheckArea.server,
        evidence: 'TCP connection to ${ip.address}:$p succeeded.',
        location: '${c.host}:$p',
        impact: sev == Severity.critical
            ? '$name is often run without a password; exposed instances are found and taken over within hours (data theft, ransom notes, crypto-miners).'
            : '$name should not be open to the whole internet; it is a constant target for password guessing and exploits.',
        fixSummary: 'Close the port in your firewall / cloud security group, or allow only specific IPs (or a VPN). Bind the service to 127.0.0.1 if only the web app uses it.',
        refs: const ['CWE-284'],
        confidence: 'confirmed',
        level: ScanLevel.full,
      ));
    }
    if (open.where((p) => servicePorts[p]!.$2 != Severity.info).isEmpty) {
      c.pass('net.ports', 'No database or admin ports open to the internet', CheckArea.server, level: ScanLevel.full);
    }
  }

  // ── Subdomains (public certificate logs) ───────────────────────────────────

  Future<void> subdomains() async {
    final domain = registrableDomain(c.host);
    final r = await c.http.send('GET', Uri.https('crt.sh', '/', {'q': '%.$domain', 'output': 'json'}), timeout: const Duration(seconds: 30), quiet: true);
    c.http.sent--;
    if (!r.ok) return;
    final names = <String>{};
    try {
      for (final e in (jsonDecode(r.body) as List)) {
        for (final n in '${e['name_value']}'.split('\n')) {
          final h = n.trim().toLowerCase();
          if (h.endsWith(domain) && !h.contains('*')) names.add(h);
        }
      }
    } catch (_) {
      return;
    }
    names.remove(c.host);
    c.log('Found ${names.length} subdomains in certificate logs — checking for takeovers…');
    for (final h in names.take(40)) {
      await quick.takeover(h, level: ScanLevel.full);
    }
    if (names.isNotEmpty) {
      c.add(Finding(
        id: 'dns.subdomains',
        title: '${names.length} subdomains are listed in public certificate logs',
        severity: Severity.info,
        area: CheckArea.dns,
        evidence: (names.toList()..sort()).take(40).join('\n'),
        impact: 'Every subdomain is part of your attack surface. Forgotten ones (old staging, test, admin) are often unpatched.',
        fixSummary: 'Review the list; remove DNS for anything unused and scan the rest.',
        level: ScanLevel.full,
      ));
    }
  }
}

class _Probe {
  _Probe(this.path, this.id, this.title, this.severity, this.valid, this.impact, this.refs, {this.range = false, this.deps});
  final String path;
  final String id;
  final String title;
  final Severity severity;
  final bool Function(CyberResponse r) valid;
  final String impact;
  final List<String> refs;
  final bool range;
  final String? deps;
}
