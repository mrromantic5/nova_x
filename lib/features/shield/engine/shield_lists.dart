// lib/features/shield/engine/shield_lists.dart
//
// NOVA Shield block lists: EasyList (ads) + EasyPrivacy (trackers,
// cryptominers), turned into domain rules for the native engine.
//
//  • A snapshot ships with the app (assets/shield/nova_shield_lists.txt),
//    so blocking works from the first launch, offline.
//  • Once a week NOVA X downloads the current lists from easylist.to
//    (mirror: the EasyList GitHub repository), parses them and keeps the
//    result in the app's private folder. A download that looks wrong
//    (too few rules) is ignored and the previous lists stay in use.
//
// Licence: EasyList / EasyPrivacy are GPLv3 or CC BY-SA 3.0 — credited as
// "The EasyList authors (https://easylist.to/)" in NOVA Shield › About lists.
// Android (3.13.0): same lists and parser as NOVA X for PC; requests are
// matched in the browser's shouldInterceptRequest (see shield_engine.dart).

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

/// Rule categories (one letter, shared with the native engine).
class ShieldCategory {
  ShieldCategory._();
  static const ads = 'a';
  static const trackers = 't';
  static const miners = 'm';
  static const user = 'u';
  static const images = 'i';
  static const passwordLock = 'p';

  static String label(String c) => switch (c) {
        ads => 'Ads',
        trackers => 'Trackers',
        miners => 'Cryptominers',
        user => 'Your rules',
        images => 'Images (site setting)',
        passwordLock => 'Password Guard lock',
        _ => 'Other',
      };
}

class ShieldListSet {
  ShieldListSet(this.rules, {required this.source, required this.updated});

  /// domain → category letter.
  final Map<String, String> rules;
  final String source; // 'bundled' | 'easylist.to' | 'github'
  final DateTime? updated;

  int get count => rules.length;
  int countOf(String cat) => rules.values.where((c) => c == cat).length;

  /// The engine's "rules" object: {"a":[…],"t":[…],"m":[…]}.
  Map<String, List<String>> grouped() {
    final out = <String, List<String>>{};
    rules.forEach((d, c) => (out[c] ??= <String>[]).add(d));
    return out;
  }
}

class ShieldListParser {
  ShieldListParser._();

  static const Set<String> _okOptions = {
    'third-party', '3p', 'script', 'image', 'subdocument', 'xmlhttprequest', 'ping', 'media', 'font', 'other',
    'stylesheet', 'object', 'websocket', 'all', 'important', 'popup', 'document',
  };
  static final RegExp _domain = RegExp(r'^[a-z0-9][a-z0-9.-]*\.[a-z0-9-]{2,}$');

  /// Domain rules of an Adblock-style list: blocked and exception domains.
  /// Only whole-domain rules ("||example.com^", optionally with simple
  /// type options) are taken; path, regex, cosmetic and domain-scoped
  /// rules are skipped (the engine works on hosts).
  static (Set<String>, Set<String>) parse(String text) {
    final block = <String>{};
    final allow = <String>{};
    for (var line in const LineSplitter().convert(text)) {
      line = line.trim();
      if (line.isEmpty || line.startsWith('!') || line.startsWith('[')) continue;
      if (line.contains('##') || line.contains('#@#') || line.contains('#?#') || line.contains('#\$#')) continue;
      final exception = line.startsWith('@@');
      if (exception) line = line.substring(2);
      if (!line.startsWith('||')) continue;
      var body = line.substring(2);
      final dollar = body.indexOf(r'$');
      if (dollar >= 0) {
        final opts = body.substring(dollar + 1).split(',').map((o) => o.trim().toLowerCase()).where((o) => o.isNotEmpty);
        if (opts.any((o) => !_okOptions.contains(o))) continue;
        body = body.substring(0, dollar);
      }
      if (body.endsWith('^|')) body = body.substring(0, body.length - 1);
      if (!body.endsWith('^')) continue;
      final d = body.substring(0, body.length - 1).toLowerCase();
      if (!_domain.hasMatch(d)) continue;
      (exception ? allow : block).add(d);
    }
    return (block, allow);
  }

