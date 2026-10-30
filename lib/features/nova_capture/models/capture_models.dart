// lib/features/nova_capture/models/capture_models.dart
//
// Typed contract with the native NOVA Capture module
// (android/.../capture/CaptureContract.kt). The native coordinator is the
// single source of truth; these classes only mirror what it reports.

import 'media_asset.dart';

/// Recording states, exactly as the native state machine names them.
enum RecordingState {
  idle('idle'),
  awaitingConsent('awaiting_consent'),
  starting('starting'),
  recording('recording'),
  paused('paused'),
  stopping('stopping'),
  finalizing('finalizing'),
  saved('saved'),
  cancelled('cancelled'),
  failed('failed');

  const RecordingState(this.wire);
  final String wire;

  static RecordingState fromWire(Object? v) {
    for (final s in values) {
      if (s.wire == v) return s;
    }
    return RecordingState.idle;
  }

  /// A session exists: a new recording can't start.
  bool get isActive => switch (this) {
        RecordingState.awaitingConsent ||
        RecordingState.starting ||
        RecordingState.recording ||
        RecordingState.paused ||
        RecordingState.stopping ||
        RecordingState.finalizing =>
          true,
        _ => false,
      };

  /// Video is being captured (or is paused mid-capture).
  bool get isCapturing => this == RecordingState.recording || this == RecordingState.paused;

  /// Saving after Stop.
  bool get isSaving => this == RecordingState.stopping || this == RecordingState.finalizing;

  String get label => switch (this) {
        RecordingState.idle => 'Ready',
        RecordingState.awaitingConsent => 'Waiting for permission',
        RecordingState.starting => 'Starting',
        RecordingState.recording => 'Recording',
        RecordingState.paused => 'Paused',
        RecordingState.stopping => 'Stopping',
        RecordingState.finalizing => 'Saving video',
        RecordingState.saved => 'Saved',
        RecordingState.cancelled => 'Cancelled',
        RecordingState.failed => 'Failed',
      };
}

/// Stable error codes from the native side, with plain-language fallbacks.
class CaptureErrorCode {
  CaptureErrorCode._();

  static const consentDenied = 'CONSENT_DENIED';
  static const permission = 'PERMISSION_REQUIRED';
  static const busy = 'BUSY';
  static const busyRecording = 'BUSY_RECORDING';
  static const invalidState = 'INVALID_STATE';
  static const staleSession = 'STALE_SESSION';
  static const unsupported = 'UNSUPPORTED';
  static const lowStorage = 'LOW_STORAGE';
  static const locked = 'DEVICE_LOCKED';
  static const encoder = 'ENCODER_FAILED';
  static const audio = 'AUDIO_UNAVAILABLE';
  static const save = 'SAVE_FAILED';
  static const tooShort = 'TOO_SHORT';
  static const interrupted = 'INTERRUPTED';
  static const protectedContent = 'PROTECTED_CONTENT';
  static const notFound = 'NOT_FOUND';
  static const invalidArgument = 'INVALID_ARGUMENT';
  static const needsApproval = 'NEEDS_USER_APPROVAL';
  static const noActivity = 'NO_ACTIVITY';
  static const timeout = 'TIMEOUT';
  static const cancelled = 'CANCELLED';
  static const webCapture = 'WEB_CAPTURE_FAILED';
  static const noPage = 'NO_PAGE';
  static const error = 'ERROR';

  static String message(String? code) => switch (code) {
        consentDenied => 'Nothing was captured because the screen-capture request was declined.',
        permission => 'NOVA X needs a permission to do that.',
        busy => 'NOVA Capture is busy. Try again in a moment.',
        busyRecording => 'A screen recording is running. Stop it first.',
        invalidState => "That can't be done right now.",
        staleSession => 'That recording has already ended.',
        unsupported => "That isn't available on this phone.",
        lowStorage => 'Your phone is almost out of space.',
        locked => 'Unlock your phone first.',
        encoder => "This phone's video encoder couldn't start. Try a lower resolution.",
        audio => "Audio can't be recorded that way on this phone.",
        save => "It couldn't be saved. Check that your phone has free space.",
        tooShort => 'The recording was too short to save.',
        interrupted => 'Screen capture was stopped by Android.',
        protectedContent => 'The app on screen blocks screenshots, so nothing was captured.',
        notFound => "That capture isn't available any more.",
        timeout => "Android's screen-capture request wasn't answered.",
        cancelled => 'Cancelled.',
        webCapture => "This page couldn't be captured.",
        noPage => 'Open a web page in NOVA X first.',
        _ => 'Something went wrong. Please try again.',
      };
}

