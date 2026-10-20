// lib/features/nova/nova_config.dart
//
// Central configuration for NOVA, the NOVA X assistant. No secrets live in
// the app: the NOVA AI Worker holds the AI provider key server-side.
//
// The API base URL can be overridden at build time without code changes:
//   flutter build apk --dart-define=NOVA_API_BASE=https://your-worker.example

class NovaConfig {
  NovaConfig._();

  static const String apiBaseUrl = String.fromEnvironment(
    'NOVA_API_BASE',
    defaultValue: 'https://ama-ai.techlyfeteam.workers.dev',
  );

  /// NOVA Voice (Edge TTS Worker) — NOVA's spoken voice. No key needed.
  ///   flutter build apk --dart-define=NOVA_VOICE_BASE=https://your-voice-worker.example
  static const String voiceApiBaseUrl = String.fromEnvironment(
    'NOVA_VOICE_BASE',
    defaultValue: 'https://nova-voice.techlyfeteam.workers.dev',
  );

  // Network timeouts (bounded; retries are limited in NovaApiClient).
  static const Duration connectTimeout = Duration(seconds: 12);
  static const Duration chatTimeout = Duration(seconds: 45);
  static const Duration voiceTimeout = Duration(seconds: 60);

  // Limits mirrored from the Worker so requests are never rejected for size.
  static const int maxHistoryMessages = 10; // Worker keeps history.slice(-10)
  static const int maxHistoryChars = 4000; // Worker 3.4 keeps 4000 per message
  static const int maxMessageChars = 4000; // Worker returns 413 above 4000

  /// /vision accepts up to 8000 characters (question + page text).
  static const int maxVisionMessageChars = 7000;
  static const int maxPageCharsForSummary = 3200;

  // Voice
  static const int maxRecordingSeconds = 30;
  static const int minRecordingMs = 450; // shorter clips are never uploaded

  // Agent safety limits
  static const int maxPlanSteps = 3;

  static const String greeting = 'Hi! How can I help?';

  static const _morning = [
    'Good morning! What can I do for you?',
    'Morning! How can I help?',
    "Good morning — what's on your mind?",
  ];
  static const _afternoon = [
    'Good afternoon! What can I help with?',
    'Hey! What do you need?',
    'Hi there — how can I help this afternoon?',
  ];
  static const _evening = [
    'Good evening! What can I do for you?',
    'Evening! How can I help?',
    "Hi! What's on your mind tonight?",
  ];
  static const _night = [
    'Hey, night owl! What do you need?',
    "Hi! I'm here — what can I do?",
    'Still up? How can I help?',
  ];

  /// A short, friendly greeting that fits the time of day and changes each
  /// time ([pick] chooses the wording; any int works).
  static String greetingFor(DateTime now, int pick) {
    final h = now.hour;
    final options = h >= 5 && h < 12
        ? _morning
        : h >= 12 && h < 17
            ? _afternoon
            : h >= 17 && h < 22
                ? _evening
                : _night;
    return options[pick.abs() % options.length];
  }
}
