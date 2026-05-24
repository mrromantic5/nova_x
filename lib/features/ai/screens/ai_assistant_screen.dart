import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nova_x/core/theme/app_theme.dart';

class AiAssistantScreen extends StatefulWidget {
  const AiAssistantScreen({super.key});

  @override
  State<AiAssistantScreen> createState() => _AiAssistantScreenState();
}

class _AiAssistantScreenState extends State<AiAssistantScreen>
    with SingleTickerProviderStateMixin {
  final List<Map<String, String>> _msgs = [];
  final TextEditingController _ctrl = TextEditingController();
  final ScrollController _scroll   = ScrollController();
  bool _loading = false;

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
  ));

  static const String _primary =
      'https://brains-jet-ai.brainsjetai.workers.dev/?model=llama-3.1-8b-instant&q=';
  static const String _imageEp =
      'https://ab-text-toimgfast.abrahamdw882.workers.dev/?text=';
  static const String _fallbackUrl =
      'https://openrouter.ai/api/v1/chat/completions';
  static const String _apiKey =
      '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';

  // Suggested quick prompts
  final List<String> _suggestions = [
    'Summarise a news article',
    'Help me write an email',
    'Explain a concept simply',
    'Generate an image',
  ];

  @override
  void initState() {
    super.initState();
    _msgs.add({
      'role':    'assistant',
      'content': '👋 Hi! I\'m **BRAINS JET AI**, your intelligent assistant.\n\nI can help you search, answer questions, write content, and even generate images.\n\nType **/image [description]** to create an image.',
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    _dio.close(force: false);
    super.dispose();
  }

  String _sanitize(String r, String q) {
    final ql = q.toLowerCase();
    if (ql.contains('who') &&
        RegExp(r'creat|made|develop|owner|built').hasMatch(ql)) {
      return 'I am BRAINS JET AI, created and developed by Kobby (Mr. Romantic), CEO of Tech Lyfe Team. How can I help you today?';
    }
    return r.isEmpty ? 'No response. Please try again.' : r;
  }

  Future<void> _send(String text) async {
    final t = text.trim();
    if (t.isEmpty) return;
    _ctrl.clear();
    HapticFeedback.lightImpact();
    if (!mounted) return;
    setState(() {
      _msgs.add({'role': 'user', 'content': t});
      _loading = true;
    });
    _scrollEnd();

    // Image command
    if (t.toLowerCase().startsWith('/image ')) {
      final prompt =
          t.replaceFirst(RegExp(r'^/image\s+', caseSensitive: false), '');
      final url = '$_imageEp${Uri.encodeComponent(prompt)}';
      if (mounted) {
        setState(() {
          _msgs.add({'role': 'assistant', 'content': '[IMAGE]$url'});
          _loading = false;
        });
      }
      _scrollEnd();
      return;
    }

    // Primary API
    try {
      final res = await _dio.get('$_primary${Uri.encodeComponent(t)}');
      final reply = _sanitize((res.data ?? '').toString().trim(), t);
      if (mounted) {
        setState(() {
          _msgs.add({'role': 'assistant', 'content': reply});
          _loading = false;
        });
      }
    } catch (_) {
      await _fallback(t);
    }
    _scrollEnd();
  }

  Future<void> _fallback(String text) async {
    try {
      final res = await _dio.post(_fallbackUrl,
          options: Options(headers: {
            'Authorization': 'Bearer $_apiKey',
            'Content-Type': 'application/json',
          }),
          data: {
            'model': 'openai/gpt-4o',
            'messages': [
              {'role': 'system',
               'content': 'You are BRAINS JET AI by Kobby / Tech Lyfe Team. Never mention OpenAI, GPT, or Claude.'},
              {'role': 'user', 'content': text},
            ],
          });
      final choices = res.data?['choices'];
      String reply;
      if (choices is List && choices.isNotEmpty) {
        reply = _sanitize(
            (choices[0]?['message']?['content'] ?? '').toString().trim(), text);
      } else {
        reply = 'AI is temporarily unavailable. Please try again.';
      }
      if (mounted) setState(() { _msgs.add({'role': 'assistant', 'content': reply}); _loading = false; });
    } catch (_) {
      if (mounted) setState(() {
        _msgs.add({'role': 'assistant', 'content': 'Network error. Check your connection.'});
        _loading = false;
      });
    }
  }

  void _scrollEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut);
      }
    });
  }

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
            width: 32, height: 32,
            decoration: BoxDecoration(
              gradient: AppTheme.primaryGradient,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.psychology, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('BRAINS JET AI',
                style: GoogleFonts.spaceGrotesk(
                    color: AppTheme.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.bold)),
            Text('Online',
                style: GoogleFonts.inter(
                    color: AppTheme.success, fontSize: 10)),
          ]),
        ]),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded,
                color: AppTheme.textHint, size: 20),
            onPressed: () => setState(() {
              _msgs.clear();
              _msgs.add({'role': 'assistant', 'content': '✓ Chat cleared. How can I help?'});
            }),
          ),
        ],
      ),
      body: Column(children: [
        // Suggestions row
        if (_msgs.length == 1)
          _buildSuggestions(),
        // Messages
        Expanded(
          child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
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
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
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
    final isImage = content.startsWith('[IMAGE]');

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78),
        margin: const EdgeInsets.symmetric(vertical: 5),
        decoration: BoxDecoration(
          gradient: isUser ? AppTheme.primaryGradient : null,
          color: isUser ? null : AppTheme.bgCard,
          borderRadius: BorderRadius.only(
            topLeft:     const Radius.circular(18),
            topRight:    const Radius.circular(18),
            bottomLeft:  Radius.circular(isUser ? 18 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 18),
          ),
          boxShadow: AppTheme.cardShadow,
        ),
        padding: const EdgeInsets.all(14),
        child: isImage
            ? _buildImageMsg(content.replaceFirst('[IMAGE]', ''))
            : SelectableText(content,
                style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 14,
                    height: 1.5)),
      ),
    );
  }

  Widget _buildImageMsg(String url) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.network(
        url,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => Padding(
          padding: const EdgeInsets.all(8),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.broken_image_outlined,
                color: AppTheme.textHint, size: 18),
            const SizedBox(width: 8),
            Text('Image unavailable',
                style: GoogleFonts.inter(
                    color: AppTheme.textHint, fontSize: 12)),
          ]),
        ),
        loadingBuilder: (_, child, progress) => progress == null
            ? child
            : const SizedBox(
                height: 80,
                child: Center(
                  child: CircularProgressIndicator(
                      color: AppTheme.accentCyan, strokeWidth: 2),
                )),
      ),
    );
  }

  Widget _buildTyping() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: const BorderRadius.only(
            topLeft:     Radius.circular(18),
            topRight:    Radius.circular(18),
            bottomRight: Radius.circular(18),
            bottomLeft:  Radius.circular(4),
          ),
        ),
        child: const _TypingDots(),
      ),
    );
  }

  Widget _buildInput() {
    return Container(
      padding: EdgeInsets.fromLTRB(
          16, 8, 16, MediaQuery.of(context).padding.bottom + 12),
      decoration: BoxDecoration(
        color: AppTheme.bgDark,
        border: Border(top: BorderSide(color: AppTheme.divider)),
      ),
      child: Row(children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.bgCard,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: AppTheme.divider),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
            child: TextField(
              controller: _ctrl,
              style: GoogleFonts.inter(color: Colors.white, fontSize: 14),
              maxLines: null,
              textInputAction: TextInputAction.send,
              onSubmitted: _send,
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: 'Ask AI or type /image…',
                hintStyle: GoogleFonts.inter(
                    color: AppTheme.textHint, fontSize: 14),
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: () => _send(_ctrl.text),
          child: Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              gradient: AppTheme.primaryGradient,
              shape: BoxShape.circle,
              boxShadow: AppTheme.glowShadow,
            ),
            child: const Icon(Icons.send_rounded,
                color: Colors.white, size: 18),
          ),
        ),
      ]),
    );
  }
}

// ── Animated typing indicator ─────────────────────────────────────────────────
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
  Widget build(BuildContext context) {
    return AnimatedBuilder(
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
}
