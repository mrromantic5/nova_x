// lib/features/nova_capture/controllers/capture_voice_action_handler.dart
//
// Carries out validated NOVA Capture actions for the NOVA assistant
// (voice, wake word, floating panel). Every reply describes what the native
// capture module actually reported — "Recording started" is said only after
// the native state is "recording"; a declined Android dialog is reported as
// declined. Works offline: nothing here uses the network.

import 'dart:async';

import '../../nova/models/nova_models.dart';
import '../../nova/services/nova_executor.dart';
import '../../nova/services/nova_validator.dart';
import '../models/capture_models.dart';
import '../models/capture_settings.dart';
import '../models/media_asset.dart';
import '../services/webpage_capture_service.dart';
import 'capture_controller.dart';
import 'capture_voice_commands.dart';

class CaptureVoiceActionHandler implements NovaCaptureActions {
  CaptureVoiceActionHandler(this._c);

  final CaptureController _c;

  /// Registers NOVA Capture with the NOVA assistant (main app and floating panel).
  static void install() {
    final c = CaptureController.instance;
    NovaCaptureActions.instance = CaptureVoiceActionHandler(c);
    unawaited(c.init());
  }

  @override
  bool get silenceSpeech => _c.shouldSilenceAssistant;

  NovaActionResult _r(NovaAction a, NovaActionStatus s, String m, {List<NovaChoice> choices = const []}) =>
      NovaActionResult(action: a, status: s, message: m, choices: choices);

  NovaActionResult _ok(NovaAction a, String m) => _r(a, NovaActionStatus.success, m);

  NovaActionStatus _statusFor(CaptureResult r) => switch (r.errorCode) {
        CaptureErrorCode.permission || CaptureErrorCode.consentDenied => NovaActionStatus.permissionRequired,
        CaptureErrorCode.unsupported || CaptureErrorCode.audio => NovaActionStatus.unsupported,
        CaptureErrorCode.notFound => NovaActionStatus.notFound,
        CaptureErrorCode.invalidState || CaptureErrorCode.staleSession => NovaActionStatus.invalid,
        _ => NovaActionStatus.failed,
      };

  NovaActionResult _fail(NovaAction a, CaptureResult r, CaptureCommand cmd) {
    CaptureCommandRegistry.lastFailed = cmd;
    return _r(a, _statusFor(r), r.message);
  }

  @override
  Future<NovaActionResult> run(NovaAction a, NovaHost host) async {
    final intent = CaptureIntent.fromId(a.arg('command'));
    if (intent == null) return _r(a, NovaActionStatus.invalid, "That capture request isn't supported.");
    await _c.init();
    if (!_c.capabilities.available) {
      return _r(a, NovaActionStatus.unsupported, "Screen capture isn't available on this device.");
    }
    final args = Map<String, String>.of(a.args)..remove('command');
    var cmd = CaptureCommand(intent, args);
    if (intent == CaptureIntent.retry) {
      final last = CaptureCommandRegistry.lastFailed;
      if (last == null) return _r(a, NovaActionStatus.invalid, "There's nothing to try again.");
      cmd = last;
    }
    final result = await _run(a, cmd, host);
    if (result.ok) CaptureCommandRegistry.lastFailed = null;
    return result;
  }

