// lib/features/nova_capture/services/media_library_service.dart
//
// The NOVA Capture library: the files themselves live in MediaStore (see
// CaptureMediaRepository.kt); this keeps the small, local-only extras —
// favourites, folders (categories) and, only when the user turned it on, the
// page title/address of webpage screenshots. Nothing here leaves the phone.

import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/capture_settings.dart';
import '../models/media_asset.dart';
import 'capture_platform.dart';

enum MediaSort { newest, oldest, name, size }

enum MediaFilter { all, screenshots, recordings, favorites }

class MediaLibraryQuery {
  const MediaLibraryQuery({
    this.sort = MediaSort.newest,
    this.filter = MediaFilter.all,
    this.search = '',
    this.category,
  });

  final MediaSort sort;
  final MediaFilter filter;
  final String search;

  /// Only items in this folder (null = every folder).
  final String? category;

  MediaLibraryQuery copyWith({MediaSort? sort, MediaFilter? filter, String? search, String? category, bool clearCategory = false}) =>
      MediaLibraryQuery(
        sort: sort ?? this.sort,
        filter: filter ?? this.filter,
        search: search ?? this.search,
        category: clearCategory ? null : (category ?? this.category),
      );
}

/// Pure filtering/sorting (unit-tested).
class MediaLibrary {
  MediaLibrary._();

  static List<MediaAsset> apply(
    List<MediaAsset> items,
    MediaLibraryQuery q, {
    Set<String> favorites = const {},
    Map<String, String> categories = const {},
  }) {
    final search = q.search.trim().toLowerCase();
    final out = items.where((a) {
      switch (q.filter) {
        case MediaFilter.screenshots:
          if (!a.isImage) return false;
        case MediaFilter.recordings:
          if (!a.isVideo) return false;
        case MediaFilter.favorites:
          if (!favorites.contains(a.uri)) return false;
        case MediaFilter.all:
          break;
      }
      if (q.category != null && categories[a.uri] != q.category) return false;
      if (search.isNotEmpty) {
        final hay = '${a.name.toLowerCase()} ${_dateText(a.created)}';
        if (!hay.contains(search)) return false;
      }
      return true;
    }).toList();
    int byNewest(MediaAsset a, MediaAsset b) {
      final c = b.createdMs.compareTo(a.createdMs);
      return c != 0 ? c : a.name.compareTo(b.name);
    }

    switch (q.sort) {
      case MediaSort.newest:
        out.sort(byNewest);
      case MediaSort.oldest:
        out.sort((a, b) => -byNewest(a, b));
      case MediaSort.name:
        out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      case MediaSort.size:
        out.sort((a, b) {
          final c = b.sizeBytes.compareTo(a.sizeBytes);
          return c != 0 ? c : byNewest(a, b);
        });
    }
    return out;
  }

  /// Searchable date text: "2026-10-27 27 oct 2026 october".
  static String _dateText(DateTime t) {
    const months = ['january', 'february', 'march', 'april', 'may', 'june', 'july', 'august',
      'september', 'october', 'november', 'december'];
    final m = months[t.month - 1];
    final mm = t.month.toString().padLeft(2, '0');
    final dd = t.day.toString().padLeft(2, '0');
    return '${t.year}-$mm-$dd ${t.day} ${m.substring(0, 3)} ${t.year} $m';
  }

  static int totalBytes(Iterable<MediaAsset> items) => items.fold(0, (s, a) => s + a.sizeBytes);

  /// Folder names: trimmed, 1–24 characters, letters/numbers/spaces.
  static String? cleanCategory(String raw) {
    final t = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (t.isEmpty || t.length > 24) return null;
    if (!RegExp(r"^[\p{L}\p{N} _'&-]+$", unicode: true).hasMatch(t)) return null;
    return t;
  }
}

/// Webpage title/address kept with a screenshot (only when the user allows it).
class WebMetadata {
  const WebMetadata(this.title, this.url);
  final String title;
  final String url;
}

class MediaLibraryService {
  MediaLibraryService({CapturePlatform? platform}) : _platform = platform ?? CapturePlatform.instance;

  static final MediaLibraryService instance = MediaLibraryService();

  static const _kFav = 'nx_capture_favorites';
  static const _kCat = 'nx_capture_categories';
  static const _kFolders = 'nx_capture_folders';
  static const _kMeta = 'nx_capture_web_meta';
  static const _kRec = 'nx_capture_rec_settings';
  static const _kShot = 'nx_capture_shot_settings';
  static const _kIntro = 'nx_capture_intro_seen';

  final CapturePlatform _platform;
  Set<String> favorites = {};
  Map<String, String> categories = {};
  List<String> folders = [];
  Map<String, Map<String, String>> _meta = {};
  bool _loaded = false;

  final Map<String, Uint8List> _thumbs = {};
  static const _maxThumbs = 120;

  Future<SharedPreferences?> _prefs() async {
    try {
      return await SharedPreferences.getInstance();
    } catch (_) {
      return null;
    }
  }

