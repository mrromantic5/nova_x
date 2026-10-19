// test/nova/nova_controller_test.dart
//
// End-to-end assistant flows with fake API, native layer and host:
// commands, conversation, permissions, contact disambiguation, voice
// capture rules, overlay hand-off and cancellation of stale work.

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nova_x/features/nova/controller/nova_controller.dart';
import 'package:nova_x/features/nova/models/nova_models.dart';
import 'package:nova_x/features/nova/services/nova_api.dart';
import 'package:nova_x/features/nova/services/nova_executor.dart';
import 'package:nova_x/features/nova/services/nova_native.dart';
import 'package:nova_x/features/nova/services/nova_voice.dart';

class FakeApi implements NovaApi {
  String chatReply = 'Flutter is a UI toolkit.';
  String transcript = '';
  NovaPlannerResult? planResult; // null = Worker without /plan
  Completer<String>? chatGate;
  final List<String> chatCalls = [];
  final List<String> transcribeCalls = [];
  List<Map<String, String>> lastHistory = const [];

  @override
  Future<String> chat(String message, List<Map<String, String>> history,
      {CancelToken? cancel}) async {
    chatCalls.add(message);
    lastHistory = history;
    final gate = chatGate;
    if (gate != null) return gate.future;
    return chatReply;
  }

  @override
  Future<String> transcribe(String filePath, {CancelToken? cancel}) async {
    transcribeCalls.add(filePath);
    return transcript;
  }

  @override
  Future<NovaPlannerResult?> plan(String message, List<Map<String, String>> history,
          {CancelToken? cancel}) async =>
      planResult;

  @override
  void dispose() {}
}

class FakeNative implements NovaNativeApi {
  final StreamController<NovaNativeEvent> controller = StreamController.broadcast();
  final List<String> actions = [];
  final List<String> spoken = [];
  final Map<String, NovaNativeResult> results = {};
  bool micGranted = true;
  bool contactsGranted = false;
  bool grantOnRequest = true;
  NovaRecording recording = const NovaRecording(status: 'idle');

  @override
  Stream<NovaNativeEvent> get events => controller.stream;

  @override
  Future<NovaRecordStart> startRecording({int maxSeconds = 30, bool autoStop = true}) async =>
      micGranted ? const NovaRecordStart('recording') : const NovaRecordStart('permission_required');

  @override
  Future<NovaRecording> stopRecording() async => recording;

  @override
  Future<void> cancelRecording() async {}

  @override
  Future<bool> speak(String text, String utteranceId) async {
    spoken.add(text);
    return false; // behave like a phone without TTS → no waiting in tests
  }

  @override
  Future<void> stopSpeaking() async {}

  @override
  Future<bool> isPermissionGranted(String kind) async =>
      kind == 'microphone' ? micGranted : contactsGranted;

  @override
  Future<bool> requestPermission(String kind) async {
    if (!grantOnRequest) return false;
    if (kind == 'contacts') contactsGranted = true;
    if (kind == 'microphone') micGranted = true;
    return true;
  }

  @override
  Future<void> openAppPermissionSettings() async {}

  @override
  Future<NovaNativeResult> runAction(String action, Map<String, String> args) async {
    actions.add('$action:${args.values.join('|')}');
    if (action == 'search_contacts' && !contactsGranted) {
      return const NovaNativeResult('permission_required', {});
    }
    return results[action] ?? const NovaNativeResult('success', {'label': 'YouTube'});
  }

  @override
  Future<NovaAssistantStatus> assistantStatus() async =>
      const NovaAssistantStatus(supported: true, held: false, eligible: true, sdk: 34);

  @override
  Future<bool> openAssistantSettings() async => true;

  @override
  Future<void> closeAssistant() async {}
}

class FakeHost implements NovaHost {
  FakeHost({this.overlay = false});
  final bool overlay;
  final List<String> opened = [];
  int closes = 0;

  @override
  bool get isOverlay => overlay;

  @override
  Future<bool> openInBrowser(String url) async {
    opened.add(url);
    return true;
  }

