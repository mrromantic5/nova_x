// lib/features/browser/devtools/tabs/tools_tab.dart
//
// Developer utilities that work offline: JSON formatter/validator, JWT
// decoder, Base64, URL encode/decode + parser, Unix timestamp converter,
// regex tester, color converter, UUID generator, HTML entities, text diff.

import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../../xcoder/ai/xcoder_ai.dart' show lineDiff, DiffOp;
import '../dt_ui.dart';

class ToolsTab extends StatefulWidget {
  const ToolsTab({super.key});

  @override
  State<ToolsTab> createState() => _ToolsTabState();
}

class _ToolsTabState extends State<ToolsTab> {
  String _tool = 'json';
  final _in = TextEditingController();
  final _in2 = TextEditingController();
  final _pattern = TextEditingController();
  String _flags = 'g';

  static const _tools = [
    ('json', 'JSON'),
    ('jwt', 'JWT'),
    ('b64', 'Base64'),
    ('url', 'URL'),
    ('time', 'Timestamp'),
    ('regex', 'Regex'),
    ('color', 'Color'),
    ('uuid', 'UUID'),
    ('html', 'HTML entities'),
    ('diff', 'Diff'),
  ];

  @override
  void dispose() {
    _in.dispose();
    _in2.dispose();
    _pattern.dispose();
    super.dispose();
  }

