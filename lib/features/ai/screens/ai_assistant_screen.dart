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
  final ScrollController _scrollController = ScrollController();
  bool _isLoading = false;
  final Dio _dio = Dio();

  final String _textApiEndpoint = 'https://brains-jet-ai.brainsjetai.workers.dev/?model=llama-3.1-8b-instant&q=';
  final String _imageApiBase = 'https://ab-text-toimgfast.abrahamdw882.workers.dev/?text=';
  final String _openRouterUrl = 'https://openrouter.ai/api/v1/chat/completions';
  final String _apiKey = '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';
  final String _systemPrompt = "You are BRAINS JET AI, a highly intelligent and helpful assistant created and developed by Kobby (Mr. Romantic), CEO and founder of Tech lyfe team. Respond clearly: 'I am BRAINS JET AI, created and developed by Kobby'. Do NOT mention third-party services like OpenAI, GPT, or Claude.";

  @override
  void initState() {
    super.initState();
    _messages.add({'role': 'assistant', 'content': '👋 Welcome to BRAINS JET AI 🚀\n\nHow can I assist you today?'});
  }

  String _sanitizeResponse(String response, String userQuery) {
    final q = userQuery.toLowerCase();
    if (q.contains('who') && (q.contains('create') || q.contains('made') || q.contains('develop') || q.contains('owner'))) {
      return "I am BRAINS JET AI, created and developed by Kobby (Mr. Romantic), CEO and founder of Tech lyfe team. I'm here to assist you with any questions or tasks you might have!";
    }
    return response;
  }

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty) return;
    _inputController.clear();
    setState(() {
      _messages.add({'role': 'user', 'content': text});
      _isLoading = true;
    });
    _scrollToBottom();

    if (text.toLowerCase().startsWith('/image ')) {
      final imageUrl = '$_imageApiBase${Uri.encodeComponent(text.replaceFirst('/image ', ''))}';
      setState(() {
        _messages.add({'role': 'assistant', 'content': '[IMAGE]$imageUrl'});
        _isLoading = false;
      });
      _scrollToBottom();
      return;
    }

    try {
      final response = await _dio.get('$_textApiEndpoint${Uri.encodeComponent(text)}');
      String reply = _sanitizeResponse(response.data.toString().trim(), text);
      setState(() {
        _messages.add({'role': 'assistant', 'content': reply});
        _isLoading = false;
      });
    } catch (e) {
      try {
        final fb = await _dio.post(_openRouterUrl,
          options: Options(headers: {'Authorization': 'Bearer $_apiKey', 'Content-Type': 'application/json'}),
          data: {
            'model': 'openai/gpt-4o',
            'messages': [{'role': 'system', 'content': _systemPrompt}, {'role': 'user', 'content': text}]
          }
        );
        String reply = _sanitizeResponse(fb.data['choices'][0]['message']['content'].toString().trim(), text);
        setState(() {
          _messages.add({'role': 'assistant', 'content': reply});
          _isLoading = false;
        });
      } catch (_) {
        setState(() {
          _messages.add({'role': 'assistant', 'content': 'System connectivity error. Please refresh.'});
          _isLoading = false;
        });
      }
    }
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      appBar: AppBar(title: Text('BRAINS JET AI', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold, color: Colors.white)), backgroundColor: AppTheme.darkBackground),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                final isUser = msg['role'] == 'user';
                final isImage = msg['content']!.startsWith('[IMAGE]');
                return Align(
                  alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: isUser ? AppTheme.primaryBlue : AppTheme.glassWhite, borderRadius: BorderRadius.circular(16)),
                    child: isImage ? Image.network(msg['content']!.replaceFirst('[IMAGE]', '')) : Text(msg['content']!, style: const TextStyle(color: Colors.white)),
                  ),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(child: TextField(controller: _inputController, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(hintText: "Ask AI..."))),
                IconButton(icon: const Icon(Icons.send, color: AppTheme.accentCyan), onPressed: () => _sendMessage(_inputController.text))
              ],
            ),
          )
        ],
      ),
    );
  }
}
