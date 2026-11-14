// lib/features/cyber/engine/cyber_code_scan.dart
//
// NOVA Cyber — Code scan. Reads a project on the device (nothing is uploaded
// except package names + versions to OSV.dev) and finds:
// Android (3.13.0): scanFiles() reads a picked .zip or picked files in memory
// (no All-Files permission); scan() still reads a folder.
//  • hard-coded secrets (keys, tokens, private keys, DB URLs)
//  • dangerous code patterns (SQL built from input, eval, shell commands
//    with input, disabled TLS checks, weak hashing for passwords…)
//  • dependencies with known vulnerabilities (npm, Composer, PyPI, Pub)

import 'dart:convert';
import 'dart:io';

import 'cyber_models.dart';
import 'cyber_osv.dart';
import 'checks_quick.dart' show osvFinding;

class CodeRule {
  const CodeRule(this.id, this.title, this.severity, this.exts, this.pattern, this.impact, this.fix, this.refs);
  final String id;
  final String title;
  final Severity severity;
  final Set<String> exts; // empty = all text files
  final RegExp pattern;
  final String impact;
  final String fix;
  final List<String> refs;
}

final List<CodeRule> codeRules = [
  // Secrets
  CodeRule('code.secret.aws', 'AWS access key in code', Severity.critical, const {}, RegExp(r'\b(AKIA|ASIA)[A-Z0-9]{16}\b'),
      'Anyone with the code (or a leaked repo) controls your AWS account.', 'Revoke the key in IAM; load credentials from the environment or a role.', const ['CWE-798']),
  CodeRule('code.secret.private_key', 'Private key in code', Severity.critical, const {}, RegExp(r'-----BEGIN (RSA |EC |OPENSSH |DSA |)PRIVATE KEY-----'),
      'Private keys allow impersonating your servers or signing as you.', 'Remove it, rotate the key pair, keep keys in a secrets manager.', const ['CWE-321']),
  CodeRule('code.secret.stripe', 'Stripe secret key in code', Severity.critical, const {}, RegExp(r'\bsk_live_[0-9a-zA-Z]{20,}\b'),
      'Full access to payments and customers.', 'Roll the key in Stripe and load it from the environment.', const ['CWE-798']),
  CodeRule('code.secret.github', 'GitHub token in code', Severity.critical, const {}, RegExp(r'\bgh[pousr]_[A-Za-z0-9]{36,}\b'),
      'Access to your repositories and possibly CI secrets.', 'Revoke the token at github.com/settings/tokens.', const ['CWE-798']),
  CodeRule('code.secret.ai', 'AI provider secret key in code', Severity.critical, const {}, RegExp(r'\b(sk-(proj-)?[A-Za-z0-9_-]{32,}|gsk_[A-Za-z0-9]{40,})\b'),
      'Anyone can use your AI account and run up your bill.', 'Revoke the key; call the AI provider from your server only.', const ['CWE-798']),
  CodeRule('code.secret.slack', 'Slack token in code', Severity.high, const {}, RegExp(r'\bxox[baprs]-[A-Za-z0-9-]{10,}\b'),
      'Read and post messages in your workspace.', 'Revoke the token in Slack.', const ['CWE-798']),
  CodeRule('code.secret.sendgrid', 'SendGrid key in code', Severity.critical, const {}, RegExp(r'\bSG\.[A-Za-z0-9_-]{22}\.[A-Za-z0-9_-]{43}\b'),
      'Send email as your domain (phishing).', 'Revoke the key in SendGrid.', const ['CWE-798']),
  CodeRule('code.secret.dburl', 'Database URL with password in code', Severity.critical, const {},
      RegExp(r'\b(mongodb(\+srv)?|postgres(ql)?|mysql|redis)://[^\s:@/"\x27]+:[^\s@"\x27]{3,}@'),
      'Direct access to your database.', 'Change the database password; load the URL from the environment.', const ['CWE-798']),
  CodeRule('code.secret.assign', 'Password or secret assigned in code', Severity.high, const {'php', 'js', 'ts', 'py', 'dart', 'java', 'kt', 'go', 'rb', 'cs', 'json', 'yml', 'yaml', 'env'},
      RegExp(r'''\b(db_?pass(word)?|password|passwd|secret(_?key)?|api_?key|auth_?token|private_?key)\b\s*[:=]\s*["']([^"'\s$]{8,})["']''', caseSensitive: false),
      'Secrets in source code end up in repositories, backups and builds.', 'Move it to environment variables / a secrets manager and rotate it.', const ['CWE-798']),

  // Injection
  CodeRule('code.sqli.php', 'SQL built from request input (PHP)', Severity.critical, const {'php'},
      RegExp(r'''(mysqli_query|->query|->exec|mysql_query|pg_query)\s*\([^;]*\$_(GET|POST|REQUEST|COOKIE)'''),
      'Attackers can read or change the database.', 'Use prepared statements (\$pdo->prepare + execute).', const ['CWE-89']),
  CodeRule('code.sqli.concat', 'SQL query built by string concatenation', Severity.high, const {'php', 'js', 'ts', 'py', 'java', 'cs', 'go', 'rb', 'kt'},
      RegExp(r'''["'`]\s*(SELECT|INSERT|UPDATE|DELETE)\b[^;\n]{0,200}?\b(WHERE|VALUES|SET)\b[^;\n]*?["'`]\s*(\+|\.)\s*\$?[A-Za-z_]''', caseSensitive: false),
      'If any part comes from users, this is SQL injection.', 'Use parameter placeholders (?, \$1, :name) instead of concatenation.', const ['CWE-89']),
  CodeRule('code.sqli.template', 'SQL query built with template strings', Severity.high, const {'js', 'ts'},
      RegExp(r'''\.(query|execute|raw)\s*\(\s*`[^`]*\b(SELECT|INSERT|UPDATE|DELETE)\b[^`]*\$\{''', caseSensitive: false),
      'Interpolating values into SQL allows injection.', 'Pass values as parameters: db.query("… WHERE id = \$1", [id]).', const ['CWE-89']),
  CodeRule('code.cmd.php', 'Shell command with request input (PHP)', Severity.critical, const {'php'},
      RegExp(r'''\b(system|exec|shell_exec|passthru|popen|proc_open)\s*\([^;]*\$_(GET|POST|REQUEST|COOKIE)'''),
      'Remote command execution: attackers run any command on your server.', 'Never pass input to the shell; use escapeshellarg or a library call.', const ['CWE-78']),
  CodeRule('code.cmd.node', 'Shell command built from variables (Node)', Severity.high, const {'js', 'ts'},
      RegExp(r'''\b(exec|execSync)\s*\(\s*(`[^`]*\$\{|[^)]*\+\s*(req|request|params|query|body)\b)'''),
      'Command injection if any part comes from users.', 'Use execFile/spawn with an argument array, never a shell string.', const ['CWE-78']),
  CodeRule('code.cmd.python', 'subprocess with shell=True', Severity.medium, const {'py'}, RegExp(r'subprocess\.\w+\([^)]*shell\s*=\s*True'),
      'Command injection if the command contains input.', 'Pass a list of arguments and shell=False.', const ['CWE-78']),
  CodeRule('code.eval.php', 'eval / include with request input (PHP)', Severity.critical, const {'php'},
      RegExp(r'''\b(eval|assert|include|include_once|require|require_once)\s*\(?[^;]*\$_(GET|POST|REQUEST|COOKIE)'''),
      'Remote code execution or reading any file.', 'Never evaluate or include user-controlled values; use an allow-list.', const ['CWE-95', 'CWE-98']),
  CodeRule('code.eval.js', 'eval / new Function', Severity.medium, const {'js', 'ts', 'html'}, RegExp(r'''\b(eval\s*\(|new\s+Function\s*\()'''),
      'Runs strings as code; with user input this is code injection and it blocks a strict CSP.', 'Use JSON.parse or explicit logic instead.', const ['CWE-95']),
  CodeRule('code.xss.innerhtml', 'innerHTML / document.write with dynamic values', Severity.medium, const {'js', 'ts', 'html', 'jsx', 'tsx'},
      RegExp(r'''(\.innerHTML\s*=\s*[^"'`;]*[A-Za-z_$]|\.outerHTML\s*=|document\.write\s*\(|dangerouslySetInnerHTML)'''),
      'Inserting unescaped values into HTML causes DOM XSS.', 'Use textContent, or sanitize with DOMPurify before inserting HTML.', const ['CWE-79']),
  CodeRule('code.xss.php', 'Request input echoed without escaping (PHP)', Severity.high, const {'php'},
      RegExp(r'''\b(echo|print)\b(?![^;]*(htmlspecialchars|htmlentities|esc_html|esc_attr|intval|\(int\)))[^;]*\$_(GET|POST|REQUEST|COOKIE)\['''),
      'Reflected XSS.', 'Wrap output in htmlspecialchars(\$v, ENT_QUOTES, "UTF-8").', const ['CWE-79']),
  CodeRule('code.deserialize.php', 'unserialize() on request input', Severity.critical, const {'php'}, RegExp(r'''unserialize\s*\([^;]*\$_(GET|POST|REQUEST|COOKIE)'''),
      'PHP object injection can lead to code execution.', 'Use json_decode instead.', const ['CWE-502']),
  CodeRule('code.deserialize.py', 'Unsafe deserialization (pickle / yaml.load)', Severity.high, const {'py'},
      RegExp(r'''(pickle\.loads?\s*\(|yaml\.load\s*\((?![^)]*SafeLoader))'''),
      'Loading untrusted data this way runs code.', 'Use json, or yaml.safe_load.', const ['CWE-502']),

  // Crypto & TLS
  CodeRule('code.tls.disabled', 'TLS certificate checks are disabled', Severity.high, const {},
      RegExp(r'''(rejectUnauthorized\s*:\s*false|NODE_TLS_REJECT_UNAUTHORIZED\s*=\s*['"]?0|verify\s*=\s*False|CURLOPT_SSL_VERIFYPEER\s*,\s*(false|0)|InsecureSkipVerify\s*:\s*true|badCertificateCallback\s*=\s*\([^)]*\)\s*=>\s*true)'''),
      'Connections can be intercepted (man-in-the-middle) without any error.', 'Remove the override; fix the certificate chain instead.', const ['CWE-295']),
  CodeRule('code.crypto.password', 'Weak password hashing (md5/sha1)', Severity.high, const {'php', 'js', 'ts', 'py', 'java', 'cs', 'go', 'rb'},
      RegExp(r'''(md5|sha1)\s*\(\s*\$?[A-Za-z_]*pass''', caseSensitive: false),
      'MD5/SHA-1 password hashes are cracked in seconds with GPUs.', 'Use password_hash() (PHP), bcrypt/argon2 (Node, Python).', const ['CWE-916']),
  CodeRule('code.jwt.none', 'JWT verification may accept "none" / is disabled', Severity.high, const {'js', 'ts', 'py', 'php'},
      RegExp(r'''(algorithms\s*:\s*\[[^\]]*['"]none['"]|verify\s*=\s*False|verify_signature['"]?\s*:\s*False|jwt\.decode\([^)]*,\s*null)'''),
      'Attackers can forge tokens and log in as anyone.', 'Always verify with a fixed algorithm list and the secret/public key.', const ['CWE-347']),
  CodeRule('code.cors.any', 'CORS allows any origin with credentials', Severity.high, const {'js', 'ts', 'php', 'py'},
      RegExp(r'''(origin\s*:\s*(true|['"]\*['"])[^}]*credentials\s*:\s*true|Access-Control-Allow-Origin:\s*['"]?\s*\.\s*\$_SERVER\[['"]HTTP_ORIGIN)'''),
      'Any website can read responses as your signed-in users.', 'Use a fixed allow-list of origins.', const ['CWE-942']),
  CodeRule('code.debug.on', 'Debug mode enabled in config', Severity.medium, const {'env', 'py', 'php', 'json', 'yml', 'yaml'},
      RegExp(r'''^\s*(APP_DEBUG\s*=\s*true|DEBUG\s*=\s*True|['"]debug['"]\s*=>\s*true)''', multiLine: true),
      'Debug pages reveal source, environment variables and secrets to visitors.', 'Turn debug off in production configuration.', const ['CWE-489']),
];

