// lib/features/ai/services/nova_chat_repository.dart
//
// NOVA AI chat history: saved on the phone first (works offline), then kept
// in sync with the NOVA X server for signed-in users, so they find their
// chats on any phone they log in to. Guests keep their chats on this phone;
// when they sign in, those chats move into their account.
//
// One shared repository per account (all NOVA AI screens use the same one),
// so two open chat screens never overwrite each other's history.

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:nova_x/core/services/api_service.dart';

import 'nova_chat_api.dart';
import 'nova_chat_models.dart';
import 'nova_chat_store.dart';

class NovaChatRepository extends ChangeNotifier {
  NovaChatRepository._(this._store, this._api);

  // ── Opening ──────────────────────────────────────────────────────────────

  static NovaChatRepository? _shared;
  static Future<NovaChatRepository>? _opening;
  static String? _openingKey;

  /// The history of whoever is using NOVA X right now (shared instance).
  /// Throws when the phone's storage can't be used.
  static Future<NovaChatRepository> open() async {
    final key = await _currentAccountKey();
    final shared = _shared;
    if (shared != null && shared.accountKey == key) return shared;
    final opening = _opening;
    if (opening != null && _openingKey == key) return opening;
    final future = _create(key);
    _opening = future;
    _openingKey = key;
    try {
      final repo = await future;
      final old = _shared;
      _shared = repo;
      if (old != null && !identical(old, repo)) old._retire();
      return repo;
    } finally {
      if (identical(_opening, future)) {
        _opening = null;
        _openingKey = null;
      }
    }
  }

  static Future<String> _currentAccountKey() async {
    final token = await ApiService.getToken();
    final user = await ApiService.getCachedUser();
    final id = user == null ? null : user['id'];
    final signedIn = token != null && token.isNotEmpty && id != null && '$id'.isNotEmpty;
    return signedIn ? 'u$id' : NovaChatStore.guestKey;
  }

  static Future<NovaChatRepository> _create(String key) async {
    final store = await NovaChatStore.open(key);
    final signedIn = key != NovaChatStore.guestKey;
    if (signedIn) {
      try {
        await store.adoptGuestChats();
      } catch (_) {
        // the guest chats stay where they are
      }
    }
    return NovaChatRepository._(store, signedIn ? NovaChatApi() : null);
  }

  // ── Limits ───────────────────────────────────────────────────────────────

  /// The server keeps at most this many messages per chat (the latest).
  static const int maxMessagesPerChat = 400;
  static const int maxTitleLength = 120;

  /// The server refuses chats larger than 900 KB; older messages are left
  /// out of the upload above this size (they stay on this phone).
  static const int maxUploadBytes = 800000;

  // ── State ────────────────────────────────────────────────────────────────

  final NovaChatStore _store;
  NovaChatApi? _api;
  final Set<String> _toUpload = {};
  Timer? _uploadTimer;
  bool _syncing = false;
  bool _retired = false;
  NovaChatSyncProblem? _problem;

  String get accountKey => _store.accountKey;

  /// Chats are kept on the server (signed in) or only on this phone (guest).
  bool get signedIn => _store.accountKey != NovaChatStore.guestKey;
  bool get syncing => _syncing;

  /// Why the last server sync didn't work (null when fine).
  NovaChatSyncProblem? get problem => _problem;

  /// Newest first.
  List<NovaChatMeta> get chats =>
      List<NovaChatMeta>.of(_store.chats)..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  NovaChatMeta? find(String id) => _store.find(id);

  static String newChatId() {
    final r = Random();
    final suffix = List.generate(6, (_) => r.nextInt(16).toRadixString(16)).join();
    return 'chat_${DateTime.now().millisecondsSinceEpoch}_$suffix';
  }

  /// A short title from the first message.
  static String titleFrom(String text) {
    var t = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    final lower = t.toLowerCase();
    if (lower.startsWith('/image ')) t = 'Image: ${t.substring(7).trim()}';
    if (lower.startsWith('/video ')) t = 'Video: ${t.substring(7).trim()}';
    if (t.isEmpty) return 'New chat';
    return t.length > 48 ? '${t.substring(0, 47).trimRight()}…' : t;
  }

