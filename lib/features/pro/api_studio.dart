// lib/features/pro/api_studio.dart
//
// 3.14.0: Android port of API Studio from NOVA X for Windows (same request
// model, cURL import/export, variables, history). Phones: Request / Response
// / Saved panes; tablets: the Windows three-column layout.
//
// API Studio — test any HTTP API from the browser (no CORS limits, the
// request is made by NOVA X itself):
//  • GET/POST/PUT/PATCH/DELETE/HEAD/OPTIONS, headers, body (JSON, text,
//    form), auth (Bearer, Basic, API-key header)
//  • {{variables}} for base URLs and tokens
//  • response status, time, size, headers, pretty JSON; save body to a file
//  • copy as cURL / import from cURL, history, saved collection
// Stored on this phone only. History never keeps auth secrets.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data' show BytesBuilder, Uint8List;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../cyber/ui/cyber_palette.dart';
import 'pro_ui.dart';

enum ApiAuth { none, bearer, basic, apiKey }

enum ApiBody { none, json, text, form }

class ApiRequest {
  ApiRequest({
    String? id,
    this.name = '',
    this.method = 'GET',
    this.url = '',
    this.headers = '',
    this.body = '',
    this.bodyType = ApiBody.none,
    this.auth = ApiAuth.none,
    this.authUser = '',
    this.authSecret = '',
    this.apiKeyHeader = 'X-API-Key',
  }) : id = id ?? 'q${DateTime.now().microsecondsSinceEpoch}';

  final String id;
  String name;
  String method;
  String url;

  /// "Name: value" per line.
  String headers;
  String body;
  ApiBody bodyType;
  ApiAuth auth;
  String authUser;
  String authSecret;
  String apiKeyHeader;