  /// Several lists → one rule map (first category wins), exceptions removed.
  static Map<String, String> combine(List<(String category, String text)> lists) {
    final out = <String, String>{};
    final allow = <String>{};
    for (final (cat, text) in lists) {
      final (b, a) = parse(text);
      allow.addAll(a);
      for (final d in b) {
        out.putIfAbsent(d, () => cat);
      }
    }
    allow.forEach(out.remove);
    return out;
  }

  /// The bundled / cached file format: "<category> <domain>" per line.
  static Map<String, String> readCompact(String text) {
    final out = <String, String>{};
    for (final line in const LineSplitter().convert(text)) {
      if (line.length < 3 || line.startsWith('#') || line[1] != ' ') continue;
      final d = line.substring(2).trim();
      if (_domain.hasMatch(d)) out[d] = line[0];
    }
    return out;
  }

  static String writeCompact(Map<String, String> rules, {required String source}) {
    final b = StringBuffer()
      ..writeln('# NOVA Shield block list ($source). Built from EasyList and EasyPrivacy (https://easylist.to/), GPLv3 / CC BY-SA 3.0.')
      ..writeln('# Format: <category> <domain>   a = ads, t = trackers, m = cryptominers');
    final keys = rules.keys.toList()..sort();
    for (final d in keys) {
      b.writeln('${rules[d]} $d');
    }
    return b.toString();
  }
}

class ShieldLists {
  ShieldLists._();
  static final ShieldLists instance = ShieldLists._();

  static const String asset = 'assets/shield/nova_shield_lists.txt';
  static const Duration updateEvery = Duration(days: 7);
  static const int minimumRules = 10000; // a smaller download is treated as broken

  /// Full lists (preferred) and the EasyList repository's component files (mirror).
  static const List<(String, String)> primary = [
    ('a', 'https://easylist.to/easylist/easylist.txt'),
    ('t', 'https://easylist.to/easylist/easyprivacy.txt'),
  ];
  static const String _gh = 'https://raw.githubusercontent.com/easylist/easylist/master';
  static const List<(String, String)> mirror = [
    ('a', '$_gh/easylist/easylist_adservers.txt'),
    ('a', '$_gh/easylist/easylist_adservers_popup.txt'),
    ('a', '$_gh/easylist/easylist_thirdparty.txt'),
    ('m', '$_gh/easyprivacy/easyprivacy_trackingservers_mining.txt'),
    ('t', '$_gh/easyprivacy/easyprivacy_trackingservers_general.txt'),
    ('t', '$_gh/easyprivacy/easyprivacy_trackingservers_thirdparty.txt'),
    ('t', '$_gh/easyprivacy/easyprivacy_trackingservers_admiral.txt'),
    ('t', '$_gh/easyprivacy/easyprivacy_trackingservers.txt'),
    ('t', '$_gh/easyprivacy/easyprivacy_thirdparty.txt'),
    ('t', '$_gh/easyprivacy/easyprivacy_general.txt'),
    ('t', '$_gh/easyprivacy/easyprivacy_trackingservers_notifications.txt'),
    ('-', '$_gh/easylist/easylist_allowlist.txt'),
  ];

  ShieldListSet? _current;
  Future<ShieldListSet>? _loading;
  bool _updating = false;
  String? lastUpdateError;

  ShieldListSet? get current => _current;

  /// The app's private support folder (never shared with other apps).
  static Future<Directory> shieldDir() async {
    final base = await getApplicationSupportDirectory();
    return Directory('${base.path}${Platform.pathSeparator}shield');
  }

  static Future<File> _cacheFile() async => File('${(await shieldDir()).path}${Platform.pathSeparator}lists.txt');
  static Future<File> _metaFile() async => File('${(await shieldDir()).path}${Platform.pathSeparator}lists.json');

  /// The newest lists on this phone (downloaded copy, else the bundled snapshot).
  Future<ShieldListSet> load() => _current != null ? Future.value(_current!) : (_loading ??= _load());

