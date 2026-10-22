// test/nova/nova_controller_test.dart
//
// End-to-end assistant flows with fake API, native layer and host:
// commands, conversation, permissions, contact disambiguation, voice
// capture rules, offline voice input, NOVA Music, honest answers for things
// NOVA can't do, overlay hand-off and cancellation of stale work.

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nova_x/features/network/models/network_models.dart';
import 'package:nova_x/features/network/services/network_probe.dart';
import 'package:nova_x/features/network/services/speed_test_engine.dart';
import 'package:nova_x/features/nova/controller/nova_controller.dart';
import 'package:nova_x/features/nova/models/nova_models.dart';
import 'package:nova_x/features/nova/nova_config.dart';
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

  String visionReply = 'It is a login form.';
  final List<String> visionCalls = [];
  int lastImageCount = 0;

  @override
  Future<String> vision(String message, List<Map<String, String>> history, List<NovaVisionImage> images,
      {CancelToken? cancel}) async {
    visionCalls.add(message);
    lastHistory = history;
    lastImageCount = images.length;
    return visionReply;
  }

  @override
  void dispose() {}
}

class FakeNetwork implements NovaNetworkProbe {
  int tests = 0;
  bool cancelled = false;
  Object? error;

  @override
  Future<SpeedTestResult> speedTest({void Function(SpeedProgress)? onProgress}) async {
    tests++;
    if (error != null) throw error!;
    onProgress?.call(const SpeedProgress(phase: SpeedPhase.download, liveMbps: 88));
    return SpeedTestResult(
      time: DateTime(2026, 10, 23),
      downloadMbps: 131.3,
      uploadMbps: 45.2,
      pingMs: 37,
      jitterMs: 3,
      isp: 'Zenlayer',
    );
  }

  @override
  Future<double> ping() async => 23;

  @override
  Future<NetworkMeta> meta() async =>
      NetworkMeta.fromJson(const {'ip': '31.57.228.94', 'isp': 'Zenlayer', 'city': 'Dubai', 'country': 'AE'});

  @override
  Future<DeviceSnapshot> device() async => DeviceSnapshot.fromMap(const {
        'battery': {'level': 76, 'charging': true},
      });

  @override
  void cancel() => cancelled = true;
}

class FakeNative implements NovaNativeApi {
  final StreamController<NovaNativeEvent> controller = StreamController.broadcast();
  final List<String> actions = [];
  final List<String> spoken = [];
  final Map<String, NovaNativeResult> results = {};
  bool micGranted = true;
  bool contactsGranted = false;
  bool audioGranted = false;
  bool grantOnRequest = true;
  bool online = true;
  String deviceSpeechStatus = 'listening';
  int recordStarts = 0;
  int deviceSpeechStarts = 0;
  NovaRecording recording = const NovaRecording(status: 'idle');

  @override
  Stream<NovaNativeEvent> get events => controller.stream;

  @override
  Future<NovaRecordStart> startRecording({int maxSeconds = 30, bool autoStop = true}) async {
    recordStarts++;
    return micGranted ? const NovaRecordStart('recording') : const NovaRecordStart('permission_required');
  }

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
  Future<bool> isPermissionGranted(String kind) async => switch (kind) {
        'microphone' => micGranted,
        'audio' => audioGranted,
        _ => contactsGranted,
      };

