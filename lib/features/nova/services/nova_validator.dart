// lib/features/nova/services/nova_validator.dart
//
// The single source of truth for what a NOVA action may contain. Every
// action — from the on-device parser or from the AI planner — is built here.
// AI output is untrusted: unknown actions, unsafe URL schemes, oversized or
// malformed arguments are rejected, never "best-effort" executed.

import '../models/nova_models.dart';

class NovaActionValidator {
  NovaActionValidator._();

  /// Settings screens NOVA can open (opening a screen never changes a setting).
  static const Set<String> settingsTargets = {
    'wifi', 'bluetooth', 'display', 'sound', 'location', 'battery', 'airplane',
    'notifications', 'app', 'general', 'language', 'storage', 'security',
    'date', 'data', 'nfc', 'default_apps', 'assistant',
  };

  /// NOVA Music controls (music_control "command"), including media volume.
  static const Set<String> musicCommands = {
    'pause', 'resume', 'next', 'previous', 'stop', 'now_playing',
    'volume_up', 'volume_down', 'mute', 'unmute',
    'shuffle_on', 'shuffle_off', 'repeat_one', 'repeat_all', 'repeat_off', 'restart',
  };

  /// Apps that support "search inside the app" through a validated deep link.
  static const Set<String> searchableApps = {
    'youtube', 'spotify', 'maps', 'play_store', 'x',
  };

  /// Spoken settings names → canonical target.
  static const Map<String, String> settingsSynonyms = {
    'wifi': 'wifi', 'wi-fi': 'wifi', 'wi fi': 'wifi', 'wireless': 'wifi', 'internet': 'wifi',
    'bluetooth': 'bluetooth',
    'display': 'display', 'screen': 'display', 'brightness': 'display',
    'sound': 'sound', 'sounds': 'sound', 'volume': 'sound', 'ringtone': 'sound',
    'location': 'location', 'gps': 'location',
    'battery': 'battery', 'battery saver': 'battery', 'power saving': 'battery',
    'airplane': 'airplane', 'airplane mode': 'airplane', 'aeroplane mode': 'airplane',
    'flight mode': 'airplane',
    'notification': 'notifications', 'notifications': 'notifications',
    'app': 'app', 'app info': 'app',
    'language': 'language', 'languages': 'language',
    'storage': 'storage',
    'security': 'security', 'lock screen': 'security', 'privacy': 'security',
    'date': 'date', 'time': 'date', 'date and time': 'date',
    'data': 'data', 'mobile data': 'data', 'data usage': 'data', 'hotspot': 'data',
    'nfc': 'nfc',
    'default apps': 'default_apps', 'default browser': 'default_apps',
    'assistant': 'assistant', 'digital assistant': 'assistant', 'voice input': 'assistant',
    'phone': 'general', 'device': 'general', 'system': 'general',
  };

  static final RegExp _control = RegExp(r'[\u0000-\u001F\u007F]');
  static final RegExp _domainLike =
      RegExp(r'^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,24}(?::\d{2,5})?(?:[/?#]\S*)?$',
          caseSensitive: false);

  // ── Builders ──────────────────────────────────────────────────────────────

  /// Validates a planner action `{name, args}`. Returns null if rejected.
  static NovaAction? fromPlanner(String? name, Object? rawArgs) {
    final type = NovaActionType.fromWire(name);
    if (type == null) return null;
    final args = <String, String>{};
    if (rawArgs is Map) {
      rawArgs.forEach((k, v) {
        if (k is String && (v is String || v is num)) args[k] = v.toString();
      });
    }
    return build(type, args);
  }

