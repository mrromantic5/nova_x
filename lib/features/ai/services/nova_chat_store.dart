// lib/features/ai/services/nova_chat_store.dart
//
// NOVA AI chat history on the phone: one folder per account
// (<app documents>/nova_chats/<account>/), an index.json with the list and
// one <chat id>.json per conversation. Only the signed-in account's chats (and
// guest chats) are kept: when someone else signs in on the same phone, the
// previous account's local copy is removed (it stays on the server). After
// signing out, the account's copy is kept (but not shown) so chats saved
// offline are still uploaded when the same person signs in again.

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'nova_chat_models.dart';

class NovaChatStore {
  NovaChatStore._(this.accountKey, this._dir);

  static const String guestKey = 'guest';

  final String accountKey;
  final Directory _dir;

  final List<NovaChatMeta> chats = [];
  final Set<String> pendingDeletes = {};

  /// File writes run one after another (two saves never share a temp file).
  Future<void> _queue = Future<void>.value();

  Future<void> _serial(Future<void> Function() write) {
    final next = _queue.then((_) => write());
    _queue = next.catchError((Object _) {});
    return next;
  }

  static Future<Directory> _root() async {
    final base = await getApplicationDocumentsDirectory();
    return Directory('${base.path}/nova_chats');
  }

  static String _safe(String key) => key.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

  static Future<NovaChatStore> open(String accountKey) async {
    final root = await _root();
    final dir = Directory('${root.path}/${_safe(accountKey)}');
    await dir.create(recursive: true);
    if (accountKey != guestKey) await _purgeOtherAccounts(root, _safe(accountKey));
    final store = NovaChatStore._(accountKey, dir);
    await store._loadIndex();
    return store;
  }

  static Future<void> _purgeOtherAccounts(Directory root, String keep) async {
    try {
      await for (final entity in root.list()) {
        if (entity is! Directory) continue;
        final name = entity.uri.pathSegments.where((s) => s.isNotEmpty).last;
        if (name != keep && name != guestKey) await entity.delete(recursive: true);
      }
    } catch (_) {
      // best effort
    }
  }

  File get _indexFile => File('${_dir.path}/index.json');

  File _chatFile(String id) => File('${_dir.path}/${_safe(id)}.json');

  Future<void> _loadIndex() async {
    chats.clear();
    pendingDeletes.clear();
    try {
      if (!await _indexFile.exists()) return;
      final data = jsonDecode(await _indexFile.readAsString());
      if (data is! Map) return;
      final list = data['chats'];
      if (list is List) {
        for (final item in list) {
          final meta = NovaChatMeta.fromJson(item);
          if (meta != null) chats.add(meta);
        }
      }
      final deleted = data['deleted'];
      if (deleted is List) pendingDeletes.addAll(deleted.whereType<String>());
    } catch (_) {
      // A damaged index starts empty; chat files are re-listed from the server.
    }
  }

  Future<void> saveIndex() => _serial(_saveIndexNow);

  Future<void> _saveIndexNow() async {
    final data = {
      'version': 1,
      'account': accountKey,
      'chats': chats.map((c) => c.toJson()).toList(),
      'deleted': pendingDeletes.toList(),
    };
    final tmp = File('${_indexFile.path}.tmp');
    await tmp.writeAsString(jsonEncode(data), flush: true);
    await tmp.rename(_indexFile.path);
  }

  NovaChatMeta? find(String id) {
    for (final c in chats) {
      if (c.id == id) return c;
    }
    return null;
  }

  Future<List<Map<String, String>>?> readMessages(String id) async {
    try {
      final f = _chatFile(id);
      if (!await f.exists()) return null;
      final data = jsonDecode(await f.readAsString());
      if (data is! List) return null;
      return [
        for (final m in data)
          if (m is Map && m['role'] is String && m['content'] is String)
            {
              'id': m['id'] is String ? m['id'] as String : '',
              'role': m['role'] as String,
              'content': m['content'] as String,
            },
      ];
    } catch (_) {
      return null;
    }
  }

  Future<void> writeMessages(String id, List<Map<String, String>> messages) =>
      _serial(() => _writeMessagesNow(id, messages));

  Future<void> _writeMessagesNow(String id, List<Map<String, String>> messages) async {
    final f = _chatFile(id);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(messages), flush: true);
    await tmp.rename(f.path);
  }

  Future<void> removeMessages(String id) => _serial(() => _removeMessagesNow(id));

  Future<void> _removeMessagesNow(String id) async {
    try {
      final f = _chatFile(id);
      if (await f.exists()) await f.delete();
    } catch (_) {
      // best effort
    }
  }

  /// After signing in: move chats made as a guest on this phone into the
  /// account (they are uploaded on the next sync).
  Future<int> adoptGuestChats() async {
    if (accountKey == guestKey) return 0;
    final root = await _root();
    final guest = await NovaChatStore._openExisting(root, guestKey);
    if (guest == null || guest.chats.isEmpty) return 0;
    var moved = 0;
    for (final meta in guest.chats) {
      if (find(meta.id) != null) continue;
      final messages = await guest.readMessages(meta.id);
      if (messages == null || messages.isEmpty) continue;
      await writeMessages(meta.id, messages);
      meta.synced = false;
      meta.onServerOnly = false;
      chats.add(meta);
      moved++;
    }
    await saveIndex();
    try {
      await guest._dir.delete(recursive: true);
    } catch (_) {
      // best effort
    }
    return moved;
  }

  static Future<NovaChatStore?> _openExisting(Directory root, String key) async {
    final dir = Directory('${root.path}/${_safe(key)}');
    if (!await dir.exists()) return null;
    final store = NovaChatStore._(key, dir);
    await store._loadIndex();
    return store;
  }
}
