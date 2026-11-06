// lib/features/playback/playback_engine.dart
//
// AI Playback (3.12.1): speaks the conversation.
//
// Voices: NOVA Voice (the same natural voices NOVA AI speaks with — Microsoft
// neural voices through the NOVA Voice Worker, no cost per use):
// Ava = a female voice, Leo = a male voice, in the page's language.
// Each line is turned into audio a few lines AHEAD of the one playing, so the
// next line is ready the moment the current one ends — no gaps. The intro
// starts playing the moment ▶ is tapped, while NOVA AI is still writing the
// conversation, so there is no silent wait at the start either.
//
// Real pause/resume, ±10 s and seeking inside a line, and speed (0.75–2×).
// If NOVA Voice can't be reached (offline, blocked), the phone's own
// text-to-speech voices take over from the current line.

import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path_provider/path_provider.dart';

import '../nova/nova_config.dart';
import 'playback_models.dart';

enum PlaybackPhase { preparing, ready, playing, paused, finished, error }

/// NOVA Voice voices per language: (Ava, Leo). The NOVA Voice Worker accepts
/// full Microsoft voice names.
class PlaybackCloudVoices {
  PlaybackCloudVoices._();

  static const Map<String, (String, String)> byLang = {
    'en': ('en-US-AvaNeural', 'en-US-AndrewNeural'),
    'fr': ('fr-FR-DeniseNeural', 'fr-FR-HenriNeural'),
    'es': ('es-ES-ElviraNeural', 'es-ES-AlvaroNeural'),
    'pt': ('pt-BR-FranciscaNeural', 'pt-BR-AntonioNeural'),
    'de': ('de-DE-KatjaNeural', 'de-DE-ConradNeural'),
    'it': ('it-IT-ElsaNeural', 'it-IT-DiegoNeural'),
    'nl': ('nl-NL-ColetteNeural', 'nl-NL-MaartenNeural'),
    'ar': ('ar-SA-ZariyahNeural', 'ar-SA-HamedNeural'),
    'hi': ('hi-IN-SwaraNeural', 'hi-IN-MadhurNeural'),
    'sw': ('sw-KE-ZuriNeural', 'sw-KE-RafikiNeural'),
    'zh': ('zh-CN-XiaoxiaoNeural', 'zh-CN-YunxiNeural'),
    'ja': ('ja-JP-NanamiNeural', 'ja-JP-KeitaNeural'),
    'ko': ('ko-KR-SunHiNeural', 'ko-KR-InJoonNeural'),
    'ru': ('ru-RU-SvetlanaNeural', 'ru-RU-DmitryNeural'),
    'tr': ('tr-TR-EmelNeural', 'tr-TR-AhmetNeural'),
    'pl': ('pl-PL-ZofiaNeural', 'pl-PL-MarekNeural'),
    'id': ('id-ID-GadisNeural', 'id-ID-ArdiNeural'),
    'uk': ('uk-UA-PolinaNeural', 'uk-UA-OstapNeural'),
    'vi': ('vi-VN-HoaiMyNeural', 'vi-VN-NamMinhNeural'),
    'th': ('th-TH-PremwadeeNeural', 'th-TH-NiwatNeural'),
    'bn': ('bn-IN-TanishaaNeural', 'bn-IN-BashkarNeural'),
    'ta': ('ta-IN-PallaviNeural', 'ta-IN-ValluvarNeural'),
    'ur': ('ur-PK-UzmaNeural', 'ur-PK-AsadNeural'),
    'fa': ('fa-IR-DilaraNeural', 'fa-IR-FaridNeural'),
    'ms': ('ms-MY-YasminNeural', 'ms-MY-OsmanNeural'),
  };

  /// Nigerian / Kenyan / … English pages get those accents.
  static const Map<String, (String, String)> englishByRegion = {
    'NG': ('en-NG-EzinneNeural', 'en-NG-AbeoNeural'),
    'KE': ('en-KE-AsiliaNeural', 'en-KE-ChilembaNeural'),
    'TZ': ('en-TZ-ImaniNeural', 'en-TZ-ElimuNeural'),
    'ZA': ('en-ZA-LeahNeural', 'en-ZA-LukeNeural'),
    'GB': ('en-GB-SoniaNeural', 'en-GB-RyanNeural'),
    'IE': ('en-IE-EmilyNeural', 'en-IE-ConnorNeural'),
    'AU': ('en-AU-NatashaNeural', 'en-AU-WilliamNeural'),
    'IN': ('en-IN-NeerjaNeural', 'en-IN-PrabhatNeural'),
    'CA': ('en-CA-ClaraNeural', 'en-CA-LiamNeural'),
  };

