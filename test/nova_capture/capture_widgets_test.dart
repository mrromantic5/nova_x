// test/nova_capture/capture_widgets_test.dart
//
// NOVA Capture widgets: the recording indicator (never colour-only), the
// floating controls (visible and working while recording, gone when idle),
// and the explanation shown before any Android permission dialog.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nova_x/features/nova_capture/controllers/capture_controller.dart';
import 'package:nova_x/features/nova_capture/models/capture_models.dart';
import 'package:nova_x/features/nova_capture/services/capture_platform.dart';
import 'package:nova_x/features/nova_capture/widgets/capture_ui.dart';
import 'package:nova_x/features/nova_capture/widgets/floating_recording_controls.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> pushState(Map<String, Object?> state) async {
  final data = const StandardMethodCodec().encodeMethodCall(MethodCall('capture.state', state));
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(CapturePlatform.channelName, data, (_) {});
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];

  setUpAll(() async {
    captureUseGoogleFonts = false; // no font downloads in tests
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel(CapturePlatform.channelName),
      (call) async {
        calls.add(call);
        return switch (call.method) {
          'getState' => {'state': 'idle', 'sessionId': 0},
          'capabilities' => {'sdk': 34, 'micGranted': true},
          'pauseRecording' => {'success': true, 'state': 'paused'},
          _ => {'success': false, 'errorCode': 'ERROR'},
        };
      },
    );
    await CaptureController.instance.init();
  });

  testWidgets('recording indicator says what is happening in words', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: RecordingStatusIndicator(state: RecordingState.paused, elapsed: Duration(seconds: 75)),
      ),
    ));
    expect(find.text('Paused · 1:15'), findsOneWidget);
    expect(find.bySemanticsLabel('Recording paused at 1:15'), findsOneWidget);
  });

  testWidgets('floating controls appear only while recording and pause works', (tester) async {
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => CaptureOverlayHost(child: child!),
      home: const Scaffold(body: Text('page')),
    ));
    expect(find.bySemanticsLabel('Stop and save recording'), findsNothing);

    await pushState({'state': 'recording', 'sessionId': 21, 'elapsedMs': 3000});
    await tester.pump();
    expect(find.bySemanticsLabel('Stop and save recording'), findsOneWidget);
    expect(find.bySemanticsLabel('Pause recording'), findsOneWidget);
    expect(find.text('page'), findsOneWidget, reason: 'the page underneath stays usable');

    await tester.tap(find.byIcon(Icons.pause_rounded));
    await tester.pump();
    final pause = calls.lastWhere((c) => c.method == 'pauseRecording');
    expect((pause.arguments as Map)['sessionId'], 21);

    await pushState({'state': 'idle', 'sessionId': 21});
    await tester.pump();
    expect(find.bySemanticsLabel('Stop and save recording'), findsNothing);
    // Stop the 1 s timer the controller runs while recording.
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('countdown is shown before recording starts', (tester) async {
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => CaptureOverlayHost(child: child!),
      home: const Scaffold(body: SizedBox()),
    ));
    await pushState({'state': 'starting', 'sessionId': 22, 'countdown': 3});
    await tester.pump();
    expect(find.text('3'), findsOneWidget);
    await pushState({'state': 'idle', 'sessionId': 22});
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('permission explanation comes first and can be declined', (tester) async {
    bool? answer;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async => answer = await CapturePermissionSheet.recording(context),
            child: const Text('go'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('Record your screen'), findsOneWidget);
    expect(find.textContaining('asks every time'), findsOneWidget);
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(answer, isFalse);
  });
}
