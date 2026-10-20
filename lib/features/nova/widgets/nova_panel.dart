// lib/features/nova/widgets/nova_panel.dart
//
// NOVA's floating bottom assistant panel (used inside NOVA X as a bottom
// sheet, and by the floating assistant window over other apps).
// 3.4.0: answers are formatted (Markdown, code blocks); 📷 adds photos or
// screenshots, and over other apps "Read my screen" lets NOVA see the app
// in front (one screenshot, after Android's consent dialog).

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_theme.dart';
import '../../ai/widgets/nova_markdown_view.dart';
import '../controller/nova_controller.dart';
import '../models/nova_models.dart';
import 'nova_orb.dart';

class NovaPanel extends StatefulWidget {
  const NovaPanel({
    super.key,
    required this.controller,
    required this.onClose,
    required this.onToggleVoice,
    this.onExpand,
    this.onAddPhoto,
    this.onReadScreen,
  });

  final NovaController controller;
  final VoidCallback onClose;
  final ValueChanged<bool> onToggleVoice;

  /// 📷 — add photos or screenshots from the camera or gallery.
  final VoidCallback? onAddPhoto;

  /// "Read my screen" (floating assistant over other apps only).
  final VoidCallback? onReadScreen;

  /// Opens the full NOVA AI chat (in-app only).
  final VoidCallback? onExpand;

  @override
  State<NovaPanel> createState() => _NovaPanelState();
}

class _NovaPanelState extends State<NovaPanel> {
  final TextEditingController _text = TextEditingController();
  final FocusNode _focus = FocusNode();
  bool _typing = false;

  NovaController get c => widget.controller;

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  static String labelFor(NovaState s) => switch (s) {
        NovaState.idle => 'Tap the orb to speak',
        NovaState.activating => 'NOVA is waking up',
        NovaState.listening => 'Listening…',
        NovaState.processingSpeech => 'Understanding you…',
        NovaState.thinking => 'Thinking…',
        NovaState.executing => 'Working on it…',
        NovaState.speaking => 'Speaking',
        NovaState.clarifying => 'Needs a detail',
        NovaState.permissionRequired => 'Permission needed',
        NovaState.error => 'Something went wrong',
        NovaState.disabled => 'NOVA is off',
      };

  void _primaryTap() {
    HapticFeedback.lightImpact();
    switch (c.state) {
      case NovaState.listening:
        c.stopListening();
        break;
      case NovaState.speaking:
        c.stopSpeaking();
        break;
      case NovaState.processingSpeech:
      case NovaState.thinking:
      case NovaState.executing:
        c.cancel();
        break;
      default:
        setState(() => _typing = false);
        c.startListening();
    }
  }

