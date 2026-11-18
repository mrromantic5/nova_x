// lib/features/cyber/engine/cyber_audit.dart
//
// NOVA Cyber — audit trail. An append-only log of who scanned what, when, and
// on what authority (verified ownership, own device, local file). Every entry
// carries the SHA-256 of the previous one, so editing or deleting a past line
// breaks the chain and [CyberAudit.verify] reports where.
//
// Kept on this phone in the app's private folder (cyber/audit.log, one JSON
// object per line). Never sent anywhere.

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'cyber_storage.dart';

class AuditEntry {
  AuditEntry({required this.seq, required this.at, required this.action, required this.target, this.scope = '', this.detail = '', this.prev = '', this.hash = ''});

  final int seq;
  final DateTime at;
  final String action; // scan.start, scan.done, scan.failed, ownership, export, triage, rules
  final String target;
  final String scope; // how the target is authorised
  final String detail;
  final String prev;
  final String hash;

  Map<String, Object?> body() => {
        'seq': seq,
        'at': at.toUtc().toIso8601String(),
        'action': action,
        'target': target,
        'scope': scope,
        'detail': detail,
        'prev': prev,
      };

  /// SHA-256 over the canonical body (fixed key order, no hash field).
  String computeHash() => sha256.convert(utf8.encode(jsonEncode(body()))).toString();

  String toLine() => jsonEncode({...body(), 'hash': hash});

  static AuditEntry fromJson(Map<String, dynamic> j) => AuditEntry(
        seq: (j['seq'] as num?)?.toInt() ?? 0,
        at: DateTime.tryParse('${j['at']}') ?? DateTime.fromMillisecondsSinceEpoch(0),
        action: '${j['action'] ?? ''}',
        target: '${j['target'] ?? ''}',
        scope: '${j['scope'] ?? ''}',
        detail: '${j['detail'] ?? ''}',
        prev: '${j['prev'] ?? ''}',
        hash: '${j['hash'] ?? ''}',
      );
}

/// Result of checking the chain.
class AuditCheck {
  AuditCheck(this.entries, this.brokenAt, this.reason);
  final int entries;
  final int? brokenAt; // seq of the first bad entry, null when intact
  final String reason;
  bool get intact => brokenAt == null;
}

class CyberAudit {
  static File? overrideFile; // tests

  static File get file {
    if (overrideFile != null) return overrideFile!;
    return File(CyberStorage.path(['audit.log']));
  }

  static Future<void> _lock = Future.value();

  /// Appends one entry (serialised, so concurrent scans can't interleave).
  static Future<AuditEntry?> log(String action, String target, {String scope = '', String detail = ''}) {
    final done = _lock.then((_) async {
      try {
        final f = file;
        await f.parent.create(recursive: true);
        var prev = '';
        var seq = 1;
        if (await f.exists()) {
          final last = await _lastLine(f);
          if (last != null) {
            final e = AuditEntry.fromJson(jsonDecode(last) as Map<String, dynamic>);
            prev = e.hash;
            seq = e.seq + 1;
          }
        }
        final draft = AuditEntry(seq: seq, at: DateTime.now(), action: action, target: target, scope: scope, detail: detail, prev: prev);
        final entry = AuditEntry(seq: seq, at: draft.at, action: action, target: target, scope: scope, detail: detail, prev: prev, hash: draft.computeHash());
        await f.writeAsString('${entry.toLine()}\n', mode: FileMode.append, flush: true);
        return entry;
      } catch (_) {
        return null;
      }
    });
    _lock = done.then((_) {});
    return done;
  }

  static Future<String?> _lastLine(File f) async {
    final len = await f.length();
    if (len == 0) return null;
    final raf = await f.open();
    try {
      final start = len > 8192 ? len - 8192 : 0;
      await raf.setPosition(start);
      final tail = utf8.decode(await raf.read(len - start), allowMalformed: true);
      final lines = tail.split('\n').where((l) => l.trim().isNotEmpty).toList();
      return lines.isEmpty ? null : lines.last;
    } finally {
      await raf.close();
    }
  }

  /// Newest first.
  static Future<List<AuditEntry>> recent({int limit = 300}) async {
    try {
      final lines = await file.readAsLines();
      final out = <AuditEntry>[];
      for (final l in lines.reversed) {
        if (l.trim().isEmpty) continue;
        try {
          out.add(AuditEntry.fromJson(jsonDecode(l) as Map<String, dynamic>));
        } catch (_) {}
        if (out.length >= limit) break;
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  /// Re-computes every hash and link. Pure over [lines] (unit-tested).
  static AuditCheck verifyLines(List<String> lines) {
    var prev = '';
    var expectSeq = 1;
    var n = 0;
    for (final l in lines) {
      if (l.trim().isEmpty) continue;
      AuditEntry e;
      try {
        e = AuditEntry.fromJson(jsonDecode(l) as Map<String, dynamic>);
      } catch (_) {
        return AuditCheck(n, expectSeq, 'Line ${n + 1} is not valid JSON');
      }
      n++;
      if (e.seq != expectSeq) return AuditCheck(n, e.seq, 'Entry ${e.seq}: expected number $expectSeq (an entry was removed or inserted)');
      if (e.prev != prev) return AuditCheck(n, e.seq, 'Entry ${e.seq}: link to the previous entry does not match');
      if (e.computeHash() != e.hash) return AuditCheck(n, e.seq, 'Entry ${e.seq}: contents were changed after it was written');
      prev = e.hash;
      expectSeq++;
    }
    return AuditCheck(n, null, n == 0 ? 'No entries yet' : 'All $n entries intact');
  }

  static Future<AuditCheck> verify() async {
    try {
      if (!await file.exists()) return AuditCheck(0, null, 'No entries yet');
      return verifyLines(await file.readAsLines());
    } catch (e) {
      return AuditCheck(0, 0, 'Could not read the log: $e');
    }
  }
}
