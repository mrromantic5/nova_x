// lib/features/nova/services/nova_screen.dart
//
// "Read my screen" for the floating NOVA assistant (Android side:
// NovaScreenCapture.kt). NOVA takes ONE screenshot of the app the user is
// looking at, only after the user agrees in Android's own screen-capture
// dialog, and only when the user taps "Read my screen". The screenshot stays
// in memory and is shown in the panel; it is sent to NOVA AI only when the
// user sends the question. Nothing is recorded in the background.

import 'dart:typed_data';

import 'package:flutter/services.dart';

enum NovaScreenStatus {
  ok,
  granted,
  denied,
  locked,
  busy,
  unsupported,
  expired,

  /// The app in front blocks screenshots (banking apps, private content).
  protected,
  error,
}

class NovaScreenResult {
  const NovaScreenResult(this.status, [this.bytes]);
  final NovaScreenStatus status;
  final Uint8List? bytes;
}

class NovaScreen {
  NovaScreen._();

  static const MethodChannel _channel = MethodChannel('com.tlyfe.nova_x/nova');

  static NovaScreenStatus _status(Object? raw) {
    final s = raw is Map ? raw['status'] : null;
    for (final v in NovaScreenStatus.values) {
      if (v.name == s) return v;
    }
    return NovaScreenStatus.error;
  }

  /// Shows Android's screen-capture consent dialog.
  static Future<NovaScreenStatus> request() async {
    try {
      return _status(await _channel.invokeMethod<Object?>('screenCaptureRequest'));
    } on PlatformException {
      return NovaScreenStatus.error;
    } on MissingPluginException {
      return NovaScreenStatus.unsupported;
    }
  }

  /// Takes the one screenshot (call after [request] returned granted and the
  /// panel has been hidden).
  static Future<NovaScreenResult> grab() async {
    try {
      final raw = await _channel.invokeMethod<Object?>('screenCaptureGrab');
      final status = _status(raw);
      final bytes = raw is Map ? raw['bytes'] : null;
      if (status == NovaScreenStatus.ok && bytes is Uint8List && bytes.isNotEmpty) {
        return NovaScreenResult(status, bytes);
      }
      return NovaScreenResult(status == NovaScreenStatus.ok ? NovaScreenStatus.error : status);
    } on PlatformException {
      return const NovaScreenResult(NovaScreenStatus.error);
    } on MissingPluginException {
      return const NovaScreenResult(NovaScreenStatus.unsupported);
    }
  }

  /// Drops a consent that will not be used.
  static Future<void> cancel() async {
    try {
      await _channel.invokeMethod<Object?>('screenCaptureCancel');
    } catch (_) {
      // nothing to release
    }
  }

  /// Keeps the floating panel open while the photo picker or camera is shown.
  static Future<void> keepAssistantOpen(bool open) async {
    try {
      await _channel.invokeMethod<Object?>('assistantKeepOpen', {'open': open});
    } catch (_) {
      // older native side: the panel may close while picking
    }
  }

  static Future<bool> phoneLocked() async {
    try {
      return await _channel.invokeMethod<bool>('phoneLocked') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// What NOVA says when the screen could not be read.
  static String messageFor(NovaScreenStatus status) => switch (status) {
        NovaScreenStatus.denied => "Okay, I won't look at your screen.",
        NovaScreenStatus.locked => 'Unlock your phone first, then ask me to read your screen.',
        NovaScreenStatus.protected =>
          "This app doesn't allow screenshots, so I can't see it. Try a screenshot from your gallery instead.",
        NovaScreenStatus.unsupported => "Reading the screen isn't available on this phone.",
        NovaScreenStatus.busy => 'One moment — I am already reading your screen.',
        NovaScreenStatus.expired => 'That took too long. Tap "Read my screen" again.',
        _ => "I couldn't read your screen. Please try again.",
      };
}
