// lib/features/nova/services/nova_prefs.dart
//
// NOVA's local preferences (stored on the phone only; nothing is synced).

import 'package:shared_preferences/shared_preferences.dart';

import '../models/nova_models.dart';
import 'nova_voice.dart';

class NovaPrefs {
  NovaPrefs._();

  static const _kSpeakReplies = 'nova_speak_replies';
  static const _kGreet = 'nova_greet_on_activate';
  static const _kVoice = 'nova_voice';

  static Future<NovaSettings> load() async {
    final p = await SharedPreferences.getInstance();
    // The floating assistant runs in a second Flutter engine: pick up changes
    // it (or the main app) saved since this engine started.
    try {
      await p.reload();
    } catch (_) {
      // keep the cached values
    }
    final voice = p.getString(_kVoice);
    final settings = NovaSettings(
      speakReplies: p.getBool(_kSpeakReplies) ?? true,
      greetOnActivate: p.getBool(_kGreet) ?? true,
      voice: voice != null && NovaVoiceCatalog.isKnown(voice) ? voice : NovaSettings.defaultVoice,
    );
    NovaVoiceSelection.current = settings.voice;
    return settings;
  }

  static Future<void> save(NovaSettings s) async {
    final p = await SharedPreferences.getInstance();
    NovaVoiceSelection.current = s.voice;
    await p.setBool(_kSpeakReplies, s.speakReplies);
    await p.setBool(_kGreet, s.greetOnActivate);
    await p.setString(_kVoice, s.voice);
  }
}