Map<String, Object?> asStringMap(Object? raw) {
  if (raw is! Map) return const {};
  final out = <String, Object?>{};
  raw.forEach((k, v) {
    if (k is String) out[k] = v;
  });
  return out;
}

/// The result of one capture operation.
class CaptureResult {
  const CaptureResult({
    required this.success,
    this.errorCode,
    this.userMessage,
    this.state,
    this.sessionId,
    this.item,
    this.data = const {},
  });

  factory CaptureResult.fromMap(Object? raw) {
    final m = asStringMap(raw);
    final code = m['errorCode'];
    final msg = m['userMessage'];
    final sid = m['sessionId'];
    final success = m['success'] == true;
    return CaptureResult(
      success: success,
      errorCode: code is String ? code : (success ? null : CaptureErrorCode.error),
      userMessage: msg is String && msg.isNotEmpty
          ? msg
          : (success ? null : CaptureErrorCode.message(code is String ? code : null)),
      state: m['state'] == null ? null : RecordingState.fromWire(m['state']),
      sessionId: sid is num ? sid.toInt() : null,
      item: MediaAsset.fromMap(m['item']),
      data: m,
    );
  }

  factory CaptureResult.failure(String code, [String? message]) => CaptureResult(
        success: false,
        errorCode: code,
        userMessage: message ?? CaptureErrorCode.message(code),
      );

  final bool success;
  final String? errorCode;
  final String? userMessage;
  final RecordingState? state;
  final int? sessionId;
  final MediaAsset? item;
  final Map<String, Object?> data;

  /// Which runtime permission is missing ('mic' | 'storage'), when that's the problem.
  String? get missingPermission {
    final p = data['permission'];
    return errorCode == CaptureErrorCode.permission && p is String ? p : null;
  }

  String get message => userMessage ?? (success ? 'Done.' : CaptureErrorCode.message(errorCode));
}

/// A snapshot of the native recording state.
class CaptureSnapshot {
  const CaptureSnapshot({
    this.state = RecordingState.idle,
    this.sessionId = 0,
    this.elapsedMs = 0,
    this.receivedAtMs = 0,
    this.countdown = 0,
    this.audio = 'none',
    this.micInUse = false,
    this.width = 0,
    this.height = 0,
    this.fps = 0,
    this.bitrate = 0,
    this.errorCode,
    this.userMessage,
    this.lastItem,
    this.warnings = const [],
    this.stopReason = 'user',
    this.screenshotBusy = false,
    this.overlayShowing = false,
    this.hasUnsaved = false,
    this.bubbleEnabled = false,
    this.bubbleShowing = false,
  });

  factory CaptureSnapshot.fromMap(Object? raw, {int? nowMs}) {
    final m = asStringMap(raw);
    int i(String k) {
      final v = m[k];
      return v is num ? v.toInt() : 0;
    }

    String? s(String k) {
      final v = m[k];
      return v is String ? v : null;
    }

    final w = m['warnings'];
    return CaptureSnapshot(
      state: RecordingState.fromWire(m['state']),
      sessionId: i('sessionId'),
      elapsedMs: i('elapsedMs'),
      receivedAtMs: nowMs ?? DateTime.now().millisecondsSinceEpoch,
      countdown: i('countdown'),
      audio: s('audio') ?? 'none',
      micInUse: m['micInUse'] == true,
      width: i('width'),
      height: i('height'),
      fps: i('fps'),
      bitrate: i('bitrate'),
      errorCode: s('errorCode'),
      userMessage: s('userMessage'),
      lastItem: MediaAsset.fromMap(m['lastItem']),
      warnings: w is List ? w.whereType<String>().toList(growable: false) : const [],
      stopReason: s('stopReason') ?? 'user',
      screenshotBusy: m['screenshotBusy'] == true,
      overlayShowing: m['overlayShowing'] == true,
      hasUnsaved: m['hasUnsaved'] == true,
      bubbleEnabled: m['bubbleEnabled'] == true,
      bubbleShowing: m['bubbleShowing'] == true,
    );
  }

