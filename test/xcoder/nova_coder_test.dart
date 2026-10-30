// test/xcoder/nova_coder_test.dart
//
// NOVA Coder (3.11.1): streamed answers, agent plans, safe patching, and
// the Developer Guide content.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nova_x/features/devguide/guide_content.dart';
import 'package:nova_x/features/xcoder/ai/nova_coder_client.dart';

Stream<List<int>> _sse(List<String> events, {int split = 7}) async* {
  final all = utf8.encode(events.map((e) => 'data: $e\n\n').join());
  for (var i = 0; i < all.length; i += split) {
    yield all.sublist(i, i + split > all.length ? all.length : i + split);
  }
}

void main() {
  group('streamed answers', () {
    test('deltas arrive in order even when chunks split events', () async {
      final out = await parseCoderSse(_sse([
        jsonEncode({'t': 'delta', 'v': 'Hello'}),
        jsonEncode({'t': 'delta', 'v': ', wörld'}),
        jsonEncode({'t': 'done', 'model': 'openai/gpt-oss-120b', 'usage': {'completion': 4}}),
      ])).toList();
      expect(out.where((d) => !d.done).map((d) => d.text).join(), 'Hello, wörld');
      expect(out.last.done, isTrue);
      expect(out.last.model, 'openai/gpt-oss-120b');
      expect(out.last.completionTokens, 4);
    });

    test('an error event becomes a CoderException', () async {
      expect(parseCoderSse(_sse([jsonEncode({'t': 'error', 'error': 'interrupted'})])).toList(),
          throwsA(isA<CoderException>()));
    });

    test('junk lines are ignored', () async {
      final out = await parseCoderSse(_sse(['not json', jsonEncode({'t': 'delta', 'v': 'ok'}), jsonEncode({'t': 'done'})])).toList();
      expect(out.first.text, 'ok');
    });
  });

  group('agent plans', () {
    test('parse a plan with edits and commands', () {
      final r = AgentResult.parse({
        'type': 'plan',
        'summary': 'Add dark mode',
        'steps': ['a', 'b'],
        'edits': [
          {'path': 'style.css', 'action': 'patch', 'patches': [{'search': 'body{', 'replace': 'body.dark{'}]},
          {'path': 'theme.js', 'action': 'create', 'content': 'x'},
          {'path': 'x', 'action': 'explode'},
        ],
        'commands': [{'command': 'node theme.js', 'why': 'try it', 'phone': true}],
      });
      expect(r.type, 'plan');
      expect(r.edits.length, 2);
      expect(r.edits.first.patches.single.replace, 'body.dark{');
      expect(r.commands.single.phone, isTrue);
    });

    test('need_files and question', () {
      expect(AgentResult.parse({'type': 'need_files', 'files': ['a.js', 3]}).files, ['a.js']);
      expect(AgentResult.parse({'type': 'question', 'question': 'Which page?'}).question, 'Which page?');
    });
  });

  group('patches', () {
    test('each search must match exactly once', () {
      expect(applyPatches('a b c', [(search: 'b', replace: 'B')]), ('a B c', null));
      final (none, why) = applyPatches('a b c', [(search: 'x', replace: 'y')]);
      expect(none, isNull);
      expect(why, contains('not found'));
      final (twice, why2) = applyPatches('b b', [(search: 'b', replace: 'c')]);
      expect(twice, isNull);
      expect(why2, contains('more than once'));
    });

    test('patches apply in order and tolerate CRLF files', () {
      expect(applyPatches('one\r\ntwo\r\n', [(search: 'one\ntwo', replace: '1\n2')]).$1, '1\n2\r\n');
      expect(applyPatches('x', [(search: 'x', replace: 'xy'), (search: 'xy', replace: 'z')]).$1, 'z');
    });
  });

  group('Developer Guide', () {
    test('sections have unique ids and content', () {
      final ids = kGuideSections.map((s) => s.id).toList();
      expect(ids.toSet().length, ids.length);
      for (final s in kGuideSections) {
        expect(s.body.trim(), isNotEmpty, reason: s.id);
        expect(s.tab.length, lessThan(20), reason: s.id);
      }
      expect(ids, containsAll(['xcoder', 'novacoder', 'terminal', 'devtools', 'cyber', 'shield', 'network', 'capture']));
    });

    test('the terminal section documents every X Coder command', () {
      final t = kGuideSections.firstWhere((s) => s.id == 'terminal').body;
      for (final c in ['help', 'clear', 'pwd', 'cd', 'open', 'run', 'node', 'serve', 'search', 'tree', 'history', 'env', 'nova', 'agent', 'guide']) {
        expect(t, contains('`$c'), reason: c);
      }
    });
  });
}