  Widget _field(TextEditingController c, String hint, {int lines = 6}) => Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
        child: TextField(
          controller: c,
          minLines: lines,
          maxLines: lines + 6,
          autocorrect: false,
          enableSuggestions: false,
          style: XC.mono(12.5),
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: XC.mono(12, color: XC.faint),
            filled: true,
            fillColor: XC.bg,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
          ),
        ),
      );

  Widget _out(String label, String text, {Color? color}) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 0), child: Text(label, style: XC.ui(11.5, color: color ?? XC.dim, weight: FontWeight.w700))),
        DtCode(text, label: label),
      ]);

  Widget _err(String msg) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
        child: Text(msg, style: XC.mono(12, color: XC.error)),
      );

  static String _b64Fix(String s) {
    var t = s.trim().replaceAll('-', '+').replaceAll('_', '/').replaceAll(RegExp(r'\s'), '');
    while (t.length % 4 != 0) {
      t += '=';
    }
    return t;
  }

  Widget _body() {
    final t = _in.text;
    switch (_tool) {
      case 'json':
        Object? v;
        String? err;
        if (t.trim().isNotEmpty) {
          try {
            v = jsonDecode(t);
          } on FormatException catch (e) {
            err = 'Invalid JSON: ${e.message}${e.offset != null ? ' (character ${e.offset})' : ''}';
          }
        }
        return ListView(children: [
          _field(_in, '{"paste": "JSON here"}'),
          if (err != null) _err(err),
          if (v != null) ...[
            Padding(padding: const EdgeInsets.fromLTRB(12, 4, 12, 0), child: Text('✓ Valid JSON', style: XC.ui(12, color: XC.ok))),
            _out('Formatted', const JsonEncoder.withIndent('  ').convert(v)),
            _out('Minified', jsonEncode(v)),
            const DtSection('Tree'),
            JsonTree(v),
          ],
        ]);
      case 'jwt':
        final parts = t.trim().split('.');
        Widget? res;
        if (t.trim().isNotEmpty) {
          if (parts.length < 2) {
            res = _err('A JWT has 3 parts separated by dots.');
          } else {
            try {
              final h = jsonDecode(utf8.decode(base64.decode(_b64Fix(parts[0]))));
              final p = jsonDecode(utf8.decode(base64.decode(_b64Fix(parts[1]))));
              String when(Object? s) => s is num ? '${DateTime.fromMillisecondsSinceEpoch(s.toInt() * 1000).toLocal()}' : '—';
              final exp = p is Map && p['exp'] is num ? DateTime.fromMillisecondsSinceEpoch((p['exp'] as num).toInt() * 1000) : null;
              res = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _out('Header', const JsonEncoder.withIndent('  ').convert(h)),
                _out('Payload', const JsonEncoder.withIndent('  ').convert(p)),
                if (p is Map) ...[
                  DtKV('issued (iat)', when(p['iat'])),
                  DtKV('expires (exp)', exp == null ? '—' : '${exp.toLocal()} ${exp.isBefore(DateTime.now()) ? '(EXPIRED)' : ''}',
                      valueColor: exp != null && exp.isBefore(DateTime.now()) ? XC.error : XC.ok),
                  DtKV('subject (sub)', '${p['sub'] ?? '—'}'),
                  DtKV('issuer (iss)', '${p['iss'] ?? '—'}'),
                ],
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text('The signature is not verified here (that needs the secret or public key).', style: XC.ui(11.5, color: XC.faint)),
                ),
              ]);
            } catch (e) {
              res = _err('Not a valid JWT: $e');
            }
          }
        }
        return ListView(children: [_field(_in, 'eyJhbGciOi…', lines: 4), if (res != null) res]);
      case 'b64':
        String enc = '', dec = '';
        String? decErr;
        if (t.isNotEmpty) {
          enc = base64.encode(utf8.encode(t));
          try {
            dec = utf8.decode(base64.decode(_b64Fix(t)), allowMalformed: true);
          } catch (_) {
            decErr = 'Not valid Base64';
          }
        }
        return ListView(children: [
          _field(_in, 'Text or Base64', lines: 4),
          if (t.isNotEmpty) _out('Encoded', enc),
          if (t.isNotEmpty && decErr == null) _out('Decoded', dec),
          if (decErr != null) _err(decErr),
          if (t.isNotEmpty) _out('URL-safe', base64Url.encode(utf8.encode(t)).replaceAll('=', '')),
        ]);
      case 'url':
        final u = Uri.tryParse(t.trim());
        String dec;
        try {
          dec = Uri.decodeFull(t);
        } catch (_) {
          dec = '(invalid escape sequence)';
        }
        return ListView(children: [
          _field(_in, 'https://example.com/path?q=hello%20world', lines: 3),
          if (t.isNotEmpty) ...[
            _out('Encoded (component)', Uri.encodeComponent(t)),
            _out('Decoded', dec),
            if (u != null && u.hasScheme) ...[
              const DtSection('Parsed'),
              DtKV('scheme', u.scheme),
              DtKV('host', u.host),
              DtKV('port', u.hasPort ? '${u.port}' : '(default)'),
              DtKV('path', u.path),
              DtKV('fragment', u.fragment),
              if (u.queryParametersAll.isNotEmpty) DtSection('Query (${u.queryParametersAll.length})'),
              for (final q in u.queryParametersAll.entries) DtKV(q.key, q.value.join(', ')),
            ],
          ],
        ]);
      case 'time':
        final n = int.tryParse(t.trim());
        DateTime? d;
        if (n != null) d = n > 100000000000 ? DateTime.fromMillisecondsSinceEpoch(n) : DateTime.fromMillisecondsSinceEpoch(n * 1000);
        d ??= DateTime.tryParse(t.trim());
        final now = DateTime.now();
        return ListView(children: [
          _field(_in, 'Unix seconds / milliseconds, or 2026-10-30T12:00:00Z', lines: 2),
          if (d != null) ...[
            DtKV('local', d.toLocal().toString()),
            DtKV('UTC', d.toUtc().toIso8601String()),
            DtKV('unix (s)', '${d.millisecondsSinceEpoch ~/ 1000}'),
            DtKV('unix (ms)', '${d.millisecondsSinceEpoch}'),
            DtKV('relative', _rel(now.difference(d))),
          ] else if (t.trim().isNotEmpty)
            _err('Not a timestamp or ISO date'),
          const DtSection('Now'),
          DtKV('unix (s)', '${now.millisecondsSinceEpoch ~/ 1000}'),
          DtKV('unix (ms)', '${now.millisecondsSinceEpoch}'),
          DtKV('ISO (UTC)', now.toUtc().toIso8601String()),
        ]);
      case 'regex':
        RegExp? re;
        String? err;
        if (_pattern.text.isNotEmpty) {
          try {
            re = RegExp(_pattern.text, caseSensitive: !_flags.contains('i'), multiLine: _flags.contains('m'), dotAll: _flags.contains('s'), unicode: _flags.contains('u'));
          } catch (e) {
            err = '$e';
          }
        }
        final matches = re == null ? const <RegExpMatch>[] : (_flags.contains('g') ? re.allMatches(t).take(500).toList() : [if (re.firstMatch(t) != null) re.firstMatch(t)!]);
        final spans = <TextSpan>[];
        var last = 0;
        for (final m in matches) {
          if (m.start < last) continue;
          spans.add(TextSpan(text: t.substring(last, m.start), style: XC.mono(12.5)));
          spans.add(TextSpan(text: t.substring(m.start, m.end), style: XC.mono(12.5, color: Colors.black).copyWith(backgroundColor: const Color(0xFFFFCB6B))));
          last = m.end;
        }
        spans.add(TextSpan(text: t.substring(last), style: XC.mono(12.5)));
        return ListView(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
            child: Row(children: [
              Text('/', style: XC.mono(16, color: XC.faint)),
              Expanded(
                child: TextField(
                  controller: _pattern,
                  autocorrect: false,
                  enableSuggestions: false,
                  style: XC.mono(13, color: const Color(0xFFD16969)),
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(isDense: true, hintText: r'\b\w+@\w+\.\w+\b', border: InputBorder.none),
                ),
              ),
              Text('/', style: XC.mono(16, color: XC.faint)),
              for (final f in ['g', 'i', 'm', 's', 'u'])
                DtChip(f, selected: _flags.contains(f), onTap: () => setState(() => _flags = _flags.contains(f) ? _flags.replaceAll(f, '') : _flags + f)),
            ]),
          ),
          if (err != null) _err(err),
          _field(_in, 'Test text', lines: 5),
          if (re != null) ...[
            Padding(padding: const EdgeInsets.fromLTRB(12, 4, 12, 4), child: Text('${matches.length} match${matches.length == 1 ? '' : 'es'}', style: XC.ui(12, color: XC.dim))),
            if (t.isNotEmpty) Container(margin: const EdgeInsets.symmetric(horizontal: 10), padding: const EdgeInsets.all(10), color: XC.bg, child: SelectableText.rich(TextSpan(children: spans))),
            for (final (i, m) in matches.take(50).indexed)
              ExpansionTile(
                dense: true,
                title: Text('#${i + 1}  "${m.group(0)}"', style: XC.mono(12)),
                subtitle: Text('index ${m.start}–${m.end}', style: XC.ui(10.5, color: XC.faint)),
                children: [
                  for (var g = 1; g <= m.groupCount; g++) DtKV('group $g', m.group(g) ?? '(none)'),
                  for (final n in m.groupNames) DtKV('<$n>', m.namedGroup(n) ?? '(none)'),
                ],
              ),
          ],
        ]);
      case 'color':
        final c = _parseColor(t.trim());
        return ListView(children: [
          _field(_in, '#00d4ff · rgb(0,212,255) · hsl(190,100%,50%)', lines: 1),
          if (c != null) ...[
            Container(height: 64, margin: const EdgeInsets.all(10), decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(10), border: Border.all(color: XC.border))),
            DtKV('HEX', '#${(c.value & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}${c.alpha < 255 ? c.alpha.toRadixString(16).padLeft(2, '0') : ''}'),
            DtKV('RGB', 'rgb(${c.red}, ${c.green}, ${c.blue}${c.alpha < 255 ? ', ${(c.alpha / 255).toStringAsFixed(2)}' : ''})'),
            DtKV('HSL', _hsl(c)),
            DtKV('Flutter', 'Color(0x${c.value.toRadixString(16).padLeft(8, '0').toUpperCase()})'),
            DtKV('contrast on white', '${_contrast(c, Colors.white).toStringAsFixed(2)}:1'),
            DtKV('contrast on black', '${_contrast(c, Colors.black).toStringAsFixed(2)}:1'),
          ] else if (t.trim().isNotEmpty)
            _err('Unknown color format'),
        ]);
      case 'uuid':
        final r = Random.secure();
        String v4() {
          final b = List<int>.generate(16, (_) => r.nextInt(256));
          b[6] = (b[6] & 0x0f) | 0x40;
          b[8] = (b[8] & 0x3f) | 0x80;
          final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
          return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
        }

        final ids = List.generate(8, (_) => v4());
        return ListView(children: [
          Padding(
            padding: const EdgeInsets.all(10),
            child: Row(children: [
              Expanded(child: Text('Random UUID v4 (secure random)', style: XC.ui(12.5, color: XC.dim))),
              TextButton.icon(onPressed: () => setState(() {}), icon: const Icon(Icons.refresh_rounded, size: 16), label: const Text('New')),
            ]),
          ),
          for (final id in ids) DtKV('uuid', id),
          _out('All', ids.join('\n')),
        ]);
      case 'html':
        String esc(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;').replaceAll("'", '&#39;');
        String unesc(String s) => s
            .replaceAllMapped(RegExp(r'&#(\d+);'), (m) => String.fromCharCode(int.parse(m.group(1)!)))
            .replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)))
            .replaceAll('&lt;', '<')
            .replaceAll('&gt;', '>')
            .replaceAll('&quot;', '"')
            .replaceAll('&apos;', "'")
            .replaceAll('&nbsp;', ' ')
            .replaceAll('&amp;', '&');
        return ListView(children: [
          _field(_in, '<div class="x">Tom & Jerry</div>', lines: 4),
          if (t.isNotEmpty) ...[_out('Escaped', esc(t)), _out('Unescaped', unesc(t))],
        ]);
      default: // diff
        final d = lineDiff(_in.text, _in2.text);
        return ListView(children: [
          _field(_in, 'Original text', lines: 4),
          _field(_in2, 'Changed text', lines: 4),
          if (_in.text.isNotEmpty || _in2.text.isNotEmpty)
            Container(
              margin: const EdgeInsets.all(10),
              color: XC.bg,
              child: Column(children: [
                for (final l in d)
                  Container(
                    width: double.infinity,
                    color: l.op == DiffOp.add ? XC.added : (l.op == DiffOp.remove ? XC.removed : null),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                    child: Text('${l.op == DiffOp.add ? '+' : l.op == DiffOp.remove ? '−' : ' '} ${l.text}', style: XC.mono(12)),
                  ),
              ]),
            ),
        ]);
    }
  }

  static String _rel(Duration d) {
    final past = !d.isNegative;
    final a = d.abs();
    final s = a.inDays > 0 ? '${a.inDays} days' : a.inHours > 0 ? '${a.inHours} hours' : a.inMinutes > 0 ? '${a.inMinutes} minutes' : '${a.inSeconds} seconds';
    return past ? '$s ago' : 'in $s';
  }

  static Color? _parseColor(String s) {
    final t = s.toLowerCase();
    var m = RegExp(r'^#?([0-9a-f]{3,8})$').firstMatch(t);
    if (m != null) {
      var h = m.group(1)!;
      if (h.length == 3 || h.length == 4) h = h.split('').map((c) => '$c$c').join();
      if (h.length == 6) return Color(int.parse('ff$h', radix: 16));
      if (h.length == 8) return Color(int.parse(h.substring(6) + h.substring(0, 6), radix: 16));
      return null;
    }
    m = RegExp(r'^rgba?\(\s*(\d+)[,\s]+(\d+)[,\s]+(\d+)(?:[,\s/]+([\d.]+))?\s*\)$').firstMatch(t);
    if (m != null) {
      final a = m.group(4) == null ? 1.0 : double.tryParse(m.group(4)!) ?? 1.0;
      return Color.fromRGBO(int.parse(m.group(1)!).clamp(0, 255), int.parse(m.group(2)!).clamp(0, 255), int.parse(m.group(3)!).clamp(0, 255), a.clamp(0.0, 1.0));
    }
    m = RegExp(r'^hsla?\(\s*([\d.]+)(?:deg)?[,\s]+([\d.]+)%[,\s]+([\d.]+)%(?:[,\s/]+([\d.]+))?\s*\)$').firstMatch(t);
    if (m != null) {
      final a = m.group(4) == null ? 1.0 : double.tryParse(m.group(4)!) ?? 1.0;
      return HSLColor.fromAHSL(a.clamp(0.0, 1.0), double.parse(m.group(1)!) % 360, (double.parse(m.group(2)!) / 100).clamp(0.0, 1.0),
              (double.parse(m.group(3)!) / 100).clamp(0.0, 1.0))
          .toColor();
    }
    return null;
  }

  static String _hsl(Color c) {
    final h = HSLColor.fromColor(c);
    return 'hsl(${h.hue.round()}, ${(h.saturation * 100).round()}%, ${(h.lightness * 100).round()}%)';
  }

  static double _contrast(Color a, Color b) {
    final la = a.computeLuminance(), lb = b.computeLuminance();
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05);
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      SizedBox(
        height: 38,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6), children: [
          for (final (k, l) in _tools)
            DtChip(l, selected: _tool == k, onTap: () => setState(() {
                  _tool = k;
                })),
        ]),
      ),
      const Divider(height: 1, color: XC.border),
      Expanded(child: _body()),
    ]);
  }
}
