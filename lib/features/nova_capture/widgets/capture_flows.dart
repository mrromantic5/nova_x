// lib/features/nova_capture/widgets/capture_flows.dart
//
// The tap flows of NOVA Capture: explain → ask for what is needed → act →
// report the real result. Permissions are asked progressively, only when a
// feature needs them, and a "no" keeps the rest of NOVA X working.

import 'package:flutter/material.dart';

import '../controllers/capture_controller.dart';
import '../models/capture_models.dart';
import '../models/capture_settings.dart';
import '../models/media_asset.dart';
import '../screens/media_preview_screen.dart';
import '../services/media_library_service.dart';
import '../services/webpage_capture_service.dart';
import 'capture_ui.dart';

class CaptureFlows {
  CaptureFlows._();

  static CaptureController get _c => CaptureController.instance;

  /// Start a screen recording from a button.
  static Future<CaptureResult> startRecording(BuildContext context, {RecordingSettings? using}) async {
    await _c.init();
    if (_c.state.isActive) {
      return CaptureResult.failure(CaptureErrorCode.busy, 'A recording is already in progress.');
    }
    var settings = using ?? _c.settings;

    if (!await MediaLibraryService.instance.introSeen()) {
      if (!context.mounted) return CaptureResult.failure(CaptureErrorCode.cancelled);
      if (!await CapturePermissionSheet.recording(context)) return CaptureResult.failure(CaptureErrorCode.cancelled);
      await MediaLibraryService.instance.markIntroSeen();
    }

    await _c.refreshCapabilities();
    if (settings.audio.usesDeviceAudio && !_c.capabilities.deviceAudio) {
      settings = settings.copyWith(audio: settings.audio.usesMicrophone ? CaptureAudioMode.mic : CaptureAudioMode.none);
      captureToast('Recording app sound needs Android 10 or newer, so it is left out.', ok: false);
    }
    if (settings.audio.needsRecordPermission && !_c.capabilities.micGranted) {
      if (!context.mounted) return CaptureResult.failure(CaptureErrorCode.cancelled);
      final go = await CapturePermissionSheet.microphone(context);
      final granted = go ? (await _c.requestPermissions(['mic']))['mic'] == true : false;
      if (!granted) {
        settings = settings.copyWith(audio: CaptureAudioMode.none);
        captureToast('Recording without sound. You can allow the microphone later in Settings.', ok: false);
      }
    }
    if (!_c.capabilities.notificationsGranted && _c.capabilities.sdk >= 33) {
      if (!context.mounted) return CaptureResult.failure(CaptureErrorCode.cancelled);
      if (await CapturePermissionSheet.notifications(context)) await _c.requestPermissions(['notifications']);
    }
    if (_c.capabilities.needsStoragePermission) {
      final g = await _c.requestPermissions(['storage']);
      if (g['storage'] != true) {
        captureToast('NOVA X needs storage access on this Android version to save videos.', ok: false);
        return CaptureResult.failure(CaptureErrorCode.permission);
      }
    }

    final r = await _c.startRecording(using: settings);
    if (!r.success) captureReport(r);
    return r;
  }

  /// Stop & save, then tell the user where it went.
  static Future<CaptureResult> stopAndSave() async {
    final r = await _c.stop();
    if (!r.success) {
      captureReport(r);
      return r;
    }
    final saved = await _c.waitForSaved();
    if (saved.success) {
      captureToast('Saved to Movies › NOVA X › Recordings.', title: 'Recording saved');
    } else {
      captureReport(saved);
    }
    return saved;
  }

  /// Discard (asks first: nothing is saved).
  static Future<void> cancelRecording(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: CaptureCardColors.dialog,
        title: Text('Discard recording?', style: captureText(17, weight: FontWeight.w800)),
        content: Text('The video recorded so far will not be saved.', style: captureText(14)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep recording')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Discard', style: TextStyle(color: CaptureColors.record)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final r = await _c.cancel();
    captureReport(r, success: 'Recording discarded.');
  }

  /// Whole-screen screenshot from a button; opens the result.
  static Future<void> captureScreen(BuildContext context) async {
    await _c.init();
    if (!context.mounted) return;
    if (!await CapturePermissionSheet.screen(context)) return;
    await _c.refreshCapabilities();
    if (_c.capabilities.needsStoragePermission) {
      final g = await _c.requestPermissions(['storage']);
      if (g['storage'] != true) {
        captureToast('NOVA X needs storage access on this Android version to save screenshots.', ok: false);
        return;
      }
    }
    final r = await _c.captureScreen();
    if (!r.success) {
      captureReport(r);
      return;
    }
    final item = r.item;
    if (item != null && context.mounted) await openPreview(context, item, justCaptured: true);
  }

  /// Screenshot of the open web page (visible part or the full page).
  static Future<void> captureWebpage(BuildContext context, WebCaptureTarget target, {required bool fullPage}) async {
    await _c.init();
    if (target.captureProgress < 1.0 && context.mounted) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: CaptureCardColors.dialog,
          title: Text('Page still loading', style: captureText(17, weight: FontWeight.w800)),
          content: Text('Some parts may be missing. Capture it anyway?', style: captureText(14)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Wait')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Capture')),
          ],
        ),
      );
      if (go != true) return;
    }
    await _c.refreshCapabilities();
    if (_c.capabilities.needsStoragePermission) {
      final g = await _c.requestPermissions(['storage']);
      if (g['storage'] != true) {
        captureToast('NOVA X needs storage access on this Android version to save screenshots.', ok: false);
        return;
      }
    }
    if (fullPage) captureToast('Capturing the whole page…');
    final out = fullPage
        ? await WebpageCaptureService.captureFullPage(target)
        : await WebpageCaptureService.captureVisible(target);
    if (!out.ok) {
      captureToast(CaptureErrorCode.message(out.errorCode), ok: false);
      return;
    }
    final r = await _c.saveWebScreenshot(out.bytes!, from: target);
    if (!r.success || r.item == null) {
      captureReport(r);
      return;
    }
    if (out.truncated) captureToast('The page is very long, so the bottom part was left out.', ok: false);
    if (context.mounted) await openPreview(context, r.item!, justCaptured: true);
  }

  static Future<void> openPreview(BuildContext context, MediaAsset item, {bool justCaptured = false}) =>
      Navigator.of(context).push(MaterialPageRoute(
        settings: const RouteSettings(name: 'nova/capture_preview'),
        builder: (_) => MediaPreviewScreen(asset: item, justCaptured: justCaptured),
      ));
}

class CaptureCardColors {
  CaptureCardColors._();
  static const Color dialog = Color(0xFF162846);
}
