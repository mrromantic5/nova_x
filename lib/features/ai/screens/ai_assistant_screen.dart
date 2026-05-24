import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nova_x/core/theme/app_theme.dart';

class AiAssistantScreen extends StatefulWidget {
  const AiAssistantScreen({super.key});

  @override
  State<AiAssistantScreen> createState() => _AiAssistantScreenState();
}

class _AiAssistantScreenState extends State<AiAssistantScreen> {
  final List<Map<String, String>> _messages = [];
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController   = ScrollController();
  bool _isLoading = false;
  final Dio _dio  = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
  ));

  // ── API endpoints ────────────────────────────────────────────────────────
  static const String _primaryEndpoint =
      'https://brains-jet-ai.brainsjetai.workers.dev/?model=llama-3.1-8b-instant&q=';
  static const String _imageEndpoint =
      'https://ab-text-toimgfast.abrahamdw882.workers.dev/?text=';
  static const String _fallbackUrl =
      'https://openrouter.ai/api/v1/chat/completions';
  static const String _apiKey =
      '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';
  static const String _systemPrompt =
      "You are BRAINS JET AI, a highly intelligent and helpful assistant "
      "created and developed by Kobby (Mr. Romantic), CEO and founder of "
      "Tech lyfe team. If asked who created you, respond clearly: "
      "'I am BRAINS JET AI, created and developed by Kobby'. "
      "Do NOT mention OpenAI, GPT, Claude, or any third-party AI service.";

  @override
  void initState() {
    super.initState();
    _messages.add({
      'role':    'assistant',
      'content': '👋 Welcome to BRAINS JET AI 🚀\n\nHow can I assist you today?',
    });
  }

  @override
  void dispose() {
    // FIXED: both controllers were never disposed — caused memory leaks on
    // each navigation to/from this screen.
    _inputController.dispose();
    _scrollController.dispose();
    _dio.close();
    super.dispose();
  }

  // ── Identity guard ───────────────────────────────────────────────────────
  String _sanitize(String response, String query) {
    final q = query.toLowerCase();
    if (q.contains('who') &&
        (q.contains('creat') || q.contains('made') ||
            q.contains('develop') || q.contains('owner') ||
            q.contains('built'))) {
      return "I am BRAINS JET AI, created and developed by Kobby "
          "(Mr. Romantic), CEO and founder of Tech lyfe team. "
          "I'm here to assist you with any questions or tasks!";
    }
    return response.isEmpty ? 'No response received. Please try again.' : response;
  }

  // ── Send message ─────────────────────────────────────────────────────────
  Future<void> _sendMessage(String text) async {
    final t = text.trim();
    if (t.isEmpty) return;

    _inputController.clear();
    if (!mounted) return;
    setState(() {
      _messages.add({'role': 'user', 'content': t});
      _isLoading = true;
    });
    _scrollToBottom();

    // Image generation command
    if (t.toLowerCase().startsWith('/image ')) {
      final prompt = t.replaceFirst(RegExp(r'^/image\s+', caseSensitive: false), '');
      final url = '$_imageEndpoint${Uri.encodeComponent(prompt)}';
      if (!mounted) return;
      setState(() {
        _messages.add({'role': 'assistant', 'content': '[IMAGE]$url'});
        _isLoading = false;
      });
      _scrollToBottom();
      return;
    }

    // Primary API call
    try {
      final res = await _dio.get(
        '$_primaryEndpoint${Uri.encodeComponent(t)}',
      );
      final reply = _sanitize(
        (res.data ?? '').toString().trim(),
        t,
      );
      if (!mounted) return;
      setState(() {
        _messages.add({'role': 'assistant', 'content': reply});
        _isLoading = false;
      });
    } catch (_) {
      // Fallback to OpenRouter
      await _callFallback(t);
    }
    _scrollToBottom();
  }

  Future<void> _callFallback(String text) async {
    try {
      final res = await _dio.post(
        _fallbackUrl,
        options: Options(headers: {
          'Authorization': 'Bearer $_apiKey',
          'Content-Type':  'application/json',
        }),
        data: {
          'model': 'openai/gpt-4o',
          'messages': [
            {'role': 'system', 'content': _systemPrompt},
            {'role': 'user',   'content': text},
          ],
        },
      );

      // FIXED: previously `fb.data['choices'][0]` with no null check threw
      // a RangeError crash when OpenRouter returned an empty or error body.
      final choices = res.data?['choices'];
      String reply;
      if (choices is List && choices.isNotEmpty) {
        final content = choices[0]?['message']?['content'];
        reply = _sanitize((content ?? '').toString().trim(), text);
      } else {
        reply = 'AI is temporarily unavailable. Please try again shortly.';
      }

      if (!mounted) return;
      setState(() {
        _messages.add({'role': 'assistant', 'content': reply});
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _messages.add({
          'role':    'assistant',
          'content': 'Network error. Please check your connection and retry.',
        });
        _isLoading = false;
      });
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      appBar: AppBar(
        backgroundColor: AppTheme.darkBackground,
        elevation: 0,
        title: Text(
          'BRAINS JET AI',
          style: GoogleFonts.spaceGrotesk(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        actions: [
          // Clear chat
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.white54),
            tooltip: 'Clear chat',
            onPressed: () {
              setState(() {
                _messages.clear();
                _messages.add({
                  'role':    'assistant',
                  'content': '👋 Chat cleared. How can I help you?',
                });
              });
            },
          ),
        ],
      ),

      body: Column(
        children: [
          // ── Message list ────────────────────────────────────────────────
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              itemCount: _messages.length + (_isLoading ? 1 : 0),
              itemBuilder: (context, index) {
                // Typing indicator
                if (_isLoading && index == _messages.length) {
                  return const Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: _TypingIndicator(),
                    ),
                  );
                }

                final msg     = _messages[index];
                final isUser  = msg['role'] == 'user';
                final content = msg['content'] ?? '';
                final isImage = content.startsWith('[IMAGE]');

                return Align(
                  alignment:
                      isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.78,
                    ),
                    margin: const EdgeInsets.symmetric(vertical: 5),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isUser
                          ? AppTheme.primaryBlue
                          : AppTheme.glassWhite,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: isImage
                        ? _buildImageMessage(
                            content.replaceFirst('[IMAGE]', ''))
                        : SelectableText(
                            content,
                            style: const TextStyle(
                              color: Colors.white, height: 1.5),
                          ),
                  ),
                );
              },
            ),
          ),

          // ── Input bar ──────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            decoration: BoxDecoration(
              color: AppTheme.darkBackground,
              border: Border(
                top: BorderSide(color: Colors.white12, width: 0.5),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _inputController,
                    style: const TextStyle(color: Colors.white),
                    maxLines: null,
                    textInputAction: TextInputAction.send,
                    onSubmitted: _sendMessage,
                    decoration: InputDecoration(
                      hintText: 'Ask AI… (type /image for images)',
                      hintStyle: const TextStyle(color: Colors.white38),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: const BorderSide(color: Colors.white24),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24),
                        borderSide: const BorderSide(
                          color: AppTheme.accentCyan),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => _sendMessage(_inputController.text),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: const BoxDecoration(
                      color: AppTheme.primaryBlue,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.send, color: Colors.white, size: 20),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── AI-generated image widget ────────────────────────────────────────────
  Widget _buildImageMessage(String url) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        url,
        fit: BoxFit.contain,
        // FIXED: was missing — a failed image URL previously showed Flutter's
        // red error widget filling the entire message bubble.
        errorBuilder: (_, __, ___) => Container(
          padding: const EdgeInsets.all(12),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.broken_image_outlined,
                  color: Colors.white54, size: 20),
              SizedBox(width: 8),
              Text('Image unavailable',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
            ],
          ),
        ),
        loadingBuilder: (_, child, progress) {
          if (progress == null) return child;
          return const SizedBox(
            height: 80,
            child: Center(
              child: CircularProgressIndicator(
                  color: AppTheme.accentCyan, strokeWidth: 2),
            ),
          );
        },
      ),
    );
  }
}

// ── Animated typing indicator ──────────────────────────────────────────────
class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.3, end: 1.0).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _anim,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.glassWhite,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) => Container(
            margin: EdgeInsets.only(left: i == 0 ? 0 : 4),
            width: 7, height: 7,
            decoration: const BoxDecoration(
              color: AppTheme.accentCyan, shape: BoxShape.circle),
          )),
        ),
      ),
    );
  }
}
