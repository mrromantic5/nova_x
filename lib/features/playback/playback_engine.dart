// lib/features/playback/playback_engine.dart
//
// AI Playback (3.12.0): speaks the conversation with the phone's own
// text-to-speech voices — a female voice for Ava and a male voice for Leo,
// one line at a time. Free, and the voices themselves work offline.
//
// Android's speech engine can't pause in the middle of a sentence or jump
// to a time inside it, so pause/seek work per line: pausing stops the line
// and Play starts it again; ±10 s and the progress bar jump to the line at
// that time. Times are estimated from the number of words.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'playback_models.dart';

enum PlaybackPhase { preparing, ready, playing, paused, finished, error }

/// Picks a female and a male voice from what the phone has.
class PlaybackVoicePicker {
  PlaybackVoicePicker._();

  // Google speech engine voice codes (name contains e.g. "en-us-x-sfg-local").
  static const _googleFemale = {'sfg', 'iob', 'iog', 'tpc', 'tpf', 'gba', 'gbc', 'gbg', 'cxx', 'fra', 'frc', 'esc', 'esf', 'afh'};
  static const _googleMale = {'iol', 'iom', 'tpd', 'gbb', 'gbd', 'rjs', 'frb', 'frd', 'esd', 'ese'};

  /// 'f', 'm' or '' when the name doesn't say.
  static String genderOf(String name) {
    final n = name.toLowerCase();
    if (RegExp(r'female|woman|\bwoman\b|-f\d|#female').hasMatch(n)) return 'f';
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
    // Names that don't say: take two different voices so the hosts differ.
    female ??= mine.where((v) => v != male).firstOrNull;
    male ??= mine.where((v) => v != female).firstOrNull;
    Map<String, String>? strip(Map<String, String>? v) => v == null ? null : {'name': v['name']!, 'locale': v['locale']!};
    return (strip(female), strip(male));
  }
}

class PlaybackEngine extends ChangeNotifier {
  PlaybackEngine({FlutterTts? tts}) : _tts = tts ?? FlutterTts();

  final FlutterTts _tts;
  PlaybackPhase phase = PlaybackPhase.preparing;
  PlaybackScript? script;
  String? error;
  int index = 0;
  double speed = 1.0;
  int? feedback; // 1 = 👍, -1 = 👎

  Map<String, String>? _female, _male;
  bool _sameVoice = false;
  int _gen = 0;
  DateTime? _lineStartedAt;
  Timer? _tick;
  bool _disposed = false;

  bool get isPlaying => phase == PlaybackPhase.playing;
  PlaybackLine? get current => script == null || index >= script!.lines.length ? null : script!.lines[index];

  /// Estimated position in seconds (shown with the current speed).
  double get position {
    final s = script;
    if (s == null) return 0;
    if (phase == PlaybackPhase.finished) return total;
    final starts = s.starts;
    final i = index.clamp(0, s.lines.length - 1);
    var p = starts[i];
    final at = _lineStartedAt;
    if (isPlaying && at != null) {
      final spoken = DateTime.now().difference(at).inMilliseconds / 1000 * speed;
      p += spoken.clamp(0.0, s.lines[i].seconds);
    }
    return p / speed;
  }

  double get total => (script?.totalSeconds ?? 0) / speed;

  /// Sets up the speech engine. Returns the language the conversation should
  /// be written in: the page's language when the phone can speak it,
  /// otherwise English.
  Future<String> prepare(String pageLang) async {
    final parts = pageLang.toLowerCase().replaceAll('_', '-').split('-');
    var lang = RegExp(r'^[a-z]{2,3}$').hasMatch(parts.first) ? parts.first : 'en';
    final region = parts.length > 1 ? parts[1].toUpperCase() : '';
    try {
      await _tts.awaitSpeakCompletion(true);
      final voices = (await _tts.getVoices) as List? ?? const [];
      var (f, m) = PlaybackVoicePicker.pick(voices.cast<Object?>(), lang, region: region);
      if (f == null && m == null && lang != 'en') {
        lang = 'en';
        (f, m) = PlaybackVoicePicker.pick(voices.cast<Object?>(), 'en', region: 'US');
      }
      _female = f;
      _male = m;
      _sameVoice = f == null || m == null || f['name'] == m['name'];
      final locale = (f ?? m)?['locale'] ?? (lang == 'en' ? 'en-US' : lang);
      await _tts.setLanguage(locale);
      await _tts.setSpeechRate(_rate);
      await _tts.setVolume(1.0);
    } catch (_) {
      // No voices list: the default voice speaks both hosts (pitch differs).
      _sameVoice = true;
    }
    return lang;
  }

