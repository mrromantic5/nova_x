// lib/features/nova_capture/screens/recording_settings_screen.dart
//
// Recording and screenshot settings. The phone's encoder has the final say:
// if it can't record at the chosen size or frame rate, NOVA X steps down to
// the closest supported value (never promised for every phone).

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../controllers/capture_controller.dart';
import '../models/capture_settings.dart';
import '../models/media_asset.dart';
import '../widgets/capture_flows.dart';
import '../widgets/capture_ui.dart';

class RecordingSettingsScreen extends StatefulWidget {
  const RecordingSettingsScreen({super.key});

  @override
  State<RecordingSettingsScreen> createState() => _RecordingSettingsScreenState();
}

class _RecordingSettingsScreenState extends State<RecordingSettingsScreen> with WidgetsBindingObserver {
  final _c = CaptureController.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _c.init().then((_) => _c.refreshCapabilities());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _c.refreshCapabilities();
  }

  Future<void> _set(RecordingSettings s) => _c.updateSettings(s);

  Future<void> _pick<T>(String title, List<T> values, T current, String Function(T) label, void Function(T) onPick,
      {String Function(T)? subtitle, bool Function(T)? enabled}) async {
    final v = await showModalBottomSheet<T>(
      context: context,
      backgroundColor: AppTheme.bgElevated,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
              child: Text(title, style: captureText(16, weight: FontWeight.w800)),
            ),
            for (final x in values)
              ListTile(
                enabled: enabled?.call(x) ?? true,
                leading: Icon(x == current ? Icons.radio_button_checked : Icons.radio_button_off,
                    color: AppTheme.accentCyan),
                title: Text(label(x), style: captureText(14)),
                subtitle: subtitle == null ? null : Text(subtitle(x), style: captureText(12, color: AppTheme.textSecondary)),
                onTap: () => Navigator.pop(ctx, x),
              ),
          ]),
        ),
      ),
    );
    if (v != null) onPick(v);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      appBar: AppBar(
        backgroundColor: AppTheme.bgDark,
        elevation: 0,
        title: Text('Capture settings', style: captureText(18, weight: FontWeight.w800)),
      ),
      body: ListenableBuilder(
        listenable: _c,
        builder: (context, _) {
          final s = _c.settings;
          final shot = _c.shotSettings;
          final caps = _c.capabilities;
          final perMin = s.estimatedBytesPerMinute();
          final recording = _c.state.isActive;
          return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 32), children: [
            if (recording)
              CaptureCard(
                borderColor: CaptureColors.paused.withOpacity(0.5),
                child: Text('Changes apply to your next recording.', style: captureText(13.5)),
              ),
            const CaptureSectionTitle('Video'),
            CaptureCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(children: [
                _row(Icons.high_quality_rounded, 'Resolution', s.resolutionLabel, () => _pick<String>(
                      'Resolution', RecordingSettings.resolutions, s.resolution,
                      (v) => v == 'auto' ? 'Auto (best up to 1080p)' : '${v}p',
                      (v) => _set(s.copyWith(resolution: v)),
                      subtitle: (v) => v == 'auto' ? 'Recommended' : 'If your phone can’t, the next lower size is used',
                    )),
                _row(Icons.speed_rounded, 'Frame rate', '${s.fps} fps', () => _pick<int>(
                      'Frame rate', RecordingSettings.frameRates, s.fps, (v) => '$v fps',
                      (v) => _set(s.copyWith(fps: v)),
                      subtitle: (v) => switch (v) {
                        24 => 'Smaller files',
                        60 => 'Smoothest — not every phone supports it',
                        _ => 'Recommended',
                      },
                    )),
                _row(Icons.data_usage_rounded, 'Quality', s.bitrateLabel, () => _pick<String>(
                      'Quality (bit rate)', RecordingSettings.bitrates, s.bitrate,
                      (v) => RecordingSettings(bitrate: v).bitrateLabel,
                      (v) => _set(s.copyWith(bitrate: v)),
                    )),
                _row(Icons.screen_rotation_rounded, 'Orientation', s.orientationLabel, () => _pick<String>(
                      'Orientation', RecordingSettings.orientations, s.orientation,
                      (v) => RecordingSettings(orientation: v).orientationLabel,
                      (v) => _set(s.copyWith(orientation: v)),
                      subtitle: (v) => v == 'auto' ? 'Decided when the recording starts' : 'Rotating mid-recording adds black bars',
                    )),
                _row(Icons.timer_outlined, 'Time limit', s.durationLabel, () => _pick<int>(
                      'Stop automatically after', RecordingSettings.durations, s.maxDurationSec,
                      (v) => v == 0 ? 'No limit' : '${v ~/ 60} minutes',
                      (v) => _set(s.copyWith(maxDurationSec: v)),
                    )),
                _row(Icons.hourglass_bottom_rounded, 'Countdown', s.countdownSec == 0 ? 'Off' : '${s.countdownSec} seconds',
                    () => _pick<int>(
                          'Countdown before recording', RecordingSettings.countdowns, s.countdownSec,
                          (v) => v == 0 ? 'Off' : '$v seconds',
                          (v) => _set(s.copyWith(countdownSec: v)),
                          subtitle: (v) => 'Time to switch to what you want to record',
                        )),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 8, 6, 0),
              child: Text('About ${formatBytes(perMin)} per minute (estimate — the screen content decides).',
                  style: captureText(12, color: AppTheme.textHint)),
            ),
            const CaptureSectionTitle('Sound'),
            CaptureCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(children: [
                for (final m in CaptureAudioMode.values)
                  RadioListTile<CaptureAudioMode>(
                    value: m,
                    groupValue: s.audio,
                    activeColor: AppTheme.accentCyan,
                    onChanged: m.usesDeviceAudio && !caps.deviceAudio
                        ? null
                        : (v) async {
                            if (v == null) return;
                            if (v.needsRecordPermission && !caps.micGranted) {
                              if (!await CapturePermissionSheet.microphone(context)) return;
                              final g = await _c.requestPermissions(['mic']);
                              if (g['mic'] != true) {
                                captureToast('The microphone isn’t allowed, so recordings stay without sound.', ok: false);
                                if (g['micCanAsk'] != true) await _c.openAppSettings();
                                return;
                              }
                            }
                            await _set(s.copyWith(audio: v));
                          },
                    title: Text(m.label, style: captureText(14, weight: FontWeight.w600)),
                    subtitle: Text(
                      m.usesDeviceAudio && !caps.deviceAudio ? 'Needs Android 10 or newer' : m.description,
                      style: captureText(12, color: AppTheme.textSecondary),
                    ),
                  ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 8, 6, 0),
              child: Text(
                'While a recording with sound runs, NOVA answers in text instead of speaking, so its voice isn’t recorded. '
                'With the microphone on, “Hey NOVA” pauses — use the on-screen or notification controls.',
                style: captureText(12, color: AppTheme.textHint),
              ),
            ),
            const CaptureSectionTitle('Controls'),
            CaptureCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: SwitchListTile(
                value: _c.bubbleEnabled,
                activeColor: AppTheme.accentCyan,
                title: Text('Floating capture button', style: captureText(14, weight: FontWeight.w600)),
                subtitle: Text(
                  'A round button on your screen and over other apps: Record, Pause, Stop, Screenshot. '
                  'Drag it to move, drag it onto ✕ to close. Needs “Display over other apps”.',
                  style: captureText(12, color: AppTheme.textSecondary),
                ),
                onChanged: (on) => CaptureFlows.toggleBubble(context, on),
              ),
            ),
            const CaptureSectionTitle('Screenshots'),
            CaptureCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(children: [
                _row(Icons.image_rounded, 'Edited copy format', shot.format.toUpperCase(), () => _pick<String>(
                      'Format for edited copies', ScreenshotSettings.formats, shot.format, (v) => v.toUpperCase(),
                      (v) => _c.updateShotSettings(shot.copyWith(format: v)),
                      subtitle: (v) => switch (v) {
                        'png' => 'Lossless (screenshots are always captured as PNG)',
                        'jpeg' => 'Smaller files',
                        _ => 'Smallest files',
                      },
                    )),
                _row(Icons.timer_rounded, 'Entire-screen delay',
                    shot.screenDelaySec == 0 ? 'None' : '${shot.screenDelaySec} seconds', () => _pick<int>(
                          'Wait before capturing the screen', ScreenshotSettings.delays, shot.screenDelaySec,
                          (v) => v == 0 ? 'None' : '$v seconds',
                          (v) => _c.updateShotSettings(shot.copyWith(screenDelaySec: v)),
                        )),
                SwitchListTile(
                  value: shot.hideAppForScreen,
                  activeColor: AppTheme.accentCyan,
                  title: Text('Step NOVA X aside for entire-screen captures', style: captureText(14, weight: FontWeight.w600)),
                  subtitle: Text('Captures the app behind NOVA X instead of NOVA X itself',
                      style: captureText(12, color: AppTheme.textSecondary)),
                  onChanged: (v) => _c.updateShotSettings(shot.copyWith(hideAppForScreen: v)),
                ),
                SwitchListTile(
                  value: shot.copyToClipboard,
                  activeColor: AppTheme.accentCyan,
                  title: Text('Also copy new screenshots', style: captureText(14, weight: FontWeight.w600)),
                  subtitle: Text('Puts each new screenshot on the clipboard. Android shows when the clipboard is used.',
                      style: captureText(12, color: AppTheme.textSecondary)),
                  onChanged: (v) => _c.updateShotSettings(shot.copyWith(copyToClipboard: v)),
                ),
                SwitchListTile(
                  value: shot.saveWebMetadata,
                  activeColor: AppTheme.accentCyan,
                  title: Text('Remember page title and address', style: captureText(14, weight: FontWeight.w600)),
                  subtitle: Text(
                    'Stored only on this phone with webpage screenshots (never for private tabs). Turning it off erases them.',
                    style: captureText(12, color: AppTheme.textSecondary),
                  ),
                  onChanged: (v) => _c.updateShotSettings(shot.copyWith(saveWebMetadata: v)),
                ),
              ]),
            ),
          ]);
        },
      ),
    );
  }

  Widget _row(IconData icon, String title, String value, VoidCallback onTap) => ListTile(
        leading: Icon(icon, color: AppTheme.accentCyan),
        title: Text(title, style: captureText(14, weight: FontWeight.w600)),
        subtitle: Text(value, style: captureText(12.5, color: AppTheme.textSecondary)),
        trailing: const Icon(Icons.chevron_right_rounded, color: AppTheme.textHint),
        onTap: onTap,
      );
}