  static (String, String)? pick(String lang, String region) {
    if (lang == 'en' && englishByRegion.containsKey(region)) return englishByRegion[region];
    return byLang[lang];
  }
}

/// Picks a female and a male voice from the phone's own voices (fallback).
class PlaybackVoicePicker {
  PlaybackVoicePicker._();

  // Google speech engine voice codes (name contains e.g. "en-us-x-sfg-local").
  static const _googleFemale = {'sfg', 'iob', 'iog', 'tpc', 'tpf', 'gba', 'gbc', 'gbg', 'cxx', 'fra', 'frc', 'esc', 'esf', 'afh'};
  static const _googleMale = {'iol', 'iom', 'tpd', 'gbb', 'gbd', 'rjs', 'frb', 'frd', 'esd', 'ese'};

  /// 'f', 'm' or '' when the name doesn't say.
  static String genderOf(String name) {
    final n = name.toLowerCase();
    if (RegExp(r'female|woman|-f\d|#female').hasMatch(n)) return 'f';
    if (RegExp(r'(^|[^e])male|\bman\b|-m\d|#male').hasMatch(n)) return 'm';
    final code = RegExp(r'-x-([a-z]{3})').firstMatch(n)?.group(1);
    if (code != null && _googleFemale.contains(code)) return 'f';
    if (code != null && _googleMale.contains(code)) return 'm';
    return '';
  }

  static bool _offline(Map v) {
    final net = '${v['network_required'] ?? v['networkRequired'] ?? ''}'.toLowerCase();
    final name = '${v['name'] ?? ''}'.toLowerCase();
    return net == '0' || net == 'false' || name.endsWith('-local');
  }

  /// (female, male) voices for [lang] (e.g. "en"), preferring the region
  /// [region] (e.g. "US") and voices that work offline. Either can be null.
  static (Map<String, String>?, Map<String, String>?) pick(List<Object?> voices, String lang, {String region = ''}) {
    final mine = <Map<String, String>>[];
    for (final v in voices) {
      if (v is! Map) continue;
      final name = '${v['name'] ?? ''}', locale = '${v['locale'] ?? ''}';
      if (name.isEmpty || locale.isEmpty) continue;
      final l = locale.toLowerCase().replaceAll('_', '-');
      if (l == lang || l.startsWith('$lang-')) {
        mine.add({'name': name, 'locale': locale, 'offline': _offline(v) ? '1' : '0'});
      }
    }
    int score(Map<String, String> v) {
      var s = 0;
      if (v['offline'] == '1') s += 2;
      if (region.isNotEmpty && v['locale']!.toLowerCase().replaceAll('_', '-').endsWith('-${region.toLowerCase()}')) s += 3;
      return s;
    }

    mine.sort((a, b) => score(b).compareTo(score(a)));
    Map<String, String>? female, male;
    for (final v in mine) {
      final g = genderOf(v['name']!);
      if (g == 'f') female ??= v;
      if (g == 'm') male ??= v;
    }
    female ??= mine.where((v) => v != male).firstOrNull;
    male ??= mine.where((v) => v != female).firstOrNull;
    Map<String, String>? strip(Map<String, String>? v) => v == null ? null : {'name': v['name']!, 'locale': v['locale']!};
    return (strip(female), strip(male));
  }
}

class PlaybackEngine extends ChangeNotifier {
  PlaybackEngine({Dio? dio}) : _dio = dio ?? Dio(BaseOptions(connectTimeout: const Duration(seconds: 8), receiveTimeout: const Duration(seconds: 25)));

  final Dio _dio;
  final AudioPlayer _player = AudioPlayer();
  FlutterTts? _tts; // only when NOVA Voice can't be reached

  PlaybackPhase phase = PlaybackPhase.preparing;
  PlaybackScript? script;
  String? error;
  int index = 0;
  double speed = 1.0;
  int? feedback; // 1 = 👍, -1 = 👎

  /// The whole conversation has arrived (until then only the intro exists).
  bool _complete = false;

  /// Waiting for the next line's audio (or the rest of the conversation).
  bool buffering = false;

  // NOVA Voice
  bool _cloud = true;
  (String, String)? _cloudVoices;
  final Map<int, Future<String?>> _files = {};
  final Map<int, double> _durations = {}; // real line lengths (s, normal speed)
  double _linePos = 0; // seconds into the current line (normal speed)
  final List<StreamSubscription<Object?>> _subs = [];
  CancelToken _cancel = CancelToken();

