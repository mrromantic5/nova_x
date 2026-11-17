// lib/features/devhub/devhub_toolbox.dart
//
// NOVA X Developer Hub — Toolbox (Android port of the Windows Developer Hub,
// 3.14.0): 14 everyday developer utilities. Everything runs on the phone;
// nothing is sent anywhere, and results update as you type.
// Logic: devhub_tools.dart (same as Windows, same tests).
//
// Phones: [DevToolGrid] lists the tools; a tap opens [DevToolPage], the tool
// full screen. Tablets: [DevToolbox] with the tool list on the left.

import 'package:flutter/material.dart';

import '../cyber/ui/cyber_palette.dart';
import '../cyber/ui/cyber_widgets.dart' show CodeBlock, kMono;
import 'devhub_tools.dart';

class DevToolInfo {
  const DevToolInfo(this.id, this.name, this.icon, this.description);
  final String id;
  final String name;
  final IconData icon;
  final String description;
}

class DevToolbox extends StatefulWidget {
  const DevToolbox({super.key, this.initial = 'json', this.single = false});
  final String initial;

  /// Only the [initial] tool, without the tool list (phone tool page).
  final bool single;

  static const List<DevToolInfo> tools = [
    DevToolInfo('json', 'JSON', Icons.data_object_rounded, 'Format, validate (with line and column of errors), minify and sort keys.'),
    DevToolInfo('jwt', 'JWT decoder', Icons.key_rounded, 'Read a JSON Web Token: header, claims, expiry. Decoded here, never sent anywhere.'),
    DevToolInfo('base64', 'Base64', Icons.swap_horiz_rounded, 'Encode text, or decode Base64 / Base64URL / data URLs (binary shown as hex).'),
    DevToolInfo('url', 'URL', Icons.link_rounded, 'Percent-encode, decode, or break a URL into its parts and query parameters.'),
    DevToolInfo('hash', 'Hash & HMAC', Icons.tag_rounded, 'MD5, SHA-1, SHA-256, SHA-512 and HMAC-SHA256 / 512 of any text.'),
    DevToolInfo('uuid', 'UUID', Icons.fingerprint_rounded, 'Cryptographically random UUID v4, one or many at once.'),
    DevToolInfo('time', 'Timestamp', Icons.schedule_rounded, 'Unix seconds / milliseconds ↔ ISO 8601, UTC, local time and RFC 1123.'),
    DevToolInfo('regex', 'Regex tester', Icons.manage_search_rounded, 'Live matches and groups, highlighted. JavaScript-style syntax and flags.'),
    DevToolInfo('color', 'Colour & contrast', Icons.palette_outlined, 'HEX / RGB / HSL / Flutter Color, and the WCAG contrast ratio of two colours.'),
    DevToolInfo('diff', 'Text diff', Icons.difference_outlined, 'Line-by-line comparison of two texts: added and removed lines.'),
    DevToolInfo('base', 'Number bases', Icons.numbers_rounded, 'Decimal, hex, octal and binary, any size (0xff, 0b1010, 0o17).'),
    DevToolInfo('html', 'HTML entities', Icons.code_rounded, 'Escape text for HTML, or turn &amp; / &#39; / &#x27; back into characters.'),
    DevToolInfo('case', 'Case converter', Icons.text_fields_rounded, 'camelCase, PascalCase, snake_case, CONSTANT_CASE, kebab-case and more.'),
    DevToolInfo('secret', 'Secret generator', Icons.password_rounded, 'Strong passwords and random keys (hex, Base64URL) from a secure generator.'),
  ];

  @override
  State<DevToolbox> createState() => _DevToolboxState();
}

class _DevToolboxState extends State<DevToolbox> {
  late String _id = DevToolbox.tools.any((t) => t.id == widget.initial) ? widget.initial : 'json';

  // Inputs (kept while you switch tools).
  final _in = <String, TextEditingController>{};
  TextEditingController _c(String key, [String initial = '']) =>
      _in.putIfAbsent(key, () => TextEditingController(text: initial)..addListener(() => setState(() {})));