  static String cleanTitle(String title) {
    final t = title
        .replaceAll(RegExp(r'[\u0000-\u001F\u007F]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (t.isEmpty) return 'New chat';
    return t.length > maxTitleLength ? t.substring(0, maxTitleLength).trimRight() : t;
  }

  /// The latest messages that fit the server's limits.
  static List<Map<String, String>> forUpload(List<Map<String, String>> messages) {
    var start = messages.length > maxMessagesPerChat ? messages.length - maxMessagesPerChat : 0;
    var list = messages.sublist(start);
    while (list.length > 1 && utf8.encode(jsonEncode(list)).length > maxUploadBytes) {
      final step = list.length ~/ 10;
      start += step < 1 ? 1 : step;
      list = messages.sublist(start);
    }
    return list;
  }

  int _nextTime(NovaChatMeta? meta) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (meta == null) return now;
    return now > meta.updatedAt ? now : meta.updatedAt + 1;
  }

  void _notify() {
    if (!_retired) notifyListeners();
  }

  Future<void> _saveIndexQuietly() async {
    try {
      await _store.saveIndex();
    } catch (_) {
      // best effort: the in-memory list is still right; saved next time
    }
  }

  // ── Reading ──────────────────────────────────────────────────────────────

  /// The messages of a chat — from the phone, or downloaded when needed.
  /// Null when it can't be loaded (e.g. offline) or no longer exists.
  Future<List<Map<String, String>>?> load(String id) async {
    final meta = _store.find(id);
    if (meta == null) return null;
    if (!meta.onServerOnly) {
      final local = await _store.readMessages(id);
      if (local != null) return local;
    }
    final api = _api;
    if (api == null) return null;
    try {
      final remote = await api.messages(id);
      if (remote == null) {
        // Deleted on another phone.
        await _forget(id);
        return null;
      }
      // Changed here while downloading: keep this phone's version.
      if (_store.find(id) != meta || !meta.onServerOnly) {
        return await _store.readMessages(id) ?? remote;
      }
      await _store.writeMessages(id, remote);
      meta.onServerOnly = false;
      meta.synced = true;
      meta.messageCount = remote.length;
      _problem = null;
      await _saveIndexQuietly();
      _notify();
      return remote;
    } on NovaChatSyncException catch (e) {
      _problem = e.problem;
      _notify();
      return null;
    }
  }

  // ── Changes ──────────────────────────────────────────────────────────────

  /// Saves a chat on the phone and uploads it shortly after (signed in).
  /// A chat that is already saved keeps its name (it may have been renamed).
  Future<void> save(String id, List<Map<String, String>> messages, {required String titleIfNew}) async {
    if (messages.isEmpty) return;
    var meta = _store.find(id);
    final time = _nextTime(meta);
    if (meta == null) {
      meta = NovaChatMeta(id: id, title: cleanTitle(titleIfNew), createdAt: time, updatedAt: time);
      _store.chats.add(meta);
    }
    meta.updatedAt = time;
    meta.messageCount = messages.length;
    meta.synced = false;
    meta.onServerOnly = false;
    _store.pendingDeletes.remove(id);
    _notify();
    await _store.writeMessages(id, List<Map<String, String>>.of(messages));
    await _saveIndexQuietly();
    _scheduleUpload(id);
  }

  Future<void> rename(String id, String title) async {
    final meta = _store.find(id);
    if (meta == null) return;
    final onServer = meta.synced || meta.onServerOnly;
    meta.title = cleanTitle(title);
    meta.updatedAt = _nextTime(meta);
    meta.synced = false;
    _notify();
    await _saveIndexQuietly();
    final api = _api;
    if (api == null) return;
    if (!onServer) {
      _scheduleUpload(id); // the upload carries the new title
      return;
    }
    await _renameOnServer(api, meta);
    await _saveIndexQuietly();
    _notify();
  }

  Future<void> delete(String id) async {
    _store.chats.removeWhere((c) => c.id == id);
    _toUpload.remove(id);
    final api = _api;
    if (api != null) _store.pendingDeletes.add(id);
    _notify();
    await _store.removeMessages(id);
    await _saveIndexQuietly();
    if (api == null) return;
    await _deleteOnServer(api, id);
    await _saveIndexQuietly();
    _notify();
  }

  Future<void> _forget(String id) async {
    _store.chats.removeWhere((c) => c.id == id);
    _toUpload.remove(id);
    _notify();
    await _store.removeMessages(id);
    await _saveIndexQuietly();
  }

  // ── Server sync ──────────────────────────────────────────────────────────

  /// Brings this phone and the server up to date (signed in only).
  Future<void> sync() async {
    final api = _api;
    if (api == null || _syncing || _retired) return;
    _syncing = true;
    _notify();
    try {
      final remote = await api.list();
      if (_retired) return;
      final plan = NovaChatMerge.plan(
        local: List<NovaChatMeta>.of(_store.chats),
        pendingDeletes: Set<String>.of(_store.pendingDeletes),
        remote: remote,
      );
      _problem = null;

      // Apply the list right away (no waiting in between, so a chat saved
      // meanwhile can't be overwritten by older server data).
      _store.pendingDeletes.removeAll(plan.forgetDeleted);
      for (final r in plan.addFromServer) {
        if (_store.find(r.id) != null || _store.pendingDeletes.contains(r.id)) continue;
        _store.chats.add(NovaChatMeta(
          id: r.id,
          title: r.title,
          createdAt: r.createdAt,
          updatedAt: r.updatedAt,
          messageCount: r.messageCount,
          synced: true,
          onServerOnly: true,
        ));
      }
      for (final r in plan.newerOnServer) {
        final m = _store.find(r.id);
        if (m == null || r.updatedAt <= m.updatedAt) continue;
        m.title = r.title;
        m.updatedAt = r.updatedAt;
        m.messageCount = r.messageCount;
        m.synced = true;
        m.onServerOnly = true;
      }
      final remoteAt = {for (final r in remote) r.id: r.updatedAt};
      for (final id in plan.markSynced) {
        final m = _store.find(id);
        if (m != null && remoteAt[id] == m.updatedAt) m.synced = true;
      }
      final removed = <String>[];
      for (final id in plan.removeLocally) {
        final m = _store.find(id);
        if (m == null || !m.synced) continue;
        _store.chats.remove(m);
        _toUpload.remove(id);
        removed.add(id);
      }
      _notify();
      for (final id in removed) {
        await _store.removeMessages(id);
      }
      await _saveIndexQuietly();

      for (final id in plan.deleteOnServer) {
        await _deleteOnServer(api, id);
      }
      for (final id in plan.upload) {
        await _uploadOne(api, id);
      }
      await _saveIndexQuietly();
    } on NovaChatSyncException catch (e) {
      _problem = e.problem;
    } catch (_) {
      _problem = NovaChatSyncProblem.failed;
    } finally {
      _syncing = false;
      _notify();
    }
  }

  void _scheduleUpload(String id) {
    if (_api == null || _retired) return;
    _toUpload.add(id);
    _uploadTimer?.cancel();
    _uploadTimer = Timer(const Duration(milliseconds: 1500), () {
      _flushUploads();
    });
  }

  Future<void> _flushUploads() async {
    final api = _api;
    if (api == null || _toUpload.isEmpty) return;
    final ids = List<String>.of(_toUpload);
    _toUpload.clear();
    for (final id in ids) {
      await _uploadOne(api, id);
    }
    await _saveIndexQuietly();
    _notify();
  }

  Future<void> _uploadOne(NovaChatApi api, String id) async {
    final meta = _store.find(id);
    if (meta == null) return;
    if (meta.onServerOnly) {
      // Only the title can have changed (the messages aren't on this phone).
      await _renameOnServer(api, meta);
      return;
    }
    final sent = meta.updatedAt;
    try {
      final messages = await _store.readMessages(id);
      if (messages == null || messages.isEmpty) return;
      final serverAt = await api.upload(id, meta.title, sent, forUpload(messages));
      if (_store.find(id) != meta) {
        // Deleted here while it was uploading: delete it there too.
        if (!_store.pendingDeletes.contains(id)) _store.pendingDeletes.add(id);
        await _deleteOnServer(api, id);
        return;
      }
      _problem = null;
      if (meta.updatedAt != sent) return; // changed again meanwhile — uploaded next
      if (serverAt > sent) {
        // Another phone saved a newer version: it wins; downloaded when opened.
        meta.updatedAt = serverAt;
        meta.onServerOnly = true;
      }
      meta.synced = true;
    } on NovaChatSyncException catch (e) {
      _problem = e.problem; // retried at the next sync (still not synced)
    }
  }

  Future<void> _renameOnServer(NovaChatApi api, NovaChatMeta meta) async {
    final sent = meta.updatedAt;
    try {
      final found = await api.rename(meta.id, meta.title, sent);
      if (!found) {
        if (meta.onServerOnly) {
          await _forget(meta.id); // deleted on another phone
        } else {
          _scheduleUpload(meta.id); // not there yet: upload it with the new title
        }
        return;
      }
      _problem = null;
      if (meta.updatedAt == sent) meta.synced = true;
    } on NovaChatSyncException catch (e) {
      _problem = e.problem; // retried at the next sync
    }
  }

  Future<void> _deleteOnServer(NovaChatApi api, String id) async {
    try {
      await api.delete(id);
      _store.pendingDeletes.remove(id);
      _problem = null;
    } on NovaChatSyncException catch (e) {
      _problem = e.problem; // deleted there at the next sync
    }
  }

  /// Another account signed in: finish uploading, then stop using the server.
  void _retire() {
    if (_retired) return;
    _uploadTimer?.cancel();
    final api = _api;
    final flush = _toUpload.isEmpty ? Future<void>.value() : _flushUploads();
    _retired = true;
    _api = null;
    flush.whenComplete(() => api?.dispose());
  }
}
