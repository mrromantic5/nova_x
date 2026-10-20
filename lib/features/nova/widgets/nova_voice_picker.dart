// lib/features/nova/widgets/nova_voice_picker.dart
//
// NOVA settings → Voice → "NOVA voice": choose the voice NOVA speaks with.
// Tapping a voice selects it (saved at once) and plays a short preview.
// Only voices the NOVA Voice service offers are listed; when the service
// can't be reached, the standard voices every version has are shown.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_theme.dart';
import '../services/nova_native.dart';
import '../services/nova_voice.dart';

/// Shows the voice list. [onSelected] is called as soon as a voice is chosen.
Future<void> showNovaVoicePicker(
  BuildContext context, {
  required String current,
  required ValueChanged<String> onSelected,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _NovaVoicePicker(current: current, onSelected: onSelected),
  );
}

class _NovaVoicePicker extends StatefulWidget {
  const _NovaVoicePicker({required this.current, required this.onSelected});

  final String current;
  final ValueChanged<String> onSelected;

  @override
  State<_NovaVoicePicker> createState() => _NovaVoicePickerState();
}

class _NovaVoicePickerState extends State<_NovaVoicePicker> {
  static const String _sample = "Hi, I'm NOVA, your assistant in NOVA X. This is how I sound.";

  late String _selected = widget.current;
  late String _previewVoice = widget.current;

  /// Voices the service offers (null while checking or when unreachable).
  Set<String>? _available;
  bool _checked = false;

  late final NovaCloudVoice _preview = NovaCloudVoice(
    native: NovaNative.instance,
    voiceName: () => _previewVoice,
    fallbackToPhone: false,
  );
  StreamSubscription<String>? _previewSub;
  String? _utterance;
  String? _playing; // voice being previewed
  bool _starting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _previewSub = _preview.completed.listen((id) {
      if (mounted && id == _utterance) {
        setState(() {
          _playing = null;
          _utterance = null;
        });
      }
    });
    NovaCloudVoice.availableVoices().then((voices) {
      if (!mounted) return;
      setState(() {
        _available = (voices == null || voices.isEmpty) ? null : voices;
        _checked = true;
      });
    });
  }

  @override
  void dispose() {
    _previewSub?.cancel();
    _preview.dispose();
    super.dispose();
  }

  /// The voices to list: those the service offers (the standard ones when it
  /// can't be reached), always including the current choice.
  List<NovaVoiceInfo> get _voices {
    final available = _available;
    return [
      for (final v in NovaVoiceCatalog.voices)
        if (v.key == _selected ||
            (available != null ? available.contains(v.key) : NovaVoiceCatalog.original.contains(v.key)))
          v,
    ];
  }

  void _select(NovaVoiceInfo voice) {
    HapticFeedback.selectionClick();
    if (voice.key != _selected) {
      setState(() => _selected = voice.key);
      widget.onSelected(voice.key);
    }
    _play(voice.key, restart: true);
  }

  Future<void> _play(String key, {bool restart = false}) async {
    if (_playing == key && !restart) {
      await _stopPreview();
      return;
    }
    final utterance = 'nova_voice_preview_${key}_${DateTime.now().millisecondsSinceEpoch}';
    await _preview.stop();
    if (!mounted) return;
    setState(() {
      _previewVoice = key;
      _utterance = utterance;
      _playing = key;
      _starting = true;
      _error = null;
    });
    final ok = await _preview.speak(_sample, utterance);
    if (!mounted || _utterance != utterance) return; // another preview started
    setState(() {
      _starting = false;
      if (!ok) {
        _playing = null;
        _utterance = null;
        _error = "Couldn't play a preview. Check your internet connection — "
            'NOVA uses your phone\'s own voice while offline.';
      }
    });
  }

  Future<void> _stopPreview() async {
    _utterance = null;
    await _preview.stop();
    if (mounted) {
      setState(() {
        _playing = null;
        _starting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    final voices = _voices;
    return DraggableScrollableSheet(
      initialChildSize: 0.78,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scroll) => Container(
        decoration: const BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(top: 12, bottom: 12),
            decoration: BoxDecoration(color: AppTheme.divider, borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 12, 4),
            child: Row(children: [
              Expanded(
                child: Text('NOVA voice',
                    style: GoogleFonts.spaceGrotesk(
                        color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Done',
                    style: GoogleFonts.inter(color: AppTheme.accentCyan, fontWeight: FontWeight.w700)),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              !_checked
                  ? 'Checking the voices available…'
                  : _available == null
                      ? "NOVA Voice can't be reached right now, so only the standard voices are shown. "
                          'Previews need the internet.'
                      : 'Tap a voice to choose it and hear how it sounds.',
              style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 12, height: 1.4),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(_error!,
                  style: GoogleFonts.inter(color: AppTheme.warning, fontSize: 12, height: 1.4)),
            ),
          Expanded(
            child: ListView(
              controller: scroll,
              padding: EdgeInsets.fromLTRB(12, 0, 12, bottom + 16),
              children: [
                for (final region in NovaVoiceCatalog.regions)
                  ..._regionTiles(region, voices.where((v) => v.region == region).toList()),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  List<Widget> _regionTiles(String region, List<NovaVoiceInfo> voices) {
    if (voices.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 14, 8, 6),
        child: Text(region.toUpperCase(),
            style: GoogleFonts.inter(
                color: AppTheme.textHint, fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 1.1)),
      ),
      for (final v in voices) _voiceTile(v),
    ];
  }

  Widget _voiceTile(NovaVoiceInfo v) {
    final selected = v.key == _selected;
    final playing = v.key == _playing;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: selected ? AppTheme.bgElevated : AppTheme.bgDark,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _select(v),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: selected ? AppTheme.accentCyan.withOpacity(0.6) : AppTheme.divider),
            ),
            child: Row(children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: selected ? AppTheme.primaryGradient : null,
                  color: selected ? null : AppTheme.bgCard,
                ),
                child: Text(v.label.isEmpty ? '?' : v.label[0],
                    style: GoogleFonts.spaceGrotesk(
                        color: selected ? Colors.white : AppTheme.textSecondary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Flexible(
                      child: Text(v.label,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                              color: AppTheme.textPrimary,
                              fontSize: 14,
                              fontWeight: selected ? FontWeight.w700 : FontWeight.w600)),
                    ),
                    if (v.key == NovaVoiceCatalog.defaultVoice)
                      Container(
                        margin: const EdgeInsets.only(left: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppTheme.accentCyan.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text('Default',
                            style: GoogleFonts.inter(color: AppTheme.accentCyan, fontSize: 9.5)),
                      ),
                  ]),
                  const SizedBox(height: 2),
                  Text(v.description,
                      style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 11.5)),
                ]),
              ),
              if (selected)
                const Padding(
                  padding: EdgeInsets.only(right: 2),
                  child: Icon(Icons.check_circle_rounded, color: AppTheme.accentCyan, size: 19),
                ),
              IconButton(
                tooltip: playing ? 'Stop preview' : 'Play preview',
                onPressed: () => _play(v.key),
                icon: playing && _starting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accentCyan),
                      )
                    : Icon(playing ? Icons.stop_circle_outlined : Icons.play_circle_outline_rounded,
                        color: playing ? AppTheme.accentCyan : AppTheme.textSecondary, size: 24),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
