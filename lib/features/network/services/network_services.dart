// lib/features/network/services/network_services.dart
//
// NOVA Network helpers:
//   DeviceInfoService — device, battery, connection, system (Android, on the phone)
//   SpeedHistory      — finished tests, kept on the phone (last 100)
//   NetworkTools      — DNS lookup timing, popular-site response checks and a
//                       latency monitor (all real measurements)

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/network_models.dart';
import 'speed_math.dart';
import 'speed_test_engine.dart';

class DeviceInfoService {
  DeviceInfoService._();

  static const MethodChannel _channel = MethodChannel('com.tlyfe.nova_x/nova');

  static Future<DeviceSnapshot> read() async {
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>('deviceInfo');
      return DeviceSnapshot.fromMap(raw);
    } on PlatformException {
      return DeviceSnapshot.fromMap(null);
    } on MissingPluginException {
      return DeviceSnapshot.fromMap(null);
    }
  }
}

class SpeedHistory {
  SpeedHistory._();

  static const String _key = 'nova_network_history_v1';
  static const int maxItems = 100;

  static List<SpeedTestResult> decode(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      return [
        for (final item in list)
          if (item is Map) SpeedTestResult.fromJson(Map<String, dynamic>.from(item)),
      ];
    } catch (_) {
      return const [];
    }
  }

  static String encode(List<SpeedTestResult> items) =>
      jsonEncode([for (final r in items.take(maxItems)) r.toJson()]);

  static Future<List<SpeedTestResult>> load() async {
    final prefs = await SharedPreferences.getInstance();
    return decode(prefs.getString(_key));
  }

  /// Newest first.
  static Future<List<SpeedTestResult>> add(SpeedTestResult r) async {
    final prefs = await SharedPreferences.getInstance();
    final items = [r, ...decode(prefs.getString(_key))];
    await prefs.setString(_key, encode(items));
    return items.take(maxItems).toList();
  }

  static Future<List<SpeedTestResult>> removeAt(int index) async {
    final prefs = await SharedPreferences.getInstance();
    final items = decode(prefs.getString(_key)).toList();
    if (index >= 0 && index < items.length) items.removeAt(index);
    await prefs.setString(_key, encode(items));
    return items;
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}

class DnsCheck {
  const DnsCheck(this.host, this.ms, this.addresses, {this.error});
  final String host;
  final double? ms;
  final List<String> addresses;
  final String? error;
}

class SiteCheck {
  const SiteCheck(this.name, this.url, {this.ms, this.status, this.error});
  final String name;
  final String url;
  final double? ms;
  final int? status;
  final String? error;

  bool get reachable => status != null;
}

class LatencySample {
  const LatencySample(this.index, this.ms);
  final int index;

  /// null = no answer (counted as lost).
  final double? ms;
}

class NetworkTools {
  NetworkTools._();

  static const List<String> dnsHosts = [
    'google.com',
    'youtube.com',
    'whatsapp.net',
    'facebook.com',
    'cloudflare.com',
    'tiktok.com',
    'netflix.com',
    'github.com',
  ];

  static const List<(String, String)> sites = [
    ('Google', 'https://www.google.com/generate_204'),
    ('YouTube', 'https://www.youtube.com/generate_204'),
    ('WhatsApp', 'https://web.whatsapp.com/'),
    ('Facebook', 'https://www.facebook.com/'),
    ('Instagram', 'https://www.instagram.com/'),
    ('TikTok', 'https://www.tiktok.com/'),
    ('X (Twitter)', 'https://x.com/'),
    ('Netflix', 'https://www.netflix.com/'),
    ('Cloudflare', 'https://www.cloudflare.com/cdn-cgi/trace'),
    ('GitHub', 'https://github.com/'),
  ];

  /// Time the phone takes to turn each name into addresses.
  static Future<List<DnsCheck>> dnsLookups({void Function(DnsCheck)? onEach}) async {
    final out = <DnsCheck>[];
    for (final host in dnsHosts) {
      final sw = Stopwatch()..start();
      DnsCheck check;
      try {
        final addrs = await InternetAddress.lookup(host).timeout(const Duration(seconds: 6));
        sw.stop();
        check = DnsCheck(host, sw.elapsedMicroseconds / 1000, [for (final a in addrs.take(2)) a.address]);
      } on TimeoutException {
        check = DnsCheck(host, null, const [], error: 'Timed out');
      } on SocketException {
        check = DnsCheck(host, null, const [], error: 'Not found');
      }
      out.add(check);
      onEach?.call(check);
    }
    return out;
  }

  /// Response time of popular services (connection + first reply).
  static Future<List<SiteCheck>> checkSites({void Function(SiteCheck)? onEach}) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8)
      ..userAgent = 'Mozilla/5.0 (Linux; Android) NOVA-X-Network/1.0';
    final results = await Future.wait([
      for (final (name, url) in sites)
        _checkOne(client, name, url).then((r) {
          onEach?.call(r);
          return r;
        }),
    ]);
    client.close(force: true);
    return results;
  }

  static Future<SiteCheck> _checkOne(HttpClient client, String name, String url) async {
    final sw = Stopwatch()..start();
    try {
      final req = await client.getUrl(Uri.parse(url)).timeout(const Duration(seconds: 8));
      req.followRedirects = false;
      final res = await req.close().timeout(const Duration(seconds: 8));
      sw.stop();
      unawaited(res.drain<void>().catchError((_) {}));
      return SiteCheck(name, url, ms: sw.elapsedMicroseconds / 1000, status: res.statusCode);
    } on TimeoutException {
      return SiteCheck(name, url, error: 'Timed out');
    } on SocketException {
      return SiteCheck(name, url, error: 'Unreachable');
    } on HandshakeException {
      return SiteCheck(name, url, error: 'Secure connection failed');
    } on HttpException {
      return SiteCheck(name, url, error: 'Connection error');
    }
  }

  /// One ping per second to the NOVA speed server, [count] times.
  static Stream<LatencySample> latencyMonitor({int count = 30, String? baseUrl}) async* {
    final engine = SpeedTestEngine(baseUrl: baseUrl);
    try {
      for (var i = 0; i < count; i++) {
        double? ms;
        try {
          final s = await engine.measureLatency(1);
          ms = s.first;
        } catch (_) {
          ms = null;
        }
        yield LatencySample(i, ms);
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    } finally {
      engine.cancel();
    }
  }

  /// Summary of a latency run: avg, min, max, jitter, loss %.
  static ({double avg, double min, double max, double jitter, double loss}) summarize(List<LatencySample> s) {
    final ok = [for (final x in s) if (x.ms != null) x.ms!];
    if (ok.isEmpty) return (avg: 0, min: 0, max: 0, jitter: 0, loss: s.isEmpty ? 0 : 100);
    final sum = ok.fold<double>(0, (a, b) => a + b);
    return (
      avg: sum / ok.length,
      min: ok.reduce((a, b) => a < b ? a : b),
      max: ok.reduce((a, b) => a > b ? a : b),
      jitter: SpeedMath.jitter(ok),
      loss: (s.length - ok.length) * 100 / s.length,
    );
  }
}