  @override
  Future<bool> openFeature(String featureId) async {
    opened.add('feature:$featureId');
    return true;
  }

  @override
  bool get isClosed => false;

  @override
  void close() => closes++;
}

class FakeVoice implements NovaVoiceOutput {
  final StreamController<String> done = StreamController<String>.broadcast();
  final List<String> spoken = [];
  final List<String> ids = [];
  int stops = 0;

  @override
  Future<bool> speak(String text, String utteranceId) async {
    spoken.add(text);
    ids.add(utteranceId);
    return true;
  }

  @override
  Future<void> stop() async => stops++;

  @override
  Stream<String> get completed => done.stream;

  @override
  void dispose() {}
}

Future<void> settle() async {
  for (var i = 0; i < 30; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late FakeApi api;
  late FakeNative native;
  late FakeHost host;
  late NovaController c;

  NovaController make({bool overlay = false}) {
    host = FakeHost(overlay: overlay);
    return NovaController(
      api: api,
      native: native,
      host: host,
      searchUrl: (q) => 'https://search.test/?q=${Uri.encodeComponent(q)}',
      clock: () => DateTime(2026, 10, 19, 9, 30),
    );
  }

  setUp(() {
    api = FakeApi();
    native = FakeNative();
    c = make();
  });

  tearDown(() => c.dispose());

  test('clear commands run on-device, without calling the AI', () async {
    await c.submitText('Hey NOVA, open YouTube');
    expect(native.actions, ['open_app:youtube']);
    expect(api.chatCalls, isEmpty);
    expect(c.reply, 'Opening YouTube.');
    expect(c.state, NovaState.idle);
    expect(native.spoken, contains('Opening YouTube.'));
  });

  test('web search opens NOVA X with the search URL', () async {
    await c.submitText('search for flutter tutorials');
    expect(host.opened.single, 'https://search.test/?q=flutter%20tutorials');
  });

  test('missing apps fall back to their website inside NOVA X', () async {
    native.results['open_app'] = const NovaNativeResult('not_found', {});
    await c.submitText('open youtube');
    expect(host.opened.single, 'https://m.youtube.com');
    expect(c.reply, contains("isn't installed"));
  });

  test('conversation goes to /chat with bounded history', () async {
    await c.submitText('what is flutter');
    expect(api.chatCalls, ['what is flutter']);
    expect(c.reply, 'Flutter is a UI toolkit.');
    expect(c.history.length, 2);

    await c.submitText('who made it');
    expect(api.lastHistory, [
      {'role': 'user', 'content': 'what is flutter'},
      {'role': 'assistant', 'content': 'Flutter is a UI toolkit.'},
    ]);
  });

  test('validated planner actions are executed; reply reports the real outcome', () async {
    api.planResult = const NovaPlannerResult(NovaActionsPlan([
      NovaAction(NovaActionType.openSettings, {'target': 'wifi', 'toggle': 'on'}),
    ], speak: 'Wi-Fi is now on!')); // planner claims too much…
    native.results['open_settings'] = const NovaNativeResult('success', {'opened': 'wifi'});
    await c.submitText('could you make sure my wifi is enabled');
    expect(native.actions, ['open_settings:wifi']);
    // …but NOVA only reports what actually happened.
    expect(c.reply, contains("I can't switch Wi-Fi on myself"));
    expect(api.chatCalls, isEmpty);
  });

  test('calling by name: permission → clarification → dialer', () async {
    await c.submitText('call ama');
    expect(c.state, NovaState.permissionRequired);
    expect(c.permissionKind, 'contacts');

    native.results['search_contacts'] = const NovaNativeResult('success', {
      'matches': [
        {'name': 'Ama Mensah', 'number': '+233241112222', 'type': 'Mobile'},
        {'name': 'Ama Boateng', 'number': '0209998888', 'type': 'Work'},
      ],
    });
    await c.grantPermission();
    expect(c.state, NovaState.clarifying);
    expect(c.choices.map((x) => x.label), ['Ama Mensah', 'Ama Boateng']);

    await c.choose(c.choices.first);
    expect(native.actions.last, 'dial_number:+233241112222');
    expect(c.reply, contains('Opening the dialer for Ama Mensah'));
    expect(c.reply, contains('Tap Call'));
  });

  test('refusing contacts access keeps NOVA usable', () async {
    native.grantOnRequest = false;
    await c.submitText('call ama');
    await c.grantPermission();
    expect(c.state, NovaState.idle);
    expect(c.offerPermissionSettings, isTrue);
    expect(native.actions.where((a) => a.startsWith('dial_number')), isEmpty);
  });

  test('silence is never uploaded', () async {
    await c.startListening();
    expect(c.state, NovaState.listening);
    native.recording =
        const NovaRecording(status: 'ok', path: '/tmp/none.m4a', durationMs: 7000, hadSpeech: false);
    native.controller.add(const NovaRecordingStoppedEvent('no_speech'));
    await settle();
    expect(api.transcribeCalls, isEmpty);
    expect(c.reply, contains("didn't catch that"));
  });

  test('speech is transcribed and acted on', () async {
    api.transcript = 'open youtube';
    await c.startListening();
    native.recording =
        const NovaRecording(status: 'ok', path: '/tmp/none.m4a', durationMs: 1800, hadSpeech: true);
    native.controller.add(const NovaRecordingStoppedEvent('silence'));
    await settle();
    expect(api.transcribeCalls, ['/tmp/none.m4a']);
    expect(native.actions, ['open_app:youtube']);
  });

  test('microphone permission prompt when not granted', () async {
    native.micGranted = false;
    await c.startListening();
    expect(c.state, NovaState.permissionRequired);
    expect(c.permissionKind, 'microphone');
    await c.grantPermission();
    expect(c.state, NovaState.listening);
  });

  test('floating assistant hands over silently after an action', () async {
    c.dispose();
    c = make(overlay: true);
    await c.submitText('open youtube');
    expect(host.closes, 1);
    expect(native.spoken, isEmpty);
  });

  test('cancel discards a late AI answer', () async {
    final gate = Completer<String>();
    api.chatGate = gate;
    final pending = c.submitText('tell me a long story');
    await settle();
    expect(c.state, NovaState.thinking);
    c.cancel();
    gate.complete('Once upon a time…');
    await pending;
    expect(c.state, NovaState.idle);
    expect(c.reply, isNot(contains('Once upon a time')));
  });

  test('duplicate taps are ignored', () async {
    await c.submitText('open youtube');
    await c.submitText('open youtube');
    expect(native.actions, hasLength(1));
  });

  test('local answers', () async {
    await c.submitText('what time is it');
    expect(c.reply, "It's 9:30 AM.");
    await c.submitText('never mind');
    expect(c.state, NovaState.idle);
  });

  test('replies are spoken through the voice; its completion ends speaking', () async {
    final voice = FakeVoice();
    c.dispose();
    c = NovaController(
      api: api,
      native: native,
      host: FakeHost(),
      voice: voice,
      clock: () => DateTime(2026, 10, 19, 9, 30),
    );
    final run = c.submitText('Hey NOVA, open YouTube');
    await settle();
    expect(voice.spoken, contains('Opening YouTube.'));
    expect(native.spoken, isEmpty); // the phone voice is only the fallback
    voice.done.add(voice.ids.last);
    await run;
    await settle();
    expect(c.state, NovaState.idle);
  });

  test('spoken text drops markdown and long content', () {
    expect(NovaController.speakable('**Hi** there, see `code` at https://x.com'),
        'Hi there, see code at a link');
    final long = List.filled(80, 'Sentence number one is here.').join(' ');
    final s = NovaController.speakable(long);
    expect(s.length, lessThan(420));
    expect(s, endsWith('The full answer is on your screen.'));
    expect(NovaController.speakable(long, maxChars: 0).length, greaterThan(1000));
  });
}
