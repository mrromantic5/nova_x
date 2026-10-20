// lib/features/nova/nova_launcher.dart
//
// Opens NOVA inside NOVA X as a floating bottom sheet.
//   showNovaAssistant(context)                       — greet + listen
//   showNovaAssistant(context, summarise: page)      — summarise a page
//   showNovaAssistant(context, activate: false)      — open idle

import 'package:flutter/material.dart';

import '../../core/database/local_db.dart';
import '../ai/screens/ai_assistant_screen.dart';
import '../bookmarks/screens/bookmarks_screen.dart';
import '../browser/screens/browser_view.dart';
import '../downloads/screens/downloads_screen.dart';
import '../history/screens/history_screen.dart';
import '../map/screens/nova_map_screen.dart';
import '../music/screens/nova_music_screen.dart';
import '../rewards/screens/rewards_screen.dart';
import '../settings/screens/settings_screen.dart';
import '../shield/screens/nova_shield_screen.dart';
import 'controller/nova_controller.dart';
import 'models/nova_models.dart';
import 'screens/nova_settings_screen.dart';
import 'services/nova_api.dart';
import 'services/nova_executor.dart';
import 'services/nova_native.dart';
import 'services/nova_prefs.dart';
import 'services/nova_voice.dart';
import 'services/nova_wake.dart';
import 'widgets/nova_panel.dart';

bool _sheetOpen = false;

Future<void> showNovaAssistant(
  BuildContext context, {
  NovaPageContent? summarise,
  bool activate = true,
}) async {
  if (_sheetOpen) return; // never stack two assistants
  _sheetOpen = true;
  try {
    final navigator = Navigator.of(context);
    final settings = await NovaPrefs.load();
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.35),
      elevation: 0,
      builder: (_) => _NovaSheet(
        navigator: navigator,
        settings: settings,
        summarise: summarise,
        activate: activate,
      ),
    );
  } finally {
    _sheetOpen = false;
  }
}

/// Navigation for NOVA running inside NOVA X.
class NovaInAppHost implements NovaHost {
  NovaInAppHost(this._navigator, this._closeSheet);

  final NavigatorState _navigator;
  final VoidCallback _closeSheet;
  bool _closed = false;

  @override
  bool get isOverlay => false;

  @override
  bool get isClosed => _closed;

  @override
  Future<bool> openInBrowser(String url) async {
    close();
    _navigator.push(MaterialPageRoute(builder: (_) => BrowserView(initialQuery: url)));
    return true;
  }

  @override
  Future<bool> openFeature(String featureId) async {
    final Widget? screen = switch (featureId) {
      'bookmarks' => const BookmarksScreen(),
      'history' => const HistoryScreen(),
      'downloads' => const DownloadsScreen(),
      'shield' => const NovaShieldScreen(),
      'nova_map' => const NovaMapScreen(),
      'rewards' => const RewardsScreen(),
      'nova_ai' => const AiAssistantScreen(),
      'nova_settings' => const NovaSettingsScreen(),
      'browser_settings' => const SettingsScreen(),
      'nova_music' => const NovaMusicScreen(),
      _ => null,
    };
    if (screen == null) return false;
    close();
    _navigator.push(MaterialPageRoute(builder: (_) => screen));
    return true;
  }

  @override
  void close() {
    _closed = true;
    _closeSheet();
  }
}

class _NovaSheet extends StatefulWidget {
  const _NovaSheet({
    required this.navigator,
    required this.settings,
    this.summarise,
    required this.activate,
  });

  final NavigatorState navigator;
  final NovaSettings settings;
  final NovaPageContent? summarise;
  final bool activate;

  @override
  State<_NovaSheet> createState() => _NovaSheetState();
}

class _NovaSheetState extends State<_NovaSheet> {
  final NovaApiClient _api = NovaApiClient();
  final NovaCloudVoice _voice = NovaCloudVoice(native: NovaNative.instance);
  late final NovaController _controller = NovaController(
    api: _api,
    native: NovaNative.instance,
    host: NovaInAppHost(widget.navigator, _closeSheet),
    settings: widget.settings,
    searchUrl: LocalDB.buildSearchUrl,
    voice: _voice,
  );
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    // "Hey NOVA" pauses while this panel is open.
    NovaWake.hold('panel', true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final page = widget.summarise;
      if (page != null) {
        _controller.summarise(page);
      } else if (widget.activate) {
        _controller.activate();
      }
    });
  }

  void _closeSheet() {
    if (_closing || !mounted) return;
    _closing = true;
    final route = ModalRoute.of(context);
    if (route == null) return;
    if (route.isCurrent) {
      Navigator.of(context).pop();
    } else if (route.isActive) {
      Navigator.of(context).removeRoute(route);
    }
  }

  Future<void> _toggleVoice(bool on) async {
    final next = _controller.settings.copyWith(speakReplies: on);
    _controller.updateSettings(next);
    await NovaPrefs.save(next);
  }

  @override
  void dispose() {
    _controller.dispose();
    _voice.dispose();
    _api.dispose();
    NovaWake.hold('panel', false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return NovaPanel(
      controller: _controller,
      onToggleVoice: _toggleVoice,
      onClose: () {
        _controller.cancel();
        _closeSheet();
      },
      onExpand: () {
        _controller.cancel();
        _closeSheet();
        widget.navigator.push(MaterialPageRoute(builder: (_) => const AiAssistantScreen()));
      },
    );
  }
}
