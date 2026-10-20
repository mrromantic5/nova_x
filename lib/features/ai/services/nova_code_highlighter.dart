// lib/features/ai/services/nova_code_highlighter.dart
//
// Lightweight syntax highlighting for code in NOVA AI answers (pure Dart,
// unit-tested). It splits code into coloured tokens for the code-editor style
// code blocks; it never changes the code itself (joining all token texts
// gives back exactly the original code).

enum CodeTok { plain, keyword, string, comment, number, tag, attr, func, type, punct }

class CodeToken {
  const CodeToken(this.text, this.kind);
  final String text;
  final CodeTok kind;

  @override
  String toString() => '${kind.name}:$text';
}

class NovaCodeHighlighter {
  NovaCodeHighlighter._();

  static final RegExp _cssSelectorStart = RegExp(r'[.#:A-Za-z\-_\[\]*>+~=]');
  static final RegExp _tagPunct = RegExp(r'[<>/!?]');
  static final RegExp _tagStart = RegExp(r'[A-Za-z/!?]');
  static final RegExp _cssNumberChar = RegExp(r'[A-Za-z0-9.%]');
  static final RegExp _tagNameChar = RegExp(r'[A-Za-z0-9\-:_]');
  static final RegExp _cssWordChar = RegExp(r'[A-Za-z0-9\-_]');
  static final RegExp _attrChar = RegExp(r'[A-Za-z0-9_:@.\-]');
  static final RegExp _cssWordStart = RegExp(r'[A-Za-z\-]');
  static final RegExp _attrStart = RegExp(r'[A-Za-z_:@\-]');
  static final RegExp _cssSelectorChar = RegExp(r'[^{,/"\x27\n]');
  static final RegExp _entity = RegExp(r'^&[#A-Za-z0-9]{1,10};');
  static final RegExp _reLower = RegExp('[a-z]');

  /// Friendly label for the code block header.
  static String label(String language) {
    final l = language.trim().toLowerCase();
    if (l.isEmpty) return 'code';
    return switch (l) {
      'js' || 'javascript' || 'jsx' || 'mjs' => 'javascript',
      'ts' || 'typescript' || 'tsx' => 'typescript',
      'py' || 'python' || 'python3' => 'python',
      'sh' || 'bash' || 'shell' || 'zsh' || 'console' => 'bash',
      'kt' || 'kotlin' => 'kotlin',
      'c++' || 'cpp' || 'cc' || 'hpp' => 'cpp',
      'cs' || 'csharp' || 'c#' => 'csharp',
      'yml' || 'yaml' => 'yaml',
      'md' || 'markdown' => 'markdown',
      'htm' || 'html' || 'xhtml' => 'html',
      _ => l,
    };
  }

  static String _family(String language) {
    switch (label(language)) {
      case 'html':
      case 'xml':
      case 'svg':
      case 'vue':
        return 'markup';
      case 'css':
      case 'scss':
      case 'sass':
      case 'less':
        return 'css';
      case 'python':
      case 'ruby':
      case 'rb':
      case 'r':
        return 'python';
      case 'bash':
      case 'powershell':
      case 'ps1':
      case 'dockerfile':
      case 'makefile':
      case 'yaml':
      case 'toml':
      case 'ini':
      case 'env':
        return 'hash';
      case 'sql':
      case 'mysql':
      case 'postgresql':
      case 'sqlite':
        return 'sql';
      case 'json':
      case 'jsonc':
        return 'json';
      case 'text':
      case 'txt':
      case 'plaintext':
      case 'markdown':
      case 'output':
        return 'none';
      case 'php':
        return 'php';
      default:
        return 'clike';
    }
  }