const Set<String> _textExts = {
  'php', 'js', 'mjs', 'cjs', 'ts', 'jsx', 'tsx', 'py', 'dart', 'java', 'kt', 'go', 'rb', 'cs', 'html', 'htm', 'vue', 'svelte',
  'json', 'yml', 'yaml', 'env', 'ini', 'conf', 'config', 'xml', 'sh', 'ps1', 'sql', 'txt', 'properties', 'toml', 'twig', 'blade',
};
const Set<String> _skipDirs = {'node_modules', '.git', 'vendor', 'build', 'dist', '.dart_tool', '.next', '.nuxt', 'coverage', '__pycache__', '.venv', 'venv', '.idea', '.gradle', 'Pods'};

class CodeScanResult {
  final List<Finding> findings = [];
  int files = 0;
  int bytes = 0;
  int packages = 0;
  final Set<String> manifests = {};
}

/// One file of a project picked on the phone (from a .zip or picked files).
class CodeFile {
  const CodeFile(this.path, this.bytes);

  /// Path inside the project, with "/" separators (e.g. "src/db.php").
  final String path;
  final List<int> bytes;
}

class CodeScanner {
  /// Max files read from one project (phones: keeps memory and time bounded).
  static const int maxFiles = 20000;

  /// Scans a folder (desktop, or a folder in the app's own storage).
  static Future<CodeScanResult> scan(String folder, {void Function(String)? onLog}) async {
    final s = _CodeScan(onLog);
    final root = Directory(folder);

    Future<void> walk(Directory d, int depth) async {
      if (depth > 12 || s.res.files >= maxFiles) return;
      List<FileSystemEntity> items;
      try {
        items = await d.list(followLinks: false).toList();
      } catch (_) {
        return;
      }
      for (final e in items) {
        final name = e.uri.pathSegments.where((x) => x.isNotEmpty).last;
        if (e is Directory) {
          if (!_skipDirs.contains(name)) await walk(e, depth + 1);
          continue;
        }
        if (e is! File) continue;
        if (!_CodeScan.wanted(name)) continue;
        int len;
        try {
          len = await e.length();
        } catch (_) {
          continue;
        }
        if (len > 1024 * 1024) continue;
        String text;
        try {
          text = await e.readAsString();
        } catch (_) {
          continue;
        }
        s.add(e.path.substring(folder.length).replaceAll('\\', '/'), name, text, len);
      }
    }

    onLog?.call('Reading $folder…');
    await walk(root, 0);
    return s.finish();
  }

