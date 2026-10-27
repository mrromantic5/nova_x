// test/nova_capture/capture_logic_test.dart
//
// NOVA Capture logic that runs without a phone: the native contract
// parsing, settings, the media library (sort/filter/search), the editor's
// geometry and error-code mapping.

import 'dart:convert';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:nova_x/features/nova_capture/models/capture_models.dart';
import 'package:nova_x/features/nova_capture/models/capture_settings.dart';
import 'package:nova_x/features/nova_capture/models/media_asset.dart';
import 'package:nova_x/features/nova_capture/screens/screenshot_editor.dart';
import 'package:nova_x/features/nova_capture/services/media_library_service.dart';

MediaAsset asset(String name, {MediaKind kind = MediaKind.screenshot, int size = 1000, int created = 0, int id = 1}) =>
    MediaAsset(
      uri: 'content://media/external_primary/${kind == MediaKind.screenshot ? 'images' : 'video'}/media/$id',
      name: name,
      kind: kind,
      sizeBytes: size,
      createdMs: created,
    );

void main() {
  group('recording states', () {
    test('wire names round-trip and unknown values are idle', () {
      for (final s in RecordingState.values) {
        expect(RecordingState.fromWire(s.wire), s);
      }
      expect(RecordingState.fromWire('hacked'), RecordingState.idle);
      expect(RecordingState.fromWire(null), RecordingState.idle);
    });

    test('active / capturing / saving groups', () {
      expect(RecordingState.recording.isActive && RecordingState.recording.isCapturing, isTrue);
      expect(RecordingState.paused.isCapturing, isTrue);
      expect(RecordingState.finalizing.isSaving && RecordingState.finalizing.isActive, isTrue);
      for (final s in [RecordingState.idle, RecordingState.saved, RecordingState.cancelled, RecordingState.failed]) {
        expect(s.isActive, isFalse, reason: s.wire);
      }
    });
  });

  group('snapshot', () {
    test('parses the native map', () {
      final s = CaptureSnapshot.fromMap({
        'state': 'recording',
        'sessionId': 7,
        'elapsedMs': 61000,
        'audio': 'mic',
        'width': 1072,
        'height': 2384,
        'fps': 30,
        'warnings': ['a', 3, 'b'],
        'lastItem': {'uri': 'content://media/x/1', 'name': 'a.mp4', 'kind': 'recording', 'size': 99},
      }, nowMs: 1000);
      expect(s.state, RecordingState.recording);
      expect(s.sessionId, 7);
      expect(s.hasAudio, isTrue);
      expect(s.warnings, ['a', 'b']);
      expect(s.lastItem?.isVideo, isTrue);
    });

    test('the timer only advances while recording', () {
      final rec = CaptureSnapshot.fromMap({'state': 'recording', 'elapsedMs': 10000}, nowMs: 1000);
      expect(rec.elapsedAt(DateTime.fromMillisecondsSinceEpoch(4000)), const Duration(seconds: 13));
      final paused = CaptureSnapshot.fromMap({'state': 'paused', 'elapsedMs': 10000}, nowMs: 1000);
      expect(paused.elapsedAt(DateTime.fromMillisecondsSinceEpoch(90000)), const Duration(seconds: 10));
    });

    test('junk is harmless', () {
      final s = CaptureSnapshot.fromMap('nope');
      expect(s.state, RecordingState.idle);
      expect(s.lastItem, isNull);
    });
  });

  group('results and errors', () {
    test('failure keeps the code and gives a plain message', () {
      final r = CaptureResult.fromMap({'success': false, 'errorCode': 'CONSENT_DENIED'});
      expect(r.success, isFalse);
      expect(r.errorCode, CaptureErrorCode.consentDenied);
      expect(r.message, contains('declined'));
    });

    test('native message wins over the fallback', () {
      final r = CaptureResult.fromMap({'success': false, 'errorCode': 'LOW_STORAGE', 'userMessage': 'Free 300 MB'});
      expect(r.message, 'Free 300 MB');
    });

    test('missing permission is reported', () {
      final r = CaptureResult.fromMap({'success': false, 'errorCode': 'PERMISSION_REQUIRED', 'permission': 'mic'});
      expect(r.missingPermission, 'mic');
    });

    test('an empty answer is a failure, never a success', () {
      expect(CaptureResult.fromMap(null).success, isFalse);
      expect(CaptureResult.fromMap({}).success, isFalse);
    });

    test('every known code has a message', () {
      for (final code in [
        CaptureErrorCode.consentDenied, CaptureErrorCode.lowStorage, CaptureErrorCode.protectedContent,
        CaptureErrorCode.encoder, CaptureErrorCode.tooShort, CaptureErrorCode.locked, CaptureErrorCode.noPage,
      ]) {
        expect(CaptureErrorCode.message(code), isNot(CaptureErrorCode.message('???')), reason: code);
      }
    });
  });

  group('media assets', () {
    test('only content:// MediaStore items are accepted', () {
      expect(MediaAsset.fromMap({'uri': 'file:///sdcard/x.png', 'name': 'x.png'}), isNull);
      expect(MediaAsset.fromMap({'uri': 'content://media/external/images/media/5', 'name': 'x.png'}), isNotNull);
      expect(MediaAsset.fromMap({'name': 'x'}), isNull);
    });

    test('formatting', () {
      expect(formatDuration(const Duration(seconds: 65)), '1:05');
      expect(formatDuration(const Duration(hours: 1, minutes: 2, seconds: 3)), '1:02:03');
      expect(formatBytes(1536), '2 KB');
      expect(formatBytes(5 * 1024 * 1024), '5.0 MB');
      expect(formatCaptureDate(DateTime(2026, 10, 27, 9, 5)), '27 Oct 2026, 09:05');
    });
  });

  group('library sort, filter, search', () {
    final items = [
      asset('NOVA_Screenshot_b.png', size: 300, created: 2000, id: 1),
      asset('NOVA_Recording_a.mp4', kind: MediaKind.recording, size: 9000, created: 3000, id: 2),
      asset('Holiday.png', size: 100, created: 1000, id: 3),
    ];

    test('newest, oldest, name, size', () {
      String names(MediaSort s) =>
          MediaLibrary.apply(items, MediaLibraryQuery(sort: s)).map((a) => a.name).join(',');
      expect(names(MediaSort.newest), 'NOVA_Recording_a.mp4,NOVA_Screenshot_b.png,Holiday.png');
      expect(names(MediaSort.oldest), 'Holiday.png,NOVA_Screenshot_b.png,NOVA_Recording_a.mp4');
      expect(names(MediaSort.name), 'Holiday.png,NOVA_Recording_a.mp4,NOVA_Screenshot_b.png');
      expect(names(MediaSort.size), 'NOVA_Recording_a.mp4,NOVA_Screenshot_b.png,Holiday.png');
    });

    test('filters, favourites, folders', () {
      expect(MediaLibrary.apply(items, const MediaLibraryQuery(filter: MediaFilter.recordings)).length, 1);
      expect(MediaLibrary.apply(items, const MediaLibraryQuery(filter: MediaFilter.screenshots)).length, 2);
      final favs = {items[2].uri};
      expect(MediaLibrary.apply(items, const MediaLibraryQuery(filter: MediaFilter.favorites), favorites: favs).single.name,
          'Holiday.png');
      final cats = {items[0].uri: 'Work'};
      expect(MediaLibrary.apply(items, const MediaLibraryQuery(category: 'Work'), categories: cats).single.name,
          'NOVA_Screenshot_b.png');
    });

    test('search by name and by date', () {
      expect(MediaLibrary.apply(items, const MediaLibraryQuery(search: 'holi')).single.name, 'Holiday.png');
      final dated = [asset('a.png', created: DateTime(2026, 10, 27).millisecondsSinceEpoch)];
      expect(MediaLibrary.apply(dated, const MediaLibraryQuery(search: 'oct 2026')), hasLength(1));
      expect(MediaLibrary.apply(dated, const MediaLibraryQuery(search: '2026-10-27')), hasLength(1));
      expect(MediaLibrary.apply(dated, const MediaLibraryQuery(search: 'march')), isEmpty);
    });

    test('folder names are validated', () {
      expect(MediaLibrary.cleanCategory('  Work  stuff '), 'Work stuff');
      expect(MediaLibrary.cleanCategory(''), isNull);
      expect(MediaLibrary.cleanCategory('a/b'), isNull);
      expect(MediaLibrary.cleanCategory('x' * 25), isNull);
      expect(MediaLibrary.totalBytes(items), 9400);
    });
  });

  group('settings', () {
    test('round-trip and junk falls back to defaults', () {
      const s = RecordingSettings(resolution: '720', fps: 60, audio: CaptureAudioMode.micAndDevice, overlayEnabled: true);
      final back = RecordingSettings.fromJson(s.toJson());
      expect(back.resolution, '720');
      expect(back.fps, 60);
      expect(back.audio, CaptureAudioMode.micAndDevice);
      expect(back.overlayEnabled, isTrue);
      final junk = RecordingSettings.fromJson(jsonEncode({'resolution': '8k', 'fps': 240, 'audio': 'spy', 'countdownSec': 99}));
      expect(junk.resolution, 'auto');
      expect(junk.fps, 30);
      expect(junk.audio, CaptureAudioMode.none);
      expect(junk.countdownSec, 3);
      expect(RecordingSettings.fromJson('not json').fps, 30);
    });

    test('native config uses the documented keys', () {
      final m = const RecordingSettings().toNative();
      expect(m.keys, containsAll(['resolution', 'fps', 'bitrate', 'orientation', 'audio', 'maxDurationSec', 'countdownSec', 'overlayEnabled']));
      expect(m['audio'], 'none');
    });

    test('audio modes', () {
      expect(CaptureAudioMode.none.needsRecordPermission, isFalse);
      expect(CaptureAudioMode.device.needsRecordPermission, isTrue);
      expect(CaptureAudioMode.micAndDevice.usesMicrophone && CaptureAudioMode.micAndDevice.usesDeviceAudio, isTrue);
    });

    test('size estimate grows with quality and is bounded', () {
      final low = const RecordingSettings(bitrate: 'low', fps: 24).estimatedBytesPerMinute();
      final high = const RecordingSettings(bitrate: 'high', fps: 60).estimatedBytesPerMinute();
      expect(high, greaterThan(low));
      expect(high, lessThanOrEqualTo((24000000 + 128000) * 60 ~/ 8 + 1));
    });

    test('screenshot settings: metadata off by default', () {
      expect(const ScreenshotSettings().saveWebMetadata, isFalse);
      expect(const ScreenshotSettings().copyToClipboard, isFalse);
      expect(ScreenshotSettings.fromJson(const ScreenshotSettings(format: 'jpeg', quality: 70).toJson()).format, 'jpeg');
      expect(ScreenshotSettings.fromJson('{"format":"bmp","quality":5}').format, 'png');
    });
  });

  group('editor geometry', () {
    const g = EditorGeometry(1080, 2400);

    test('rotation round-trips for every quarter turn', () {
      for (var r = 0; r < 4; r++) {
        for (final p in const [Offset(0, 0), Offset(10, 20), Offset(1080, 2400), Offset(500, 1700)]) {
          final back = g.fromRotated(g.toRotated(p, r), r);
          expect((back - p).distance, lessThan(1e-9), reason: 'rotation $r, $p');
        }
      }
      expect(g.rotatedSize(1), const Size(2400, 1080));
      expect(g.toRotated(const Offset(0, 0), 1), const Offset(2400, 0));
    });

    test('a crop keeps its size when rotated', () {
      const crop = Rect.fromLTRB(100, 300, 700, 900);
      final next = g.rotateCrop(crop, 0);
      expect(next.width, crop.height);
      expect(next.height, crop.width);
    });

    test('aspect presets fit inside the image', () {
      final r = EditorGeometry.fitAspect(const Size(1080, 2400), 16 / 9);
      expect(r.width, 1080);
      expect((r.width / r.height - 16 / 9).abs(), lessThan(1e-9));
      expect(r.top, greaterThan(0));
    });
  });
}