  Future<NovaActionResult> _run(NovaAction a, CaptureCommand cmd, NovaHost host) async {
    switch (cmd.intent) {
      case CaptureIntent.screenshotAuto:
        final visible = WebpageCaptureService.current;
        return visible != null && !host.isOverlay ? _webShot(a, cmd, visible, full: false) : _screenShot(a, cmd, host);
      case CaptureIntent.screenshotWebpage:
      case CaptureIntent.screenshotFullPage:
        final page = WebpageCaptureService.current;
        if (page == null || host.isOverlay) {
          CaptureCommandRegistry.lastFailed = null;
          return _r(a, NovaActionStatus.unsupported,
              "There's no web page open in NOVA X to capture. Say “capture my screen” to capture everything on screen.");
        }
        return _webShot(a, cmd, page, full: cmd.intent == CaptureIntent.screenshotFullPage);
      case CaptureIntent.screenshotFullScreen:
        return _screenShot(a, cmd, host);
      case CaptureIntent.recordingStart:
        return _start(a, cmd, host);
      case CaptureIntent.recordingPause:
        final paused = await _c.pause();
        if (!paused.success) return _fail(a, paused, cmd);
        return _ok(a, 'Recording paused at ${formatDuration(_c.elapsed)}. Nothing is recorded until you resume.');
      case CaptureIntent.recordingResume:
        final resumed = await _c.resume();
        if (!resumed.success) return _fail(a, resumed, cmd);
        return _ok(a, 'Recording again.');
      case CaptureIntent.recordingStop:
        return _stop(a, cmd);
      case CaptureIntent.recordingCancel:
        return _cancel(a, cmd);
      case CaptureIntent.recordingStatus:
        return _ok(a, _statusText());
      case CaptureIntent.recordingControls:
        if (!_c.isRecording && !_c.state.isActive) {
          return _r(a, NovaActionStatus.notFound,
              "Nothing is being recorded right now. Say “start screen recording” to begin.");
        }
        return _open(a, host, 'capture', 'Here are the recording controls.');
      case CaptureIntent.openLibrary:
        final id = switch (cmd.args['kind']) {
          'screenshot' => 'capture_shots',
          'recording' => 'capture_videos',
          _ => 'capture_library',
        };
        return _open(a, host, id, switch (cmd.args['kind']) {
          'screenshot' => 'Here are your screenshots.',
          'recording' => 'Here are your recordings.',
          _ => 'Here are your captures.',
        });
      case CaptureIntent.previewLatest:
      case CaptureIntent.editLatest:
      case CaptureIntent.shareLatest:
        return _latest(a, cmd, host);
      case CaptureIntent.openStudio:
        return _open(a, host, 'capture', 'Opening NOVA Capture.');
      case CaptureIntent.openSettings:
        return _open(a, host, 'capture_settings', 'Here are your recording settings.');
      case CaptureIntent.setResolution:
        return _setResolution(a, cmd);
      case CaptureIntent.setOrientation:
        final orientation = cmd.args['value']!;
        await _c.updateSettings(_c.settings.copyWith(orientation: orientation));
        return _ok(a, switch (orientation) {
          'landscape' => 'Recordings will be landscape. Turn your phone sideways for the best result.',
          'portrait' => 'Recordings will be portrait.',
          _ => 'Recordings will follow how you hold the phone when they start.',
        });
      case CaptureIntent.setAudio:
        return _setAudio(a, cmd);
      case CaptureIntent.audioModes:
        final device = _c.capabilities.deviceAudio;
        return _ok(a,
            'I can record with no audio or with your microphone${device ? ', sound from apps, or both together' : ''}. '
            '${device ? '' : 'Recording app sound needs Android 10 or newer. '}'
            'Recordings are set to: ${_c.settings.audio.label.toLowerCase()}.');
      case CaptureIntent.storage:
        final (free, _) = await _c.storageInfo();
        if (free < 0) return _r(a, NovaActionStatus.failed, "I couldn't check your storage.");
        final perMin = _c.settings.estimatedBytesPerMinute();
        final minutes = perMin > 0 ? (free - 150 * 1024 * 1024) ~/ perMin : 0;
        return _ok(a,
            'You have ${formatBytes(free)} free. That is roughly ${minutes < 0 ? 0 : minutes} minutes of recording '
            'at your current settings (an estimate).');
      case CaptureIntent.explain:
        return _ok(a, _c.explainLastProblem());
      case CaptureIntent.options:
        return _ok(a,
            'I can screenshot this web page or the whole page, capture your entire screen, record your screen '
            'with or without sound, and open, edit or share your saved captures.');
      case CaptureIntent.retry:
        return _r(a, NovaActionStatus.invalid, "There's nothing to try again.");
    }
  }

  String _statusText() {
    final s = _c.snapshot;
    return switch (s.state) {
      RecordingState.recording => "Yes, you've been recording for ${_spoken(_c.elapsed)}.",
      RecordingState.paused => 'The recording is paused at ${_spoken(_c.elapsed)}.',
      RecordingState.starting => 'The recording is about to start.',
      RecordingState.awaitingConsent => "I'm waiting for you to allow screen recording in Android's dialog.",
      RecordingState.stopping || RecordingState.finalizing => 'Your recording is being saved.',
      _ => "Screen recording isn't active.",
    };
  }

  static String _spoken(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    if (m == 0) return '$s second${s == 1 ? '' : 's'}';
    return '$m minute${m == 1 ? '' : 's'} and $s second${s == 1 ? '' : 's'}';
  }

  Future<NovaActionResult> _open(NovaAction a, NovaHost host, String feature, String message) async {
    if (await host.openFeature(feature)) return _ok(a, message);
    return _r(a, NovaActionStatus.unsupported, "I can't open that from here. Open NOVA X and choose NOVA Capture.");
  }

