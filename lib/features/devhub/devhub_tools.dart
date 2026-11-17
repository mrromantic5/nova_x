// lib/features/devhub/devhub_tools.dart
//
// NOVA X Developer Hub — Toolbox logic. Pure Dart, runs on the device only
// (nothing is sent anywhere). Tested in test/desktop/devhub_test.dart.

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Result of a tool run: text to show, or an error.
class ToolOutput {
  const ToolOutput(this.text, {this.error, this.notes = const []});
  const ToolOutput.error(String message)
      : text = '',
        error = message,
        notes = const [];
  final String text;
  final String? error;

  /// Short facts shown above the output ("3 keys · depth 2").
  final List<String> notes;
  bool get ok => error == null;
}

class DevTools {
  DevTools._();

  // ── JSON ──────────────────────────────────────────────────────────────────
  static ToolOutput jsonFormat(String input, {int indent = 2, bool sortKeys = false, bool minify = false}) {
    final src = input.trim();
    if (src.isEmpty) return const ToolOutput.error('Paste JSON to format it.');
    Object? data;
    try {
      data = jsonDecode(src);
    } on FormatException catch (e) {
      return ToolOutput.error(_jsonError(src, e));
    }
    if (sortKeys) data = _sorted(data);
    final out = minify ? jsonEncode(data) : JsonEncoder.withIndent(' ' * indent).convert(data);
    final s = _jsonStats(data);
    return ToolOutput(out, notes: [
      'Valid JSON',
      '${s.$1} key${s.$1 == 1 ? '' : 's'}',
      '${s.$2} item${s.$2 == 1 ? '' : 's'} in arrays',
      'depth ${s.$3}',
      '${utf8.encode(out).length} bytes',
    ]);
  }

  static String _jsonError(String src, FormatException e) {
    final off = e.offset;
    if (off == null || off < 0 || off > src.length) return 'Invalid JSON: ${e.message}';
    final before = src.substring(0, off);
    final line = '\n'.allMatches(before).length + 1;
    final col = off - (before.lastIndexOf('\n') + 1) + 1;
    return 'Invalid JSON at line $line, column $col: ${e.message}';
  }

  static Object? _sorted(Object? v) {
    if (v is Map) {
      final keys = v.keys.map((k) => '$k').toList()..sort();
      return {for (final k in keys) k: _sorted(v[k])};
    }
    if (v is List) return [for (final x in v) _sorted(x)];
    return v;
  }

  /// (keys, array items, depth)
  static (int, int, int) _jsonStats(Object? v, [int depth = 0]) {
    if (v is Map) {
      var k = v.length, a = 0, d = depth + 1;
      for (final x in v.values) {
        final s = _jsonStats(x, depth + 1);
        k += s.$1;
        a += s.$2;
        d = max(d, s.$3);
      }
      return (k, a, d);
    }
    if (v is List) {
      var k = 0, a = v.length, d = depth + 1;
      for (final x in v) {
        final s = _jsonStats(x, depth + 1);
        k += s.$1;
        a += s.$2;
        d = max(d, s.$3);
      }
      return (k, a, d);
    }
    return (0, 0, depth);
  }