  /// Scans files already in memory (Android: a picked .zip or picked files).
  /// Folders in [_skipDirs] (node_modules, vendor, .git…) are skipped.
  static Future<CodeScanResult> scanFiles(List<CodeFile> files, {String label = 'project', void Function(String)? onLog}) async {
    final s = _CodeScan(onLog);
    onLog?.call('Reading $label…');
    for (final f in files) {
      if (s.res.files >= maxFiles) break;
      final parts = f.path.replaceAll('\\', '/').split('/').where((x) => x.isNotEmpty).toList();
      if (parts.isEmpty) continue;
      if (parts.length > 13) continue;
      if (parts.take(parts.length - 1).any(_skipDirs.contains)) continue;
      final name = parts.last;
      if (!_CodeScan.wanted(name)) continue;
      if (f.bytes.length > 1024 * 1024) continue;
      String text;
      try {
        text = utf8.decode(f.bytes, allowMalformed: true);
      } catch (_) {
        continue;
      }
      if (text.contains('\u0000')) continue; // binary
      s.add('/${parts.join('/')}', name, text, f.bytes.length);
      if (s.res.files % 50 == 0) await Future<void>.delayed(Duration.zero); // keep the UI responsive
    }
    return s.finish();
  }

  static void _manifest(String name, String text, List<OsvPackage> out, CodeScanResult res, String rel) {
    try {
      if (name == 'package-lock.json') {
        final j = jsonDecode(text);
        final packages = j['packages'];
        if (packages is Map) {
          packages.forEach((k, v) {
            final n = '$k'.split('node_modules/').last;
            if (n.isNotEmpty && v is Map && v['version'] != null) out.add(OsvPackage(n, 'npm', '${v['version']}'));
          });
        } else if (j['dependencies'] is Map) {
          (j['dependencies'] as Map).forEach((k, v) {
            if (v is Map && v['version'] != null) out.add(OsvPackage('$k', 'npm', '${v['version']}'));
          });
        }
        res.manifests.add(rel);
      } else if (name == 'composer.lock') {
        final j = jsonDecode(text);
        for (final p in [...(j['packages'] as List? ?? const []), ...(j['packages-dev'] as List? ?? const [])]) {
          out.add(OsvPackage('${p['name']}', 'Packagist', '${p['version']}'.replaceFirst(RegExp(r'^v'), '')));
        }
        res.manifests.add(rel);
      } else if (name == 'requirements.txt') {
        for (final m in RegExp(r'^\s*([A-Za-z0-9_.\-\[\]]+)\s*==\s*([\w.\-]+)', multiLine: true).allMatches(text)) {
          out.add(OsvPackage(m[1]!.replaceAll(RegExp(r'\[.*\]'), ''), 'PyPI', m[2]!));
        }
        res.manifests.add(rel);
      } else if (name == 'pubspec.lock') {
        for (final m in RegExp(r'^  ([a-z0-9_]+):\n(?:    .*\n)*?    version: "([^"]+)"', multiLine: true).allMatches(text)) {
          out.add(OsvPackage(m[1]!, 'Pub', m[2]!));
        }
        res.manifests.add(rel);
      } else if (name == 'yarn.lock') {
        for (final m in RegExp(r'^"?(@?[^@\s"]+)@[^\n]*:\n\s+version "([^"]+)"', multiLine: true).allMatches(text)) {
          out.add(OsvPackage(m[1]!, 'npm', m[2]!));
        }
        res.manifests.add(rel);
      }
    } catch (_) {}
  }
}

