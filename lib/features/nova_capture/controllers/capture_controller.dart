// lib/features/nova_capture/controllers/capture_controller.dart
//
// App-side view of NOVA Capture. It never decides on its own that something
// was recorded or saved: it mirrors the native coordinator's state
// (capture.state) and reports the native result of every operation.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../models/capture_models.dart';
import '../models/capture_settings.dart';
import '../models/media_asset.dart';
import '../services/capture_platform.dart';
import '../services/media_library_service.dart';
import '../services/webpage_capture_service.dart';

class CaptureController extends ChangeNotifier {
  CaptureController({CapturePlatform? platform, MediaLibraryService? library})
      : _platform = platform ?? CapturePlatform.instance,
        library = library ?? MediaLibraryService.instance;

  static final CaptureController instance = CaptureController();

  final CapturePlatform _platform;
  final MediaLibraryService library;

  CaptureSnapshot snapshot = const CaptureSnapshot();
  CaptureCapabilities capabilities = const CaptureCapabilities();
  RecordingSettings settings = const RecordingSettings();
  ScreenshotSettings shotSettings = const ScreenshotSettings();

  /// Bumped whenever a capture is added, renamed or deleted (library screens listen).
  final ValueNotifier<int> libraryVersion = ValueNotifier<int>(0);

  final _events = StreamController<CaptureEvent>.broadcast();
  Stream<CaptureEvent> get events => _events.stream;

  StreamSubscription<CaptureSnapshot>? _stateSub;
  StreamSubscription<CaptureEvent>? _eventSub;
  Timer? _tick;
  bool _inited = false;
  Future<void>? _initFuture;

  Future<void> init() => _initFuture ??= _init();

  Future<void> _init() async {
    if (_inited) return;
    _inited = true;
    _platform.bind();
    _stateSub = _platform.states.listen(_onState);
    _eventSub = _platform.events.listen(_onEvent);
    settings = await library.loadRecordingSettings();
    shotSettings = await library.loadScreenshotSettings();
    await refresh();
  }

  Future<void> refresh() async {
    _onState(await _platform.getState());
    capabilities = await _platform.capabilities();
    notifyListeners();
  }

  Future<void> refreshCapabilities() async {
    capabilities = await _platform.capabilities();
    notifyListeners();
  }

  void _onState(CaptureSnapshot s) {
    snapshot = s;
    _syncTicker();
    notifyListeners();
  }

  void _onEvent(CaptureEvent e) {
    if (e.type == CaptureEvent.mediaAvailable) libraryVersion.value++;
    if (!_events.isClosed) _events.add(e);
  }

  /// Rebuilds once a second while recording so timers move.
  void _syncTicker() {
    final want = snapshot.state == RecordingState.recording || snapshot.state == RecordingState.starting;
    if (want && _tick == null) {
      _tick = Timer.periodic(const Duration(seconds: 1), (_) => notifyListeners());
    } else if (!want && _tick != null) {
      _tick?.cancel();
      _tick = null;
    }
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _eventSub?.cancel();
    _tick?.cancel();
    _events.close();
    super.dispose();
  }

  // ── Read ────────────────────────────────────────────────────────────────

  RecordingState get state => snapshot.state;
  Duration get elapsed => snapshot.elapsedAt(DateTime.now());
  bool get isRecording => snapshot.state.isCapturing;
  bool get isBusy => snapshot.state.isActive || snapshot.screenshotBusy;

  /// NOVA should not speak while its voice could end up in the recording
  /// (any recording with sound, including the countdown before it starts).
  bool get shouldSilenceAssistant {
    final s = snapshot.state;
    if (s == RecordingState.recording || s == RecordingState.paused) return snapshot.hasAudio;
    if (s == RecordingState.starting || s == RecordingState.awaitingConsent) {
      return settings.audio != CaptureAudioMode.none;
    }
    return false;
  }

  /// Why the last recording didn't start / failed, in plain words.
  String explainLastProblem() {
    final s = snapshot;
    if (s.state.isCapturing) return 'Your screen is being recorded right now (${formatDuration(elapsed)}).';
    final msg = s.userMessage;
    if (msg != null && msg.isNotEmpty && (s.state == RecordingState.failed || s.state == RecordingState.cancelled)) {
      return msg;
    }
    if (s.warnings.isNotEmpty) return s.warnings.last;
    return "I don't see a problem with the last recording.";
  }

  // ── Settings ────────────────────────────────────────────────────────────

  Future<void> updateSettings(RecordingSettings s) async {
    settings = s;
    notifyListeners();
    await library.saveRecordingSettings(s);
  }

  Future<void> updateShotSettings(ScreenshotSettings s) async {
    final droppedMetadata = shotSettings.saveWebMetadata && !s.saveWebMetadata;
    shotSettings = s;
    notifyListeners();
    await library.saveScreenshotSettings(s);
    if (droppedMetadata) await library.clearAllMetadata();
  }

  // ── Permissions ─────────────────────────────────────────────────────────

  Future<Map<String, bool>> requestPermissions(List<String> kinds) async {
    final r = await _platform.requestPermissions(kinds);
    await refreshCapabilities();
    return r;
  }

