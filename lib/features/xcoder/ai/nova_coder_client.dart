// lib/features/xcoder/ai/nova_coder_client.dart
//
// Client for NOVA Coder (backend/nova-coder-worker), the AI engine of
// X Coder. The Worker holds the AI key; the app sends the user's NOVA X
// token and (3.11.4) a short-lived Premium pass signed by the NOVA X server
// (subscription.php?action=coder_pass). The Worker checks the pass itself,
// so it doesn't need to reach the NOVA X server — whose hosting firewall
// answers Cloudflare with HTTP 403.
//
//   POST /v1/chat      streamed (SSE) or plain answers, with project context
//   POST /v1/agent     multi-file plans (need_files → plan / question)
//   POST /v1/complete  fast inline completion
//   GET  /v1/usage     today's usage
//
// Everything NOVA Coder returns is data: code is only ever put into the
// editor after the developer reviews it, and commands only run when tapped.

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../core/services/api_service.dart';
import '../../nova/nova_config.dart';

class CoderException implements Exception {
  const CoderException(this.code, this.message, {this.status});

  /// auth | premium | quota | busy | upstream | network | timeout | not_deployed | bad_request | too_large | cancelled | error
  final String code;
  final String message;
  final int? status;

  bool get needsPremium => code == 'premium';
  bool get needsSignIn => code == 'auth';

  @override
  String toString() => 'CoderException($code, $status)';
}

/// One event of a streamed answer.
class CoderDelta {
  const CoderDelta.text(this.text)
      : done = false,
        model = null,
        completionTokens = null;
  const CoderDelta.done({this.model, this.completionTokens})
      : text = '',
        done = true;
  final String text;
  final bool done;
  final String? model;
  final int? completionTokens;
}

class AgentEdit {
  AgentEdit({required this.path, required this.action, this.content, this.patches = const []});
  final String path;
  final String action; // create | replace | patch | delete
  final String? content;
  final List<({String search, String replace})> patches;

  static AgentEdit? fromJson(Object? j) {
    if (j is! Map) return null;
    final path = j['path'];
    final action = j['action'];
    if (path is! String || action is! String) return null;
    if (!const {'create', 'replace', 'patch', 'delete'}.contains(action)) return null;
    final patches = <({String search, String replace})>[];
    if (j['patches'] is List) {
      for (final p in j['patches'] as List) {
        if (p is Map && p['search'] is String && p['replace'] is String) {
          patches.add((search: p['search'] as String, replace: p['replace'] as String));
        }
      }
    }
    return AgentEdit(path: path, action: action, content: j['content'] is String ? j['content'] as String : null, patches: patches);
  }
}

class AgentCommand {
  const AgentCommand(this.command, this.why, this.phone);
  final String command;
  final String why;
  final bool phone;
}

class AgentResult {
  AgentResult({
    required this.type,
    this.files = const [],
    this.why = '',
    this.question = '',
    this.summary = '',
    this.steps = const [],
    this.edits = const [],
    this.commands = const [],
    this.notes = const [],
  });

  final String type; // need_files | plan | question
  final List<String> files;
  final String why;
  final String question;
  final String summary;
  final List<String> steps;
  final List<AgentEdit> edits;
  final List<AgentCommand> commands;
  final List<String> notes;

  static AgentResult parse(Map<String, dynamic> m) {
    List<String> strings(Object? v) => v is List ? v.whereType<String>().toList() : const [];
    return AgentResult(
      type: '${m['type']}',
      files: strings(m['files']),
      why: m['why'] is String ? m['why'] as String : '',
      question: m['question'] is String ? m['question'] as String : '',
      summary: m['summary'] is String ? m['summary'] as String : '',
      steps: strings(m['steps']),
      edits: m['edits'] is List ? (m['edits'] as List).map(AgentEdit.fromJson).whereType<AgentEdit>().toList() : const [],
      commands: m['commands'] is List
          ? [
              for (final c in m['commands'] as List)
                if (c is Map && c['command'] is String)
                  AgentCommand(c['command'] as String, c['why'] is String ? c['why'] as String : '', c['phone'] == true),
            ]
          : const [],
      notes: strings(m['notes']),
    );
  }
}

/// Applies search/replace patches. Each search must match exactly once.
/// Returns (new text, null) or (null, reason).
(String?, String?) applyPatches(String text, List<({String search, String replace})> patches) {
  var out = text;
  for (var i = 0; i < patches.length; i++) {
    final p = patches[i];
    var at = out.indexOf(p.search);
    var search = p.search;
    if (at < 0) {
      // tolerate Windows line endings in the file
      final crlf = p.search.replaceAll('\n', '\r\n');
      at = out.indexOf(crlf);
      if (at >= 0) search = crlf;
    }
    if (at < 0) return (null, 'change ${i + 1}: the text to replace was not found');
    if (out.indexOf(search, at + 1) >= 0) return (null, 'change ${i + 1}: the text to replace appears more than once');
    out = out.replaceRange(at, at + search.length, p.replace);
  }
  return (out, null);
}