  static const methods = ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'HEAD', 'OPTIONS'];

  ApiRequest copy({String? id, bool withSecrets = true}) => ApiRequest(
        id: id ?? this.id,
        name: name,
        method: method,
        url: url,
        headers: withSecrets ? headers : stripAuthHeaders(headers),
        body: body,
        bodyType: bodyType,
        auth: auth,
        authUser: authUser,
        authSecret: withSecrets ? authSecret : '',
        apiKeyHeader: apiKeyHeader,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'method': method,
        'url': url,
        'headers': headers,
        'body': body,
        'bodyType': bodyType.name,
        'auth': auth.name,
        'authUser': authUser,
        'authSecret': authSecret,
        'apiKeyHeader': apiKeyHeader,
      };

  static ApiRequest? fromJson(Object? raw) {
    if (raw is! Map) return null;
    String s(String k, [String d = '']) => raw[k] is String ? raw[k] as String : d;
    return ApiRequest(
      id: raw['id'] is String ? raw['id'] as String : null,
      name: s('name'),
      method: methods.contains(raw['method']) ? raw['method'] as String : 'GET',
      url: s('url'),
      headers: s('headers'),
      body: s('body'),
      bodyType: ApiBody.values.where((b) => b.name == raw['bodyType']).firstOrNull ?? ApiBody.none,
      auth: ApiAuth.values.where((a) => a.name == raw['auth']).firstOrNull ?? ApiAuth.none,
      authUser: s('authUser'),
      authSecret: s('authSecret'),
      apiKeyHeader: s('apiKeyHeader', 'X-API-Key'),
    );
  }

  static String stripAuthHeaders(String headers) => headers
      .split('\n')
      .where((l) => !RegExp(r'^\s*(authorization|cookie|x-api-key|api-key|x-auth-token)\s*:', caseSensitive: false).hasMatch(l))
      .join('\n');

  // ── Pure helpers (tested) ─────────────────────────────────────────────────

  /// Replaces {{name}} with variables (unknown names stay as they are).
  static String substitute(String text, Map<String, String> vars) =>
      text.replaceAllMapped(RegExp(r'\{\{\s*([\w.\-]+)\s*\}\}'), (m) => vars[m.group(1)!] ?? m.group(0)!);

  static Map<String, String> parseVars(String text) {
    final out = <String, String>{};
    for (final line in const LineSplitter().convert(text)) {
      final i = line.indexOf('=');
      if (i <= 0 || line.trimLeft().startsWith('#')) continue;
      out[line.substring(0, i).trim()] = line.substring(i + 1).trim();
    }
    return out;
  }

  static List<MapEntry<String, String>> parseHeaders(String text) {
    final out = <MapEntry<String, String>>[];
    for (final line in const LineSplitter().convert(text)) {
      final i = line.indexOf(':');
      if (i <= 0 || line.trimLeft().startsWith('#')) continue;
      out.add(MapEntry(line.substring(0, i).trim(), line.substring(i + 1).trim()));
    }
    return out;
  }

  /// Final headers (auth and content type included), variables applied.
  List<MapEntry<String, String>> resolvedHeaders(Map<String, String> vars) {
    final h = [for (final e in parseHeaders(headers)) MapEntry(e.key, substitute(e.value, vars))];
    bool has(String name) => h.any((e) => e.key.toLowerCase() == name.toLowerCase());
    switch (auth) {
      case ApiAuth.bearer:
        if (!has('authorization')) h.add(MapEntry('Authorization', 'Bearer ${substitute(authSecret, vars)}'));
      case ApiAuth.basic:
        if (!has('authorization')) {
          h.add(MapEntry('Authorization',
              'Basic ${base64.encode(utf8.encode('${substitute(authUser, vars)}:${substitute(authSecret, vars)}'))}'));
        }
      case ApiAuth.apiKey:
        if (apiKeyHeader.trim().isNotEmpty) h.add(MapEntry(apiKeyHeader.trim(), substitute(authSecret, vars)));
      case ApiAuth.none:
        break;
    }
    if (!has('content-type')) {
      switch (bodyType) {
        case ApiBody.json:
          h.add(const MapEntry('Content-Type', 'application/json'));
        case ApiBody.form:
          h.add(const MapEntry('Content-Type', 'application/x-www-form-urlencoded'));
        case ApiBody.text:
          h.add(const MapEntry('Content-Type', 'text/plain; charset=utf-8'));
        case ApiBody.none:
          break;
      }
    }
    return h;
  }

  String resolvedBody(Map<String, String> vars) {
    if (bodyType == ApiBody.none) return '';
    final b = substitute(body, vars);
    if (bodyType == ApiBody.form && !b.contains('&') && b.contains('\n')) {
      // "key=value" per line → urlencoded
      return parseVars(b).entries.map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}').join('&');
    }
    return b;
  }

  String toCurl(Map<String, String> vars) {
    String q(String s) => "'${s.replaceAll("'", r"'\''")}'";
    final b = StringBuffer('curl -X $method ${q(substitute(url, vars))}');
    for (final e in resolvedHeaders(vars)) {
      b.write(' \\\n  -H ${q('${e.key}: ${e.value}')}');
    }
    final body = resolvedBody(vars);
    if (body.isNotEmpty) b.write(' \\\n  --data-raw ${q(body)}');
    return b.toString();
  }

  /// Reads a cURL command (the common options). Null if it isn't one.
  static ApiRequest? fromCurl(String cmd) {
    final args = _shellSplit(cmd.replaceAll(RegExp(r'\\\r?\n'), ' '));
    if (args.isEmpty || args.first != 'curl') return null;
    final r = ApiRequest();
    final headers = <String>[];
    var explicitMethod = false;
    for (var i = 1; i < args.length; i++) {
      final a = args[i];
      String next() => i + 1 < args.length ? args[++i] : '';
      switch (a) {
        case '-X':
        case '--request':
          r.method = next().toUpperCase();
          explicitMethod = true;
        case '-H':
        case '--header':
          headers.add(next());
        case '-d':
        case '--data':
        case '--data-raw':
        case '--data-binary':
        case '--data-ascii':
          r.body = r.body.isEmpty ? next() : '${r.body}&${next()}';
          if (!explicitMethod) r.method = 'POST';
        case '-u':
        case '--user':
          final v = next();
          final c = v.indexOf(':');
          r.auth = ApiAuth.basic;
          r.authUser = c < 0 ? v : v.substring(0, c);
          r.authSecret = c < 0 ? '' : v.substring(c + 1);
        case '-I':
        case '--head':
          r.method = 'HEAD';
          explicitMethod = true;
        case '--url':
          r.url = next();
        case '-A':
        case '--user-agent':
          headers.add('User-Agent: ${next()}');
        case '-b':
        case '--cookie':
          headers.add('Cookie: ${next()}');
        default:
          if (!a.startsWith('-') && r.url.isEmpty) r.url = a;
      }
    }
    if (!methods.contains(r.method)) r.method = 'GET';
    final ct = headers.firstWhere((h) => h.toLowerCase().startsWith('content-type:'), orElse: () => '');
    if (r.body.isNotEmpty) {
      r.bodyType = ct.contains('json') || r.body.trimLeft().startsWith('{') || r.body.trimLeft().startsWith('[')
          ? ApiBody.json
          : (ct.contains('x-www-form-urlencoded') || (ct.isEmpty && r.body.contains('=')) ? ApiBody.form : ApiBody.text);
    }
    r.headers = headers.join('\n');
    return r.url.isEmpty ? null : r;
  }

  static List<String> _shellSplit(String s) {
    final out = <String>[];
    final cur = StringBuffer();
    String? quote;
    var has = false;
    for (var i = 0; i < s.length; i++) {
      final ch = s[i];
      if (quote != null) {
        if (ch == quote) {
          quote = null;
        } else if (ch == r'\' && quote == '"' && i + 1 < s.length) {
          cur.write(s[++i]);
        } else {
          cur.write(ch);
        }
      } else if (ch == "'" || ch == '"') {
        quote = ch;
        has = true;
      } else if (ch == ' ' || ch == '\t' || ch == '\n') {
        if (cur.isNotEmpty || has) {
          out.add(cur.toString());
          cur.clear();
          has = false;
        }
      } else if (ch == r'\' && i + 1 < s.length) {
        cur.write(s[++i]);
      } else {
        cur.write(ch);
      }
    }
    if (cur.isNotEmpty || has) out.add(cur.toString());
    return out;
  }
}

