// test/xcoder/xcoder_logic_test.dart
//
// Pure logic of X Coder (3.11.0): safe project paths, file names, shell
// argument splitting, line diff, fuzzy file search, ZIP export, the NOVA
// /code request and answer parsing, and file-type detection.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nova_x/features/nova/services/nova_api.dart';
import 'package:nova_x/features/xcoder/ai/xcoder_ai.dart';
import 'package:nova_x/features/xcoder/editor/ace_editor.dart';
import 'package:nova_x/features/xcoder/terminal/xcoder_terminal.dart';
import 'package:nova_x/features/xcoder/widgets/xcoder_palette.dart';
import 'package:nova_x/features/xcoder/widgets/xcoder_ui.dart';
import 'package:nova_x/features/xcoder/workspace/xcoder_workspace.dart';

void main() {
  group('project paths never leave the project', () {
    test('normalize', () {
      expect(XWorkspace.normalize('src/app.js'), 'src/app.js');
      expect(XWorkspace.normalize('./src//app.js'), 'src/app.js');
      expect(XWorkspace.normalize(r'src\app.js'), 'src/app.js');
      expect(XWorkspace.normalize(''), '');
      expect(XWorkspace.normalize('../etc/passwd'), isNull);
      expect(XWorkspace.normalize('a/../../b'), isNull);
      expect(XWorkspace.normalize('/abs/path'), isNull);
      expect(XWorkspace.normalize('bad\u0000name'), isNull);
    });

    test('file names', () {
      expect(XWorkspace.validName('index.html'), isNull);
      expect(XWorkspace.validName(''), isNotNull);
      expect(XWorkspace.validName('a/b'), isNotNull);
      expect(XWorkspace.validName('..'), isNotNull);
      expect(XWorkspace.validName('what?.js'), isNotNull);
      expect(XWorkspace.validName('x' * 121), isNotNull);
    });
  });

  group('terminal', () {
    test('splits arguments like a shell', () {
      expect(XTerminal.splitArgs('ls -la src'), ['ls', '-la', 'src']);
      expect(XTerminal.splitArgs('node -e "console.log(1 + 1)"'), ['node', '-e', 'console.log(1 + 1)']);
      expect(XTerminal.splitArgs("echo 'a b'  c"), ['echo', 'a b', 'c']);
      expect(XTerminal.splitArgs(r'open my\ file.js'), ['open', 'my file.js']);
      expect(XTerminal.splitArgs('echo ""'), ['echo', '']);
      expect(XTerminal.splitArgs('   '), isEmpty);
    });
  });

  group('line diff', () {
    String side(List<DiffLine> d, bool newSide) =>
        d.where((l) => newSide ? l.op != DiffOp.remove : l.op != DiffOp.add).map((l) => l.text).join('\n');

    test('rebuilds both sides and numbers lines', () {
      const a = 'one\ntwo\nthree\nfour';
      const b = 'one\n2\nthree\nfour\nfive';
      final d = lineDiff(a, b);
      expect(side(d, false), a);
      expect(side(d, true), b);
      expect(diffStats(d), (2, 1));
      final adds = d.where((l) => l.op == DiffOp.add).map((l) => l.newNo).toList();
      expect(adds, [2, 5]);
    });

    test('identical and empty inputs', () {
      expect(diffStats(lineDiff('x\ny', 'x\ny')), (0, 0));
      expect(side(lineDiff('', 'new'), true), 'new');
    });

    test('very large inputs fall back to a block replace', () {
      final a = List.generate(3000, (i) => 'a$i').join('\n');
      final b = List.generate(3000, (i) => 'b$i').join('\n');
      final d = lineDiff(a, b, maxCells: 1000);
      expect(diffStats(d), (3000, 3000));
    });
  });

  group('command palette', () {
    test('fuzzy file search ranks direct matches first', () {
      final files = ['src/components/Button.tsx', 'README.md', 'src/index.html', 'styles/button.css'];
      final ranked = [...files]..sort((a, b) => fuzzyScore(b, 'butt').compareTo(fuzzyScore(a, 'butt')));
      expect(ranked.take(2).toSet(), {'src/components/Button.tsx', 'styles/button.css'});
      expect(fuzzyScore('src/index.html', 'sih'), greaterThan(0));
      expect(fuzzyScore('README.md', 'xyz'), 0);
    });
  });

  group('zip export', () {
    test('crc32 of a known string', () {
      expect(ZipWriter.crc32(utf8.encode('The quick brown fox jumps over the lazy dog')), 0x414FA339);
    });

    test('archive structure', () {
      final w = ZipWriter()..add('p/a.txt', utf8.encode('hi'), DateTime(2026, 10, 30, 12));
      final z = w.finish();
      expect(z.sublist(0, 4), [0x50, 0x4B, 0x03, 0x04]); // local header
      final eocd = z.length - 22;
      expect(z.sublist(eocd, eocd + 4), [0x50, 0x4B, 0x05, 0x06]); // end of central directory
      expect(z[eocd + 10], 1); // one entry
    });
  });

  group('NOVA in X Coder', () {
    test('request carries the editor state within limits', () {
      final r = XAiRequest(
        task: XAiTask.fix,
        fileName: 'app.js',
        language: 'JavaScript',
        code: 'x' * 30000,
        selection: 'let a = ;',
        diagnostics: const [AceAnnotation(row: 0, column: 8, type: 'error', text: 'Unexpected ;')],
      ).toJson();
      expect(r['task'], 'fix');
      expect((r['code'] as String).length, XAiRequest.maxCode);
      expect(r['selection'], 'let a = ;');
      expect((r['diagnostics'] as List).single, {'row': 0, 'type': 'error', 'text': 'Unexpected ;'});
      expect(r.containsKey('instruction'), isFalse);
    });

    test('only code-editing tasks offer Apply', () {
      expect(XAiTask.fix.editsCode, isTrue);
      expect(XAiTask.refactor.editsCode, isTrue);
      expect(XAiTask.explain.editsCode, isFalse);
      expect(XAiTask.review.editsCode, isFalse);
    });

    test('first code block of an answer', () {
      expect(NovaCodeResult.firstBlock('Here:\n```js\nconst a = 1;\n```\nDone'), ('js', 'const a = 1;'));
      expect(NovaCodeResult.firstBlock('```\nplain\n```'), ('', 'plain'));
      expect(NovaCodeResult.firstBlock('no code'), ('', ''));
    });
  });

  group('file types', () {
    test('editor language per file', () {
      expect(aceModeFor('index.html'), 'html');
      expect(aceModeFor('App.TSX'), 'tsx');
      expect(aceModeFor('main.py'), 'python');
      expect(aceModeFor('Dockerfile'), 'dockerfile');
      expect(aceModeFor('notes'), 'text');
    });

    test('templates', () {
      expect(XTemplate.web.files.keys, containsAll(['index.html', 'style.css', 'script.js']));
      expect(XTemplate.web.open, ['index.html', 'style.css', 'script.js']);
      expect(XTemplate.empty.files, isEmpty);
      expect(XTemplate.javascript.files['main.js'], contains(r'${name}'));
    });
  });
}
