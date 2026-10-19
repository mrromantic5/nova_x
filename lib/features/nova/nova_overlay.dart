// lib/features/nova/nova_overlay.dart
//
// The floating NOVA assistant shown over other apps when the user invokes
// the system digital assistant (long-press Home / hold power / assistant
// gesture) with NOVA X selected as "Digital assistant app".
//
// Runs in its own Flutter engine (entrypoint `novaAssistantMain` in
// main.dart, hosted by NovaAssistActivity on a transparent window).

import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/database/local_db.dart';
import '../../core/theme/app_theme.dart';
import 'controller/nova_controller.dart';
import 'models/nova_models.dart';
import 'services/nova_api.dart';
import 'services/nova_executor.dart';
import 'services/nova_native.dart';
import 'services/nova_prefs.dart';
import 'services/nova_voice.dart';
import 'services/nova_wake.dart';
import 'widgets/nova_panel.dart';

/// Navigation for the floating assistant: everything opens outside it.
class NovaOverlayHost implements NovaHost {
  NovaOverlayHost(this._native);

  final NovaNativeApi _native;
  bool _closed = false;

  @override
  bool get isOverlay => true;

  @override
  bool get isClosed => _closed;

  @override
  Future<bool> openInBrowser(String url) async {
    final r = await _native.runAction('open_in_nova', {'url': url});
    return r.status == 'success';
  }

  /// NOVA X screens can only be opened from inside the browser.
  @override
  Future<bool> openFeature(String featureId) async => false;

  @override
  void close() {
    _closed = true;
    _native.closeAssistant();
  }
}

class NovaAssistantApp extends StatelessWidget {
  const NovaAssistantApp({super.key, required this.settings});

  final NovaSettings settings;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NOVA',
      debugShowCheckedModeBanner: false,
      color: Colors.transparent,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.transparent,
        canvasColor: Colors.transparent,
        colorScheme: const ColorScheme.dark(
          primary: AppTheme.accentCyan,
          secondary: AppTheme.accentPurple,
          surface: AppTheme.bgCard,
        ),
      ),
      home: NovaOverlayScreen(settings: settings),
    );
  }
}

class NovaOverlayScreen extends StatefulWidget {
  const NovaOverlayScreen({super.key, required this.settings});

  final NovaSettings settings;

  @override
  State<NovaOverlayScreen> createState() => _NovaOverlayScreenState();
}

class _NovaOverlayScreenState extends State<NovaOverlayScreen> {
  final NovaApiClient _api = NovaApiClient();
  final NovaBrainsVoice _voice = NovaBrainsVoice(native: NovaNative.instance);
  late final NovaController _controller = NovaController(
    api: _api,
    native: NovaNative.instance,
    host: NovaOverlayHost(NovaNative.instance),
    settings: widget.settings,
    searchUrl: LocalDB.buildSearchUrl,
    voice: _voice,
  );
  StreamSubscription<NovaNativeEvent>? _invocations;

  @override
  void initState() {
    super.initState();
    _invocations = NovaNative.instance.events.listen((e) {
      if (e is NovaAssistInvokedEvent) _activate(e.reason);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final reason = await NovaWake.launchReason();
      if (mounted) _activate(reason);
    });
  }

  /// After "Hey NOVA" the user usually keeps talking ("Hey NOVA, open
  /// YouTube"), so NOVA listens straight away instead of greeting first.
  void _activate(String reason) {
    _controller.activate(greet: reason == 'wake' ? false : null);
  }

  void _close() {
    _controller.cancel();
    NovaNative.instance.closeAssistant();
  }

  Future<void> _toggleVoice(bool on) async {
    final next = _controller.settings.copyWith(speakReplies: on);
    _controller.updateSettings(next);
    await NovaPrefs.save(next);
  }

  @override
  void dispose() {
    _invocations?.cancel();
    _controller.dispose();
    _voice.dispose();
    _api.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _close,
              child: const ColoredBox(color: Color(0x47000000)),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOutCubic,
              builder: (context, v, child) => Opacity(
                opacity: v,
                child: Transform.translate(offset: Offset(0, (1 - v) * 60), child: child),
              ),
              child: NovaPanel(
                controller: _controller,
                onClose: _close,
                onToggleVoice: _toggleVoice,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