class ApiResponse {
  ApiResponse({required this.status, required this.reason, required this.ms, required this.headers, required this.bytes, this.error});
  final int status;
  final String reason;
  final int ms;
  final Map<String, String> headers;
  final Uint8List bytes;
  final String? error;

  String get text => utf8.decode(bytes, allowMalformed: true);

  String get pretty {
    final t = text;
    final ct = headers['content-type'] ?? '';
    if (ct.contains('json') || t.trimLeft().startsWith('{') || t.trimLeft().startsWith('[')) {
      try {
        return const JsonEncoder.withIndent('  ').convert(jsonDecode(t));
      } catch (_) {}
    }
    return t;
  }
}

class ApiStudioStore extends ChangeNotifier {
  ApiStudioStore._();
  static final ApiStudioStore instance = ApiStudioStore._();
  static const String _key = 'nova_pro_api_studio_v1';

  final List<ApiRequest> saved = [];
  final List<ApiRequest> history = [];
  String vars = 'baseUrl=https://jsonplaceholder.typicode.com';
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_key);
      if (raw != null) {
        final j = jsonDecode(raw);
        if (j is Map) {
          for (final r in (j['saved'] as List? ?? const [])) {
            final x = ApiRequest.fromJson(r);
            if (x != null) saved.add(x);
          }
          for (final r in (j['history'] as List? ?? const [])) {
            final x = ApiRequest.fromJson(r);
            if (x != null) history.add(x);
          }
          if (j['vars'] is String) vars = j['vars'] as String;
        }
      }
    } catch (_) {}
    notifyListeners();
  }

  Future<void> save() async {
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(
          _key,
          jsonEncode({
            'saved': [for (final r in saved) r.toJson()],
            'history': [for (final r in history.take(50)) r.toJson()],
            'vars': vars,
          }));
    } catch (_) {}
  }

  void addHistory(ApiRequest r) {
    history.insert(0, r.copy(id: 'h${DateTime.now().microsecondsSinceEpoch}', withSecrets: false));
    if (history.length > 50) history.removeRange(50, history.length);
    save();
  }

  static Future<ApiResponse> send(ApiRequest r, Map<String, String> vars, {Duration timeout = const Duration(seconds: 60)}) async {
    final sw = Stopwatch()..start();
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final uri = Uri.parse(ApiRequest.substitute(r.url.trim(), vars));
      if (!(uri.scheme == 'http' || uri.scheme == 'https') || uri.host.isEmpty) {
        return ApiResponse(status: 0, reason: '', ms: 0, headers: const {}, bytes: Uint8List(0), error: 'Enter a full http(s):// address.');
      }
      final req = await client.openUrl(r.method, uri).timeout(timeout);
      req.followRedirects = true;
      for (final e in r.resolvedHeaders(vars)) {
        req.headers.set(e.key, e.value, preserveHeaderCase: true);
      }
      final body = r.resolvedBody(vars);
      if (body.isNotEmpty && r.method != 'GET' && r.method != 'HEAD') {
        final data = utf8.encode(body);
        req.contentLength = data.length;
        req.add(data);
      }
      final res = await req.close().timeout(timeout);
      final b = BytesBuilder(copy: false);
      await for (final chunk in res.timeout(timeout)) {
        b.add(chunk);
        if (b.length > 20 * 1024 * 1024) break;
      }
      sw.stop();
      final headers = <String, String>{};
      res.headers.forEach((k, v) => headers[k.toLowerCase()] = v.join(', '));
      return ApiResponse(status: res.statusCode, reason: res.reasonPhrase, ms: sw.elapsedMilliseconds, headers: headers, bytes: b.takeBytes());
    } on TimeoutException {
      return ApiResponse(status: 0, reason: '', ms: sw.elapsedMilliseconds, headers: const {}, bytes: Uint8List(0), error: 'The request timed out.');
    } catch (e) {
      return ApiResponse(status: 0, reason: '', ms: sw.elapsedMilliseconds, headers: const {}, bytes: Uint8List(0), error: '$e');
    } finally {
      client.close(force: true);
    }
  }
}

