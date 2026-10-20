// lib/features/ai/services/nova_markdown_parser.dart
//
// A small, safe Markdown reader for NOVA AI answers (pure Dart, unit-tested).
// It understands what the NOVA AI service writes: paragraphs, headings,
// bullet and numbered lists, quotes, tables, fenced code blocks, **bold**,
// *italic*, ~~strike~~, `inline code` and links. Anything it does not
// understand is shown as plain text — never as raw "**" or "```" symbols.
// No HTML is interpreted, and nothing in a reply is ever executed.

/// One block of an answer.
sealed class MdBlock {
  const MdBlock();
}

class MdParagraph extends MdBlock {
  const MdParagraph(this.text);
  final String text;
}

class MdHeading extends MdBlock {
  const MdHeading(this.level, this.text);
  final int level; // 1–6
  final String text;
}

class MdListItem extends MdBlock {
  const MdListItem({required this.ordered, required this.marker, required this.level, required this.text});
  final bool ordered;

  /// "1." for numbered items, "•" for bullets.
  final String marker;

  /// Nesting depth, 0–3.
  final int level;
  final String text;
}

class MdQuote extends MdBlock {
  const MdQuote(this.text);
  final String text;
}

class MdCode extends MdBlock {
  const MdCode(this.language, this.code);

  /// Lower-case language name from the fence ("" when not given).
  final String language;
  final String code;
}

class MdTable extends MdBlock {
  const MdTable(this.header, this.rows);
  final List<String> header;
  final List<List<String>> rows;
}

class MdRule extends MdBlock {
  const MdRule();
}

/// A run of inline text with its style.
class MdSpan {
  const MdSpan(this.text, {this.bold = false, this.italic = false, this.code = false, this.strike = false, this.link});
  final String text;
  final bool bold;
  final bool italic;
  final bool code;
  final bool strike;

  /// http(s) or mailto link target, when this span is a link.
  final String? link;

  @override
  String toString() =>
      '${bold ? 'B' : ''}${italic ? 'I' : ''}${code ? 'C' : ''}${strike ? 'S' : ''}${link != null ? 'L' : ''}:$text';
}

class NovaMarkdown {
  NovaMarkdown._();

  static final RegExp _fence = RegExp(r'^\s{0,3}(`{3,}|~{3,})\s*([A-Za-z0-9_+#.\-]*)[^`]*$');
  static final RegExp _heading = RegExp(r'^\s{0,3}(#{1,6})\s+(.*?)\s*#*\s*$');
  static final RegExp _rule = RegExp(r'^\s{0,3}([-*_])(?:\s*\1){2,}\s*$');
  static final RegExp _bullet = RegExp(r'^(\s*)([-*+•])\s+(.*)$');
  static final RegExp _ordered = RegExp(r'^(\s*)(\d{1,3})[.)]\s+(.*)$');
  static final RegExp _quote = RegExp(r'^\s{0,3}>\s?(.*)$');
  static final RegExp _tableSep = RegExp(r'^\s*\|?\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)*\|?\s*$');
  static final RegExp _task = RegExp(r'^\[([ xX])\]\s+');

  // ── Blocks ─────────────────────────────────────────────────────────────────

