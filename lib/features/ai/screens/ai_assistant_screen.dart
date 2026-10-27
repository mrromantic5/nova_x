// lib/features/ai/screens/ai_assistant_screen.dart
//
// NOVA X — NOVA AI chat screen
// v3.3.0 — Photos: 📎 attaches up to 3 photos or screenshots (camera or
// gallery), and the browser's "Ask NOVA about this page" opens this screen
// with a capture of the page. NOVA reads them through the Worker's /vision.
// Photos are saved on this phone only (NovaMediaStore); synced chats carry
// just a reference, so other phones show "Photo is on your other phone".
// v3.2.0 — Chat history: every chat is saved on the phone and, for signed-in
// users, on the NOVA X server (☰ opens the history; long-press a chat to
// rename or delete it). Replies are read aloud with the NOVA Voice chosen in
// NOVA settings → Voice. The welcome message is folded (tap ▾ to see more).
// The 🎙 button opens the NOVA voice assistant.
// v3.0.0 — Brains Jet AI replaced by the NOVA AI API (Tech Lyfe Cloudflare
// Worker, lib/features/nova/services/nova_api.dart). No AI keys live in the
// app any more. Image (/image) and video (/video) generation are unchanged.
// Voice: the mic records a short clip that NOVA transcribes; replies are read
// aloud with NOVA Voice, or the phone's own voice when the voice service is
// unavailable.
// v2.1.0 — AI content flag/report added for Google Play policy compliance.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nova_x/core/services/rewards_service.dart';
import 'package:nova_x/core/services/api_service.dart';
import 'package:nova_x/core/theme/app_theme.dart';
import 'package:nova_x/features/ai/services/nova_chat_commands.dart';
import 'package:nova_x/features/ai/services/nova_chat_repository.dart';
import 'package:nova_x/features/ai/services/nova_markdown_parser.dart';
import 'package:nova_x/features/ai/services/nova_media_store.dart';
import 'package:nova_x/features/ai/services/nova_quota.dart';
import 'package:nova_x/features/ai/widgets/ai_flag_sheet.dart';
import 'package:nova_x/features/ai/widgets/nova_chat_drawer.dart';
import 'package:nova_x/features/ai/widgets/nova_image_generating.dart';
import 'package:nova_x/features/ai/widgets/nova_limit_sheet.dart';
import 'package:nova_x/features/ai/widgets/nova_opening_card.dart';
import 'package:nova_x/features/ai/widgets/nova_markdown_view.dart';
import 'package:nova_x/features/browser/screens/browser_view.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:nova_x/features/network/services/network_intents.dart';
import 'package:nova_x/features/network/services/network_probe.dart';
import 'package:nova_x/features/network/services/speed_math.dart';
import 'package:nova_x/features/network/services/speed_test_engine.dart';
import 'package:nova_x/features/nova/controller/nova_controller.dart';
import 'package:nova_x/features/nova/nova_config.dart';
import 'package:nova_x/features/nova/models/nova_models.dart';
import 'package:nova_x/features/nova/nova_features.dart';
import 'package:nova_x/features/nova/nova_launcher.dart';
import 'package:nova_x/features/nova/services/nova_executor.dart';
import 'package:nova_x/features/nova/services/nova_api.dart';
import 'package:nova_x/features/nova/services/nova_native.dart';
import 'package:nova_x/features/nova/services/nova_prefs.dart';
import 'package:nova_x/features/nova/services/nova_voice.dart';
import 'package:nova_x/features/nova/services/nova_wake.dart';
import 'package:nova_x/features/premium/screens/subscription_screen.dart';
import 'package:nova_x/features/rewards/screens/rewards_screen.dart';
import 'package:nova_x/core/services/analytics_service.dart';

class AiAssistantScreen extends StatefulWidget {
  const AiAssistantScreen({super.key, this.pageCapture});

  /// Opened from the browser's "Ask NOVA about this page": the capture is
  /// attached to the first message.
  final NovaPageCapture? pageCapture;

  @override
  State<AiAssistantScreen> createState() => _AiAssistantScreenState();
}

