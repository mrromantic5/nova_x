// lib/features/nova/services/nova_history.dart
//
// Bounded conversation memory for one NOVA session. Kept in memory only —
// it is never written to disk and is discarded when the session closes.

import '../models/nova_models.dart';
import '../nova_config.dart';

class NovaHistory {
  NovaHistory({this.maxMessages = NovaConfig.maxHistoryMessages,
      this.maxChars = NovaConfig.maxHistoryChars});

  final int maxMessages;
  final int maxChars;
  final List<NovaMessage> _items = [];

  List<NovaMessage> get messages => List.unmodifiable(_items);
  bool get isEmpty => _items.isEmpty;
  int get length => _items.length;

  void addUser(String text) => _add('user', text);
  void addAssistant(String text) => _add('assistant', text);

  void _add(String role, String text) {
    final t = text.trim();
    if (t.isEmpty) return;
    _items.add(NovaMessage(
      role: role,
      content: t.length > maxChars ? t.substring(0, maxChars) : t,
    ));
    while (_items.length > maxMessages) {
      _items.removeAt(0);
    }
  }

  /// JSON-ready history (only 'user' / 'assistant' roles, already bounded).
  List<Map<String, String>> toJson() => _items.map((m) => m.toJson()).toList();

  void clear() => _items.clear();
}
