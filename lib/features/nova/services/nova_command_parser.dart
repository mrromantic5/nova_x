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

  String? _inAppFeature(String t) {
    final stripped = t.replaceFirst(RegExp(r'^(?:open|show|go to|show me|take me to)\s+'), '');
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
