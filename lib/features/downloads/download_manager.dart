// lib/features/downloads/download_manager.dart
//
// 3.13.1: NOVA X's download manager — works like Chrome's.
//
//  • Files really download (Dio, streamed) with progress, speed and time left.
//  • Pause / resume (HTTP Range — resumes where it stopped when the server
//    supports it, otherwise starts again), cancel, retry.
//  • When complete the file is saved where the user wants it:
//      – Download/NOVA X on the phone (default, visible in Files / Downloads),
//      – a folder the user picked (any folder, SD card, Drive …),
//      – or "Ask every time".
//    Saving is done by NovaDownloadsBridge.kt (MediaStore / Storage Access
//    Framework), so no broad storage permission is needed.
//  • Progress notifications; tapping one opens the Downloads screen.
//  • The list survives restarts (downloads that were running come back as
//    paused). Incognito downloads are kept off the saved list, like Chrome.
//
// The download is written to the app's private folder first (a ".part"
// file), and only copied out once complete, so a half-finished file never
// appears in the user's Downloads.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:nova_x/core/database/local_db.dart';
import 'download_names.dart';

enum DlStatus { queued, running, paused, saving, completed, failed, canceled }

/// Where completed downloads go.
enum DlDestMode { downloads, folder, ask }

class DownloadTask {
  DownloadTask({
    required this.id,
    required this.url,
    required this.name,
    this.mime = '',
    this.total = -1,
    this.received = 0,
    this.status = DlStatus.queued,
    this.error = '',
    required this.createdAt,
    this.finishedAt,
    this.savedUri = '',
    this.savedLocation = '',
    this.userAgent = '',
    this.referer = '',
    this.dest = 'downloads',
    this.incognito = false,
  });

  final String id;
  final String url;
  String name;
  String mime;

  /// Size in bytes, -1 when the server doesn't say.
  int total;
  int received;
  DlStatus status;
  String error;
  final DateTime createdAt;
  DateTime? finishedAt;

  /// content:// address of the saved file, and a readable place ("Download/NOVA X").
  String savedUri;
  String savedLocation;
  String userAgent;
  String referer;

  /// 'downloads', or a folder (tree) address.
  String dest;
  final bool incognito;

  // Live only.
  double speed = 0; // bytes per second
  CancelToken? _token;
  String _stopReason = '';

  bool get active => status == DlStatus.queued || status == DlStatus.running || status == DlStatus.saving;
  bool get finished => status == DlStatus.completed || status == DlStatus.failed || status == DlStatus.canceled;
  double? get fraction => total > 0 ? (received / total).clamp(0.0, 1.0) : null;
  int get notificationId => 74000 + (id.hashCode & 0x3FFF);

  Map<String, dynamic> toJson() => {
        'id': id,
        'url': url,
        'name': name,
        'mime': mime,
        'total': total,
        'received': received,
        'status': status.name,
        'error': error,
        'createdAt': createdAt.toIso8601String(),
        'finishedAt': finishedAt?.toIso8601String(),
        'savedUri': savedUri,
        'savedLocation': savedLocation,
        'userAgent': userAgent,
        'referer': referer,
        'dest': dest,
      };

  static DownloadTask fromJson(Map<String, dynamic> j) {
    var st = DlStatus.values.firstWhere((s) => s.name == j['status'], orElse: () => DlStatus.failed);
    // Anything that was in progress when NOVA X closed comes back paused.
    if (st == DlStatus.running || st == DlStatus.queued || st == DlStatus.saving) st = DlStatus.paused;
    return DownloadTask(
      id: (j['id'] ?? '').toString(),
      url: (j['url'] ?? '').toString(),
      name: (j['name'] ?? DownloadNames.fallback).toString(),
      mime: (j['mime'] ?? '').toString(),
      total: (j['total'] as num?)?.toInt() ?? -1,
      received: (j['received'] as num?)?.toInt() ?? 0,
      status: st,
      error: (j['error'] ?? '').toString(),
      createdAt: DateTime.tryParse((j['createdAt'] ?? '').toString()) ?? DateTime.now(),
      finishedAt: DateTime.tryParse((j['finishedAt'] ?? '').toString()),
      savedUri: (j['savedUri'] ?? '').toString(),
      savedLocation: (j['savedLocation'] ?? '').toString(),
      userAgent: (j['userAgent'] ?? '').toString(),
      referer: (j['referer'] ?? '').toString(),
      dest: (j['dest'] ?? 'downloads').toString(),
    );
  }
}