class _AiAssistantScreenState extends State<AiAssistantScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final List<Map<String, String>> _msgs   = [];
  final TextEditingController     _ctrl   = TextEditingController();
  final ScrollController          _scroll = ScrollController();
  final GlobalKey<ScaffoldState>  _scaffoldKey = GlobalKey<ScaffoldState>();

  bool    _loading      = false;
  bool    _isSpeaking   = false;
  bool    _isListening  = false;
  bool    _transcribing = false;
  String? _speakingId;
  String? _utteranceId;

  // Chat history (null until opened, or if the phone's storage can't be used).
  NovaChatRepository? _chats;
  String _chatId          = NovaChatRepository.newChatId();
  bool   _openingChat     = false;
  int    _openToken       = 0;
  bool   _welcomeExpanded = false;

  // Photos waiting to be sent with the next message (max 3).
  final List<NovaPickedPhoto> _pending = [];
  NovaPageCapture? _page; // web page context for the next message
  NovaPickedPhoto? _pageShot; // the pending photo that is the page capture
  bool _picking = false;

  // Used only by image / video generation (unchanged).
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
  ));

  // NOVA AI (chat + transcription) and NOVA Voice (phone voice as backup).
  final NovaApiClient _nova   = NovaApiClient();
  final NovaNativeApi _native = NovaNative.instance;
  StreamSubscription<NovaNativeEvent>? _nativeSub;
  final NovaCloudVoice _voice = NovaCloudVoice(native: NovaNative.instance);
  StreamSubscription<String>? _voiceSub;
  CancelToken? _chatCancel;

  // NOVA commands typed in the chat ("open NOVA Music", "next song",
  // "test my internet speed") run for real instead of being explained.
  final NovaChatCommands _commands = NovaChatCommands();
  final NovaNetworkProbe _probe = NovaNetworkProbeImpl();
  bool _measuring = false;
  List<NovaChoice> _choices = const [];

  // ── Image & video generation (3.9.1: through the NOVA X server, which
  // keeps the providers private and enforces the daily limits) ────────────
  static const String _imageApi = '${ApiService.baseUrl}/api/v1/gen/image?text=';
  static const String _videoApi = '${ApiService.baseUrl}/api/v1/gen/video?q=';

  static Future<Map<String, String>> _authHeaders() async {
    final t = await ApiService.getToken();
    return t == null ? const {} : {'Authorization': 'Bearer $t'};
  }

  static const List<String> _suggestions = [
    'Test my internet speed',
    'Play me a song',
    'Summarise a news article',
    'Help me write an email',
    'Explain something simply',
    '/image futuristic city at night',
    '/video waves on a beach',
  ];

  // ── Welcome message (only the first line shows until ▾ is tapped) ─────────
  static const String _welcomeTitle =
      '\u{1F44B} Hi! I\'m NOVA AI, your assistant in NOVA X.';
  static const String _welcomeMore =
      '• Ask me anything — including how to use NOVA X\n'
      '• Tell me what to do: "open NOVA Network", "play me a song", "next song", "test my internet speed"\n'
      '• Type /image [description] to generate an image\n'
      '• Type /video [description] to generate a video (Premium)\n'
      '• Tap \u{1F3A4} to talk, or \u{1F50A} on any reply to hear it\n'
      '• Tap \u{1F5BC}\uFE0F to show me a photo or screenshot — I can read and explain it\n'
      '• Tap \u{1F5E3}️ at the top for the NOVA voice assistant\n'
      '• Tap ☰ to see your chats — long-press one to rename or delete it\n'
      '• Tap \u{1F6A9} Report under a reply if anything seems inappropriate';
  static const String _welcome = '$_welcomeTitle\n\n$_welcomeMore';

  static Map<String, String> _welcomeMessage() =>
      {'id': 'welcome', 'role': 'assistant', 'content': _welcome};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _nativeSub = _native.events.listen(_onNativeEvent);
    // "Hey NOVA" pauses while the chat is open (it has its own mic button).
    NovaWake.hold('chat', true);
    _voiceSub = _voice.completed.listen((id) {
      if (mounted && id == _utteranceId) {
        setState(() { _isSpeaking = false; _speakingId = null; _utteranceId = null; });
      }
    });
    _msgs.add(_welcomeMessage());
    NovaMediaStore.init().then((_) {
      if (mounted) setState(() {}); // saved photos can be shown now
    }).catchError((Object _) {});
    final capture = widget.pageCapture;
    if (capture != null) {
      _page = capture;
      _pageShot = NovaPickedPhoto(
          capture.image, NovaMediaStore.mimeOf(capture.image) ?? 'image/jpeg');
      _pending.add(_pageShot!);
    }
    // Loads the voice chosen in NOVA settings → Voice.
    _loadVoice();
    _openHistory();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _nativeSub?.cancel();
    _chatCancel?.cancel();
    _probe.cancel();
    if (_isListening) _native.cancelRecording();
    _voiceSub?.cancel();
    if (_isSpeaking) _voice.stop();
    _voice.dispose();
    NovaWake.hold('chat', false);
    _ctrl.dispose();
    _scroll.dispose();
    _dio.close(force: false);
    _nova.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // The voice may have been changed in the floating assistant, and chats
      // on another phone.
      _loadVoice();
      _chats?.sync();
    }
  }

  Future<void> _loadVoice() async {
    try {
      await NovaPrefs.load();
    } catch (_) {
      // keep the current voice
    }
  }

  // ── Chat history ───────────────────────────────────────────────────────────
  Future<void> _openHistory() async {
    try {
      final repo = await NovaChatRepository.open();
      if (!mounted) return;
      setState(() => _chats = repo);
      // A message sent before the history was ready is saved now.
      if (_savableMessages().isNotEmpty) _persist();
      unawaited(repo.sync());
    } catch (_) {
      // No history on this phone right now; chatting still works.
    }
  }

  /// The messages worth keeping (no welcome, errors or unfinished videos).
  List<Map<String, String>> _savableMessages() {
    final out = <Map<String, String>>[];
    for (final m in _msgs) {
      final id      = m['id'] ?? '';
      final role    = m['role'] ?? '';
      final content = m['content'] ?? '';
      if (id == 'welcome' || id == 'cleared' || content.trim().isEmpty) continue;
      if (role != 'user' && role != 'assistant') continue;
      if (m['error'] == 'true') continue;
      if (content.startsWith('[LOADING_VIDEO]') || content.startsWith('[GENERATING_IMAGE]') ||
          content.startsWith('[OPENING]')) continue;
      out.add({'id': id, 'role': role, 'content': content});
    }
    return out;
  }

  /// Saves the open chat (on the phone, and on the server when signed in).
  void _persist() {
    final repo = _chats;
    if (repo == null) return;
    final messages = _savableMessages();
    if (messages.isEmpty) return;
    final first = messages.firstWhere((m) => m['role'] == 'user',
        orElse: () => messages.first);
    repo
        .save(_chatId, messages,
            titleIfNew: NovaChatRepository.titleFrom(first['content'] ?? ''))
        .catchError((Object _) {
      // Storage full or unavailable: this chat simply isn't kept.
    });
  }

  /// Stops voice, recording and any reply in progress (when switching chats).
  void _stopActivity() {
    _chatCancel?.cancel();
    _chatCancel = null;
    if (_measuring) _probe.cancel();
    _measuring = false;
    _choices = const [];
    if (_isSpeaking) _stopSpeaking();
    if (_isListening) {
      _native.cancelRecording();
      _isListening = false;
    }
    _loading = false;
  }

  void _closeDrawer() {
    final scaffold = _scaffoldKey.currentState;
    if (scaffold != null && scaffold.isEndDrawerOpen) scaffold.closeEndDrawer();
  }

  void _openDrawer() {
    HapticFeedback.lightImpact();
    FocusScope.of(context).unfocus();
    _scaffoldKey.currentState?.openEndDrawer();
  }

  /// Starts a new, empty chat (the current one stays in the history).
  void _newChat({bool closeDrawer = true}) {
    HapticFeedback.lightImpact();
    if (closeDrawer) _closeDrawer();
    _openToken++;
    setState(() {
      _stopActivity();
      _chatId = NovaChatRepository.newChatId();
      _pending.clear();
      _page = null;
      _pageShot = null;
      _msgs
        ..clear()
        ..add(_welcomeMessage());
      _openingChat     = false;
      _welcomeExpanded = false;
    });
  }

  Future<void> _openChat(String id) async {
    _closeDrawer();
    final repo = _chats;
    if (repo == null || (id == _chatId && !_openingChat)) return;
    final token = ++_openToken;
    setState(() {
      _stopActivity();
      _openingChat = true;
    });
    final messages = await repo.load(id);
    if (!mounted || token != _openToken) return;
    if (messages == null || messages.isEmpty) {
      setState(() => _openingChat = false);
      _snack(repo.find(id) == null
          ? 'That chat was deleted.'
          : 'That chat couldn\'t be opened. Check your connection and try again.');
      return;
    }
    setState(() {
      _chatId = id;
      _pending.clear();
      _page = null;
      _pageShot = null;
      _msgs
        ..clear()
        ..addAll(messages);
      _openingChat     = false;
      _welcomeExpanded = false;
    });
    _scrollEnd();
  }

  void _onChatDeleted(String id) {
    if (id == _chatId) _newChat(closeDrawer: false);
  }

  // ── NOVA voice assistant ───────────────────────────────────────────────────
  Future<void> _openVoiceAssistant() async {
    HapticFeedback.mediumImpact();
    if (_isSpeaking) await _stopSpeaking();
    if (_isListening) {
      await _native.cancelRecording();
      if (mounted) setState(() => _isListening = false);
    }
    if (!mounted) return;
    await showNovaAssistant(context);
  }

  void _onNativeEvent(NovaNativeEvent e) {
    if (!mounted) return;
    if (e is NovaTtsEvent) {
      if (e.kind != 'start' && e.utteranceId == _utteranceId) {
        setState(() { _isSpeaking = false; _speakingId = null; _utteranceId = null; });
      }
    } else if (e is NovaRecordingStoppedEvent) {
      if (_isListening) _stopAndTranscribe(e.reason);
    }
  }

  // ── Voice input (NOVA records → NOVA AI transcribes) ──────────────────────
  Future<void> _toggleListen() async {
    HapticFeedback.mediumImpact();
    if (_transcribing) return;
    if (_isListening) {
      await _stopAndTranscribe('manual');
      return;
    }
    if (_isSpeaking) await _stopSpeaking();

    var start = await _native.startRecording(
        maxSeconds: NovaConfig.maxRecordingSeconds, autoStop: true);
    if (start.status == 'permission_required') {
      final granted = await _native.requestPermission('microphone');
      if (!granted) {
        _snack('Microphone permission is needed for voice input');
        return;
      }
      start = await _native.startRecording(
          maxSeconds: NovaConfig.maxRecordingSeconds, autoStop: true);
    }
    if (start.status != 'recording') {
      if (start.status != 'busy') _snack(start.message ?? 'Microphone unavailable');
      return;
    }
    if (mounted) setState(() => _isListening = true);
  }

  Future<void> _stopAndTranscribe(String reason) async {
    if (!_isListening) return;
    setState(() { _isListening = false; _transcribing = true; });
    final rec  = await _native.stopRecording();
    final path = rec.path;
    try {
      final silent = !rec.hadSpeech && reason != 'manual';
      if (reason == 'interrupted' || !rec.usable || path == null || silent ||
          rec.durationMs < NovaConfig.minRecordingMs) {
        if (reason != 'interrupted') {
          _snack('I didn\'t catch that. Tap the mic and try again.');
        }
        return;
      }
      final text = await _nova.transcribe(path);
      if (!mounted) return;
      if (text.isEmpty) {
        _snack('I didn\'t catch that. Tap the mic and try again.');
        return;
      }
      _ctrl.text = text;
      await _send(text);
    } on NovaApiException catch (e) {
      if (e.kind != NovaApiErrorKind.cancelled) _snack(e.userMessage);
    } finally {
      if (path != null) {
        try {
          final f = File(path);
          if (f.existsSync()) f.deleteSync(); // recordings are never kept
        } catch (_) {}
      }
      if (mounted) setState(() => _transcribing = false);
    }
  }

  // ── TTS (NOVA Voice chosen in NOVA settings; phone voice as fallback) ────────────
  Future<void> _speakMessage(String id, String text) async {
    HapticFeedback.lightImpact();
    if (_isSpeaking && _speakingId == id) {
      await _stopSpeaking();
      return;
    }
    await _voice.stop();
    final utterance = 'chat_${id}_${DateTime.now().millisecondsSinceEpoch}';
    if (mounted) {
      setState(() { _isSpeaking = true; _speakingId = id; _utteranceId = utterance; });
    }
    final ok = await _voice.speak(
        NovaController.speakable(text, maxChars: 4500), utterance);
    // Not started — unless the user stopped it or picked another reply meanwhile.
    if (!ok && mounted && _utteranceId == utterance) {
      setState(() { _isSpeaking = false; _speakingId = null; _utteranceId = null; });
      _snack('No voice is available right now');
    }
  }

  Future<void> _stopSpeaking() async {
    await _voice.stop();
    if (mounted) {
      setState(() { _isSpeaking = false; _speakingId = null; _utteranceId = null; });
    }
  }

  // ── Feedback on answers (3.9.1) ─────────────────────────────────────────────
  String? _feedbackOf(String id) {
    for (final m in _msgs) {
      if (m['id'] == id) return m['fb'];
    }
    return null;
  }

  void _setFeedback(String id, String? value) {
    final i = _msgs.indexWhere((m) => m['id'] == id);
    if (i < 0) return;
    setState(() {
      final m = Map<String, String>.from(_msgs[i]);
      if (value == null) {
        m.remove('fb');
      } else {
        m['fb'] = value;
      }
      _msgs[i] = m;
    });
    if (value != null) AnalyticsService.log('ai_feedback', feature: 'nova_ai', props: {'value': value});
    _persist();
  }

  // ── Report / Flag ──────────────────────────────────────────────────────────
  void _reportContent({required String contentType, String? contentRef}) {
    HapticFeedback.mediumImpact();
    showAiFlagSheet(context, contentType: contentType, contentRef: contentRef);
  }

  // ── Conversation history for NOVA AI (bounded, text turns only) ───────────
  List<Map<String, String>> _history() {
    final out = <Map<String, String>>[];
    for (final m in _msgs) {
      final id      = m['id'] ?? '';
      final role    = m['role'] ?? '';
      final content = (m['content'] ?? '').trim();
      if (id == 'welcome' || id == 'cleared' || content.isEmpty) continue;
      if (role != 'user' && role != 'assistant') continue;
      if (m['error'] == 'true') continue;
      if (content.startsWith('[IMAGE]') || content.startsWith('[VIDEO]') ||
          content.startsWith('[LOADING_VIDEO]') || content.startsWith('[GENERATING_IMAGE]') ||
          content.startsWith('[OPENING]')) {
        continue;
      }
      final lower = content.toLowerCase();
      if (role == 'user' &&
          (lower.startsWith('/image ') || lower.startsWith('/video '))) {
        continue;
      }
      final text = NovaMediaStore.forAi(content); // photos → "(I shared a photo.)"
      out.add({
        'role':    role,
        'content': text.length > NovaConfig.maxHistoryChars
            ? text.substring(0, NovaConfig.maxHistoryChars)
            : text,
      });
    }
    return out.length > NovaConfig.maxHistoryMessages
        ? out.sublist(out.length - NovaConfig.maxHistoryMessages)
        : out;
  }

  // ── Send message ────────────────────────────────────────────────────────────
  /// Unique message ids (two messages can be created in the same millisecond).
  String _newId() => '${DateTime.now().millisecondsSinceEpoch}_${_idSeq++}';
  int _idSeq = 0;

  Future<void> _send(String text) async {
    final t = text.trim();
    if (_loading || _openingChat) return;
    if (_measuring) {
      _snack('Wait a moment — the speed test is still running.');
      return;
    }
    if (_pending.isNotEmpty) {
      await _sendWithPhotos(t);
      return;
    }
    if (t.isEmpty) return;

    // Fire-and-forget earn call — result not needed
    RewardsService.earn(RewardTaskKey.useAi);

    final history = _history(); // previous turns only
    _ctrl.clear();
    HapticFeedback.lightImpact();

    final msgId = _newId();
    if (mounted) {
      setState(() {
        _msgs.add({'id': msgId, 'role': 'user', 'content': t});
        _loading = true;
      });
    }
    _persist();
    _scrollEnd();

    // Image generation: 5 per 24 hours, a "creating" card while it works,
    // and the result kept on the phone (shown and saved from that file).
    if (t.toLowerCase().startsWith('/image ')) {
      final prompt =
          t.replaceFirst(RegExp(r'^/image\s+', caseSensitive: false), '').trim();
      final blocked = await NovaQuota.tryUse(NovaQuotaKind.image);
      if (!mounted) return;
      if (blocked != null) {
        final at = blocked.resetAt;
        final when = at == null ? 'soon' : 'at ${TimeOfDay.fromDateTime(at).format(context)}';
        setState(() {
          _msgs.add({
            'id':      _newId(),
            'role':    'assistant',
            'content': "You've created ${blocked.used} of ${blocked.limit} images in the last "
                '${NovaQuotaRules.window.inHours} hours. You can create more $when.',
            'error':   'true',
          });
          _loading = false;
        });
        _scrollEnd();
        showNovaLimitSheet(context, blocked, onUpgrade: () => _openUpgrade(blocked));
        return;
      }
      final genId = _newId();
      setState(() {
        _msgs.add({
          'id':      genId,
          'role':    'assistant',
          'content': '[GENERATING_IMAGE]$prompt',
        });
        _loading = false;
      });
      _scrollEnd();
      _generateImage(prompt, genId);
      return;
    }

    // Video generation — Premium only (3 per 24 hours), 3.9.0.
    if (t.toLowerCase().startsWith('/video ')) {
      final prompt =
          t.replaceFirst(RegExp(r'^/video\s+', caseSensitive: false), '');
      final blocked = await NovaQuota.tryUse(NovaQuotaKind.video);
      if (!mounted) return;
      if (blocked != null) {
        setState(() {
          _msgs.add({
            'id':      _newId(),
            'role':    'assistant',
            'content': blocked.limit == 0
                ? 'Video generation is part of NOVA X Premium. Upgrade in Profile → Premium to create '
                    'up to ${NovaQuotaRules.limitFor(NovaQuotaKind.video, NovaTier.premium)} short videos a day.'
                : "You've created ${blocked.used} of ${blocked.limit} videos in the last "
                    '${NovaQuotaRules.window.inHours} hours. Please try again later.',
            'error':   'true',
          });
          _loading = false;
        });
        _scrollEnd();
        showNovaLimitSheet(context, blocked, onUpgrade: () => _openUpgrade(blocked));
        return;
      }
      final loadId = _newId();
      if (mounted) setState(() {
        _msgs.add({
          'id':      loadId,
          'role':    'assistant',
          'content': '[LOADING_VIDEO]Generating video for: "$prompt"…',
        });
        _loading = false;
      });
      _scrollEnd();
      _generateVideo(prompt, loadId);
      return;
    }

    // NOVA commands: open a page, control music, measure the connection.
    if (_choices.isNotEmpty) setState(() => _choices = const []);
    if (await _runCommand(t)) return;

    // Text — NOVA AI (with the photos of the last few messages, if any)
    await _ask((cancel) => _answer(t, history, cancel));
  }

  // ── NOVA commands in the chat ──────────────────────────────────────────────

  /// How long the in-chat "Opening …" card shows before the page opens.
  static const Duration _openingTime = Duration(milliseconds: 1500);

  /// Runs [t] as a NOVA command when it is one. Returns false to let NOVA AI
  /// answer instead.
  Future<bool> _runCommand(String t) async {
    final net = _commands.network(t);
    if (net != NetworkIntent.none) {
      await _runNetwork(net);
      return true;
    }
    final actions = _commands.actions(t);
    if (actions == null) return false;

    final chatId = _chatId;
    final openToken = _openToken;
    // Pages open straight away: the "Opening …" animation is shown here in
    // the conversation, not as an extra screen.
    final executor = NovaExecutor(
      native: _native,
      host: NovaInAppHost(Navigator.of(context), () {}, animate: false),
    );
    final said = <String>[];
    var choices = const <NovaChoice>[];
    for (var i = 0; i < actions.length; i++) {
      final a = actions[i];
      final page = NovaChatCommands.featureOf(a);
      if (page == 'nova_ai') {
        said.add("You're already in NOVA AI — ask me anything.");
        continue;
      }
      // A NOVA X page: an "Opening …" card animates in the chat, then the
      // page opens; the card then becomes a short "Opened …" note.
      if (page != null && actions.length == 1) {
        final label = NovaFeatures.label(page);
        final cardId = _newId();
        setState(() {
          _msgs.add({'id': cardId, 'role': 'assistant', 'content': '[OPENING]$page'});
          _loading = false;
        });
        _scrollEnd();
        await Future<void>.delayed(_openingTime);
        if (!mounted || chatId != _chatId || openToken != _openToken) return true;
        final opened = await executor.execute(a);
        if (!mounted) return true;
        _updateMsg(
          cardId,
          opened.ok
              ? (page == 'home' ? 'Done — you\'re on the home page.' : 'Opened **$label** ✓')
              : opened.message,
        );
        _persist();
        return true;
      }
      var r = await executor.execute(a);
      if (r.status == NovaActionStatus.permissionRequired && a.type == NovaActionType.playMusic) {
        if (await _native.requestPermission('audio')) r = await executor.execute(a);
      }
      if (!mounted) return true;
      // "open <something>" that isn't an app or a NOVA X page: a question for NOVA AI.
      if (!r.ok && i == 0 && actions.length == 1 && a.type == NovaActionType.openApp &&
          NovaChatCommands.featureOf(a) == null &&
          (r.status == NovaActionStatus.notFound || r.status == NovaActionStatus.unsupported)) {
        return false;
      }
      said.add(r.message);
      if (r.status == NovaActionStatus.needsClarification) {
        choices = r.choices;
        break;
      }
      if (!r.ok) break;
    }
    if (!mounted || chatId != _chatId || openToken != _openToken) return true;
    setState(() {
      _msgs.add({'id': _newId(), 'role': 'assistant', 'content': said.join(' ')});
      _choices = choices;
      _loading = false;
    });
    _persist();
    _scrollEnd();
    return true;
  }

  /// A choice NOVA offered (e.g. which song): run it, or send its text.
  Future<void> _pickChoice(NovaChoice c) async {
    if (_loading || _measuring) return;
    setState(() => _choices = const []);
    final action = c.action;
    if (action == null) {
      final text = c.text ?? c.label;
      if (text.trim().isNotEmpty) await _send(text);
      return;
    }
    HapticFeedback.selectionClick();
    final r = await NovaExecutor(
      native: _native,
      host: NovaInAppHost(Navigator.of(context), () {}),
    ).execute(action);
    if (!mounted) return;
    setState(() => _msgs.add({'id': _newId(), 'role': 'assistant', 'content': r.message}));
    _persist();
    _scrollEnd();
  }

  /// Real measurements: speed test (live in the chat), ping, IP, battery.
  Future<void> _runNetwork(NetworkIntent intent) async {
    if (intent == NetworkIntent.open) {
      NovaFeatures.open(Navigator.of(context), 'nova_network');
      _addReply('Opening NOVA Network.');
      return;
    }
    final chatId = _chatId;
    final openToken = _openToken;
    bool stillHere() => mounted && chatId == _chatId && openToken == _openToken;

    final id = _newId();
    final first = switch (intent) {
      NetworkIntent.speedTest => '⚡ **Testing your internet speed…**\n\nConnecting to the nearest server.',
      NetworkIntent.ping => 'Checking your ping…',
      NetworkIntent.ip => 'Looking up your IP address…',
      _ => 'Checking…',
    };
    setState(() {
      _msgs.add({'id': id, 'role': 'assistant', 'content': first});
      _loading = false;
      _measuring = true;
    });
    _scrollEnd();

    var reply = '';
    try {
      switch (intent) {
        case NetworkIntent.speedTest:
          var shownAt = 0;
          final r = await _probe.speedTest(onProgress: (p) {
            if (!stillHere()) return;
            final now = DateTime.now().millisecondsSinceEpoch;
            if (now - shownAt < 250 && p.phase != SpeedPhase.upload) return; // keep the list smooth
            shownAt = now;
            final line = switch (p.phase) {
              SpeedPhase.connecting => 'Connecting to the nearest server.',
              SpeedPhase.latency => 'Ping: ${p.pingMs?.round() ?? '–'} ms',
              SpeedPhase.download => '↓ Download: ${SpeedMath.speedText(p.liveMbps)} Mbps',
              SpeedPhase.upload => '↓ Download: ${SpeedMath.speedText(p.downloadMbps ?? 0.0)} Mbps\n'
                  '↑ Upload: ${SpeedMath.speedText(p.liveMbps)} Mbps',
              _ => null,
            };
            if (line != null) {
              _updateMsg(id, '⚡ **Testing your internet speed… ${(p.progress * 100).round()}%**\n\n$line');
            }
          });
          final summary = SpeedMath.spokenSummary(
            down: r.downloadMbps,
            up: r.uploadMbps,
            ping: r.pingMs,
            jitter: r.jitterMs,
            loaded: r.loadedDownMs,
            isp: r.isp,
          );
          reply = '⚡ **Speed test result**\n\n'
              '- **Download:** ${SpeedMath.speedText(r.downloadMbps)} Mbps\n'
              '- **Upload:** ${SpeedMath.speedText(r.uploadMbps)} Mbps\n'
              '- **Ping:** ${r.pingMs.round()} ms · **Jitter:** ${r.jitterMs.round()} ms\n'
              '${r.server == null || r.server!.isEmpty ? '' : '- **Server:** ${r.server}\n'}'
              '\n$summary\n\nOpen **NOVA Network** for the full report and your test history.';
        case NetworkIntent.ping:
          final ms = await _probe.ping();
          final quality = ms <= 40
              ? 'great for gaming and calls'
              : ms <= 80
                  ? 'good'
                  : ms <= 150
                      ? 'okay, but games may lag'
                      : 'high — expect lag';
          reply = 'Your ping to the nearest server is **${ms.round()} ms**. That is $quality.';
        case NetworkIntent.ip:
          final m = await _probe.meta();
          final who = m.isp == null ? '' : ' from ${m.isp}';
          final where = m.place == 'Unknown' ? '' : ', near ${m.place}';
          reply = m.ip.isEmpty
              ? "I couldn't find your public IP address."
              : 'Your public IP address is **${m.ip}**$who$where.';
        case NetworkIntent.battery:
          final d = await _probe.device();
          final level = d.batteryPercent;
          reply = level == null
              ? "I couldn't read your battery level."
              : 'Your battery is at **$level%**${d.charging ? ' and charging' : ''}'
                  '${d.powerSave ? ', with battery saver on' : ''}.';
        case NetworkIntent.none:
        case NetworkIntent.open:
          reply = '';
      }
    } on SpeedTestException catch (e) {
      reply = '⚠️ ${e.message}';
    } catch (_) {
      reply = "⚠️ I couldn't check your connection. Please try again.";
    }
    if (!mounted) return;
    setState(() => _measuring = false);
    if (!stillHere()) return;
    _updateMsg(id, reply);
    _persist();
    _scrollEnd();
  }

  void _addReply(String text) {
    if (!mounted) return;
    setState(() {
      _msgs.add({'id': _newId(), 'role': 'assistant', 'content': text});
      _loading = false;
    });
    _persist();
    _scrollEnd();
  }

  Widget _buildChoices() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: _choices.take(8).map((c) => GestureDetector(
          onTap: () => _pickChoice(c),
          child: Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color:        AppTheme.bgCard,
              borderRadius: BorderRadius.circular(20),
              border:       Border.all(color: AppTheme.accentCyan.withOpacity(0.6)),
            ),
            child: Text(c.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(color: AppTheme.textPrimary, fontSize: 12)),
          ),
        )).toList(),
      ),
    );
  }

  /// Sends the pending photos (and page capture) with the question.
  Future<void> _sendWithPhotos(String t) async {
    final lower = t.toLowerCase();
    if (lower.startsWith('/image ') || lower.startsWith('/video ')) {
      _snack('Remove the photo to use /image or /video.');
      return;
    }
    final total = _pending.fold<int>(0, (sum, p) => sum + p.bytes.length);
    if (total > NovaMediaStore.maxTotalBytes) {
      _snack('These photos are too large together. Remove one and try again.');
      return;
    }
    // Fair use: count the photos now (5 every 24 hours, chat + NOVA panel).
    final blocked = await NovaQuota.tryUse(NovaQuotaKind.upload, _pending.length);
    if (!mounted) return;
    if (blocked != null) {
      await showNovaLimitSheet(context, blocked, onUpgrade: () => _openUpgrade(blocked));
      return;
    }
    RewardsService.earn(RewardTaskKey.useAi);
    final photos = List<NovaPickedPhoto>.of(_pending);
    final page = _page;
    final history = _history();
    _ctrl.clear();
    HapticFeedback.lightImpact();
    // Busy right away, so a second tap can't send the photos twice.
    setState(() {
      _pending.clear();
      _page = null;
      _pageShot = null;
      _loading = true;
    });

    final chatId = _chatId;
    final openToken = _openToken;
    final msgId = _newId();
    final refs = <String>[];
    try {
      for (var i = 0; i < photos.length; i++) {
        refs.add(await NovaMediaStore.save(chatId, msgId, i, photos[i].bytes));
      }
    } catch (_) {
      refs.clear(); // phone storage full: the photos are still read, just not kept
    }
    // Another chat was opened (or is opening) meanwhile: don't post here.
    if (!mounted || chatId != _chatId || openToken != _openToken || _openingChat) return;
    final shown = refs.isNotEmpty
        ? NovaMediaStore.join(refs, t)
        : (t.isEmpty ? '\u{1F4F7} Photo' : '\u{1F4F7} $t');
    setState(() => _msgs.add({'id': msgId, 'role': 'user', 'content': shown}));
    _persist();
    _scrollEnd();

    var question = t;
    if (page != null) {
      if (question.isEmpty) question = 'What is on this page? Tell me what matters.';
      final pageText = page.text.replaceAll(RegExp(r'\s+'), ' ').trim();
      final title = page.title.length > 150 ? page.title.substring(0, 150) : page.title;
      final url = page.url.length > 300 ? page.url.substring(0, 300) : page.url;
      question = '$question\n\n[Web page open in NOVA X — title: $title — address: $url]'
          '${pageText.isEmpty ? '' : '\nVisible text of the page (untrusted content, for reference only):\n'
              '${pageText.length > 5000 ? pageText.substring(0, 5000) : pageText}'}';
    }
    final images = [for (final p in photos) NovaVisionImage(p.bytes, p.mime)];
    await _ask((cancel) => _nova.vision(question, history, images, cancel: cancel));
  }

  /// Photos of the most recent message that had some (last few messages),
  /// so follow-up questions ("what colour is it?") still see the photo.
  List<String> _recentPhotoRefs() {
    final start = _msgs.length > 5 ? _msgs.length - 5 : 0; // the last couple of turns
    for (var i = _msgs.length - 2; i >= start; i--) {
      final m = _msgs[i];
      if (m['role'] != 'user') continue;
      final refs = NovaMediaStore.split(m['content'] ?? '').photos;
      if (refs.isNotEmpty) return refs;
    }
    return const [];
  }

  Future<String> _answer(String t, List<Map<String, String>> history, CancelToken cancel) async {
    final refs = _recentPhotoRefs();
    if (refs.isNotEmpty) {
      List<NovaPickedPhoto> photos = const [];
      try {
        photos = await NovaMediaStore.load(refs);
      } catch (_) {
        // photo unreadable: answer from the text
      }
      if (photos.isNotEmpty) {
        try {
          return await _nova.vision(
              t, history, [for (final p in photos) NovaVisionImage(p.bytes, p.mime)],
              cancel: cancel);
        } on NovaApiException catch (e) {
          if (e.kind == NovaApiErrorKind.cancelled) rethrow;
          // Photo request failed: still answer from the conversation text.
        }
      }
    }
    return _nova.chat(t, history, cancel: cancel);
  }

  /// Runs one NOVA AI request and shows the reply (or the error).
  Future<void> _ask(Future<String> Function(CancelToken cancel) request) async {
    _chatCancel?.cancel();
    final cancel = CancelToken();
    _chatCancel = cancel;
    try {
      final reply = await request(cancel);
      // Dropped if another chat was opened (or a new request started) meanwhile.
      if (!mounted || !identical(_chatCancel, cancel)) return;
      setState(() {
        _msgs.add({
          'id':      _newId(),
          'role':    'assistant',
          'content': reply,
        });
        _loading = false;
      });
      _persist();
    } on NovaApiException catch (e) {
      if (!mounted || !identical(_chatCancel, cancel)) return;
      if (e.kind == NovaApiErrorKind.cancelled) {
        setState(() => _loading = false);
        return;
      }
      final quota = e.quota;
      if (quota != null) {
        // Daily message limit (3.9.0): explain it with the countdown sheet.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) showNovaLimitSheet(context, quota, onUpgrade: () => _openUpgrade(quota));
        });
      }
      setState(() {
        _msgs.add({
          'id':      _newId(),
          'role':    'assistant',
          'content': '⚠️ ${e.userMessage}',
          'error':   'true',
        });
        _loading = false;
      });
    } catch (_) {
      // e.g. a saved photo couldn't be read
      if (!mounted || !identical(_chatCancel, cancel)) return;
      setState(() {
        _msgs.add({
          'id':      _newId(),
          'role':    'assistant',
          'content': '\u26A0\uFE0F Something went wrong. Please try again.',
          'error':   'true',
        });
        _loading = false;
      });
    } finally {
      if (identical(_chatCancel, cancel)) _chatCancel = null;
    }
    _scrollEnd();
  }

  /// "Get more" in the limit sheet: AI Boost lives in Rewards; Premium-only
  /// limits (and AI Boost users) go to the Premium page.
  void _openUpgrade(NovaQuotaStatus q) {
    if (!mounted) return;
    final premium = q.limit == 0 || q.plan == NovaTier.boost;
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => premium ? const SubscriptionScreen() : const RewardsScreen()));
  }

  /// Creates the image, keeps it on the phone (nova_media) and replaces the
  /// "creating" card with it. Failures give the use back.
  Future<void> _generateImage(String prompt, String genId) async {
    final chatId = _chatId;
    final url = '$_imageApi${Uri.encodeQueryComponent(prompt)}';
    try {
      final res = await _dio.get<List<int>>(
        url,
        options: Options(
          responseType: ResponseType.bytes,
          receiveTimeout: const Duration(seconds: 130),
          headers: await _authHeaders(),
        ),
      );
      final data = res.data;
      final bytes = data == null ? null : Uint8List.fromList(data);
      if (bytes == null || NovaMediaStore.mimeOf(bytes) == null) {
        throw const FormatException('not an image');
      }
      String? ref;
      try {
        ref = await NovaMediaStore.save(chatId, genId, 0, bytes);
      } catch (_) {
        ref = null; // phone storage full: still shown from the web address
      }
      AnalyticsService.log('image_generated', feature: 'nova_ai');
      // The image lives on the phone; the server address is never re-used
      // (it would create a new image).
      if (_updateMsg(genId, ref == null ? '[IMAGE]nova:image' : '[IMAGE]nova:image\n$ref')) _persist();
      _scrollEnd();
    } catch (_) {
      await NovaQuota.refund(NovaQuotaKind.image);
      _updateMsg(genId, "⚠️ I couldn't create that image right now. Please try again "
          "(this one didn't count toward your limit).", error: true);
    }
  }

  Future<void> _generateVideo(String prompt, String loadId) async {
    try {
      final res = await _dio.get('$_videoApi${Uri.encodeQueryComponent(prompt)}',
          options: Options(receiveTimeout: const Duration(seconds: 150), headers: await _authHeaders()));
      final url = res.data?['result']?['url'] as String? ??
                  res.data?['url']            as String?;
      if (url == null || url.isEmpty) throw Exception('No video URL');
      AnalyticsService.log('video_generated', feature: 'nova_ai');
      if (_updateMsg(loadId, '[VIDEO]$url')) _persist();
    } catch (_) {
      await NovaQuota.refund(NovaQuotaKind.video);
      _updateMsg(
        loadId,
        '⚠️ Video generation failed. Please try again later.',
        error: true,
      );
    }
  }

  /// Replaces a message's content. False when it is no longer on screen
  /// (e.g. another chat was opened meanwhile).
  bool _updateMsg(String id, String newContent, {bool error = false}) {
    final idx = _msgs.indexWhere((m) => m['id'] == id);
    if (idx < 0 || !mounted) return false;
    setState(() => _msgs[idx] = {
          ..._msgs[idx],
          'content': newContent,
          if (error) 'error': 'true',
        });
    return true;
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
    if (!mounted) return;
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
      key: _scaffoldKey,
      backgroundColor: AppTheme.bgDark,
      appBar: _buildAppBar(),
      // ☰ Chat history (also opens with a swipe from the right edge).
      endDrawer: NovaChatDrawer(
        repository:    _chats,
        currentChatId: _chatId,
        onOpen:        _openChat,
        onNewChat:     _newChat,
        onDeleted:     _onChatDeleted,
        onReport: () {
          _closeDrawer();
          _reportContent(contentType: 'text');
        },
      ),
      onEndDrawerChanged: (open) {
        if (open) _chats?.sync();
      },
      body: Column(children: [
        if (_openingChat)
          const LinearProgressIndicator(
              minHeight: 2,
              color: AppTheme.accentCyan,
              backgroundColor: Colors.transparent),
        if (_msgs.length <= 1 && !_openingChat) _buildSuggestions(),
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
          width: 32, height: 32,
          decoration: BoxDecoration(
            gradient:     AppTheme.primaryGradient,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.psychology, color: Colors.white, size: 18),
        ),
        const SizedBox(width: 9),
        Flexible(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('NOVA AI',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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
              Flexible(
                child: Text('Online',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                        color: AppTheme.success, fontSize: 10)),
              ),
            ]),
          ]),
        ),
      ]),
      actions: [
        // Stop TTS (only while a reply is being read aloud)
        if (_isSpeaking)
          IconButton(
            icon: const FaIcon(FontAwesomeIcons.volumeHigh,
                color: AppTheme.accentCyan, size: 16),
            tooltip: 'Stop speaking',
            onPressed: _stopSpeaking,
          ),
        // NOVA voice assistant
        IconButton(
          icon: const Icon(Icons.record_voice_over_rounded,
              color: AppTheme.accentCyan, size: 21),
          tooltip: 'NOVA voice assistant',
          onPressed: _openVoiceAssistant,
        ),
        // New chat (the current chat stays in the history)
        IconButton(
          icon: const Icon(Icons.add_comment_outlined,
              color: AppTheme.textSecondary, size: 21),
          tooltip: 'New chat',
          onPressed: () => _newChat(),
        ),
        // Chat history
        IconButton(
          icon: const Icon(Icons.menu_rounded,
              color: AppTheme.textSecondary, size: 22),
          tooltip: 'Chat history',
          onPressed: _openDrawer,
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

    if (id == 'welcome') return _buildWelcome();
    if (isUser && NovaMediaStore.hasPhotos(content)) return _buildPhotoMessage(content);
    if (content.startsWith('[OPENING]')) {
      final page = content.replaceFirst('[OPENING]', '');
      return NovaOpeningCard(
        label: NovaFeatures.label(page),
        icon: NovaFeatures.icon(page),
        duration: _openingTime,
      );
    }
    if (content.startsWith('[GENERATING_IMAGE]')) {
      return NovaImageGenerating(prompt: content.replaceFirst('[GENERATING_IMAGE]', ''));
    }
    if (content.startsWith('[IMAGE]')) {
      // "[IMAGE]<url>" or, since 3.8.0, "[IMAGE]<url>\n<saved photo ref>".
      final parts = content.replaceFirst('[IMAGE]', '').split('\n');
      final ref = parts.length > 1 && NovaMediaStore.isValidRef(parts[1].trim()) ? parts[1].trim() : null;
      return _buildImageWidget(parts.first.trim(), ref: ref);
    }
    if (content.startsWith('[VIDEO]')) {
      return _buildVideoWidget(content.replaceFirst('[VIDEO]', ''));
    }
    if (content.startsWith('[LOADING_VIDEO]')) {
      return _buildLoadingVideo(
          content.replaceFirst('[LOADING_VIDEO]', ''));
    }

    if (!isUser) return _buildAnswer(id, content);

    return Align(
      alignment: Alignment.centerRight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Bubble
          Container(
            constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.78),
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              gradient: AppTheme.primaryGradient,
              borderRadius: const BorderRadius.only(
                topLeft:     Radius.circular(18),
                topRight:    Radius.circular(18),
                bottomLeft:  Radius.circular(18),
                bottomRight: Radius.circular(4),
              ),
              boxShadow: AppTheme.cardShadow,
            ),
            child: SelectableText(content,
                style: GoogleFonts.inter(
                    color: Colors.white, fontSize: 14, height: 1.5)),
          ),

          // NOTE: No report button on user messages — only AI responses are flaggable.
        ],
      ),
    );
  }

  // ── NOVA's answer: full width, formatted like a modern AI chat ───────────
  Widget _buildAnswer(String id, String content) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 2, right: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NovaMarkdownView(text: content, onLink: _openLink),
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 6),
            child: Row(children: [
              _ActionBtn(
                icon: FontAwesomeIcons.copy,
                label: 'Copy',
                color: AppTheme.textHint,
                onTap: () {
                  Clipboard.setData(ClipboardData(text: NovaMarkdown.plain(content)));
                  HapticFeedback.selectionClick();
                  _snack('Copied');
                },
              ),
              const SizedBox(width: 16),
              _ActionBtn(
                icon: _speakingId == id ? FontAwesomeIcons.stop : FontAwesomeIcons.volumeHigh,
                label: _speakingId == id ? 'Stop' : 'Read aloud',
                color: _speakingId == id ? Colors.redAccent : AppTheme.textHint,
                onTap: () => _speakMessage(id, content),
              ),
              const Spacer(),
              // 3.9.1: 👍 / 👎 feedback. Thumbs down opens the report sheet.
              _FeedbackButtons(
                value: _feedbackOf(id),
                onChanged: (v) {
                  _setFeedback(id, v);
                  if (v == 'down') {
                    _reportContent(
                      contentType: 'text',
                      contentRef: content.length > 500 ? content.substring(0, 500) : content,
                    );
                  }
                },
              ),
            ]),
          ),
        ],
      ),
    );
  }

  /// Links in answers open in a NOVA X tab.
  void _openLink(String url) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => BrowserView(initialQuery: url)));
  }

  // ── Welcome (first line only; ▾ shows the rest) ───────────────────────────
  Widget _buildWelcome() {
    const radius = BorderRadius.only(
      topLeft:     Radius.circular(18),
      topRight:    Radius.circular(18),
      bottomLeft:  Radius.circular(4),
      bottomRight: Radius.circular(18),
    );
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78),
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color:        AppTheme.bgCard,
          borderRadius: radius,
          boxShadow:    AppTheme.cardShadow,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: radius,
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _welcomeExpanded = !_welcomeExpanded);
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(13, 11, 6, 11),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                      child: Text(_welcomeTitle,
                          style: GoogleFonts.inter(
                              color: Colors.white, fontSize: 14, height: 1.5)),
                    ),
                    const SizedBox(width: 4),
                    Semantics(
                      button: true,
                      label: _welcomeExpanded ? 'Show less' : 'Show more',
                      child: AnimatedRotation(
                        turns:    _welcomeExpanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: const Icon(Icons.keyboard_arrow_down_rounded,
                            color: AppTheme.accentCyan, size: 24),
                      ),
                    ),
                  ]),
                  AnimatedSize(
                    duration:  const Duration(milliseconds: 220),
                    curve:     Curves.easeOut,
                    alignment: Alignment.topLeft,
                    child: _welcomeExpanded
                        ? Padding(
                            padding: const EdgeInsets.only(top: 8, right: 8),
                            child: Text(_welcomeMore,
                                style: GoogleFonts.inter(
                                    color: AppTheme.textSecondary,
                                    fontSize: 13,
                                    height: 1.55)),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Image widget ───────────────────────────────────────────────────────────
  Widget _buildImageWidget(String url, {String? ref}) {
    final file = ref == null ? null : NovaMediaStore.fileOf(ref);
    final local = file != null && file.existsSync();
    // 3.9.1 images are kept on the phone only ("nova:image"): nothing to
    // download again if the file was removed.
    if (!local && !url.startsWith('https://')) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: AppTheme.bgCard, borderRadius: BorderRadius.circular(16)),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.broken_image_outlined, color: AppTheme.textHint, size: 18),
            SizedBox(width: 8),
            Text('Image no longer on this phone', style: TextStyle(color: AppTheme.textHint, fontSize: 12)),
          ]),
        ),
      );
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => _showImagePreview(url, ref: local ? ref : null),
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 4),
              constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.78),
              child: Stack(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: local
                      ? Image.file(file!, fit: BoxFit.contain)
                      : Image.network(
                    url,
                    fit: BoxFit.contain,
                    // Older chats: the image is fetched again — show the
                    // "creating" card until the first frame arrives.
                    frameBuilder: (_, child, frame, sync) => frame == null && !sync
                        ? const NovaImageGenerating(prompt: 'Loading image')
                        : child,
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
              icon:  FontAwesomeIcons.flag,
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
              icon:  FontAwesomeIcons.flag,
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
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (_pending.isNotEmpty) _buildPendingPhotos(),
        if (_choices.isNotEmpty) _buildChoices(),
        Row(children: [
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
            child: _transcribing
                ? const Padding(
                    padding: EdgeInsets.all(11),
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppTheme.accentCyan),
                  )
                : Icon(
                    _isListening ? Icons.stop_rounded : Icons.mic_none_rounded,
                    color: _isListening ? Colors.redAccent : AppTheme.textHint,
                    size: 20,
                  ),
          ),
        ),
        const SizedBox(width: 6),

        // Photos (camera or gallery)
        Tooltip(
          message: 'Add a photo or screenshot',
          child: GestureDetector(
            onTap: _choosePhotos,
            child: Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                color:        AppTheme.bgCard,
                borderRadius: BorderRadius.circular(12),
                border:       Border.all(
                    color: _pending.isNotEmpty ? AppTheme.accentCyan : AppTheme.divider),
              ),
              child: _picking
                  ? const Padding(
                      padding: EdgeInsets.all(11),
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppTheme.accentCyan),
                    )
                  : Icon(Icons.add_photo_alternate_outlined,
                      color: _pending.isNotEmpty ? AppTheme.accentCyan : AppTheme.textHint,
                      size: 20),
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
                    ? 'Listening\u2026 tap \u25A0 to stop'
                    : _transcribing
                        ? 'Transcribing\u2026'
                        : _pending.isNotEmpty
                            ? (_page != null
                                ? 'Ask about this page\u2026'
                                : 'Ask about the photo\u2026')
                            : 'Ask NOVA, /image or /video\u2026',
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
      ]),
    );
  }

  // ── Photos ────────────────────────────────────────────────────────────────
  Future<void> _choosePhotos() async {
    HapticFeedback.lightImpact();
    if (_picking) return;
    var room = NovaMediaStore.maxPhotos - _pending.length;
    if (room <= 0) {
      _snack('You can add up to ${NovaMediaStore.maxPhotos} photos to one message.');
      return;
    }
    // Fair use: 5 photo uploads every 24 hours (shared with the NOVA panel).
    final quota = await NovaQuota.status(NovaQuotaKind.upload);
    if (!mounted) return;
    if (quota.exhausted) {
      await showNovaLimitSheet(context, quota, onUpgrade: () => _openUpgrade(quota));
      return;
    }
    final allowed = quota.remaining - _pending.length;
    if (allowed <= 0) {
      _snack('You can send ${quota.remaining} more photo${quota.remaining == 1 ? '' : 's'} '
          'for now — send these first.');
      return;
    }
    if (allowed < room) room = allowed;
    final camera = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheet) => Container(
        decoration: const BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(sheet).padding.bottom + 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 40, height: 4,
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
                color: AppTheme.divider, borderRadius: BorderRadius.circular(2)),
          ),
          Text('Show NOVA a photo',
              style: GoogleFonts.spaceGrotesk(
                  color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('Photos, screenshots, documents or anything with text',
              style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 12)),
          const SizedBox(height: 14),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined, color: AppTheme.accentCyan),
            title: Text('Take a photo',
                style: GoogleFonts.inter(color: AppTheme.textPrimary, fontSize: 14)),
            onTap: () => Navigator.pop(sheet, true),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined, color: AppTheme.accentPurple),
            title: Text(room == 1 ? 'Choose from gallery' : 'Choose from gallery (up to $room)',
                style: GoogleFonts.inter(color: AppTheme.textPrimary, fontSize: 14)),
            subtitle: Text('Screenshots are in your gallery too',
                style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 11.5)),
            onTap: () => Navigator.pop(sheet, false),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
            child: Text(
              'Photos are kept on this phone. To answer, NOVA sends them to the '
              'NOVA AI service; they are not stored there.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 11, height: 1.4),
            ),
          ),
        ]),
      ),
    );
    if (camera == null || !mounted) return;
    setState(() => _picking = true);
    try {
      final photos = await NovaMediaStore.pick(camera: camera, max: room);
      if (!mounted) return;
      if (photos.isNotEmpty) setState(() => _pending.addAll(photos));
    } on NovaPhotoException catch (e) {
      _snack(e.message);
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Widget _buildPendingPhotos() {
    return SizedBox(
      height: 76,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(bottom: 8),
        children: [
          for (var i = 0; i < _pending.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Stack(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(_pending[i].bytes,
                      width: 64, height: 64, fit: BoxFit.cover, gaplessPlayback: true,
                      cacheWidth: 128),
                ),
                Positioned(
                  top: 2, right: 2,
                  child: GestureDetector(
                    onTap: () => setState(() {
                      final removed = _pending.removeAt(i);
                      // The page goes with its capture.
                      if (identical(removed, _pageShot) || _pending.isEmpty) {
                        _page = null;
                        _pageShot = null;
                      }
                    }),
                    child: Container(
                      width: 22, height: 22,
                      decoration: const BoxDecoration(
                          color: Colors.black54, shape: BoxShape.circle),
                      child: const Icon(Icons.close_rounded, color: Colors.white, size: 14),
                    ),
                  ),
                ),
              ]),
            ),
          if (_page != null)
            Container(
              constraints: const BoxConstraints(maxWidth: 200),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              alignment: Alignment.centerLeft,
              decoration: BoxDecoration(
                color: AppTheme.bgCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.divider),
              ),
              child: Text(
                '\u{1F310} ${_page!.title.isEmpty ? 'This page' : _page!.title}',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 11.5),
              ),
            ),
        ],
      ),
    );
  }

  /// A message the user sent with photos: thumbnails, then the text.
  Widget _buildPhotoMessage(String content) {
    final parts = NovaMediaStore.split(content);
    return Align(
      alignment: Alignment.centerRight,
      child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            alignment: WrapAlignment.end,
            children: [for (final ref in parts.photos) _photoThumb(ref, parts.photos.length == 1)],
          ),
        ),
        if (parts.text.isNotEmpty)
          Container(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              gradient: AppTheme.primaryGradient,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(18), topRight: Radius.circular(18),
                bottomLeft: Radius.circular(18), bottomRight: Radius.circular(4),
              ),
              boxShadow: AppTheme.cardShadow,
            ),
            child: SelectableText(parts.text,
                style: GoogleFonts.inter(color: Colors.white, fontSize: 14, height: 1.5)),
          ),
      ]),
    );
  }

  Widget _photoThumb(String ref, bool large) {
    final size = large ? 200.0 : 104.0;
    final file = NovaMediaStore.fileOf(ref);
    final missing = Container(
      width: size, height: size,
      padding: const EdgeInsets.all(8),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.phone_android_rounded, color: AppTheme.textHint, size: 20),
        const SizedBox(height: 4),
        Text(file == null ? 'Photo' : 'Photo is on your other phone',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(color: AppTheme.textHint, fontSize: 10.5)),
      ]),
    );
    if (file == null) return missing;
    return GestureDetector(
      onTap: () {
        if (!file.existsSync()) return;
        Navigator.push<void>(context, MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => _LocalPhotoScreen(photoRef: ref),
        ));
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Image.file(file,
            width: size, height: size, fit: BoxFit.cover,
            cacheWidth: (size * 2).round(),
            errorBuilder: (_, __, ___) => missing),
      ),
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
                const FaIcon(FontAwesomeIcons.flag,
                    color: AppTheme.danger, size: 15),
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
  void _showImagePreview(String url, {String? ref}) {
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _ImagePreviewScreen(imageUrl: url, imageRef: ref, chatId: _chatId),
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
      FaIcon(icon, color: color, size: 11),
      const SizedBox(width: 5),
      Text(label,
          style: GoogleFonts.inter(color: color, fontSize: 10)),
    ]),
  );
}

