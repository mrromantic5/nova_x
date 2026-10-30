// lib/core/services/offline_cache.dart
//
// Offline support for the home screen (3.11.0).
//
//  - Images (Quick Access icons, news pictures) are kept on the phone after
//    the first download, so they appear instantly and without internet.
//    Stored in the app cache folder; Android may clear it when space is low,
//    and NOVA X keeps it under ~40 MB itself (oldest first).
//  - Small JSON snapshots (last news per category, last coin balance) are
//    kept with the time they were saved, so the app can say "saved 2 h ago".
//
// Nothing here is uploaded; it is a local copy of what the app already showed.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OfflineCache {
  OfflineCache._();

  static const int _maxImageBytes = 3 * 1024 * 1024;
  static const int _maxTotalBytes = 40 * 1024 * 1024;
  static const Duration _refreshAfter = Duration(days: 7);

  static Directory? _dir;
  static final Map<String, Future<Uint8List?>> _inFlight = {};
  static final Map<String, Uint8List> _memory = {};
  static const int _memoryMax = 160;
  static int _writes = 0;

  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 15),
    responseType: ResponseType.bytes,
    followRedirects: true,
    validateStatus: (s) => s != null && s >= 200 && s < 300,
  ));

  static Future<Directory> _images() async {
    final d = _dir ??= Directory('${(await getTemporaryDirectory()).path}/nx_offline_images');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  /// FNV-1a 64-bit of the URL → file name (no crypto package needed).
  static String keyFor(String url) {
    // 64-bit arithmetic wraps on the Dart VM, as FNV needs.
    var h = 0xcbf29ce484222325;
    const prime = 0x100000001b3;
    for (final c in utf8.encode(url)) {
      h ^= c;
      h *= prime;
    }
    final hi = (h >> 32) & 0xFFFFFFFF, lo = h & 0xFFFFFFFF;
    return hi.toRadixString(16).padLeft(8, '0') + lo.toRadixString(16).padLeft(8, '0');
  }

  /// Bytes from memory or disk at once (null when not saved yet).
  static Uint8List? peek(String url) => _memory[url];

  /// The image for [url]: memory → disk → network (then saved). Null when
  /// there is no saved copy and the phone is offline.
  static Future<Uint8List?> image(String url) {
    if (url.isEmpty || !(url.startsWith('https://') || url.startsWith('http://'))) return Future.value(null);
    final hit = _memory[url];
    if (hit != null) return Future.value(hit);
    return _inFlight[url] ??= _load(url).whenComplete(() => _inFlight.remove(url));
  }

  static Future<Uint8List?> _load(String url) async {
    File? file;
    try {
      file = File('${(await _images()).path}/${keyFor(url)}');
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        _remember(url, bytes);
        // Old copy: refresh quietly in the background (keeps the old one if offline).
        final age = DateTime.now().difference(await file.lastModified());
        if (age > _refreshAfter) _download(url, file);
        return bytes;
      }
    } catch (_) {}
    return file == null ? null : _download(url, file);
  }

  static Future<Uint8List?> _download(String url, File file) async {
    try {
      final r = await _dio.get<List<int>>(url);
      final data = r.data;
      if (data == null || data.isEmpty || data.length > _maxImageBytes) return null;
      final bytes = Uint8List.fromList(data);
      if (!_looksLikeImage(bytes)) return null;
      await file.writeAsBytes(bytes, flush: false);
      _remember(url, bytes);
      if (++_writes % 25 == 0) _trim();
      return bytes;
    } catch (_) {
      return null;
    }
  }

  static bool _looksLikeImage(Uint8List b) {
    if (b.length < 4) return false;
    final png = b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47;
    final jpg = b[0] == 0xFF && b[1] == 0xD8;
    final gif = b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46;
    final webp = b.length > 12 && b[0] == 0x52 && b[1] == 0x49 && b[8] == 0x57 && b[9] == 0x45;
    final ico = b[0] == 0x00 && b[1] == 0x00 && (b[2] == 0x01 || b[2] == 0x02);
    final svg = utf8.decode(b.sublist(0, b.length < 200 ? b.length : 200), allowMalformed: true).contains('<svg');
    return png || jpg || gif || webp || ico || svg;
  }

  static void _remember(String url, Uint8List bytes) {
    if (_memory.length >= _memoryMax) _memory.remove(_memory.keys.first);
    _memory[url] = bytes;
  }

  static Future<void> _trim() async {
    try {
      final files = (await _images()).listSync().whereType<File>().toList();
      var total = 0;
      final stats = <File, FileStat>{};
      for (final f in files) {
        final st = f.statSync();
        stats[f] = st;
        total += st.size;
      }
      if (total <= _maxTotalBytes) return;
      files.sort((a, b) => stats[a]!.modified.compareTo(stats[b]!.modified));
      for (final f in files) {
        if (total <= _maxTotalBytes * 0.8) break;
        total -= stats[f]!.size;
        try { f.deleteSync(); } catch (_) {}
      }
    } catch (_) {}
  }

  // ── JSON snapshots ──────────────────────────────────────────────────────

  /// Saves [value] (anything jsonEncode accepts) under [key] with the time.
  static Future<void> putJson(String key, Object? value) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('nx_offline_$key', jsonEncode({'at': DateTime.now().millisecondsSinceEpoch, 'v': value}));
    } catch (_) {}
  }

  /// (value, savedAt) or null.
  static Future<(Object?, DateTime)?> getJson(String key) async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString('nx_offline_$key');
      if (raw == null) return null;
      final m = jsonDecode(raw);
      if (m is! Map || m['at'] is! int) return null;
      return (m['v'], DateTime.fromMillisecondsSinceEpoch(m['at'] as int));
    } catch (_) {
      return null;
    }
  }

  static Future<void> remove(String key) async {
    try {
      (await SharedPreferences.getInstance()).remove('nx_offline_$key');
    } catch (_) {}
  }

  /// "just now", "5 min ago", "3 h ago", "2 days ago".
  static String age(DateTime at) {
    final d = DateTime.now().difference(at);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours} h ago';
    return '${d.inDays} day${d.inDays == 1 ? '' : 's'} ago';
  }
}

/// Network image that is kept on the phone, so it also shows offline.
class CachedNetImage extends StatefulWidget {
  const CachedNetImage(
    this.url, {
    super.key,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.fallback,
    this.semanticLabel,
  });

  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;

  /// Shown while loading and when there is no copy (e.g. first time offline).
  final Widget? fallback;
  final String? semanticLabel;

  @override
  State<CachedNetImage> createState() => _CachedNetImageState();
}

class _CachedNetImageState extends State<CachedNetImage> {
  Uint8List? _bytes;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(CachedNetImage old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) {
      _bytes = null;
      _failed = false;
      _start();
    }
  }

  void _start() {
    final hit = OfflineCache.peek(widget.url);
    if (hit != null) {
      _bytes = hit;
      return;
    }
    OfflineCache.image(widget.url).then((b) {
      if (!mounted) return;
      setState(() {
        _bytes = b;
        _failed = b == null;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final b = _bytes;
    final fallback = widget.fallback ?? SizedBox(width: widget.width, height: widget.height);
    if (b == null) return fallback;
    return Image.memory(
      b,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      gaplessPlayback: true,
      semanticLabel: widget.semanticLabel,
      excludeFromSemantics: widget.semanticLabel == null,
      errorBuilder: (_, __, ___) => fallback,
    );
  }

  bool get failed => _failed;
}