  final RecordingState state;
  final int sessionId;
  final int elapsedMs;
  final int receivedAtMs;
  final int countdown;
  final String audio;
  final bool micInUse;
  final int width;
  final int height;
  final int fps;
  final int bitrate;
  final String? errorCode;
  final String? userMessage;
  final MediaAsset? lastItem;
  final List<String> warnings;
  final String stopReason;
  final bool screenshotBusy;
  final bool overlayShowing;
  final bool hasUnsaved;

  /// The floating capture button is turned on / currently on screen.
  final bool bubbleEnabled;
  final bool bubbleShowing;

  /// Recording time at [now] (only advances while actually recording).
  Duration elapsedAt(DateTime now) {
    if (state != RecordingState.recording) return Duration(milliseconds: elapsedMs);
    final extra = now.millisecondsSinceEpoch - receivedAtMs;
    return Duration(milliseconds: elapsedMs + (extra > 0 ? extra : 0));
  }

  bool get hasAudio => audio != 'none';
}

/// One-off events from the native side ("capture.recordingSaved"…).
class CaptureEvent {
  const CaptureEvent({required this.type, this.sessionId = 0, this.state, this.item, this.data = const {}});

  factory CaptureEvent.fromMap(Object? raw) {
    final m = asStringMap(raw);
    final t = m['type'];
    final sid = m['sessionId'];
    return CaptureEvent(
      type: t is String ? t : '',
      sessionId: sid is num ? sid.toInt() : 0,
      state: m['state'] == null ? null : RecordingState.fromWire(m['state']),
      item: MediaAsset.fromMap(m['item']),
      data: m,
    );
  }

  static const permissionRequired = 'capture.permissionRequired';
  static const permissionGranted = 'capture.permissionGranted';
  static const permissionDenied = 'capture.permissionDenied';
  static const screenshotStarted = 'capture.screenshotStarted';
  static const screenshotCompleted = 'capture.screenshotCompleted';
  static const screenshotFailed = 'capture.screenshotFailed';
  static const recordingStarted = 'capture.recordingStarted';
  static const recordingPaused = 'capture.recordingPaused';
  static const recordingResumed = 'capture.recordingResumed';
  static const recordingStopped = 'capture.recordingStopped';
  static const recordingSaved = 'capture.recordingSaved';
  static const recordingCancelled = 'capture.recordingCancelled';
  static const recordingInterrupted = 'capture.recordingInterrupted';
  static const recordingFailed = 'capture.recordingFailed';
  static const mediaAvailable = 'capture.mediaAvailable';
  static const warning = 'capture.warning';

  final String type;
  final int sessionId;
  final RecordingState? state;
  final MediaAsset? item;
  final Map<String, Object?> data;

  String? get userMessage {
    final v = data['userMessage'];
    return v is String ? v : null;
  }
}

/// What this phone and NOVA X are currently allowed to do.
class CaptureCapabilities {
  const CaptureCapabilities({
    this.sdk = 0,
    this.deviceAudio = false,
    this.micGranted = false,
    this.notificationsGranted = true,
    this.overlayPermission = false,
    this.needsStoragePermission = false,
    this.lostRecordings = 0,
    this.available = true,
    this.bubbleEnabled = false,
  });

  factory CaptureCapabilities.fromMap(Object? raw) {
    final m = asStringMap(raw);
    if (m.isEmpty) return const CaptureCapabilities(available: false);
    final sdk = m['sdk'];
    final lost = m['lostRecordings'];
    return CaptureCapabilities(
      sdk: sdk is num ? sdk.toInt() : 0,
      deviceAudio: m['deviceAudio'] == true,
      micGranted: m['micGranted'] == true,
      notificationsGranted: m['notificationsGranted'] != false,
      overlayPermission: m['overlayPermission'] == true,
      needsStoragePermission: m['needsStoragePermission'] == true,
      lostRecordings: lost is num ? lost.toInt() : 0,
      bubbleEnabled: m['bubbleEnabled'] == true,
    );
  }

  final int sdk;
  final bool deviceAudio;
  final bool micGranted;
  final bool notificationsGranted;
  final bool overlayPermission;
  final bool needsStoragePermission;
  final int lostRecordings;
  final bool bubbleEnabled;

  /// False when the native module isn't there (tests, other platforms).
  final bool available;
}
