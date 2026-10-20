// lib/features/nova/services/nova_voice.dart
//
// NOVA's spoken voice.
//
//  • NovaCloudVoice — NOVA Voice (Tech Lyfe's Edge TTS Worker): natural
//    voices the user picks in NOVA settings → Voice. The text is sent to the
//    NOVA Voice service, which returns MP3 audio; the file is played by
//    Android (NovaVoicePlayer) and deleted afterwards. Long texts are spoken
//    in parts so NOVA starts talking quickly. If the service can't be
//    reached (e.g. offline), the phone's own text-to-speech speaks instead.
//  • NovaNativeVoice — the phone's text-to-speech only (tests, fallback).
//
// Completion: when the cloud voice finishes, is stopped or fails, the
// utterance id is reported on [completed]. When the phone's voice is used,
// completion arrives as the usual NovaTtsEvent from NovaNative instead.

import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../models/nova_models.dart';
import '../nova_config.dart';
import 'nova_native.dart';

abstract class NovaVoiceOutput {
  /// Starts speaking [text]. Returns false when nothing can be spoken.
  Future<bool> speak(String text, String utteranceId);

  /// Stops any speech (cloud voice and phone voice).
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

/// One NOVA Voice option.
class NovaVoiceInfo {
  const NovaVoiceInfo(this.key, this.gender, this.accent, this.region);

  /// Short name used by the NOVA Voice service (e.g. "libby").
  final String key;

  /// female · male
  final String gender;

  /// Where the accent is from, e.g. "Nigeria".
  final String accent;

  /// Group shown in settings.
  final String region;

  String get label => key.isEmpty ? key : key[0].toUpperCase() + key.substring(1);

  String get description => '${gender == 'female' ? 'Female' : 'Male'} · $accent';
}

/// Every voice offered by the NOVA Voice service (backend/nova-voice-worker).
class NovaVoiceCatalog {
  NovaVoiceCatalog._();

  static const String defaultVoice = NovaSettings.defaultVoice;

  static const List<String> regions = [
    'Africa',
    'United Kingdom & Ireland',
    'United States & Canada',
    'Asia-Pacific',
  ];

  static const List<NovaVoiceInfo> voices = [
    NovaVoiceInfo('ezinne', 'female', 'Nigeria', 'Africa'),
    NovaVoiceInfo('abeo', 'male', 'Nigeria', 'Africa'),
    NovaVoiceInfo('asilia', 'female', 'Kenya', 'Africa'),
    NovaVoiceInfo('chilemba', 'male', 'Kenya', 'Africa'),
    NovaVoiceInfo('imani', 'female', 'Tanzania', 'Africa'),
    NovaVoiceInfo('elimu', 'male', 'Tanzania', 'Africa'),
    NovaVoiceInfo('leah', 'female', 'South Africa', 'Africa'),
    NovaVoiceInfo('luke', 'male', 'South Africa', 'Africa'),
    NovaVoiceInfo('libby', 'female', 'United Kingdom', 'United Kingdom & Ireland'),
    NovaVoiceInfo('sonia', 'female', 'United Kingdom', 'United Kingdom & Ireland'),
    NovaVoiceInfo('ryan', 'male', 'United Kingdom', 'United Kingdom & Ireland'),
    NovaVoiceInfo('thomas', 'male', 'United Kingdom', 'United Kingdom & Ireland'),
    NovaVoiceInfo('emily', 'female', 'Ireland', 'United Kingdom & Ireland'),
    NovaVoiceInfo('connor', 'male', 'Ireland', 'United Kingdom & Ireland'),
    NovaVoiceInfo('jenny', 'female', 'United States', 'United States & Canada'),
    NovaVoiceInfo('lisa', 'female', 'United States', 'United States & Canada'),
    NovaVoiceInfo('jane', 'female', 'United States', 'United States & Canada'),
    NovaVoiceInfo('nancy', 'female', 'United States', 'United States & Canada'),
    NovaVoiceInfo('amber', 'female', 'United States', 'United States & Canada'),
    NovaVoiceInfo('sara', 'female', 'United States', 'United States & Canada'),
    NovaVoiceInfo('guy', 'male', 'United States', 'United States & Canada'),
    NovaVoiceInfo('tony', 'male', 'United States', 'United States & Canada'),
    NovaVoiceInfo('andrew', 'male', 'United States', 'United States & Canada'),
    NovaVoiceInfo('brian', 'male', 'United States', 'United States & Canada'),
    NovaVoiceInfo('eric', 'male', 'United States', 'United States & Canada'),
    NovaVoiceInfo('clara', 'female', 'Canada', 'United States & Canada'),
    NovaVoiceInfo('liam', 'male', 'Canada', 'United States & Canada'),
    NovaVoiceInfo('natasha', 'female', 'Australia', 'Asia-Pacific'),
    NovaVoiceInfo('william', 'male', 'Australia', 'Asia-Pacific'),
    NovaVoiceInfo('molly', 'female', 'New Zealand', 'Asia-Pacific'),
    NovaVoiceInfo('mitchell', 'male', 'New Zealand', 'Asia-Pacific'),
    NovaVoiceInfo('neerja', 'female', 'India', 'Asia-Pacific'),
    NovaVoiceInfo('prabhat', 'male', 'India', 'Asia-Pacific'),
    NovaVoiceInfo('luna', 'female', 'Singapore', 'Asia-Pacific'),
    NovaVoiceInfo('rosa', 'female', 'Philippines', 'Asia-Pacific'),
  ];

