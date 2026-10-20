// test/nova/nova_markdown_test.dart
//
// NOVA AI answer formatting: Markdown reading and code highlighting.

import 'package:flutter_test/flutter_test.dart';
import 'package:nova_x/features/ai/services/nova_code_highlighter.dart';
import 'package:nova_x/features/ai/services/nova_markdown_parser.dart';

List<String> fmt(List<MdSpan> spans) => spans.map((s) => s.toString()).toList();

void main() {
  group('NovaMarkdown blocks', () {
    test('the answer from the tester screenshot shows no raw * symbols', () {
      const answer = 'The image shows a handwritten assignment. Here are the answers:\n\n'
          '**1. What is oral tradition?**\n'
          'Oral tradition is the way stories are passed down.\n\n'
          '**2. Write three (3) advantages of oral tradition:**\n'
          "*   **It is easy to share:** You don't need paper.\n"
          '*   **It is interactive and engaging:** The storyteller can use voice.\n'
          '*   **It preserves culture:** It helps keep history alive.';
      final b = NovaMarkdown.parse(answer);
      expect(b.map((x) => x.runtimeType).toList(),
          [MdParagraph, MdParagraph, MdParagraph, MdListItem, MdListItem, MdListItem]);
      expect(fmt(NovaMarkdown.inline((b[1] as MdParagraph).text)),
          ['B:1. What is oral tradition?', ':\nOral tradition is the way stories are passed down.']);
      final item = b[3] as MdListItem;
      expect(item.marker, '•');
      expect(fmt(NovaMarkdown.inline(item.text)), ['B:It is easy to share:', ": You don't need paper."]);
      expect(NovaMarkdown.plain(answer).contains('*'), isFalse);
    });

    test('fenced code keeps the language and the code exactly', () {
      final b = NovaMarkdown.parse('Here:\n\n```html\n<!DOCTYPE html>\n<p>Hi</p>\n```\nAfter');
      expect(b.length, 3);
      final code = b[1] as MdCode;
      expect(code.language, 'html');
      expect(code.code, '<!DOCTYPE html>\n<p>Hi</p>');
      // An unclosed fence runs to the end; Markdown inside code is untouched.
      expect((NovaMarkdown.parse('```js\nconst a = 1;\n\nconsole.log(a)').single as MdCode).code,
          'const a = 1;\n\nconsole.log(a)');
      expect((NovaMarkdown.parse('```\n**not bold**\n```').single as MdCode).code, '**not bold**');
      expect((NovaMarkdown.parse('```md\nUse ```js to start\n```').single as MdCode).code, 'Use ```js to start');
    });

    test('headings, rules, quotes, lists and tables', () {
      final b = NovaMarkdown.parse('## Setup\n### Step one ###\n---\n> Note: **careful**\n> second');
      expect((b[0] as MdHeading).level, 2);
      expect((b[1] as MdHeading).text, 'Step one');
      expect(b[2], isA<MdRule>());
      expect((b[3] as MdQuote).text, 'Note: **careful**\nsecond');
      expect(NovaMarkdown.parse('#hashtag').single, isA<MdParagraph>());

      final l = NovaMarkdown.parse('1. First\n2) Second\n   - nested\n     more text\n- [ ] todo\n- [x] done')
          .cast<MdListItem>();
      expect(l.map((x) => '${x.marker}${x.level}').toList(), ['1.0', '2.0', '•1', '☐0', '☑0']);
      expect(l.elementAt(2).text, 'nested\nmore text');
      expect(NovaMarkdown.parse('3.5 is a number').single, isA<MdParagraph>());

      final t = NovaMarkdown.parse('| Name | Price |\n|---|:---:|\n| A | \$1 |\n| B |\n\nafter');
      final table = t.first as MdTable;
      expect(table.header, ['Name', 'Price']);
      expect(table.rows, [
        ['A', '\$1'],
        ['B', ''],
      ]);
      expect(t.last, isA<MdParagraph>());
    });

    test('odd input never throws', () {
      for (final s in ['', '*', '**', '***', '`', '```', '|', '| |\n|-|', '- ', '> ', '~~', '[', '[a](', '_ _', '****']) {
        NovaMarkdown.parse(s);
        NovaMarkdown.inline(s);
        NovaMarkdown.plain(s);
      }
      expect(NovaMarkdown.parse(''), isEmpty);
    });
  });

  group('NovaMarkdown inline', () {
    test('bold, italic, strike and code', () {
      expect(fmt(NovaMarkdown.inline('a **b** *c* ***d*** ~~e~~ `f`')),
          [':a ', 'B:b', ': ', 'I:c', ': ', 'BI:d', ': ', 'S:e', ': ', 'C:f']);
      expect(fmt(NovaMarkdown.inline('__bold__ and _it_')), ['B:bold', ': and ', 'I:it']);
      expect(fmt(NovaMarkdown.inline('snake_case_name and 5 * 4 * 3')), [':snake_case_name and 5 * 4 * 3']);
      expect(fmt(NovaMarkdown.inline('**unclosed bold')), [':**unclosed bold']);
      expect(fmt(NovaMarkdown.inline(r'\*literal\*')), [':*literal*']);
      expect(fmt(NovaMarkdown.inline('**Note:** `npm i` is **very *fast***')),
          ['B:Note:', ': ', 'C:npm i', ': is ', 'B:very ', 'BI:fast']);
    });

    test('links are only http(s) or mailto', () {
      final s = NovaMarkdown.inline('See [the docs](https://dart.dev/guides) or https://flutter.dev/docs. Ok');
      expect(fmt(s), [':See ', 'L:the docs', ': or ', 'L:https://flutter.dev/docs', ':. Ok']);
      expect(s[1].link, 'https://dart.dev/guides');
      expect(fmt(NovaMarkdown.inline('[x](javascript:alert(1))')), [':[x](javascript:alert(1))']);
    });

    test('plain text for copying', () {
      expect(NovaMarkdown.plain('## Title\n\n- **a**\n- b\n\n```js\nx()\n```'), 'Title\n• a\n• b\nx()');
    });
  });

  group('NovaCodeHighlighter', () {
    const html = '<!DOCTYPE html>\n<html lang="en">\n<head>\n  <style>\n'
        '    body { font-family: Arial; background: #f0f2f5; margin: 1.5rem; }\n  </style>\n</head>\n'
        '<body>\n  <!-- form -->\n  <script>function check() { return 42; }</script>\n  &copy; 2026\n</body>\n</html>';

    String? kindOf(List<CodeToken> tokens, String text) {
      for (final t in tokens) {
        if (t.text == text) return t.kind.name;
      }
      return null;
    }

    test('tokens always join back to the exact code', () {
      final samples = {
        'html': html,
        'css': 'a:hover{color:red}\n/* c */\n.x > .y { padding: 0 -2px; content: "a{b}"; }',
        'js': "const a = `t \${x}`; // note\nlet b = 'it\\'s';",
        'python': 'def add(a, b):\n    """Doc"""\n    return a + b  # sum',
        'php': '<?php\n\$name = "Kobby"; # c\necho strlen(\$name);',
        'sql': 'SELECT id FROM users -- one',
        'bash': 'echo "\$HOME" # x',
        'json': '{ "name": "nova", "ok": true }',
        'text': '**raw**',
        '': 'x := 1',
      };
      samples.forEach((lang, code) {
        expect(NovaCodeHighlighter.highlight(code, lang).map((t) => t.text).join(), code, reason: lang);
      });
      for (final c in ['', '<', '<a', '"', '/*', r'$', '@', '#', '&', '{', '<style>', '<script>x', 'a:', '-5']) {
        for (final l in ['html', 'css', 'js', 'python', 'php', 'sql', 'bash', 'json', '']) {
          expect(NovaCodeHighlighter.highlight(c, l).map((t) => t.text).join(), c);
        }
      }
    });

    test('colours the right parts', () {
      final h = NovaCodeHighlighter.highlight(html, 'html');
      expect(kindOf(h, '<!DOCTYPE'), 'tag');
      expect(kindOf(h, 'lang'), 'attr');
      expect(kindOf(h, '"en"'), 'string');
      expect(kindOf(h, 'font-family'), 'attr');
      expect(kindOf(h, '#f0f2f5'), 'number');
      expect(kindOf(h, '<!-- form -->'), 'comment');
      expect(kindOf(h, 'function'), 'keyword');
      final py = NovaCodeHighlighter.highlight('def f():\n    return 1  # one', 'py');
      expect(kindOf(py, 'def'), 'keyword');
      expect(kindOf(py, '# one'), 'comment');
      final json = NovaCodeHighlighter.highlight('{ "name": "nova" }', 'json');
      expect(kindOf(json, '"name"'), 'attr');
      expect(kindOf(json, '"nova"'), 'string');
      expect(NovaCodeHighlighter.label('JS'), 'javascript');
      expect(NovaCodeHighlighter.label(''), 'code');
    });
  });
}