/// Shared state of one code scan (folder or in-memory files).
class _CodeScan {
  _CodeScan(this.onLog);
  final void Function(String)? onLog;
  final res = CodeScanResult();
  final grouped = <String, List<String>>{}; // rule id → hits
  final pkgs = <OsvPackage>[];

  static bool wanted(String name) {
    final lower = name.toLowerCase();
    final ext = lower.contains('.') ? lower.substring(lower.lastIndexOf('.') + 1) : '';
    final isEnv = lower == '.env' || lower.startsWith('.env.');
    if (!_textExts.contains(ext) && !isEnv) return false;
    if (lower.endsWith('.min.js') || lower.endsWith('.map')) return false;
    return true;
  }

  void add(String rel, String name, String text, int len) {
    final lower = name.toLowerCase();
    final ext = lower.contains('.') ? lower.substring(lower.lastIndexOf('.') + 1) : '';
    final isEnv = lower == '.env' || lower.startsWith('.env.');
    res.files++;
    res.bytes += len;
    final effExt = isEnv ? 'env' : ext;
    if (res.files % 200 == 0) onLog?.call('Read ${res.files} files…');
    CodeScanner._manifest(lower, text, pkgs, res, rel);
    final lines = const LineSplitter().convert(text);
    for (final rule in codeRules) {
      if (rule.exts.isNotEmpty && !rule.exts.contains(effExt)) continue;
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.length > 2000) continue;
        if (!rule.pattern.hasMatch(line)) continue;
        if (rule.id == 'code.secret.assign' && RegExp(r'(example|placeholder|changeme|your[_-]|xxx|\*\*\*|<.*>|process\.env|getenv|env\()', caseSensitive: false).hasMatch(line)) continue;
        final shown = redactSecrets(line.trim());
        final masked = shown.replaceAllMapped(RegExp(r'''(["'])([^"']{6})[^"']{4,}(["'])'''), (m) => '${m[1]}${m[2]}…${m[3]}');
        (grouped[rule.id] ??= []).add('$rel:${i + 1}  ${masked.length > 160 ? '${masked.substring(0, 160)}…' : masked}');
      }
    }
    if (isEnv && !lower.endsWith('.example') && !lower.endsWith('.sample')) {
      (grouped['code.envfile'] ??= []).add(rel);
    }
  }

  Future<CodeScanResult> finish() async {
    for (final rule in codeRules) {
      final hits = grouped[rule.id];
      if (hits == null) continue;
      res.findings.add(Finding(
        id: rule.id,
        title: '${rule.title} (${hits.length})',
        severity: rule.severity,
        area: CheckArea.code,
        evidence: hits.take(15).join('\n') + (hits.length > 15 ? '\n… and ${hits.length - 15} more' : ''),
        location: hits.first.split('  ').first,
        impact: rule.impact,
        fixSummary: rule.fix,
        refs: rule.refs,
        confidence: rule.id.startsWith('code.secret') ? 'firm' : 'tentative',
        level: ScanLevel.code,
      ));
    }
    if (grouped['code.envfile'] != null) {
      res.findings.add(Finding(
        id: 'code.envfile',
        title: '.env files in the project (${grouped['code.envfile']!.length})',
        severity: Severity.info,
        area: CheckArea.code,
        evidence: grouped['code.envfile']!.join('\n'),
        impact: 'Make sure these are in .gitignore and are never deployed inside the public web folder.',
        fixSummary: 'Add ".env*" (except .env.example) to .gitignore; keep the web root separate from config.',
        level: ScanLevel.code,
      ));
    }
    if (pkgs.isNotEmpty) {
      res.packages = pkgs.length;
      onLog?.call('Checking ${pkgs.length} dependencies against OSV.dev…');
      final unique = {for (final p in pkgs) '${p.ecosystem}:${p.name}@${p.version}': p}.values.toList();
      final vulns = await Osv.query(unique);
      for (final e in vulns.entries) {
        final p = unique.firstWhere((x) => x.name == e.key);
        res.findings.add(osvFinding('dep.code.${p.ecosystem}.${p.name}', '${p.name} ${p.version} (${p.ecosystem})', e.value, CheckArea.dependencies,
            res.manifests.join(', '), ScanLevel.code));
      }
    }
    onLog?.call('Done: ${res.files} files, ${res.packages} dependencies, ${res.findings.length} findings.');
    return res;
  }
}
