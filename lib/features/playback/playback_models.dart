// lib/features/playback/playback_models.dart
//
// AI Playback (3.12.0): the conversation the two hosts speak.

/// One spoken turn. [female] = Ava (asks), otherwise Leo (answers).
class PlaybackLine {
  const PlaybackLine({required this.female, required this.text});

  final bool female;
  final String text;

  String get speaker => female ? 'Ava' : 'Leo';

  int get words => text.trim().isEmpty ? 0 : text.trim().split(RegExp(r'\s+')).length;

  /// Rough spoken length at normal speed (~155 words per minute).
  double get seconds => words / 2.6 + 0.35;

  static PlaybackLine? fromJson(Object? j) {
    if (j is! Map) return null;
    final t = j['t'];
    if (t is! String || t.trim().isEmpty) return null;
    if (j['s'] != 'f' && j['s'] != 'm') return null;
    final text = stripSpeaker(t);
    if (text.isEmpty) return null;
    return PlaybackLine(female: j['s'] == 'f', text: text);
  }

  /// "Ava: How do I…" → "How do I…" (the hosts never say their own names
  /// as a label; the player already shows who is speaking).
  static String stripSpeaker(String t) {
    var s = t.trim();
    for (var i = 0; i < 2; i++) {
      s = s.replaceFirst(RegExp(r'^\**\s*(Ava|Leo|Host\s*[12AB]?|Female|Male)\s*\**\s*(?:[:：]|\s[-–—])\s*', caseSensitive: false), '').trim();
    }
    return s;
  }
}

class PlaybackScript {
  const PlaybackScript({required this.title, required this.host, required this.lang, required this.lines, this.url = ''});

  final String title;
  final String host;
  final String lang;
  final String url;
  final List<PlaybackLine> lines;

  /// Start of each line in seconds (at normal speed) and the total length.
  List<double> get starts {
    final out = <double>[];
    var t = 0.0;
    for (final l in lines) {
      out.add(t);
      t += l.seconds;
    }
    return out;
  }

  double get totalSeconds => lines.fold(0.0, (t, l) => t + l.seconds);

  /// Which line is playing at [seconds] (normal speed).
  int lineAt(double seconds) {
    final s = starts;
    for (var i = s.length - 1; i >= 0; i--) {
      if (seconds >= s[i]) return i;
    }
    return 0;
  }

  /// The app's own first line, spoken by Leo before the conversation.
  static String introFor(String lang) => switch (lang) {
        'fr' => 'Cette lecture IA vous est proposée par NOVA X.',
        'es' => 'Esta reproducción con IA es una función de NOVA X.',
        'pt' => 'Esta reprodução com IA é oferecida pelo NOVA X.',
        'de' => 'Diese KI-Wiedergabe wird von NOVA X bereitgestellt.',
        'it' => 'Questa riproduzione IA è offerta da NOVA X.',
        'ar' => 'هذا التشغيل بالذكاء الاصطناعي مقدم من NOVA X.',
        _ => 'This AI playback is powered by NOVA X.',
      };

  /// Parses the Worker's answer and puts the intro line first.
  static PlaybackScript? fromJson(Map<String, dynamic> j, {required String host, required String url}) {
    final lines = j['lines'] is List
        ? (j['lines'] as List).map(PlaybackLine.fromJson).whereType<PlaybackLine>().toList()
        : <PlaybackLine>[];
    if (lines.length < 2) return null;
    final lang = j['lang'] is String ? j['lang'] as String : 'en';
    return PlaybackScript(
      title: (j['title'] is String && (j['title'] as String).trim().isNotEmpty) ? (j['title'] as String).trim() : host,
      host: host,
      url: url,
      lang: lang,
      lines: [PlaybackLine(female: false, text: introFor(lang)), ...lines],
    );
  }
}

/// "1:31"
String playbackClock(double seconds) {
  final s = seconds.isFinite && seconds > 0 ? seconds.round() : 0;
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}
