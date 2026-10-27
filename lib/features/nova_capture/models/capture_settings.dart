// lib/features/nova_capture/models/capture_settings.dart
//
// NOVA Capture settings, kept on the phone (SharedPreferences). Values the
// native side doesn't know are replaced by defaults there too.

import 'dart:convert';

enum CaptureAudioMode {
  none('none', 'No audio', 'Video only. Nothing is recorded from the microphone.'),
  mic('mic', 'Microphone', 'Your voice, for narration. The microphone is on only while recording.'),
  device('device', 'App sound', 'Sound from apps (Android 10+). Calls and some apps block it.'),
  micAndDevice('mic_device', 'Microphone + app sound', 'Both, mixed together (Android 10+).');

  const CaptureAudioMode(this.wire, this.label, this.description);
  final String wire;
  final String label;
  final String description;

  /// Every audio mode needs Android's microphone permission (app sound too).
  bool get needsRecordPermission => this != CaptureAudioMode.none;
  bool get usesMicrophone => this == CaptureAudioMode.mic || this == CaptureAudioMode.micAndDevice;
  bool get usesDeviceAudio => this == CaptureAudioMode.device || this == CaptureAudioMode.micAndDevice;

  static CaptureAudioMode fromWire(Object? v) {
    for (final m in values) {
      if (m.wire == v) return m;
    }
    return CaptureAudioMode.none;
  }
}

class RecordingSettings {
  const RecordingSettings({
    this.resolution = 'auto',
    this.fps = 30,
    this.bitrate = 'auto',
    this.orientation = 'auto',
    this.audio = CaptureAudioMode.none,
    this.maxDurationSec = 0,
    this.countdownSec = 3,
    this.overlayEnabled = false,
  });

  static const resolutions = ['auto', '1080', '720', '480'];
  static const frameRates = [24, 30, 60];
  static const bitrates = ['auto', 'low', 'medium', 'high'];
  static const orientations = ['auto', 'portrait', 'landscape'];
  static const durations = [0, 300, 900, 1800, 3600];
  static const countdowns = [0, 3, 5, 10];

  /// auto | 1080 | 720 | 480 (short side, pixels).
  final String resolution;
  final int fps;
  final String bitrate;
  final String orientation;
  final CaptureAudioMode audio;

  /// 0 = no limit.
  final int maxDurationSec;
  final int countdownSec;

  /// Floating controls over other apps (needs Android's "Display over other apps").
  final bool overlayEnabled;

  RecordingSettings copyWith({
    String? resolution,
    int? fps,
    String? bitrate,
    String? orientation,
    CaptureAudioMode? audio,
    int? maxDurationSec,
    int? countdownSec,
    bool? overlayEnabled,
  }) =>
      RecordingSettings(
        resolution: resolution ?? this.resolution,
        fps: fps ?? this.fps,
        bitrate: bitrate ?? this.bitrate,
        orientation: orientation ?? this.orientation,
        audio: audio ?? this.audio,
        maxDurationSec: maxDurationSec ?? this.maxDurationSec,
        countdownSec: countdownSec ?? this.countdownSec,
        overlayEnabled: overlayEnabled ?? this.overlayEnabled,
      );

  /// The `config` map sent to CaptureCoordinator.startRecording.
  Map<String, Object> toNative() => {
        'resolution': resolution,
        'fps': fps,
        'bitrate': bitrate,
        'orientation': orientation,
        'audio': audio.wire,
        'maxDurationSec': maxDurationSec,
        'countdownSec': countdownSec,
        'overlayEnabled': overlayEnabled,
      };

  String toJson() => jsonEncode(toNative());

  static RecordingSettings fromJson(String? raw) {
    if (raw == null || raw.isEmpty) return const RecordingSettings();
    try {
      final m = jsonDecode(raw);
      if (m is! Map) return const RecordingSettings();
      T pick<T>(Object? v, List<T> allowed, T fallback) => v is T && allowed.contains(v) ? v : fallback;
      return RecordingSettings(
        resolution: pick<String>(m['resolution'], resolutions, 'auto'),
        fps: pick<int>(m['fps'], frameRates, 30),
        bitrate: pick<String>(m['bitrate'], bitrates, 'auto'),
        orientation: pick<String>(m['orientation'], orientations, 'auto'),
        audio: CaptureAudioMode.fromWire(m['audio']),
        maxDurationSec: pick<int>(m['maxDurationSec'], durations, 0),
        countdownSec: pick<int>(m['countdownSec'], countdowns, 3),
        overlayEnabled: m['overlayEnabled'] == true,
      );
    } catch (_) {
      return const RecordingSettings();
    }
  }

