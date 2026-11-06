// lib/features/playback/playback_player.dart
//
// AI Playback (3.12.0): the player — a mini bar above the browser's bottom
// bar (play/pause, title, close, progress) and a full sheet (progress bar,
// −10 s / play / +10 s, speed, 👍 👎, and who is speaking).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_theme.dart';
import 'playback_engine.dart';
import 'playback_models.dart';

const _kPink = Color(0xFFFF6FA8); // Ava
const _kBlue = Color(0xFF4DA3FF); // Leo
const _kSheet = Color(0xFF111827);

class PlaybackMiniBar extends StatelessWidget {
  const PlaybackMiniBar({super.key, required this.engine, required this.onOpen, required this.onClose});

  final PlaybackEngine engine;
  final VoidCallback onOpen;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: engine,
      builder: (context, _) {
        final e = engine;
        final preparing = e.phase == PlaybackPhase.preparing;
        final failed = e.phase == PlaybackPhase.error;
        final progress = e.total > 0 ? (e.position / e.total).clamp(0.0, 1.0) : 0.0;
        return Material(
          color: _kSheet,
          child: InkWell(
            onTap: preparing || failed ? null : onOpen,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
                child: Row(children: [
                  _RoundButton(
                    size: 46,
                    onTap: preparing || failed ? null : e.toggle,
                    child: preparing
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2, color: AppTheme.accentCyan))
                        : Icon(
                            failed
                                ? Icons.error_outline_rounded
                                : e.isPlaying
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                            color: failed ? AppTheme.warning : Colors.white,
                            size: 28),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Text(
                        failed ? (e.error ?? 'AI Playback stopped.') : (e.script?.title ?? 'Preparing AI playback…'),
                        maxLines: failed ? 2 : 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        preparing
                            ? 'Reading the page and writing the conversation…'
                            : failed
                                ? 'AI playback'
                                : 'AI playback · ${e.current?.speaker ?? ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 11.5),
                      ),
                    ]),
                  ),
                  IconButton(
                    tooltip: 'Close AI playback',
                    onPressed: onClose,
                    icon: const Icon(Icons.close_rounded, color: Colors.white, size: 24),
                  ),
                ]),
              ),
              LinearProgressIndicator(
                value: preparing ? null : progress,
                minHeight: 3,
                backgroundColor: Colors.white12,
                valueColor: const AlwaysStoppedAnimation(Color(0xFFA8C7FA)),
              ),
            ]),
          ),
        );
      },
    );
  }
}

/// The full player.
Future<void> showPlaybackSheet(BuildContext context, PlaybackEngine engine) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: _kSheet,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (_) => _PlaybackSheet(engine: engine),
  );
}

class _PlaybackSheet extends StatefulWidget {
  const _PlaybackSheet({required this.engine});
  final PlaybackEngine engine;

  @override
  State<_PlaybackSheet> createState() => _PlaybackSheetState();
}

class _PlaybackSheetState extends State<_PlaybackSheet> {
  double? _drag; // seconds while the slider is held

  static const _speeds = [0.75, 1.0, 1.25, 1.5, 2.0];

  String _speedLabel(double v) => '${v == v.roundToDouble() ? v.toInt() : v}x';

