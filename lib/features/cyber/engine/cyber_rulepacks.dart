// lib/features/cyber/engine/cyber_rulepacks.dart
//
// NOVA Cyber — rules as data. Extra code-scan rules live in versioned JSON
// "rule packs" (cyber/rules/*.json in the app's private folder on Android —
// added with "Import rule pack"), so new checks can be added or shared across
// a team without updating NOVA X.
//
// Pack format:
// {
//   "name": "my-team-rules",
//   "version": "1.0.0",
//   "rules": [
//     {
//       "id": "no-md5-tokens",                 // becomes pack.<name>.<id>
//       "title": "MD5 used for tokens",
//       "severity": "high",                    // critical | high | medium | low | info
//       "extensions": ["php", "js"],           // empty or missing = all text files
//       "pattern": "md5\\(\\s*\\$token",       // regular expression, one line at a time
//       "caseInsensitive": true,
//       "impact": "Why it matters",
//       "fix": "How to fix it",
//       "refs": ["CWE-328"]
//     }
//   ]
// }

import 'dart:convert';
import 'dart:io';

import 'cyber_code_scan.dart' show CodeRule;
import 'cyber_models.dart';
import 'cyber_storage.dart';

class RulePack {
  RulePack(this.name, this.version, this.file, this.rules, this.errors);
  final String name;
  final String version;
  final String file;
  final List<CodeRule> rules;
  final List<String> errors;
}

class RulePacks {
  static Directory get dir {
    return Directory(CyberStorage.path(['rules']));
  }

  static List<RulePack> loaded = [];
  static List<CodeRule> get rules => [for (final p in loaded) ...p.rules];

  /// Reads every *.json pack in [dir]. Broken packs are reported, never fatal.
  static Future<List<RulePack>> reload() async {
    final out = <RulePack>[];
    try {
      if (await dir.exists()) {
        final files = await dir.list().where((e) => e is File && e.path.toLowerCase().endsWith('.json')).cast<File>().toList();
        files.sort((a, b) => a.path.compareTo(b.path));
        for (final f in files) {
          final name = f.uri.pathSegments.last;
          try {
            out.add(parse(await f.readAsString(), file: name));
          } catch (e) {
            out.add(RulePack(name, '?', name, const [], ['$e']));
          }
        }
      }
    } catch (_) {}
    return loaded = out;
  }

  static final _idRe = RegExp(r'^[a-z0-9][a-z0-9_.\-]{0,80}$');

  /// Parses and validates one pack. Pure (unit-tested).
  static RulePack parse(String json, {String file = 'pack.json'}) {
    final j = jsonDecode(json);
    if (j is! Map) throw const FormatException('A rule pack must be a JSON object.');
    final name = '${j['name'] ?? ''}'.trim().toLowerCase();
    if (!_idRe.hasMatch(name)) throw FormatException('"name" must be lowercase letters, digits, dots or dashes (got "$name").');
    final version = '${j['version'] ?? '0.0.0'}';
    final rules = <CodeRule>[];
    final errors = <String>[];
    final seen = <String>{};
    final list = j['rules'];
    if (list is! List) throw const FormatException('"rules" must be a list.');
    for (var i = 0; i < list.length; i++) {
      final r = list[i];
      if (r is! Map) {
        errors.add('Rule #${i + 1}: not an object');
        continue;
      }
      final rawId = '${r['id'] ?? ''}'.trim().toLowerCase();
      if (!_idRe.hasMatch(rawId)) {
        errors.add('Rule #${i + 1}: invalid id "$rawId"');
        continue;
      }
      final id = 'pack.$name.$rawId';
      if (!seen.add(id)) {
        errors.add('Rule "$rawId": duplicate id');
        continue;
      }
      final pattern = '${r['pattern'] ?? ''}';
      if (pattern.isEmpty || pattern.length > 2000) {
        errors.add('Rule "$rawId": pattern missing or too long');
        continue;
      }
      RegExp re;
      try {
        re = RegExp(pattern, caseSensitive: r['caseInsensitive'] != true);
      } catch (e) {
        errors.add('Rule "$rawId": invalid pattern ($e)');
        continue;
      }
      final sev = Severity.values.where((s) => s.name == '${r['severity'] ?? 'medium'}'.toLowerCase()).firstOrNull;
      if (sev == null) {
        errors.add('Rule "$rawId": severity must be critical, high, medium, low or info');
        continue;
      }
      final exts = {for (final e in (r['extensions'] as List? ?? const [])) '$e'.toLowerCase().replaceFirst('.', '')};
      rules.add(CodeRule(
        id,
        '${r['title'] ?? rawId}',
        sev,
        exts,
        re,
        '${r['impact'] ?? 'Custom rule from the $name rule pack.'}',
        '${r['fix'] ?? 'See your team\'s guidance for this rule.'}',
        [for (final x in (r['refs'] as List? ?? const [])) '$x', 'pack:$name@$version'],
      ));
    }
    return RulePack(name, version, file, rules, errors);
  }

  /// Android: validates [json] and saves it as a pack (replacing a pack with
  /// the same name). Returns the parsed pack; throws FormatException when the
  /// file isn't a valid pack.
  static Future<RulePack> import(String json) async {
    final pack = parse(json);
    if (pack.rules.isEmpty) {
      throw FormatException(pack.errors.isEmpty ? 'The pack has no rules.' : 'No usable rules: ${pack.errors.first}');
    }
    await dir.create(recursive: true);
    await File('${dir.path}${Platform.pathSeparator}${pack.name}.json').writeAsString(json);
    await reload();
    return pack;
  }

  /// Removes an imported pack.
  static Future<void> remove(RulePack pack) async {
    try {
      final f = File('${dir.path}${Platform.pathSeparator}${pack.file}');
      if (await f.exists()) await f.delete();
    } catch (_) {}
    await reload();
  }

  /// The example pack as text (Android: saved with the system file dialog).
  static Future<String> exampleJson() async => (await writeExample()).readAsString();

  /// Writes an example pack the user can copy and edit.
  static Future<File> writeExample() async {
    await dir.create(recursive: true);
    final f = File('${dir.path}${Platform.pathSeparator}example-team-rules.json.sample');
    await f.writeAsString(const JsonEncoder.withIndent('  ').convert({
      'name': 'example-team-rules',
      'version': '1.0.0',
      'rules': [
        {
          'id': 'no-console-secrets',
          'title': 'Secret logged to the console',
          'severity': 'medium',
          'extensions': ['js', 'ts'],
          'pattern': r'console\.log\([^)]*(token|secret|password)',
          'caseInsensitive': true,
          'impact': 'Secrets in logs end up in browser consoles, crash reports and log files.',
          'fix': 'Remove the log line or redact the value.',
          'refs': ['CWE-532'],
        },
        {
          'id': 'php-display-errors',
          'title': 'display_errors turned on',
          'severity': 'low',
          'extensions': ['php', 'ini'],
          'pattern': r'''display_errors\s*[=,]\s*['"]?(1|on|true)''',
          'caseInsensitive': true,
          'impact': 'Error messages reveal paths, queries and versions to visitors.',
          'fix': 'Set display_errors=Off in production and log errors instead.',
          'refs': ['CWE-209'],
        },
      ],
    }));
    return f;
  }
}
