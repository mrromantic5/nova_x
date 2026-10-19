// lib/features/nova/services/nova_voice.dart
//
// NOVA's spoken voice.
//
//  • NovaBrainsVoice — the Brains Jet voice API ("libby"), the voice NOVA X
//    used before. The reply text is sent to the voice service, which returns
//    an audio URL that is played with audioplayers. If the service fails or
//    is unreachable, the phone's own text-to-speech speaks instead.
//  • NovaNativeVoice — the phone's text-to-speech only (used by tests and as
//    the default when no voice is supplied).
//
// Completion: playback finished/stopped/failed is reported on [completed]
// with the utterance id. When the phone's voice is used, completion arrives
// as the usual NovaTtsEvent from NovaNative instead.

import 'dart:async';
import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:dio/dio.dart';

import 'nova_native.dart';
import 'nova_wake.dart';

abstract class NovaVoiceOutput {
  /// Starts speaking [text]. Returns false when nothing can be spoken.
  Future<bool> speak(String text, String utteranceId);

  /// Stops any speech (cloud playback and phone voice).
  Future<void> stop();

  /// Utterance ids whose cloud playback finished, was stopped or failed.
  Stream<String> get completed;

  void dispose();
}

/// Phone text-to-speech only.
class NovaNativeVoice implements NovaVoiceOutput {
  NovaNativeVoice(this._native);

  final NovaNativeApi _native;

  @override
  Future<bool> speak(String text, String utteranceId) => _native.speak(text, utteranceId);

  @override
  Future<void> stop() => _native.stopSpeaking();

  @override
  Stream<String> get completed => const Stream<String>.empty();

  @override
  void dispose() {}
}

/// Brains Jet voice ("libby"), with the phone's voice as fallback.
class NovaBrainsVoice implements NovaVoiceOutput {
  NovaBrainsVoice({required NovaNativeApi native, Dio? dio, AudioPlayer? player})
      : _native = native,
        _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 15),
            )),
        _player = player ?? AudioPlayer() {
    _completeSub = _player.onPlayerComplete.listen(
      (_) => _finish(_playingId),
      // A playback error ends the speech instead of surfacing as an uncaught error.
      onError: (Object _) => _finish(_playingId),
    );
  }

  static const String apiUrl = 'https://brains-tts.brainsjetai.workers.dev/';
  static const String voiceName = 'libby';

  /// The voice API is given at most this many characters (as before).
  static const int maxChars = 400;

  /// Longest wait for the voice to start before the phone's voice takes over.
  static const Duration startTimeout = Duration(seconds: 10);

  final NovaNativeApi _native;
  final Dio _dio;
  final AudioPlayer _player;
  final StreamController<String> _completed = StreamController<String>.broadcast();
  StreamSubscription<void>? _completeSub;
  CancelToken? _request;
  Timer? _guard;
  String? _playingId;
  int _generation = 0;
  bool _disposed = false;
  late final String _holdKey = 'voice${identityHashCode(this)}';

  @override
  Stream<String> get completed => _completed.stream;

  /// Text the voice API receives: plain, at most [maxChars], cut at a
  /// sentence end where possible.
  static String clip(String text) {
    final t = text
        .replaceAll(RegExp(r'[*#_`>|]+'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (t.length <= maxChars) return t;
    final cut = t.substring(0, maxChars);
    final end = cut.lastIndexOf(RegExp(r'[.!?](\s|$)'));
    return end > 80 ? cut.substring(0, end + 1) : cut;
  }

  @override
  Future<bool> speak(String text, String utteranceId) async {
    if (_disposed) return false;
    final clean = clip(text);
    if (clean.isEmpty) return false;
    // Claim this generation before stopping the old reply, so a late failure
    // of the old request can never fall back to speaking over the new one.
    final gen = ++_generation;
    await _stopPlayback();
    if (gen != _generation || _disposed) return false;
    final cancel = CancelToken();
    _request = cancel;
    try {
      final res = await _dio.get<dynamic>(
        apiUrl,
        queryParameters: {'q': clean, 'voicename': voiceName},
        cancelToken: cancel,
      ).timeout(startTimeout);
      if (gen != _generation || _disposed) return false; // stopped meanwhile
      final url = parseAudioUrl(res.data);
      if (url == null) throw const FormatException('no audio url');
      _playingId = utteranceId;
      // "Hey NOVA" steps aside while NOVA talks (so it never wakes itself).
      NovaWake.hold(_holdKey, true);
      await _player.play(UrlSource(url)).timeout(startTimeout);
      if (gen != _generation || _disposed) {
        if (!_disposed) await _player.stop();
        _finish(utteranceId);
        return false;
      }
      // A lost "complete" event must never leave NOVA stuck "speaking".
      final words = clean.split(' ').length;
      _guard?.cancel();
      _guard = Timer(Duration(milliseconds: 6000 + words * 500), () {
        if (_playingId == utteranceId) {
          _player.stop();
          _finish(utteranceId);
        }
      });
      return true;
    } catch (_) {
      cancel.cancel();
      if (_playingId == utteranceId) {
        NovaWake.hold(_holdKey, false);
        try {
          await _player.stop(); // a slow start must not play over the fallback
        } catch (_) {}
      }
      if (gen != _generation || _disposed) return false;
      _playingId = null;
      // Voice service unavailable — the phone's own voice speaks instead.
      return _native.speak(text, utteranceId);
    }
  }

  /// The audio URL from the voice API's reply (`{"url": "https://…"}`), or null.
  static String? parseAudioUrl(dynamic data) {
    dynamic body = data;
    if (body is String) {
      try {
        body = jsonDecode(body);
      } catch (_) {
        return null;
      }
    }
    if (body is Map) {
      final url = body['url'];
      if (url is String) {
        final uri = Uri.tryParse(url.trim());
        if (uri != null && (uri.scheme == 'https' || uri.scheme == 'http') && uri.host.isNotEmpty) {
          return uri.toString();
        }
      }
    }
    return null;
  }

  void _finish(String? id) {
    _guard?.cancel();
    _guard = null;
    if (id == null || id != _playingId) return;
    _playingId = null;
    NovaWake.hold(_holdKey, false);
    if (!_completed.isClosed) _completed.add(id);
  }

  Future<void> _stopPlayback() async {
    _request?.cancel();
    _request = null;
    final id = _playingId;
    if (id != null) {
      try {
        await _player.stop();
      } catch (_) {}
      _finish(id);
    }
  }

  @override
  Future<void> stop() async {
    _generation++;
    await _stopPlayback();
    await _native.stopSpeaking();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    _request?.cancel();
    _guard?.cancel();
    _completeSub?.cancel();
    if (_playingId != null) NovaWake.hold(_holdKey, false);
    _player.dispose();
    _dio.close(force: true);
    _completed.close();
  }
}