  // Options
  int _indent = 2;
  bool _sortKeys = false, _minify = false;
  String _b64Mode = 'encode';
  bool _urlSafe = false;
  String _urlMode = 'parse';
  int _uuidCount = 5;
  bool _uuidUpper = false;
  String _uuidOut = '';
  bool _ri = false, _rm = false, _rs = false, _ru = false;
  String _htmlMode = 'encode';
  double _secretLen = 24;
  bool _sLower = true, _sUpper = true, _sDigits = true, _sSymbols = true;
  ToolOutput? _secretOut;

  @override
  void dispose() {
    for (final c in _in.values) {
      c.dispose();
    }
    super.dispose();
  }

  DevToolInfo get _tool => DevToolbox.tools.firstWhere((t) => t.id == _id);

  @override
  Widget build(BuildContext context) {
    final p = NovaThemeScope.of(context);
    if (widget.single) {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(_tool.description, style: p.ui(size: 13, color: p.textMuted, height: 1.4)),
          const SizedBox(height: 14),
          _body(p),
        ]),
      );
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        width: 210,
        decoration: BoxDecoration(color: p.surfaceAlt, border: Border(right: BorderSide(color: p.border))),
        child: ListView(padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8), children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
            child: Text('TOOLBOX', style: p.ui(size: 10.5, color: p.textFaint, weight: FontWeight.w700, letterSpacing: 0.8)),
          ),
          for (final t in DevToolbox.tools)
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => setState(() => _id = t.id),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                margin: const EdgeInsets.only(bottom: 2),
                decoration: BoxDecoration(color: _id == t.id ? p.surface : null, borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _id == t.id ? p.border : Colors.transparent)),
                child: Row(children: [
                  Icon(t.icon, size: 16, color: _id == t.id ? p.accent : p.textMuted),
                  const SizedBox(width: 10),
                  Expanded(child: Text(t.name, style: p.ui(size: 13, weight: _id == t.id ? FontWeight.w700 : FontWeight.w500))),
                ]),
              ),
            ),
        ]),
      ),
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Icon(_tool.icon, size: 22, color: p.accent),
                  const SizedBox(width: 10),
                  Text(_tool.name, style: p.title(size: 22)),
                ]),
                const SizedBox(height: 4),
                Text(_tool.description, style: p.ui(size: 13, color: p.textMuted)),
                const SizedBox(height: 18),
                _body(p),
              ]),
            ),
          ),
        ),
      ),
    ]);
  }

  // ── Building blocks ───────────────────────────────────────────────────────
  Widget _input(NovaPalette p, TextEditingController c, String hint, {int lines = 8, bool singleLine = false}) => TextField(
        controller: c,
        maxLines: singleLine ? 1 : null,
        minLines: singleLine ? 1 : lines,
        style: kMono.copyWith(fontSize: 13, color: p.text),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: kMono.copyWith(fontSize: 13, color: p.textFaint),
          contentPadding: const EdgeInsets.all(14),
        ),
      );

  Widget _seg(NovaPalette p, List<(String, String)> items, String value, ValueChanged<String> onChanged) => SegmentedButton<String>(
        segments: [for (final (v, l) in items) ButtonSegment(value: v, label: Text(l))],
        selected: {value},
        showSelectedIcon: false,
        style: const ButtonStyle(visualDensity: VisualDensity.compact),
        onSelectionChanged: (s) => onChanged(s.first),
      );

  Widget _check(NovaPalette p, String label, bool v, ValueChanged<bool> onChanged) => Row(mainAxisSize: MainAxisSize.min, children: [
        Checkbox(value: v, onChanged: (x) => onChanged(x ?? false), visualDensity: VisualDensity.compact),
        Text(label, style: p.ui(size: 12.5)),
        const SizedBox(width: 10),
      ]);

  Widget _output(NovaPalette p, ToolOutput? o, {String label = 'RESULT'}) {
    if (o == null || (o.text.isEmpty && o.error == null)) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 14),
      if (o.notes.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Wrap(spacing: 6, runSpacing: 6, children: [
            for (final n in o.notes)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (n.startsWith('⚠') || n.startsWith('Expired') ? p.warning : p.accent).withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(n,
                    style: p.ui(size: 11.5, weight: FontWeight.w600, color: n.startsWith('⚠') || n.startsWith('Expired') ? p.warning : p.accent)),
              ),
          ]),
        ),
      if (o.error != null)
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: p.danger.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: p.danger.withValues(alpha: 0.35)),
          ),
          child: Row(children: [
            Icon(Icons.error_outline_rounded, size: 17, color: p.danger),
            const SizedBox(width: 8),
            Expanded(child: Text(o.error!, style: p.ui(size: 12.5))),
          ]),
        )
      else
        CodeBlock(o.text, label: label, maxHeight: 460),
    ]);
  }

  Widget _row(List<Widget> children) => Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: children);

  // ── Tools ─────────────────────────────────────────────────────────────────
  Widget _body(NovaPalette p) {
    switch (_id) {
      case 'json':
        final c = _c('json');
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _row([
            _seg(p, const [('2', '2 spaces'), ('4', '4 spaces')], '$_indent', (v) => setState(() => _indent = int.parse(v))),
            _check(p, 'Sort keys', _sortKeys, (v) => setState(() => _sortKeys = v)),
            _check(p, 'Minify', _minify, (v) => setState(() => _minify = v)),
          ]),
          const SizedBox(height: 10),
          _input(p, c, '{"paste": "JSON here"}', lines: 10),
          if (c.text.trim().isNotEmpty) _output(p, DevTools.jsonFormat(c.text, indent: _indent, sortKeys: _sortKeys, minify: _minify), label: 'JSON'),
        ]);
      case 'jwt':
        final c = _c('jwt');
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _input(p, c, 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9…  (a "Bearer …" header works too)', lines: 4),
          if (c.text.trim().isNotEmpty) _output(p, DevTools.jwtDecode(c.text), label: 'DECODED (NOT VERIFIED)'),
        ]);
      case 'base64':
        final c = _c('b64');
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _row([
            _seg(p, const [('encode', 'Encode'), ('decode', 'Decode')], _b64Mode, (v) => setState(() => _b64Mode = v)),
            if (_b64Mode == 'encode') _check(p, 'URL-safe (Base64URL, no padding)', _urlSafe, (v) => setState(() => _urlSafe = v)),
          ]),
          const SizedBox(height: 10),
          _input(p, c, _b64Mode == 'encode' ? 'Text to encode' : 'Base64, Base64URL or data:…;base64,… to decode'),
          if (c.text.isNotEmpty) _output(p, _b64Mode == 'encode' ? DevTools.base64Encode(c.text, urlSafe: _urlSafe) : DevTools.base64Decode(c.text)),
        ]);
      case 'url':
        final c = _c('url');
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _row([
            _seg(p, const [('parse', 'Parse'), ('encode', 'Encode'), ('decode', 'Decode')], _urlMode, (v) => setState(() => _urlMode = v)),
          ]),
          const SizedBox(height: 10),
          _input(p, c, _urlMode == 'parse' ? 'https://example.com/search?q=nova+x&page=2#top' : 'Text', lines: 4),
          if (c.text.isNotEmpty)
            _output(
                p,
                switch (_urlMode) {
                  'encode' => DevTools.urlEncode(c.text),
                  'decode' => DevTools.urlDecode(c.text),
                  _ => DevTools.urlParse(c.text),
                }),
        ]);
      case 'hash':
        final c = _c('hash'), k = _c('hmac');
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _input(p, c, 'Text to hash', lines: 5),
          const SizedBox(height: 10),
          _input(p, k, 'HMAC key (optional)', singleLine: true),
          if (c.text.isNotEmpty) _output(p, DevTools.hashes(c.text, hmacKey: k.text), label: 'HASHES (HEX)'),
        ]);
      case 'uuid':
        if (_uuidOut.isEmpty) _uuidOut = DevTools.uuids(_uuidCount, upper: _uuidUpper).text;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _row([
            Text('How many', style: p.ui(size: 12.5)),
            SizedBox(
              width: 90,
              child: TextField(
                controller: _c('uuidN', '$_uuidCount'),
                style: kMono.copyWith(fontSize: 13, color: p.text),
                keyboardType: TextInputType.number,
                onChanged: (v) => _uuidCount = int.tryParse(v) ?? 1,
                decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.all(10)),
              ),
            ),
            _check(p, 'Uppercase', _uuidUpper, (v) => setState(() {
                  _uuidUpper = v;
                  _uuidOut = _uuidUpper ? _uuidOut.toUpperCase() : _uuidOut.toLowerCase();
                })),
            FilledButton.icon(
              onPressed: () => setState(() => _uuidOut = DevTools.uuids(_uuidCount, upper: _uuidUpper).text),
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Generate'),
            ),
          ]),
          _output(p, ToolOutput(_uuidOut, notes: const ['UUID v4 · cryptographically random']), label: 'UUID v4'),
        ]);
      case 'time':
        final c = _c('time');
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: _input(p, c, '1794787918  ·  1794787918924  ·  2026-11-16T04:13:00Z  (empty = now)', singleLine: true)),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: () => c.text = '${DateTime.now().millisecondsSinceEpoch ~/ 1000}',
              child: const Text('Now'),
            ),
          ]),
          _output(p, DevTools.timestamp(c.text), label: 'TIME'),
        ]);
      case 'regex':
        return _regex(p);
      case 'color':
        final fg = _c('fg', '#0B57D0'), bg = _c('bg', '#FFFFFF');
        final a = DevTools.parseColor(fg.text), b = DevTools.parseColor(bg.text);
        Color? col((int, int, int, double)? x) => x == null ? null : Color.fromARGB((x.$4 * 255).round(), x.$1, x.$2, x.$3);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _input(p, fg, 'Colour (#0B57D0, rgb(…), hsl(…))', singleLine: true),
          const SizedBox(height: 10),
          _input(p, bg, 'Background to test contrast (optional)', singleLine: true),
          const SizedBox(height: 12),
          if (a != null)
            Container(
              height: 86,
              decoration: BoxDecoration(color: col(b) ?? p.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: p.border)),
              alignment: Alignment.center,
              child: Text('The quick brown fox — Aa 123',
                  style: p.ui(size: 22, weight: FontWeight.w700, color: col(a))),
            ),
          _output(p, DevTools.colorInfo(fg.text, bg.text), label: 'COLOUR'),
        ]);
      case 'diff':
        return _diff(p);
      case 'base':
        final c = _c('base');
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _input(p, c, '255  ·  0xFF  ·  0b11111111  ·  0o377', singleLine: true),
          if (c.text.isNotEmpty) _output(p, DevTools.numberBases(c.text), label: 'BASES'),
        ]);
      case 'html':
        final c = _c('html');
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _row([_seg(p, const [('encode', 'Escape'), ('decode', 'Unescape')], _htmlMode, (v) => setState(() => _htmlMode = v))]),
          const SizedBox(height: 10),
          _input(p, c, _htmlMode == 'encode' ? '<a href="?q=1&x=2">Tom\'s</a>' : '&lt;b&gt;Caf&eacute; &amp; &#x1F680;&lt;/b&gt;', lines: 5),
          if (c.text.isNotEmpty) _output(p, ToolOutput(_htmlMode == 'encode' ? DevTools.htmlEncode(c.text) : DevTools.htmlDecode(c.text))),
        ]);
      case 'case':
        final c = _c('case');
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _input(p, c, 'user profile id  ·  userProfileId  ·  USER_PROFILE_ID', singleLine: true),
          if (c.text.isNotEmpty) _output(p, DevTools.caseConvert(c.text), label: 'CASES'),
        ]);
      case 'secret':
        _secretOut ??= DevTools.secrets(length: _secretLen.round());
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Text('Length ${_secretLen.round()}', style: p.ui(size: 12.5, weight: FontWeight.w600)),
            Expanded(
              child: Slider(
                value: _secretLen,
                min: 8,
                max: 128,
                divisions: 120,
                onChanged: (v) => setState(() => _secretLen = v),
                onChangeEnd: (_) => setState(_regen),
              ),
            ),
          ]),
          _row([
            _check(p, 'a–z', _sLower, (v) => setState(() {
                  _sLower = v;
                  _regen();
                })),
            _check(p, 'A–Z', _sUpper, (v) => setState(() {
                  _sUpper = v;
                  _regen();
                })),
            _check(p, '0–9', _sDigits, (v) => setState(() {
                  _sDigits = v;
                  _regen();
                })),
            _check(p, 'Symbols', _sSymbols, (v) => setState(() {
                  _sSymbols = v;
                  _regen();
                })),
            FilledButton.icon(onPressed: () => setState(_regen), icon: const Icon(Icons.refresh_rounded, size: 16), label: const Text('Generate')),
          ]),
          _output(p, _secretOut, label: 'SECRETS'),
        ]);
    }
    return const SizedBox.shrink();
  }

  /// New secrets for the current options (call inside setState).
  void _regen() {
    _secretOut = DevTools.secrets(
        length: _secretLen.round(), lower: _sLower, upper: _sUpper, digits: _sDigits, symbols: _sSymbols);
  }

  Widget _regex(NovaPalette p) {
    final pat = _c('rePat', r'(\w+)@(\w+)\.com');
    final txt = _c('reText', 'Contact: ama@example.com, kofi@nova.com\nSales: sales@shop.org');
    final (matches, err) = DevTools.regex(pat.text, txt.text, ignoreCase: _ri, multiLine: _rm, dotAll: _rs, unicode: _ru);
    final spans = <TextSpan>[];
    var at = 0;
    for (final m in matches) {
      if (m.start < at) continue;
      if (m.start > at) spans.add(TextSpan(text: txt.text.substring(at, m.start)));
      spans.add(TextSpan(
        text: txt.text.substring(m.start, m.end).isEmpty ? '∅' : txt.text.substring(m.start, m.end),
        style: TextStyle(backgroundColor: p.accent.withValues(alpha: 0.25), color: p.text, fontWeight: FontWeight.w700),
      ));
      at = m.end;
      if (m.end == m.start) at = m.end; // empty match
    }
    if (at < txt.text.length) spans.add(TextSpan(text: txt.text.substring(at)));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Text('/', style: kMono.copyWith(fontSize: 18, color: p.textFaint)),
        const SizedBox(width: 6),
        Expanded(child: _input(p, pat, r'pattern, e.g. ^\d{3}-\d{4}$', singleLine: true)),
        const SizedBox(width: 6),
        Text('/', style: kMono.copyWith(fontSize: 18, color: p.textFaint)),
      ]),
      const SizedBox(height: 8),
      Wrap(children: [
        for (final (f, v, set) in [
          ('i', _ri, (bool x) => _ri = x),
          ('m', _rm, (bool x) => _rm = x),
          ('s', _rs, (bool x) => _rs = x),
          ('u', _ru, (bool x) => _ru = x),
        ])
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: FilterChip(
              label: Text(f, style: kMono.copyWith(fontSize: 13, color: p.text, fontWeight: FontWeight.w700)),
              selected: v,
              tooltip: const {'i': 'ignore case', 'm': 'multi-line (^ \$ per line)', 's': 'dot matches new lines', 'u': 'unicode'}[f],
              onSelected: (x) => setState(() => set(x)),
              visualDensity: VisualDensity.compact,
            ),
          ),
      ]),
      const SizedBox(height: 10),
      _input(p, txt, 'Test text', lines: 6),
      const SizedBox(height: 12),
      if (err != null)
        _output(p, ToolOutput.error(err))
      else ...[
        Text(
            matches.isEmpty
                ? 'No matches'
                : '${matches.length}${matches.length >= DevTools.maxMatches ? '+' : ''} match${matches.length == 1 ? '' : 'es'}',
            style: p.ui(size: 12.5, weight: FontWeight.w700, color: matches.isEmpty ? p.textFaint : p.success)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: p.surfaceAlt, borderRadius: BorderRadius.circular(8), border: Border.all(color: p.border)),
          child: SelectableText.rich(TextSpan(style: kMono.copyWith(fontSize: 13, color: p.textMuted), children: spans)),
        ),
        if (matches.isNotEmpty) _output(p, ToolOutput(DevTools.describeMatches(matches)), label: 'MATCHES & GROUPS'),
      ],
    ]);
  }

  Widget _diff(NovaPalette p) {
    final a = _c('diffA'), b = _c('diffB');
    final lines = (a.text.isEmpty && b.text.isEmpty) ? const <(String, String)>[] : DevTools.diffLines(a.text, b.text);
    final added = lines.where((l) => l.$1 == '+').length, removed = lines.where((l) => l.$1 == '-').length;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _input(p, a, 'Original', lines: 6),
      const SizedBox(height: 10),
      _input(p, b, 'Changed', lines: 6),
      if (lines.isNotEmpty) ...[
        const SizedBox(height: 14),
        Text(added == 0 && removed == 0 ? 'Identical' : '+$added added · −$removed removed',
            style: p.ui(size: 12.5, weight: FontWeight.w700, color: added == 0 && removed == 0 ? p.success : p.text)),
        const SizedBox(height: 8),
        Container(
          constraints: const BoxConstraints(maxHeight: 480),
          decoration: BoxDecoration(color: p.surfaceAlt, borderRadius: BorderRadius.circular(8), border: Border.all(color: p.border)),
          child: ListView.builder(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: lines.length,
            itemBuilder: (_, i) {
              final (k, t) = lines[i];
              final color = k == '+' ? p.success : (k == '-' ? p.danger : null);
              return Container(
                color: color?.withValues(alpha: 0.10),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
                child: Text('${k == ' ' ? ' ' : k} $t', style: kMono.copyWith(fontSize: 12.5, color: color ?? p.textMuted)),
              );
            },
          ),
        ),
      ],
    ]);
  }
}

