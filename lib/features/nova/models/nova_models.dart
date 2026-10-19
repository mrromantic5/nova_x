// lib/features/nova/models/nova_models.dart
//
// Typed models shared by NOVA's parser, planner, executor, controller and UI.

/// Every visual/behavioural state of the assistant.
enum NovaState {
  idle,
  activating,
  listening,
  processingSpeech,
  thinking,
  executing,
  speaking,
  clarifying,
  permissionRequired,
  error,
  disabled,
}

/// One turn of conversation sent to the NOVA AI Worker as history.
class NovaMessage {
  const NovaMessage({required this.role, required this.content});

  /// Only 'user' or 'assistant' are ever produced (see NovaHistory).
  final String role;
  final String content;

  Map<String, String> toJson() => {'role': role, 'content': content};
}

/// The fixed set of actions NOVA can perform. Anything else is rejected.
enum NovaActionType {
  openUrl('open_url'),
  webSearch('web_search'),
  openApp('open_app'),
  searchInApp('search_in_app'),
  callContact('call_contact'),
  dialNumber('dial_number'),
  openSettings('open_settings'),
  navigate('navigate');

  const NovaActionType(this.wireName);

  /// Name used by the planner API.
  final String wireName;

  static NovaActionType? fromWire(String? name) {
    for (final t in NovaActionType.values) {
      if (t.wireName == name) return t;
    }
    return null;
  }

  /// Actions that hand the user over to another app or screen.
  bool get leavesApp => switch (this) {
        NovaActionType.openApp ||
        NovaActionType.searchInApp ||
        NovaActionType.dialNumber ||
        NovaActionType.openSettings ||
        NovaActionType.navigate =>
          true,
        _ => false,
      };
}

/// A validated action. Construct through NovaActionValidator only.
class NovaAction {
  const NovaAction(this.type, this.args);

  final NovaActionType type;
  final Map<String, String> args;

  String arg(String key) => args[key] ?? '';

  @override
  String toString() => 'NovaAction(${type.wireName}, $args)';

  @override
  bool operator ==(Object other) =>
      other is NovaAction &&
      other.type == type &&
      other.args.length == args.length &&
      other.args.entries.every((e) => args[e.key] == e.value);

  @override
  int get hashCode => Object.hash(type, Object.hashAllUnordered(
      args.entries.map((e) => Object.hash(e.key, e.value))));
}

enum NovaActionStatus {
  success,
  notFound,
  invalid,
  unsupported,
  permissionRequired,
  needsClarification,
  failed,
}

/// A choice offered to the user (clarification, contact pick…).
class NovaChoice {
  const NovaChoice({required this.label, this.subtitle, this.action, this.text});

  final String label;
  final String? subtitle;

  /// Run this validated action when chosen…
  final NovaAction? action;

  /// …or submit this text as if the user had said it.
  final String? text;
}

/// The real outcome of executing one action.
class NovaActionResult {
  const NovaActionResult({
    required this.action,
    required this.status,
    required this.message,
    this.choices = const [],
  });

  final NovaAction action;
  final NovaActionStatus status;

  /// Human-readable, spoken sentence describing what actually happened.
  final String message;

  final List<NovaChoice> choices;

  bool get ok => status == NovaActionStatus.success;
}

/// Outcome of planning a user request (local parser or AI planner).
sealed class NovaPlan {
  const NovaPlan();
}

/// Execute these validated actions in order (bounded by NovaConfig.maxPlanSteps).
class NovaActionsPlan extends NovaPlan {
  const NovaActionsPlan(this.actions, {this.speak});
  final List<NovaAction> actions;

  /// Optional short sentence from the AI planner (used only if actions succeed).
  final String? speak;
}

/// Answer directly with this text (no actions).
class NovaReplyPlan extends NovaPlan {
  const NovaReplyPlan(this.reply, {this.fromAi = false});
  final String reply;
  final bool fromAi;
}

/// Ask the user a short question before doing anything.
class NovaClarifyPlan extends NovaPlan {
  const NovaClarifyPlan(this.question, {this.options = const []});
  final String question;
  final List<String> options;
}

/// The user asked NOVA to stop / cancel.
class NovaCancelPlan extends NovaPlan {
  const NovaCancelPlan();
}

/// Page content handed to NOVA for summarising (treated as untrusted data).
class NovaPageContent {
  const NovaPageContent({required this.title, required this.url, required this.text});
  final String title;
  final String url;
  final String text;
}

/// Voice/assistant preferences (stored locally on the phone).
class NovaSettings {
  const NovaSettings({this.speakReplies = true, this.greetOnActivate = true});
  final bool speakReplies;
  final bool greetOnActivate;

  NovaSettings copyWith({bool? speakReplies, bool? greetOnActivate}) => NovaSettings(
        speakReplies: speakReplies ?? this.speakReplies,
        greetOnActivate: greetOnActivate ?? this.greetOnActivate,
      );
}