  Future<void> load() async {
    if (_loaded) return;
    final p = await _prefs();
    _loaded = true;
    if (p == null) return;
    favorites = (p.getStringList(_kFav) ?? const []).toSet();
    folders = p.getStringList(_kFolders) ?? <String>[];
    try {
      final c = jsonDecode(p.getString(_kCat) ?? '{}');
      if (c is Map) categories = {for (final e in c.entries) if (e.key is String && e.value is String) e.key as String: e.value as String};
    } catch (_) {}
    try {
      final m = jsonDecode(p.getString(_kMeta) ?? '{}');
      if (m is Map) {
        _meta = {
          for (final e in m.entries)
            if (e.key is String && e.value is Map)
              e.key as String: {
                for (final f in (e.value as Map).entries)
                  if (f.key is String && f.value is String) f.key as String: f.value as String,
              },
        };
      }
    } catch (_) {}
  }

  Future<void> _save() async {
    final p = await _prefs();
    if (p == null) return;
    await p.setStringList(_kFav, favorites.toList());
    await p.setStringList(_kFolders, folders);
    await p.setString(_kCat, jsonEncode(categories));
    await p.setString(_kMeta, jsonEncode(_meta));
  }

  // ── Settings ────────────────────────────────────────────────────────────

  Future<RecordingSettings> loadRecordingSettings() async =>
      RecordingSettings.fromJson((await _prefs())?.getString(_kRec));

  Future<void> saveRecordingSettings(RecordingSettings s) async => (await _prefs())?.setString(_kRec, s.toJson());

  Future<ScreenshotSettings> loadScreenshotSettings() async =>
      ScreenshotSettings.fromJson((await _prefs())?.getString(_kShot));

  Future<void> saveScreenshotSettings(ScreenshotSettings s) async => (await _prefs())?.setString(_kShot, s.toJson());

  /// True once the user has seen the "how NOVA Capture works" explanation.
  Future<bool> introSeen() async => (await _prefs())?.getBool(_kIntro) ?? false;
  Future<void> markIntroSeen() async => (await _prefs())?.setBool(_kIntro, true);

  // ── Items ───────────────────────────────────────────────────────────────

  Future<List<MediaAsset>> list() async {
    await load();
    final items = await _platform.listMedia();
    // Forget extras for files that are gone (deleted in the Gallery, etc.).
    final live = items.map((e) => e.uri).toSet();
    final before = favorites.length + categories.length + _meta.length;
    favorites.removeWhere((u) => !live.contains(u));
    categories.removeWhere((u, _) => !live.contains(u));
    _meta.removeWhere((u, _) => !live.contains(u));
    if (items.isNotEmpty && favorites.length + categories.length + _meta.length != before) await _save();
    return items;
  }

  Future<MediaAsset?> latest({MediaKind? kind}) async {
    final items = await list();
    final pool = kind == null ? items : items.where((a) => a.kind == kind).toList();
    if (pool.isEmpty) return null;
    return MediaLibrary.apply(pool, const MediaLibraryQuery()).first;
  }

  bool isFavorite(String uri) => favorites.contains(uri);

  Future<void> setFavorite(String uri, bool on) async {
    await load();
    if (on) {
      favorites.add(uri);
    } else {
      favorites.remove(uri);
    }
    await _save();
  }

  Future<bool> addFolder(String raw) async {
    await load();
    final name = MediaLibrary.cleanCategory(raw);
    if (name == null) return false;
    if (!folders.contains(name)) folders.add(name);
    await _save();
    return true;
  }

  Future<void> setCategory(String uri, String? folder) async {
    await load();
    if (folder == null) {
      categories.remove(uri);
    } else if (folders.contains(folder)) {
      categories[uri] = folder;
    }
    await _save();
  }

  Future<void> removeFolder(String folder) async {
    await load();
    folders.remove(folder);
    categories.removeWhere((_, f) => f == folder);
    await _save();
  }

  WebMetadata? metadataFor(String uri) {
    final m = _meta[uri];
    if (m == null) return null;
    return WebMetadata(m['title'] ?? '', m['url'] ?? '');
  }

  Future<void> setMetadata(String uri, String title, String url) async {
    await load();
    _meta[uri] = {
      'title': title.length > 200 ? title.substring(0, 200) : title,
      'url': url.length > 500 ? url.substring(0, 500) : url,
    };
    await _save();
  }

  /// Removes the local extras after a delete.
  Future<void> forget(String uri) async {
    await load();
    favorites.remove(uri);
    categories.remove(uri);
    _meta.remove(uri);
    _thumbs.removeWhere((k, _) => k.startsWith('$uri|'));
    await _save();
  }

  /// Removes every stored page title/address (when the user turns the setting off).
  Future<void> clearAllMetadata() async {
    await load();
    _meta.clear();
    await _save();
  }

  Future<Uint8List?> thumbnail(MediaAsset a) async {
    final key = '${a.uri}|${a.sizeBytes}';
    final hit = _thumbs[key];
    if (hit != null) return hit;
    final bytes = await _platform.thumbnail(a.uri, size: 360);
    if (bytes != null) {
      if (_thumbs.length >= _maxThumbs) _thumbs.remove(_thumbs.keys.first);
      _thumbs[key] = bytes;
    }
    return bytes;
  }
}