/// Phones: the 14 tools as a grid; a tap opens the tool full screen.
class DevToolGrid extends StatelessWidget {
  const DevToolGrid({super.key});

  @override
  Widget build(BuildContext context) {
    final p = NovaThemeScope.of(context);
    final w = MediaQuery.of(context).size.width;
    final cols = w > 840 ? 4 : (w > 560 ? 3 : 2);
    return GridView.count(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      crossAxisCount: cols,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.25,
      children: [
        for (final t in DevToolbox.tools)
          Material(
            color: p.surface,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => DevToolPage(id: t.id))),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: p.border)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(t.icon, color: p.accent, size: 22),
                  const Spacer(),
                  Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: p.ui(size: 13.5, weight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(t.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: p.ui(size: 11, color: p.textFaint, height: 1.3)),
                ]),
              ),
            ),
          ),
      ],
    );
  }
}

/// One Toolbox tool, full screen (phones).
class DevToolPage extends StatelessWidget {
  const DevToolPage({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context) {
    final t = DevToolbox.tools.firstWhere((x) => x.id == id, orElse: () => DevToolbox.tools.first);
    return NovaThemed(
      child: Builder(builder: (context) {
        final p = NovaThemeScope.of(context);
        return Scaffold(
          backgroundColor: p.bg,
          appBar: AppBar(
            backgroundColor: p.bg,
            surfaceTintColor: Colors.transparent,
            iconTheme: IconThemeData(color: p.textMuted),
            title: Row(children: [
              Icon(t.icon, color: p.accent, size: 20),
              const SizedBox(width: 10),
              Text(t.name, style: p.ui(size: 16, weight: FontWeight.w700)),
            ]),
          ),
          body: DevToolbox(initial: id, single: true),
        );
      }),
    );
  }
}