  // phone voices (fallback)
  Map<String, String>? _female, _male;
  bool _sameVoice = false;
  DateTime? _lineStartedAt;

  String _lang = 'en';
  String _region = '';
  int _gen = 0;
  Timer? _tick;
  bool _disposed = false;

  bool get isPlaying => phase == PlaybackPhase.playing;
  bool get usesNovaVoice => _cloud;
  PlaybackLine? get current => script == null || index >= script!.lines.length ? null : script!.lines[index];

  double _len(int i) => _durations[i] ?? script!.lines[i].seconds;

  double _startOf(int i) {
    var t = 0.0;
    for (var k = 0; k < i; k++) {
      t += _len(k);
    }
    return t;
  }

  /// Estimated total in seconds (shown at the current speed).
  double get total {
    final s = script;
    if (s == null) return 0;
    var t = 0.0;
    for (var i = 0; i < s.lines.length; i++) {
      t += _len(i);
    }
    return t / speed;
  }

  /// Position in seconds (shown at the current speed).
  double get position {
    final s = script;
    if (s == null) return 0;
    if (phase == PlaybackPhase.finished) return total;
    final i = index.clamp(0, s.lines.length - 1);
    var into = _linePos;
    if (!_cloud) {
      final at = _lineStartedAt;
      into = isPlaying && at != null ? DateTime.now().difference(at).inMilliseconds / 1000 * speed : 0.0;
    }
    return (_startOf(i) + into.clamp(0.0, _len(i))) / speed;
  }

  // ── Setup ────────────────────────────────────────────────────────────────

  /// Chooses the voices. Returns the language the conversation should be
  /// written in: the page's language when NOVA Voice has voices for it,
  /// otherwise English.
  Future<String> prepare(String pageLang) async {
    final parts = pageLang.toLowerCase().replaceAll('_', '-').split('-');
    var lang = RegExp(r'^[a-z]{2,3}$').hasMatch(parts.first) ? parts.first : 'en';
    _region = parts.length > 1 ? parts[1].toUpperCase() : '';
    if (PlaybackCloudVoices.pick(lang, _region) == null) lang = 'en';
    _lang = lang;
    _cloudVoices = PlaybackCloudVoices.pick(lang, _region);
    _subs.add(_player.onPlayerComplete.listen((_) => _onLineDone()));
    _subs.add(_player.onPositionChanged.listen((d) {
      _linePos = d.inMilliseconds / 1000; // media time = normal speed
    }));
    _subs.add(_player.onDurationChanged.listen((d) {
      if (d.inMilliseconds > 0) _durations[index] = d.inMilliseconds / 1000;
    }));
    try {
      await _player.setReleaseMode(ReleaseMode.stop);
    } catch (_) {}
    return lang;
  }

  /// Plays the intro straight away while NOVA AI writes the conversation.
  void startIntro() {
    script = PlaybackScript(title: '', host: '', lang: _lang, lines: [PlaybackLine(female: false, text: PlaybackScript.introFor(_lang))]);
    index = 0;
    _complete = false;
    phase = PlaybackPhase.playing;
    _startTicker();
    _playIndex(0);
  }

  /// The conversation has arrived (its first line is the intro).
  void start(PlaybackScript s) {
    // Did the intro start (startIntro) before the conversation arrived?
    final introStarted = script != null && !_complete && phase != PlaybackPhase.error;
    final waiting = buffering && index >= 1; // the intro already ended
    script = s;
    _complete = true;
    error = null;
    for (var i = 1; i < s.lines.length && i <= 4; i++) {
      _prefetch(i);
    }
    if (introStarted) {
      if (waiting && phase == PlaybackPhase.playing) _playIndex(index);
      _notify();
      return;
    }
    index = 0;
    play();
  }

  void fail(String message) {
    error = message;
    phase = PlaybackPhase.error;
    buffering = false;
    _halt();
    _notify();
  }

  // ── Controls ─────────────────────────────────────────────────────────────

  void play() {
    final s = script;
    if (s == null || _disposed) return;
    if (phase == PlaybackPhase.finished || index >= s.lines.length) {
      index = 0;
      _linePos = 0;
    }
    final resume = phase == PlaybackPhase.paused && _cloud && _linePos > 0.05 && _pendingOffset == 0;
    final offset = _pendingOffset;
    _pendingOffset = 0;
    phase = PlaybackPhase.playing;
    _startTicker();
    if (resume) {
      _player.resume().catchError((_) => _playIndex(index));
      _notify();
    } else {
      _playIndex(index, offset: offset);
    }
  }

