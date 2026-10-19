// lib/features/nova/services/nova_executor.dart
//
// Executes validated NovaActions through trusted handlers (NOVA X browser
// navigation via NovaHost, device actions via the native bridge) and returns
// the REAL outcome. Messages describe what actually happened — e.g. "Opening
// the dialer…", never "Calling…" — because launching an intent is not the
// same as completing the task.

import '../models/nova_models.dart';
import 'nova_native.dart';
import 'nova_validator.dart';

/// Where NOVA is running and how it can navigate.
abstract class NovaHost {
  /// True for the floating assistant window shown over other apps.
  bool get isOverlay;

  /// Opens [url] in a NOVA X browser tab.
  Future<bool> openInBrowser(String url);

  /// Opens a NOVA X screen by id (see NovaActionValidator.inAppFeatures).
  Future<bool> openFeature(String featureId);

  /// Dismisses the assistant UI.
  void close();

  /// True once the assistant UI has been dismissed (e.g. NOVA opened a page
  /// in the browser). The controller stops there instead of speaking.
  bool get isClosed;
}

class NovaExecutor {
  NovaExecutor({
    required NovaNativeApi native,
    required NovaHost host,
    String Function(String query)? searchUrl,
  })  : _native = native,
        _host = host,
        _searchUrl = searchUrl ??
            ((q) => 'https://www.google.com/search?q=${Uri.encodeComponent(q)}');

  final NovaNativeApi _native;
  final NovaHost _host;
  final String Function(String query) _searchUrl;

  static const Map<String, String> _featureNames = {
    'bookmarks': 'your bookmarks',
    'history': 'your browsing history',
    'downloads': 'your downloads',
    'shield': 'NOVA Shield',
    'nova_map': 'NOVA Map',
    'rewards': 'your rewards',
    'nova_ai': 'NOVA AI chat',
    'nova_settings': 'NOVA assistant settings',
    'browser_settings': 'NOVA X settings',
  };

  Future<NovaActionResult> execute(NovaAction a) async {
    try {
      return await switch (a.type) {
        NovaActionType.openUrl => _openUrl(a),
        NovaActionType.webSearch => _webSearch(a),
        NovaActionType.openApp => _openApp(a),
        NovaActionType.searchInApp => _searchInApp(a),
        NovaActionType.callContact => _callContact(a),
        NovaActionType.dialNumber => _dial(a),
        NovaActionType.openSettings => _openSettings(a),
        NovaActionType.navigate => _navigate(a),
      };
    } catch (_) {
      return _result(a, NovaActionStatus.failed, 'Something went wrong while doing that.');
    }
  }

  // ── Browser ───────────────────────────────────────────────────────────────

  Future<NovaActionResult> _openUrl(NovaAction a) async {
    final url = a.arg('url');
    final ok = await _host.openInBrowser(url);
    if (!ok) return _result(a, NovaActionStatus.failed, "I couldn't open that page.");
    return _result(a, NovaActionStatus.success, 'Opening ${_hostLabel(url)} in NOVA X.');
  }

  Future<NovaActionResult> _webSearch(NovaAction a) async {
    final q = a.arg('query');
    final ok = await _host.openInBrowser(_searchUrl(q));
    if (!ok) return _result(a, NovaActionStatus.failed, "I couldn't start that search.");
    return _result(a, NovaActionStatus.success, 'Searching the web for “$q”.');
  }

  // ── Apps ──────────────────────────────────────────────────────────────────

  Future<NovaActionResult> _openApp(NovaAction a) async {
    final spoken = a.arg('app');
    final lower = spoken.toLowerCase();

    final feature = NovaActionValidator.inAppFeatures[lower];
    if (feature != null) {
      final name = _featureNames[feature] ?? spoken;
      if (await _host.openFeature(feature)) {
        return _result(a, NovaActionStatus.success, 'Opening $name.');
      }
      return _result(a, NovaActionStatus.unsupported,
          "I can't open $name from here. Open NOVA X and you'll find it in the menu.");
    }

    final canonical = NovaActionValidator.canonicalApp(spoken) ?? lower;
    final display = NovaActionValidator.displayName(canonical);
    final r = await _native.runAction('open_app', {'app': canonical});
    switch (r.status) {
      case 'success':
        final label = r.str('label') ?? display;
        if (canonical == 'nova_x' && !_host.isOverlay) {
          return _result(a, NovaActionStatus.success, "You're already in NOVA X.");
        }
        return _result(a, NovaActionStatus.success, 'Opening $label.');
      case 'not_found':
        final web = NovaActionValidator.webFallbacks[canonical];
        if (web != null && await _host.openInBrowser(web)) {
          return _result(a, NovaActionStatus.success,
              "$display isn't installed, so I opened it in NOVA X.");
        }
        return _result(a, NovaActionStatus.notFound,
            "I couldn't find an app called “$spoken” on your phone.");
      case 'invalid':
        return _result(a, NovaActionStatus.invalid, "That app name doesn't look right.");
      default:
        return _nativeFailure(a, r.status);
    }
  }

  Future<NovaActionResult> _searchInApp(NovaAction a) async {
    final app = a.arg('app');
    final q = a.arg('query');
    final display = NovaActionValidator.displayName(app);
    final r = await _native.runAction('search_in_app', {'app': app, 'query': q});
    if (r.status == 'success') {
      return _result(a, NovaActionStatus.success, 'Searching $display for “$q”.');
    }
    final web = _webSearchFallback(app, q);
    if (web != null && await _host.openInBrowser(web)) {
      return _result(a, NovaActionStatus.success,
          "$display isn't installed, so I searched it in NOVA X.");
    }
    return _nativeFailure(a, r.status);
  }