  // flutter_tts on Android: 0.5 is normal speed.
  double get _rate => (0.5 * speed).clamp(0.1, 1.0);

  Future<void> _voiceFor(PlaybackLine l) async {
    final v = l.female ? _female : _male;
    if (v != null) {
      try {
        await _tts.setVoice(v);
      } catch (_) {}
    }
    // Same voice for both: pitch tells them apart. Different voices: natural.
    await _tts.setPitch(_sameVoice ? (l.female ? 1.18 : 0.82) : (l.female ? 1.04 : 0.96));
  }

  void start(PlaybackScript s) {
    script = s;
    index = 0;
    error = null;
    play();
  }

  void fail(String message) {
    error = message;
    phase = PlaybackPhase.error;
    _notify();
  }

  void play() {
    final s = script;
    if (s == null || _disposed) return;
    if (phase == PlaybackPhase.finished || index >= s.lines.length) index = 0;
    phase = PlaybackPhase.playing;
    _startTicker();
    _run();
  }

  Future<void> pause() async {
    if (!isPlaying) return;
    _gen++;
    phase = PlaybackPhase.paused;
    _stopTicker();
    _notify();
    await _safeStop();
  }

  void toggle() {
    if (isPlaying) {
      pause();
    } else {
      play();
    }
  }

  /// Jumps to line [i] (keeps playing if it was playing).
  Future<void> seekLine(int i) async {
    final s = script;
    if (s == null) return;
    final was = isPlaying || phase == PlaybackPhase.finished;
    _gen++;
    await _safeStop();
    index = i.clamp(0, s.lines.length - 1);
    _lineStartedAt = DateTime.now();
    if (was) {
      play();
    } else {
      phase = PlaybackPhase.paused;
      _notify();
    }
  }

  /// Jumps to the line playing at [seconds] (as shown, i.e. at this speed).
  Future<void> seekTo(double seconds) async {
    final s = script;
    if (s == null) return;
    await seekLine(s.lineAt(seconds * speed));
  }

  /// −10 s / +10 s, to the line playing at that time. Going back within
  /// the first 3 s of a line goes to the line before; going forward always
  /// moves at least one line.
  Future<void> skip(double seconds) async {
    final s = script;
    if (s == null) return;
    final last = s.lines.length - 1;
    final cur = index.clamp(0, last);
    final target = (position + seconds).clamp(0.0, total);
    var line = s.lineAt(target * speed);
    if (seconds < 0) {
      final intoLine = position - s.starts[cur] / speed;
      if (line >= cur) line = intoLine > 3 ? cur : cur - 1;
    } else if (line <= cur) {
      line = cur + 1;
    }
    await seekLine(line.clamp(0, last));
  }

  Future<void> setSpeed(double v) async {
    speed = v;
    try {
      await _tts.setSpeechRate(_rate);
    } catch (_) {}
    if (isPlaying) {
      await seekLine(index); // the new speed is heard straight away
    } else {
      _notify();
    }
  }

  void rate(int v) {
    feedback = feedback == v ? null : v;
    _notify();
  }

  Future<void> _run() async {
    final g = ++_gen;
    final s = script!;
    while (g == _gen && !_disposed && index < s.lines.length) {
      final l = s.lines[index];
      try {
        await _voiceFor(l);
        if (g != _gen) return;
        _lineStartedAt = DateTime.now();
        _notify();
        await _tts.speak(l.text);
      } catch (_) {
        if (g == _gen) fail('The phone’s voice couldn’t speak. Check Settings › Text-to-speech.');
        return;
      }
      if (g != _gen || _disposed) return;
      index++;
    }
    if (g == _gen && !_disposed) {
      phase = PlaybackPhase.finished;
      index = s.lines.length - 1;
      _stopTicker();
      _notify();
    }
  }

  Future<void> _safeStop() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }

  void _startTicker() {
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(milliseconds: 500), (_) => _notify());
  }

  void _stopTicker() {
    _tick?.cancel();
    _tick = null;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Stops speaking for good.
  @override
  void dispose() {
    _disposed = true;
    _gen++;
    _stopTicker();
    _safeStop();
    super.dispose();
  }
}
