// lib/features/nova/nova_overlay.dart
//
// The floating NOVA assistant shown over other apps when the user invokes
// the system digital assistant (long-press Home / hold power / assistant
// gesture) with NOVA X selected as "Digital assistant app".
//
// Runs in its own Flutter engine (entrypoint `novaAssistantMain` in
// main.dart, hosted by NovaAssistActivity on a transparent window).
//
// 3.4.0: 📷 adds photos / screenshots from the camera or gallery, and
// "Read my screen" lets NOVA see the app in front: ONE screenshot, only after
// the user agrees in Android's screen-capture dialog (never over the lock
// screen). The panel hides itself for that moment so NOVA sees the app, not
// the panel. Photos and screenshots here stay in memory only.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/database/local_db.dart';
import '../../core/theme/app_theme.dart';
import '../ai/services/nova_media_store.dart';
import '../ai/widgets/nova_limit_sheet.dart';
import 'controller/nova_controller.dart';
import 'models/nova_models.dart';
import 'services/nova_api.dart';
import 'services/nova_executor.dart';
import 'services/nova_native.dart';
import 'services/nova_prefs.dart';
import 'services/nova_screen.dart';
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

  /// Opens a NOVA X page: Android brings NOVA X to the front and the home
  /// screen opens the page (see MainActivity.EXTRA_FEATURE).
  @override
  Future<bool> openFeature(String featureId) async {
    if (!RegExp(r'^[a-z_]{1,30}$').hasMatch(featureId)) return false;
    final r = await _native.runAction('open_feature', {'feature': featureId});
    return r.status == 'success';
  }

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
  final NovaCloudVoice _voice = NovaCloudVoice(native: NovaNative.instance);
  late final NovaController _controller = NovaController(
    api: _api,
    native: NovaNative.instance,
    host: NovaOverlayHost(NovaNative.instance),
    settings: widget.settings,
    searchUrl: LocalDB.buildSearchUrl,
    voice: _voice,
  );
  StreamSubscription<NovaNativeEvent>? _invocations;

  /// True while the screenshot is taken (the panel is invisible).
  bool _hidden = false;
  bool _busyMedia = false;

  @override
  void initState() {
    super.initState();
    _invocations = NovaNative.instance.events.listen((e) {
      if (e is NovaAssistInvokedEvent) _activate(e.reason);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final reason = await NovaWake.launchReason();
      if (mounted && reason != null) _activate(reason);
    });
  }

  /// Each opening of the window (also on a reused, warm engine).
  int _openings = 0;

  /// After "Hey NOVA" the user usually keeps talking ("Hey NOVA, open
  /// YouTube"), so NOVA listens straight away instead of greeting first.
  void _activate(String reason) {
    if (mounted) setState(() => _openings++); // replays the slide-in
    _controller.activate(greet: reason == 'wake' ? false : null);
    // The engine may have been started long ago: pick up settings changed
    // in the app since (voice, speak replies, greeting).
    NovaPrefs.load().then((s) {
      if (mounted) _controller.updateSettings(s);
    }).catchError((Object _) {});
  }

  void _close() {
    _controller.cancel();
    NovaScreen.cancel();
    NovaNative.instance.closeAssistant();
  }

  void _say(String text) => ScaffoldMessenger.maybeOf(context)
      ?.showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 3)));

  /// 📷 — camera or gallery (the panel stays open while picking).
  Future<void> _addPhoto() async {
    if (_busyMedia) return;
    if (await NovaScreen.phoneLocked()) {
      _say('Unlock your phone to add photos.');
      return;
    }
    if (!mounted) return;
    if (3 - _controller.pendingImages.length <= 0) {
      _say('You can add up to 3 photos.');
      return;
    }
    // Fair use: 5 photo uploads every 24 hours (shared with NOVA AI chat).
    final room = await novaPhotoRoom(context, 3 - _controller.pendingImages.length);
    if (room <= 0 || !mounted) return;
    final camera = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined, color: AppTheme.accentCyan),
            title: const Text('Take a photo', style: TextStyle(color: Colors.white)),
            onTap: () => Navigator.pop(ctx, true),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined, color: AppTheme.accentCyan),
            title: const Text('Photo or screenshot from gallery', style: TextStyle(color: Colors.white)),
            onTap: () => Navigator.pop(ctx, false),
          ),
        ]),
      ),
    );
    if (camera == null || !mounted) return;
    _busyMedia = true;
    await NovaScreen.keepAssistantOpen(true);
    try {
      final photos = await NovaMediaStore.pick(camera: camera, max: room);
      if (photos.isNotEmpty && mounted && await novaCountPhotos(context, photos.length)) {
        _controller.addImages([for (final p in photos) NovaVisionImage(p.bytes, p.mime)]);
      }
    } on NovaPhotoException catch (e) {
      _say(e.message);
    } finally {
      await NovaScreen.keepAssistantOpen(false);
      _busyMedia = false;
    }
  }

  /// "Read my screen": Android's consent dialog, then one screenshot.
  Future<void> _readScreen() async {
    if (_busyMedia) return;
    // Fair use: a screenshot counts as one photo upload.
    if (await novaPhotoRoom(context, 1) <= 0 || !mounted) return;
    _busyMedia = true;
    _controller.cancel();
    try {
      await NovaScreen.keepAssistantOpen(true);
      final consent = await NovaScreen.request();
      if (consent != NovaScreenStatus.granted) {
        if (consent != NovaScreenStatus.denied) _say(NovaScreen.messageFor(consent));
        return;
      }
      if (!mounted) {
        await NovaScreen.cancel();
        return;
      }
      // Hide the panel so the screenshot shows the app behind it.
      setState(() => _hidden = true);
      await WidgetsBinding.instance.endOfFrame;
      await Future<void>.delayed(const Duration(milliseconds: 250));
      final shot = await NovaScreen.grab();
      if (!mounted) return;
      setState(() => _hidden = false);
      final bytes = shot.bytes;
      if (shot.status == NovaScreenStatus.ok && bytes != null) {
        if (await novaCountPhotos(context, 1)) {
          _controller.addImages([NovaVisionImage(bytes, 'image/jpeg')], fromScreen: true);
        }
      } else {
        _say(NovaScreen.messageFor(shot.status));
      }
    } finally {
      await NovaScreen.keepAssistantOpen(false);
      _busyMedia = false;
      if (mounted && _hidden) setState(() => _hidden = false);
    }
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
      body: Visibility(
        visible: !_hidden,
        maintainState: true,
        maintainAnimation: true,
        maintainSize: true,
        child: Stack(
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
                key: ValueKey(_openings),
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
                  onAddPhoto: _addPhoto,
                  onReadScreen: _readScreen,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
