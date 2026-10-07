// lib/features/ai/screens/ai_assistant_screen.dart
//
// NOVA X — BRAINS JET AI Screen
// v2.1.0 — AI content flag/report added for Google Play policy compliance.
// Verified clean: all string literals, imports, and null-safety checked.

import 'dart:io';
import 'dart:math';
import 'package:audioplayers/audioplayers.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nova_x/core/services/rewards_service.dart';
import 'package:nova_x/core/theme/app_theme.dart';
import 'package:nova_x/features/ai/widgets/ai_flag_sheet.dart';
import 'package:path_provider/path_provider.dart';
import 'package:speech_to_text/speech_to_text.dart';

class AiAssistantScreen extends StatefulWidget {
  const AiAssistantScreen({super.key});

  @override
  State<AiAssistantScreen> createState() => _AiAssistantScreenState();
}

class _AiAssistantScreenState extends State<AiAssistantScreen>
    with SingleTickerProviderStateMixin {
  final List<Map<String, String>> _msgs   = [];
  final TextEditingController     _ctrl   = TextEditingController();
  final ScrollController          _scroll = ScrollController();

  bool    _loading     = false;
  bool    _isSpeaking  = false;
  bool    _isListening = false;
  String? _speakingId;

  final Dio         _dio    = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
  ));
  final AudioPlayer  _player = AudioPlayer();
  final SpeechToText _speech = SpeechToText();
  bool _speechAvail = false;

  // ── API endpoints ──────────────────────────────────────────────────────────
  static const String _textApi  =
      'https://brains-jet-ai.brainsjetai.workers.dev/?model=openai/gpt-oss-20b&q=';
  static const String _ttsApi   =
      'https://brains-tts.brainsjetai.workers.dev/';
  static const String _imageApi =
      'https://ab-text-toimgfast.abrahamdw882.workers.dev/?text=';
  static const String _videoApi =
      'https://eliteprotech-apis.zone.id/aivideo?q=';
  static const String _orUrl    =
      'https://openrouter.ai/api/v1/chat/completions';
  static const String _orKey    =
      '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';

  static const List<String> _suggestions = [
    'Summarise a news article',
    'Help me write an email',
    'Explain something simply',
    '/image futuristic city at night',
    '/video waves on a beach',
  ];

  // ── Welcome message ────────────────────────────────────────────────────────
  static const String _welcome =
      '\u{1F44B} Hi! I\'m BRAINS JET AI.\n\n'
      '\u2022 Ask me anything\n'
      '\u2022 Type /image [description] to generate an image\n'
      '\u2022 Type /video [description] to generate a video\n'
      '\u2022 Tap \u{1F50A} on any reply to hear it read aloud\n'
      '\u2022 Tap \u{1F6A9} to report any content that seems inappropriate';

  @override
  void initState() {
    super.initState();
    _initSpeech();
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() { _isSpeaking = false; _speakingId = null; });
    });
    _msgs.add({'id': 'welcome', 'role': 'assistant', 'content': _welcome});
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    _player.dispose();
    _dio.close(force: false);
    _speech.stop();
    super.dispose();
  }

  // ── Speech ─────────────────────────────────────────────────────────────────
  Future<void> _initSpeech() async {
    _speechAvail = await _speech.initialize(
      onError: (_) { if (mounted) setState(() => _isListening = false); },
    );
  }

  Future<void> _toggleListen() async {
    if (!_speechAvail) { _snack('Microphone unavailable'); return; }
    HapticFeedback.mediumImpact();
    if (_isListening) {
      await _speech.stop();
      if (mounted) setState(() => _isListening = false);
    } else {
      setState(() => _isListening = true);
      await _speech.listen(
        onResult: (r) {
          if (r.finalResult && r.recognizedWords.isNotEmpty) {
            if (mounted) setState(() => _isListening = false);
            _ctrl.text = r.recognizedWords;
            _send(r.recognizedWords);
          }
        },
        localeId:       'en_US',
        cancelOnError:  true,
        partialResults: false,
      );
    }
  }

  // ── TTS ────────────────────────────────────────────────────────────────────
  Future<void> _speakMessage(String id, String text) async {
    HapticFeedback.lightImpact();
    if (_isSpeaking && _speakingId == id) {
      await _player.stop();
      if (mounted) setState(() { _isSpeaking = false; _speakingId = null; });
      return;
    }
    await _player.stop();
    if (mounted) setState(() { _isSpeaking = true; _speakingId = id; });
    try {
      final clean = text
          .replaceAll(RegExp(r'\*+'), '')
          .replaceAll('#', '')
          .replaceAll(RegExp(r'\n+'), ' ')
          .trim();
      final snippet = clean.substring(0, min(clean.length, 400));
      final res = await _dio.get(
        _ttsApi,
        queryParameters: {'q': snippet, 'voicename': 'libby'},
      );
      final audioUrl = res.data?['url'] as String?;
      if (audioUrl != null && audioUrl.isNotEmpty) {
        await _player.play(UrlSource(audioUrl));
      } else {
        throw Exception('No audio URL returned');
      }
    } catch (_) {
      if (mounted) setState(() { _isSpeaking = false; _speakingId = null; });
    }
  }

  // ── Report / Flag ──────────────────────────────────────────────────────────
  void _reportContent({required String contentType, String? contentRef}) {
    HapticFeedback.mediumImpact();
    showAiFlagSheet(context, contentType: contentType, contentRef: contentRef);
  }

  // ── Identity guard ─────────────────────────────────────────────────────────
  String _sanitize(String reply, String query) {
    final q = query.toLowerCase();
    if (RegExp(r'\b(who|what).*(creat|made|develop|owner|built)\b')
        .hasMatch(q)) {
      return 'I am BRAINS JET AI, created and developed by Kobby '
          '(Mr. Romantic), CEO of Tech Lyfe Team. How can I help you?';
    }
    return reply.isEmpty ? 'No response received. Please try again.' : reply;
  }

  // ── Send message ────────────────────────────────────────────────────────────
  Future<void> _send(String text) async {
    final t = text.trim();
    if (t.isEmpty) return;

    // Fire-and-forget earn call — result not needed
    RewardsService.earn(RewardTaskKey.useAi);

    _ctrl.clear();
    HapticFeedback.lightImpact();

    final msgId = DateTime.now().millisecondsSinceEpoch.toString();
    if (mounted) {
      setState(() {
        _msgs.add({'id': msgId, 'role': 'user', 'content': t});
        _loading = true;
      });
    }
    _scrollEnd();

    // Image generation
    if (t.toLowerCase().startsWith('/image ')) {
      final prompt =
          t.replaceFirst(RegExp(r'^/image\s+', caseSensitive: false), '');
      final url = '$_imageApi${Uri.encodeComponent(prompt)}';
      if (mounted) setState(() {
        _msgs.add({
          'id':      DateTime.now().millisecondsSinceEpoch.toString(),
          'role':    'assistant',
          'content': '[IMAGE]$url',
        });
        _loading = false;
      });
      _scrollEnd();
      return;
    }

    // Video generation
    if (t.toLowerCase().startsWith('/video ')) {
      final prompt =
          t.replaceFirst(RegExp(r'^/video\s+', caseSensitive: false), '');
      final loadId = DateTime.now().millisecondsSinceEpoch.toString();
      if (mounted) setState(() {
        _msgs.add({
          'id':      loadId,
          'role':    'assistant',
          'content': '[LOADING_VIDEO]Generating video for: "$prompt"\u2026',
        });
        _loading = false;
      });
      _scrollEnd();
      _generateVideo(prompt, loadId);
      return;
    }

    // Text AI
    try {
      final res =
          await _dio.get('$_textApi${Uri.encodeComponent(t)}');
      final reply = _sanitize((res.data ?? '').toString().trim(), t);
      if (mounted) setState(() {
        _msgs.add({
          'id':      DateTime.now().millisecondsSinceEpoch.toString(),
          'role':    'assistant',
          'content': reply,
        });
        _loading = false;
      });
    } catch (_) {
      await _fallback(t);
    }
    _scrollEnd();
  }

  Future<void> _generateVideo(String prompt, String loadId) async {
    try {
      final res =
          await _dio.get('$_videoApi${Uri.encodeComponent(prompt)}');
      final url = res.data?['result']?['url'] as String? ??
                  res.data?['url']            as String?;
      if (url == null || url.isEmpty) throw Exception('No video URL');
      _updateMsg(loadId, '[VIDEO]$url');
    } catch (_) {
      _updateMsg(
        loadId,
        '\u26A0\uFE0F Video generation failed. Please try again later.',
      );
    }
  }

  void _updateMsg(String id, String newContent) {
    final idx = _msgs.indexWhere((m) => m['id'] == id);
    if (idx >= 0 && mounted) {
      setState(() => _msgs[idx] = {..._msgs[idx], 'content': newContent});
    }
  }

  Future<void> _fallback(String text) async {
    try {
      final res = await _dio.post(
        _orUrl,
        options: Options(headers: {
          'Authorization': 'Bearer $_orKey',
          'Content-Type':  'application/json',
        }),
        data: {
          'model': 'openai/gpt-4o',
          'messages': [
            {
              'role':    'system',
              'content': 'You are BRAINS JET AI by Kobby / Tech Lyfe Team. '
                  'Never mention OpenAI, GPT, Claude, or any third-party AI.',
            },
            {'role': 'user', 'content': text},
          ],
        },
      );
      final choices = res.data?['choices'];
      String reply = 'AI is temporarily unavailable. Please try again.';
      if (choices is List && choices.isNotEmpty) {
        reply = _sanitize(
          (choices[0]?['message']?['content'] ?? '').toString().trim(),
          text,
        );
      }
      if (mounted) setState(() {
        _msgs.add({
          'id':      DateTime.now().millisecondsSinceEpoch.toString(),
          'role':    'assistant',
          'content': reply,
        });
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() {
        _msgs.add({
          'id':      DateTime.now().millisecondsSinceEpoch.toString(),
          'role':    'assistant',
          'content': 'Network error. Check your connection and retry.',
        });
        _loading = false;
      });
    }
  }

  void _scrollEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve:    Curves.easeOut,
        );
      }
    });
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content:          Text(msg,
          style: GoogleFonts.inter(color: Colors.white)),
      backgroundColor:  AppTheme.bgElevated,
      behavior:         SnackBarBehavior.floating,
      shape:            RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12)),
    ));
  }

  // ═══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      appBar: _buildAppBar(),
      body: Column(children: [
        if (_msgs.length <= 1) _buildSuggestions(),
        Expanded(
          child: ListView.builder(
            controller: _scroll,
            padding:    const EdgeInsets.fromLTRB(14, 12, 14, 8),
            itemCount:  _msgs.length + (_loading ? 1 : 0),
            itemBuilder: (_, i) {
              if (_loading && i == _msgs.length) return _buildTyping();
              return _buildBubble(_msgs[i]);
            },
          ),
        ),
        _buildInput(),
      ]),
    );
  }

  // ── AppBar ─────────────────────────────────────────────────────────────────
  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: AppTheme.bgDark,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded,
            color: AppTheme.textSecondary, size: 18),
        onPressed: () => Navigator.pop(context),
      ),
      title: Row(children: [
        Container(
          width: 34, height: 34,
          decoration: BoxDecoration(
            gradient:     AppTheme.primaryGradient,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.psychology, color: Colors.white, size: 19),
        ),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('BRAINS JET AI',
              style: GoogleFonts.spaceGrotesk(
                  color: AppTheme.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.bold)),
          Row(children: [
            Container(
              width: 6, height: 6,
              decoration: const BoxDecoration(
                  color: AppTheme.success, shape: BoxShape.circle),
            ),
            const SizedBox(width: 4),
            Text('Online',
                style: GoogleFonts.inter(
                    color: AppTheme.success, fontSize: 10)),
          ]),
        ]),
      ]),
      actions: [
        // Global report shortcut
        Tooltip(
          message: 'Report AI Content',
          child: IconButton(
            icon: const Icon(Icons.flag_outlined,
                color: AppTheme.textHint, size: 20),
            onPressed: () =>
                _reportContent(contentType: 'text'),
          ),
        ),
        // Stop TTS
        IconButton(
          icon: Icon(
            _isSpeaking
                ? Icons.volume_up_rounded
                : Icons.volume_off_rounded,
            color: _isSpeaking ? AppTheme.accentCyan : AppTheme.textHint,
            size: 20,
          ),
          tooltip: 'Stop speaking',
          onPressed: () async {
            await _player.stop();
            if (mounted) setState(() { _isSpeaking = false; _speakingId = null; });
          },
        ),
        // Clear chat
        IconButton(
          icon: const Icon(Icons.delete_outline_rounded,
              color: AppTheme.textHint, size: 20),
          onPressed: () => setState(() {
            _msgs.clear();
            _msgs.add({
              'id':      'cleared',
              'role':    'assistant',
              'content': '\u2713 Chat cleared. How can I help?',
            });
          }),
        ),
      ],
    );
  }

  // ── Suggestion chips ───────────────────────────────────────────────────────
  Widget _buildSuggestions() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
      child: Row(
        children: _suggestions.map((s) => GestureDetector(
          onTap: () => _send(s),
          child: Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color:        AppTheme.bgCard,
              borderRadius: BorderRadius.circular(20),
              border:       Border.all(color: AppTheme.divider),
            ),
            child: Text(s,
                style: GoogleFonts.inter(
                    color: AppTheme.textSecondary, fontSize: 12)),
          ),
        )).toList(),
      ),
    );
  }

  // ── Chat bubble ────────────────────────────────────────────────────────────
  Widget _buildBubble(Map<String, String> msg) {
    final isUser  = msg['role'] == 'user';
    final content = msg['content'] ?? '';
    final id      = msg['id']     ?? '';

    if (content.startsWith('[IMAGE]')) {
      return _buildImageWidget(content.replaceFirst('[IMAGE]', ''));
    }
    if (content.startsWith('[VIDEO]')) {
      return _buildVideoWidget(content.replaceFirst('[VIDEO]', ''));
    }
    if (content.startsWith('[LOADING_VIDEO]')) {
      return _buildLoadingVideo(
          content.replaceFirst('[LOADING_VIDEO]', ''));
    }

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment:
            isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          // Bubble
          Container(
            constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.78),
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              gradient: isUser ? AppTheme.primaryGradient : null,
              color:    isUser ? null : AppTheme.bgCard,
              borderRadius: BorderRadius.only(
                topLeft:     const Radius.circular(18),
                topRight:    const Radius.circular(18),
                bottomLeft:  Radius.circular(isUser ? 18 : 4),
                bottomRight: Radius.circular(isUser ? 4  : 18),
              ),
              boxShadow: AppTheme.cardShadow,
            ),
            child: SelectableText(content,
                style: GoogleFonts.inter(
                    color: Colors.white, fontSize: 14, height: 1.5)),
          ),

          // Action row — assistant
          if (!isUser)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 4),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                _ActionBtn(
                  icon:  _speakingId == id
                      ? Icons.stop_circle_outlined
                      : Icons.volume_up_outlined,
                  label: _speakingId == id ? 'Stop' : 'Read aloud',
                  color: _speakingId == id
                      ? Colors.redAccent
                      : AppTheme.textHint,
                  onTap: () => _speakMessage(id, content),
                ),
                const SizedBox(width: 14),
                _ActionBtn(
                  icon:  Icons.flag_outlined,
                  label: 'Report',
                  color: AppTheme.textHint,
                  onTap: () => _reportContent(
                    contentType: 'text',
                    contentRef: content.length > 500
                        ? content.substring(0, 500)
                        : content,
                  ),
                ),
              ]),
            ),

          // Action row — user message
          if (isUser)
            Padding(
              padding: const EdgeInsets.only(right: 4, bottom: 4),
              child: _ActionBtn(
                icon:  Icons.flag_outlined,
                label: 'Report',
                color: AppTheme.textHint,
                onTap: () => _reportContent(
                  contentType: 'text',
                  contentRef: content.length > 500
                      ? content.substring(0, 500)
                      : content,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Image widget ───────────────────────────────────────────────────────────
  Widget _buildImageWidget(String url) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => _showImagePreview(url),
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 4),
              constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.78),
              child: Stack(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.network(
                    url,
                    fit: BoxFit.contain,
                    loadingBuilder: (_, child, prog) => prog == null
                        ? child
                        : Container(
                            height: 120,
                            alignment: Alignment.center,
                            child: const CircularProgressIndicator(
                                color: AppTheme.accentCyan, strokeWidth: 2)),
                    errorBuilder: (_, __, ___) => Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                          color:        AppTheme.bgCard,
                          borderRadius: BorderRadius.circular(16)),
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.broken_image_outlined,
                            color: AppTheme.textHint, size: 18),
                        SizedBox(width: 8),
                        Text('Image unavailable',
                            style: TextStyle(
                                color: AppTheme.textHint, fontSize: 12)),
                      ]),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 8, right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color:        Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.fullscreen_rounded,
                          color: Colors.white, size: 13),
                      const SizedBox(width: 4),
                      Text('Preview',
                          style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w600)),
                    ]),
                  ),
                ),
              ]),
            ),
          ),
          // Report image
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 4),
            child: _ActionBtn(
              icon:  Icons.flag_outlined,
              label: 'Report image',
              color: AppTheme.textHint,
              onTap: () =>
                  _reportContent(contentType: 'image', contentRef: url),
            ),
          ),
        ],
      ),
    );
  }

  // ── Video widget ───────────────────────────────────────────────────────────
  Widget _buildVideoWidget(String url) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => _showVideoSheet(url),
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 4),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color:        AppTheme.bgCard,
                borderRadius: BorderRadius.circular(16),
                border:       Border.all(color: AppTheme.divider),
              ),
              child: Row(children: [
                const Icon(Icons.play_circle_fill_rounded,
                    color: AppTheme.accentCyan, size: 36),
                const SizedBox(width: 10),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Video Generated!',
                        style: GoogleFonts.spaceGrotesk(
                            color: AppTheme.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w700)),
                    Text('Tap to preview & copy link',
                        style: GoogleFonts.inter(
                            color: AppTheme.accentCyan, fontSize: 11)),
                  ],
                )),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    gradient:     AppTheme.primaryGradient,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.download_rounded,
                        color: Colors.white, size: 13),
                    const SizedBox(width: 4),
                    Text('Save',
                        style: GoogleFonts.inter(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700)),
                  ]),
                ),
              ]),
            ),
          ),
          // Report video
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 4),
            child: _ActionBtn(
              icon:  Icons.flag_outlined,
              label: 'Report video',
              color: AppTheme.textHint,
              onTap: () =>
                  _reportContent(contentType: 'video', contentRef: url),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingVideo(String msg) => Align(
    alignment: Alignment.centerLeft,
    child: Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color:        AppTheme.bgCard,
          borderRadius: BorderRadius.circular(16)),
      child: Row(children: [
        const SizedBox(
          width: 20, height: 20,
          child: CircularProgressIndicator(
              color: AppTheme.accentCyan, strokeWidth: 2)),
        const SizedBox(width: 12),
        Expanded(child: Text(msg,
            style: GoogleFonts.inter(
                color: AppTheme.textSecondary, fontSize: 13))),
      ]),
    ),
  );

  Widget _buildTyping() => Align(
    alignment: Alignment.centerLeft,
    child: Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: const BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.only(
          topLeft:     Radius.circular(18),
          topRight:    Radius.circular(18),
          bottomRight: Radius.circular(18),
          bottomLeft:  Radius.circular(4),
        ),
      ),
      child: const _TypingDots(),
    ),
  );

  // ── Input bar ──────────────────────────────────────────────────────────────
  Widget _buildInput() {
    return Container(
      padding: EdgeInsets.fromLTRB(
          14, 8, 14, MediaQuery.of(context).padding.bottom + 12),
      decoration: BoxDecoration(
        color:  AppTheme.bgDark,
        border: Border(top: BorderSide(color: AppTheme.divider)),
      ),
      child: Row(children: [
        // Mic
        GestureDetector(
          onTap: _toggleListen,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 42, height: 42,
            decoration: BoxDecoration(
              color:        _isListening
                  ? Colors.red.withOpacity(0.15)
                  : AppTheme.bgCard,
              borderRadius: BorderRadius.circular(12),
              border:       Border.all(
                  color: _isListening ? Colors.redAccent : AppTheme.divider),
            ),
            child: Icon(
              _isListening ? Icons.mic : Icons.mic_none_rounded,
              color: _isListening ? Colors.redAccent : AppTheme.textHint,
              size: 20,
            ),
          ),
        ),
        const SizedBox(width: 8),

        // Text field
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color:        AppTheme.bgCard,
              borderRadius: BorderRadius.circular(28),
              border:       Border.all(color: AppTheme.divider),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: TextField(
              controller:      _ctrl,
              style:           GoogleFonts.inter(
                  color: Colors.white, fontSize: 14),
              maxLines:        null,
              textInputAction: TextInputAction.send,
              onSubmitted:     _send,
              decoration:      InputDecoration(
                border:         InputBorder.none,
                hintText:       _isListening
                    ? 'Listening\u2026'
                    : 'Ask AI, /image or /video\u2026',
                hintStyle: GoogleFonts.inter(
                    color: _isListening
                        ? Colors.redAccent
                        : AppTheme.textHint,
                    fontSize: 14),
                isDense:        true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),

        // Send button
        GestureDetector(
          onTap: () => _send(_ctrl.text),
          child: Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              gradient:  AppTheme.primaryGradient,
              shape:     BoxShape.circle,
              boxShadow: AppTheme.glowShadow,
            ),
            child: const Icon(Icons.send_rounded,
                color: Colors.white, size: 18),
          ),
        ),
      ]),
    );
  }

  // ── Video bottom sheet ─────────────────────────────────────────────────────
  void _showVideoSheet(String url) {
    showModalBottomSheet<void>(
      context:           context,
      backgroundColor:   Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color:        AppTheme.bgCard,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(
            24, 12, 24, MediaQuery.of(context).padding.bottom + 28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 40, height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
                color: AppTheme.divider,
                borderRadius: BorderRadius.circular(2)),
          ),
          const Icon(Icons.videocam_rounded,
              color: AppTheme.accentCyan, size: 40),
          const SizedBox(height: 12),
          Text('Video Ready',
              style: GoogleFonts.spaceGrotesk(
                  color: AppTheme.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text('Your AI video has been generated',
              style: GoogleFonts.inter(
                  color: AppTheme.textHint, fontSize: 13)),
          const SizedBox(height: 20),
          // Copy link
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: url));
              Navigator.pop(context);
              _snack('Video link copied to clipboard \u2713');
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color:        AppTheme.bgElevated,
                borderRadius: BorderRadius.circular(14),
                border:       Border.all(color: AppTheme.divider),
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.copy_rounded,
                    color: AppTheme.accentCyan, size: 18),
                const SizedBox(width: 8),
                Text('Copy Video Link',
                    style: GoogleFonts.inter(
                        color: AppTheme.accentCyan,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
          const SizedBox(height: 10),
          // Report video
          GestureDetector(
            onTap: () {
              Navigator.pop(context);
              _reportContent(contentType: 'video', contentRef: url);
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color:        const Color(0xFF1A0808),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: AppTheme.danger.withOpacity(0.3), width: 1.2),
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.flag_outlined,
                    color: AppTheme.danger, size: 18),
                const SizedBox(width: 8),
                Text('Report This Video',
                    style: GoogleFonts.inter(
                        color: AppTheme.danger,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  // ── Full-screen image preview ──────────────────────────────────────────────
  void _showImagePreview(String url) {
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _ImagePreviewScreen(imageUrl: url),
      ),
    );
  }
}

// ── Reusable action button ─────────────────────────────────────────────────
class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String   label;
  final Color    color;
  final VoidCallback onTap;

  const _ActionBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    behavior: HitTestBehavior.opaque,
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: color, size: 14),
      const SizedBox(width: 4),
      Text(label,
          style: GoogleFonts.inter(color: color, fontSize: 10)),
    ]),
  );
}