  static List<MdBlock> parse(String input) {
    final lines = input.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
    final blocks = <MdBlock>[];
    final para = <String>[];

    void flushPara() {
      if (para.isEmpty) return;
      final text = para.join('\n').trim();
      if (text.isNotEmpty) blocks.add(MdParagraph(text));
      para.clear();
    }

    var i = 0;
    while (i < lines.length) {
      final line = lines[i];

      // Fenced code block (an unclosed fence runs to the end).
      final fence = _fence.firstMatch(line);
      if (fence != null) {
        flushPara();
        final marker = fence.group(1)!;
        final lang = fence.group(2)!.toLowerCase();
        final code = <String>[];
        i++;
        while (i < lines.length) {
          final l = lines[i];
          final t = l.trimLeft();
          if (t.startsWith(marker[0] * 3) && t.replaceAll(marker[0], '').trim().isEmpty &&
              t.length >= marker.length) {
            i++;
            break;
          }
          code.add(l);
          i++;
        }
        blocks.add(MdCode(lang, _trimCode(code)));
        continue;
      }

      if (line.trim().isEmpty) {
        flushPara();
        i++;
        continue;
      }

      final heading = _heading.firstMatch(line);
      if (heading != null) {
        flushPara();
        blocks.add(MdHeading(heading.group(1)!.length, heading.group(2)!.trim()));
        i++;
        continue;
      }

      if (_rule.hasMatch(line)) {
        flushPara();
        blocks.add(const MdRule());
        i++;
        continue;
      }

      // Table: a row with "|" followed by a |---|---| separator.
      if (line.contains('|') && i + 1 < lines.length && _tableSep.hasMatch(lines[i + 1]) &&
          lines[i + 1].contains('-')) {
        final header = _cells(line);
        if (header.length >= 2 || line.trim().startsWith('|')) {
          flushPara();
          final rows = <List<String>>[];
          i += 2;
          while (i < lines.length && lines[i].contains('|') && lines[i].trim().isNotEmpty) {
            final cells = _cells(lines[i]);
            // Same number of columns as the header.
            rows.add(List<String>.generate(header.length, (c) => c < cells.length ? cells[c] : ''));
            i++;
          }
          blocks.add(MdTable(header, rows));
          continue;
        }
      }

      final quote = _quote.firstMatch(line);
      if (quote != null) {
        flushPara();
        final q = <String>[quote.group(1)!];
        i++;
        while (i < lines.length) {
          final m = _quote.firstMatch(lines[i]);
          if (m == null) break;
          q.add(m.group(1)!);
          i++;
        }
        final text = q.join('\n').trim();
        if (text.isNotEmpty) blocks.add(MdQuote(text));
        continue;
      }

      final bullet = _bullet.firstMatch(line);
      final ordered = bullet == null ? _ordered.firstMatch(line) : null;
      if (bullet != null || ordered != null) {
        flushPara();
        final m = (bullet ?? ordered)!;
        final indent = m.group(1)!.replaceAll('\t', '    ').length;
        var text = m.group(3)!;
        final task = _task.firstMatch(text);
        var marker = ordered != null ? '${m.group(2)}.' : '•';
        if (task != null) {
          marker = task.group(1) == ' ' ? '☐' : '☑';
          text = text.substring(task.end);
        }
        i++;
        // Lazy continuation lines belong to the item.
        while (i < lines.length) {
          final next = lines[i];
          if (next.trim().isEmpty || _startsBlock(next, i + 1 < lines.length ? lines[i + 1] : null)) break;
          text = '$text\n${next.trim()}';
          i++;
        }
        blocks.add(MdListItem(
          ordered: ordered != null,
          marker: marker,
          level: (indent ~/ 2).clamp(0, 3),
          text: text.trim(),
        ));
        continue;
      }

      para.add(line);
      i++;
    }
    flushPara();
    return blocks;
  }

  static bool _startsBlock(String line, String? next) =>
      _fence.hasMatch(line) ||
      _heading.hasMatch(line) ||
      _rule.hasMatch(line) ||
      _quote.hasMatch(line) ||
      _bullet.hasMatch(line) ||
      _ordered.hasMatch(line) ||
      (line.contains('|') && next != null && _tableSep.hasMatch(next) && next.contains('-'));

  static String _trimCode(List<String> lines) {
    var start = 0;
    var end = lines.length;
    while (start < end && lines[start].trim().isEmpty) {
      start++;
    }
    while (end > start && lines[end - 1].trim().isEmpty) {
      end--;
    }
    return lines.sublist(start, end).join('\n');
  }

  static List<String> _cells(String row) {
    var r = row.trim();
    if (r.startsWith('|')) r = r.substring(1);
    if (r.endsWith('|') && !r.endsWith(r'\|')) r = r.substring(0, r.length - 1);
    final cells = <String>[];
    final buf = StringBuffer();
    for (var k = 0; k < r.length; k++) {
      final ch = r[k];
      if (ch == r'\' && k + 1 < r.length && r[k + 1] == '|') {
        buf.write('|');
        k++;
      } else if (ch == '|') {
        cells.add(buf.toString().trim());
        buf.clear();
      } else {
        buf.write(ch);
      }
    }
    cells.add(buf.toString().trim());
    return cells;
  }

  // ── Inline ─────────────────────────────────────────────────────────────────

  static final RegExp _url = RegExp(r'''https?://[^\s<>()\[\]"'`]+[^\s<>()\[\]"'`.,;:!?*_~]''');

  /// Inline spans of [text] (bold, italic, code, strike, links).
  static List<MdSpan> inline(String text) {
    final out = <MdSpan>[];
    _inline(text, out, false, false, false);
    return _merge(out);
  }

