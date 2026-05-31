import 'dart:math';
import 'package:nova_x/core/services/rewards_service.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'dart:io';
import 'package:nova_x/core/theme/app_theme.dart';
import 'package:path_provider/path_provider.dart';

class AiAssistantScreen extends StatefulWidget {
  const AiAssistantScreen({super.key});
  @override
  State<AiAssistantScreen> createState() => _AiAssistantScreenState();
}

class _AiAssistantScreenState extends State<AiAssistantScreen>
    with SingleTickerProviderStateMixin {
  final List<Map<String, String>> _msgs  = [];
  final TextEditingController _ctrl      = TextEditingController();
  final ScrollController      _scroll    = ScrollController();
  bool _loading     = false;
  bool _isSpeaking  = false;
  bool _isListening = false;
  String? _speakingMsgId; // which message is being read aloud

  final Dio          _dio    = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30)));
  final AudioPlayer  _player = AudioPlayer();
  final SpeechToText _speech = SpeechToText();
  bool _speechAvail = false;

  // ── API endpoints ──────────────────────────────────────────────────────────
  static const String _textApi  = 'https://brains-jet-ai.brainsjetai.workers.dev/?model=llama-3.1-8b-instant&q=';
  static const String _ttsApi   = 'https://brains-tts.brainsjetai.workers.dev/';
  static const String _imageApi = 'https://ab-text-toimgfast.abrahamdw882.workers.dev/?text=';
  static const String _videoApi = 'https://eliteprotech-apis.zone.id/aivideo?q=';
  static const String _orUrl    = 'https://openrouter.ai/api/v1/chat/completions';
  static const String _orKey    = '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';

  final List<String> _suggestions = [
    'Summarise a news article',
    'Help me write an email',
    'Explain something simply',
    '/image futuristic city at night',
    '/video waves on a beach',
  ];

  @override
  void initState() {
    super.initState();
    _initSpeech();
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() { _isSpeaking = false; _speakingMsgId = null; });
    });
    _msgs.add({
      'id':      'welcome',
      'role':    'assistant',
      'content': '👋 Hi! I\'m BRAINS JET AI.\n\n'
          '• Ask me anything\n'
          '• Type /image [description] to generate an image\n'
          '• Type /video [description] to generate a video\n'
          '• Tap 🔊 on any response to hear it read aloud',
    });
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

  // ── Voice input ────────────────────────────────────────────────────────────
  Future<void> _initSpeech() async {
    _speechAvail = await _speech.initialize(
        onError: (_) => setState(() => _isListening = false));
  }

  Future<void> _toggleListen() async {
    if (!_speechAvail) { _snack('Mic unavailable'); return; }
    HapticFeedback.mediumImpact();
    if (_isListening) {
      _speech.stop();
      setState(() => _isListening = false);
    } else {
      setState(() => _isListening = true);
      await _speech.listen(
        onResult: (r) {
          if (r.finalResult && r.recognizedWords.isNotEmpty) {
            _ctrl.text = r.recognizedWords;
            setState(() => _isListening = false);
            _send(r.recognizedWords);
          }
        },
        localeId: 'en_US', cancelOnError: true, partialResults: false,
      );
    }
  }

  // ── TTS voice output ────────────────────────────────────────────────────────
  Future<void> _speakMessage(String id, String text) async {
    HapticFeedback.lightImpact();
    if (_isSpeaking && _speakingMsgId == id) {
      await _player.stop();
      setState(() { _isSpeaking = false; _speakingMsgId = null; });
      return;
    }
    await _player.stop();
    setState(() { _isSpeaking = true; _speakingMsgId = id; });
    try {
      // Clean text for TTS — remove markdown symbols
      final clean = text
          .replaceAll(RegExp(r'\*+'), '')
          .replaceAll('#', '')
          .replaceAll(RegExp(r'\n+'), ' ')
          .trim();
      final snippet = clean.substring(0, min(clean.length, 400));

      final res = await _dio.get(_ttsApi,
          queryParameters: {'q': snippet, 'voicename': 'libby'});
      final audioUrl = res.data?['url'] as String?;
      if (audioUrl != null && audioUrl.isNotEmpty) {
        await _player.play(UrlSource(audioUrl));
      } else {
        throw Exception('No audio URL');
      }
    } catch (_) {
      if (mounted) setState(() { _isSpeaking = false; _speakingMsgId = null; });
    }
  }

  // ── Identity guard ─────────────────────────────────────────────────────────
  String _sanitize(String r, String q) {
    final ql = q.toLowerCase();
    if (RegExp(r'\b(who|what).*(creat|made|develop|owner|built)\b').hasMatch(ql)) {
      return 'I am BRAINS JET AI, created and developed by Kobby (Mr. Romantic), '
          'CEO of Tech Lyfe Team. How can I help you?';
    }
    return r.isEmpty ? 'No response. Please try again.' : r;
  }

  // ── Send message ────────────────────────────────────────────────────────────
  Future<void> _send(String text) async {
    final t = text.trim();
    if (t.isEmpty) return;
    RewardsService.earn(RewardTaskKey.useAi); // auto-claim: real AI use (server caps 1/day)
    _ctrl.clear();
    HapticFeedback.lightImpact();
    if (!mounted) return;
    final msgId = DateTime.now().millisecondsSinceEpoch.toString();
    setState(() {
      _msgs.add({'id': msgId, 'role': 'user', 'content': t});
      _loading = true;
    });
    _scrollEnd();

    // Image generation — FIX #10: use direct API (no CORS proxy needed in Flutter)
    if (t.toLowerCase().startsWith('/image ')) {
      final prompt = t.replaceFirst(RegExp(r'^/image\s+', caseSensitive: false), '');
      final url    = '$_imageApi${Uri.encodeComponent(prompt)}';
      if (mounted) setState(() {
        _msgs.add({'id': DateTime.now().toString(), 'role': 'assistant',
            'content': '[IMAGE]$url'});
        _loading = false;
      });
      _scrollEnd();
      return;
    }

    // Video generation — NEW from media.js
    if (t.toLowerCase().startsWith('/video ')) {
      final prompt = t.replaceFirst(RegExp(r'^/video\s+', caseSensitive: false), '');
      setState(() {
        _msgs.add({'id': DateTime.now().toString(), 'role': 'assistant',
            'content': '[LOADING_VIDEO]Generating video for: "$prompt"…'});
        _loading = false;
      });
      _scrollEnd();
      _generateVideo(prompt);
      return;
    }

    // Text response
    try {
      final res = await _dio.get('$_textApi${Uri.encodeComponent(t)}');
      final reply = _sanitize((res.data ?? '').toString().trim(), t);
      if (mounted) setState(() {
        _msgs.add({'id': DateTime.now().toString(), 'role': 'assistant',
            'content': reply});
        _loading = false;
      });
    } catch (_) {
      await _fallback(t);
    }
    _scrollEnd();
  }

  Future<void> _generateVideo(String prompt) async {
    try {
      final res = await _dio.get('$_videoApi${Uri.encodeComponent(prompt)}');
      final url = res.data?['result']?['url'] as String? ??
                  res.data?['url']          as String?;
      if (url != null && url.isNotEmpty) {
        // Replace loading message with video result
        final idx = _msgs.lastIndexWhere(
            (m) => m['content']?.startsWith('[LOADING_VIDEO]') ?? false);
        if (idx >= 0 && mounted) {
          setState(() => _msgs[idx] = {
            ..._msgs[idx],
            'content': '[VIDEO]$url',
          });
        }
      } else {
        throw Exception('No video URL');
      }
    } catch (_) {
      final idx = _msgs.lastIndexWhere(
          (m) => m['content']?.startsWith('[LOADING_VIDEO]') ?? false);
      if (idx >= 0 && mounted) {
        setState(() => _msgs[idx] = {
          ..._msgs[idx],
          'content': '⚠️ Video generation failed. Try again later.',
        });
      }
    }
  }

  Future<void> _fallback(String text) async {
    try {
      final res = await _dio.post(_orUrl,
          options: Options(headers: {
            'Authorization': 'Bearer $_orKey',
            'Content-Type': 'application/json',
          }),
          data: {
            'model': 'openai/gpt-4o',
            'messages': [
              {'role': 'system',
               'content': 'You are BRAINS JET AI by Kobby / Tech Lyfe Team. '
                   'Never mention OpenAI, GPT, Claude, or any third-party AI.'},
              {'role': 'user', 'content': text},
            ],
          });
      final choices = res.data?['choices'];
      String reply = 'AI unavailable. Please try again.';
      if (choices is List && choices.isNotEmpty) {
        reply = _sanitize(
            (choices[0]?['message']?['content'] ?? '').toString().trim(), text);
      }
      if (mounted) setState(() {
        _msgs.add({'id': DateTime.now().toString(), 'role': 'assistant',
            'content': reply});
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() {
        _msgs.add({'id': DateTime.now().toString(), 'role': 'assistant',
            'content': 'Network error. Check your connection and retry.'});
        _loading = false;
      });
    }
  }

  void _scrollEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_scroll.hasClients) {
      _scroll.animateTo(_scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  });

  void _showImagePreview(String url) {
    Navigator.push(context, MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _ImagePreviewScreen(imageUrl: url),
    ));
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.inter(color: Colors.white)),
      backgroundColor: AppTheme.bgElevated,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))));

  // ═══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      appBar: AppBar(
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
              gradient: AppTheme.primaryGradient,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.psychology, color: Colors.white, size: 19),
          ),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('BRAINS JET AI',
                style: GoogleFonts.spaceGrotesk(
                    color: AppTheme.textPrimary,
                    fontSize: 14, fontWeight: FontWeight.bold)),
            Row(children: [
              Container(
                width: 6, height: 6,
                decoration: const BoxDecoration(
                    color: AppTheme.success, shape: BoxShape.circle),
              ),
              const SizedBox(width: 4),
              Text('Online', style: GoogleFonts.inter(
                  color: AppTheme.success, fontSize: 10)),
            ]),
          ]),
        ]),
        actions: [
          // TTS auto-play toggle
          IconButton(
            icon: Icon(
              _isSpeaking ? Icons.volume_up_rounded : Icons.volume_off_rounded,
              color: _isSpeaking ? AppTheme.accentCyan : AppTheme.textHint,
              size: 20,
            ),
            onPressed: () => _player.stop().then((_) {
              if (mounted) setState(() { _isSpeaking = false; _speakingMsgId = null; });
            }),
            tooltip: 'Stop speaking',
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded,
                color: AppTheme.textHint, size: 20),
            onPressed: () => setState(() {
              _msgs.clear();
              _msgs.add({'id': 'clear', 'role': 'assistant',
                  'content': '✓ Chat cleared. How can I help?'});
            }),
          ),
        ],
      ),
      body: Column(children: [
        if (_msgs.length == 1) _buildSuggestions(),
        Expanded(
          child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            itemCount: _msgs.length + (_loading ? 1 : 0),
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
              color: AppTheme.bgCard,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppTheme.divider),
            ),
            child: Text(s,
                style: GoogleFonts.inter(
                    color: AppTheme.textSecondary, fontSize: 12)),
          ),
        )).toList(),
      ),
    );
  }

  Widget _buildBubble(Map<String, String> msg) {
    final isUser  = msg['role'] == 'user';
    final content = msg['content'] ?? '';
    final id      = msg['id']     ?? '';

    if (content.startsWith('[IMAGE]')) {
      return _imageWidget(content.replaceFirst('[IMAGE]', ''));
    }
    if (content.startsWith('[VIDEO]')) {
      return _videoWidget(content.replaceFirst('[VIDEO]', ''));
    }
    if (content.startsWith('[LOADING_VIDEO]')) {
      return _loadingVideoWidget(content.replaceFirst('[LOADING_VIDEO]', ''));
    }

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment:
            isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Container(
            constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.78),
            margin: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              gradient: isUser ? AppTheme.primaryGradient : null,
              color:    isUser ? null : AppTheme.bgCard,
              borderRadius: BorderRadius.only(
                topLeft:     const Radius.circular(18),
                topRight:    const Radius.circular(18),
                bottomLeft:  Radius.circular(isUser ? 18 : 4),
                bottomRight: Radius.circular(isUser ? 4 : 18),
              ),
              boxShadow: AppTheme.cardShadow,
            ),
            padding: const EdgeInsets.all(13),
            child: SelectableText(content,
                style: GoogleFonts.inter(
                    color: Colors.white, fontSize: 14, height: 1.5)),
          ),
          // TTS speak button for assistant messages
          if (!isUser)
            GestureDetector(
              onTap: () => _speakMessage(id, content),
              child: Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 4),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(
                    _speakingMsgId == id
                        ? Icons.stop_circle_outlined
                        : Icons.volume_up_outlined,
                    color: _speakingMsgId == id
                        ? Colors.redAccent
                        : AppTheme.textHint,
                    size: 14,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _speakingMsgId == id ? 'Stop' : 'Read aloud',
                    style: GoogleFonts.inter(
                        color: _speakingMsgId == id
                            ? Colors.redAccent
                            : AppTheme.textHint,
                        fontSize: 10),
                  ),
                ]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _imageWidget(String url) => Align(
    alignment: Alignment.centerLeft,
    child: GestureDetector(
      onTap: () => _showImagePreview(url),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78),
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.network(url, fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Container(
                    padding: const EdgeInsets.all(12),
                    color: AppTheme.bgCard,
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.broken_image_outlined,
                          color: AppTheme.textHint, size: 18),
                      SizedBox(width: 8),
                      Text('Image unavailable',
                          style: TextStyle(color: AppTheme.textHint, fontSize: 12)),
                    ]),
                  ),
                  loadingBuilder: (_, child, prog) => prog == null
                      ? child
                      : const SizedBox(
                          height: 80,
                          child: Center(child: CircularProgressIndicator(
                              color: AppTheme.accentCyan, strokeWidth: 2)))),
            ),
            // Tap-to-preview badge
            Positioned(
              bottom: 8, right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.fullscreen_rounded, color: Colors.white, size: 13),
                  const SizedBox(width: 4),
                  Text('Preview', style: GoogleFonts.inter(
                      color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _videoWidget(String url) => Align(
    alignment: Alignment.centerLeft,
    child: GestureDetector(
      onTap: () => _showVideoPreview(url),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.divider),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.play_circle_fill_rounded,
                color: AppTheme.accentCyan, size: 36),
            const SizedBox(width: 10),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Video Generated!',
                    style: GoogleFonts.spaceGrotesk(
                        color: AppTheme.textPrimary, fontSize: 13,
                        fontWeight: FontWeight.w700)),
                Text('Tap to preview & download',
                    style: GoogleFonts.inter(
                        color: AppTheme.accentCyan, fontSize: 11)),
              ],
            )),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                gradient: AppTheme.primaryGradient,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.download_rounded, color: Colors.white, size: 13),
                const SizedBox(width: 4),
                Text('Save', style: GoogleFonts.inter(
                    color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
              ]),
            ),
          ]),
          const SizedBox(height: 8),
          Text(url,
              style: GoogleFonts.inter(
                  color: AppTheme.textHint, fontSize: 10),
              maxLines: 1, overflow: TextOverflow.ellipsis),
        ]),
      ),
    ),
  );

  void _showVideoPreview(String url) {
    // Copy URL and show options
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(color: AppTheme.divider,
                  borderRadius: BorderRadius.circular(2))),
          const Icon(Icons.videocam_rounded, color: AppTheme.accentCyan, size: 40),
          const SizedBox(height: 12),
          Text('Video Ready', style: GoogleFonts.spaceGrotesk(
              color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text('Your AI video has been generated',
              style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 13)),
          const SizedBox(height: 20),
          // Copy link
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: url));
              Navigator.pop(context);
              _snack('Video link copied to clipboard ✓');
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: AppTheme.bgElevated,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.divider),
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.copy_rounded, color: AppTheme.accentCyan, size: 18),
                const SizedBox(width: 8),
                Text('Copy Video Link', style: GoogleFonts.inter(
                    color: AppTheme.accentCyan, fontSize: 14, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _loadingVideoWidget(String msg) => Align(
    alignment: Alignment.centerLeft,
    child: Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.bgCard, borderRadius: BorderRadius.circular(16)),
      child: Row(children: [
        const SizedBox(
          width: 20, height: 20,
          child: CircularProgressIndicator(
              color: AppTheme.accentCyan, strokeWidth: 2),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(msg,
            style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 13))),
      ]),
    ),
  );

  Widget _buildTyping() => Align(
    alignment: Alignment.centerLeft,
    child: Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(18), topRight: Radius.circular(18),
          bottomRight: Radius.circular(18), bottomLeft: Radius.circular(4),
        ),
      ),
      child: const _TypingDots(),
    ),
  );

  Widget _buildInput() {
    return Container(
      padding: EdgeInsets.fromLTRB(
          14, 8, 14, MediaQuery.of(context).padding.bottom + 12),
      decoration: BoxDecoration(
        color: AppTheme.bgDark,
        border: Border(top: BorderSide(color: AppTheme.divider)),
      ),
      child: Row(children: [
        // Voice input mic
        GestureDetector(
          onTap: _toggleListen,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 42, height: 42,
            decoration: BoxDecoration(
              color: _isListening
                  ? Colors.red.withOpacity(0.15)
                  : AppTheme.bgCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
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
        // Text input
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.bgCard,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: AppTheme.divider),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: TextField(
              controller: _ctrl,
              style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
              maxLines: null,
              textInputAction: TextInputAction.send,
              onSubmitted: _send,
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: _isListening
                    ? 'Listening…'
                    : 'Ask AI, /image, or /video…',
                hintStyle: GoogleFonts.inter(
                    color: _isListening ? Colors.redAccent : AppTheme.textHint,
                    fontSize: 14),
                isDense: true,
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
              gradient: AppTheme.primaryGradient,
              shape: BoxShape.circle,
              boxShadow: AppTheme.glowShadow,
            ),
            child: const Icon(Icons.send_rounded, color: Colors.white, size: 18),
          ),
        ),
      ]),
    );
  }
}