/// The native side (android/.../downloads/NovaDownloadsBridge.kt).
class DownloadsPlatform {
  DownloadsPlatform._();
  static const MethodChannel _ch = MethodChannel('com.tlyfe.nova_x/downloads');

  static Future<T?> _call<T>(String method, [Map<String, dynamic>? args]) async {
    try {
      return await _ch.invokeMethod<T>(method, args);
    } on MissingPluginException {
      return null;
    }
  }

  /// Opens the system folder picker. Returns {tree, name} or null.
  static Future<Map<String, String>?> pickFolder() async {
    final r = await _call<Map>('pickFolder');
    if (r == null) return null;
    return {'tree': (r['tree'] ?? '').toString(), 'name': (r['name'] ?? '').toString()};
  }

  static Future<bool> hasFolderAccess(String tree) async =>
      (await _call<bool>('hasFolderAccess', {'tree': tree})) ?? false;

  /// Android 7–9 only: asks for storage permission. True when it's still missing.
  static Future<bool> stillNeedsWritePermission() async => (await _call<bool>('needsWritePermission')) ?? false;

  static Future<Map<String, String>> save({required String path, required String name, required String mime, required String dest}) async {
    final args = <String, dynamic>{'path': path, 'name': name, 'mime': mime};
    Map? r;
    if (dest == 'downloads') {
      r = await _ch.invokeMethod<Map>('saveToDownloads', args);
    } else {
      args['tree'] = dest;
      r = await _ch.invokeMethod<Map>('saveToFolder', args);
    }
    if (r == null) throw StateError('Nothing was saved');
    return {
      'uri': (r['uri'] ?? '').toString(),
      'name': (r['name'] ?? name).toString(),
      'location': (r['location'] ?? '').toString(),
    };
  }

  static Future<bool> open(String uri, String mime) async => (await _call<bool>('open', {'uri': uri, 'mime': mime})) ?? false;
  static Future<bool> share(String uri, String mime) async => (await _call<bool>('share', {'uri': uri, 'mime': mime})) ?? false;
  static Future<bool> openDownloadsApp() async => (await _call<bool>('openDownloadsApp')) ?? false;

  static Future<bool> delete(String uri) async {
    final r = await _call<Map>('delete', {'uri': uri});
    return r?['ok'] == true;
  }

  static Future<bool> exists(String uri) async {
    final r = await _call<Map>('exists', {'uri': uri});
    return r?['ok'] == true;
  }

  static Future<void> notify(int id, String title, String text, {int progress = 0, bool indeterminate = false, bool ongoing = false}) =>
      _call('notify', {
        'id': id,
        'title': title,
        'text': text,
        'progress': progress,
        'indeterminate': indeterminate,
        'ongoing': ongoing,
      });

  static Future<void> cancelNotify(int id) => _call('cancelNotify', {'id': id});
}

class DownloadManager extends ChangeNotifier {
  DownloadManager._();
  static final DownloadManager instance = DownloadManager._();

  static const String _kTasks = 'nx_downloads_v2';
  static const String _kMigrated = 'nx_downloads_v2_migrated';
  static const String _kDestMode = 'nx_dl_dest_mode';
  static const String _kTree = 'nx_dl_tree';
  static const String _kTreeName = 'nx_dl_tree_name';
  static const int maxParallel = 3;

  /// Blob downloads are read through the page; keep them to a sensible size.
  static const int maxInlineBytes = 50 * 1024 * 1024;