  static void _inline(String s, List<MdSpan> out, bool bold, bool italic, bool strike) {
    final buf = StringBuffer();

    void flush() {
      if (buf.isEmpty) return;
      out.add(MdSpan(buf.toString(), bold: bold, italic: italic, strike: strike));
      buf.clear();
    }

    var i = 0;
    while (i < s.length) {
      final ch = s[i];

      // Escaped punctuation: \* \_ \` \~ \[ \] \\ \#
      if (ch == r'\' && i + 1 < s.length && r'\`*_~[]()#|>-+.!'.contains(s[i + 1])) {
        buf.write(s[i + 1]);
        i += 2;
        continue;
      }

      // `code` (also ``code with ` inside``)
      if (ch == '`') {
        var n = 1;
        while (i + n < s.length && s[i + n] == '`') {
          n++;
        }
        final ticks = '`' * n;
        final close = s.indexOf(ticks, i + n);
        if (close > i + n) {
          flush();
          var code = s.substring(i + n, close);
          if (code.length > 2 && code.startsWith(' ') && code.endsWith(' ')) {
            code = code.substring(1, code.length - 1);
          }
          out.add(MdSpan(code, code: true, bold: bold, italic: italic));
          i = close + n;
          continue;
        }
        buf.write(ticks);
        i += n;
        continue;
      }

      // [text](https://link)
      if (ch == '[') {
        final m = RegExp(r'^\[([^\[\]\n]{1,300})\]\(\s*(<?)((?:https?://|mailto:)[^\s)>]+)>?(?:\s+"[^"]*")?\s*\)')
            .firstMatch(s.substring(i));
        if (m != null) {
          flush();
          final label = <MdSpan>[];
          _inline(m.group(1)!, label, bold, italic, strike);
          for (final l in label) {
            out.add(MdSpan(l.text, bold: l.bold, italic: l.italic, code: l.code, strike: l.strike, link: m.group(3)));
          }
          i += m.end;
          continue;
        }
      }

      // Bare web address
      if ((ch == 'h' || ch == 'H') && (i == 0 || !_isWord(s[i - 1]))) {
        final m = _url.matchAsPrefix(s, i);
        if (m != null) {
          flush();
          out.add(MdSpan(m.group(0)!, bold: bold, italic: italic, strike: strike, link: m.group(0)));
          i = m.end;
          continue;
        }
      }

      // ~~strike~~
      if (ch == '~' && s.startsWith('~~', i)) {
        final close = _closing(s, '~~', i + 2);
        if (close > 0) {
          flush();
          _inline(s.substring(i + 2, close), out, bold, italic, true);
          i = close + 2;
          continue;
        }
      }

      // ***bold italic***, **bold**, __bold__, *italic*, _italic_
      if (ch == '*' || ch == '_') {
        var n = 1;
        while (i + n < s.length && s[i + n] == ch) {
          n++;
        }
        final opensWord = i + n < s.length && s[i + n] != ' ' && s[i + n] != '\n';
        // "_" inside a word (snake_case) is just text.
        final intraword = ch == '_' && i > 0 && _isWord(s[i - 1]);
        if (n <= 3 && opensWord && !intraword) {
          final delim = ch * n;
          final close = _closing(s, delim, i + n);
          if (close > 0) {
            flush();
            final inner = s.substring(i + n, close);
            _inline(inner, out, bold || n >= 2, italic || n == 1 || n == 3, strike);
            i = close + n;
            continue;
          }
        }
        buf.write(ch * n);
        i += n;
        continue;
      }

      buf.write(ch);
      i++;
    }
    flush();
  }

  /// Index of a closing [delim] after [from]: the end of a run of delimiter
  /// characters that follows a non-space character ("**bold**", and the
  /// "***" in "**very *fast***"); -1 if none.
  static int _closing(String s, String delim, int from) {
    final ch = delim[0];
    var k = from;
    while (true) {
      final idx = s.indexOf(delim, k);
      if (idx < 0) return -1;
      var j = idx;
      while (j < s.length && s[j] == ch) {
        j++;
      }
      final candidate = j - delim.length; // the last characters of the run
      final before = idx > 0 ? s[idx - 1] : ' ';
      final after = j < s.length ? s[j] : '';
      final validEnd = before != ' ' && before != '\n' && candidate > from;
      final wordAfter = ch == '_' && after.isNotEmpty && _isWord(after);
      if (validEnd && !wordAfter) return candidate;
      k = j;
    }
  }

  static bool _isWord(String c) => RegExp(r'[A-Za-z0-9]').hasMatch(c);

  static List<MdSpan> _merge(List<MdSpan> spans) {
    final out = <MdSpan>[];
    for (final s in spans) {
      if (s.text.isEmpty) continue;
      if (out.isNotEmpty) {
        final p = out.last;
        if (p.bold == s.bold && p.italic == s.italic && p.code == s.code && p.strike == s.strike &&
            p.link == s.link) {
          out[out.length - 1] =
              MdSpan(p.text + s.text, bold: p.bold, italic: p.italic, code: p.code, strike: p.strike, link: p.link);
          continue;
        }
      }
      out.add(s);
    }
    return out;
  }

  // ── Plain text ─────────────────────────────────────────────────────────────

  /// The answer as plain text (no Markdown symbols): previews, copying.
  static String plain(String input) {
    final parts = <String>[];
    for (final b in parse(input)) {
      switch (b) {
        case MdParagraph(:final text):
          parts.add(_plainInline(text));
        case MdHeading(:final text):
          parts.add(_plainInline(text));
        case MdListItem(:final marker, :final level, :final text):
          parts.add('${'  ' * level}$marker ${_plainInline(text)}');
        case MdQuote(:final text):
          parts.add(_plainInline(text));
        case MdCode(:final code):
          parts.add(code);
        case MdTable(:final header, :final rows):
          parts.add([header, ...rows].map((r) => r.map(_plainInline).join(' | ')).join('\n'));
        case MdRule():
          break;
      }
    }
    return parts.join('\n').trim();
  }

  static String _plainInline(String text) => inline(text).map((s) => s.text).join();
}