// ── Page ─────────────────────────────────────────────────────────────────────

class ApiStudioScreen extends StatefulWidget {
  const ApiStudioScreen({super.key});

  @override
  State<ApiStudioScreen> createState() => _ApiStudioScreenState();
}

class _ApiStudioScreenState extends State<ApiStudioScreen> {
  final ApiStudioStore _s = ApiStudioStore.instance;
  ApiRequest _r = ApiRequest(url: '{{baseUrl}}/todos/1');
  final _url = TextEditingController();
  final _headers = TextEditingController();
  final _body = TextEditingController();
  final _user = TextEditingController();
  final _secret = TextEditingController();
  final _keyHeader = TextEditingController();
  final _vars = TextEditingController();
  int _reqTab = 0;
  int _resTab = 0;
  bool _sending = false;
  ApiResponse? _res;
  bool _pretty = true;
  int _pane = 0; // phones: 0 request, 1 response, 2 saved & history

  @override
  void initState() {
    super.initState();
    _s.load().then((_) {
      if (!mounted) return;
      _vars.text = _s.vars;
      setState(() {});
    });
    _fill(_r);
  }

  @override
  void dispose() {
    for (final c in [_url, _headers, _body, _user, _secret, _keyHeader, _vars]) {
      c.dispose();
    }
    super.dispose();
  }

  void _fill(ApiRequest r) {
    _r = r;
    _url.text = r.url;
    _headers.text = r.headers;
    _body.text = r.body;
    _user.text = r.authUser;
    _secret.text = r.authSecret;
    _keyHeader.text = r.apiKeyHeader;
  }

  ApiRequest _collect() => _r
    ..url = _url.text
    ..headers = _headers.text
    ..body = _body.text
    ..authUser = _user.text
    ..authSecret = _secret.text
    ..apiKeyHeader = _keyHeader.text;

  Map<String, String> get _varMap => ApiRequest.parseVars(_vars.text);

  Future<void> _send() async {
    if (_sending) return;
    final r = _collect();
    setState(() {
      _sending = true;
      _res = null;
    });
    final res = await ApiStudioStore.send(r, _varMap);
    _s.addHistory(r);
    if (mounted) {
      setState(() {
        _res = res;
        _sending = false;
        _pane = 1;
      });
    }
  }