  // ── Screenshots ─────────────────────────────────────────────────────────

  Future<NovaActionResult> _webShot(NovaAction a, CaptureCommand cmd, WebCaptureTarget page, {required bool full}) async {
    final out = full ? await WebpageCaptureService.captureFullPage(page) : await WebpageCaptureService.captureVisible(page);
    if (!out.ok) return _fail(a, CaptureResult.failure(out.errorCode ?? CaptureErrorCode.webCapture), cmd);
    final saved = await _c.saveWebScreenshot(out.bytes!, from: page);
    if (!saved.success) return _fail(a, saved, cmd);
    final note = out.truncated ? ' The page was very long, so the bottom part was left out.' : '';
    return _ok(a, '${full ? 'Full-page screenshot' : 'Screenshot'} saved to Pictures, NOVA X.$note '
        'Say “edit my last screenshot” to mark it up.');
  }

  /// Whole screen: NOVA steps out of the way once Android's dialog is answered,
  /// so the assistant itself isn't in the picture.
  Future<NovaActionResult> _screenShot(NovaAction a, CaptureCommand cmd, NovaHost host) async {
    final sub = _closeOnConsent(host);
    final r = await _c.captureScreen(hideApp: false, delayMs: 1200);
    await sub.cancel();
    if (!r.success) return _fail(a, r, cmd);
    return _ok(a, 'Screenshot saved to Pictures, NOVA X.');
  }

  StreamSubscription<CaptureEvent> _closeOnConsent(NovaHost host) => _c.events.listen((e) {
        if (e.type == CaptureEvent.permissionGranted && e.data['permission'] == 'screen_capture' && !host.isClosed) {
          host.close();
        }
      });

  // ── Recording ───────────────────────────────────────────────────────────

  Future<NovaActionResult> _start(NovaAction a, CaptureCommand cmd, NovaHost host) async {
    if (_c.state.isActive) {
      return _r(a, NovaActionStatus.invalid,
          _c.isRecording ? 'Your screen is already being recorded (${formatDuration(_c.elapsed)}).' : _statusText());
    }
    var settings = _c.settings;
    final wanted = cmd.args['audio'];
    if (wanted != null && wanted != 'default') settings = settings.copyWith(audio: CaptureAudioMode.fromWire(wanted));
    if (settings.audio.usesDeviceAudio && !_c.capabilities.deviceAudio) {
      return _r(a, NovaActionStatus.unsupported,
          'Recording sound from apps needs Android 10 or newer. I can record with your microphone or without audio.',
          choices: _audioChoices());
    }
    if (settings.audio.needsRecordPermission && !_c.capabilities.micGranted) {
      final granted = await _c.requestPermissions(['mic']);
      if (granted['mic'] != true) {
        return _r(a, NovaActionStatus.permissionRequired,
            'To record sound, NOVA X needs the microphone. You can allow it in Settings, or record without audio.',
            choices: _audioChoices(noMic: true));
      }
    }
    final sub = _closeOnConsent(host);
    final r = await _c.startRecording(using: settings);
    await sub.cancel();
    if (!r.success) {
      if (r.missingPermission == 'mic') {
        return _r(a, NovaActionStatus.permissionRequired, r.message, choices: _audioChoices(noMic: true));
      }
      return _fail(a, r, cmd);
    }
    final audio = _c.snapshot.audio == 'none' ? 'without sound' : 'with sound';
    return _ok(a, 'Recording your screen $audio. Say “Hey NOVA, stop recording”, or use the controls on screen '
        'or in the notification.');
  }

  List<NovaChoice> _audioChoices({bool noMic = false}) => [
        const NovaChoice(label: 'Record without audio', text: 'record my screen without audio'),
        if (!noMic) const NovaChoice(label: 'Record with microphone', text: 'record my screen with microphone'),
      ];

  Future<NovaActionResult> _stop(NovaAction a, CaptureCommand cmd) async {
    final r = await _c.stop();
    if (!r.success) {
      if (r.errorCode == CaptureErrorCode.invalidState && !_c.state.isActive) {
        CaptureCommandRegistry.lastFailed = null;
        return _r(a, NovaActionStatus.notFound, "Nothing is being recorded right now.");
      }
      return _fail(a, r, cmd);
    }
    final saved = await _c.waitForSaved();
    if (!saved.success) return _fail(a, saved, cmd);
    final d = saved.item?.durationMs ?? 0;
    return _ok(a, 'Saved your ${d > 0 ? '${formatDuration(Duration(milliseconds: d))} ' : ''}recording to Movies, NOVA X. '
        'Say “open my latest recording” to watch it.');
  }