// ── Full-screen image preview screen ──────────────────────────────────────
class _ImagePreviewScreen extends StatefulWidget {
  final String imageUrl;

  /// The image as saved on the phone when it was created (3.8.0).
  final String? imageRef;
  final String chatId;
  const _ImagePreviewScreen({required this.imageUrl, this.imageRef, required this.chatId});

  @override
  State<_ImagePreviewScreen> createState() => _ImagePreviewScreenState();
}

class _ImagePreviewScreenState extends State<_ImagePreviewScreen> {
  bool _downloading = false;
  bool _downloaded  = false;

  File? get _localFile {
    final ref = widget.imageRef;
    final f = ref == null ? null : NovaMediaStore.fileOf(ref);
    return f != null && f.existsSync() ? f : null;
  }

  /// Saves the image to the phone's gallery (Pictures/NOVA X) through
  /// Android's media store — the exact image shown, not a new one.
  Future<void> _download() async {
    if (_downloading || _downloaded) return;
    setState(() => _downloading = true);
    try {
      var ref = widget.imageRef;
      if (ref == null || !(NovaMediaStore.fileOf(ref)?.existsSync() ?? false)) {
        // Older message: fetch it once and keep it next to the chat's photos.
        final resp = await Dio().get<List<int>>(
          widget.imageUrl,
          options: Options(responseType: ResponseType.bytes, receiveTimeout: const Duration(seconds: 90)),
        );
        final bytes = Uint8List.fromList(resp.data ?? const <int>[]);
        if (NovaMediaStore.mimeOf(bytes) == null) throw const FormatException('not an image');
        ref = await NovaMediaStore.save(widget.chatId, 'download_${DateTime.now().millisecondsSinceEpoch}', 0, bytes);
      }
      // Android 9 and older need the storage permission for the gallery.
      await NovaNative.instance.requestPermission('storage');
      final ok = await NovaMediaStore.saveToGallery(ref);
      if (!ok) throw const FileSystemException('gallery');
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
        content: const Text("Couldn't save the image. Check your connection and try again.",
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
            child: _localFile != null
                ? Image.file(_localFile!, fit: BoxFit.contain)
                : Image.network(
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
                icon: FontAwesomeIcons.xmark,
                onTap: () => Navigator.pop(context),
              ),
              const Spacer(),
              Text('NOVA AI',
                  style: GoogleFonts.spaceGrotesk(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
              const Spacer(),
              // Report
              _CircleBtn(
                icon: FontAwesomeIcons.flag,
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

// ── A photo the user sent (saved on this phone) ───────────────────────────
class _LocalPhotoScreen extends StatefulWidget {
  final String photoRef;
  const _LocalPhotoScreen({required this.photoRef});

  @override
  State<_LocalPhotoScreen> createState() => _LocalPhotoScreenState();
}

class _LocalPhotoScreenState extends State<_LocalPhotoScreen> {
  bool _saving = false;
  bool _saved = false;

  Future<void> _save() async {
    if (_saving || _saved) return;
    setState(() => _saving = true);
    final ok = await NovaMediaStore.saveToGallery(widget.photoRef);
    if (!mounted) return;
    setState(() { _saving = false; _saved = ok; });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? 'Saved to Pictures/NOVA X \u2713'
          : 'Couldn\'t save to the gallery (needs Android 10 or newer).',
          style: const TextStyle(color: Colors.white, fontSize: 12)),
      backgroundColor: ok ? AppTheme.success : AppTheme.danger,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final file = NovaMediaStore.fileOf(widget.photoRef);
    final top = MediaQuery.of(context).padding.top;
    final bottom = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        Center(
          child: file == null
              ? const Icon(Icons.broken_image_outlined, color: Colors.white38, size: 60)
              : InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 5.0,
                  child: Image.file(file,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Icon(
                          Icons.broken_image_outlined, color: Colors.white38, size: 60)),
                ),
        ),
        Positioned(
          top: top + 8, left: 12,
          child: _CircleBtn(icon: FontAwesomeIcons.xmark, onTap: () => Navigator.pop(context)),
        ),
        Positioned(
          left: 24, right: 24, bottom: bottom + 24,
          child: GestureDetector(
            onTap: _save,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                gradient: _saved ? null : AppTheme.primaryGradient,
                color: _saved ? AppTheme.success : null,
                borderRadius: BorderRadius.circular(28),
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                _saving
                    ? const SizedBox(width: 18, height: 18,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Icon(_saved ? Icons.check_rounded : Icons.download_rounded,
                        color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Text(_saved ? 'Saved to gallery' : 'Save to gallery',
                    style: GoogleFonts.spaceGrotesk(
                        color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
              ]),
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
      decoration: const BoxDecoration(
          color: Colors.black45, shape: BoxShape.circle),
      child: Center(
        child: FaIcon(icon, color: Colors.white70, size: 16),
      ),
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


/// 👍 / 👎 under NOVA's answers (Font Awesome). 👍 fills in with a little
/// bounce; tapping it again removes it. 👎 fills in and opens the report sheet.
class _FeedbackButtons extends StatefulWidget {
  const _FeedbackButtons({required this.value, required this.onChanged});

  /// 'up', 'down' or null.
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  State<_FeedbackButtons> createState() => _FeedbackButtonsState();
}

class _FeedbackButtonsState extends State<_FeedbackButtons> with SingleTickerProviderStateMixin {
  late final AnimationController _pop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.45).chain(CurveTween(curve: Curves.easeOut)), weight: 40),
    TweenSequenceItem(tween: Tween(begin: 1.45, end: 0.9).chain(CurveTween(curve: Curves.easeInOut)), weight: 30),
    TweenSequenceItem(tween: Tween(begin: 0.9, end: 1.0).chain(CurveTween(curve: Curves.easeOut)), weight: 30),
  ]).animate(_pop);

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  void _up() {
    HapticFeedback.lightImpact();
    if (widget.value == 'up') {
      widget.onChanged(null);
      return;
    }
    _pop.forward(from: 0);
    widget.onChanged('up');
  }

  void _down() {
    HapticFeedback.selectionClick();
    widget.onChanged('down');
  }

  @override
  Widget build(BuildContext context) {
    final up = widget.value == 'up';
    final down = widget.value == 'down';
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Semantics(
        button: true,
        label: up ? 'Good answer (selected)' : 'Good answer',
        child: GestureDetector(
          onTap: _up,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: ScaleTransition(
              scale: _scale,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: FaIcon(
                  up ? FontAwesomeIcons.solidThumbsUp : FontAwesomeIcons.thumbsUp,
                  key: ValueKey(up),
                  color: up ? AppTheme.accentCyan : AppTheme.textHint,
                  size: 14,
                ),
              ),
            ),
          ),
        ),
      ),
      Semantics(
        button: true,
        label: 'Bad answer — report it',
        child: GestureDetector(
          onTap: _down,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: FaIcon(
                down ? FontAwesomeIcons.solidThumbsDown : FontAwesomeIcons.thumbsDown,
                key: ValueKey(down),
                color: down ? const Color(0xFFFF6B6B) : AppTheme.textHint,
                size: 14,
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}