  void _send() {
    final t = _text.text.trim();
    if (t.isEmpty) {
      if (c.pendingImages.isNotEmpty) c.askAboutImages();
      return;
    }
    _text.clear();
    c.submitText(t);
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final bottomInset = math.max(media.viewPadding.bottom, media.viewInsets.bottom);
    // With the keyboard open there is far less room: shrink the orb and reply.
    final keyboardOpen = media.viewInsets.bottom > 0;
    final maxReplyHeight = keyboardOpen
        ? math.min(140.0, media.size.height * 0.18)
        : math.min(320.0, media.size.height * 0.36);
    final orbSize = keyboardOpen ? 64.0 : 116.0;

    return AnimatedBuilder(
      animation: c,
      builder: (context, _) {
        final state = c.state;
        final accent = NovaOrb.colorFor(state);
        return Padding(
          padding: EdgeInsets.fromLTRB(10, 0, 10, 10 + bottomInset),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(30),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(30),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color.lerp(const Color(0xEB0B1528), accent, 0.10)!,
                      const Color(0xF5060C19),
                    ],
                  ),
                  border: Border.all(color: Colors.white.withOpacity(0.10)),
                  boxShadow: [
                    BoxShadow(color: accent.withOpacity(0.22), blurRadius: 40, spreadRadius: -6),
                  ],
                ),
                child: SafeArea(
                  top: false,
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 10, 18, 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 38,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.18),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(height: 8),
                        _header(state, accent),
                        const SizedBox(height: 6),
                        Semantics(
                          button: true,
                          label: 'NOVA. ${labelFor(state)}',
                          child: GestureDetector(
                            onTap: _primaryTap,
                            child: NovaOrb(state: state, level: c.level, size: orbSize),
                          ),
                        ),
                        if (c.transcript.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            '“${c.transcript}”',
                            textAlign: TextAlign.center,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              color: AppTheme.textSecondary,
                              fontSize: 13.5,
                              fontStyle: FontStyle.italic,
                              height: 1.4,
                            ),
                          ),
                        ],
                        if (c.reply.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          ConstrainedBox(
                            constraints: BoxConstraints(maxHeight: maxReplyHeight),
                            child: SingleChildScrollView(
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 250),
                                child: NovaMarkdownView(
                                  key: ValueKey(c.reply),
                                  text: c.reply,
                                  fontSize: 14.5,
                                  centerShort: true,
                                  onLink: c.openLink,
                                ),
                              ),
                            ),
                          ),
                        ],
                        ..._contextualActions(state, accent),
                        if (c.pendingImages.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          _pendingImages(accent),
                        ],
                        const SizedBox(height: 14),
                        if (_typing) _inputRow(accent) else _controls(state, accent),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _header(NovaState state, Color accent) {
    return Row(
      children: [
        ShaderMask(
          shaderCallback: (b) => AppTheme.primaryGradient.createShader(b),
          child: Text('NOVA',
              style: GoogleFonts.spaceGrotesk(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w800,
                letterSpacing: 2.5,
              )),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: accent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: accent.withOpacity(0.35)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    labelFor(state),
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      color: accent,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const Spacer(),
        if (widget.onExpand != null)
          _iconButton(Icons.open_in_full_rounded, 'Open NOVA AI chat', widget.onExpand!),
        _iconButton(Icons.close_rounded, 'Close NOVA', widget.onClose),
      ],
    );
  }

  List<Widget> _contextualActions(NovaState state, Color accent) {
    final widgets = <Widget>[];
    if (state == NovaState.permissionRequired) {
      widgets.add(const SizedBox(height: 12));
      widgets.add(Wrap(
        alignment: WrapAlignment.center,
        spacing: 10,
        runSpacing: 8,
        children: [
          _pill('Allow access', accent, filled: true, onTap: c.grantPermission),
          _pill('Not now', accent, onTap: c.declinePermission),
        ],
      ));
    } else if (c.choices.isNotEmpty) {
      widgets.add(const SizedBox(height: 12));
      widgets.add(Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final choice in c.choices)
            _pill(choice.label, accent, subtitle: choice.subtitle, onTap: () => c.choose(choice)),
        ],
      ));
    } else if (state == NovaState.error) {
      widgets.add(const SizedBox(height: 12));
      widgets.add(_pill('Try again', accent, filled: true, onTap: c.startListening));
    }
    if (c.offerPermissionSettings && state != NovaState.permissionRequired) {
      widgets.add(const SizedBox(height: 10));
      widgets.add(_pill('Open app settings', AppTheme.warning, onTap: c.openPermissionSettings));
    }
    return widgets;
  }

  Widget _controls(NovaState state, Color accent) {
    final listening = state == NovaState.listening;
    final speaking = state == NovaState.speaking;
    final busy = c.isBusy;
    final IconData mainIcon = listening
        ? Icons.stop_rounded
        : speaking
            ? Icons.volume_off_rounded
            : busy
                ? Icons.close_rounded
                : Icons.mic_rounded;
    final String mainLabel = listening
        ? 'Stop listening'
        : speaking
            ? 'Stop speaking'
            : busy
                ? 'Cancel'
                : 'Speak to NOVA';

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        if (widget.onAddPhoto != null)
          _iconButton(Icons.add_photo_alternate_outlined, 'Add a photo or screenshot', () {
            if (listening) c.cancel();
            widget.onAddPhoto!();
          }),
        _iconButton(Icons.keyboard_alt_outlined, 'Type to NOVA', () {
          setState(() => _typing = true);
          if (listening) c.cancel();
          WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
        }),
        Semantics(
          button: true,
          label: mainLabel,
          child: GestureDetector(
            onTap: _primaryTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: listening
                    ? const LinearGradient(colors: [Color(0xFFFF4D6A), Color(0xFFFF7A59)])
                    : AppTheme.primaryGradient,
                boxShadow: [BoxShadow(color: accent.withOpacity(0.45), blurRadius: 22)],
              ),
              child: Icon(mainIcon, color: Colors.white, size: 30),
            ),
          ),
        ),
        _iconButton(
          c.settings.speakReplies ? Icons.volume_up_rounded : Icons.volume_off_outlined,
          c.settings.speakReplies ? 'Mute NOVA voice' : 'Turn on NOVA voice',
          () => widget.onToggleVoice(!c.settings.speakReplies),
        ),
        if (widget.onReadScreen != null)
          _iconButton(Icons.screenshot_monitor_outlined, 'Read my screen', () {
            if (listening) c.cancel();
            widget.onReadScreen!();
          }),
      ],
    );
  }

  /// Photos / screenshot waiting for the question (tap × to remove).
  Widget _pendingImages(Color accent) {
    final images = c.pendingImages;
    final screen = c.pendingIsScreen;
    return Column(
      children: [
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          children: [
            for (var i = 0; i < images.length; i++)
              Stack(
                clipBehavior: Clip.none,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(
                      _bytes(images[i].bytes),
                      width: screen ? 46 : 58,
                      height: screen ? 82 : 58,
                      fit: BoxFit.cover,
                      cacheWidth: 160,
                      gaplessPlayback: true,
                    ),
                  ),
                  Positioned(
                    top: -6,
                    right: -6,
                    child: Semantics(
                      button: true,
                      label: screen ? 'Remove the screenshot' : 'Remove photo',
                      child: GestureDetector(
                        onTap: () => c.removeImage(i),
                        child: Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.75),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white24),
                          ),
                          child: const Icon(Icons.close_rounded, size: 14, color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          screen ? 'Ask about your screen — speak, type, or tap send.' : 'Ask about this — speak, type, or tap send.',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 12),
        ),
        if (!_typing) ...[
          const SizedBox(height: 8),
          _pill(screen ? 'What’s on my screen?' : 'What’s in this?', accent, filled: true, onTap: () => c.askAboutImages()),
        ],
      ],
    );
  }

  static Uint8List _bytes(List<int> b) => b is Uint8List ? b : Uint8List.fromList(b);

  Widget _inputRow(Color accent) {
    return Row(
      children: [
        _iconButton(Icons.mic_none_rounded, 'Speak instead', () {
          setState(() => _typing = false);
          _focus.unfocus();
          c.startListening();
        }),
        if (widget.onAddPhoto != null) ...[
          const SizedBox(width: 6),
          _iconButton(Icons.add_photo_alternate_outlined, 'Add a photo or screenshot', widget.onAddPhoto!),
        ],
        const SizedBox(width: 6),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: accent.withOpacity(0.35)),
            ),
            child: TextField(
              controller: _text,
              focusNode: _focus,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              maxLength: 1000,
              style: GoogleFonts.inter(color: Colors.white, fontSize: 14.5),
              decoration: InputDecoration(
                border: InputBorder.none,
                counterText: '',
                hintText: c.pendingImages.isEmpty
                    ? 'Ask NOVA or give a command…'
                    : (c.pendingIsScreen ? 'Ask about your screen…' : 'Ask about this photo…'),
                hintStyle: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 14),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        _iconButton(Icons.send_rounded, 'Send', _send),
      ],
    );
  }

  Widget _iconButton(IconData icon, String tooltip, VoidCallback onTap) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      icon: Icon(icon, color: AppTheme.textSecondary, size: 22),
      style: IconButton.styleFrom(
        minimumSize: const Size(44, 44),
        backgroundColor: Colors.white.withOpacity(0.06),
      ),
    );
  }

  Widget _pill(String label, Color accent,
      {String? subtitle, bool filled = false, required VoidCallback onTap}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Container(
          constraints: const BoxConstraints(minHeight: 40),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            gradient: filled ? AppTheme.primaryGradient : null,
            color: filled ? null : accent.withOpacity(0.10),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: accent.withOpacity(filled ? 0.0 : 0.4)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  )),
              if (subtitle != null && subtitle.isNotEmpty)
                Text(subtitle,
                    style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }
}
