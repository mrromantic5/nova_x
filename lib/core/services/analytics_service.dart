// lib/core/services/analytics_service.dart
//
// 3.9.0 — privacy-light usage statistics for the admin dashboard (active
// users, most used features, versions, time zones).
//
// What is sent: event names ("app_open", "screen_view", "ai_chat"…), the
// feature/page name, the app version, the phone's time zone and an anonymous
// install id (a SHA-256 hash — never the raw Android id). Never sent: what you
// type or say, web addresses, page contents, photos, contacts or location.
//
// Events are batched (every 60 s, at 20 events, and when the app goes to the
// background) so this costs almost no data or battery.

import 'dart:async';

import 'package:flutter/widgets.dart';

import 'app_info.dart';
import 'device_clock.dart';
import 'platform_api.dart';

class AnalyticsService with WidgetsBindingObserver {
  AnalyticsService._();
  static final AnalyticsService instance = AnalyticsService._();

  static final RegExp _name = RegExp(r'^[a-z][a-z0-9_]{1,47}$');
  static const int _maxQueue = 200;

  final List<Map<String, Object?>> _queue = [];
  Timer? _flushTimer;
  Timer? _beatTimer;
  bool _started = false;
  bool _sending = false;
  bool _foreground = true;

  /// Call once after the first frame.
  static Future<void> start() => instance._start();

  /// Records one event. [feature] and [props] keys must be snake_case;
  /// prop values are short text / numbers only.
  static void log(String name, {String? feature, Map<String, Object?>? props}) =>
      instance._log(name, feature: feature, props: props);

  /// "NovaShieldScreen" → "nova_shield".
  static String? featureFromType(String typeName) {
    var n = typeName.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    n = n.replaceFirst(RegExp(r'(Screen|Page|View)$'), '');
    if (n.isEmpty) return null;
    final snake = n
        .replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m[1]}_${m[2]}')
        .replaceAllMapped(RegExp(r'([A-Z])([A-Z][a-z])'), (m) => '${m[1]}_${m[2]}')
        .toLowerCase();
    return _name.hasMatch(snake) ? snake : null;
  }

  Future<void> _start() async {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    await AppInfo.load();
    await DeviceClock.load();
    _log('app_open');
    _flushTimer = Timer.periodic(const Duration(seconds: 60), (_) => _flush());
    // "Live now" on the dashboard = seen in the last 5 minutes.
    _beatTimer = Timer.periodic(const Duration(minutes: 4), (_) {
      if (_foreground) _flush(heartbeat: true);
    });
    unawaited(_flush(heartbeat: true));
  }

  void _log(String name, {String? feature, Map<String, Object?>? props}) {
    if (!_name.hasMatch(name)) return;
    final f = feature != null && RegExp(r'^[a-z][a-z0-9_]{0,47}$').hasMatch(feature) ? feature : null;
    final clean = <String, Object?>{};
    props?.forEach((k, v) {
      if (clean.length >= 8 || !RegExp(r'^[a-z_]{1,24}$').hasMatch(k)) return;
      if (v is num || v is bool) clean[k] = v;
      if (v is String) clean[k] = v.length > 60 ? v.substring(0, 60) : v;
    });
    _queue.add({'name': name, if (f != null) 'feature': f, if (clean.isNotEmpty) 'props': clean});
    if (_queue.length > _maxQueue) _queue.removeRange(0, _queue.length - _maxQueue);
    if (_queue.length >= 20) unawaited(_flush());
  }

  Future<void> _flush({bool heartbeat = false}) async {
    if (!_started || _sending || (_queue.isEmpty && !heartbeat)) return;
    _sending = true;
    final batch = _queue.take(50).toList();
    try {
      final ok = await PlatformApi.sendEvents({
        if (AppInfo.installId != null) 'device': AppInfo.installId,
        'app_version': AppInfo.version,
        if (DeviceClock.timeZoneId != null) 'tz': DeviceClock.timeZoneId,
        'events': batch,
        if (heartbeat) 'heartbeat': true,
      });
      if (ok) _queue.removeRange(0, batch.length < _queue.length ? batch.length : _queue.length);
    } catch (_) {
    } finally {
      _sending = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (state == AppLifecycleState.paused) unawaited(_flush());
    if (state == AppLifecycleState.resumed) {
      _log('app_resume');
      unawaited(_flush(heartbeat: true));
    }
  }

  void dispose() {
    _flushTimer?.cancel();
    _beatTimer?.cancel();
  }
}

/// Logs a "screen_view" for every page that opens (the page's class name,
/// e.g. NovaShieldScreen → nova_shield). Add to MaterialApp.navigatorObservers.
class AnalyticsNavigatorObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is! PageRoute<dynamic>) return;
    final PageRoute<dynamic> page = route;
    final named = page.settings.name;
    if (named != null && named.isNotEmpty && named != '/') {
      final f = AnalyticsService.featureFromType(named.replaceAll('/', ' '));
      if (f != null) AnalyticsService.log('screen_view', feature: f);
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = page.subtreeContext;
      if (ctx == null) return;
      final type = _firstScreen(ctx);
      final f = type == null ? null : AnalyticsService.featureFromType(type);
      if (f != null) AnalyticsService.log('screen_view', feature: f);
    });
  }

  /// The first widget in the page whose class name ends in "Screen"/"Page".
  static String? _firstScreen(BuildContext ctx) {
    String? found;
    var budget = 60;
    void visit(Element e) {
      if (found != null || budget-- <= 0) return;
      final n = e.widget.runtimeType.toString();
      if (n.endsWith('Screen') || n.endsWith('Page')) {
        found = n;
        return;
      }
      e.visitChildElements(visit);
    }

    try {
      (ctx as Element).visitChildElements(visit);
    } catch (_) {}
    return found;
  }
}
