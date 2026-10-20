// lib/features/ai/services/nova_chat_api.dart
//
// NOVA AI chat history on the NOVA X server (/api/v1/sync/ai-chats, see
// backend/api.browser/nova_ai_chats.php). Only for signed-in users.
//
// Answers that don't look like the server's JSON are treated as failures, so
// a broken or captive-portal response can never empty the saved history.

import 'package:dio/dio.dart';
import 'package:nova_x/core/services/api_service.dart';

import 'nova_chat_models.dart';

enum NovaChatSyncProblem { offline, signedOut, notSetUp, failed }

class NovaChatSyncException implements Exception {
  const NovaChatSyncException(this.problem);
  final NovaChatSyncProblem problem;

  @override
  String toString() => 'NovaChatSyncException($problem)';
}

class NovaChatApi {
  NovaChatApi({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: ApiService.baseUrl,
              connectTimeout: const Duration(seconds: 12),
              sendTimeout: const Duration(seconds: 25),
              receiveTimeout: const Duration(seconds: 25),
              headers: {'Accept': 'application/json'},
            ));

  static const String _path = '/api/v1/sync/ai-chats';
  final Dio _dio;

  static const NovaChatSyncException _failed = NovaChatSyncException(NovaChatSyncProblem.failed);

  Future<Options> _options() async {
    final token = await ApiService.getToken();
    if (token == null || token.isEmpty) {
      throw const NovaChatSyncException(NovaChatSyncProblem.signedOut);
    }
    return Options(headers: {'Authorization': 'Bearer $token', 'Content-Type': 'application/json'});
  }

  static String _chatPath(String id) => '$_path/${Uri.encodeComponent(id)}';

  /// The server's JSON object, or a failure when the answer isn't one.
  static Map _ok(Response<dynamic> res) {
    final data = res.data;
    if (data is Map && data['status'] == 'success') return data;
    throw _failed;
  }

  Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == null) throw const NovaChatSyncException(NovaChatSyncProblem.offline);
      if (status == 401) throw const NovaChatSyncException(NovaChatSyncProblem.signedOut);
      // 503 = the chat-history table couldn't be created on the server.
      if (status == 503) throw const NovaChatSyncException(NovaChatSyncProblem.notSetUp);
      throw _failed;
    }
  }

  /// The user's chats, newest first (at most [NovaChatMerge.serverListLimit]).
  Future<List<NovaRemoteChat>> list() => _guard(() async {
        try {
          final res = await _dio.get<dynamic>(_path, options: await _options());
          final raw = _ok(res)['chats'];
          if (raw is! List) throw _failed;
          final chats = <NovaRemoteChat>[];
          for (final item in raw) {
            final chat = NovaRemoteChat.fromJson(item);
            if (chat != null) chats.add(chat);
          }
          return chats;
        } on DioException catch (e) {
          // 404 = the server doesn't have the chat-history endpoint yet.
          if (e.response?.statusCode == 404) {
            throw const NovaChatSyncException(NovaChatSyncProblem.notSetUp);
          }
          rethrow;
        }
      });

  /// The messages of one chat (null if it no longer exists on the server).
  Future<List<Map<String, String>>?> messages(String id) => _guard(() async {
        try {
          final res = await _dio.get<dynamic>(_chatPath(id), options: await _options());
          final chat = _ok(res)['chat'];
          final raw = chat is Map ? chat['messages'] : null;
          if (raw is! List) throw _failed;
          var n = 0;
          final out = <Map<String, String>>[];
          for (final m in raw) {
            if (m is! Map) continue;
            final role = m['role'];
            final content = m['content'];
            if ((role != 'user' && role != 'assistant') || content is! String) continue;
            final mid = m['id'];
            out.add({
              'id': mid is String && mid.isNotEmpty ? mid : 'r${n++}',
              'role': role as String,
              'content': content,
            });
          }
          return out;
        } on DioException catch (e) {
          if (e.response?.statusCode == 404) return null;
          rethrow;
        }
      });

  /// Creates or updates a chat. Returns the version time the server keeps:
  /// [updatedAt], or a newer one when another phone saved a newer version.
  Future<int> upload(String id, String title, int updatedAt, List<Map<String, String>> messages) =>
      _guard(() async {
        final res = await _dio.post<dynamic>(
          _path,
          data: {
            'id': id,
            'title': title,
            'updated_at': updatedAt,
            'messages': [
              for (final m in messages)
                {'id': m['id'] ?? '', 'role': m['role'] ?? '', 'content': m['content'] ?? ''},
            ],
          },
          options: await _options(),
        );
        final chat = _ok(res)['chat'];
        final at = chat is Map ? chat['updated_at'] : null;
        if (at is! num) throw _failed; // not confirmed: stays unsynced, retried later
        return at.toInt();
      });

  /// Renames a chat. False when the chat is not on the server.
  Future<bool> rename(String id, String title, int updatedAt) => _guard(() async {
        try {
          final res = await _dio.post<dynamic>(
            '${_chatPath(id)}/rename',
            data: {'title': title, 'updated_at': updatedAt},
            options: await _options(),
          );
          _ok(res);
          return true;
        } on DioException catch (e) {
          if (e.response?.statusCode == 404) return false;
          rethrow;
        }
      });

  Future<void> delete(String id) => _guard(() async {
        try {
          _ok(await _dio.delete<dynamic>(_chatPath(id), options: await _options()));
        } on DioException catch (e) {
          final status = e.response?.statusCode;
          if (status == 404) return; // already gone
          // Some hosts block DELETE: use the POST form instead.
          if (status == 405 || status == 403) {
            _ok(await _dio.post<dynamic>('${_chatPath(id)}/delete', options: await _options()));
            return;
          }
          rethrow;
        }
      });

  void dispose() => _dio.close(force: true);
}