  Future<void> openAppSettings() => _platform.openAppSettings();
  Future<void> openOverlaySettings() => _platform.openOverlaySettings();

  // ── Recording ───────────────────────────────────────────────────────────

  /// Starts after Android's consent; completes when recording has begun (or failed).
  Future<CaptureResult> startRecording({RecordingSettings? using}) async {
    await init();
    final r = await _platform.startRecording((using ?? settings).toNative());
    await refresh();
    return r;
  }

  Future<CaptureResult> pause() => _platform.pause(snapshot.sessionId);
  Future<CaptureResult> resume() => _platform.resume(snapshot.sessionId);
  Future<CaptureResult> stop() => _platform.stop(snapshot.sessionId);
  Future<CaptureResult> cancel() => _platform.cancel(snapshot.sessionId);

  Future<CaptureResult> retrySave() async {
    final r = await _platform.retrySave();
    if (r.success) libraryVersion.value++;
    return r;
  }

  Future<CaptureResult> discardUnsaved() => _platform.discardUnsaved();

  /// Waits for the recording that was just stopped to be saved (or to fail).
  Future<CaptureResult> waitForSaved({Duration timeout = const Duration(seconds: 60)}) async {
    final sid = snapshot.sessionId;
    // Already finished before we started waiting?
    if (snapshot.state == RecordingState.saved) {
      return CaptureResult(success: true, item: snapshot.lastItem, state: RecordingState.saved, sessionId: sid);
    }
    if (snapshot.state == RecordingState.failed) {
      return CaptureResult.failure(snapshot.errorCode ?? CaptureErrorCode.save, snapshot.userMessage);
    }
    try {
      final e = await events
          .firstWhere((e) =>
              e.sessionId == sid &&
              (e.type == CaptureEvent.recordingSaved || e.type == CaptureEvent.recordingFailed))
          .timeout(timeout);
      if (e.type == CaptureEvent.recordingSaved) {
        return CaptureResult(success: true, item: e.item, state: RecordingState.saved, sessionId: sid);
      }
      final code = e.data['errorCode'];
      return CaptureResult.failure(code is String ? code : CaptureErrorCode.save, e.userMessage);
    } on TimeoutException {
      return CaptureResult.failure(CaptureErrorCode.timeout, 'Saving is taking longer than expected.');
    } on StateError {
      return CaptureResult.failure(CaptureErrorCode.error);
    }
  }

  // ── Screenshots ─────────────────────────────────────────────────────────

  /// Whole-screen screenshot after Android's consent (see ScreenshotSettings).
  Future<CaptureResult> captureScreen({bool? hideApp, int? delayMs}) async {
    await init();
    final r = await _platform.captureScreen(
      hideApp: hideApp ?? shotSettings.hideAppForScreen,
      delayMs: delayMs ?? shotSettings.screenDelaySec * 1000,
    );
    if (r.success && r.item != null) await _afterNewScreenshot(r.item!);
    return r;
  }

  /// Saves a captured webpage image (PNG) and its page details if allowed.
  Future<CaptureResult> saveWebScreenshot(Uint8List png, {WebCaptureTarget? from}) async {
    final r = await _platform.saveImage(png, format: 'png');
    final item = r.item;
    if (r.success && item != null) {
      if (from != null && shotSettings.saveWebMetadata && !from.captureIncognito) {
        await library.setMetadata(item.uri, from.captureTitle, from.captureUrl);
      }
      await _afterNewScreenshot(item);
    }
    return r;
  }

  /// Saves an edited copy (the original screenshot is never overwritten).
  Future<CaptureResult> saveEdited(Uint8List png, {required String name, String? format, int? quality}) async {
    final r = await _platform.saveImage(
      png,
      name: name,
      format: format ?? shotSettings.format,
      quality: quality ?? shotSettings.quality,
    );
    if (r.success) libraryVersion.value++;
    return r;
  }

  Future<void> _afterNewScreenshot(MediaAsset item) async {
    libraryVersion.value++;
    if (shotSettings.copyToClipboard) await _platform.copyImage(item.uri);
  }

  // ── Media actions ───────────────────────────────────────────────────────

  Future<CaptureResult> rename(MediaAsset a, String name) async {
    final r = await _platform.rename(a.uri, name);
    if (r.success) libraryVersion.value++;
    return r;
  }

  Future<CaptureResult> delete(MediaAsset a) async {
    final r = await _platform.delete(a.uri);
    if (r.success) {
      await library.forget(a.uri);
      libraryVersion.value++;
    }
    return r;
  }

  Future<CaptureResult> share(MediaAsset a) => _platform.share(a.uri);
  Future<CaptureResult> openExternal(MediaAsset a) => _platform.openExternal(a.uri);
  Future<CaptureResult> copyImage(MediaAsset a) => _platform.copyImage(a.uri);
  Future<CaptureResult> exportTo(MediaAsset a) => _platform.exportTo(a.uri);
  Future<Uint8List?> readBytes(MediaAsset a) => _platform.readBytes(a.uri);
  Future<MediaAsset?> describe(String uri) => _platform.describe(uri);
  Future<(int, int)> storageInfo() => _platform.storageInfo();
}
