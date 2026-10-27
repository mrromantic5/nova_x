// lib/features/nova_capture/widgets/floating_recording_controls.dart
//
// Recording controls that float over every NOVA X screen while a recording
// runs (inside NOVA X no special permission is needed). Over other apps the
// notification — and, if the user turned it on, the native floating pill —
// take over. The recording indicator stays visible on every screen; it can be
// dragged and shrunk but not hidden while recording.

import 'dart:math' as math;
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/nova_toast.dart';
import '../controllers/capture_controller.dart';
import '../models/capture_models.dart';
import '../models/media_asset.dart';
import '../screens/capture_dashboard.dart';
import 'capture_flows.dart';
import 'capture_ui.dart';

/// Wrap MaterialApp's child with this (MaterialApp.builder).
class CaptureOverlayHost extends StatelessWidget {
  const CaptureOverlayHost({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      child,
      ListenableBuilder(
        listenable: CaptureController.instance,
        builder: (context, _) {
          final c = CaptureController.instance;
          final s = c.snapshot.state;
          if (s == RecordingState.starting && c.snapshot.countdown > 0) {
            return _Countdown(seconds: c.snapshot.countdown);
          }
          if (!s.isCapturing && !s.isSaving) return const SizedBox.shrink();
          return const FloatingRecordingControls();
        },
      ),
    ]);
  }
}

class _Countdown extends StatelessWidget {
  const _Countdown({required this.seconds});
  final int seconds;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Center(
          child: Semantics(
            liveRegion: true,
            label: 'Screen recording starts in $seconds',
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: const Color(0xCC07101E),
                shape: BoxShape.circle,
                border: Border.all(color: CaptureColors.record, width: 3),
              ),
              alignment: Alignment.center,
              child: Text('$seconds', style: captureText(52, weight: FontWeight.w800)),
            ),
          ),
        ),
      ),
    );
  }
}

class FloatingRecordingControls extends StatefulWidget {
  const FloatingRecordingControls({super.key});

  @override
  State<FloatingRecordingControls> createState() => _FloatingRecordingControlsState();
}

class _FloatingRecordingControlsState extends State<FloatingRecordingControls> {
  Offset? _pos;
  bool _collapsed = false;
  bool _busy = false;

  CaptureController get _c => CaptureController.instance;

  Future<void> _act(Future<void> Function() f) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await f();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openDashboard() {
    final nav = NovaToast.navigatorKey?.currentState;
    if (nav == null) return;
    nav.push(MaterialPageRoute(
      settings: const RouteSettings(name: 'nova/capture'),
      builder: (_) => const CaptureDashboard(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final size = media.size;
    final pos = _pos ?? Offset(12, size.height * 0.30);
    final s = _c.snapshot.state;
    final paused = s == RecordingState.paused;
    final saving = s.isSaving;
    final elapsed = _c.elapsed;

    final pill = Material(
      type: MaterialType.transparency,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xEE0F1E35),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: (paused ? CaptureColors.paused : CaptureColors.record).withOpacity(0.55)),
          boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 16, offset: Offset(0, 6))],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Semantics(
            button: true,
            label: _collapsed ? 'Show recording controls' : 'Shrink recording controls',
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => setState(() => _collapsed = !_collapsed),
              child: SizedBox(
                width: 44,
                height: 44,
                child: Icon(
                  saving
                      ? Icons.hourglass_top_rounded
                      : (paused ? Icons.pause_circle_filled_rounded : Icons.fiber_manual_record_rounded),
                  color: saving ? AppTheme.accentCyan : (paused ? CaptureColors.paused : CaptureColors.record),
                  size: 22,
                ),
              ),
            ),
          ),
          if (!_collapsed) ...[
            Semantics(
              button: true,
              label: saving
                  ? 'Saving recording. Open NOVA Capture'
                  : '${paused ? 'Paused at' : 'Recording'} ${formatDuration(elapsed)}. Open NOVA Capture',
              child: InkWell(
                onTap: _openDashboard,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                  child: ExcludeSemantics(
                    child: Text(
                      saving ? 'Saving…' : formatDuration(elapsed),
                      style: captureText(15, weight: FontWeight.w700)
                          .copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                    ),
                  ),
                ),
              ),
            ),
            if (!saving) ...[
              // No tooltip: these controls sit above the Navigator (no Overlay here).
              Semantics(
                button: true,
                label: paused ? 'Resume recording' : 'Pause recording',
                child: IconButton(
                onPressed: _busy
                    ? null
                    : () => _act(() async {
                          final r = paused ? await _c.resume() : await _c.pause();
                          captureReport(r);
                        }),
                icon: Icon(paused ? Icons.play_arrow_rounded : Icons.pause_rounded, color: Colors.white),
              ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 2),
                child: Semantics(
                  button: true,
                  label: 'Stop and save recording',
                  child: InkWell(
                    onTap: _busy ? null : () => _act(() async => CaptureFlows.stopAndSave()),
                    borderRadius: BorderRadius.circular(22),
                    child: Container(
                      height: 40,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(color: CaptureColors.record, borderRadius: BorderRadius.circular(22)),
                      alignment: Alignment.center,
                      child: ExcludeSemantics(
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.stop_rounded, color: Colors.white, size: 18),
                          const SizedBox(width: 4),
                          Text('Stop', style: captureText(13, weight: FontWeight.w800)),
                        ]),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ]),
      ),
    );

    return Positioned(
      left: pos.dx,
      top: pos.dy,
      child: GestureDetector(
        onPanUpdate: (d) {
          final next = pos + d.delta;
          final maxX = math.max(0.0, size.width - 60);
          final maxY = math.max(media.padding.top, size.height - 80);
          setState(() => _pos = Offset(
                next.dx.clamp(0.0, maxX).toDouble(),
                next.dy.clamp(media.padding.top, maxY).toDouble(),
              ));
        },
        child: pill,
      ),
    );
  }
}