  @override
  Future<bool> requestPermission(String kind) async {
    if (!grantOnRequest) return false;
    if (kind == 'contacts') contactsGranted = true;
    if (kind == 'microphone') micGranted = true;
    if (kind == 'audio') audioGranted = true;
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
    if (action == 'play_music' && !audioGranted) {
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

  @override
  Future<bool> isOnline() async => online;

  @override
  Future<String> startDeviceSpeech() async {
    deviceSpeechStarts++;
    return deviceSpeechStatus;
  }

  @override
  Future<void> stopDeviceSpeech() async {}

  @override
  Future<void> cancelDeviceSpeech() async {}
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
  late FakeNetwork network;

  NovaController make({bool overlay = false}) {
    host = FakeHost(overlay: overlay);
    return NovaController(
      api: api,
      native: native,
      host: host,
      network: network,
      searchUrl: (q) => 'https://search.test/?q=${Uri.encodeComponent(q)}',
      clock: () => DateTime(2026, 10, 19, 9, 30),
    );
  }

  setUp(() {
    api = FakeApi();
    native = FakeNative();
    network = FakeNetwork();
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

  test('"lock my screen" gets an honest answer — no AI, no action', () async {
    await c.submitText('Lock my screen');
    expect(api.chatCalls, isEmpty);
    expect(native.actions, isEmpty);
    expect(c.reply, contains("can't lock your screen"));
  });

  test('over the lock screen: an action the user did not unlock for is reported honestly', () async {
    native.results['open_app'] = const NovaNativeResult('locked', {});
    await c.submitText('open youtube');
    expect(c.reply, 'Unlock your phone first, then ask me again.');
  });

  test('the same number saved twice is offered once', () async {
    native.contactsGranted = true;
    native.results['search_contacts'] = const NovaNativeResult('success', {
      'matches': [
        {'name': 'Wendy', 'number': '+233 27 127 3330', 'type': 'Mobile'},
        {'name': 'Wendy', 'number': '0271273330', 'type': 'Mobile'},
      ],
    });
    await c.submitText('call wendy');
    expect(native.actions.last, 'dial_number:+233271273330');
    expect(c.state, isNot(NovaState.clarifying));
    expect(c.reply, contains('Opening the dialer for Wendy'));
  });

  test('offline: the phone recognises the words and on-device commands still work', () async {
    native.online = false;
    await c.startListening();
    expect(c.state, NovaState.listening);
    expect(native.deviceSpeechStarts, 1);
    expect(native.recordStarts, 0); // nothing is recorded or uploaded
    native.controller.add(const NovaDeviceSpeechEvent('result', text: 'open youtube'));
    await settle();
    expect(native.actions, ['open_app:youtube']);
    expect(api.transcribeCalls, isEmpty);
  });

  test('offline without on-device speech: NOVA says so', () async {
    native.online = false;
    native.deviceSpeechStatus = 'unavailable';
    await c.startListening();
    expect(c.reply, NovaController.offlineNoSpeech);
    expect(c.state, isNot(NovaState.listening));
  });

  test('"Hey NOVA" heard again right after waking: NOVA listens once more', () async {
    api.transcript = 'Hello NOVA';
    native.recording =
        const NovaRecording(status: 'ok', path: '/tmp/none.m4a', durationMs: 1800, hadSpeech: true);
    await c.startListening();
    native.controller.add(const NovaRecordingStoppedEvent('silence'));
    await settle();
    expect(c.state, NovaState.listening);
    expect(native.recordStarts, 2);
    expect(native.spoken, contains("I'm listening."));

    // Only once: hearing just the wake phrase again ends with the greeting.
    native.controller.add(const NovaRecordingStoppedEvent('silence'));
    await settle();
    expect(c.state, isNot(NovaState.listening));
    expect(native.recordStarts, 2);
  });

  test('play a song: asks for music access first, then plays it', () async {
    native.results['play_music'] = const NovaNativeResult(
        'success', {'kind': 'song', 'title': 'Like You', 'artist': 'Tatiana Manaois'});
    await c.submitText('Hey NOVA, play me Tatiana Like You');
    expect(c.state, NovaState.permissionRequired);
    expect(c.permissionKind, 'audio');
    expect(api.chatCalls, isEmpty);

    await c.grantPermission();
    expect(native.actions.last, 'play_music:tatiana like you');
    expect(c.reply, 'Playing Like You by Tatiana Manaois.');
  });

  test('"play my music" with nothing queued asks for music access (not contacts)', () async {
    native.results['music_control'] = const NovaNativeResult('not_playing', {});
    await c.submitText('play my music');
    expect(c.state, NovaState.permissionRequired);
    expect(c.permissionKind, 'audio');
  });

  test('several matching songs: NOVA asks which one, then plays the choice', () async {
    native.audioGranted = true;
    native.results['play_music'] = const NovaNativeResult('choices', {
      'matches': [
        {'id': '11', 'title': 'Like You', 'artist': 'Tatiana Manaois'},
        {'id': '12', 'title': 'Like You (Remix)', 'artist': 'Tatiana Manaois'},
      ],
    });
    await c.submitText('play like you');
    expect(c.state, NovaState.clarifying);
    expect(c.choices.map((x) => x.label), ['Like You', 'Like You (Remix)']);

    native.results['play_music'] = const NovaNativeResult(
        'success', {'kind': 'song', 'title': 'Like You (Remix)', 'artist': 'Tatiana Manaois'});
    await c.choose(c.choices.last);
    expect(native.actions.last, 'play_music:|12');
    expect(c.reply, 'Playing Like You (Remix) by Tatiana Manaois.');
  });

  test('a song that is not on the phone: offers to search online', () async {
    native.audioGranted = true;
    native.results['play_music'] = const NovaNativeResult('not_found', {});
    await c.submitText('play essence');
    expect(c.state, NovaState.clarifying);
    expect(c.choices.map((x) => x.label), ['Search YouTube', 'Search Spotify']);
  });

  test('music controls: "next song" and "pause" go to NOVA Music', () async {
    native.results['music_control'] =
        const NovaNativeResult('success', {'title': 'Essence', 'artist': 'Wizkid'});
    await c.submitText('next song');
    expect(native.actions.last, 'music_control:next');
    expect(c.reply, 'Next up: Essence by Wizkid.');
    await c.submitText('pause');
    expect(native.actions.last, 'music_control:pause');
    expect(c.reply, 'Paused.');
  });

  group('photos and screen in the assistant panel (3.4.0)', () {
    const img = NovaVisionImage([0xFF, 0xD8, 0xFF, 0x00], 'image/jpeg');

    test('a question with a photo goes to /vision, never to actions', () async {
      c.addImages([img]);
      expect(c.pendingImages.length, 1);
      await c.submitText('open youtube');
      expect(api.visionCalls, ['open youtube']);
      expect(api.lastImageCount, 1);
      expect(native.actions, isEmpty);
      expect(api.chatCalls, isEmpty);
      expect(c.reply, 'It is a login form.');
      expect(c.pendingImages, isEmpty);
      expect(c.history.toJson().first['content'], '(I shared a photo.) open youtube');
    });

    test('screen capture: default question and replacement of an older capture', () async {
      c.addImages([img], fromScreen: true);
      c.addImages([img], fromScreen: true);
      expect(c.pendingImages.length, 1);
      expect(c.pendingIsScreen, isTrue);
      await c.askAboutImages();
      expect(api.visionCalls.single, startsWith('This is a screenshot of my phone screen.'));
      expect(c.transcript, 'What is on my screen?');
    });

    test('at most 3 photos; remove and clear', () {
      c.addImages([img, img, img, img]);
      expect(c.pendingImages.length, 3);
      c.removeImage(0);
      expect(c.pendingImages.length, 2);
      c.clearImages();
      expect(c.pendingImages, isEmpty);
      expect(c.pendingIsScreen, isFalse);
    });

    test('"cancel" still cancels with a photo attached', () async {
      c.addImages([img]);
      await c.submitText('cancel');
      expect(api.visionCalls, isEmpty);
    });

    test('links in answers open in NOVA X (web links only)', () async {
      await c.openLink('https://flutter.dev');
      await c.openLink('javascript:alert(1)');
      expect(host.opened, ['https://flutter.dev']);
    });
  });

  group('NOVA Network answers (3.6.0)', () {
    test('"what\'s my internet speed" runs a real test, never the AI', () async {
      await c.submitText("Hey NOVA, what's my internet speed?");
      expect(network.tests, 1);
      expect(api.chatCalls, isEmpty);
      expect(native.actions, isEmpty);
      expect(c.reply, contains('**Download:** 131.30 Mbps'));
      expect(native.spoken.last, startsWith('Your internet speed on Zenlayer is 131 megabits per second'));
      expect(c.state, NovaState.idle);
    });

    test('ping, IP address and battery', () async {
      await c.submitText("what's my ping");
      expect(c.reply, 'Your ping to the nearest server is 23 milliseconds. That is great for gaming and calls.');
      await c.submitText('what is my IP address');
      expect(c.reply, 'Your public IP address is 31.57.228.94 from Zenlayer, near Dubai, AE.');
      await c.submitText("what's my battery percentage");
      expect(c.reply, 'Your battery is at 76 percent and charging.');
    });

    test('a failed test is reported honestly', () async {
      network.error = const SpeedTestException("Can't reach the internet. Check Wi-Fi or mobile data.");
      await c.submitText('run a speed test');
      expect(c.state, NovaState.error);
      expect(c.reply, "Can't reach the internet. Check Wi-Fi or mobile data.");
    });

    test('"open NOVA Network" opens the page', () async {
      await c.submitText('open NOVA Network');
      expect(host.opened, ['feature:nova_network']);
      expect(network.tests, 0);
    });
  });

  test('greetings are short, friendly and fit the time of day', () {
    final morning = {for (var i = 0; i < 6; i++) NovaConfig.greetingFor(DateTime(2026, 1, 1, 8), i)};
    expect(morning.length, 3);
    expect(morning.every((g) => !g.contains('NOVA')), isTrue);
    expect(NovaConfig.greetingFor(DateTime(2026, 1, 1, 20), 0), contains('evening'));
    expect(NovaConfig.greetingFor(DateTime(2026, 1, 1, 2), 0), contains('night owl'));
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