  Future<void> pause() async {
    if (!isPlaying && !buffering) return;
    _gen++; // a line still downloading must not start playing
    phase = PlaybackPhase.paused;
    buffering = false;
    _stopTicker();
    _notify();
    if (_cloud) {
      try {
        await _player.pause();
      } catch (_) {}
    } else {
      _gen++;
      await _ttsStop();
    }
  }

  void toggle() {
    if (isPlaying || buffering) {
      pause();
    } else {
      play();
    }
  }

  /// Jumps to the place playing at [seconds] (as shown, at this speed).
  Future<void> seekTo(double seconds) async {
    final s = script;
    if (s == null) return;
    final target = (seconds * speed).clamp(0.0, total * speed);
    var line = s.lines.length - 1;
    for (var i = 0; i < s.lines.length; i++) {
      if (target < _startOf(i) + _len(i)) {
        line = i;
        break;
      }
    }
    final offset = _cloud ? target - _startOf(line) : 0.0;
    final was = isPlaying || buffering || phase == PlaybackPhase.finished;
    if (line == index && _cloud && phase != PlaybackPhase.finished && _durations.containsKey(line)) {
      _linePos = offset;
      try {
        await _player.seek(Duration(milliseconds: (offset * 1000).round()));
      } catch (_) {}
      if (was && !isPlaying) play();
      _notify();
      return;
    }
    await seekLine(line, offset: offset, keepPlaying: was);
  }

  /// −10 s / +10 s.
  Future<void> skip(double seconds) async {
    if (!_cloud) {
      // phone voices can only start whole lines
      final cur = index;
      final s = script;
      if (s == null) return;
      await seekLine((seconds < 0 ? cur - 1 : cur + 1).clamp(0, s.lines.length - 1), keepPlaying: isPlaying || buffering);
      return;
    }
    await seekTo((position + seconds).clamp(0.0, total));
  }

  Future<void> seekLine(int i, {double offset = 0, bool? keepPlaying}) async {
    final s = script;
    if (s == null) return;
    final was = keepPlaying ?? (isPlaying || buffering || phase == PlaybackPhase.finished);
    _gen++;
    await _halt();
    index = i.clamp(0, s.lines.length - 1);
    _linePos = 0;
    if (was) {
      phase = PlaybackPhase.playing;
      _startTicker();
      _playIndex(index, offset: offset);
    } else {
      phase = PlaybackPhase.paused;
      _pendingOffset = offset;
      _notify();
    }
  }

  double _pendingOffset = 0;

  Future<void> setSpeed(double v) async {
    speed = v;
    if (_cloud) {
      try {
        await _player.setPlaybackRate(v);
      } catch (_) {}
      _notify();
    } else {
      try {
        await _tts?.setSpeechRate((0.5 * v).clamp(0.1, 1.0));
      } catch (_) {}
      if (isPlaying) {
        await seekLine(index, keepPlaying: true);
      } else {
        _notify();
      }
    }
  }

  void rate(int v) {
    feedback = feedback == v ? null : v;
    _notify();
  }

  // ── NOVA Voice ───────────────────────────────────────────────────────────