  // ── JWT ───────────────────────────────────────────────────────────────────
  /// Decodes (does not verify) a JSON Web Token.
  static ToolOutput jwtDecode(String token, {DateTime? now}) {
    final t = token.trim().replaceFirst(RegExp(r'^Bearer\s+', caseSensitive: false), '');
    final parts = t.split('.');
    if (parts.length != 3 && parts.length != 5) {
      return const ToolOutput.error('A JWT has three parts separated by dots (header.payload.signature).');
    }
    if (parts.length == 5) return const ToolOutput.error('This is an encrypted JWT (JWE); its payload can\'t be read without the key.');
    Map<String, dynamic> header, payload;
    try {
      header = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[0])))) as Map<String, dynamic>;
      payload = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1])))) as Map<String, dynamic>;
    } catch (_) {
      return const ToolOutput.error('The header or payload isn\'t valid Base64URL-encoded JSON.');
    }
    final notes = <String>[];
    final n = now ?? DateTime.now();
    final alg = '${header['alg'] ?? '?'}';
    notes.add('alg $alg');
    if (alg.toLowerCase() == 'none') notes.add('⚠ alg "none": unsigned token — never accept it on a server');
    String when(String claim) {
      final v = payload[claim];
      if (v is! num) return '';
      final d = DateTime.fromMillisecondsSinceEpoch((v * 1000).round(), isUtc: true);
      return '${d.toIso8601String()} (${relative(d, n)})';
    }

    if (payload['exp'] is num) {
      final exp = DateTime.fromMillisecondsSinceEpoch(((payload['exp'] as num) * 1000).round(), isUtc: true);
      notes.add(exp.isBefore(n) ? 'Expired ${relative(exp, n)}' : 'Expires ${relative(exp, n)}');
    } else {
      notes.add('No expiry (exp)');
    }
    final enc = const JsonEncoder.withIndent('  ');
    final b = StringBuffer()
      ..writeln('// Header')
      ..writeln(enc.convert(header))
      ..writeln()
      ..writeln('// Payload')
      ..writeln(enc.convert(payload));
    final times = [for (final c in ['iat', 'nbf', 'exp']) if (when(c).isNotEmpty) '$c: ${when(c)}'];
    if (times.isNotEmpty) {
      b
        ..writeln()
        ..writeln('// Times (UTC)');
      for (final x in times) {
        b.writeln(x);
      }
    }
    b
      ..writeln()
      ..writeln('// Signature: ${parts[2].isEmpty ? '(none)' : '${parts[2].length} characters — not verified here (needs the key)'}');
    return ToolOutput(b.toString().trimRight(), notes: notes);
  }

  // ── Base64 ────────────────────────────────────────────────────────────────
  static ToolOutput base64Encode(String input, {bool urlSafe = false}) {
    final bytes = utf8.encode(input);
    var out = urlSafe ? base64Url.encode(bytes) : base64.encode(bytes);
    if (urlSafe) out = out.replaceAll('=', '');
    return ToolOutput(out, notes: ['${bytes.length} bytes in', '${out.length} characters out']);
  }

  static ToolOutput base64Decode(String input) {
    var s = input.replaceAll(RegExp(r'\s'), '');
    if (s.isEmpty) return const ToolOutput.error('Paste Base64 to decode it.');
    s = s.replaceAll('-', '+').replaceAll('_', '/');
    if (s.startsWith('data:') && s.contains(',')) s = s.substring(s.indexOf(',') + 1);
    try {
      final bytes = base64.decode(base64.normalize(s));
      try {
        final text = utf8.decode(bytes);
        return ToolOutput(text, notes: ['${bytes.length} bytes', 'UTF-8 text']);
      } on FormatException {
        return ToolOutput(hexDump(bytes), notes: ['${bytes.length} bytes', 'Binary — shown as hex']);
      }
    } on FormatException {
      return const ToolOutput.error('That isn\'t valid Base64.');
    }
  }

  static String hexDump(List<int> bytes, {int max = 4096}) {
    final b = StringBuffer();
    final n = bytes.length < max ? bytes.length : max;
    for (var i = 0; i < n; i += 16) {
      final row = bytes.sublist(i, i + 16 > n ? n : i + 16);
      b.write(i.toRadixString(16).padLeft(8, '0'));
      b.write('  ');
      b.write(row.map((x) => x.toRadixString(16).padLeft(2, '0')).join(' ').padRight(48));
      b.write('  ');
      b.writeln(String.fromCharCodes(row.map((x) => x >= 32 && x < 127 ? x : 46)));
    }
    if (bytes.length > max) b.writeln('… ${bytes.length - max} more bytes');
    return b.toString().trimRight();
  }

  // ── URL ───────────────────────────────────────────────────────────────────
  static ToolOutput urlEncode(String input) => ToolOutput(Uri.encodeComponent(input));

  static ToolOutput urlDecode(String input) {
    try {
      return ToolOutput(Uri.decodeComponent(input.replaceAll('+', ' ')));
    } catch (_) {
      return const ToolOutput.error('Invalid percent-encoding (a % must be followed by two hex digits).');
    }
  }

  static ToolOutput urlParse(String input) {
    final u = Uri.tryParse(input.trim());
    if (u == null || (!u.hasScheme && !input.contains('/'))) return const ToolOutput.error('That isn\'t a URL.');
    final b = StringBuffer()
      ..writeln('scheme    ${u.scheme}')
      ..writeln('host      ${u.host}')
      ..writeln('port      ${u.hasPort ? u.port : '(default ${u.scheme == 'https' ? 443 : u.scheme == 'http' ? 80 : '-'})'}')
      ..writeln('path      ${u.path.isEmpty ? '/' : u.path}');
    if (u.userInfo.isNotEmpty) b.writeln('user      ${u.userInfo}');
    if (u.hasFragment) b.writeln('fragment  ${u.fragment}');
    final q = u.queryParametersAll;
    if (q.isNotEmpty) {
      b.writeln('\nquery (${q.length})');
      for (final e in q.entries) {
        for (final v in e.value) {
          b.writeln('  ${e.key} = $v');
        }
      }
    }
    return ToolOutput(b.toString().trimRight(), notes: [if (q.isNotEmpty) '${q.length} query parameter${q.length == 1 ? '' : 's'}']);
  }

  // ── Hashes ────────────────────────────────────────────────────────────────
  static ToolOutput hashes(String input, {String hmacKey = ''}) {
    final bytes = utf8.encode(input);
    final b = StringBuffer()
      ..writeln('MD5      ${md5.convert(bytes)}')
      ..writeln('SHA-1    ${sha1.convert(bytes)}')
      ..writeln('SHA-256  ${sha256.convert(bytes)}')
      ..writeln('SHA-512  ${sha512.convert(bytes)}');
    if (hmacKey.isNotEmpty) {
      final k = utf8.encode(hmacKey);
      b
        ..writeln()
        ..writeln('HMAC-SHA256  ${Hmac(sha256, k).convert(bytes)}')
        ..writeln('HMAC-SHA512  ${Hmac(sha512, k).convert(bytes)}');
    }
    return ToolOutput(b.toString().trimRight(), notes: ['${bytes.length} bytes (UTF-8)', 'MD5 / SHA-1 are not safe for passwords or signatures']);
  }

  // ── UUID ──────────────────────────────────────────────────────────────────
  static String uuidV4([Random? r]) {
    final rnd = r ?? Random.secure();
    final b = List<int>.generate(16, (_) => rnd.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }

  static ToolOutput uuids(int count, {bool upper = false}) {
    final n = count.clamp(1, 1000);
    final list = [for (var i = 0; i < n; i++) upper ? uuidV4().toUpperCase() : uuidV4()];
    return ToolOutput(list.join('\n'), notes: ['$n × UUID v4 (cryptographically random)']);
  }

  // ── Timestamps ────────────────────────────────────────────────────────────
  static ToolOutput timestamp(String input, {DateTime? now}) {
    final n = now ?? DateTime.now();
    final s = input.trim();
    DateTime? d;
    String kind;
    if (s.isEmpty) {
      d = n;
      kind = 'Now';
    } else if (RegExp(r'^-?\d+(\.\d+)?$').hasMatch(s)) {
      final v = double.parse(s);
      final digits = s.replaceAll('-', '').split('.').first.length;
      if (digits >= 16) {
        d = DateTime.fromMicrosecondsSinceEpoch(v.round(), isUtc: true);
        kind = 'Unix microseconds';
      } else if (digits >= 12) {
        d = DateTime.fromMillisecondsSinceEpoch(v.round(), isUtc: true);
        kind = 'Unix milliseconds';
      } else {
        d = DateTime.fromMillisecondsSinceEpoch((v * 1000).round(), isUtc: true);
        kind = 'Unix seconds';
      }
    } else {
      d = DateTime.tryParse(s);
      kind = 'Date / time text';
    }
    if (d == null) return const ToolOutput.error('Enter a Unix timestamp (seconds or milliseconds) or a date like 2026-11-16T10:30:00Z.');
    final utc = d.toUtc();
    final local = d.toLocal();
    final off = local.timeZoneOffset;
    final sign = off.isNegative ? '-' : '+';
    final oh = off.inHours.abs().toString().padLeft(2, '0');
    final om = (off.inMinutes.abs() % 60).toString().padLeft(2, '0');
    final b = StringBuffer()
      ..writeln('Unix (s)    ${utc.millisecondsSinceEpoch ~/ 1000}')
      ..writeln('Unix (ms)   ${utc.millisecondsSinceEpoch}')
      ..writeln('UTC         ${utc.toIso8601String()}')
      ..writeln('Local       ${local.toIso8601String().replaceFirst(RegExp(r'\.\d+$'), '')}$sign$oh:$om (${local.timeZoneName})')
      ..writeln('RFC 1123    ${_rfc1123(utc)}')
      ..writeln('Relative    ${relative(utc, n)}');
    return ToolOutput(b.toString().trimRight(), notes: [kind]);
  }

  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  static String _rfc1123(DateTime u) {
    String two(int x) => x.toString().padLeft(2, '0');
    return '${_days[u.weekday - 1]}, ${two(u.day)} ${_months[u.month - 1]} ${u.year} ${two(u.hour)}:${two(u.minute)}:${two(u.second)} GMT';
  }

  /// "in 3 days", "5 minutes ago".
  static String relative(DateTime d, DateTime now) {
    final diff = d.difference(now);
    final past = diff.isNegative;
    final a = diff.abs();
    String unit(int v, String u) => '$v $u${v == 1 ? '' : 's'}';
    final String t;
    if (a.inSeconds < 45) {
      return past ? 'just now' : 'in a few seconds';
    } else if (a.inMinutes < 60) {
      t = unit(a.inMinutes.clamp(1, 59).toInt(), 'minute');
    } else if (a.inHours < 24) {
      t = unit(a.inHours, 'hour');
    } else if (a.inDays < 45) {
      t = unit(a.inDays, 'day');
    } else if (a.inDays < 365) {
      t = unit((a.inDays / 30).round(), 'month');
    } else {
      t = unit((a.inDays / 365).floor(), 'year');
    }
    return past ? '$t ago' : 'in $t';
  }

  // ── Regex ─────────────────────────────────────────────────────────────────
  static const int maxMatches = 500;

  /// Matches of [pattern] in [text] (ECMAScript-style syntax, like JavaScript).
  static (List<RegExpMatch>, String?) regex(String pattern, String text,
      {bool ignoreCase = false, bool multiLine = false, bool dotAll = false, bool unicode = false}) {
    if (pattern.isEmpty) return (const [], null);
    try {
      final re = RegExp(pattern, caseSensitive: !ignoreCase, multiLine: multiLine, dotAll: dotAll, unicode: unicode);
      final out = <RegExpMatch>[];
      for (final m in re.allMatches(text)) {
        out.add(m);
        if (out.length >= maxMatches) break;
      }
      return (out, null);
    } on FormatException catch (e) {
      return (const [], 'Invalid pattern: ${e.message}');
    }
  }

  static String describeMatches(List<RegExpMatch> ms) {
    final b = StringBuffer();
    for (var i = 0; i < ms.length; i++) {
      final m = ms[i];
      b.writeln('#${i + 1}  [${m.start}–${m.end}]  "${m[0]}"');
      for (var g = 1; g <= m.groupCount; g++) {
        b.writeln('     group $g: ${m[g] == null ? '(no match)' : '"${m[g]}"'}');
      }
      for (final name in m.groupNames) {
        b.writeln('     <$name>: ${m.namedGroup(name) == null ? '(no match)' : '"${m.namedGroup(name)}"'}');
      }
    }
    return b.toString().trimRight();
  }

  // ── Colours ───────────────────────────────────────────────────────────────
  /// r, g, b in 0–255 and a in 0–1, or null.
  static (int, int, int, double)? parseColor(String input) {
    final s = input.trim().toLowerCase();
    final hex = RegExp(r'^#?([0-9a-f]{3,4}|[0-9a-f]{6}|[0-9a-f]{8})$').firstMatch(s);
    if (hex != null) {
      var h = hex.group(1)!;
      if (h.length <= 4) h = h.split('').map((c) => '$c$c').join();
      final r = int.parse(h.substring(0, 2), radix: 16);
      final g = int.parse(h.substring(2, 4), radix: 16);
      final b = int.parse(h.substring(4, 6), radix: 16);
      final a = h.length == 8 ? int.parse(h.substring(6, 8), radix: 16) / 255 : 1.0;
      return (r, g, b, a);
    }
    final fn = RegExp(r'^(rgba?|hsla?)\(\s*([^)]+)\)$').firstMatch(s);
    if (fn == null) return null;
    final parts = fn.group(2)!.split(RegExp(r'[\s,/]+')).where((x) => x.isNotEmpty).toList();
    if (parts.length < 3) return null;
    double val(String x, double scale) =>
        x.endsWith('%') ? double.parse(x.substring(0, x.length - 1)) / 100 * scale : double.parse(x.replaceAll('deg', ''));
    try {
      final a = parts.length > 3 ? (parts[3].endsWith('%') ? val(parts[3], 1) : double.parse(parts[3])) : 1.0;
      if (fn.group(1)!.startsWith('rgb')) {
        return (val(parts[0], 255).round().clamp(0, 255).toInt(), val(parts[1], 255).round().clamp(0, 255).toInt(),
            val(parts[2], 255).round().clamp(0, 255).toInt(), a.clamp(0, 1).toDouble());
      }
      final h = val(parts[0], 360) % 360;
      final sat = val(parts[1], 1).clamp(0, 1).toDouble();
      final l = val(parts[2], 1).clamp(0, 1).toDouble();
      final rgb = _hslToRgb(h, sat, l);
      return (rgb.$1, rgb.$2, rgb.$3, a.clamp(0, 1).toDouble());
    } catch (_) {
      return null;
    }
  }

  static (int, int, int) _hslToRgb(double h, double s, double l) {
    final c = (1 - (2 * l - 1).abs()) * s;
    final x = c * (1 - ((h / 60) % 2 - 1).abs());
    final m = l - c / 2;
    final (r1, g1, b1) = h < 60
        ? (c, x, 0.0)
        : h < 120
            ? (x, c, 0.0)
            : h < 180
                ? (0.0, c, x)
                : h < 240
                    ? (0.0, x, c)
                    : h < 300
                        ? (x, 0.0, c)
                        : (c, 0.0, x);
    return (((r1 + m) * 255).round(), ((g1 + m) * 255).round(), ((b1 + m) * 255).round());
  }

  static (double, double, double) rgbToHsl(int r, int g, int b) {
    final rf = r / 255, gf = g / 255, bf = b / 255;
    final mx = max(rf, max(gf, bf)), mn = min(rf, min(gf, bf));
    final l = (mx + mn) / 2;
    if (mx == mn) return (0, 0, l * 100);
    final d = mx - mn;
    final s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn);
    double h;
    if (mx == rf) {
      h = ((gf - bf) / d + (gf < bf ? 6 : 0));
    } else if (mx == gf) {
      h = (bf - rf) / d + 2;
    } else {
      h = (rf - gf) / d + 4;
    }
    return (h * 60, s * 100, l * 100);
  }

  /// WCAG 2.x contrast ratio (1–21).
  static double contrast((int, int, int) a, (int, int, int) b) {
    double lum((int, int, int) c) {
      double ch(int v) {
        final s = v / 255;
        return s <= 0.03928 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4).toDouble();
      }

      return 0.2126 * ch(c.$1) + 0.7152 * ch(c.$2) + 0.0722 * ch(c.$3);
    }

    final la = lum(a), lb = lum(b);
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05);
  }

  static ToolOutput colorInfo(String fg, String bg) {
    final c = parseColor(fg);
    if (c == null) return const ToolOutput.error('Enter a colour: #0B57D0, #fff, rgb(11 87 208), hsl(217 90% 43%).');
    String hex2(int v) => v.toRadixString(16).padLeft(2, '0').toUpperCase();
    final alpha = (c.$4 * 255).round();
    final hasAlpha = c.$4 < 1;
    final hsl = rgbToHsl(c.$1, c.$2, c.$3);
    final a = hasAlpha ? ' / ${c.$4.toStringAsFixed(2)}' : '';
    final lines = <String>[
      'HEX      #${hex2(c.$1)}${hex2(c.$2)}${hex2(c.$3)}${hasAlpha ? hex2(alpha) : ''}',
      'RGB      rgb(${c.$1} ${c.$2} ${c.$3}$a)',
      'HSL      hsl(${hsl.$1.round()} ${hsl.$2.round()}% ${hsl.$3.round()}%$a)',
      'Flutter  Color(0x${hex2(alpha)}${hex2(c.$1)}${hex2(c.$2)}${hex2(c.$3)})',
    ];
    final notes = <String>[];
    final other = parseColor(bg);
    if (other != null) {
      final r = contrast((c.$1, c.$2, c.$3), (other.$1, other.$2, other.$3));
      lines
        ..add('')
        ..add('Contrast with ${bg.trim()}: ${r.toStringAsFixed(2)} : 1')
        ..add('  Normal text  AA ${r >= 4.5 ? 'pass' : 'fail'} · AAA ${r >= 7 ? 'pass' : 'fail'}')
        ..add('  Large text   AA ${r >= 3 ? 'pass' : 'fail'} · AAA ${r >= 4.5 ? 'pass' : 'fail'}')
        ..add('  UI / icons   ${r >= 3 ? 'pass' : 'fail'} (needs 3 : 1)');
      notes.add('${r.toStringAsFixed(2)} : 1');
    }
    return ToolOutput(lines.join('\n'), notes: notes);
  }

  // ── Diff ──────────────────────────────────────────────────────────────────
  /// Line diff: (' ', line) same, ('-', line) removed, ('+', line) added.
  static List<(String, String)> diffLines(String a, String b, {int maxLines = 3000}) {
    final x = a.split('\n'), y = b.split('\n');
    if (x.length > maxLines || y.length > maxLines) {
      return [('!', 'Too long to compare here (over $maxLines lines).')];
    }
    final n = x.length, m = y.length;
    final dp = List.generate(n + 1, (_) => Uint32List(m + 1));
    for (var i = n - 1; i >= 0; i--) {
      for (var j = m - 1; j >= 0; j--) {
        dp[i][j] = x[i] == y[j] ? dp[i + 1][j + 1] + 1 : max(dp[i + 1][j], dp[i][j + 1]);
      }
    }
    final out = <(String, String)>[];
    var i = 0, j = 0;
    while (i < n && j < m) {
      if (x[i] == y[j]) {
        out.add((' ', x[i]));
        i++;
        j++;
      } else if (dp[i + 1][j] >= dp[i][j + 1]) {
        out.add(('-', x[i++]));
      } else {
        out.add(('+', y[j++]));
      }
    }
    while (i < n) {
      out.add(('-', x[i++]));
    }
    while (j < m) {
      out.add(('+', y[j++]));
    }
    return out;
  }

  // ── Number bases ──────────────────────────────────────────────────────────
  static ToolOutput numberBases(String input) {
    var s = input.trim().replaceAll('_', '').replaceAll(' ', '').toLowerCase();
    if (s.isEmpty) return const ToolOutput.error('Enter a number: 255, 0xff, 0b1010, 0o17.');
    var neg = false;
    if (s.startsWith('-')) {
      neg = true;
      s = s.substring(1);
    }
    int radix = 10;
    if (s.startsWith('0x')) {
      radix = 16;
      s = s.substring(2);
    } else if (s.startsWith('0b')) {
      radix = 2;
      s = s.substring(2);
    } else if (s.startsWith('0o')) {
      radix = 8;
      s = s.substring(2);
    }
    final v = BigInt.tryParse(s, radix: radix);
    if (v == null) return const ToolOutput.error('That isn\'t a valid number in this base.');
    final n = neg ? -v : v;
    final b = StringBuffer()
      ..writeln('Decimal      $n')
      ..writeln('Hexadecimal  ${neg ? '-' : ''}0x${v.toRadixString(16).toUpperCase()}')
      ..writeln('Octal        ${neg ? '-' : ''}0o${v.toRadixString(8)}')
      ..writeln('Binary       ${neg ? '-' : ''}0b${v.toRadixString(2)}')
      ..writeln('Bits needed  ${v.bitLength}');
    return ToolOutput(b.toString().trimRight());
  }

  // ── HTML entities ─────────────────────────────────────────────────────────
  static String htmlEncode(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');

  static const Map<String, String> _named = {
    'amp': '&', 'lt': '<', 'gt': '>', 'quot': '"', 'apos': "'", 'nbsp': ' ', 'copy': '©', 'reg': '®',
    'trade': '™', 'hellip': '…', 'mdash': '—', 'ndash': '–', 'laquo': '«', 'raquo': '»', 'euro': '€', 'pound': '£',
    'yen': '¥', 'cent': '¢', 'deg': '°', 'times': '×', 'divide': '÷', 'middot': '·', 'bull': '•', 'lsquo': '‘',
    'rsquo': '’', 'ldquo': '“', 'rdquo': '”',
  };

  static String htmlDecode(String s) => s.replaceAllMapped(RegExp(r'&(#x[0-9a-fA-F]+|#\d+|[a-zA-Z]+);'), (m) {
        final e = m.group(1)!;
        if (e.startsWith('#x') || e.startsWith('#X')) {
          final c = int.tryParse(e.substring(2), radix: 16);
          return c == null || c > 0x10FFFF ? m.group(0)! : String.fromCharCode(c);
        }
        if (e.startsWith('#')) {
          final c = int.tryParse(e.substring(1));
          return c == null || c > 0x10FFFF ? m.group(0)! : String.fromCharCode(c);
        }
        return _named[e] ?? m.group(0)!;
      });

  // ── Case converter ────────────────────────────────────────────────────────
  static List<String> words(String s) {
    final spaced = s
        .replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m[1]} ${m[2]}')
        .replaceAllMapped(RegExp(r'([A-Z]+)([A-Z][a-z])'), (m) => '${m[1]} ${m[2]}');
    return spaced.split(RegExp(r'[^A-Za-z0-9]+')).where((w) => w.isNotEmpty).map((w) => w.toLowerCase()).toList();
  }

  static ToolOutput caseConvert(String input) {
    final w = words(input);
    if (w.isEmpty) return const ToolOutput.error('Type a name or phrase, e.g. "user profile id".');
    String cap(String x) => x[0].toUpperCase() + x.substring(1);
    final b = StringBuffer()
      ..writeln('camelCase       ${w.first}${w.skip(1).map(cap).join()}')
      ..writeln('PascalCase      ${w.map(cap).join()}')
      ..writeln('snake_case      ${w.join('_')}')
      ..writeln('CONSTANT_CASE   ${w.join('_').toUpperCase()}')
      ..writeln('kebab-case      ${w.join('-')}')
      ..writeln('Title Case      ${w.map(cap).join(' ')}')
      ..writeln('dot.case        ${w.join('.')}');
    return ToolOutput(b.toString().trimRight());
  }

  // ── Secrets ───────────────────────────────────────────────────────────────
  static String secret({int length = 32, bool lower = true, bool upper = true, bool digits = true, bool symbols = true, Random? r}) {
    final sets = [
      if (lower) 'abcdefghijkmnopqrstuvwxyz',
      if (upper) 'ABCDEFGHJKLMNPQRSTUVWXYZ',
      if (digits) '23456789',
      if (symbols) '!@#\$%^&*()-_=+[]{};:,.?',
    ];
    if (sets.isEmpty) return '';
    final rnd = r ?? Random.secure();
    final all = sets.join();
    final n = length.clamp(4, 256);
    // At least one character from every chosen set.
    final chars = [for (final s in sets) s[rnd.nextInt(s.length)]];
    while (chars.length < n) {
      chars.add(all[rnd.nextInt(all.length)]);
    }
    chars.shuffle(rnd);
    return chars.join();
  }

  static ToolOutput secrets({int length = 32, bool lower = true, bool upper = true, bool digits = true, bool symbols = true}) {
    final pw = secret(length: length, lower: lower, upper: upper, digits: digits, symbols: symbols);
    if (pw.isEmpty) return const ToolOutput.error('Choose at least one kind of character.');
    final rnd = Random.secure();
    String hex(int bytes) => List.generate(bytes, (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    String b64(int bytes) => base64Url.encode(List.generate(bytes, (_) => rnd.nextInt(256))).replaceAll('=', '');
    var pool = 0;
    if (lower) pool += 25;
    if (upper) pool += 24;
    if (digits) pool += 8;
    if (symbols) pool += 23;
    final bits = (log(pool) / ln2 * pw.length).round();
    final b = StringBuffer()
      ..writeln('Password      $pw')
      ..writeln()
      ..writeln('Hex key 128   ${hex(16)}')
      ..writeln('Hex key 256   ${hex(32)}')
      ..writeln('Base64URL 256 ${b64(32)}')
      ..writeln('Base64URL 512 ${b64(64)}');
    return ToolOutput(b.toString().trimRight(), notes: ['≈$bits bits of entropy', 'Made on this device with a secure random generator']);
  }
}