  Future<NovaActionResult> _cancel(NovaAction a, CaptureCommand cmd) async {
    if (!_c.state.isActive) return _r(a, NovaActionStatus.notFound, 'Nothing is being recorded right now.');
    if (cmd.args['confirm'] != 'yes') {
      final confirm = NovaActionValidator.build(
          NovaActionType.capture, {'command': CaptureIntent.recordingCancel.id, 'confirm': 'yes'});
      final keep = NovaActionValidator.build(NovaActionType.capture, {'command': CaptureIntent.recordingStop.id});
      return _r(a, NovaActionStatus.needsClarification,
          'Discard this recording? It will not be saved. Or I can stop and save it instead.',
          choices: [
            if (confirm != null) NovaChoice(label: 'Discard recording', subtitle: 'Not saved', action: confirm),
            if (keep != null) NovaChoice(label: 'Stop and save', action: keep),
          ]);
    }
    final r = await _c.cancel();
    if (!r.success) return _fail(a, r, cmd);
    return _ok(a, 'Recording discarded. Nothing was saved.');
  }

  // ── Settings ────────────────────────────────────────────────────────────

  Future<NovaActionResult> _setResolution(NovaAction a, CaptureCommand cmd) async {
    final v = cmd.args['value']!;
    await _c.updateSettings(_c.settings.copyWith(resolution: v));
    if (v == 'auto') return _ok(a, 'Recordings will use the best quality up to 1080p that your phone supports.');
    return _ok(a, "Recordings will be ${v}p when your phone supports it; if it can't, I'll use the closest lower quality.");
  }

  Future<NovaActionResult> _setAudio(NovaAction a, CaptureCommand cmd) async {
    final mode = CaptureAudioMode.fromWire(cmd.args['value']);
    if (mode.usesDeviceAudio && !_c.capabilities.deviceAudio) {
      return _r(a, NovaActionStatus.unsupported, 'Recording sound from apps needs Android 10 or newer.');
    }
    if (mode.needsRecordPermission && !_c.capabilities.micGranted) {
      final g = await _c.requestPermissions(['mic']);
      if (g['mic'] != true) {
        return _r(a, NovaActionStatus.permissionRequired,
            "The microphone isn't allowed, so recordings stay without sound. You can allow it in Settings.");
      }
    }
    await _c.updateSettings(_c.settings.copyWith(audio: mode));
    if (_c.isRecording) {
      return _ok(a, 'Done. That applies from your next recording; this one keeps its current sound setting.');
    }
    return _ok(a, switch (mode) {
      CaptureAudioMode.none => 'Recordings will have no sound.',
      CaptureAudioMode.mic => 'Recordings will include your microphone for narration.',
      CaptureAudioMode.device => 'Recordings will include sound from apps.',
      CaptureAudioMode.micAndDevice => 'Recordings will include your microphone and sound from apps.',
    });
  }

  // ── Saved captures ──────────────────────────────────────────────────────

  Future<NovaActionResult> _latest(NovaAction a, CaptureCommand cmd, NovaHost host) async {
    final kind = switch (cmd.intent == CaptureIntent.editLatest ? 'screenshot' : cmd.args['kind']) {
      'screenshot' => MediaKind.screenshot,
      'recording' => MediaKind.recording,
      _ => null,
    };
    final item = await _c.library.latest(kind: kind);
    final what = kind == MediaKind.recording ? 'recordings' : (kind == MediaKind.screenshot ? 'screenshots' : 'captures');
    if (item == null) return _r(a, NovaActionStatus.notFound, "You don't have any saved $what yet.");
    switch (cmd.intent) {
      case CaptureIntent.shareLatest:
        final shared = await _c.share(item);
        if (!shared.success) return _fail(a, shared, cmd);
        return _ok(a, 'Choose where to share ${item.isVideo ? 'your recording' : 'your screenshot'}.');
      case CaptureIntent.editLatest:
        return _open(a, host, 'capture_edit_latest', 'Opening your latest screenshot in the editor.');
      default:
        final id = item.isVideo ? 'capture_latest_video' : 'capture_latest_shot';
        return _open(a, host, id, 'Opening your latest ${item.isVideo ? 'recording' : 'screenshot'}.');
    }
  }
}
