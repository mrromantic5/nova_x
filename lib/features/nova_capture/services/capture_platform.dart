// lib/features/nova_capture/services/capture_platform.dart
//
// Typed wrapper around the native NOVA Capture channel
// (com.tlyfe.nova_x/capture — see CaptureContract.kt for the full contract).
// Every call returns a CaptureResult; a missing native side (tests, another
// platform) gives an UNSUPPORTED result instead of throwing.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';

import '../models/capture_models.dart';
import '../models/media_asset.dart';

class CapturePlatform {
  CapturePlatform({MethodChannel? channel}) : _ch = channel ?? const MethodChannel(channelName);

  static const String channelName = 'com.tlyfe.nova_x/capture';
  static final CapturePlatform instance = CapturePlatform();

  final MethodChannel _ch;
  final _states = StreamController<CaptureSnapshot>.broadcast();
  final _events = StreamController<CaptureEvent>.broadcast();
  bool _bound = false;

  /// State changes pushed by the native coordinator (the source of truth).
  Stream<CaptureSnapshot> get states => _states.stream;

  /// One-off events (recordingSaved, screenshotCompleted, warning…).
  Stream<CaptureEvent> get events => _events.stream;

  void bind() {
    if (_bound) return;
    _bound = true;
    _ch.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'capture.state':
          _states.add(CaptureSnapshot.fromMap(call.arguments));
        case 'capture.event':
          _events.add(CaptureEvent.fromMap(call.arguments));
      }
      return null;
    });
  }

  Future<Map<String, Object?>> _invoke(String method, [Map<String, Object?>? args]) async {
    try {
      final r = await _ch.invokeMethod<Object?>(method, args);
      final m = asStringMap(r);
      return m.isEmpty
          ? {'success': false, 'errorCode': CaptureErrorCode.error}
          : m;
    } on MissingPluginException {
      return {
        'success': false,
        'errorCode': CaptureErrorCode.unsupported,
        'userMessage': "NOVA Capture isn't available here.",
      };
    } on PlatformException {
      return {'success': false, 'errorCode': CaptureErrorCode.error};
    }
  }

  Future<CaptureResult> _call(String method, [Map<String, Object?>? args]) async =>
      CaptureResult.fromMap(await _invoke(method, args));

  // ── State ───────────────────────────────────────────────────────────────

  Future<CaptureSnapshot> getState() async {
    try {
      return CaptureSnapshot.fromMap(await _ch.invokeMethod<Object?>('getState'));
    } catch (_) {
      return const CaptureSnapshot();
    }
  }

  Future<CaptureCapabilities> capabilities() async {
    try {
      return CaptureCapabilities.fromMap(await _ch.invokeMethod<Object?>('capabilities'));
    } catch (_) {
      return const CaptureCapabilities(available: false);
    }
  }

  // ── Recording ───────────────────────────────────────────────────────────

  Future<CaptureResult> startRecording(Map<String, Object> config) => _call('startRecording', {'config': config});
  Future<CaptureResult> pause(int? sessionId) => _call('pauseRecording', {'sessionId': sessionId});
  Future<CaptureResult> resume(int? sessionId) => _call('resumeRecording', {'sessionId': sessionId});
  Future<CaptureResult> stop(int? sessionId) => _call('stopRecording', {'sessionId': sessionId});
  Future<CaptureResult> cancel(int? sessionId) => _call('cancelRecording', {'sessionId': sessionId});
  Future<CaptureResult> retrySave() => _call('retrySave');
  Future<CaptureResult> discardUnsaved() => _call('discardUnsaved');

  // ── Screenshots ─────────────────────────────────────────────────────────

  Future<CaptureResult> captureScreen({required bool hideApp, required int delayMs}) =>
      _call('captureScreen', {'hideApp': hideApp, 'delayMs': delayMs});

  Future<CaptureResult> saveImage(Uint8List bytes, {String? name, String format = 'png', int quality = 92}) =>
      _call('saveImage', {'bytes': bytes, 'name': name, 'format': format, 'quality': quality});

  // ── Library ─────────────────────────────────────────────────────────────

  Future<List<MediaAsset>> listMedia() async {
    final m = await _invoke('listMedia');
    final items = m['items'];
    if (items is! List) return const [];
    return items.map(MediaAsset.fromMap).whereType<MediaAsset>().toList();
  }

  Future<Uint8List?> readBytes(String uri) async {
    final m = await _invoke('readBytes', {'uri': uri});
    final b = m['bytes'];
    return b is Uint8List ? b : null;
  }

  Future<Uint8List?> thumbnail(String uri, {int size = 320}) async {
    final m = await _invoke('thumbnail', {'uri': uri, 'size': size});
    final b = m['bytes'];
    return b is Uint8List ? b : null;
  }

  Future<MediaAsset?> describe(String uri) async => MediaAsset.fromMap((await _invoke('describe', {'uri': uri}))['item']);

  Future<CaptureResult> rename(String uri, String name) => _call('rename', {'uri': uri, 'name': name});
  Future<CaptureResult> delete(String uri) => _call('delete', {'uri': uri});
  Future<CaptureResult> share(String uri) => _call('share', {'uri': uri});
  Future<CaptureResult> openExternal(String uri) => _call('openExternal', {'uri': uri});
  Future<CaptureResult> copyImage(String uri) => _call('copyImage', {'uri': uri});
  Future<CaptureResult> exportTo(String uri) => _call('exportTo', {'uri': uri});

  /// {freeBytes, totalBytes}; -1 when unknown.
  Future<(int, int)> storageInfo() async {
    final m = await _invoke('storageInfo');
    final f = m['freeBytes'];
    final t = m['totalBytes'];
    return (f is num ? f.toInt() : -1, t is num ? t.toInt() : -1);
  }

  // ── Permissions ─────────────────────────────────────────────────────────

  /// [kinds]: 'mic' | 'notifications' | 'storage'. Returns the granted state of each.
  Future<Map<String, bool>> requestPermissions(List<String> kinds) async {
    final m = await _invoke('requestPermissions', {'kinds': kinds});
    return {
      'mic': m['mic'] == true,
      'notifications': m['notifications'] != false,
      'storage': m['storage'] != false,
      'micCanAsk': m['micCanAsk'] == true,
    };
  }

  Future<void> openOverlaySettings() => _invoke('openOverlaySettings');
  Future<void> openAppSettings() => _invoke('openAppSettings');
}
