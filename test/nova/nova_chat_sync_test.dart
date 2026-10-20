// test/nova/nova_chat_sync_test.dart
//
// NOVA AI chat history: the merge rules between this phone and the server,
// chat names, upload limits, and the server client (fake HTTP, no network).
// A broken or non-JSON server answer must never empty the saved history.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nova_x/features/ai/services/nova_chat_api.dart';
import 'package:nova_x/features/ai/services/nova_chat_models.dart';
import 'package:nova_x/features/ai/services/nova_chat_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

NovaChatMeta local(String id, int at, {bool synced = true, bool onServerOnly = false}) => NovaChatMeta(
      id: id,
      title: 'Chat $id',
      createdAt: 1,
      updatedAt: at,
      synced: synced,
      onServerOnly: onServerOnly,
    );

NovaRemoteChat remote(String id, int at) =>
    NovaRemoteChat(id: id, title: 'Chat $id', createdAt: 1, updatedAt: at, messageCount: 2);

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.respond);

  final ResponseBody Function(RequestOptions options) respond;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(int status, Object body) => ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

(NovaChatApi, _FakeAdapter) _api(ResponseBody Function(RequestOptions o) respond) {
  final adapter = _FakeAdapter(respond);
  final dio = Dio(BaseOptions(baseUrl: 'https://api.test'))..httpClientAdapter = adapter;
  return (NovaChatApi(dio: dio), adapter);
}