/// Parses an SSE byte stream from NOVA Coder into deltas.
Stream<CoderDelta> parseCoderSse(Stream<List<int>> bytes) async* {
  var buf = '';
  // bind(), not bytes.transform(): on a phone Dio's stream is really a
  // Stream<Uint8List>, and Stream<Uint8List>.transform(Utf8Decoder) fails at
  // run time with a type error (that was the "NOVA couldn't answer" on Android).
  await for (final chunk in const Utf8Decoder(allowMalformed: true).bind(bytes)) {
    buf += chunk.replaceAll('\r\n', '\n');
    int i;
    while ((i = buf.indexOf('\n\n')) >= 0) {
      final block = buf.substring(0, i);
      buf = buf.substring(i + 2);
      for (final line in block.split('\n')) {
        if (!line.startsWith('data:')) continue;
        Object? j;
        try {
          j = jsonDecode(line.substring(5).trim());
        } catch (_) {
          continue;
        }
        if (j is! Map) continue;
        switch (j['t']) {
          case 'delta':
            if (j['v'] is String) yield CoderDelta.text(j['v'] as String);
          case 'done':
            final u = j['usage'];
            yield CoderDelta.done(
              model: j['model']?.toString(),
              completionTokens: u is Map && u['completion'] is num ? (u['completion'] as num).toInt() : null,
            );
            return;
          case 'error':
            throw CoderException('upstream', '${j['error'] ?? 'The answer was interrupted.'}');
        }
      }
    }
  }
}