  Future<void> _saveRequest() async {
    final r = _collect();
    final name = TextEditingController(text: r.name.isEmpty ? '${r.method} ${Uri.tryParse(r.url)?.path ?? r.url}' : r.name);
    final ok = await showProDialog<bool>(context, (ctx) {
      final p = NovaThemeScope.of(ctx);
      return AlertDialog(
        backgroundColor: p.surface,
        title: Text('Save request', style: p.title(size: 17)),
        content: SizedBox(
          width: 380,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ProField(controller: name, label: 'Name'),
            const SizedBox(height: 10),
            Text('Saved requests keep their auth values on this phone. Use {{variables}} for tokens you share.',
                style: p.ui(size: 12, color: p.textMuted)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      );
    });
    if (ok != true) return;
    r.name = name.text.trim();
    final i = _s.saved.indexWhere((x) => x.id == r.id);
    if (i >= 0) {
      _s.saved[i] = r.copy();
    } else {
      _s.saved.insert(0, r.copy());
    }
    await _s.save();
    proToast('Request saved');
  }

  Future<void> _importCurl() async {
    final c = TextEditingController();
    final text = await showProDialog<String>(context, (ctx) {
      final p = NovaThemeScope.of(ctx);
      return AlertDialog(
        backgroundColor: p.surface,
        title: Text('Import from cURL', style: p.title(size: 17)),
        content: SizedBox(width: 560, child: ProField(controller: c, hint: "curl -X POST 'https://…' -H 'Content-Type: application/json' -d '{…}'", maxLines: 8, minLines: 5, mono: true)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Import')),
        ],
      );
    });
    if (text == null) return;
    final r = ApiRequest.fromCurl(text.trim());
    if (r == null) {
      proToast('That doesn’t look like a cURL command', ok: false);
      return;
    }
    setState(() => _fill(r));
  }

  Future<void> _saveBody() async {
    final res = _res;
    if (res == null) return;
    try {
      final path = await FilePicker.platform.saveFile(dialogTitle: 'Save response', fileName: 'response.txt', bytes: res.bytes);
      if (path == null) return;
      proToast('Response saved');
    } catch (_) {
      proToast('Couldn’t save the file', ok: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ProPage(
      icon: Icons.api_rounded,
      title: 'API Studio',
      subtitle: 'Send HTTP requests, inspect responses, share as cURL',
      maxWidth: 1700,
      actions: [
        IconButton(tooltip: 'Import cURL', onPressed: _importCurl, icon: const Icon(Icons.input_rounded)),
        IconButton(tooltip: 'Save request', onPressed: _saveRequest, icon: const Icon(Icons.bookmark_add_outlined)),
      ],
      child: Builder(builder: (context) {
        final p = NovaThemeScope.of(context);
        return LayoutBuilder(builder: (context, box) {
          if (box.maxWidth > 900) {
            return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(width: 260, child: _sidebar(p)),
              VerticalDivider(width: 1, color: p.border),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _requestBar(p),
                  Expanded(
                    child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Expanded(child: _requestEditor(p)),
                      VerticalDivider(width: 1, color: p.border),
                      Expanded(child: _responseView(p)),
                    ]),
                  ),
                ]),
              ),
            ]);
          }
          // Phones
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _requestBar(p),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: SegmentedButton<int>(
                segments: [
                  const ButtonSegment(value: 0, label: Text('Request')),
                  ButtonSegment(value: 1, label: Text(_res == null ? 'Response' : 'Response · ${_res!.status == 0 ? 'error' : _res!.status}')),
                  const ButtonSegment(value: 2, label: Text('Saved')),
                ],
                selected: {_pane},
                showSelectedIcon: false,
                onSelectionChanged: (v) => setState(() => _pane = v.first),
              ),
            ),
            Expanded(
              child: switch (_pane) {
                1 => _responseView(p),
                2 => _sidebar(p),
                _ => _requestEditor(p),
              },
            ),
          ]);
        });
      }),
    );
  }

  Widget _sidebar(NovaPalette p) => ListenableBuilder(
        listenable: _s,
        builder: (context, _) {
          Widget item(ApiRequest r, {bool deletable = false}) => ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                leading: SizedBox(width: 52, child: Text(r.method, style: p.ui(size: 11, weight: FontWeight.w800, color: _methodColor(p, r.method)))),
                title: Text(r.name.isNotEmpty ? r.name : r.url, maxLines: 1, overflow: TextOverflow.ellipsis, style: p.ui(size: 12.5, color: p.text)),
                onTap: () => setState(() {
                  _fill(r.copy());
                  _res = null;
                }),
                trailing: deletable
                    ? IconButton(
                        icon: Icon(Icons.close_rounded, size: 16, color: p.textFaint),
                        onPressed: () {
                          _s.saved.remove(r);
                          _s.save();
                        },
                      )
                    : null,
              );
          return ListView(padding: const EdgeInsets.symmetric(vertical: 10), children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 6),
              child: Text('SAVED', style: p.ui(size: 11, weight: FontWeight.w800, color: p.textFaint)),
            ),
            if (_s.saved.isEmpty)
              Padding(padding: const EdgeInsets.symmetric(horizontal: 14), child: Text('Nothing saved yet.', style: p.ui(size: 12, color: p.textMuted))),
            for (final r in _s.saved) item(r, deletable: true),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 16, 6, 6),
              child: Row(children: [
                Expanded(child: Text('HISTORY', style: p.ui(size: 11, weight: FontWeight.w800, color: p.textFaint))),
                if (_s.history.isNotEmpty)
                  TextButton(
                    onPressed: () {
                      _s.history.clear();
                      _s.save();
                    },
                    child: const Text('Clear'),
                  ),
              ]),
            ),
            for (final r in _s.history.take(50)) item(r),
          ]);
        },
      );

  Color _methodColor(NovaPalette p, String m) => switch (m) {
        'GET' => p.success,
        'POST' => p.warning,
        'PUT' || 'PATCH' => p.accent,
        'DELETE' => p.danger,
        _ => p.textMuted,
      };

  Widget _requestBar(NovaPalette p) => Container(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.border))),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(color: p.surfaceAlt, borderRadius: BorderRadius.circular(10), border: Border.all(color: p.border)),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _r.method,
                dropdownColor: p.surface,
                items: [
                  for (final m in ApiRequest.methods)
                    DropdownMenuItem(value: m, child: Text(m, style: p.ui(weight: FontWeight.w800, color: _methodColor(p, m)))),
                ],
                onChanged: (v) => setState(() => _r.method = v ?? 'GET'),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: ProField(controller: _url, hint: 'https://api.example.com/items or {{baseUrl}}/items', mono: true, onSubmitted: (_) => _send())),
          const SizedBox(width: 6),
          IconButton.filled(
            tooltip: 'Send',
            onPressed: _sending ? null : _send,
            icon: _sending
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.send_rounded, size: 18),
          ),
        ]),
      );

  Widget _tabs(NovaPalette p, List<String> labels, int sel, ValueChanged<int> onSel) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
        child: Wrap(spacing: 6, children: [
          for (var i = 0; i < labels.length; i++)
            ChoiceChip(
              label: Text(labels[i]),
              selected: sel == i,
              selectedColor: p.accentSoft,
              labelStyle: p.ui(size: 12.5, weight: FontWeight.w600, color: sel == i ? p.accent : p.textMuted),
              onSelected: (_) => onSel(i),
            ),
        ]),
      );

  Widget _requestEditor(NovaPalette p) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _tabs(p, ['Headers', 'Body', 'Auth', 'Variables'], _reqTab, (i) => setState(() => _reqTab = i)),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
          child: switch (_reqTab) {
            0 => ProField(controller: _headers, hint: 'Accept: application/json\nX-Request-Id: 123', expands: true, mono: true),
            1 => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Wrap(spacing: 6, children: [
                  for (final b in ApiBody.values)
                    ChoiceChip(
                      label: Text(switch (b) { ApiBody.none => 'None', ApiBody.json => 'JSON', ApiBody.text => 'Text', ApiBody.form => 'Form' }),
                      selected: _r.bodyType == b,
                      onSelected: (_) => setState(() => _r.bodyType = b),
                    ),
                  if (_r.bodyType == ApiBody.json)
                    TextButton(
                      onPressed: () {
                        try {
                          _body.text = const JsonEncoder.withIndent('  ').convert(jsonDecode(_body.text));
                        } catch (_) {
                          proToast('The body isn’t valid JSON', ok: false);
                        }
                      },
                      child: const Text('Format JSON'),
                    ),
                ]),
                const SizedBox(height: 8),
                Expanded(
                  child: _r.bodyType == ApiBody.none
                      ? Center(child: Text('No body', style: p.ui(color: p.textMuted)))
                      : ProField(
                          controller: _body,
                          hint: _r.bodyType == ApiBody.form ? 'name=value (one per line) or a=1&b=2' : '{\n  "name": "NOVA"\n}',
                          expands: true,
                          mono: true,
                        ),
                ),
              ]),
            2 => ListView(children: [
                Wrap(spacing: 6, children: [
                  for (final a in ApiAuth.values)
                    ChoiceChip(
                      label: Text(switch (a) { ApiAuth.none => 'None', ApiAuth.bearer => 'Bearer token', ApiAuth.basic => 'Basic', ApiAuth.apiKey => 'API key header' }),
                      selected: _r.auth == a,
                      onSelected: (_) => setState(() => _r.auth = a),
                    ),
                ]),
                const SizedBox(height: 12),
                if (_r.auth == ApiAuth.basic) ...[ProField(controller: _user, label: 'Username'), const SizedBox(height: 10)],
                if (_r.auth == ApiAuth.apiKey) ...[ProField(controller: _keyHeader, label: 'Header name'), const SizedBox(height: 10)],
                if (_r.auth != ApiAuth.none)
                  ProField(controller: _secret, label: _r.auth == ApiAuth.basic ? 'Password' : 'Token / key  (or {{token}})', obscure: true),
                const SizedBox(height: 10),
                Text('Auth values are never kept in history.', style: p.ui(size: 12, color: p.textMuted)),
              ]),
            _ => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('One per line: name=value. Use them anywhere as {{name}}.', style: p.ui(size: 12, color: p.textMuted)),
                const SizedBox(height: 8),
                Expanded(
                  child: ProField(
                    controller: _vars,
                    expands: true,
                    mono: true,
                    onChanged: (v) {
                      _s.vars = v;
                      _s.save();
                    },
                  ),
                ),
              ]),
          },
        ),
      ),
    ]);
  }

  Widget _responseView(NovaPalette p) {
    final res = _res;
    if (_sending) return const Center(child: CircularProgressIndicator());
    if (res == null) {
      return const ProEmpty(icon: Icons.call_received_rounded, title: 'No response yet', text: 'Tap Send (or Go on the keyboard).');
    }
    if (res.error != null) {
      return ProEmpty(icon: Icons.error_outline_rounded, title: 'Request failed', text: res.error);
    }
    final ok = res.status >= 200 && res.status < 300;
    final size = res.bytes.length < 1024 ? '${res.bytes.length} B' : '${(res.bytes.length / 1024).toStringAsFixed(1)} KB';
    final shown = _pretty ? res.pretty : res.text;
    final clipped = shown.length > 400000 ? '${shown.substring(0, 400000)}\n\n… (shortened; save the response to see all of it)' : shown;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
        child: Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          ProChip('${res.status} ${res.reason}', color: ok ? p.success : (res.status >= 400 ? p.danger : p.warning)),
          ProChip('${res.ms} ms', color: p.textMuted),
          ProChip(size, color: p.textMuted),
          IconButton(tooltip: 'Copy body', icon: const Icon(Icons.copy_rounded, size: 17), onPressed: () => proCopy(res.text)),
          IconButton(tooltip: 'Save body to a file', icon: const Icon(Icons.save_alt_rounded, size: 17), onPressed: _saveBody),
        ]),
      ),
      _tabs(p, ['Body', 'Headers (${res.headers.length})', 'cURL'], _resTab, (i) => setState(() => _resTab = i)),
      Expanded(
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: p.surfaceAlt, borderRadius: BorderRadius.circular(10), border: Border.all(color: p.border)),
          child: switch (_resTab) {
            0 => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Text('Pretty', style: p.ui(size: 12, color: p.textMuted)),
                  Switch(value: _pretty, onChanged: (v) => setState(() => _pretty = v)),
                ]),
                Expanded(
                  child: SingleChildScrollView(
                    child: SelectableText(clipped, style: TextStyle(fontFamily: 'monospace', fontSize: 12.5, color: p.text)),
                  ),
                ),
              ]),
            1 => ListView(children: [for (final e in res.headers.entries) ProKv(e.key, e.value, mono: true)]),
            _ => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => proCopy(_collect().toCurl(_varMap), what: 'cURL copied'),
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    label: const Text('Copy'),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    child: SelectableText(_collect().toCurl(_varMap), style: TextStyle(fontFamily: 'monospace', fontSize: 12.5, color: p.text)),
                  ),
                ),
              ]),
          },
        ),
      ),
    ]);
  }
}