// ── Full-screen image preview screen ──────────────────────────────────────
class _ImagePreviewScreen extends StatefulWidget {
  final String imageUrl;
  const _ImagePreviewScreen({required this.imageUrl});

  @override
  State<_ImagePreviewScreen> createState() => _ImagePreviewScreenState();
}

class _ImagePreviewScreenState extends State<_ImagePreviewScreen> {
  bool _downloading = false;
  bool _downloaded  = false;

  Future<void> _download() async {
    if (_downloading || _downloaded) return;
    setState(() => _downloading = true);
    try {
      final dio  = Dio();
      final resp = await dio.get<List<int>>(
        widget.imageUrl,
        options: Options(responseType: ResponseType.bytes),
      );

      final String savePath;
      if (Platform.isAndroid) {
        final ext     = await getExternalStorageDirectory();
        final base    = ext!.path.split('/Android/')[0];
        final dir     = Directory('$base/Pictures/NOVA X');
        if (!await dir.exists()) await dir.create(recursive: true);
        savePath = '${dir.path}/brains_ai_'
            '${DateTime.now().millisecondsSinceEpoch}.jpg';
      } else {
        final dir = await getApplicationDocumentsDirectory();
        savePath  = '${dir.path}/brains_ai_'
            '${DateTime.now().millisecondsSinceEpoch}.jpg';
      }

      await File(savePath).writeAsBytes(resp.data!);
      if (!mounted) return;
      setState(() { _downloading = false; _downloaded = true; });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(children: [
          const Icon(Icons.check_circle_outline_rounded,
              color: Colors.white, size: 16),
          const SizedBox(width: 8),
          const Expanded(child: Text('Saved to Pictures/NOVA X \u2713',
              style: TextStyle(color: Colors.white, fontSize: 12))),
        ]),
        backgroundColor: AppTheme.success,
        behavior:        SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 4),
      ));
    } catch (_) {
      if (!mounted) return;
      setState(() => _downloading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Download failed. Check your connection.',
            style: TextStyle(color: Colors.white)),
        backgroundColor: AppTheme.danger,
        behavior:        SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final top    = MediaQuery.of(context).padding.top;
    final bottom = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        // Zoomable image
        Center(
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 5.0,
            child: Image.network(
              widget.imageUrl,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Icon(
                  Icons.broken_image_outlined,
                  color: Colors.white38, size: 60),
            ),
          ),
        ),

        // Top gradient bar
        Positioned(
          top: 0, left: 0, right: 0,
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end:   Alignment.bottomCenter,
                colors: [Colors.black87, Colors.transparent],
              ),
            ),
            padding: EdgeInsets.fromLTRB(12, top + 8, 12, 24),
            child: Row(children: [
              // Close
              _CircleBtn(
                icon: Icons.close_rounded,
                onTap: () => Navigator.pop(context),
              ),
              const Spacer(),
              Text('BRAINS JET AI',
                  style: GoogleFonts.spaceGrotesk(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
              const Spacer(),
              // Report
              _CircleBtn(
                icon: Icons.flag_outlined,
                onTap: () => showAiFlagSheet(
                  context,
                  contentType: 'image',
                  contentRef:  widget.imageUrl,
                ),
              ),
            ]),
          ),
        ),

        // Bottom download bar
        Positioned(
          bottom: 0, left: 0, right: 0,
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end:   Alignment.topCenter,
                colors: [Colors.black87, Colors.transparent],
              ),
            ),
            padding: EdgeInsets.fromLTRB(24, 30, 24, bottom + 24),
            child: GestureDetector(
              onTap: _download,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                    horizontal: 28, vertical: 14),
                decoration: BoxDecoration(
                  gradient:     _downloaded ? null : AppTheme.primaryGradient,
                  color:        _downloaded ? AppTheme.success : null,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow:    AppTheme.glowShadow,
                ),
                child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                  _downloading
                      ? const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : Icon(
                          _downloaded
                              ? Icons.check_rounded
                              : Icons.download_rounded,
                          color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  Text(
                    _downloaded ? 'Saved to device!' : 'Download Image',
                    style: GoogleFonts.spaceGrotesk(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

class _CircleBtn extends StatelessWidget {
  final IconData     icon;
  final VoidCallback onTap;
  const _CircleBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 40, height: 40,
      decoration: BoxDecoration(
          color: Colors.black45, shape: BoxShape.circle),
      child: Icon(icon, color: Colors.white70, size: 20),
    ),
  );
}

// ── Typing dots ────────────────────────────────────────────────────────────
class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _ctrl,
    builder: (_, __) => Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        final t = (_ctrl.value - i * 0.15).clamp(0.0, 1.0);
        final scale = 0.6 + 0.4 * (t < 0.5 ? t * 2 : (1 - t) * 2);
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width:  8 * scale,
          height: 8 * scale,
          decoration: const BoxDecoration(
              color: AppTheme.accentCyan, shape: BoxShape.circle),
        );
      }),
    ),
  );
}
