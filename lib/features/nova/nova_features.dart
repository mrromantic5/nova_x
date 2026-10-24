// lib/features/nova/nova_features.dart
//
// Every NOVA X page NOVA can open by voice or from the NOVA AI chat, in one
// place. The ids are the values of NovaActionValidator.inAppFeatures; the
// Android overlay hands the same ids over (validated) through NovaBridge.

import 'package:flutter/material.dart';

import '../../core/database/local_db.dart';
import '../ai/screens/ai_assistant_screen.dart';
import '../bookmarks/screens/bookmarks_screen.dart';
import '../browser/screens/browser_view.dart';
import '../business/screens/business_screen.dart';
import '../customization/screens/customization_screen.dart';
import '../cyber/screens/cyber_screen.dart';
import '../devtools/screens/code_editor_screen.dart';
import '../downloads/screens/downloads_screen.dart';
import '../history/screens/history_screen.dart';
import '../map/screens/nova_map_screen.dart';
import '../music/screens/nova_music_screen.dart';
import '../network/screens/nova_network_screen.dart';
import '../notifications/screens/notifications_screen.dart';
import '../offline/screens/offline_pages_screen.dart';
import '../premium/screens/subscription_screen.dart';
import '../profile/screens/profile_screen.dart';
import '../rewards/screens/rewards_screen.dart';
import '../settings/screens/settings_screen.dart';
import '../shield/screens/nova_shield_screen.dart';
import 'screens/nova_settings_screen.dart';
import 'widgets/nova_launch_screen.dart';

class NovaFeatures {
  NovaFeatures._();

  static const String devToolsUrl = 'https://api.browser.t-lyfe.com.ng/devtools.html';

  /// Every page id NOVA may open.
  static const Set<String> ids = {
    'bookmarks', 'history', 'downloads', 'shield', 'nova_map', 'rewards',
    'nova_ai', 'nova_settings', 'browser_settings', 'nova_music', 'nova_network',
    'cyber', 'dev_tools', 'code_editor', 'business', 'customize', 'profile',
    'offline_pages', 'notifications', 'premium', 'incognito', 'new_tab', 'home',
  };

  static final RegExp _idShape = RegExp(r'^[a-z_]{1,30}$');

  /// True for a known page id (anything else from outside is ignored).
  static bool isValid(String? id) => id != null && _idShape.hasMatch(id) && ids.contains(id);

  /// The start page of the chosen search engine (for "open a new tab").
  static String newTabUrl() => switch (LocalDB.getSearchEngine()) {
        'bing' => 'https://www.bing.com',
        'duckduckgo' => 'https://duckduckgo.com',
        'yahoo' => 'https://search.yahoo.com',
        _ => 'https://www.google.com',
      };

  /// The screen for [id]; null for 'home' (handled by [open]) and unknown ids.
  static Widget? screenFor(String id) => switch (id) {
        'bookmarks' => const BookmarksScreen(),
        'history' => const HistoryScreen(),
        'downloads' => const DownloadsScreen(),
        'shield' => const NovaShieldScreen(),
        'nova_map' => const NovaMapScreen(), // shows its own Premium paywall
        'rewards' => const RewardsScreen(),
        'nova_ai' => const AiAssistantScreen(),
        'nova_settings' => const NovaSettingsScreen(),
        'browser_settings' => const SettingsScreen(),
        'nova_music' => const NovaMusicScreen(),
        'nova_network' => const NovaNetworkScreen(),
        'cyber' => const CyberScreen(),
        'dev_tools' => const BrowserView(initialQuery: devToolsUrl, autoOpenDevTools: true),
        'code_editor' => const CodeEditorScreen(sharedWorkspace: true),
        'business' => const BusinessScreen(),
        'customize' => const CustomizationScreen(),
        'profile' => const ProfileScreen(),
        'offline_pages' => const OfflinePagesScreen(),
        'notifications' => const NotificationsScreen(),
        'premium' => const SubscriptionScreen(),
        'incognito' => const BrowserView(initialQuery: 'https://www.google.com', incognito: true),
        'new_tab' => BrowserView(initialQuery: newTabUrl()),
        _ => null,
      };

  /// Display name used by the launch transition ("Opening NOVA Music").
  static String label(String id) => switch (id) {
        'bookmarks' => 'Bookmarks',
        'history' => 'History',
        'downloads' => 'Downloads',
        'shield' => 'NOVA Shield',
        'nova_map' => 'NOVA Map',
        'rewards' => 'Rewards',
        'nova_ai' => 'NOVA AI',
        'nova_settings' => 'NOVA Assistant settings',
        'browser_settings' => 'Settings',
        'nova_music' => 'NOVA Music',
        'nova_network' => 'NOVA Network',
        'cyber' => 'NOVA Cyber',
        'dev_tools' => 'Dev Tools',
        'code_editor' => 'X Coder',
        'business' => 'NOVA Business',
        'customize' => 'Customize',
        'profile' => 'your profile',
        'offline_pages' => 'Offline Pages',
        'notifications' => 'Notifications',
        'premium' => 'NOVA Premium',
        'incognito' => 'an incognito tab',
        'new_tab' => 'a new tab',
        'home' => 'Home',
        _ => 'NOVA X',
      };

  static IconData icon(String id) => switch (id) {
        'bookmarks' => Icons.bookmark_rounded,
        'history' => Icons.history_rounded,
        'downloads' => Icons.download_rounded,
        'shield' => Icons.shield_rounded,
        'nova_map' => Icons.map_rounded,
        'rewards' => Icons.monetization_on_rounded,
        'nova_ai' => Icons.auto_awesome_rounded,
        'nova_settings' => Icons.tune_rounded,
        'browser_settings' => Icons.settings_rounded,
        'nova_music' => Icons.library_music_rounded,
        'nova_network' => Icons.speed_rounded,
        'cyber' => Icons.security_rounded,
        'dev_tools' => Icons.developer_mode_rounded,
        'code_editor' => Icons.code_rounded,
        'business' => Icons.storefront_rounded,
        'customize' => Icons.palette_rounded,
        'profile' => Icons.person_rounded,
        'offline_pages' => Icons.offline_pin_rounded,
        'notifications' => Icons.notifications_rounded,
        'premium' => Icons.workspace_premium_rounded,
        'incognito' => Icons.person_off_rounded,
        'new_tab' => Icons.add_box_rounded,
        _ => Icons.home_rounded,
      };

  /// Opens [id] on [navigator]. Returns false for an unknown id.
  ///
  /// With [animate] (the default) NOVA shows its short "Opening …"
  /// transition first, so the user sees NOVA doing it.
  static bool open(NavigatorState navigator, String id, {bool animate = true}) {
    if (!isValid(id)) return false;
    if (id == 'home') {
      navigator.popUntil((route) => route.isFirst);
      return true;
    }
    final screen = screenFor(id);
    if (screen == null) return false;
    final name = 'nova/$id';
    if (!animate) {
      navigator.push(MaterialPageRoute(builder: (_) => screen, settings: RouteSettings(name: name)));
      return true;
    }
    navigator.push(PageRouteBuilder<void>(
      settings: const RouteSettings(name: 'nova/launch'),
      transitionDuration: const Duration(milliseconds: 260),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, __, ___) => NovaLaunchScreen(
        label: label(id),
        icon: icon(id),
        routeName: name,
        builder: (_) => screen,
      ),
      transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
    ));
    return true;
  }
}
