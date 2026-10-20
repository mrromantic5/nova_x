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
  static const int maxHistoryChars = 2000; // Worker truncates each to 2000
  static const int maxMessageChars = 4000; // Worker returns 413 above 4000
  static const int maxPageCharsForSummary = 3200;

  // Voice
  static const int maxRecordingSeconds = 30;
  static const int minRecordingMs = 450; // shorter clips are never uploaded

  // Agent safety limits
  static const int maxPlanSteps = 3;

  static const String greeting = 'Hi, NOVA is active to assist you.';
}
