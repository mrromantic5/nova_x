// lib/features/ai/services/nova_chat_commands.dart
//
// NOVA AI chat → NOVA commands (pure Dart, unit-tested).
//
// Typed requests such as "open NOVA Music", "play me a song", "next song",
// "test my internet speed" or "what's my IP" are carried out for real in the
// chat instead of being answered with instructions. Everything else
// (questions, writing, explanations) still goes to NOVA AI.
//
// Only actions that NOVA's own parser produced (already validated by
// NovaActionValidator) are run, and only the kinds listed in [chatActions].

import '../../network/services/network_intents.dart';
import '../../nova/models/nova_models.dart';
import '../../nova/services/nova_command_parser.dart';
import '../../nova/services/nova_validator.dart';

class NovaChatCommands {
  NovaChatCommands({NovaCommandParser? parser}) : _parser = parser ?? NovaCommandParser();

  final NovaCommandParser _parser;

  /// What a typed message may do in the chat. Calls and contact searches stay
  /// with the voice assistant (they need a confirmation flow).
  static const Set<NovaActionType> chatActions = {
    NovaActionType.openApp,
    NovaActionType.openUrl,
    NovaActionType.openSettings,
    NovaActionType.navigate,
    NovaActionType.searchInApp,
    NovaActionType.playMusic,
    NovaActionType.musicControl,
  };

  /// Questions *about* the connection ("how do I make my wifi faster?",
  /// "why is my internet slow?") are for NOVA AI, not a measurement.
  static final RegExp _advice = RegExp(
      r"^(?:(?:hey|hi|ok|okay)\s+nova[\s,]*)?(?:how\s+(?:to|do|can|could|should|would)\b|why\b|explain\b|tips?\b|ways?\b|"
      r"what\s+(?:affects|causes|makes|is\s+a\s+good|is\s+the\s+best|are)\b|give\s+me\s+tips|help\s+me\s+(?:improve|fix|speed))",
      caseSensitive: false);

  /// A measurement NOVA should run (speed test, ping, IP, battery), or open
  /// NOVA Network; [NetworkIntent.none] otherwise.
  NetworkIntent network(String text) {
    final t = text.trim();
    if (t.isEmpty || _advice.hasMatch(t)) return NetworkIntent.none;
    return NetworkIntents.parse(t);
  }

  /// The actions to run for [text], or null to ask NOVA AI.
  List<NovaAction>? actions(String text) {
    final t = text.trim();
    if (t.isEmpty || t.startsWith('/')) return null;
    final plan = _parser.parse(t);
    if (plan is! NovaActionsPlan || plan.actions.isEmpty) return null;
    if (!plan.actions.every((a) => chatActions.contains(a.type))) return null;
    return plan.actions;
  }

  /// The NOVA X page id an "open …" action points at, if any.
  static String? featureOf(NovaAction a) => a.type == NovaActionType.openApp
      ? NovaActionValidator.inAppFeatures[a.arg('app').toLowerCase()]
      : null;
}
