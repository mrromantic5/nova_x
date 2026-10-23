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

  /// Opens [id] on [navigator]. Returns false for an unknown id.
  static bool open(NavigatorState navigator, String id) {
    if (!isValid(id)) return false;
    if (id == 'home') {
      navigator.popUntil((route) => route.isFirst);
      return true;
    }
    final screen = screenFor(id);
    if (screen == null) return false;
    navigator.push(MaterialPageRoute(
      builder: (_) => screen,
      settings: RouteSettings(name: 'nova/$id'),
    ));
    return true;
  }
}