  @override
  Widget build(BuildContext context) {
    final e = widget.engine;
    return AnimatedBuilder(
      animation: e,
      builder: (context, _) {
        final s = e.script;
        final total = e.total;
        final pos = _drag ?? e.position;
        final line = e.current;
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 18),
              Text('AI playback', style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 13)),
              const SizedBox(height: 6),
              Text(s?.title ?? '',
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              if (s != null && s.host.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(20)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.public_rounded, color: AppTheme.textSecondary, size: 14),
                    const SizedBox(width: 6),
                    Text(s.host, style: GoogleFonts.inter(color: Colors.white, fontSize: 12.5)),
                  ]),
                ),
              const SizedBox(height: 18),
              // Who is speaking, and what.
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: line == null
                    ? const SizedBox(height: 74)
                    : Container(
                        key: ValueKey('${e.index}'),
                        width: double.infinity,
                        constraints: const BoxConstraints(minHeight: 74),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: (line.female ? _kPink : _kBlue).withOpacity(0.08),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: (line.female ? _kPink : _kBlue).withOpacity(0.25)),
                        ),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          CircleAvatar(
                            radius: 15,
                            backgroundColor: (line.female ? _kPink : _kBlue).withOpacity(0.2),
                            child: Text(line.speaker[0],
                                style: GoogleFonts.inter(color: line.female ? _kPink : _kBlue, fontWeight: FontWeight.w800, fontSize: 13)),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(line.speaker,
                                  style: GoogleFonts.inter(color: line.female ? _kPink : _kBlue, fontSize: 11.5, fontWeight: FontWeight.w700)),
                              const SizedBox(height: 3),
                              Text(line.text,
                                  maxLines: 4,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(color: Colors.white, fontSize: 13, height: 1.4)),
                            ]),
                          ),
                        ]),
                      ),
              ),
              const SizedBox(height: 14),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 5,
                  activeTrackColor: const Color(0xFFA8C7FA),
                  inactiveTrackColor: Colors.white24,
                  thumbColor: Colors.white,
                  overlayColor: Colors.white12,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                ),
                child: Slider(
                  min: 0,
                  max: total > 0 ? total : 1,
                  value: pos.clamp(0.0, total > 0 ? total : 1.0),
                  onChanged: s == null ? null : (v) => setState(() => _drag = v),
                  onChangeEnd: s == null
                      ? null
                      : (v) {
                          setState(() => _drag = null);
                          e.seekTo(v);
                        },
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Row(children: [
                  Text(playbackClock(pos), style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 12)),
                  const Spacer(),
                  Text(playbackClock(total), style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 12)),
                ]),
              ),
              const SizedBox(height: 14),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                _RoundButton(size: 64, onTap: () => e.skip(-10), child: const Icon(Icons.replay_10_rounded, color: Colors.white, size: 30)),
                const SizedBox(width: 22),
                _RoundButton(
                  size: 86,
                  wide: true,
                  onTap: e.toggle,
                  child: Icon(e.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.white, size: 40),
                ),
                const SizedBox(width: 22),
                _RoundButton(size: 64, onTap: () => e.skip(10), child: const Icon(Icons.forward_10_rounded, color: Colors.white, size: 30)),
              ]),
              const SizedBox(height: 18),
              Row(children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: const Color(0xFFA8C7FA), borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.graphic_eq_rounded, color: Color(0xFF0B1A33), size: 24),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () {
                    final i = _speeds.indexOf(e.speed);
                    e.setSpeed(_speeds[(i + 1) % _speeds.length]);
                  },
                  child: Text(_speedLabel(e.speed), style: GoogleFonts.inter(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Good playback',
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    e.rate(1);
                  },
                  icon: Icon(e.feedback == 1 ? Icons.thumb_up_alt_rounded : Icons.thumb_up_off_alt_rounded, color: Colors.white),
                ),
                IconButton(
                  tooltip: 'Bad playback',
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    e.rate(-1);
                  },
                  icon: Icon(e.feedback == -1 ? Icons.thumb_down_alt_rounded : Icons.thumb_down_off_alt_rounded, color: Colors.white),
                ),
              ]),
              const SizedBox(height: 6),
              Text('AI-generated from this page’s text. It can make mistakes — check the page for details.',
                  textAlign: TextAlign.center, style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 11)),
            ]),
          ),
        );
      },
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.size, required this.child, this.onTap, this.wide = false});
  final double size;
  final Widget child;
  final VoidCallback? onTap;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withOpacity(0.08),
      shape: wide ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(size / 2)) : const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: wide ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(size / 2)) : const CircleBorder(),
        child: SizedBox(width: wide ? size * 1.5 : size, height: size, child: Center(child: child)),
      ),
    );
  }
}
