// lib/features/nova/services/nova_prefs.dart
//
// NOVA's local preferences (stored on the phone only; nothing is synced).

import 'package:shared_preferences/shared_preferences.dart';

import '../models/nova_models.dart';

class NovaPrefs {
  NovaPrefs._();

  static const _kSpeakReplies = 'nova_speak_replies';
  static const _kGreet = 'nova_greet_on_activate';

  static Future<NovaSettings> load() async {
    final p = await SharedPreferences.getInstance();
    return NovaSettings(
      speakReplies: p.getBool(_kSpeakReplies) ?? true,
      greetOnActivate: p.getBool(_kGreet) ?? true,
    );
  }

  static Future<void> save(NovaSettings s) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kSpeakReplies, s.speakReplies);
    await p.setBool(_kGreet, s.greetOnActivate);
  }
}