  static const _clikeKeywords = {
    // JavaScript / TypeScript
    'var', 'let', 'const', 'function', 'return', 'if', 'else', 'for', 'while', 'do', 'switch', 'case',
    'break', 'continue', 'default', 'new', 'delete', 'typeof', 'instanceof', 'in', 'of', 'try', 'catch',
    'finally', 'throw', 'class', 'extends', 'super', 'this', 'import', 'export', 'from', 'as', 'async',
    'await', 'yield', 'static', 'get', 'set', 'true', 'false', 'null', 'undefined', 'void', 'interface',
    'type', 'enum', 'implements', 'public', 'private', 'protected', 'readonly', 'abstract', 'declare',
    // Dart / Java / Kotlin / C-family / Go / Rust / Swift
    'final', 'late', 'required', 'dynamic', 'factory', 'mixin', 'with', 'is', 'sealed', 'base', 'when',
    'override', 'package', 'fun', 'val', 'object', 'companion', 'data', 'int', 'double', 'float', 'long',
    'short', 'char', 'bool', 'boolean', 'byte', 'string', 'struct', 'union', 'unsigned', 'signed',
    'sizeof', 'namespace', 'using', 'template', 'typename', 'virtual', 'friend', 'include', 'define',
    'func', 'go', 'defer', 'chan', 'map', 'range', 'select', 'fallthrough', 'fn', 'mut', 'pub', 'impl',
    'trait', 'match', 'loop', 'move', 'ref', 'self', 'Self', 'crate', 'mod', 'use', 'where',
    'guard', 'init', 'deinit', 'extension', 'protocol', 'inout', 'nil', 'throws', 'rethrows', 'operator',
    'goto', 'volatile', 'synchronized', 'transient', 'native', 'strictfp', 'assert', 'debugger', 'lateinit',
    'internal', 'open', 'inline', 'suspend', 'vararg', 'external', 'covariant', 'show', 'hide', 'part',
    'library', 'on', 'rethrow', 'sync', 'Function', 'Future', 'Stream', 'String', 'List', 'Map', 'Set',
  };

  static const _phpKeywords = {
    'echo', 'print', 'function', 'return', 'if', 'else', 'elseif', 'endif', 'foreach', 'endforeach', 'for',
    'while', 'do', 'switch', 'case', 'break', 'continue', 'default', 'new', 'class', 'extends', 'implements',
    'interface', 'trait', 'public', 'private', 'protected', 'static', 'const', 'abstract', 'final', 'try',
    'catch', 'finally', 'throw', 'namespace', 'use', 'as', 'require', 'require_once', 'include',
    'include_once', 'isset', 'unset', 'empty', 'array', 'list', 'true', 'false', 'null', 'self', 'parent',
    'instanceof', 'match', 'fn', 'yield', 'global', 'and', 'or', 'not', 'die', 'exit', 'enum', 'readonly',
    'int', 'float', 'string', 'bool', 'void', 'mixed', 'never', 'iterable', 'callable', 'object',
  };

  static const _pythonKeywords = {
    'def', 'return', 'if', 'elif', 'else', 'for', 'while', 'break', 'continue', 'pass', 'class', 'import',
    'from', 'as', 'try', 'except', 'finally', 'raise', 'with', 'lambda', 'yield', 'global', 'nonlocal',
    'and', 'or', 'not', 'in', 'is', 'None', 'True', 'False', 'async', 'await', 'del', 'assert', 'match',
    'case', 'self', 'print', 'end', 'begin', 'module', 'require', 'puts', 'unless', 'until', 'then', 'nil',
    'function', 'library',
  };

  static const _hashKeywords = {
    'if', 'then', 'else', 'elif', 'fi', 'for', 'in', 'do', 'done', 'while', 'until', 'case', 'esac',
    'function', 'return', 'export', 'local', 'echo', 'cd', 'sudo', 'apt', 'npm', 'npx', 'pip', 'git',
    'flutter', 'dart', 'node', 'mkdir', 'rm', 'cp', 'mv', 'ls', 'cat', 'curl', 'wget', 'chmod', 'source',
    'true', 'false', 'null', 'FROM', 'RUN', 'COPY', 'CMD', 'ENV', 'WORKDIR', 'EXPOSE', 'ENTRYPOINT',
  };

  static const _sqlKeywords = {
    'select', 'from', 'where', 'and', 'or', 'not', 'insert', 'into', 'values', 'update', 'set', 'delete',
    'create', 'table', 'drop', 'alter', 'add', 'column', 'primary', 'key', 'foreign', 'references', 'index',
    'unique', 'join', 'left', 'right', 'inner', 'outer', 'full', 'cross', 'on', 'as', 'group', 'by', 'order',
    'having', 'limit', 'offset', 'distinct', 'union', 'all', 'null', 'is', 'in', 'like', 'between', 'exists',
    'case', 'when', 'then', 'else', 'end', 'default', 'auto_increment', 'int', 'integer', 'bigint',
    'varchar', 'text', 'char', 'date', 'datetime', 'timestamp', 'boolean', 'decimal', 'float', 'engine',
    'if', 'database', 'use', 'view', 'trigger', 'procedure', 'begin', 'commit', 'rollback', 'transaction',
    'asc', 'desc', 'count', 'sum', 'avg', 'min', 'max', 'unsigned', 'constraint', 'cascade', 'true', 'false',
  };

