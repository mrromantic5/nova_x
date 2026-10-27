// test/nova_capture/capture_controller_test.dart
//
// The Dart side against a scripted native module: it must report what the
// native side says (never invent success), send the right arguments, and the
// NOVA assistant must speak only the verified outcome.

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nova_x/features/nova/models/nova_models.dart';
import 'package:nova_x/features/nova/services/nova_executor.dart';
import 'package:nova_x/features/nova/services/nova_native.dart';
import 'package:nova_x/features/nova/services/nova_validator.dart';
import 'package:nova_x/features/nova_capture/controllers/capture_controller.dart';
import 'package:nova_x/features/nova_capture/controllers/capture_voice_action_handler.dart';
import 'package:nova_x/features/nova_capture/controllers/capture_voice_commands.dart';
import 'package:nova_x/features/nova_capture/models/capture_models.dart';
import 'package:nova_x/features/nova_capture/models/capture_settings.dart';
import 'package:nova_x/features/nova_capture/services/capture_platform.dart';
import 'package:nova_x/features/nova_capture/services/media_library_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _channelName = 'test/nova_capture';

class FakeHost implements NovaHost {
  final opened = <String>[];
  bool _closed = false;

  @override
  bool get isOverlay => false;

  @override
  bool get isClosed => _closed;

  @override
  Future<bool> openInBrowser(String url) async => true;

  @override
  Future<bool> openFeature(String featureId) async {
    opened.add(featureId);
    return true;
  }

  @override
  void close() => _closed = true;
}

/// Scripted native side: records calls, answers from [answers].
class FakeNative {
  final calls = <MethodCall>[];
  final answers = <String, Object? Function(MethodCall)>{};
  Map<String, Object?> state = {'state': 'idle', 'sessionId': 0};

  Future<Object?> handle(MethodCall call) async {
    calls.add(call);
    final a = answers[call.method];
    if (a != null) return a(call);
    return switch (call.method) {
      'getState' => state,
      'capabilities' => {'sdk': 34, 'deviceAudio': true, 'micGranted': true, 'notificationsGranted': true},
      'listMedia' => {'success': true, 'items': <Object?>[]},
      _ => {'success': false, 'errorCode': 'ERROR'},
    };
  }

  /// Native → Dart push (capture.state / capture.event).
  Future<void> push(String method, Map<String, Object?> args) async {
    final data = const StandardMethodCodec().encodeMethodCall(MethodCall(method, args));
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(_channelName, data, (_) {});
  }

  List<String> get methods => calls.map((c) => c.method).toList();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeNative native;
  late CaptureController c;
  late CaptureVoiceActionHandler handler;