Future<NovaChatSyncProblem?> problemOf(Future<Object?> Function() run) async {
  try {
    await run();
    return null;
  } on NovaChatSyncException catch (e) {
    return e.problem;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('merge rules', () {
    test('new and newer chats come from the server; newer local chats are uploaded', () {
      final plan = NovaChatMerge.plan(
        local: [local('a', 100), local('b', 300), local('c', 200)],
        pendingDeletes: {},
        remote: [remote('a', 150), remote('b', 250), remote('c', 200), remote('d', 50)],
      );
      expect(plan.newerOnServer.map((r) => r.id), ['a']);
      expect(plan.upload, ['b']);
      expect(plan.markSynced, ['c']);
      expect(plan.addFromServer.map((r) => r.id), ['d']);
      expect(plan.removeLocally, isEmpty);
    });

    test('a chat changed here but not uploaded yet is uploaded even at the same time', () {
      final plan = NovaChatMerge.plan(
        local: [local('a', 100, synced: false)],
        pendingDeletes: {},
        remote: [remote('a', 100)],
      );
      expect(plan.upload, ['a']);
      expect(plan.markSynced, isEmpty);
    });

    test('chats deleted here are deleted on the server and never come back', () {
      final plan = NovaChatMerge.plan(
        local: [],
        pendingDeletes: {'gone', 'already-gone'},
        remote: [remote('gone', 100)],
      );
      expect(plan.deleteOnServer, ['gone']);
      expect(plan.forgetDeleted, ['already-gone']);
      expect(plan.addFromServer, isEmpty);
    });

    test('a synced chat missing from the full server list was deleted on another phone', () {
      final plan = NovaChatMerge.plan(
        local: [local('kept', 100), local('deleted', 90), local('new-here', 80, synced: false)],
        pendingDeletes: {},
        remote: [remote('kept', 100)],
      );
      expect(plan.removeLocally, ['deleted']);
      expect(plan.upload, ['new-here']); // never uploaded: not lost
    });

    test('an empty server list never wipes this phone (chats are uploaded again)', () {
      final plan = NovaChatMerge.plan(local: [local('a', 100)], pendingDeletes: {}, remote: []);
      expect(plan.removeLocally, isEmpty);
      expect(plan.upload, ['a']);
    });

    test('with a capped server list, older chats that are not listed are kept', () {
      final listed = [
        for (var i = 0; i < NovaChatMerge.serverListLimit; i++) remote('r$i', 1000 + i),
      ];
      final plan = NovaChatMerge.plan(
        local: [local('old', 10), local('recent-gone', 5000)],
        pendingDeletes: {},
        remote: listed,
      );
      expect(plan.removeLocally, ['recent-gone']);
      expect(plan.removeLocally, isNot(contains('old')));
    });
  });

  group('chat data', () {
    test('saved chat info survives a round trip; damaged entries are skipped', () {
      final meta = local('chat_1', 42, synced: false, onServerOnly: true)..messageCount = 3;
      final back = NovaChatMeta.fromJson(jsonDecode(jsonEncode(meta.toJson())));
      expect(back?.id, 'chat_1');
      expect(back?.updatedAt, 42);
      expect(back?.messageCount, 3);
      expect(back?.synced, isFalse);
      expect(back?.onServerOnly, isTrue);
      expect(NovaChatMeta.fromJson({'id': '', 'title': 'x'}), isNull);
      expect(NovaChatMeta.fromJson('nonsense'), isNull);
    });

    test('server list entries', () {
      final r = NovaRemoteChat.fromJson(
          {'id': 'chat_9', 'title': 'Trip', 'message_count': 4, 'created_at': 1, 'updated_at': 7});
      expect(r?.messageCount, 4);
      expect(r?.updatedAt, 7);
      expect(NovaRemoteChat.fromJson({'title': 'no id'}), isNull);
    });

    test('chat names and ids', () {
      expect(NovaChatRepository.titleFrom('  How do   I bake bread?  '), 'How do I bake bread?');
      expect(NovaChatRepository.titleFrom('/image a red car'), 'Image: a red car');
      expect(NovaChatRepository.titleFrom(''), 'New chat');
      expect(NovaChatRepository.titleFrom('x' * 100).length, lessThanOrEqualTo(48));
      expect(NovaChatRepository.cleanTitle('  Work\n\tnotes '), 'Work notes');
      expect(NovaChatRepository.cleanTitle('   '), 'New chat');
      expect(NovaChatRepository.cleanTitle('y' * 300).length, NovaChatRepository.maxTitleLength);
      // The server only accepts ids like this.
      expect(NovaChatRepository.newChatId(), matches(RegExp(r'^[A-Za-z0-9_-]{8,64}$')));
    });

    test('uploads keep the latest messages within the server limits', () {
      final many = [
        for (var i = 0; i < 450; i++) {'id': '$i', 'role': i.isEven ? 'user' : 'assistant', 'content': 'm$i'},
      ];
      final up = NovaChatRepository.forUpload(many);
      expect(up.length, NovaChatRepository.maxMessagesPerChat);
      expect(up.last['content'], 'm449');

      final big = [
        for (var i = 0; i < 60; i++) {'id': '$i', 'role': 'assistant', 'content': 'z' * 19000},
      ];
      final trimmed = NovaChatRepository.forUpload(big);
      expect(utf8.encode(jsonEncode(trimmed)).length,
          lessThanOrEqualTo(NovaChatRepository.maxUploadBytes));
      expect(trimmed.last['id'], '59');
    });
  });

  group('server client', () {
    setUp(() => SharedPreferences.setMockInitialValues({'nx_server_token': 'token-1'}));

    test('lists chats with the account token', () async {
      final (api, adapter) = _api((o) => _json(200, {
            'status': 'success',
            'chats': [
              {'id': 'chat_1', 'title': 'Hello', 'message_count': 2, 'created_at': 1, 'updated_at': 5},
              'junk',
            ],
          }));
      final chats = await api.list();
      expect(chats.single.title, 'Hello');
      final req = adapter.requests.single;
      expect(req.path, '/api/v1/sync/ai-chats');
      expect(req.headers['Authorization'], 'Bearer token-1');
    });

    test('problems are reported, never treated as "no chats"', () async {
      final (notSetUp, _) = _api((o) => _json(404, {'message': 'Not found'}));
      expect(await problemOf(notSetUp.list), NovaChatSyncProblem.notSetUp);

      final (html, _) = _api((o) => ResponseBody.fromString('<html>Login to Wi-Fi</html>', 200,
          headers: {Headers.contentTypeHeader: ['text/html']}));
      expect(await problemOf(html.list), NovaChatSyncProblem.failed);

      final (expired, _) = _api((o) => _json(401, {'message': 'Unauthorized'}));
      expect(await problemOf(expired.list), NovaChatSyncProblem.signedOut);

      final (offline, _) = _api((o) => throw DioException(
            requestOptions: o,
            type: DioExceptionType.connectionError,
            error: const SocketException('offline'),
          ));
      expect(await problemOf(offline.list), NovaChatSyncProblem.offline);
    });

    test('signed out: nothing is sent', () async {
      SharedPreferences.setMockInitialValues({});
      final (api, adapter) = _api((o) => _json(200, {'status': 'success', 'chats': []}));
      expect(await problemOf(api.list), NovaChatSyncProblem.signedOut);
      expect(adapter.requests, isEmpty);
    });

    test('messages: a chat deleted on the server is null', () async {
      final (api, _) = _api((o) => _json(404, {'message': 'Chat not found.'}));
      expect(await api.messages('chat_1'), isNull);

      final (ok, _) = _api((o) => _json(200, {
            'status': 'success',
            'chat': {
              'id': 'chat_1',
              'messages': [
                {'id': 'm1', 'role': 'user', 'content': 'Hi'},
                {'role': 'assistant', 'content': 'Hello!'},
                {'role': 'system', 'content': 'ignored'},
              ],
            },
          }));
      final messages = await ok.messages('chat_1');
      expect(messages?.map((m) => m['role']), ['user', 'assistant']);
      expect(messages?.last['id'], isNotEmpty);
    });

    test('upload sends the chat and returns the version the server keeps', () async {
      final (api, adapter) = _api((o) => _json(200, {
            'status': 'success',
            'stale': true,
            'chat': {'id': 'chat_1', 'updated_at': 900},
          }));
      final at = await api.upload('chat_1', 'Trip', 500, [
        {'id': 'm1', 'role': 'user', 'content': 'Plan a trip'},
      ]);
      expect(at, 900); // another phone saved a newer version
      final body = adapter.requests.single.data as Map;
      expect(body['id'], 'chat_1');
      expect(body['updated_at'], 500);
      expect((body['messages'] as List).single, {'id': 'm1', 'role': 'user', 'content': 'Plan a trip'});
    });

    test('rename reports a chat that is not on the server; delete falls back to POST', () async {
      final (missing, _) = _api((o) => _json(404, {'message': 'Chat not found.'}));
      expect(await missing.rename('chat_1', 'New name', 1), isFalse);

      final (api, adapter) = _api((o) => o.method == 'DELETE'
          ? _json(405, {'message': 'Method not allowed'})
          : _json(200, {'status': 'success', 'deleted': true}));
      await api.delete('chat_1');
      expect(adapter.requests.map((r) => '${r.method} ${r.path}'), [
        'DELETE /api/v1/sync/ai-chats/chat_1',
        'POST /api/v1/sync/ai-chats/chat_1/delete',
      ]);
    });
  });
}
