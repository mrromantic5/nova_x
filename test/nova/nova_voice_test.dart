// test/nova/nova_voice_test.dart
//
// NOVA Voice (Edge TTS Worker): the text that is spoken, how long replies are
// split, the voice list, what is sent to the voice service and the phone-voice
// fallback when the service can't be reached (e.g. offline).

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nova_x/features/nova/nova_config.dart';
import 'package:nova_x/features/nova/services/nova_native.dart';
import 'package:nova_x/features/nova/services/nova_voice.dart';

/// The phone's own text-to-speech (only what NovaCloudVoice uses).
class _PhoneVoice implements NovaNativeApi {
  final StreamController<NovaNativeEvent> _events = StreamController<NovaNativeEvent>.broadcast();
  final List<String> spoken = [];

  @override
  Stream<NovaNativeEvent> get events => _events.stream;

  @override
  Future<bool> speak(String text, String utteranceId) async {
    spoken.add(text);
    return true;
  }

  @override
  Future<void> stopSpeaking() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// No internet: every request fails before reaching the service.
class _OfflineAdapter implements HttpClientAdapter {
  int calls = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls++;
    throw DioException(
      requestOptions: options,
      type: DioExceptionType.connectionError,
      error: const SocketException('offline'),
    );
  }

  @override
  void close({bool force = false}) {}
}

/// The service answers, but not with audio.
class _NotAudioAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString('{"error":"busy"}', 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('text for speech', () {
    test('markdown and code blocks are removed', () {
      expect(NovaCloudVoice.cleanForSpeech('**Hello** _there_ #1\n```dart\nprint(1);\n```'),
          'Hello there 1');
    });

    test('long replies are split at sentence ends: a short first part, then larger parts', () {
      final text = List.generate(60, (i) => 'Sentence number $i is here.').join(' ');
      final parts = NovaCloudVoice.parts(text);
      expect(parts.length, greaterThan(2));
      expect(parts.first.length, lessThanOrEqualTo(NovaCloudVoice.firstPartChars));
      for (final p in parts.skip(1)) {
        expect(p.length, lessThanOrEqualTo(NovaCloudVoice.partChars));
      }
      for (final p in parts) {
        expect(p, endsWith('.'));
      }
      expect(parts.join(' '), text); // nothing lost or repeated
    });

    test('text beyond the service limit is dropped; empty text has no parts', () {
      final parts = NovaCloudVoice.parts('a ' * 5000);
      expect(parts.join(' ').length, lessThanOrEqualTo(NovaCloudVoice.maxChars));
      expect(NovaCloudVoice.parts('   '), isEmpty);
    });
  });

  group('voice list', () {
    test('every voice has a unique name, a known region and a gender', () {
      final keys = NovaVoiceCatalog.voices.map((v) => v.key).toList();
      expect(keys.toSet().length, keys.length);
      for (final v in NovaVoiceCatalog.voices) {
        expect(NovaVoiceCatalog.regions, contains(v.region), reason: v.key);
        expect(const ['female', 'male'], contains(v.gender), reason: v.key);
        expect(v.key, matches(RegExp(r'^[a-z]+$')), reason: v.key);
      }
    });

    test('the standard voices and the default are offered', () {
      for (final key in NovaVoiceCatalog.original) {
        expect(NovaVoiceCatalog.isKnown(key), isTrue, reason: key);
      }
      expect(NovaVoiceCatalog.defaultVoice, 'libby');
      expect(NovaVoiceCatalog.byKey('libby')?.description, 'Female · United Kingdom');
      expect(NovaVoiceCatalog.byKey('ezinne')?.label, 'Ezinne');
      expect(NovaVoiceCatalog.isKnown('robot'), isFalse);
    });

    final worker = File('backend/nova-voice-worker/nova-voice-worker.js');
    test('matches the voices of the NOVA Voice Worker', () {
      final source = worker.readAsStringSync();
      final block = RegExp(r'const VOICES = \{([\s\S]*?)\n\};').firstMatch(source);
      expect(block, isNotNull);
      final workerKeys = RegExp(r'^\s{2}([a-z]+):\s*\{', multiLine: true)
          .allMatches(block!.group(1)!)
          .map((m) => m.group(1)!)
          .toSet();
      expect(workerKeys, NovaVoiceCatalog.voices.map((v) => v.key).toSet());
    }, skip: worker.existsSync() ? false : 'the Worker source is not in this checkout');
  });

  group('speaking', () {
    test('asks the NOVA Voice service for MP3 audio in the chosen voice', () async {
      final native = _PhoneVoice();
      final adapter = _NotAudioAdapter();
      final voice = NovaCloudVoice(
        native: native,
        dio: Dio()..httpClientAdapter = adapter,
        voiceName: () => 'ezinne',
      );
      await voice.speak('Hello there.', 'u1');
      final request = adapter.requests.single;
      expect(request.method, 'POST');
      expect(request.uri.toString(), '${NovaConfig.voiceApiBaseUrl}/');
      expect(request.data, {'q': 'Hello there.', 'voicename': 'ezinne', 'format': 'mp3'});
      // Not audio → the phone's own voice speaks instead.
      expect(native.spoken, ['Hello there.']);
      voice.dispose();
    });

    test('offline: the phone voice speaks instead', () async {
      final native = _PhoneVoice();
      final adapter = _OfflineAdapter();
      final voice = NovaCloudVoice(native: native, dio: Dio()..httpClientAdapter = adapter);
      expect(await voice.speak('Hello there. How are you?', 'u2'), isTrue);
      expect(adapter.calls, 1);
      expect(native.spoken, ['Hello there. How are you?']);
      voice.dispose();
    });

    test('voice preview (no phone fallback) reports that nothing was played', () async {
      final native = _PhoneVoice();
      final voice = NovaCloudVoice(
        native: native,
        dio: Dio()..httpClientAdapter = _OfflineAdapter(),
        fallbackToPhone: false,
      );
      expect(await voice.speak('Hi', 'p1'), isFalse);
      expect(native.spoken, isEmpty);
      voice.dispose();
    });
  });
}