  final List<DownloadTask> _tasks = [];
  bool _loaded = false;
  Future<void>? _loading;
  SharedPreferences? _prefs;
  Timer? _saveTimer;
  Directory? _tmpDir;
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 25),
    receiveTimeout: const Duration(seconds: 60),
    followRedirects: true,
    maxRedirects: 10,
  ));

  DlDestMode destMode = DlDestMode.downloads;
  String folderTree = '';
  String folderName = '';

  /// Newest first.
  List<DownloadTask> get tasks => List.unmodifiable(_tasks);
  int get activeCount => _tasks.where((t) => t.active).length;

  /// Human description of where files go.
  String get destinationLabel {
    switch (destMode) {
      case DlDestMode.downloads:
        return 'Download/NOVA X';
      case DlDestMode.folder:
        return folderName.isNotEmpty ? folderName : 'Chosen folder';
      case DlDestMode.ask:
        return 'Ask every time';
    }
  }

  Future<void> ensureLoaded() {
    if (_loaded) return Future.value();
    return _loading ??= _load();
  }

  Future<void> _load() async {
    try {
      final p = _prefs = await SharedPreferences.getInstance();
      destMode = DlDestMode.values.firstWhere((m) => m.name == p.getString(_kDestMode), orElse: () => DlDestMode.downloads);
      folderTree = p.getString(_kTree) ?? '';
      folderName = p.getString(_kTreeName) ?? '';
      if (destMode == DlDestMode.folder && folderTree.isEmpty) destMode = DlDestMode.downloads;
      final raw = p.getString(_kTasks);
      if (raw != null && raw.isNotEmpty) {
        final list = jsonDecode(raw);
        if (list is List) {
          for (final e in list) {
            if (e is Map) {
              try {
                _tasks.add(DownloadTask.fromJson(Map<String, dynamic>.from(e)));
              } catch (_) {}
            }
          }
        }
      }
      // Downloads "captured" by versions before 3.13.1 were never saved:
      // bring them over so they can be downloaded with one tap.
      if (p.getBool(_kMigrated) != true) {
        for (final old in LocalDB.getDownloads()) {
          final url = (old['url'] ?? '').toString();
          if (url.isEmpty || url.startsWith('blob:')) continue;
          _tasks.add(DownloadTask(
            id: _newId(),
            url: url,
            name: DownloadNames.resolve(suggested: (old['filename'] ?? '').toString(), url: url, mime: (old['mime'] ?? '').toString()),
            mime: (old['mime'] ?? '').toString() == 'unknown' ? '' : (old['mime'] ?? '').toString(),
            total: int.tryParse('${old['size'] ?? ''}') ?? -1,
            status: DlStatus.failed,
            error: 'Not downloaded yet. Tap Retry to download it.',
            createdAt: DateTime.tryParse((old['timestamp'] ?? '').toString()) ?? DateTime.now(),
          ));
        }
        await p.setBool(_kMigrated, true);
        await LocalDB.clearDownloads();
      }
      _tasks.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      _persistNow();
    } catch (e) {
      debugPrint('[Downloads] load failed: $e');
    }
    _loaded = true;
    notifyListeners();
  }

  // ── Settings ─────────────────────────────────────────────────────────────

  Future<void> setDestMode(DlDestMode mode) async {
    await ensureLoaded();
    destMode = mode;
    await _prefs?.setString(_kDestMode, mode.name);
    notifyListeners();
  }

  /// Opens the folder picker; true when a folder was chosen.
  Future<bool> chooseFolder() async {
    await ensureLoaded();
    final r = await DownloadsPlatform.pickFolder();
    if (r == null || (r['tree'] ?? '').isEmpty) return false;
    folderTree = r['tree']!;
    folderName = (r['name'] ?? '').isNotEmpty ? r['name']! : 'Chosen folder';
    destMode = DlDestMode.folder;
    await _prefs?.setString(_kTree, folderTree);
    await _prefs?.setString(_kTreeName, folderName);
    await _prefs?.setString(_kDestMode, destMode.name);
    notifyListeners();
    return true;
  }

  /// The destination new downloads use, for the current setting
  /// ('downloads' or a folder address). Null for [DlDestMode.ask].
  String? get defaultDest {
    switch (destMode) {
      case DlDestMode.downloads:
        return 'downloads';
      case DlDestMode.folder:
        return folderTree.isNotEmpty ? folderTree : 'downloads';
      case DlDestMode.ask:
        return null;
    }
  }

  // ── Starting downloads ───────────────────────────────────────────────────

  String _newId() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${Random().nextInt(1 << 20).toRadixString(36)}';

  /// Starts downloading [url]. [dest] is 'downloads' or a folder address.
  Future<DownloadTask> start({
    required String url,
    String? suggestedName,
    String? mime,
    int contentLength = -1,
    String userAgent = '',
    String referer = '',
    required String dest,
    bool incognito = false,
  }) async {
    await ensureLoaded();
    final task = DownloadTask(
      id: _newId(),
      url: url,
      name: DownloadNames.resolve(suggested: suggestedName, url: url, mime: mime),
      mime: (mime ?? '').split(';').first.trim(),
      total: contentLength > 0 ? contentLength : -1,
      createdAt: DateTime.now(),
      userAgent: userAgent,
      referer: referer,
      dest: dest,
      incognito: incognito,
    );
    _tasks.insert(0, task);
    _changed(persist: true);
    _pump();
    return task;
  }

  /// Saves bytes the page already has (data: and blob: links).
  Future<DownloadTask> startBytes({
    required Uint8List bytes,
    String? suggestedName,
    String? mime,
    String sourceUrl = '',
    required String dest,
    bool incognito = false,
  }) async {
    await ensureLoaded();
    final shownUrl = sourceUrl.startsWith('data:') ? 'data:${mime ?? ''}' : sourceUrl;
    final task = DownloadTask(
      id: _newId(),
      url: shownUrl,
      name: DownloadNames.resolve(suggested: suggestedName, url: sourceUrl, mime: mime),
      mime: (mime ?? '').split(';').first.trim(),
      total: bytes.length,
      received: bytes.length,
      status: DlStatus.saving,
      createdAt: DateTime.now(),
      dest: dest,
      incognito: incognito,
    );
    _tasks.insert(0, task);
    _changed(persist: true);
    try {
      final f = await _partFile(task);
      await f.writeAsBytes(bytes, flush: true);
      await _saveOut(task, f);
    } catch (e) {
      _fail(task, 'Couldn\'t save the file: ${_short(e)}');
    }
    return task;
  }

  // ── Controls ─────────────────────────────────────────────────────────────

  DownloadTask? byId(String id) {
    for (final t in _tasks) {
      if (t.id == id) return t;
    }
    return null;
  }

  void pause(DownloadTask t) {
    if (t.status == DlStatus.queued) {
      t.status = DlStatus.paused;
      t.speed = 0;
      _changed(persist: true);
      return;
    }
    if (t.status != DlStatus.running) return;
    t._stopReason = 'pause';
    t._token?.cancel('pause');
  }

  void resume(DownloadTask t) {
    if (t.status != DlStatus.paused && t.status != DlStatus.failed) return;
    if (t.url.startsWith('data:') || t.url.startsWith('blob:')) {
      t.error = 'This download came from the page itself. Download it again from the page.';
      _changed();
      return;
    }
    t.status = DlStatus.queued;
    t.error = '';
    _changed(persist: true);
    _pump();
  }

  /// Retry = resume for downloads that stopped; a finished download whose
  /// file is still waiting to be saved is just saved again.
  void retry(DownloadTask t) => resume(t);

  Future<void> cancel(DownloadTask t) async {
    if (t.status == DlStatus.running) {
      t._stopReason = 'cancel';
      t._token?.cancel('cancel');
      return;
    }
    if (t.finished && t.status != DlStatus.failed) return;
    t.status = DlStatus.canceled;
    t.speed = 0;
    t.finishedAt = DateTime.now();
    await _deletePart(t);
    unawaited(DownloadsPlatform.cancelNotify(t.notificationId));
    _changed(persist: true);
    _pump();
  }

  /// Removes the entry from the list (the saved file stays, like Chrome).
  Future<void> remove(DownloadTask t) async {
    if (t.status == DlStatus.running) {
      t._stopReason = 'remove';
      t._token?.cancel('remove');
    }
    _tasks.remove(t);
    await _deletePart(t);
    unawaited(DownloadsPlatform.cancelNotify(t.notificationId));
    _changed(persist: true);
    _pump();
  }

  /// Deletes the saved file from the phone and removes the entry.
  Future<bool> deleteFile(DownloadTask t) async {
    var ok = true;
    if (t.savedUri.isNotEmpty) ok = await DownloadsPlatform.delete(t.savedUri);
    await remove(t);
    return ok;
  }

  /// Clears finished entries (files stay on the phone).
  Future<void> clearFinished() async {
    await ensureLoaded();
    final gone = _tasks.where((t) => t.finished || t.status == DlStatus.paused).toList();
    for (final t in gone) {
      _tasks.remove(t);
      await _deletePart(t);
      unawaited(DownloadsPlatform.cancelNotify(t.notificationId));
    }
    _changed(persist: true);
  }

  /// "Clear browsing data → Downloads": stops everything and clears the list.
  Future<void> clearAll() async {
    await ensureLoaded();
    for (final t in List<DownloadTask>.from(_tasks)) {
      if (t.status == DlStatus.running) {
        t._stopReason = 'remove';
        t._token?.cancel('remove');
      }
      await _deletePart(t);
      unawaited(DownloadsPlatform.cancelNotify(t.notificationId));
    }
    _tasks.clear();
    _changed(persist: true);
  }

  // ── Engine ───────────────────────────────────────────────────────────────

  void _pump() {
    var running = _tasks.where((t) => t.status == DlStatus.running).length;
    // Oldest queued first.
    for (final t in _tasks.reversed) {
      if (running >= maxParallel) break;
      if (t.status == DlStatus.queued) {
        running++;
        unawaited(_run(t));
      }
    }
  }

  Future<Directory> _tmp() async {
    if (_tmpDir != null) return _tmpDir!;
    final base = await getApplicationSupportDirectory();
    final d = Directory('${base.path}${Platform.pathSeparator}downloads_tmp');
    if (!d.existsSync()) d.createSync(recursive: true);
    return _tmpDir = d;
  }

  Future<File> _partFile(DownloadTask t) async => File('${(await _tmp()).path}${Platform.pathSeparator}${t.id}.part');

  Future<void> _deletePart(DownloadTask t) async {
    try {
      final f = await _partFile(t);
      if (f.existsSync()) await f.delete();
    } catch (_) {}
  }

  Future<String> _cookiesFor(String url) async {
    try {
      final list = await CookieManager.instance().getCookies(url: WebUri(url));
      return list.map((c) => '${c.name}=${c.value}').join('; ');
    } catch (_) {
      return '';
    }
  }

  Future<void> _run(DownloadTask t) async {
    t.status = DlStatus.running;
    t.error = '';
    t.speed = 0;
    t._stopReason = '';
    final token = t._token = CancelToken();
    _changed(persist: true);
    _notifyProgress(t, force: true);

    RandomAccessFile? raf;
    try {
      final part = await _partFile(t);
      var have = part.existsSync() ? part.lengthSync() : 0;
      // Already fully downloaded (e.g. only the saving step failed before).
      if (t.total > 0 && have >= t.total) {
        t.received = have;
        await _saveOut(t, part);
        return;
      }
      final headers = <String, dynamic>{
        'Accept': '*/*',
        'Accept-Encoding': 'identity',
      };
      if (t.userAgent.isNotEmpty) headers['User-Agent'] = t.userAgent;
      if (t.referer.isNotEmpty && t.referer.startsWith('http')) headers['Referer'] = t.referer;
      final cookies = await _cookiesFor(t.url);
      if (cookies.isNotEmpty) headers['Cookie'] = cookies;
      if (have > 0) headers['Range'] = 'bytes=$have-';

      final resp = await _dio.get<ResponseBody>(
        t.url,
        cancelToken: token,
        options: Options(
          responseType: ResponseType.stream,
          headers: headers,
          validateStatus: (s) => s != null && s < 400,
        ),
      );
      final code = resp.statusCode ?? 200;
      if (code == 206) {
        final full = DownloadNames.totalFromContentRange(resp.headers.value('content-range'));
        if (full > 0) t.total = full;
      } else {
        // The server ignored the range (or this is a fresh start): start over.
        have = 0;
        final len = int.tryParse(resp.headers.value('content-length') ?? '') ?? -1;
        if (len > 0) t.total = len;
        // Learn the real name/type now, before any byte is written.
        final type = resp.headers.value('content-type') ?? '';
        if (t.mime.isEmpty && type.isNotEmpty && !type.startsWith('text/html')) t.mime = type.split(';').first.trim();
        final disposition = DownloadNames.fromContentDisposition(resp.headers.value('content-disposition'));
        if (disposition != null && t.received == 0 && (t.name == DownloadNames.fallback || !t.name.contains('.'))) {
          t.name = disposition;
        } else if (!t.name.contains('.')) {
          t.name = DownloadNames.resolve(suggested: t.name, url: t.url, mime: t.mime);
        }
      }
      t.received = have;
      raf = await part.open(mode: have > 0 ? FileMode.append : FileMode.write);
      if (have == 0) await raf.truncate(0);

      final sw = Stopwatch()..start();
      var lastTick = 0;
      var windowBytes = 0;
      var windowStart = 0;
      await for (final chunk in resp.data!.stream) {
        await raf.writeFrom(chunk);
        t.received += chunk.length;
        windowBytes += chunk.length;
        final now = sw.elapsedMilliseconds;
        if (now - windowStart >= 1000) {
          final inst = windowBytes * 1000 / (now - windowStart);
          t.speed = t.speed == 0 ? inst : t.speed * 0.6 + inst * 0.4;
          windowBytes = 0;
          windowStart = now;
        }
        if (now - lastTick >= 300) {
          lastTick = now;
          _changed();
          _notifyProgress(t);
        }
      }
      await raf.flush();
      await raf.close();
      raf = null;
      if (t.total <= 0) t.total = t.received;
      if (t.received < t.total) {
        throw const HttpException('The connection closed before the file finished');
      }
      await _saveOut(t, part);
    } on DioException catch (e) {
      await raf?.close();
      raf = null;
      if (CancelToken.isCancel(e)) {
        await _stopped(t);
      } else {
        final code = e.response?.statusCode;
        if (code == 416) {
          // Range not satisfiable: the part file is stale. Start over next time.
          await _deletePart(t);
          t.received = 0;
        }
        _fail(t, _dioMessage(e));
      }
    } catch (e) {
      try {
        await raf?.close();
      } catch (_) {}
      raf = null;
      if (t._stopReason.isNotEmpty) {
        await _stopped(t);
      } else {
        _fail(t, _short(e));
      }
    } finally {
      t._token = null;
      _pump();
    }
  }

  Future<void> _stopped(DownloadTask t) async {
    t.speed = 0;
    switch (t._stopReason) {
      case 'cancel':
        t.status = DlStatus.canceled;
        t.finishedAt = DateTime.now();
        await _deletePart(t);
        unawaited(DownloadsPlatform.cancelNotify(t.notificationId));
        break;
      case 'remove':
        await _deletePart(t);
        unawaited(DownloadsPlatform.cancelNotify(t.notificationId));
        break;
      default:
        t.status = DlStatus.paused;
        unawaited(DownloadsPlatform.notify(t.notificationId, t.name, 'Paused · ${_progressText(t)}'));
    }
    t._stopReason = '';
    _changed(persist: true);
  }

  Future<void> _saveOut(DownloadTask t, File part) async {
    t.status = DlStatus.saving;
    t.speed = 0;
    _changed(persist: true);
    unawaited(DownloadsPlatform.notify(t.notificationId, t.name, 'Saving…', indeterminate: true, ongoing: true));
    try {
      if (t.mime.isEmpty) t.mime = DownloadNames.mimeForName(t.name) ?? '';
      var dest = t.dest.isEmpty ? 'downloads' : t.dest;
      if (dest != 'downloads' && !await DownloadsPlatform.hasFolderAccess(dest)) {
        // The chosen folder is gone or access was removed: use Downloads.
        dest = 'downloads';
      }
      if (dest == 'downloads' && await DownloadsPlatform.stillNeedsWritePermission()) {
        throw StateError('NOVA X needs storage permission to save to Downloads on this Android version');
      }
      final r = await DownloadsPlatform.save(path: part.path, name: t.name, mime: t.mime, dest: dest);
      t.savedUri = r['uri'] ?? '';
      t.name = (r['name'] ?? '').isNotEmpty ? r['name']! : t.name;
      t.savedLocation = r['location'] ?? '';
      t.dest = dest;
      t.status = DlStatus.completed;
      t.finishedAt = DateTime.now();
      t.error = '';
      await _deletePart(t);
      unawaited(DownloadsPlatform.notify(t.notificationId, 'Download complete',
          '${t.name}${t.savedLocation.isNotEmpty ? ' · ${t.savedLocation}' : ''}'));
      _changed(persist: true);
    } on PlatformException catch (e) {
      _fail(t, 'Couldn\'t save the file: ${e.message ?? e.code}');
    } catch (e) {
      _fail(t, 'Couldn\'t save the file: ${_short(e)}');
    }
  }

  void _fail(DownloadTask t, String message) {
    t.status = DlStatus.failed;
    t.error = message;
    t.speed = 0;
    t.finishedAt = DateTime.now();
    unawaited(DownloadsPlatform.notify(t.notificationId, 'Download failed', '${t.name} · $message'));
    _changed(persist: true);
  }

  String _progressText(DownloadTask t) {
    if (t.total > 0) return '${DownloadNames.size(t.received)} of ${DownloadNames.size(t.total)}';
    return DownloadNames.size(t.received);
  }

  final Map<String, int> _lastNotified = {};

  void _notifyProgress(DownloadTask t, {bool force = false}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!force && now - (_lastNotified[t.id] ?? 0) < 1000) return;
    _lastNotified[t.id] = now;
    final pct = t.fraction == null ? 0 : (t.fraction! * 100).round();
    final left = t.total > 0 ? DownloadNames.timeLeft(t.total - t.received, t.speed) : '';
    unawaited(DownloadsPlatform.notify(
      t.notificationId,
      t.name,
      [_progressText(t), if (left.isNotEmpty) left].join(' · '),
      progress: pct,
      indeterminate: t.total <= 0,
      ongoing: true,
    ));
  }

  String _dioMessage(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.sendTimeout:
        return 'Network timed out. Tap Retry to continue.';
      case DioExceptionType.connectionError:
        return 'No connection. Tap Retry when you\'re back online.';
      case DioExceptionType.badResponse:
        final c = e.response?.statusCode ?? 0;
        if (c == 401 || c == 403) return 'The site refused the download ($c). Try again from the page.';
        if (c == 404 || c == 410) return 'The file is no longer on the server ($c).';
        if (c == 416) return 'The download has to start again. Tap Retry.';
        return 'Server error ($c). Tap Retry.';
      default:
        return 'Download stopped: ${_short(e.message ?? e.error ?? e)}';
    }
  }

  String _short(Object e) {
    var s = e.toString();
    s = s.replaceFirst(RegExp(r'^(Exception|StateError|Bad state|HttpException|FileSystemException):\s*'), '');
    return s.length > 160 ? '${s.substring(0, 160)}…' : s;
  }

  // ── Change + persistence ─────────────────────────────────────────────────

  void _changed({bool persist = false}) {
    notifyListeners();
    if (persist) {
      _persistSoon();
    }
  }

  void _persistSoon() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), _persistNow);
  }

  void _persistNow() {
    _saveTimer?.cancel();
    final p = _prefs;
    if (p == null) return;
    final keep = _tasks.where((t) => !t.incognito).take(200).map((t) => t.toJson()).toList();
    unawaited(p.setString(_kTasks, jsonEncode(keep)));
  }

  /// For tests.
  @visibleForTesting
  void debugReset() {
    _tasks.clear();
    _loaded = false;
    _loading = null;
  }
}