class NovaCoderClient {
  NovaCoderClient({Dio? dio, String? baseUrl, Future<String?> Function()? token, Dio? passDio})
      : _token = token ?? ApiService.getToken,
        _passDio = passDio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 12),
              receiveTimeout: const Duration(seconds: 20),
              headers: {'Accept': 'application/json'},
              validateStatus: (_) => true,
            )),
        _dio = dio ??
            Dio(BaseOptions(
              baseUrl: baseUrl ?? NovaConfig.coderApiBaseUrl,
              connectTimeout: const Duration(seconds: 12),
              receiveTimeout: const Duration(seconds: 150),
              sendTimeout: const Duration(seconds: 60),
              headers: {'Accept': 'application/json'},
            ));

  final Dio _dio;
  final Dio _passDio;
  final Future<String?> Function() _token;

  // ── Premium pass (3.11.4) ───────────────────────────────────────────────
  // Shared by every client in the app; renewed 5 minutes before it expires
  // or when the Worker says it is no longer valid.
  static String? _pass, _passToken;
  static DateTime? _passUntil;
  static Future<String?>? _passing;

  Future<String?> _passFor(String token, {bool refresh = false}) {
    final until = _passUntil;
    if (!refresh && _pass != null && _passToken == token && until != null &&
        until.isAfter(DateTime.now().add(const Duration(minutes: 5)))) {
      return Future.value(_pass);
    }
    return _passing ??= _fetchPass(token).whenComplete(() => _passing = null);
  }

  /// Asks the NOVA X server for a pass. Null when the server doesn't offer
  /// passes yet or can't be reached: the Worker then checks the account
  /// itself, as before.
  Future<String?> _fetchPass(String token) async {
    _pass = null;
    _passUntil = null;
    try {
      final r = await _passDio.get<Object>(
        '${ApiService.baseUrl}/subscription.php',
        queryParameters: {'action': 'coder_pass'},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      var d = r.data;
      if (d is String) d = jsonDecode(d);
      if (r.statusCode != 200 || d is! Map || d['success'] != true) return null;
      final p = d['pass'];
      if (p is! String || p.isEmpty) return null;
      _pass = p;
      _passToken = token;
      _passUntil = DateTime.tryParse('${d['expires_at']}') ?? DateTime.now().add(const Duration(minutes: 30));
      return p;
    } catch (_) {
      return null;
    }
  }

  Future<Options> _opts({ResponseType type = ResponseType.json, bool refreshPass = false}) async {
    final t = await _token();
    if (t == null || t.isEmpty) {
      throw const CoderException('auth', 'Sign in to NOVA X to use NOVA Coder.');
    }
    final pass = await _passFor(t, refresh: refreshPass);
    return Options(headers: {
      'Authorization': 'Bearer $t',
      'Content-Type': 'application/json',
      if (pass != null) 'X-Nova-Pass': pass,
    }, responseType: type);
  }

  /// Streamed chat / task answer.
  Stream<CoderDelta> chatStream({
    required List<Map<String, String>> messages,
    String task = 'chat',
    Map<String, Object?>? context,
    String profile = 'pro',
    CancelToken? cancel,
  }) async* {
    final res = await _openStream(
        {'messages': messages, 'task': task, 'context': context, 'profile': profile, 'stream': true}, cancel);
    final body = res.data;
    if (body == null) throw const CoderException('upstream', 'NOVA Coder sent an empty answer.');
    try {
      yield* parseCoderSse(body.stream);
    } on DioException catch (e) {
      // the connection dropped while the answer was arriving
      throw await _map(e);
    }
  }

  Future<Response<ResponseBody>> _openStream(Map<String, Object?> data, CancelToken? cancel, {bool retried = false}) async {
    try {
      return await _dio.post<ResponseBody>(
        '/v1/chat',
        data: data,
        options: await _opts(type: ResponseType.stream, refreshPass: retried),
        cancelToken: cancel,
      );
    } on DioException catch (e) {
      final err = await _map(e);
      if (err.code == 'pass' && !retried) return _openStream(data, cancel, retried: true); // renew once
      throw err;
    }
  }

  /// Plain (non-streamed) answer: (reply, model).
  Future<(String, String?)> chat({
    required List<Map<String, String>> messages,
    String task = 'chat',
    Map<String, Object?>? context,
    String profile = 'pro',
    CancelToken? cancel,
  }) async {
    final m = await _post('/v1/chat', {'messages': messages, 'task': task, 'context': context, 'profile': profile}, cancel);
    final reply = m['reply'];
    if (reply is! String || reply.trim().isEmpty) throw const CoderException('upstream', 'NOVA Coder sent an empty answer.');
    return (reply, m['model']?.toString());
  }

  Future<AgentResult> agent({
    required String instruction,
    required Map<String, Object?> context,
    List<Map<String, String>> history = const [],
    int round = 1,
    CancelToken? cancel,
  }) async {
    final m = await _post('/v1/agent', {'instruction': instruction, 'context': context, 'history': history, 'round': round}, cancel);
    return AgentResult.parse(m);
  }

  Future<String> complete({required String path, required String language, required String prefix, required String suffix, CancelToken? cancel}) async {
    final m = await _post('/v1/complete', {'path': path, 'language': language, 'prefix': prefix, 'suffix': suffix}, cancel);
    return m['completion'] is String ? m['completion'] as String : '';
  }

  /// (used, limit) or null.
  Future<(int, int)?> usage() async {
    try {
      final r = await _dio.get<Object>('/v1/usage', options: await _opts());
      final m = r.data is Map ? r.data as Map : const {};
      if (m['used'] is num && m['limit'] is num) return ((m['used'] as num).toInt(), (m['limit'] as num).toInt());
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>> _post(String path, Map<String, Object?> body, CancelToken? cancel, {bool retried = false}) async {
    try {
      final r = await _dio.post<Object>(path, data: body, options: await _opts(refreshPass: retried), cancelToken: cancel);
      var d = r.data;
      if (d is String) d = jsonDecode(d);
      if (d is! Map) throw const CoderException('upstream', 'NOVA Coder sent an unexpected answer.');
      final m = Map<String, dynamic>.from(d);
      if (m['success'] == false) throw CoderException('${m['code'] ?? 'error'}', '${m['error'] ?? 'Something went wrong.'}');
      return m;
    } on DioException catch (e) {
      final err = await _map(e);
      if (err.code == 'pass' && !retried) return _post(path, body, cancel, retried: true);
      throw err;
    } on FormatException {
      throw const CoderException('upstream', 'NOVA Coder sent an unexpected answer.');
    }
  }

  static Future<CoderException> _map(DioException e) async {
    switch (e.type) {
      case DioExceptionType.cancel:
        return const CoderException('cancelled', 'Stopped.');
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return const CoderException('timeout', 'NOVA Coder is taking too long. Please try again.');
      case DioExceptionType.connectionError:
        return const CoderException('network', 'You’re offline or NOVA Coder can’t be reached.');
      default:
        break;
    }
    final status = e.response?.statusCode ?? 0;
    Object? data = e.response?.data;
    if (data is ResponseBody) {
      try {
        data = jsonDecode(await utf8.decoder.bind(data.stream).join());
      } catch (_) {
        data = null;
      }
    } else if (data is String) {
      try {
        data = jsonDecode(data);
      } catch (_) {}
    }
    if (data is Map && data['error'] is String) {
      return CoderException('${data['code'] ?? 'error'}', data['error'] as String, status: status);
    }
    return switch (status) {
      401 => const CoderException('auth', 'Sign in to NOVA X to use NOVA Coder.', status: 401),
      402 => const CoderException('premium', 'NOVA Coder is part of NOVA X Premium.', status: 402),
      404 => const CoderException('not_deployed', 'NOVA Coder isn’t available yet.', status: 404),
      429 => const CoderException('busy', 'NOVA Coder is busy. Try again in a few seconds.', status: 429),
      _ => CoderException('upstream', 'NOVA Coder couldn’t answer. Please try again.', status: status),
    };
  }

  void dispose() {
    _dio.close(force: true);
    _passDio.close(force: true);
  }
}
