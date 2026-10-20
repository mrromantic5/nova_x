// lib/features/nova/services/nova_command_parser.dart
//
// Deterministic, schema-based recognition of clear commands — e.g.
// "open YouTube", "search for Flutter tutorials", "call Ama", "open Wi-Fi
// settings", "open YouTube and search for Flutter tutorials".
//
// It is intentionally conservative: anything it is not sure about returns
// null and goes to the NOVA AI (planner, then chat). Every action it emits is
// built through NovaActionValidator, exactly like AI-planned actions.

import '../models/nova_models.dart';
import '../nova_config.dart';
import 'nova_validator.dart';

class NovaCommandParser {
  NovaCommandParser({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;

  // "Hey NOVA", "ok nova,", "Nova:" — but not "NOVA X …" (the browser's name).
  static final RegExp _wakePrefix = RegExp(
      r'^(?:(?:hey|hi|hello|ok|okay)[\s,]+)?nova\b(?!\s*x\b)[\s,.!:]*',
      caseSensitive: false);
  static final RegExp _politePrefix = RegExp(
      r"^(?:(?:please|can you|could you|would you|will you|i want to|i'd like to|"
      r'i would like to|help me|go ahead and|kindly)\s+)+');
  static final RegExp _politeSuffix =
      RegExp(r'(?:\s+(?:please|for me|now|right now|thanks|thank you))+$');

  /// Words that mark the request as conversational, not a command.
  static final RegExp _questionStart = RegExp(
      r'^(?:what|why|how|who|when|where|which|is|are|do|does|did|can|could|should|tell me about|explain)\b');

  static const String _searchApps =
      r'(youtube|you tube|spotify|google maps|maps|play store|twitter|x)';

  /// Returns a plan for clear commands, or null to let the AI decide.
  NovaPlan? parse(String input) {
    final text = normalise(input);
    if (text.isEmpty) return null;

    if (RegExp(r"^(?:cancel|stop|never ?mind|forget it|that is all|that's all|nothing|exit|close)$")
        .hasMatch(text)) {
      return const NovaCancelPlan();
    }

    final time = _timeOrDate(text);
    if (time != null) return NovaReplyPlan(time);

    final cannot = cannotDo(text);
    if (cannot != null) return NovaReplyPlan(cannot);

    final multi = _multiStep(text);
    if (multi != null) return multi;

    final single = _single(text);
    if (single != null) return NovaActionsPlan([single]);
    return null;
  }

  /// True when the input is only the wake phrase ("Hey NOVA").
  static bool isWakeOnly(String input) =>
      input.trim().isNotEmpty && normalise(input).isEmpty;

  /// Lower-cases, strips the wake phrase, politeness and end punctuation.
  static String normalise(String input) {
    var t = input.trim().toLowerCase();
    t = t.replaceAll(RegExp(r'[“”"]'), '').replaceAll('’', "'");
    t = t.replaceFirst(_wakePrefix, '');
    t = t.replaceAll(RegExp(r'[.!?…]+$'), '').trim();
    t = t.replaceFirst(_politePrefix, '');
    t = t.replaceFirst(_politeSuffix, '');
    return t.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  // ── Local answers ─────────────────────────────────────────────────────────

  String? _timeOrDate(String t) {
    final now = _clock();
    if (RegExp(r"^(?:what(?:'s| is) the time|what time is it|tell me the time|current time|time)$")
        .hasMatch(t)) {
      final h = now.hour % 12 == 0 ? 12 : now.hour % 12;
      final m = now.minute.toString().padLeft(2, '0');
      return "It's $h:$m ${now.hour < 12 ? 'AM' : 'PM'}.";
    }
    if (RegExp(r"^(?:what(?:'s| is) (?:the |today'?s )?date|what day is (?:it|today)|today'?s date|what is today)$")
        .hasMatch(t)) {
      const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
      const months = ['January', 'February', 'March', 'April', 'May', 'June', 'July',
        'August', 'September', 'October', 'November', 'December'];
      return 'Today is ${days[now.weekday - 1]}, ${now.day} ${months[now.month - 1]} ${now.year}.';
    }
    return null;
  }

  // ── Things NOVA can't do (answered honestly, never "done") ────────────────

  /// Honest answer for phone controls Android doesn't let NOVA perform, or
  /// null. Without this the AI might reply as if it had done them.
  static String? cannotDo(String t) {
    if (RegExp(r'^lock(?: the| my)? (?:phone|screen|device|display)(?: screen)?$').hasMatch(t) ||
        RegExp(r'^(?:turn|switch) off(?: the| my)? (?:screen|display)$').hasMatch(t) ||
        RegExp(r'^(?:lock screen|screen off|lock it)$').hasMatch(t)) {
      return "I can't lock your screen — Android only lets special system apps do that. "
          'Press the power button to lock it.';
    }
    if (RegExp(r'^(?:take|capture|grab)(?: a| me a| the)? (?:screenshot|screen shot|screen capture|screengrab)$')
            .hasMatch(t) ||
        t == 'screenshot') {
      return "I can't take screenshots. Press the power and volume-down buttons together.";
    }
    if (RegExp(r'^(?:restart|reboot|shut ?down|power off|turn off|switch off)(?: the| my)? (?:phone|device|mobile)$')
            .hasMatch(t) ||
        RegExp(r'^(?:restart|reboot|shut ?down|power off)$').hasMatch(t)) {
      return "I can't restart or switch off your phone. Hold the power button to see those options.";
    }
    if (RegExp(r'^(?:set|create|make|add|start)(?: an?| my| the| me an?)? (?:alarm|timer|reminder|countdown)'
                r'(?:$| for \d| for (?:an?|one|two|three|five|ten|half)\b| at \d| at (?:noon|midnight)\b| to\b| on\b| tomorrow\b| tonight\b)')
            .hasMatch(t) ||
        RegExp(r'^(?:wake me up|remind me (?:to|at|in|on|tomorrow|tonight|about)\b)').hasMatch(t)) {
      return "I can't set alarms, timers or reminders yet. Say “open clock” and I'll open your Clock app.";
    }
    // "send a message to Ama", "text Wendy", "whatsapp Kofi that I'm late" —
    // but not "text to speech apps", "email etiquette tips" or "whatsapp settings".
    if (RegExp(r'^send(?: an?)? (?:message|text|sms|whatsapp|email|mail)\b').hasMatch(t) ||
        RegExp(r"^(?:text|message|sms) (?!me\b|you\b|to\b|for\b|settings?\b|editors?\b|history\b|gateways?\b|messages?\b|apps?\b|templates?\b|box\b|format\b|size\b)[a-z][\w'.-]*"
                r'(?: (?:that|saying|to say|and say|and tell (?:him|her|them)|about)\b.*)?$')
            .hasMatch(t) ||
        RegExp(r"^(?:whatsapp|email) (?!me\b|you\b|to\b|for\b|settings?\b|editors?\b|history\b|gateways?\b|messages?\b|apps?\b|templates?\b|box\b|format\b|size\b)[a-z][\w'.-]*"
                r' (?:that|saying|to say|and say|and tell (?:him|her|them)|about)\b')
            .hasMatch(t)) {
      return "I can't send messages for you yet. Say “open WhatsApp” or “open Messages” and I'll open it.";
    }
    if (RegExp(r'^(?:turn|switch) (?:on|off) (?:the |my )?(?:flash ?light|torch)$').hasMatch(t) ||
        RegExp(r'^(?:turn|switch) (?:the |my )?(?:flash ?light|torch) (?:on|off)$').hasMatch(t)) {
      return "I can't switch the flashlight yet — use the torch button in your quick settings.";
    }
    return null;
  }

  // ── Multi-step ────────────────────────────────────────────────────────────

  NovaPlan? _multiStep(String t) {
    // "open youtube and search (for) X" → one deep-linked in-app search.
    final inApp = RegExp(
            '^(?:open|launch|start|go to) $_searchApps '
            r'(?:and then|and|then) (?:search|look up|find|play)(?: for)? (.+)$')
        .firstMatch(t);
    if (inApp != null) {
      final a = _searchInApp(inApp.group(1)!, inApp.group(2)!);
      if (a != null) return NovaActionsPlan([a]);
    }

    final parts = t.split(RegExp(r',? (?:and then|then|and also|and) '));
    if (parts.length < 2 || parts.length > NovaConfig.maxPlanSteps) return null;
    final actions = <NovaAction>[];
    for (final p in parts) {
      final a = _single(p.trim());
      if (a == null) return null; // only split when every part is a command
      actions.add(a);
    }
    return NovaActionsPlan(actions);
  }

  // ── Single commands ───────────────────────────────────────────────────────

  NovaAction? _single(String t) {
    if (t.isEmpty || t.length > 300) return null;

    // In-app destinations: "open my bookmarks", "downloads", "nova shield".
    final feature = _inAppFeature(t);
    if (feature != null) {
      return NovaActionValidator.build(NovaActionType.openApp, {'app': feature});
    }

    // Search inside an app: "search youtube for X", "play X on spotify".
    var m = RegExp('^(?:search|look up|find)(?: for)? (.+) on $_searchApps\$').firstMatch(t);
    if (m != null) return _searchInApp(m.group(2)!, m.group(1)!);
    m = RegExp(r'^search (youtube|you tube|spotify|play store|twitter) for (.+)$').firstMatch(t);
    if (m != null) return _searchInApp(m.group(1)!, m.group(2)!);
    m = RegExp(r'^play (.+) on (youtube|you tube|spotify)$').firstMatch(t);
    if (m != null) return _searchInApp(m.group(2)!, m.group(1)!);
    // "play a video of X" → YouTube.
    m = RegExp(r'^(?:play|show me)(?: me)?(?: an?| the| some)? videos? (?:of |about |on |for )?(.+)$').firstMatch(t);
    if (m != null) return _searchInApp('youtube', m.group(1)!);

    // NOVA Music (songs saved on the phone — works offline).
    final music = _music(t);
    if (music != null) return music;

    // "turn on wifi" → NOVA can only open the screen; the executor says so.
    m = RegExp(r'^(?:turn|switch) (on|off) (?:the )?(.+)$').firstMatch(t) ??
        RegExp(r'^(?:turn|switch) (?:the )?(.+) (on|off)$').firstMatch(t);
    if (m != null) {
      final onFirst = m.group(1) == 'on' || m.group(1) == 'off';
      final toggle = onFirst ? m.group(1)! : m.group(2)!;
      final what = onFirst ? m.group(2)! : m.group(1)!;
      final target = NovaActionValidator.settingsTarget(what);
      if (target == null) return null;
      return NovaActionValidator.build(
          NovaActionType.openSettings, {'target': target, 'toggle': toggle});
    }

    // Settings screens: "open wifi settings", "bluetooth settings", "settings".
    if (t.endsWith('settings') || t.endsWith('setting')) {
      m = RegExp(r'^(?:open|show|go to|launch|take me to)?(?: the| my)? ?(.+?)? ?settings?$')
          .firstMatch(t);
      if (m != null) {
        final what = (m.group(1) ?? '').trim();
        final target = what.isEmpty ? 'general' : NovaActionValidator.settingsTarget(what);
        if (target != null) {
          return NovaActionValidator.build(NovaActionType.openSettings, {'target': target});
        }
        // "whatsapp settings" etc. → let the AI decide rather than guess.
        if (!what.contains(' ')) return null;
      }
    }

    // Directions.
    m = RegExp(r'^(?:navigate|directions|get directions|drive|give me directions)(?: me)? to (.+)$')
        .firstMatch(t);
    if (m != null) {
      return NovaActionValidator.build(NovaActionType.navigate, {'destination': m.group(1)!});
    }

    // Calling: "call ama", "dial 0241234567".
    m = RegExp(r'^(?:call|phone|ring|dial|make a call to|place a call to)(?: up)? (.+?)'
            r'(?: on (?:speaker|mobile|her phone|his phone|the phone))?$')
        .firstMatch(t);
    if (m != null) {
      final who = m.group(1)!.trim();
      final digits = who.replaceAll(RegExp(r'[^0-9]'), '');
      if (RegExp(r'^[+0-9 ()\-*#]+$').hasMatch(who) && digits.length >= 3) {
        return NovaActionValidator.build(NovaActionType.dialNumber, {'number': who});
      }
      if (_questionStart.hasMatch(who) ||
          RegExp(r'^(?:me|a|an|the|my phone|it)\b').hasMatch(who) ||
          who.split(' ').length > 4) {
        return null;
      }
      return NovaActionValidator.build(NovaActionType.callContact, {'name': who});
    }

    // Web search: "search for X", "google X", "look up X".
    m = RegExp(r'^(?:search up|search(?: the web| online| google| the internet)?(?: for)?|google|look up|find me) (.+)$')
        .firstMatch(t);
    if (m != null) {
      final q = m.group(1)!.trim();
      if (q.isEmpty) return null;
      return NovaActionValidator.build(NovaActionType.webSearch, {'query': q});
    }

    // Open a website or an app.
    m = RegExp(r'^(?:open|launch|start|go to|visit|bring up)(?: the| my)? (.+?)(?: app| application| website| site)?$')
        .firstMatch(t);
    if (m != null) {
      final target = m.group(1)!.trim();
      if (target.contains('.')) {
        final url = NovaActionValidator.normaliseUrl(target);
        if (url != null) return NovaActionValidator.build(NovaActionType.openUrl, {'url': url});
      }
      if (target.split(' ').length > 4 ||
          _questionStart.hasMatch(target) ||
          RegExp(r'^(?:a|an|some|new)\b').hasMatch(target)) {
        return null;
      }
      return NovaActionValidator.build(NovaActionType.openApp, {'app': target});
    }

    // A bare domain: "youtube.com", "news.bbc.co.uk/sport".
    if (!t.contains(' ') && t.contains('.')) {
      final url = NovaActionValidator.normaliseUrl(t);
      if (url != null) return NovaActionValidator.build(NovaActionType.openUrl, {'url': url});
    }
    return null;
  }

  NovaAction? _music(String t) {
    NovaAction? control(String command) =>
        NovaActionValidator.build(NovaActionType.musicControl, {'command': command});
    NovaAction? play(String query) {
      // "listen to some music" → any music.
      final any = RegExp(r'^(?:(?:some|my|the|any|all|random) )*(?:music|songs?|tracks?|tunes|something)$');
      return NovaActionValidator.build(
          NovaActionType.playMusic, {'query': any.hasMatch(query) ? '' : query});
    }

    const thing = r'(?:music|song|songs|track|tracks|playback|tune|tunes)';
    if (RegExp('^pause(?: (?:the |my |this )?$thing)?\$').hasMatch(t)) return control('pause');
    if ((RegExp('^(?:play|resume|unpause)(?: (?:the |my )?$thing)?(?: again)?\$').hasMatch(t) ||
            RegExp('^continue (?:playing|(?:the |my )?$thing)\$').hasMatch(t)) &&
        t != 'play music' && t != 'play songs' && t != 'play song' && t != 'play tunes') {
      return control('resume');
    }
    if (RegExp('^(?:next|skip)(?: (?:this |the )?$thing)?\$').hasMatch(t) ||
        RegExp('^(?:play )?(?:the )?next $thing\$').hasMatch(t)) {
      return control('next');
    }
    if (RegExp('^previous(?: $thing)?\$').hasMatch(t) ||
        RegExp('^(?:go )?back to (?:the )?(?:previous|last) $thing\$').hasMatch(t) ||
        RegExp('^(?:play )?(?:the )?(?:previous|last) $thing(?: again)?\$').hasMatch(t)) {
      return control('previous');
    }
    if (RegExp('^(?:stop|turn off|switch off|end) (?:the |my |this )?$thing\$').hasMatch(t)) {
      return control('stop');
    }
    if (RegExp(r"^(?:what(?:'s| is) (?:playing|this song|the song|this track|the name of this song)|"
            r'(?:which|what) song is (?:this|playing)|who sings this(?: song)?)$')
        .hasMatch(t)) {
      return control('now_playing');
    }

    // Media volume.
    if (RegExp(r'^(?:turn|crank) (?:the |it )?(?:volume|music|sound) up$|^(?:turn )?(?:the )?(?:volume|sound) up$|'
            r'^(?:increase|raise|turn up|boost) (?:the )?(?:volume|sound|music)$|^(?:louder|make it louder)$')
        .hasMatch(t)) {
      return control('volume_up');
    }
    if (RegExp(r'^(?:turn) (?:the |it )?(?:volume|music|sound) down$|^(?:turn )?(?:the )?(?:volume|sound) down$|'
            r'^(?:decrease|lower|reduce|turn down) (?:the )?(?:volume|sound|music)$|^(?:quieter|softer|make it quieter)$')
        .hasMatch(t)) {
      return control('volume_down');
    }
    if (RegExp(r'^mute(?: the)?(?: music| sound| volume| phone| it)?$').hasMatch(t)) return control('mute');
    if (RegExp(r'^unmute(?: the)?(?: music| sound| volume| phone| it)?$').hasMatch(t)) return control('unmute');

    // Play: "play some music", "play songs by Burna Boy", "play me Tatiana Like You".
    if (RegExp(r'^(?:play|put on|shuffle|start)(?: me| us)?(?: some| a| my| any| random| all my)? '
            r'(?:music|song|songs|track|tracks|tunes|something)(?: for me)?$')
        .hasMatch(t)) {
      return play('');
    }
    var m = RegExp(r'^(?:play|put on)(?: me| us)?(?: some| the| all| all the)? (?:songs|music|tracks) (?:by|from) (.+)$')
        .firstMatch(t);
    if (m != null) return play(m.group(1)!);
    m = RegExp(r"^(?:i want to |i wanna |let me |let's )?listen to (.+)$").firstMatch(t);
    if (m != null &&
        !RegExp(r'^(?:me|you|this|that|it)$|^(?:this|that|the) (?:article|page|text|story|podcast|video)\b')
            .hasMatch(m.group(1)!)) {
      return play(m.group(1)!);
    }
    m = RegExp(r'^(?:play|put on|start playing)(?: me| us)?(?: the song| the track| a song| song| track)?'
            r'(?: called| titled| named)? (.+)$')
        .firstMatch(t);
    if (m != null) {
      final what = m.group(1)!.trim();
      // "play store" is the app; a game or a question isn't a song.
      if (what == 'store' ||
          what.startsWith('store ') ||
          _questionStart.hasMatch(what) ||
          RegExp(r'^(?:an? |the |some )?(?:game|games|quiz|trivia|chess|cards|football|soccer|guitar|piano|drums|hide and seek)\b')
              .hasMatch(what)) {
        return null;
      }
      return play(what);
    }
    return null;
  }

  String? _inAppFeature(String t) {
    final stripped = t.replaceFirst(RegExp(r'^(?:open|show|go to|show me|take me to)\s+'), '');
    // "my music" / "my points" are names of their own; otherwise "the"/"my" is dropped.
    if (NovaActionValidator.inAppFeatures.containsKey(stripped)) return stripped;
    final phrase = stripped.replaceFirst(RegExp(r'^(?:the|my)\s+'), '');
    return NovaActionValidator.inAppFeatures.containsKey(phrase) ? phrase : null;
  }

  NovaAction? _searchInApp(String app, String query) {
    final canonical = NovaActionValidator.canonicalApp(app);
    if (canonical == null) return null;
    return NovaActionValidator.build(
        NovaActionType.searchInApp, {'app': canonical, 'query': query.trim()});
  }
}