  String get resolutionLabel => resolution == 'auto' ? 'Auto (up to 1080p)' : '${resolution}p';

  String get bitrateLabel => switch (bitrate) {
        'low' => 'Low (smaller files)',
        'medium' => 'Medium',
        'high' => 'High (sharpest)',
        _ => 'Auto',
      };

  String get orientationLabel => switch (orientation) {
        'portrait' => 'Portrait',
        'landscape' => 'Landscape',
        _ => 'Auto (as the phone is held)',
      };

  String get durationLabel => maxDurationSec == 0 ? 'No limit' : '${maxDurationSec ~/ 60} minutes';

  /// Rough size of one minute of video, for the settings screen (an estimate,
  /// never a promise: the encoder and the screen content decide).
  int estimatedBytesPerMinute({int shortSide = 1080, int longSide = 2400}) {
    final target = resolution == 'auto' ? (shortSide < 1080 ? shortSide : 1080) : int.parse(resolution);
    final scale = target / shortSide;
    final w = shortSide * (scale > 1 ? 1 : scale);
    final h = longSide * (scale > 1 ? 1 : scale);
    final bpp = switch (bitrate) { 'low' => 0.05, 'medium' => 0.1, 'high' => 0.18, _ => 0.09 };
    var bits = w * h * fps * bpp;
    if (bits < 1000000) bits = 1000000;
    if (bits > 24000000) bits = 24000000;
    final audioBits = audio == CaptureAudioMode.none ? 0 : 128000;
    return ((bits + audioBits) * 60 / 8).round();
  }
}

class ScreenshotSettings {
  const ScreenshotSettings({
    this.format = 'png',
    this.quality = 92,
    this.saveWebMetadata = false,
    this.copyToClipboard = false,
    this.hideAppForScreen = true,
    this.screenDelaySec = 0,
  });

  static const formats = ['png', 'jpeg', 'webp'];
  static const delays = [0, 3, 5, 10];

  /// Export format for edited images. Captures themselves are always PNG.
  final String format;
  final int quality;

  /// Remember the page title and address with webpage screenshots (off by default).
  final bool saveWebMetadata;

  /// Also copy each new screenshot to the clipboard (off by default).
  final bool copyToClipboard;

  /// "Capture entire screen": step NOVA X aside so the screen behind it is captured.
  final bool hideAppForScreen;
  final int screenDelaySec;

  ScreenshotSettings copyWith({
    String? format,
    int? quality,
    bool? saveWebMetadata,
    bool? copyToClipboard,
    bool? hideAppForScreen,
    int? screenDelaySec,
  }) =>
      ScreenshotSettings(
        format: format ?? this.format,
        quality: quality ?? this.quality,
        saveWebMetadata: saveWebMetadata ?? this.saveWebMetadata,
        copyToClipboard: copyToClipboard ?? this.copyToClipboard,
        hideAppForScreen: hideAppForScreen ?? this.hideAppForScreen,
        screenDelaySec: screenDelaySec ?? this.screenDelaySec,
      );

  String toJson() => jsonEncode({
        'format': format,
        'quality': quality,
        'saveWebMetadata': saveWebMetadata,
        'copyToClipboard': copyToClipboard,
        'hideAppForScreen': hideAppForScreen,
        'screenDelaySec': screenDelaySec,
      });

  static ScreenshotSettings fromJson(String? raw) {
    if (raw == null || raw.isEmpty) return const ScreenshotSettings();
    try {
      final m = jsonDecode(raw);
      if (m is! Map) return const ScreenshotSettings();
      final f = m['format'];
      final q = m['quality'];
      final d = m['screenDelaySec'];
      return ScreenshotSettings(
        format: f is String && formats.contains(f) ? f : 'png',
        quality: q is int && q >= 40 && q <= 100 ? q : 92,
        saveWebMetadata: m['saveWebMetadata'] == true,
        copyToClipboard: m['copyToClipboard'] == true,
        hideAppForScreen: m['hideAppForScreen'] != false,
        screenDelaySec: d is int && delays.contains(d) ? d : 0,
      );
    } catch (_) {
      return const ScreenshotSettings();
    }
  }
}
