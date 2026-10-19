// lib/features/nova/services/nova_native.dart
//
// Dart side of the "com.tlyfe.nova_x/nova" channel (see NovaBridge.kt).
// Only fixed, named operations are exposed — no raw intents or class names.

import 'dart:async';

import 'package:flutter/services.dart';

/// Events pushed from Android.
sealed class NovaNativeEvent {
  const NovaNativeEvent();
}

class NovaAmplitudeEvent extends NovaNativeEvent {
  const NovaAmplitudeEvent(this.level);
  final double level; // 0..1
}

class NovaRecordingStoppedEvent extends NovaNativeEvent {
  const NovaRecordingStoppedEvent(this.reason);

  /// silence · no_speech · max_duration · interrupted
  final String reason;
}

class NovaTtsEvent extends NovaNativeEvent {
  const NovaTtsEvent(this.kind, this.utteranceId);
  final String kind; // start · done · error
  final String utteranceId;
}

class NovaAssistInvokedEvent extends NovaNativeEvent {
  const NovaAssistInvokedEvent([this.reason = 'assist']);

  /// 'assist' (assistant gesture) or 'wake' ("Hey NOVA").
  final String reason;
}

class NovaRecordStart {
  const NovaRecordStart(this.status, [this.message]);

  /// recording · permission_required · busy · error
  final String status;
  final String? message;
}

class NovaRecording {
  const NovaRecording({
    required this.status,
    this.path,
    this.durationMs = 0,
    this.hadSpeech = false,
  });

  /// ok · empty · idle
  final String status;
  final String? path;
  final int durationMs;
  final bool hadSpeech;

  bool get usable => status == 'ok' && path != null;
}

/// Result map of a native device action (status + small display fields).
class NovaNativeResult {
  const NovaNativeResult(this.status, this.data);
  final String status; // success · not_found · invalid · unsupported · permission_required · error
  final Map<String, dynamic> data;

  String? str(String key) {
    final v = data[key];
    return v is String ? v : null;
  }
}

class NovaAssistantStatus {
  const NovaAssistantStatus({
    required this.supported,
    required this.held,
    required this.eligible,
    required this.sdk,
  });
  final bool supported;
  final bool held;
  final bool eligible;
  final int sdk;
}

abstract class NovaNativeApi {
  Stream<NovaNativeEvent> get events;

  Future<NovaRecordStart> startRecording({int maxSeconds, bool autoStop});
  Future<NovaRecording> stopRecording();
  Future<void> cancelRecording();

  /// Returns false when the phone has no usable text-to-speech engine.
  Future<bool> speak(String text, String utteranceId);
  Future<void> stopSpeaking();

  Future<bool> isPermissionGranted(String kind);
  Future<bool> requestPermission(String kind);
  Future<void> openAppPermissionSettings();

  Future<NovaNativeResult> runAction(String action, Map<String, String> args);

  Future<NovaAssistantStatus> assistantStatus();
  Future<bool> openAssistantSettings();
  Future<void> closeAssistant();
}

class NovaNative implements NovaNativeApi {
  NovaNative._() {
    _channel.setMethodCallHandler(_onNativeCall);
  }

  /// One per Flutter engine (main app and floating assistant each have one).
  static final NovaNative instance = NovaNative._();

  static const MethodChannel _channel = MethodChannel('com.tlyfe.nova_x/nova');
  final StreamController<NovaNativeEvent> _events = StreamController.broadcast();

  @override
  Stream<NovaNativeEvent> get events => _events.stream;

  Future<dynamic> _onNativeCall(MethodCall call) async {
    final arg = call.arguments;
    switch (call.method) {
      case 'onAmplitude':
        if (arg is num) _events.add(NovaAmplitudeEvent(arg.clamp(0, 1).toDouble()));
        break;
      case 'onRecordingAutoStopped':
        _events.add(NovaRecordingStoppedEvent(arg is String ? arg : 'silence'));
        break;
      case 'onTtsStart':
        _events.add(NovaTtsEvent('start', arg is String ? arg : ''));
        break;
      case 'onTtsDone':
        _events.add(NovaTtsEvent('done', arg is String ? arg : ''));
        break;
      case 'onTtsError':
        _events.add(NovaTtsEvent('error', arg is String ? arg : ''));
        break;
      case 'onAssistInvoked':
        _events.add(NovaAssistInvokedEvent(arg == 'wake' ? 'wake' : 'assist'));
        break;
    }
    return null;
  }

  Future<Map<String, dynamic>> _map(String method, [Map<String, Object?>? args]) async {
    try {
      final res = await _channel.invokeMethod<Object>(method, args);
      if (res is Map) return Map<String, dynamic>.from(res);
      return const {};
    } on PlatformException catch (e) {
      return {'status': 'error', 'message': e.message ?? 'Native error'};
    } on MissingPluginException {
      return const {'status': 'unsupported'};
    }
  }

  @override
  Future<NovaRecordStart> startRecording({int maxSeconds = 30, bool autoStop = true}) async {
    final m = await _map('startRecording', {'maxSeconds': maxSeconds, 'autoStop': autoStop});
    return NovaRecordStart(m['status'] as String? ?? 'error', m['message'] as String?);
  }

  @override
  Future<NovaRecording> stopRecording() async {
    final m = await _map('stopRecording');
    final duration = m['durationMs'];
    return NovaRecording(
      status: m['status'] as String? ?? 'idle',
      path: m['path'] as String?,
      durationMs: duration is num ? duration.toInt() : 0,
      hadSpeech: m['hadSpeech'] == true,
    );
  }

  @override
  Future<void> cancelRecording() => _call('cancelRecording');

  @override
  Future<bool> speak(String text, String utteranceId) async {
    try {
      final ok = await _channel.invokeMethod<bool>('speak', {'text': text, 'id': utteranceId});
      return ok ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<void> stopSpeaking() => _call('stopSpeaking');

  @override
  Future<bool> isPermissionGranted(String kind) async {
    try {
      return await _channel.invokeMethod<String>('permissionStatus', {'kind': kind}) == 'granted';
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<bool> requestPermission(String kind) async {
    try {
      return await _channel.invokeMethod<bool>('requestPermission', {'kind': kind}) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<void> openAppPermissionSettings() => _call('openAppPermissionSettings');

  @override
  Future<NovaNativeResult> runAction(String action, Map<String, String> args) async {
    final m = await _map('runAction', {'action': action, 'args': args});
    return NovaNativeResult(m['status'] as String? ?? 'error', m);
  }

  @override
  Future<NovaAssistantStatus> assistantStatus() async {
    final m = await _map('assistantStatus');
    final sdk = m['sdk'];
    return NovaAssistantStatus(
      supported: m['supported'] == true,
      held: m['held'] == true,
      eligible: m['eligible'] == true,
      sdk: sdk is num ? sdk.toInt() : 0,
    );
  }

  @override
  Future<bool> openAssistantSettings() async {
    try {
      return await _channel.invokeMethod<bool>('openAssistantSettings') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<void> closeAssistant() => _call('closeAssistant');

  Future<void> _call(String method) async {
    try {
      await _channel.invokeMethod<void>(method);
    } on PlatformException {
      // ignore — best effort
    } on MissingPluginException {
      // ignore — channel unavailable (e.g. tests)
    }
  }
}
