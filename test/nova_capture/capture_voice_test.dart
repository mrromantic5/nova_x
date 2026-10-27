// test/nova_capture/capture_voice_test.dart
//
// NOVA Capture voice commands, through NOVA's real command parser (the same
// path as "Hey NOVA, …"). Recognition is local and deterministic; anything
// unclear asks instead of guessing, and music/chat commands are untouched.

import 'package:flutter_test/flutter_test.dart';
import 'package:nova_x/features/nova/models/nova_models.dart';
import 'package:nova_x/features/nova/services/nova_command_parser.dart';
import 'package:nova_x/features/nova/services/nova_validator.dart';
import 'package:nova_x/features/nova_capture/controllers/capture_voice_commands.dart';

void main() {
  final parser = NovaCommandParser(clock: () => DateTime(2026, 10, 27, 14, 5));

  NovaAction? capture(String s) {
    final p = parser.parse(s);
    if (p is NovaActionsPlan && p.actions.length == 1 && p.actions.first.type == NovaActionType.capture) {
      return p.actions.first;
    }
    return null;
  }

  void expectIntent(String phrase, CaptureIntent intent, [Map<String, String> args = const {}]) {
    final a = capture(phrase);
    expect(a, isNotNull, reason: phrase);
    expect(a!.arg('command'), intent.id, reason: phrase);
    args.forEach((k, v) => expect(a.args[k], v, reason: '$phrase [$k]'));
  }

  setUp(() => CaptureCommandRegistry.lastFailed = null);

  group('screenshot commands (spec §9)', () {
    test('every listed phrase maps to the right action', () {
      expectIntent('Hey NOVA, take a screenshot.', CaptureIntent.screenshotAuto);
      expectIntent('Hey NOVA, capture this page.', CaptureIntent.screenshotWebpage);
      expectIntent('NOVA, screenshot this webpage.', CaptureIntent.screenshotWebpage);
      expectIntent('NOVA, take a full-page screenshot.', CaptureIntent.screenshotFullPage);
      expectIntent('Hey NOVA, capture my screen.', CaptureIntent.screenshotFullScreen);
      expectIntent('NOVA, take a screenshot and save it.', CaptureIntent.screenshotAuto);
      expectIntent('NOVA, open Screenshot Studio.', CaptureIntent.openStudio);
      expectIntent('NOVA, show my recent screenshots.', CaptureIntent.openLibrary, {'kind': 'screenshot'});
      expectIntent('NOVA, open my latest screenshot.', CaptureIntent.previewLatest, {'kind': 'screenshot'});
      expectIntent('NOVA, edit my last screenshot.', CaptureIntent.editLatest);
      expectIntent('NOVA, crop this screenshot.', CaptureIntent.editLatest);
      expectIntent('NOVA, share my latest screenshot.', CaptureIntent.shareLatest, {'kind': 'screenshot'});
    });

    test('natural variations', () {
      expectIntent('screenshot', CaptureIntent.screenshotAuto);
      expectIntent('grab a screenshot', CaptureIntent.screenshotAuto);
      expectIntent('screenshot the whole page', CaptureIntent.screenshotFullPage);
      expectIntent('capture the entire screen', CaptureIntent.screenshotFullScreen);
      expectIntent('take a screenshot of my screen', CaptureIntent.screenshotFullScreen);
      expectIntent('take a screenshot of this page', CaptureIntent.screenshotWebpage);
    });

    test('"take a screenshot" is no longer answered with "I can\'t"', () {
      expect(parser.parse('take a screenshot'), isA<NovaActionsPlan>());
    });
  });

  group('recording commands', () {
    test('every listed phrase maps to the right action', () {
      expectIntent('Hey NOVA, start screen recording.', CaptureIntent.recordingStart, {'audio': 'default'});
      expectIntent('NOVA, record my screen.', CaptureIntent.recordingStart, {'audio': 'default'});
      expectIntent('NOVA, start recording my screen with microphone audio.', CaptureIntent.recordingStart, {'audio': 'mic'});
      expectIntent('NOVA, record this tutorial.', CaptureIntent.recordingStart);
      expectIntent('NOVA, show me the recording controls.', CaptureIntent.recordingControls);
      expectIntent('NOVA, pause the recording.', CaptureIntent.recordingPause);
      expectIntent('NOVA, resume recording.', CaptureIntent.recordingResume);
      expectIntent('NOVA, continue recording.', CaptureIntent.recordingResume);
      expectIntent('NOVA, stop recording.', CaptureIntent.recordingStop);
      expectIntent('NOVA, stop and save the video.', CaptureIntent.recordingStop);
      expectIntent('NOVA, cancel this recording.', CaptureIntent.recordingCancel);
      expectIntent('NOVA, how long have I been recording?', CaptureIntent.recordingStatus);
      expectIntent('NOVA, is screen recording active?', CaptureIntent.recordingStatus);
      expectIntent('NOVA, open my latest recording.', CaptureIntent.previewLatest, {'kind': 'recording'});
      expectIntent('NOVA, open my recording library.', CaptureIntent.openLibrary, {'kind': 'recording'});
      expectIntent('NOVA, show my saved recordings.', CaptureIntent.openLibrary, {'kind': 'recording'});
    });

    test('audio wording', () {
      expectIntent('can you record my screen without sound', CaptureIntent.recordingStart, {'audio': 'none'});
      expectIntent('record my screen with app sound', CaptureIntent.recordingStart, {'audio': 'device'});
      expectIntent('record my screen with my voice and app audio', CaptureIntent.recordingStart, {'audio': 'mic_device'});
      expectIntent('NOVA, record without audio.', CaptureIntent.recordingStart, {'audio': 'none'});
    });

    test('natural variations', () {
      expectIntent('please start a screen recording', CaptureIntent.recordingStart);
      expectIntent('screen record', CaptureIntent.recordingStart);
      expectIntent('begin recording', CaptureIntent.recordingStart);
      expectIntent('end the recording', CaptureIntent.recordingStop);
      expectIntent('finish recording', CaptureIntent.recordingStop);
      expectIntent('stop the screen recording', CaptureIntent.recordingStop);
      expectIntent('discard the recording', CaptureIntent.recordingCancel);
      expectIntent('stop recording without saving', CaptureIntent.recordingCancel);
      expectIntent('pause recording', CaptureIntent.recordingPause);
      expectIntent('unpause the recording', CaptureIntent.recordingResume);
      expectIntent('am I still recording', CaptureIntent.recordingStatus);
      expectIntent('play my last recording', CaptureIntent.previewLatest, {'kind': 'recording'});
      expectIntent('share the last video', CaptureIntent.shareLatest, {'kind': 'recording'});
      expectIntent('show my captures', CaptureIntent.openLibrary, {'kind': 'any'});
    });
  });

  group('settings and recovery', () {
    test('settings phrases', () {
      expectIntent('NOVA, change recording quality.', CaptureIntent.openSettings);
      expectIntent('NOVA, record at 1080p if supported.', CaptureIntent.setResolution, {'value': '1080'});
      expectIntent('set recording resolution to 720', CaptureIntent.setResolution, {'value': '720'});
      expectIntent('NOVA, switch to landscape recording.', CaptureIntent.setOrientation, {'value': 'landscape'});
      expectIntent('portrait recording', CaptureIntent.setOrientation, {'value': 'portrait'});
      expectIntent('NOVA, enable microphone narration.', CaptureIntent.setAudio, {'value': 'mic'});
      expectIntent('turn off the microphone for recordings', CaptureIntent.setAudio, {'value': 'none'});
      expectIntent('NOVA, show available audio modes.', CaptureIntent.audioModes);
      expectIntent('NOVA, how much storage space is available?', CaptureIntent.storage);
      expectIntent('NOVA, open recording settings.', CaptureIntent.openSettings);
    });

    test('help and retry', () {
      expectIntent('NOVA, explain why recording did not start.', CaptureIntent.explain);
      expectIntent('NOVA, show the available capture options.', CaptureIntent.options);
      expect(capture('NOVA, try again.'), isNull, reason: 'nothing failed yet');
      CaptureCommandRegistry.lastFailed = const CaptureCommand(CaptureIntent.recordingStart);
      expectIntent('NOVA, try again.', CaptureIntent.retry);
    });

    test('"cancel that" still cancels NOVA itself', () {
      expect(parser.parse('cancel'), isA<NovaCancelPlan>());
    });
  });

  group('must not be treated as capture commands', () {
    test('music, chat and other features are unchanged', () {
      for (final phrase in [
        'pause',
        'stop',
        'resume',
        'play some music',
        'pause the music',
        'stop the music',
        'record a voice note',
        'what is a screenshot',
        'how do screenshots work on android phones in general',
        'open youtube',
        'search for screen recording apps',
      ]) {
        expect(capture(phrase), isNull, reason: phrase);
        expect(parser.parse(phrase), isNot(isA<NovaClarifyPlan>()), reason: phrase);
      }
    });

    test('loose mentions ask instead of guessing', () {
      expect(parser.parse('screen recording'), isA<NovaClarifyPlan>());
      expect(parser.parse('screenshots please'), isA<NovaClarifyPlan>());
    });
  });

  group('validation (allow-list)', () {
    test('only known intents and arguments are accepted', () {
      expect(NovaActionValidator.build(NovaActionType.capture, {'command': 'capture.recording.start'}), isNotNull);
      expect(NovaActionValidator.build(NovaActionType.capture, {'command': 'capture.shell.exec'}), isNull);
      expect(NovaActionValidator.build(NovaActionType.capture, {'command': 'capture.recording.start', 'audio': 'spy'}),
          isNull);
      expect(NovaActionValidator.build(NovaActionType.capture, {'command': 'capture.recording.pause', 'audio': 'mic'}),
          isNull, reason: 'audio only belongs to start');
      expect(NovaActionValidator.build(NovaActionType.capture, {'command': 'capture.settings.resolution'}), isNull,
          reason: 'needs a value');
      expect(NovaActionValidator.build(NovaActionType.capture, {'command': 'capture.settings.resolution', 'value': '4320'}),
          isNull);
      expect(NovaActionValidator.build(NovaActionType.capture, {'command': 'capture.recording.cancel', 'confirm': 'yes'}),
          isNotNull);
      expect(NovaActionValidator.build(NovaActionType.capture, {'command': 'capture.recording.stop', 'confirm': 'yes'}),
          isNull);
    });

    test('the AI planner can never start a capture', () {
      expect(NovaActionValidator.fromPlanner('capture', {'command': 'capture.recording.start'}), isNull);
      expect(NovaActionValidator.fromPlanner('capture', {'command': 'capture.screenshot.full_screen'}), isNull);
    });
  });
}