  Future<ShieldListSet> _load() async {
    try {
      final cacheFile = await _cacheFile();
      final metaFile = await _metaFile();
      if (await cacheFile.exists() && await metaFile.exists()) {
        final meta = jsonDecode(await metaFile.readAsString());
        final text = await cacheFile.readAsString();
        final rules = await _readCompact(text);
        if (rules.length >= minimumRules && meta is Map) {
          _current = ShieldListSet(rules,
              source: '${meta['source'] ?? 'download'}', updated: DateTime.tryParse('${meta['updated'] ?? ''}'));
          return _current!;
        }
      }
    } catch (_) {}
    final text = await rootBundle.loadString(asset);
    final rules = await _readCompact(text);
    _current = ShieldListSet(rules, source: 'bundled', updated: null);
    return _current!;
  }

  /// When the lists on this phone were downloaded (null = bundled snapshot).
  Future<DateTime?> lastDownload() async {
    try {
      final meta = jsonDecode(await (await _metaFile()).readAsString());
      return meta is Map ? DateTime.tryParse('${meta['updated'] ?? ''}') : null;
    } catch (_) {
      return null;
    }
  }

  bool get updating => _updating;

  /// Downloads fresh lists if the last download is older than a week (or
  /// [force]). Returns the new set, or null when nothing changed.
  Future<ShieldListSet?> updateIfDue({bool force = false}) async {
    if (_updating) return null;
    final last = await lastDownload();
    if (!force && last != null && DateTime.now().difference(last) < updateEvery) return null;
    _updating = true;
    lastUpdateError = null;
    try {
      var (rules, source) = await _download(primary, 'easylist.to');
      if (rules == null || rules.length < minimumRules) {
        (rules, source) = await _download(mirror, 'github');
      }
      if (rules == null || rules.length < minimumRules) {
        lastUpdateError = 'Couldn’t download the lists. The current lists stay in use.';
        return null;
      }
      final now = DateTime.now();
      await (await shieldDir()).create(recursive: true);
      final cacheFile = await _cacheFile();
      final text = await _writeCompact(rules, source);
      final tmp = File('${cacheFile.path}.tmp');
      await tmp.writeAsString(text, flush: true);
      if (await cacheFile.exists()) await cacheFile.delete();
      await tmp.rename(cacheFile.path);
      await (await _metaFile()).writeAsString(jsonEncode({'updated': now.toIso8601String(), 'source': source, 'count': rules.length}));
      _current = ShieldListSet(rules, source: source, updated: now);
      return _current;
    } catch (e) {
      lastUpdateError = 'Update failed: $e';
      return null;
    } finally {
      _updating = false;
    }
  }

  // Isolate helpers: static, and the closures capture only plain data (text,
  // maps) — never a widget, controller or this object.
  static Future<Map<String, String>> _readCompact(String text) => Isolate.run(() => ShieldListParser.readCompact(text));
  static Future<String> _writeCompact(Map<String, String> rules, String source) =>
      Isolate.run(() => ShieldListParser.writeCompact(rules, source: source));
  static Future<Map<String, String>> _combine(List<(String, String)> parts) => Isolate.run(() => ShieldListParser.combine(parts));

  static Future<(Map<String, String>?, String)> _download(List<(String, String)> urls, String source) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..userAgent = 'NOVA-X-Shield/1.0 (+list update)';
    try {
      final parts = <(String, String)>[];
      for (final (cat, url) in urls) {
        try {
          final req = await client.getUrl(Uri.parse(url)).timeout(const Duration(seconds: 20));
          final res = await req.close().timeout(const Duration(seconds: 60));
          if (res.statusCode != 200) {
            await res.drain<void>();
            if (urls == primary) return (null, source); // primary must be complete
            continue;
          }
          final text = await res.transform(utf8.decoder).join().timeout(const Duration(seconds: 120));
          parts.add((cat, text));
        } catch (_) {
          if (urls == primary) return (null, source);
        }
      }
      if (parts.isEmpty) return (null, source);
      // The allowlist ('-') only contributes exceptions; its own block rules are dropped.
      final rules = await _combine(parts);
      rules.removeWhere((_, c) => c == '-');
      return (rules, source);
    } finally {
      client.close(force: true);
    }
  }
}