  /// The 13 voices every version of the NOVA Voice service has.
  static const Set<String> original = {
    'lisa', 'jane', 'jenny', 'nancy', 'amber', 'sara', 'guy', 'tony',
    'sonia', 'libby', 'ryan', 'natasha', 'william',
  };

  static NovaVoiceInfo? byKey(String key) {
    for (final v in voices) {
      if (v.key == key) return v;
    }
    return null;
  }

  static bool isKnown(String key) => byKey(key) != null;
}

/// The voice NOVA uses right now (loaded from NOVA settings by NovaPrefs).
class NovaVoiceSelection {
  NovaVoiceSelection._();

  static String current = NovaSettings.defaultVoice;
}

/// NOVA Voice through the Edge TTS Worker, with the phone's voice as backup.
class NovaCloudVoice implements NovaVoiceOutput {
  NovaCloudVoice({
    required NovaNativeApi native,
    Dio? dio,
    String Function()? voiceName,
    this.fallbackToPhone = true,
  })  : _native = native,
        _voiceName = voiceName ?? (() => NovaVoiceSelection.current),
        _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 8),
              sendTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 20),
            )) {
    _events = _native.events.listen(_onNativeEvent);
  }

  static const MethodChannel _channel = MethodChannel('com.tlyfe.nova_x/nova');

  /// Longest wait for the first part before the phone's voice takes over.
  static const Duration startTimeout = Duration(seconds: 10);

  /// Short first part so NOVA starts talking quickly; larger parts after.
  static const int firstPartChars = 260;
  static const int partChars = 900;

  /// The service accepts up to 5000 characters per request.
  static const int maxChars = 4800;

  /// When false (voice preview), nothing is spoken if the voice service fails.
  final bool fallbackToPhone;

  final NovaNativeApi _native;
  final String Function() _voiceName;
  final Dio _dio;
  late final StreamSubscription<NovaNativeEvent> _events;
  final StreamController<String> _completed = StreamController<String>.broadcast();

  int _generation = 0;
  bool _disposed = false;
  String? _utterance;
  List<String> _parts = const [];
  int _index = 0;
  final Map<int, Future<String?>> _files = {};
  CancelToken? _cancel;
  Timer? _guard;

  @override
  Stream<String> get completed => _completed.stream;

  /// Plain text for speaking (no code blocks or markdown symbols).
  static String cleanForSpeech(String text) => text
      .replaceAll(RegExp(r'```[\s\S]*?```'), ' ')
      .replaceAll(RegExp(r'[*#_`>|~]+'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// Splits [text] at sentence ends into parts no longer than [first] (the
  /// first part) and [rest] characters. Text beyond [maxChars] is dropped.
  static List<String> parts(String text, {int first = firstPartChars, int rest = partChars}) {
    var t = text.trim();
    if (t.length > maxChars) t = t.substring(0, maxChars);
    final out = <String>[];
    while (t.isNotEmpty) {
      final limit = out.isEmpty ? first : rest;
      if (t.length <= limit) {
        out.add(t);
        break;
      }
      var cut = _lastSentenceEnd(t, limit);
      if (cut <= limit ~/ 3) cut = t.lastIndexOf(' ', limit);
      if (cut <= 0) cut = limit;
      final head = t.substring(0, cut).trim();
      if (head.isNotEmpty) out.add(head);
      t = t.substring(cut).trim();
    }
    return out;
  }

  static int _lastSentenceEnd(String t, int limit) {
    var best = -1;
    for (final m in RegExp(r'[.!?;:](?=\s)').allMatches(t)) {
      if (m.end > limit) break;
      best = m.end;
    }
    return best;
  }

  /// Voice names the NOVA Voice service offers right now (null if unreachable).
  static Future<Set<String>?> availableVoices({Dio? dio}) async {
    final client = dio ??
        Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 15),
        ));
    try {
      final res = await client.get<dynamic>('${NovaConfig.voiceApiBaseUrl}/voices');
      final data = res.data;
      final voices = data is Map ? data['voices'] : null;
      if (voices is Map) return voices.keys.whereType<String>().toSet();
      return null;
    } catch (_) {
      return null;
    } finally {
      if (dio == null) client.close(force: true);
    }
  }

  @override
  Future<bool> speak(String text, String utteranceId) async {
    if (_disposed) return false;
    final list = parts(cleanForSpeech(text));
    if (list.isEmpty) return false;
    final gen = ++_generation;
    await _stopCloud();
    if (gen != _generation || _disposed) return false;
    _utterance = utteranceId;
    _parts = list;
    _index = 0;
    final cancel = CancelToken();
    _cancel = cancel;
    try {
      final first = await _fetch(list.first, 0, gen, cancel).timeout(startTimeout);
      if (gen != _generation || _disposed) {
        _deleteFile(first);
        return false;
      }
      if (first == null) throw StateError('no audio');
      if (!await _play(first, 0)) throw StateError('playback failed');
      _prefetch(1, gen, cancel);
      return true;
    } catch (_) {
      if (gen != _generation || _disposed) return false;
      _generation++; // a late download must not be saved or played
      cancel.cancel();
      _clear();
      if (!fallbackToPhone) return false;
      // Voice service unreachable (offline?) — the phone's own voice speaks.
      return _native.speak(text, utteranceId);
    }
  }

  @override
  Future<void> stop() async {
    _generation++;
    await _stopCloud();
    await _native.stopSpeaking();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    final speaking = _utterance != null;
    _cancel?.cancel();
    _clear();
    if (speaking) _invoke('stopVoiceFile');
    _events.cancel();
    _dio.close(force: true);
    _completed.close();
  }

  // ── Internals ───────────────────────────────────────────────────────────

  String _partId(int index) => '${_utterance ?? 'nova'}#$index';

  Future<String?> _fetch(String part, int index, int gen, CancelToken cancel) async {
    final res = await _dio.post<List<int>>(
      '${NovaConfig.voiceApiBaseUrl}/',
      data: {'q': part, 'voicename': _voiceName(), 'format': 'mp3'},
      options: Options(responseType: ResponseType.bytes, contentType: 'application/json'),
      cancelToken: cancel,
    );
    final bytes = res.data;
    final type = res.headers.value('content-type') ?? '';
    if (bytes == null || bytes.length < 200 || !type.contains('audio')) return null;
    if (gen != _generation || _disposed) return null;
    final dir = await getTemporaryDirectory();
    final safeId = (_utterance ?? 'nova').replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final file = File('${dir.path}/nova_voice_${safeId}_${gen}_$index.mp3');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<String?> _safeFetch(String part, int index, int gen, CancelToken cancel) async {
    try {
      return await _fetch(part, index, gen, cancel);
    } catch (_) {
      return null;
    }
  }

  void _prefetch(int index, int gen, CancelToken? cancel) {
    if (cancel == null || index >= _parts.length || _files.containsKey(index)) return;
    _files[index] = _safeFetch(_parts[index], index, gen, cancel);
  }

  Future<bool> _play(String path, int index) async {
    final id = _partId(index);
    try {
      final ok = await _channel.invokeMethod<bool>('playVoiceFile', {'path': path, 'id': id});
      if (ok != true) {
        _deleteFile(path);
        return false;
      }
    } on PlatformException {
      _deleteFile(path);
      return false;
    } on MissingPluginException {
      _deleteFile(path);
      return false;
    }
    _index = index;
    _armGuard(index);
    return true;
  }

  /// A lost "done" event must never leave NOVA stuck "speaking".
  void _armGuard(int index) {
    _guard?.cancel();
    final words = index < _parts.length ? _parts[index].split(' ').length : 10;
    _guard = Timer(Duration(milliseconds: 6000 + words * 450), () => _onPartDone(index));
  }

  void _onNativeEvent(NovaNativeEvent e) {
    if (e is! NovaTtsEvent || e.kind == 'start') return;
    if (_utterance == null || e.utteranceId != _partId(_index)) return;
    if (e.kind == 'error') {
      // Stopped early (another NOVA screen started talking) or failed.
      final u = _utterance!;
      _cancel?.cancel();
      _clear();
      _emitDone(u);
      return;
    }
    _onPartDone(_index);
  }

  Future<void> _onPartDone(int index) async {
    _guard?.cancel();
    final u = _utterance;
    if (u == null || index != _index) return;
    final next = index + 1;
    if (next >= _parts.length) {
      _clear();
      _emitDone(u);
      return;
    }
    final gen = _generation;
    final cancel = _cancel;
    _prefetch(next, gen, cancel);
    _prefetch(next + 1, gen, cancel);
    final pending = _files.remove(next);
    final path = pending == null ? null : await pending;
    if (gen != _generation || _disposed || _utterance != u) {
      _deleteFile(path);
      return;
    }
    if (path != null && await _play(path, next)) return;
    // The rest is spoken with the phone's voice; Android reports completion with id [u].
    final rest = _parts.sublist(next).join(' ');
    _cancel?.cancel();
    _clear();
    if (!fallbackToPhone || !await _native.speak(rest, u)) _emitDone(u);
  }

  Future<void> _stopCloud() async {
    final u = _utterance;
    _cancel?.cancel();
    _clear();
    if (u != null) {
      await _invoke('stopVoiceFile');
      _emitDone(u);
    }
  }

  void _clear() {
    _guard?.cancel();
    _guard = null;
    for (final f in _files.values) {
      f.then(_deleteFile);
    }
    _files.clear();
    _utterance = null;
    _parts = const [];
    _index = 0;
    _cancel = null;
  }

  void _emitDone(String id) {
    if (!_completed.isClosed) _completed.add(id);
  }

  static void _deleteFile(String? path) {
    if (path == null) return;
    try {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {
      // best effort — the file lives in the app cache
    }
  }

  static Future<void> _invoke(String method) async {
    try {
      await _channel.invokeMethod<void>(method);
    } on PlatformException {
      // ignore — best effort
    } on MissingPluginException {
      // ignore — no channel (tests)
    }
  }
}
