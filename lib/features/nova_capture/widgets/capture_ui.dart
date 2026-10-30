// lib/features/nova_capture/widgets/capture_ui.dart
//
// Shared look for NOVA Capture (NOVA X dark/glass theme): cards, section
// titles, the recording indicator and the plain-language permission
// explanations shown BEFORE any Android dialog.

import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/nova_toast.dart';
import '../models/capture_models.dart';
import '../models/media_asset.dart';

class CaptureColors {
  CaptureColors._();
  static const Color record = Color(0xFFFF3B4E);
  static const Color paused = Color(0xFFFFAB00);
  static const Color shot = AppTheme.accentCyan;
}

void captureToast(String message, {bool ok = true, String? title}) {
  NovaToast.show(message, title: title, kind: ok ? NovaToastKind.success : NovaToastKind.warning);
}

/// Shows the result of an operation in plain words (never "done" on failure).
void captureReport(CaptureResult r, {String? success}) {
  if (r.success) {
    if (success != null) captureToast(success);
  } else if (r.errorCode != CaptureErrorCode.cancelled) {
    captureToast(r.message, ok: false);
  }
}

/// Widget tests turn this off (they can't download fonts).
bool captureUseGoogleFonts = true;

TextStyle captureText(double size, {FontWeight weight = FontWeight.w500, Color color = AppTheme.textPrimary}) =>
    captureUseGoogleFonts
        ? GoogleFonts.inter(fontSize: size, fontWeight: weight, color: color)
        : TextStyle(fontSize: size, fontWeight: weight, color: color);

class CaptureCard extends StatelessWidget {
  const CaptureCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.borderColor});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: borderColor ?? AppTheme.glassBorder),
        ),
        child: child,
      );
}

class CaptureSectionTitle extends StatelessWidget {
  const CaptureSectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 4, 10),
        child: Row(children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(text.toUpperCase(),
                  style: captureText(11.5, weight: FontWeight.w700, color: AppTheme.textSecondary)
                      .copyWith(letterSpacing: 1.1)),
            ),
          ),
          if (trailing != null) trailing!,
        ]),
      );
}

/// Red dot + words. Status is never shown by colour alone.
class RecordingStatusIndicator extends StatelessWidget {
  const RecordingStatusIndicator({super.key, required this.state, required this.elapsed, this.compact = false});
  final RecordingState state;
  final Duration elapsed;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = switch (state) {
      RecordingState.recording => CaptureColors.record,
      RecordingState.paused => CaptureColors.paused,
      RecordingState.failed => AppTheme.danger,
      RecordingState.saved => AppTheme.success,
      _ => AppTheme.textSecondary,
    };
    final showTime = state.isCapturing || state.isSaving;
    final label = showTime ? '${state.label} · ${formatDuration(elapsed)}' : state.label;
    return Semantics(
      liveRegion: true,
      label: state == RecordingState.recording
          ? 'Recording, ${formatDuration(elapsed)}'
          : (state == RecordingState.paused ? 'Recording paused at ${formatDuration(elapsed)}' : label),
      child: ExcludeSemantics(
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(
            state == RecordingState.paused ? Icons.pause_circle_filled_rounded : Icons.fiber_manual_record_rounded,
            color: color,
            size: compact ? 12 : 16,
          ),
          const SizedBox(width: 6),
          Text(label,
              style: captureText(compact ? 12 : 14, weight: FontWeight.w700, color: color)
                  .copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
        ]),
      ),
    );
  }
}

/// What a permission is for, before Android asks. Returns true to continue.
class CapturePermissionSheet {
  CapturePermissionSheet._();

  static Future<bool> show(
    BuildContext context, {
    required IconData icon,
    required String title,
    required List<String> points,
    String confirm = 'Continue',
    String cancel = 'Not now',
  }) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppTheme.bgElevated,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppTheme.accentCyan.withOpacity(0.14),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: AppTheme.accentCyan),
            ),
            const SizedBox(height: 14),
            Text(title, style: captureText(18, weight: FontWeight.w800)),
            const SizedBox(height: 12),
            for (final p in points)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 3),
                    child: Icon(Icons.check_circle_rounded, size: 16, color: AppTheme.success),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(p, style: captureText(13.5, color: AppTheme.textSecondary))),
                ]),
              ),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    side: const BorderSide(color: AppTheme.glassBorder),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(cancel, style: captureText(14)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    backgroundColor: AppTheme.accentCyan,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(confirm, style: captureText(14, weight: FontWeight.w800, color: Colors.black)),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
    return ok == true;
  }

  static Future<bool> recording(BuildContext context) => show(
        context,
        icon: Icons.videocam_rounded,
        title: 'Record your screen',
        confirm: 'Continue',
        points: const [
          'Android will ask you to allow screen recording. NOVA X starts only after you allow it, and asks every time.',
          'A notification and a red indicator stay visible the whole time, with Pause and Stop & save.',
          'Videos are saved only on this phone (Movies › NOVA X). Nothing is uploaded or shared unless you share it.',
          'Notifications, passwords and private apps on screen will be in the video — check before you share.',
        ],
      );

  static Future<bool> screen(BuildContext context) => show(
        context,
        icon: Icons.screenshot_monitor_rounded,
        title: 'Capture your entire screen',
        points: const [
          'Android will ask you to allow screen capture. NOVA X takes one screenshot, then stops at once.',
          'NOVA X steps aside so the screen behind it is captured.',
          'Apps that block screenshots (such as banking apps) stay hidden.',
          'The screenshot is saved only on this phone (Pictures › NOVA X).',
        ],
      );

  static Future<bool> microphone(BuildContext context) => show(
        context,
        icon: Icons.mic_rounded,
        title: 'Record sound',
        confirm: 'Allow microphone',
        points: const [
          'Android needs the microphone permission to record your voice or app sound.',
          'The microphone is on only while a recording runs — never in the background, never when paused.',
          'Sound stays in the video on this phone. It is not sent to NOVA AI.',
        ],
      );

  static Future<bool> notifications(BuildContext context) => show(
        context,
        icon: Icons.notifications_active_rounded,
        title: 'Recording controls in notifications',
        confirm: 'Allow notifications',
        cancel: 'Skip',
        points: const [
          'Lets the recording notification show Pause and Stop & save while you use other apps.',
          'Without it, use the controls inside NOVA X (or the floating controls, if you turn them on).',
        ],
      );

  static Future<bool> bubble(BuildContext context) => show(
        context,
        icon: Icons.radio_button_checked_rounded,
        title: 'Floating capture button',
        confirm: 'Open Android settings',
        points: const [
          'A small round button stays on your screen — in NOVA X and over other apps.',
          'Tap it for Record, Pause, Stop, Screenshot and NOVA Capture. Drag it anywhere, or onto ✕ to close it.',
          'Android calls this “Display over other apps”. Turn it on for NOVA X on the next screen, then come back.',
          'It never records by itself: Android still asks before every recording or screenshot.',
        ],
      );

  static Future<bool> overlay(BuildContext context) => show(
        context,
        icon: Icons.picture_in_picture_alt_rounded,
        title: 'Floating controls over other apps',
        confirm: 'Open Android settings',
        points: const [
          'Shows a small Pause / Stop pill over other apps while you record. You can drag it or shrink it.',
          'Android calls this “Display over other apps”. Turn it on for NOVA X on the next screen, then come back.',
          'It is only shown during a recording. Without it, use the notification controls.',
        ],
      );
}