  NovaAction action(String command, [Map<String, String> args = const {}]) =>
      NovaActionValidator.build(NovaActionType.capture, {'command': command, ...args})!;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    native = FakeNative();
    const channel = MethodChannel(_channelName);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, native.handle);
    final platform = CapturePlatform(channel: channel);
    c = CaptureController(platform: platform, library: MediaLibraryService(platform: platform));
    handler = CaptureVoiceActionHandler(c);
    CaptureCommandRegistry.lastFailed = null;
    await c.init();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel(_channelName), null);
  });

  test('state pushed by the native side is mirrored', () async {
    await native.push('capture.state', {'state': 'recording', 'sessionId': 4, 'elapsedMs': 5000, 'audio': 'mic'});
    expect(c.state, RecordingState.recording);
    expect(c.snapshot.sessionId, 4);
    expect(c.shouldSilenceAssistant, isTrue, reason: 'NOVA must not speak into a recording with sound');
    await native.push('capture.state', {'state': 'recording', 'sessionId': 4, 'audio': 'none'});
    expect(c.shouldSilenceAssistant, isFalse);
  });

  test('start sends the validated settings and reports the native result', () async {
    native.answers['startRecording'] = (_) => {'success': true, 'state': 'recording', 'sessionId': 9};
    await c.updateSettings(const RecordingSettings(resolution: '720', fps: 24, audio: CaptureAudioMode.mic));
    final r = await c.startRecording();
    expect(r.success, isTrue);
    final call = native.calls.firstWhere((m) => m.method == 'startRecording');
    final config = (call.arguments as Map)['config'] as Map;
    expect(config['resolution'], '720');
    expect(config['fps'], 24);
    expect(config['audio'], 'mic');
  });

  test('declined consent is reported as declined, not as started', () async {
    native.answers['startRecording'] = (_) => {
          'success': false,
          'errorCode': 'CONSENT_DENIED',
          'userMessage': "Screen recording didn't start because the screen-capture request was declined.",
        };
    final r = await handler.run(action('capture.recording.start'), FakeHost());
    expect(r.ok, isFalse);
    expect(r.status, NovaActionStatus.permissionRequired);
    expect(r.message, contains('declined'));
    expect(CaptureCommandRegistry.lastFailed?.intent, CaptureIntent.recordingStart, reason: '"try again" repeats it');
  });

  test('voice start succeeds only when the native side started recording', () async {
    native.answers['startRecording'] = (_) {
      native.state = {'state': 'recording', 'sessionId': 2, 'audio': 'none'};
      return {'success': true, 'state': 'recording', 'sessionId': 2};
    };
    final r = await handler.run(action('capture.recording.start', {'audio': 'none'}), FakeHost());
    expect(r.ok, isTrue);
    expect(r.message, contains('Recording your screen'));
    final config = (native.calls.firstWhere((m) => m.method == 'startRecording').arguments as Map)['config'] as Map;
    expect(config['audio'], 'none');
  });

  test('pause/resume use the current session id', () async {
    await native.push('capture.state', {'state': 'recording', 'sessionId': 12});
    native.answers['pauseRecording'] = (call) => {'success': true, 'state': 'paused'};
    final r = await handler.run(action('capture.recording.pause'), FakeHost());
    expect(r.ok, isTrue);
    expect((native.calls.last.arguments as Map)['sessionId'], 12);
  });

  test('pause when nothing is recording is not a success', () async {
    native.answers['pauseRecording'] = (_) =>
        {'success': false, 'errorCode': 'INVALID_STATE', 'userMessage': 'Nothing is being recorded right now.'};
    final r = await handler.run(action('capture.recording.pause'), FakeHost());
    expect(r.ok, isFalse);
    expect(r.message, 'Nothing is being recorded right now.');
  });

  test('stop waits for the file to be saved before saying so', () async {
    await native.push('capture.state', {'state': 'recording', 'sessionId': 5});
    native.answers['stopRecording'] = (_) {
      Timer(const Duration(milliseconds: 20), () async {
        await native.push('capture.state', {'state': 'finalizing', 'sessionId': 5});
        await native.push('capture.event', {
          'type': 'capture.recordingSaved',
          'sessionId': 5,
          'item': {'uri': 'content://media/external_primary/video/media/8', 'name': 'NOVA_Recording.mp4',
            'kind': 'recording', 'durationMs': 65000},
        });
      });
      return {'success': true, 'state': 'stopping'};
    };
    final r = await handler.run(action('capture.recording.stop'), FakeHost());
    expect(r.ok, isTrue);
    expect(r.message, contains('1:05'));
    expect(r.message, contains('Movies'));
  });

  test('a failed save is reported as failed', () async {
    await native.push('capture.state', {'state': 'recording', 'sessionId': 6});
    native.answers['stopRecording'] = (_) {
      Timer(const Duration(milliseconds: 20), () => native.push('capture.event', {
            'type': 'capture.recordingFailed',
            'sessionId': 6,
            'errorCode': 'SAVE_FAILED',
            'userMessage': "The recording couldn't be saved to your phone.",
          }));
      return {'success': true, 'state': 'stopping'};
    };
    final r = await handler.run(action('capture.recording.stop'), FakeHost());
    expect(r.ok, isFalse);
    expect(r.message, contains("couldn't be saved"));
  });

  test('cancel asks for confirmation before discarding', () async {
    await native.push('capture.state', {'state': 'recording', 'sessionId': 3});
    final first = await handler.run(action('capture.recording.cancel'), FakeHost());
    expect(first.status, NovaActionStatus.needsClarification);
    expect(native.methods, isNot(contains('cancelRecording')));
    final confirm = first.choices.firstWhere((ch) => ch.label.startsWith('Discard')).action!;
    native.answers['cancelRecording'] = (_) => {'success': true, 'state': 'cancelled'};
    final second = await handler.run(confirm, FakeHost());
    expect(second.ok, isTrue);
    expect(native.methods, contains('cancelRecording'));
  });

  test('status answers from the native state', () async {
    await native.push('capture.state', {'state': 'paused', 'sessionId': 1, 'elapsedMs': 83000});
    final r = await handler.run(action('capture.recording.status'), FakeHost());
    expect(r.message, contains('paused at 1 minute and 23 seconds'));
  });

  test('a screenshot without an open page captures the screen after consent', () async {
    native.answers['captureScreen'] = (call) => {
          'success': true,
          'item': {'uri': 'content://media/external_primary/images/media/4', 'name': 'NOVA_Screenshot.png', 'kind': 'screenshot'},
        };
    final r = await handler.run(action('capture.screenshot.auto'), FakeHost());
    expect(r.ok, isTrue);
    final args = native.calls.firstWhere((m) => m.method == 'captureScreen').arguments as Map;
    expect(args['hideApp'], isFalse, reason: 'NOVA closes itself instead');
  });

  test('a protected screen is reported honestly', () async {
    native.answers['captureScreen'] = (_) => {
          'success': false,
          'errorCode': 'PROTECTED_CONTENT',
          'userMessage': 'The app on screen blocks screenshots, so nothing was captured.',
        };
    final r = await handler.run(action('capture.screenshot.full_screen'), FakeHost());
    expect(r.ok, isFalse);
    expect(r.message, contains('blocks screenshots'));
  });

  test('library commands open the right page', () async {
    final host = FakeHost();
    await handler.run(action('capture.media.open_library', {'kind': 'recording'}), host);
    await handler.run(action('capture.settings.open'), host);
    expect(host.opened, ['capture_videos', 'capture_settings']);
  });

  test('latest capture when there is none', () async {
    final r = await handler.run(action('capture.media.preview_latest', {'kind': 'screenshot'}), FakeHost());
    expect(r.status, NovaActionStatus.notFound);
  });

  test('settings commands change the saved settings', () async {
    await handler.run(action('capture.settings.resolution', {'value': '720'}), FakeHost());
    await handler.run(action('capture.settings.orientation', {'value': 'landscape'}), FakeHost());
    expect(c.settings.resolution, '720');
    expect(c.settings.orientation, 'landscape');
  });

  test('the executor routes capture actions to NOVA Capture', () async {
    NovaCaptureActions.instance = handler;
    await native.push('capture.state', {'state': 'idle', 'sessionId': 0});
    final exec = NovaExecutor(native: _NoNative(), host: FakeHost());
    final r = await exec.execute(action('capture.recording.status'));
    expect(r.message, "Screen recording isn't active.");
    NovaCaptureActions.instance = null;
  });
}

/// The executor's device bridge is not used by capture actions.
class _NoNative implements NovaNativeApi {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('not used');
}
