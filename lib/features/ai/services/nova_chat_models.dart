// lib/features/ai/services/nova_chat_models.dart
//
// NOVA AI chat history — data types and the sync rules (pure Dart, tested in
// test/nova/nova_chat_sync_test.dart).

/// One saved conversation (the messages are stored separately).
class NovaChatMeta {
  NovaChatMeta({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.messageCount = 0,
    this.synced = false,
    this.onServerOnly = false,
  });

  final String id;
  String title;

  /// Milliseconds since 1970 (UTC).
  final int createdAt;

  /// Last change (on any phone), milliseconds since 1970.
  int updatedAt;
  int messageCount;

  /// The server has exactly this version.
  bool synced;

  /// Listed from the server; the messages are downloaded when it is opened.
  bool onServerOnly;

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        'messageCount': messageCount,
        'synced': synced,
        'onServerOnly': onServerOnly,
      };

  static NovaChatMeta? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final title = raw['title'];
    if (id is! String || id.isEmpty || title is! String) return null;
    int asInt(Object? v) => v is num ? v.toInt() : 0;
    return NovaChatMeta(
      id: id,
      title: title,
      createdAt: asInt(raw['createdAt']),
      updatedAt: asInt(raw['updatedAt']),
      messageCount: asInt(raw['messageCount']),
      synced: raw['synced'] == true,
      onServerOnly: raw['onServerOnly'] == true,
    );
  }
}

/// A chat as listed by the server.
class NovaRemoteChat {
  const NovaRemoteChat({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.messageCount,
  });

  final String id;
  final String title;
  final int createdAt;
  final int updatedAt;
  final int messageCount;

  static NovaRemoteChat? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final title = raw['title'];
    if (id is! String || title is! String) return null;
    int asInt(Object? v) => v is num ? v.toInt() : 0;
    return NovaRemoteChat(
      id: id,
      title: title,
      createdAt: asInt(raw['created_at']),
      updatedAt: asInt(raw['updated_at']),
      messageCount: asInt(raw['message_count']),
    );
  }
}

/// What to do after reading the server's list of chats.
class NovaMergePlan {
  final List<NovaRemoteChat> addFromServer = [];
  final List<NovaRemoteChat> newerOnServer = [];
  final List<String> upload = [];
  final List<String> deleteOnServer = [];
  final List<String> forgetDeleted = [];
  final List<String> removeLocally = [];
  final List<String> markSynced = [];
}

class NovaChatMerge {
  NovaChatMerge._();

  /// The server lists at most this many chats (newest first).
  static const int serverListLimit = 200;

  /// Last change wins. A chat deleted on this phone is deleted on the server;
  /// a synced chat that disappeared from the server was deleted on another
  /// phone and is removed here.
  static NovaMergePlan plan({
    required List<NovaChatMeta> local,
    required Set<String> pendingDeletes,
    required List<NovaRemoteChat> remote,
  }) {
    final plan = NovaMergePlan();
    final remoteById = {for (final r in remote) r.id: r};
    final localById = {for (final l in local) l.id: l};

    for (final id in pendingDeletes) {
      if (remoteById.containsKey(id)) {
        plan.deleteOnServer.add(id);
      } else {
        plan.forgetDeleted.add(id);
      }
    }

    for (final r in remote) {
      if (pendingDeletes.contains(r.id)) continue;
      final l = localById[r.id];
      if (l == null) {
        plan.addFromServer.add(r);
      } else if (r.updatedAt > l.updatedAt) {
        plan.newerOnServer.add(r);
      } else if (r.updatedAt < l.updatedAt || !l.synced) {
        plan.upload.add(l.id);
      } else {
        plan.markSynced.add(l.id);
      }
    }

    // A full list means anything missing from it is really gone; with a
    // capped list, older chats may simply not be listed.
    final complete = remote.length < serverListLimit;
    final oldestListed =
        remote.isEmpty ? 0 : remote.map((r) => r.updatedAt).reduce((a, b) => a < b ? a : b);
    for (final l in local) {
      if (remoteById.containsKey(l.id) || pendingDeletes.contains(l.id)) continue;
      if (l.synced) {
        // An empty list (e.g. a restored or recreated server table) never wipes
        // this phone: such chats are uploaded again instead.
        if (remote.isEmpty) {
          plan.upload.add(l.id);
        } else if (complete || l.updatedAt >= oldestListed) {
          plan.removeLocally.add(l.id);
        }
      } else {
        plan.upload.add(l.id);
      }
    }
    return plan;
  }
}