  String? _webSearchFallback(String app, String q) {
    final e = Uri.encodeComponent(q);
    return switch (app) {
      'youtube' => 'https://m.youtube.com/results?search_query=$e',
      'spotify' => 'https://open.spotify.com/search/$e',
      'maps' => 'https://www.google.com/maps/search/?api=1&query=$e',
      'play_store' => 'https://play.google.com/store/search?q=$e',
      'x' => 'https://x.com/search?q=$e',
      _ => null,
    };
  }

  // ── Phone ─────────────────────────────────────────────────────────────────

  Future<NovaActionResult> _callContact(NovaAction a) async {
    final name = a.arg('name');
    final r = await _native.runAction('search_contacts', {'query': name});
    if (r.status == 'permission_required') {
      return _result(a, NovaActionStatus.permissionRequired,
          'To call someone by name, NOVA needs to look them up in your contacts. '
          "They're searched on this phone only and never uploaded.");
    }
    if (r.status != 'success') return _nativeFailure(a, r.status);

    final raw = r.data['matches'];
    final matches = <Map<String, String>>[];
    if (raw is List) {
      for (final m in raw) {
        if (m is Map) {
          final n = m['name'];
          final number = m['number'];
          if (n is String && number is String) {
            final t = m['type'];
            matches.add({'name': n, 'number': number, 'type': t is String ? t : ''});
          }
        }
      }
    }

    if (matches.isEmpty) {
      return _result(a, NovaActionStatus.notFound, "I couldn't find “$name” in your contacts.");
    }
    if (matches.length == 1) {
      final only = matches.first;
      final dial = NovaActionValidator.build(
          NovaActionType.dialNumber, {'number': only['number']!, 'label': only['name']!});
      if (dial == null) {
        return _result(a, NovaActionStatus.invalid,
            "${only['name']}'s number doesn't look like one I can dial.");
      }
      return _dial(dial);
    }

    final choices = <NovaChoice>[];
    for (final m in matches.take(5)) {
      final dial = NovaActionValidator.build(
          NovaActionType.dialNumber, {'number': m['number']!, 'label': m['name']!});
      if (dial == null) continue;
      final type = m['type']!;
      choices.add(NovaChoice(
        label: m['name']!,
        subtitle: type.isEmpty ? m['number'] : '$type · ${m['number']}',
        action: dial,
      ));
    }
    if (choices.isEmpty) {
      return _result(a, NovaActionStatus.invalid, "I couldn't find a number I can dial for “$name”.");
    }
    return NovaActionResult(
      action: a,
      status: NovaActionStatus.needsClarification,
      message: 'I found ${choices.length} matches for “$name”. Which one should I call?',
      choices: choices,
    );
  }

  Future<NovaActionResult> _dial(NovaAction a) async {
    final r = await _native.runAction('dial_number', {'number': a.arg('number')});
    if (r.status == 'success') {
      final label = a.args['label'];
      final who = label == null ? '' : ' for $label';
      return _result(a, NovaActionStatus.success,
          'Opening the dialer$who. Tap Call when you are ready.');
    }
    if (r.status == 'invalid') {
      return _result(a, NovaActionStatus.invalid, "That phone number doesn't look right.");
    }
    return _nativeFailure(a, r.status);
  }

  // ── Settings & maps ───────────────────────────────────────────────────────

  Future<NovaActionResult> _openSettings(NovaAction a) async {
    final target = a.arg('target');
    final r = await _native.runAction('open_settings', {'target': target});
    if (r.status != 'success') return _nativeFailure(a, r.status);

    final opened = r.str('opened') ?? target;
    final name = NovaActionValidator.settingsDisplayName(target);
    final toggle = a.args['toggle'];
    if (opened != target) {
      return _result(a, NovaActionStatus.success,
          "Your phone doesn't have a shortcut to $name settings, so I opened Settings.");
    }
    if (toggle != null) {
      return _result(a, NovaActionStatus.success,
          "I can't switch $name $toggle myself, but I've opened $name settings so you can.");
    }
    if (target == 'general') return _result(a, NovaActionStatus.success, 'Opening Settings.');
    return _result(a, NovaActionStatus.success, 'Here are your $name settings.');
  }

  Future<NovaActionResult> _navigate(NovaAction a) async {
    final d = a.arg('destination');
    final r = await _native.runAction('navigate', {'destination': d});
    if (r.status == 'success') {
      return _result(a, NovaActionStatus.success, 'Getting directions to $d.');
    }
    final web = 'https://www.google.com/maps/dir/?api=1&destination=${Uri.encodeComponent(d)}';
    if (await _host.openInBrowser(web)) {
      return _result(a, NovaActionStatus.success, 'Opening directions to $d in NOVA X.');
    }
    return _nativeFailure(a, r.status);
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  NovaActionResult _result(NovaAction a, NovaActionStatus s, String message) =>
      NovaActionResult(action: a, status: s, message: message);

  NovaActionResult _nativeFailure(NovaAction a, String status) => switch (status) {
        'not_found' => _result(a, NovaActionStatus.notFound,
            "Your phone doesn't have an app that can do that."),
        'invalid' => _result(a, NovaActionStatus.invalid, "That request doesn't look right."),
        'unsupported' => _result(a, NovaActionStatus.unsupported,
            "That isn't supported on this phone yet."),
        'permission_required' => _result(a, NovaActionStatus.permissionRequired,
            'NOVA needs permission to do that.'),
        _ => _result(a, NovaActionStatus.failed, 'Something went wrong while doing that.'),
      };

  static String _hostLabel(String url) {
    final host = Uri.tryParse(url)?.host ?? url;
    return host.startsWith('www.') ? host.substring(4) : host;
  }
}