  /// Coloured tokens of [code]; joining their texts returns [code] exactly.
  static List<CodeToken> highlight(String code, String language) {
    final out = <CodeToken>[];
    switch (_family(language)) {
      case 'markup':
        _markup(code, out);
      case 'css':
        _css(code, out);
      case 'none':
        out.add(CodeToken(code, CodeTok.plain));
      case 'json':
        _generic(code, out, keywords: const {'true', 'false', 'null'}, lineComment: null, jsonKeys: true);
      case 'python':
        _generic(code, out, keywords: _pythonKeywords, lineComment: '#', blockComment: false, tripleQuotes: true);
      case 'hash':
        _generic(code, out, keywords: _hashKeywords, lineComment: '#', blockComment: false, variables: true);
      case 'sql':
        _generic(code, out, keywords: _sqlKeywords, lineComment: '--', caseInsensitive: true);
      case 'php':
        _generic(code, out, keywords: _phpKeywords, lineComment: '//', hashComment: true, variables: true);
      default:
        _generic(code, out, keywords: _clikeKeywords, lineComment: '//', backtickStrings: true);
    }
    return _merge(out);
  }

  // ── Generic programming languages ─────────────────────────────────────────

  static bool _isIdentStart(int c) =>
      (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95 || c == 36 || c > 127;
  static bool _isIdent(int c) => _isIdentStart(c) || (c >= 48 && c <= 57);
  static bool _isDigit(int c) => c >= 48 && c <= 57;

  static void _generic(
    String s,
    List<CodeToken> out, {
    required Set<String> keywords,
    required String? lineComment,
    bool blockComment = true,
    bool hashComment = false,
    bool tripleQuotes = false,
    bool backtickStrings = false,
    bool variables = false,
    bool caseInsensitive = false,
    bool jsonKeys = false,
  }) {
    var i = 0;
    final n = s.length;
    final plain = StringBuffer();

    void flushPlain() {
      if (plain.isEmpty) return;
      out.add(CodeToken(plain.toString(), CodeTok.plain));
      plain.clear();
    }

    void emit(String text, CodeTok kind) {
      flushPlain();
      out.add(CodeToken(text, kind));
    }

    while (i < n) {
      final c = s.codeUnitAt(i);
      final ch = s[i];

      // Comments
      if (lineComment != null && s.startsWith(lineComment, i) ||
          hashComment && ch == '#' && !s.startsWith('#[', i)) {
        final end = s.indexOf('\n', i);
        final stop = end < 0 ? n : end;
        emit(s.substring(i, stop), CodeTok.comment);
        i = stop;
        continue;
      }
      if (blockComment && s.startsWith('/*', i)) {
        final end = s.indexOf('*/', i + 2);
        final stop = end < 0 ? n : end + 2;
        emit(s.substring(i, stop), CodeTok.comment);
        i = stop;
        continue;
      }

      // Strings
      if (tripleQuotes && (s.startsWith('"""', i) || s.startsWith("'''", i))) {
        final q = s.substring(i, i + 3);
        final end = s.indexOf(q, i + 3);
        final stop = end < 0 ? n : end + 3;
        emit(s.substring(i, stop), CodeTok.string);
        i = stop;
        continue;
      }
      if (ch == '"' || ch == "'" || (backtickStrings && ch == '`')) {
        var j = i + 1;
        while (j < n) {
          final d = s[j];
          if (d == r'\') {
            j += 2;
            continue;
          }
          if (d == ch) {
            j++;
            break;
          }
          if (d == '\n' && ch != '`') break; // unterminated: stop at line end
          j++;
        }
        final stop = j > n ? n : j;
        final text = s.substring(i, stop);
        var kind = CodeTok.string;
        if (jsonKeys) {
          var k = stop;
          while (k < n && (s[k] == ' ' || s[k] == '\t')) {
          k++;
          }
          if (k < n && s[k] == ':') kind = CodeTok.attr;
        }
        emit(text, kind);
        i = stop;
        continue;
      }

      // $variables (shell, PHP)
      if (variables && ch == r'$' && i + 1 < n && (_isIdentStart(s.codeUnitAt(i + 1)) || s[i + 1] == '{')) {
        var j = i + 1;
        if (s[j] == '{') {
          final close = s.indexOf('}', j);
          j = close < 0 ? n : close + 1;
        } else {
          while (j < n && _isIdent(s.codeUnitAt(j)) && s[j] != r'$') {
            j++;
          }
        }
        emit(s.substring(i, j), CodeTok.attr);
        i = j;
        continue;
      }

      // Numbers
      if (_isDigit(c) && (i == 0 || !_isIdent(s.codeUnitAt(i - 1)))) {
        var j = i + 1;
        while (j < n && (_isIdent(s.codeUnitAt(j)) || s[j] == '.') ) {
          if (s[j] == '.' && (j + 1 >= n || !_isDigit(s.codeUnitAt(j + 1)))) break;
          j++;
        }
        emit(s.substring(i, j), CodeTok.number);
        i = j;
        continue;
      }

      // Identifiers / keywords / functions / types
      if (_isIdentStart(c) && !(variables && ch == r'$')) {
        var j = i + 1;
        while (j < n && _isIdent(s.codeUnitAt(j)) && !(variables && s[j] == r'$')) {
          j++;
        }
        final word = s.substring(i, j);
        final key = caseInsensitive ? word.toLowerCase() : word;
        if (keywords.contains(key)) {
          emit(word, CodeTok.keyword);
        } else {
          var k = j;
          while (k < n && s[k] == ' ') {
            k++;
          }
          if (k < n && s[k] == '(') {
            emit(word, CodeTok.func);
          } else if (!caseInsensitive && word.length > 1 && c >= 65 && c <= 90 && word.contains(_reLower)) {
            emit(word, CodeTok.type);
          } else {
            plain.write(word);
          }
        }
        i = j;
        continue;
      }

      // Decorators / annotations: @Override, @app.route
      if (ch == '@' && i + 1 < n && _isIdentStart(s.codeUnitAt(i + 1))) {
        var j = i + 1;
        while (j < n && (_isIdent(s.codeUnitAt(j)) || s[j] == '.')) {
          j++;
        }
        emit(s.substring(i, j), CodeTok.keyword);
        i = j;
        continue;
      }

      if ('{}[]();,.:<>=+-*/%!&|^~?'.contains(ch)) {
        emit(ch, CodeTok.punct);
        i++;
        continue;
      }

      plain.write(ch);
      i++;
    }
    flushPlain();
  }

  // ── HTML / XML (with <style> and <script> inside) ─────────────────────────

  static void _markup(String s, List<CodeToken> out) {
    var i = 0;
    final n = s.length;
    final text = StringBuffer();

    void flushText() {
      if (text.isEmpty) return;
      out.add(CodeToken(text.toString(), CodeTok.plain));
      text.clear();
    }

    while (i < n) {
      if (s.startsWith('<!--', i)) {
        flushText();
        final end = s.indexOf('-->', i + 4);
        final stop = end < 0 ? n : end + 3;
        out.add(CodeToken(s.substring(i, stop), CodeTok.comment));
        i = stop;
        continue;
      }
      if (s[i] == '<' && i + 1 < n && _tagStart.hasMatch(s[i + 1])) {
        flushText();
        // Tag name
        var j = i + 1;
        if (s[j] == '/' || s[j] == '!' || s[j] == '?') j++;
        while (j < n && _tagNameChar.hasMatch(s[j])) {
          j++;
        }
        final tagName = s.substring(i, j).replaceAll(_tagPunct, '').toLowerCase();
        final closing = s.startsWith('</', i);
        out.add(CodeToken(s.substring(i, j), CodeTok.tag));
        // Attributes until '>'
        while (j < n && s[j] != '>') {
          final ch = s[j];
          if (ch == '"' || ch == "'") {
            final end = s.indexOf(ch, j + 1);
            final stop = end < 0 ? n : end + 1;
            out.add(CodeToken(s.substring(j, stop), CodeTok.string));
            j = stop;
          } else if (_attrStart.hasMatch(ch)) {
            var k = j;
            while (k < n && _attrChar.hasMatch(s[k])) {
              k++;
            }
            out.add(CodeToken(s.substring(j, k), CodeTok.attr));
            j = k;
          } else if (ch == '/' && j + 1 < n && s[j + 1] == '>') {
            break;
          } else {
            out.add(CodeToken(ch, ch == '=' ? CodeTok.punct : CodeTok.plain));
            j++;
          }
        }
        // "/>" or ">"
        var close = j;
        if (close < n && s[close] == '/') close++;
        if (close < n && s[close] == '>') close++;
        if (close > j) out.add(CodeToken(s.substring(j, close), CodeTok.tag));
        i = close;

        // Embedded CSS / JavaScript
        if (!closing && (tagName == 'style' || tagName == 'script')) {
          final endTag = s.toLowerCase().indexOf('</$tagName', i);
          final stop = endTag < 0 ? n : endTag;
          final inner = s.substring(i, stop);
          if (inner.isNotEmpty) {
            if (tagName == 'style') {
              _css(inner, out);
            } else {
              _generic(inner, out, keywords: _clikeKeywords, lineComment: '//', backtickStrings: true);
            }
          }
          i = stop;
        }
        continue;
      }
      if (s[i] == '&') {
        final m = _entity.firstMatch(s.substring(i, i + 12 > n ? n : i + 12));
        if (m != null) {
          flushText();
          out.add(CodeToken(m.group(0)!, CodeTok.number));
          i += m.end;
          continue;
        }
      }
      text.write(s[i]);
      i++;
    }
    flushText();
  }

  // ── CSS ───────────────────────────────────────────────────────────────────

  static void _css(String s, List<CodeToken> out) {
    var i = 0;
    final n = s.length;
    var depth = 0; // inside { } → properties
    final plain = StringBuffer();

    void flushPlain() {
      if (plain.isEmpty) return;
      out.add(CodeToken(plain.toString(), CodeTok.plain));
      plain.clear();
    }

    void emit(String t, CodeTok k) {
      flushPlain();
      out.add(CodeToken(t, k));
    }

    while (i < n) {
      final ch = s[i];
      if (s.startsWith('/*', i)) {
        final end = s.indexOf('*/', i + 2);
        final stop = end < 0 ? n : end + 2;
        emit(s.substring(i, stop), CodeTok.comment);
        i = stop;
        continue;
      }
      if (ch == '"' || ch == "'") {
        final end = s.indexOf(ch, i + 1);
        final stop = end < 0 ? n : end + 1;
        emit(s.substring(i, stop), CodeTok.string);
        i = stop;
        continue;
      }
      if (ch == '{') {
        depth++;
        emit(ch, CodeTok.punct);
        i++;
        continue;
      }
      if (ch == '}') {
        if (depth > 0) depth--;
        emit(ch, CodeTok.punct);
        i++;
        continue;
      }
      if (ch == '@') {
        var j = i + 1;
        while (j < n && _cssWordStart.hasMatch(s[j])) {
          j++;
        }
        emit(s.substring(i, j), CodeTok.keyword);
        i = j;
        continue;
      }
      if (depth > 0) {
        // Numbers, sizes and colours: 12px, -1.5rem, 50%, #0a0a0a
        if (ch == '#' || ch == '-' && i + 1 < n && _isDigit(s.codeUnitAt(i + 1)) || _isDigit(s.codeUnitAt(i)) ||
            (ch == '.' && i + 1 < n && _isDigit(s.codeUnitAt(i + 1)))) {
          var j = i + 1;
          while (j < n && _cssNumberChar.hasMatch(s[j])) {
            j++;
          }
          emit(s.substring(i, j), CodeTok.number);
          i = j;
          continue;
        }
        // property: value;
        if (_cssWordStart.hasMatch(ch)) {
          var j = i;
          while (j < n && _cssWordChar.hasMatch(s[j])) {
            j++;
          }
          var k = j;
          while (k < n && (s[k] == ' ' || s[k] == '\t')) {
            k++;
          }
          final word = s.substring(i, j);
          if (k < n && s[k] == ':' && _cssPropertyPosition(s, i)) {
            emit(word, CodeTok.attr);
          } else if (k < n && s[k] == '(') {
            emit(word, CodeTok.func);
          } else {
            plain.write(word);
          }
          i = j;
          continue;
        }
        if (s.startsWith('!important', i)) {
          emit('!important', CodeTok.keyword);
          i += 10;
          continue;
        }
      } else if (_cssSelectorStart.hasMatch(ch)) {
        // Selectors
        var j = i;
        while (j < n && _cssSelectorChar.hasMatch(s[j]) && !s.startsWith('/*', j)) {
          j++;
        }
        final sel = s.substring(i, j);
        final trimmed = sel.trimRight();
        emit(trimmed, CodeTok.tag);
        if (trimmed.length < sel.length) plain.write(sel.substring(trimmed.length));
        i = j;
        continue;
      }
      if (':;,'.contains(ch)) {
        emit(ch, CodeTok.punct);
        i++;
        continue;
      }
      plain.write(ch);
      i++;
    }
    flushPlain();
  }

  /// A word followed by ":" is a property when it starts a declaration.
  static bool _cssPropertyPosition(String s, int i) {
    var k = i - 1;
    while (k >= 0 && (s[k] == ' ' || s[k] == '\t' || s[k] == '\n' || s[k] == '\r')) {
      k--;
    }
    return k < 0 || s[k] == '{' || s[k] == ';';
  }

  static List<CodeToken> _merge(List<CodeToken> tokens) {
    final out = <CodeToken>[];
    for (final t in tokens) {
      if (t.text.isEmpty) continue;
      if (out.isNotEmpty && out.last.kind == t.kind) {
        out[out.length - 1] = CodeToken(out.last.text + t.text, t.kind);
      } else {
        out.add(t);
      }
    }
    return out;
  }
}