  /// Validates and normalises arguments for [type]. Returns null if invalid.
  static NovaAction? build(NovaActionType type, Map<String, String> args) {
    switch (type) {
      case NovaActionType.openUrl:
        final url = normaliseUrl(args['url']);
        return url == null ? null : NovaAction(type, {'url': url});
      case NovaActionType.webSearch:
        final q = cleanText(args['query'], 300);
        return q == null ? null : NovaAction(type, {'query': q});
      case NovaActionType.openApp:
        final app = cleanAppName(args['app']);
        return app == null ? null : NovaAction(type, {'app': app});
      case NovaActionType.searchInApp:
        final app = canonicalApp(cleanAppName(args['app']) ?? '');
        final q = cleanText(args['query'], 200);
        if (app == null || q == null || !searchableApps.contains(app)) return null;
        return NovaAction(type, {'app': app, 'query': q});
      case NovaActionType.callContact:
        final name = cleanText(args['name'], 60);
        return name == null ? null : NovaAction(type, {'name': name});
      case NovaActionType.dialNumber:
        final number = sanitisePhone(args['number']);
        if (number == null) return null;
        final label = cleanText(args['label'], 60);
        return NovaAction(type, {'number': number, if (label != null) 'label': label});
      case NovaActionType.openSettings:
        final target = settingsTarget(args['target']);
        if (target == null) return null;
        final toggle = args['toggle'];
        return NovaAction(type, {
          'target': target,
          if (toggle == 'on' || toggle == 'off') 'toggle': toggle!,
        });
      case NovaActionType.navigate:
        final d = cleanText(args['destination'], 200);
        return d == null ? null : NovaAction(type, {'destination': d});
      case NovaActionType.playMusic:
        // Empty query = "play some music". A song id comes only from NOVA's
        // own choice list (digits only).
        final rawQuery = (args['query'] ?? '').trim();
        final query = rawQuery.isEmpty ? '' : cleanText(rawQuery, 200);
        if (query == null) return null;
        final rawId = args['song_id'];
        String? songId;
        if (rawId != null) {
          if (!RegExp(r'^\d{1,18}$').hasMatch(rawId)) return null;
          songId = rawId;
        }
        final label = cleanText(args['label'], 120);
        return NovaAction(type, {
          'query': query,
          if (songId != null) 'song_id': songId,
          if (label != null) 'label': label,
        });
      case NovaActionType.musicControl:
        final command = args['command'];
        if (command == null || !musicCommands.contains(command)) return null;
        return NovaAction(type, {'command': command});
    }
  }

  // ── Field validators ──────────────────────────────────────────────────────

