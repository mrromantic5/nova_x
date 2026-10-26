// test/nova/nova_api_client_test.dart
//
// NOVA AI Worker client: request shapes, response parsing, error mapping and
// bounded retries — using a fake HTTP adapter (no network).

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nova_x/features/nova/models/nova_models.dart';
import 'package:nova_x/features/nova/services/nova_api.dart';

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.respond);

  final ResponseBody Function(RequestOptions options, int attempt) respond;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return respond(options, requests.length);
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

(NovaApiClient, _FakeAdapter) _client(ResponseBody Function(RequestOptions o, int attempt) r) {
  final adapter = _FakeAdapter(r);
  final dio = Dio(BaseOptions(baseUrl: 'https://nova.test'))..httpClientAdapter = adapter;
  // No daily-limit metering in these transport tests (see platform_39_test.dart).
  return (NovaApiClient(dio: dio, meter: (_) async {}), adapter);
}

void main() {
  group('/chat', () {
    test('sends message + history and returns the reply', () async {
      final (api, adapter) = _client((o, _) =>
          _json(200, {'success': true, 'reply': ' Hello from NOVA ', 'tokens_used': 42}));
      final reply = await api.chat('Hi', [
        {'role': 'user', 'content': 'earlier'},
      ]);
      expect(reply, 'Hello from NOVA');
      final req = adapter.requests.single;
      expect(req.path, '/chat');
      expect(req.method, 'POST');
      final data = req.data as Map;
      expect(data['message'], 'Hi');
      expect((data['history'] as List).single, {'role': 'user', 'content': 'earlier'});
    });

    test('long messages are capped at the Worker limit', () async {
      final (api, adapter) = _client((o, _) => _json(200, {'success': true, 'reply': 'ok'}));
      await api.chat('x' * 5000, const []);
      expect(((adapter.requests.single.data as Map)['message'] as String).length, 4000);
    });

    test('429 maps to a rate-limit message without retrying', () async {
      final (api, adapter) =
          _client((o, _) => _json(429, {'success': false, 'error': 'busy', 'code': 429}));
      await expectLater(
        api.chat('Hi', const []),
        throwsA(isA<NovaApiException>()
            .having((e) => e.kind, 'kind', NovaApiErrorKind.rateLimited)),
      );
      expect(adapter.requests, hasLength(1));
    });

    test('413 maps to tooLarge, 400 is not retried', () async {
      final (big, _) = _client((o, _) => _json(413, {'success': false, 'code': 413}));
      await expectLater(big.chat('Hi', const []),
          throwsA(isA<NovaApiException>().having((e) => e.kind, 'kind', NovaApiErrorKind.tooLarge)));

      final (bad, adapter) = _client((o, _) => _json(400, {'success': false, 'code': 400}));
      await expectLater(bad.chat('Hi', const []), throwsA(isA<NovaApiException>()));
      expect(adapter.requests, hasLength(1));
    });

    test('503 is retried once, then succeeds', () async {
      final (api, adapter) = _client((o, attempt) => attempt == 1
          ? _json(503, {'success': false, 'code': 503})
          : _json(200, {'success': true, 'reply': 'Back online'}));
      expect(await api.chat('Hi', const []), 'Back online');
      expect(adapter.requests, hasLength(2));
    });

    test('non-JSON or success:false responses are reported, never shown raw', () async {
      final (api, _) = _client((o, _) => ResponseBody.fromString('oops', 200, headers: {
            Headers.contentTypeHeader: ['text/plain'],
          }));
      await expectLater(api.chat('Hi', const []),
          throwsA(isA<NovaApiException>().having((e) => e.kind, 'kind', NovaApiErrorKind.malformed)));

      final (api2, _) = _client((o, _) => _json(200, {'success': false, 'code': 502}));
      await expectLater(api2.chat('Hi', const []), throwsA(isA<NovaApiException>()));
    });
  });

  group('/plan', () {
    test('404 means the Worker has no planner: null, and not asked again', () async {
      final (api, adapter) = _client((o, _) => _json(404, {'success': false, 'code': 404}));
      expect(await api.plan('open youtube', const []), isNull);
      expect(await api.plan('open youtube', const []), isNull);
      expect(adapter.requests, hasLength(1));
    });

    test('valid plans are parsed and validated', () async {
      final (api, _) = _client((o, _) => _json(200, {
            'success': true,
            'type': 'actions',
            'actions': [
              {'name': 'open_app', 'args': {'app': 'YouTube'}},
            ],
            'tokens_used': 120,
          }));
      final r = await api.plan('put youtube on', const []);
      expect(r, isNotNull);
      expect(r!.tokensUsed, 120);
      final plan = r.plan as NovaActionsPlan;
      expect(plan.actions.single.type, NovaActionType.openApp);
    });
  });

  group('/transcribe', () {
    test('uploads the clip as audio/mp4 in the "audio" field', () async {
      final dir = await Directory.systemTemp.createTemp('nova_test');
      final clip = File('${dir.path}/clip.m4a')..writeAsBytesSync(List<int>.filled(64, 7));
      final (api, adapter) =
          _client((o, _) => _json(200, {'success': true, 'transcript': ' Open YouTube '}));

      expect(await api.transcribe(clip.path), 'Open YouTube');

      final req = adapter.requests.single;
      expect(req.path, '/transcribe');
      final form = req.data as FormData;
      expect(form.files.single.key, 'audio');
      expect(form.files.single.value.contentType.toString(), 'audio/mp4');
      expect(form.files.single.value.filename, 'nova_voice.m4a');
      await dir.delete(recursive: true);
    });

    test('missing or empty files are never uploaded', () async {
      final (api, adapter) = _client((o, _) => _json(200, {'success': true, 'transcript': 'x'}));
      await expectLater(api.transcribe('/nonexistent/nova.m4a'), throwsA(isA<NovaApiException>()));
      expect(adapter.requests, isEmpty);
    });
  });

  group('/vision', () {
    final jpeg = [0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3, 4];

    test('sends the question, history and base64 images; returns the reply', () async {
      final (api, adapter) = _client((o, _) => _json(200, {'success': true, 'reply': ' It says Accra. '}));
      final reply = await api.vision('Read the sign', [
        {'role': 'user', 'content': 'hi'},
      ], [
        NovaVisionImage(jpeg, 'image/jpeg'),
      ]);
      expect(reply, 'It says Accra.');
      final req = adapter.requests.single;
      expect(req.path, '/vision');
      final body = req.data as Map;
      expect(body['message'], 'Read the sign');
      expect(body['history'], [
        {'role': 'user', 'content': 'hi'},
      ]);
      expect(body['images'], [
        {'mime': 'image/jpeg', 'data': base64Encode(jpeg)},
      ]);
    });

    test('older server without /vision and oversized photos get clear messages', () async {
      final (old, _) = _client((o, _) => _json(404, {'success': false, 'error': 'Endpoint not found', 'code': 404}));
      await expectLater(
          old.vision('x', const [], [NovaVisionImage(jpeg, 'image/jpeg')]),
          throwsA(isA<NovaApiException>()
              .having((e) => e.statusCode, 'statusCode', 404)
              .having((e) => e.userMessage, 'userMessage', contains('3.3.0'))));

      final (big, _) = _client((o, _) => _json(413, {'success': false, 'error': 'Image too large.', 'code': 413}));
      await expectLater(
          big.vision('x', const [], [NovaVisionImage(jpeg, 'image/jpeg')]),
          throwsA(isA<NovaApiException>().having((e) => e.userMessage, 'userMessage', contains('too large'))));
    });

    test('no photos: nothing is sent', () async {
      final (api, adapter) = _client((o, _) => _json(200, {'success': true, 'reply': 'x'}));
      await expectLater(api.vision('x', const [], const []), throwsA(isA<NovaApiException>()));
      expect(adapter.requests, isEmpty);
    });
  });
}