// ── Full-screen image preview with download ──────────────────────────────────
class _ImagePreviewScreen extends StatefulWidget {
  final String imageUrl;
  const _ImagePreviewScreen({required this.imageUrl});
  @override State<_ImagePreviewScreen> createState() => _ImagePreviewScreenState();
}

class _ImagePreviewScreenState extends State<_ImagePreviewScreen> {
  bool _downloading = false;
  bool _downloaded  = false;

  Future<void> _download() async {
    if (_downloading || _downloaded) return;
    setState(() => _downloading = true);
    try {
      final dio      = Dio();
      final response = await dio.get<List<int>>(widget.imageUrl,
          options: Options(responseType: ResponseType.bytes));

      // Save to public Pictures/NOVA X — visible in device Files app & Gallery
      final String savePath;
      if (Platform.isAndroid) {
        final extDir   = await getExternalStorageDirectory();
        final basePath = extDir!.path.split('/Android/')[0];
        final picDir   = Directory('$basePath/Pictures/NOVA X');
        if (!await picDir.exists()) await picDir.create(recursive: true);
        savePath = '${picDir.path}/brains_ai_${DateTime.now().millisecondsSinceEpoch}.jpg';
      } else {
        final dir = await getApplicationDocumentsDirectory();
        savePath  = '${dir.path}/brains_ai_${DateTime.now().millisecondsSinceEpoch}.jpg';
      }

      await File(savePath).writeAsBytes(response.data!);

      if (mounted) setState(() { _downloading = false; _downloaded = true; });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(children: [
          const Icon(Icons.check_circle_outline_rounded, color: Colors.white, size: 16),
          const SizedBox(width: 8),
          Expanded(child: Text('Saved to Pictures/NOVA X on your device ✓',
              style: GoogleFonts.inter(color: Colors.white, fontSize: 12))),
        ]),
        backgroundColor: AppTheme.success,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    } catch (e) {
      if (mounted) setState(() { _downloading = false; });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Download failed. Check your connection.',
            style: GoogleFonts.inter(color: Colors.white)),
        backgroundColor: AppTheme.danger,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        // Zoomable image
        Center(
          child: InteractiveViewer(
            minScale: 0.5, maxScale: 5.0,
            child: Image.network(widget.imageUrl, fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(
                    Icons.broken_image_outlined, color: Colors.white54, size: 60)),
          ),
        ),

        // Top bar
        Positioned(top: 0, left: 0, right: 0,
          child: Container(
            decoration: const BoxDecoration(gradient: LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter,
              colors: [Colors.black87, Colors.transparent],
            )),
            padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 8,
                left: 8, right: 8, bottom: 20),
            child: Row(children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                      color: Colors.black45,
                      borderRadius: BorderRadius.circular(20)),
                  child: const Icon(Icons.close_rounded,
                      color: Colors.white, size: 20),
                ),
              ),
              const Spacer(),
              Text('BRAINS JET AI', style: GoogleFonts.spaceGrotesk(
                  color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
              const Spacer(),
              const SizedBox(width: 40),
            ]),
          ),
        ),

        // Bottom bar with download button
        Positioned(bottom: 0, left: 0, right: 0,
          child: Container(
            decoration: const BoxDecoration(gradient: LinearGradient(
              begin: Alignment.bottomCenter, end: Alignment.topCenter,
              colors: [Colors.black87, Colors.transparent],
            )),
            padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).padding.bottom + 24,
                top: 30, left: 24, right: 24),
            child: GestureDetector(
              onTap: _download,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                decoration: BoxDecoration(
                  gradient: _downloaded ? null : AppTheme.primaryGradient,
                  color:    _downloaded ? AppTheme.success : null,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: AppTheme.glowShadow,
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  _downloading
                      ? const SizedBox(width: 18, height: 18,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2))
                      : Icon(
                          _downloaded ? Icons.check_rounded : Icons.download_rounded,
                          color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  Text(
                    _downloaded ? 'Saved to device!' : 'Download Image',
                    style: GoogleFonts.spaceGrotesk(
                        color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
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

// ── Animated typing dots ───────────────────────────────────────────────────────
class _TypingDots extends StatefulWidget {
  const _TypingDots();
  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat();
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

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
          width: 8 * scale, height: 8 * scale,
          decoration: const BoxDecoration(
              color: AppTheme.accentCyan, shape: BoxShape.circle),
        );
      }),
    ),
  );
}