  /// Returns a safe http(s) URL, or null. Bare domains get https://.
  /// javascript:, file:, intent:, data:, content: etc. are always rejected.
  static String? normaliseUrl(String? raw) {
    var t = (raw ?? '').trim();
    if (t.isEmpty || t.length > 2048 || _control.hasMatch(t) || t.contains(' ')) return null;
    final lower = t.toLowerCase();
    if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
      if (lower.contains(':') && !_domainLike.hasMatch(lower)) return null; // other scheme
      if (!_domainLike.hasMatch(lower)) return null;
      t = 'https://$t';
    }
    final uri = Uri.tryParse(t);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) return null;
    if (uri.host.isEmpty || !uri.host.contains('.') || uri.userInfo.isNotEmpty) return null;
    return uri.toString();
  }

  /// Plain text argument: trimmed, bounded, no control characters.
  static String? cleanText(String? raw, int maxLength) {
    final t = (raw ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
    if (t.isEmpty || t.length > maxLength || _control.hasMatch(t)) return null;
    return t;
  }

  /// App names: letters, digits, spaces and a few symbols, ≤ 40 chars.
  static String? cleanAppName(String? raw) {
    final t = cleanText(raw, 40);
    if (t == null) return null;
    if (!RegExp(r"^[\p{L}\p{N} .&'+_-]+$", unicode: true).hasMatch(t)) return null;
    return t;
  }

  /// Digits with optional leading '+', and * / # for codes. 3–20 chars.
  static String? sanitisePhone(String? raw) {
    final kept = (raw ?? '').replaceAll(RegExp(r'[^0-9+*#]'), '');
    final digits = kept.replaceAll(RegExp(r'[^0-9]'), '').length;
    if (digits < 3 || kept.length > 20) return null;
    if (kept.indexOf('+') > 0) return null;
    return kept;
  }

  static String? settingsTarget(String? raw) {
    final t = (raw ?? '').trim().toLowerCase().replaceAll('_', ' ');
    if (t.isEmpty) return null;
    final canonical = t.replaceAll(' ', '_');
    if (settingsTargets.contains(canonical)) return canonical;
    return settingsSynonyms[t];
  }

  /// Spoken app name → canonical key understood by the native layer.
  static String? canonicalApp(String raw) {
    final t = raw.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    if (t.isEmpty) return null;
    return appAliases[t] ?? t.replaceAll(' ', '_');
  }

  static const Map<String, String> appAliases = {
    'youtube': 'youtube', 'you tube': 'youtube', 'yt': 'youtube',
    'youtube music': 'youtube_music', 'yt music': 'youtube_music',
    'whatsapp': 'whatsapp', 'whats app': 'whatsapp', 'whatsapp business': 'whatsapp',
    'instagram': 'instagram', 'insta': 'instagram', 'ig': 'instagram',
    'facebook': 'facebook', 'fb': 'facebook',
    'messenger': 'messenger', 'facebook messenger': 'messenger',
    'tiktok': 'tiktok', 'tik tok': 'tiktok',
    'x': 'x', 'twitter': 'x', 'x twitter': 'x',
    'telegram': 'telegram', 'snapchat': 'snapchat', 'spotify': 'spotify',
    'netflix': 'netflix', 'gmail': 'gmail', 'google mail': 'gmail',
    'maps': 'maps', 'google maps': 'maps', 'map': 'maps',
    'play store': 'play_store', 'playstore': 'play_store', 'google play': 'play_store',
    'chrome': 'chrome', 'google chrome': 'chrome',
    'linkedin': 'linkedin', 'zoom': 'zoom', 'google': 'google',
    'drive': 'drive', 'google drive': 'drive',
    'photos': 'photos', 'google photos': 'photos',
    'chatxap': 'chatxap', 'chat xap': 'chatxap', 'chat x app': 'chatxap',
    'calculator': 'calculator', 'calc': 'calculator',
    'camera': 'camera', 'phone': 'phone', 'dialer': 'phone', 'dialler': 'phone',
    'messages': 'messages', 'sms': 'messages', 'text messages': 'messages',
    'contacts': 'contacts', 'email': 'email', 'mail': 'email',
    'gallery': 'gallery', 'music': 'music', 'calendar': 'calendar',
    'clock': 'clock', 'alarm': 'clock', 'alarms': 'clock',
    'settings': 'settings',
    'nova x': 'nova_x', 'nova': 'nova_x', 'this browser': 'nova_x',
  };

  /// NOVA X's own screens, opened inside the browser (spoken phrase → id).
  static const Map<String, String> inAppFeatures = {
    'bookmarks': 'bookmarks', 'saved pages': 'bookmarks', 'saved': 'bookmarks',
    'history': 'history', 'browsing history': 'history',
    'downloads': 'downloads',
    'nova shield': 'shield', 'shield': 'shield',
    'nova map': 'nova_map',
    'rewards': 'rewards', 'points': 'rewards', 'my points': 'rewards',
    'nova ai': 'nova_ai', 'ai chat': 'nova_ai', 'nova chat': 'nova_ai',
    'nova settings': 'nova_settings', 'nova assistant settings': 'nova_settings',
    'assistant settings': 'nova_settings',
    'nova x settings': 'browser_settings', 'browser settings': 'browser_settings',
    'nova music': 'nova_music', 'music player': 'nova_music', 'my music': 'nova_music',
    'music app': 'nova_music', 'nova music player': 'nova_music', 'music library': 'nova_music',
    'nova network': 'nova_network', 'network page': 'nova_network', 'speed test page': 'nova_network',
    'speed tester': 'nova_network', 'network tools': 'nova_network', 'nova speed test': 'nova_network',
    'speed test': 'nova_network', 'network': 'nova_network',
    'nova cyber': 'cyber', 'cyber': 'cyber', 'cyber security': 'cyber', 'website scanner': 'cyber',
    'security scanner': 'cyber', 'site scanner': 'cyber',
    'dev tools': 'dev_tools', 'devtools': 'dev_tools', 'developer tools': 'dev_tools',
    'x coder': 'code_editor', 'x code editor': 'code_editor', 'code editor': 'code_editor', 'x code': 'code_editor',
    'coder': 'code_editor',
    'business': 'business', 'businesses': 'business', 'nova x business': 'business',
    'business directory': 'business', 'nova business': 'business',
    'customize': 'customize', 'customise': 'customize', 'customization': 'customize',
    'customisation': 'customize', 'wallpaper': 'customize', 'home background': 'customize',
    'profile': 'profile', 'my profile': 'profile', 'my account': 'profile', 'account': 'profile',
    'offline pages': 'offline_pages', 'saved offline pages': 'offline_pages',
    'notifications': 'notifications', 'my notifications': 'notifications',
    'premium': 'premium', 'nova x premium': 'premium', 'subscription': 'premium', 'go premium': 'premium',
    'incognito': 'incognito', 'incognito tab': 'incognito', 'private tab': 'incognito',
    'private mode': 'incognito', 'incognito mode': 'incognito', 'new private tab': 'incognito',
    'new tab': 'new_tab', 'a new tab': 'new_tab',
    'home': 'home', 'home page': 'home', 'homepage': 'home', 'home screen': 'home', 'nova x home': 'home',
  };

  /// Web pages used when an app isn't installed (opened inside NOVA X).
  static const Map<String, String> webFallbacks = {
    'youtube': 'https://m.youtube.com',
    'youtube_music': 'https://music.youtube.com',
    'facebook': 'https://m.facebook.com',
    'instagram': 'https://www.instagram.com',
    'x': 'https://x.com',
    'tiktok': 'https://www.tiktok.com',
    'whatsapp': 'https://web.whatsapp.com',
    'telegram': 'https://web.telegram.org',
    'snapchat': 'https://www.snapchat.com',
    'spotify': 'https://open.spotify.com',
    'netflix': 'https://www.netflix.com',
    'gmail': 'https://mail.google.com',
    'maps': 'https://www.google.com/maps',
    'play_store': 'https://play.google.com/store',
    'linkedin': 'https://www.linkedin.com',
    'google': 'https://www.google.com',
    'drive': 'https://drive.google.com',
    'photos': 'https://photos.google.com',
    'chatxap': 'https://c.x.t-lyfe.com.ng',
  };

  /// Display names for spoken confirmations.
  static String displayName(String canonical) => const {
        'youtube': 'YouTube', 'youtube_music': 'YouTube Music', 'whatsapp': 'WhatsApp',
        'instagram': 'Instagram', 'facebook': 'Facebook', 'messenger': 'Messenger',
        'tiktok': 'TikTok', 'x': 'X', 'telegram': 'Telegram', 'snapchat': 'Snapchat',
        'spotify': 'Spotify', 'netflix': 'Netflix', 'gmail': 'Gmail', 'maps': 'Maps',
        'play_store': 'Play Store', 'chrome': 'Chrome', 'linkedin': 'LinkedIn',
        'zoom': 'Zoom', 'google': 'Google', 'drive': 'Drive', 'photos': 'Photos',
        'chatxap': 'ChatXAP', 'calculator': 'Calculator', 'camera': 'Camera',
        'phone': 'Phone', 'messages': 'Messages', 'contacts': 'Contacts',
        'email': 'Email', 'gallery': 'Gallery', 'music': 'Music',
        'calendar': 'Calendar', 'clock': 'Clock', 'settings': 'Settings',
        'nova_x': 'NOVA X',
      }[canonical] ??
      _titleCase(canonical.replaceAll('_', ' '));

  static String settingsDisplayName(String target) => const {
        'wifi': 'Wi-Fi', 'bluetooth': 'Bluetooth', 'display': 'display',
        'sound': 'sound', 'location': 'location', 'battery': 'battery',
        'airplane': 'airplane mode', 'notifications': 'notification',
        'app': 'NOVA X app', 'general': 'main', 'language': 'language',
        'storage': 'storage', 'security': 'security', 'date': 'date and time',
        'data': 'mobile data', 'nfc': 'NFC', 'default_apps': 'default apps',
        'assistant': 'digital assistant',
      }[target] ??
      target;

  static String _titleCase(String s) => s
      .split(' ')
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1))
      .join(' ');
}