  Future<String?> _fetch(int i) async {
    final s = script;
    final v = _cloudVoices;
    if (s == null || v == null || i >= s.lines.length) return null;
    final l = s.lines[i];
    final voice = l.female ? v.$1 : v.$2;
    final dir = await getTemporaryDirectory();
    // The intro is the same every time: keep it, so it starts instantly.
    final name = 'nx_playback_${voice}_${l.text.hashCode.toUnsigned(32)}.mp3';
    final file = File('${dir.path}/$name');
    if (await file.exists() && await file.length() > 500) return file.path;
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final res = await _dio.post<List<int>>(
          '${NovaConfig.voiceApiBaseUrl}/',
          data: {'q': l.text, 'voicename': voice, 'format': 'mp3'},
          options: Options(responseType: ResponseType.bytes, contentType: 'application/json'),
          cancelToken: _cancel,
        );
        final bytes = res.data;
        final type = res.headers.value('content-type') ?? '';
        if (bytes != null && bytes.length > 500 && type.contains('audio')) {
          await file.writeAsBytes(bytes, flush: true);
          return file.path;
        }
      } on DioException catch (e) {
        if (e.type == DioExceptionType.cancel) return null;
      } catch (_) {}
    }
    return null;
  }

  Future<String?> _prefetch(int i) {
    final s = script;
    if (s == null || i < 0 || i >= s.lines.length) return Future.value(null);
    return _files[i] ??= _fetch(i);
  }

  Future<void> _playIndex(int i, {double offset = 0}) async {
    final g = ++_gen;
    final s = script;
    if (s == null || _disposed) return;
    if (i >= s.lines.length) {
      if (!_complete) {
        buffering = true; // the intro ended before the conversation arrived
        _notify();
      } else {
        _finish();
      }
      return;
    }
    if (!_cloud) return _speakPhone(i, g);
    for (var k = i + 1; k <= i + 4 && k < s.lines.length; k++) {
      _prefetch(k); // keep the next lines ready → no gaps
    }
    final ready = _files[i];
    if (ready == null) {
      buffering = true;
      _notify();
    }
    final path = await _prefetch(i);
    if (g != _gen || _disposed || !isPlaying) return;
    if (path == null) {
      await _switchToPhone(i);
      return;
    }
    buffering = false;
    _linePos = offset;
    try {
      await _player.setPlaybackRate(speed);
      await _player.play(DeviceFileSource(path),
          position: offset > 0.3 ? Duration(milliseconds: (offset * 1000).round()) : null);
    } catch (_) {
      if (g == _gen) await _switchToPhone(i);
      return;
    }
    _notify();
  }

  void _onLineDone() {
    if (_disposed || !_cloud || !isPlaying) return;
    final s = script;
    if (s == null) return;
    _durations[index] = _durations[index] ?? _linePos;
    _linePos = 0;
    index++;
    _playIndex(index);
  }

  void _finish() {
    final s = script;
    phase = PlaybackPhase.finished;
    buffering = false;
    if (s != null) index = s.lines.length - 1;
    _stopTicker();
    _notify();
  }

  Future<void> _halt() async {
    try {
      await _player.stop();
    } catch (_) {}
    await _ttsStop();
  }

  // ── Phone voices (fallback) ──────────────────────────────────────────────

  Future<void> _switchToPhone(int from) async {
    if (!_cloud) return;
    _cloud = false;
    try {
      final tts = _tts ??= FlutterTts();
      await tts.awaitSpeakCompletion(true);
      final voices = (await tts.getVoices) as List? ?? const [];
      final (f, m) = PlaybackVoicePicker.pick(voices.cast<Object?>(), _lang, region: _region);
      _female = f;
      _male = m;
      _sameVoice = f == null || m == null || f['name'] == m['name'];
      await tts.setLanguage((f ?? m)?['locale'] ?? (_lang == 'en' ? 'en-US' : _lang));
      await tts.setSpeechRate((0.5 * speed).clamp(0.1, 1.0));
    } catch (_) {
      _sameVoice = true;
    }
    if (isPlaying || buffering) _playIndex(from);
  }

  Future<void> _speakPhone(int i, int g) async {
    final s = script!;
    final tts = _tts;
    if (tts == null) return;
    var k = i;
    while (g == _gen && !_disposed && k < s.lines.length) {
      final l = s.lines[k];
      index = k;
      buffering = false;
      try {
        final v = l.female ? _female : _male;
        if (v != null) await tts.setVoice(v);
        await tts.setPitch(_sameVoice ? (l.female ? 1.18 : 0.82) : 1.0);
        if (g != _gen) return;
        _lineStartedAt = DateTime.now();
        _notify();
        await tts.speak(l.text);
      } catch (_) {
        if (g == _gen) fail('The voice couldn’t play. Check your connection or Settings › Text-to-speech.');
        return;
      }
      if (g != _gen || _disposed) return;
      _durations[k] = DateTime.now().difference(_lineStartedAt!).inMilliseconds / 1000 * speed;
      k++;
    }
    if (g != _gen || _disposed) return;
    if (k >= s.lines.length) {
      if (_complete) {
        _finish();
      } else {
        index = k;
        buffering = true;
        _notify();
      }
    }
  }

  Future<void> _ttsStop() async {
    try {
      await _tts?.stop();
    } catch (_) {}
  }

  // ── Misc ─────────────────────────────────────────────────────────────────

  void _startTicker() {
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(milliseconds: 400), (_) => _notify());
  }

  void _stopTicker() {
    _tick?.cancel();
    _tick = null;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Stops for good and frees the player.
  @override
  void dispose() {
    _disposed = true;
    _gen++;
    _stopTicker();
    _cancel.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    _player.stop().catchError((_) {}).whenComplete(() => _player.dispose());
    _ttsStop();
    _dio.close(force: true);
    super.dispose();
  }
}
