// test/cyber/cyber_audit_rules_test.dart (3.14.0)
//
// Audit trail (hash chain) and rule packs, ported from NOVA X for Windows.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nova_x/features/cyber/engine/cyber_audit.dart';
import 'package:nova_x/features/cyber/engine/cyber_models.dart';
import 'package:nova_x/features/cyber/engine/cyber_rulepacks.dart';

void main() {
  group('audit chain', () {
    late Directory dir;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('nova_audit');
      CyberAudit.overrideFile = File('${dir.path}/audit.log');
    });
    tearDown(() async {
      CyberAudit.overrideFile = null;
      await dir.delete(recursive: true);
    });

    test('entries link and verify', () async {
      await CyberAudit.log('scan.start', 'example.com', scope: 'verified owner');
      await CyberAudit.log('scan.done', 'example.com', detail: 'score=91');
      await CyberAudit.log('export', 'example.com', detail: 'sarif');
      final c = await CyberAudit.verify();
      expect(c.intact, isTrue);
      expect(c.entries, 3);
      final recent = await CyberAudit.recent();
      expect(recent.first.action, 'export');
      expect(recent.first.prev, recent[1].hash);
    });

    test('an edited line breaks the chain', () async {
      await CyberAudit.log('scan.start', 'a.com');
      await CyberAudit.log('scan.done', 'a.com');
      final lines = await CyberAudit.file.readAsLines();
      final j = jsonDecode(lines[0]) as Map<String, dynamic>..['target'] = 'b.com';
      lines[0] = jsonEncode(j);
      final c = CyberAudit.verifyLines(lines);
      expect(c.intact, isFalse);
      expect(c.brokenAt, 1);
    });

    test('a removed line is detected', () async {
      await CyberAudit.log('a', 'x');
      await CyberAudit.log('b', 'x');
      await CyberAudit.log('c', 'x');
      final lines = await CyberAudit.file.readAsLines();
      expect(CyberAudit.verifyLines([lines[0], lines[2]]).intact, isFalse);
    });
  });

  group('rule packs', () {
    test('valid pack parses with namespaced ids', () {
      final p = RulePacks.parse(jsonEncode({
        'name': 'team',
        'version': '1.2.0',
        'rules': [
          {'id': 'no-md5', 'title': 'MD5', 'severity': 'high', 'extensions': ['php'], 'pattern': r'md5\(', 'refs': ['CWE-328']},
        ],
      }));
      expect(p.rules.single.id, 'pack.team.no-md5');
      expect(p.rules.single.severity, Severity.high);
      expect(p.rules.single.pattern.hasMatch(r'$h = md5($x);'), isTrue);
      expect(p.errors, isEmpty);
    });

    test('broken rules are reported, not fatal', () {
      final p = RulePacks.parse(jsonEncode({
        'name': 'team',
        'rules': [
          {'id': 'Bad Id!', 'pattern': 'x'},
          {'id': 'ok', 'pattern': '('},
          {'id': 'sev', 'pattern': 'x', 'severity': 'urgent'},
          {'id': 'good', 'pattern': 'x'},
        ],
      }));
      expect(p.rules.length, 1);
      expect(p.errors.length, 3);
    });

    test('invalid pack name is rejected', () {
      expect(() => RulePacks.parse(jsonEncode({'name': 'Bad Name', 'rules': []})), throwsFormatException);
      expect(() => RulePacks.parse('[]'), throwsFormatException);
    });
  });
}
