// lib/features/cyber/engine/zip_reader.dart
//
// NOVA Cyber (3.13.0, Android) — reads a project .zip in memory for the
// code scan, so no storage permission is needed (the user picks the file).
//
// Supports the two methods every zip tool writes: stored (0) and deflate (8).
// Uses the central directory (sizes are always correct there, even when the
// zip was written with data descriptors). Encrypted entries are skipped.
// Zip64 archives (over 4 GB or 65,535 files) are not supported.

import 'dart:io';
import 'dart:typed_data';

import 'cyber_code_scan.dart' show CodeFile;

class ZipReadException implements Exception {
  ZipReadException(this.message);
  final String message;
  @override
  String toString() => message;
}

class ZipReader {
  /// Largest single file inflated (larger files are skipped by the scan anyway).
  static const int maxEntryBytes = 1024 * 1024;

  /// Returns the files in [zip]. [want] decides which entries are inflated
  /// (by path), so big binaries are never decompressed.
  static List<CodeFile> read(Uint8List zip, {bool Function(String path)? want, int maxEntries = 20000}) {
    final bd = ByteData.sublistView(zip);
    // End of central directory: signature 0x06054b50, within the last 64 KB.
    var eocd = -1;
    final stop = zip.length - 22 - 0xFFFF < 0 ? 0 : zip.length - 22 - 0xFFFF;
    for (var i = zip.length - 22; i >= stop; i--) {
      if (bd.getUint32(i, Endian.little) == 0x06054b50) {
        eocd = i;
        break;
      }
    }
    if (eocd < 0) throw ZipReadException('This file is not a .zip archive.');
    final count = bd.getUint16(eocd + 10, Endian.little);
    var p = bd.getUint32(eocd + 16, Endian.little);
    if (count == 0xFFFF || p == 0xFFFFFFFF) throw ZipReadException('Large (Zip64) archives aren\'t supported. Zip only the source folders.');

    final out = <CodeFile>[];
    for (var n = 0; n < count && out.length < maxEntries; n++) {
      if (p + 46 > zip.length || bd.getUint32(p, Endian.little) != 0x02014b50) break;
      final flags = bd.getUint16(p + 8, Endian.little);
      final method = bd.getUint16(p + 10, Endian.little);
      final csize = bd.getUint32(p + 20, Endian.little);
      final usize = bd.getUint32(p + 24, Endian.little);
      final nameLen = bd.getUint16(p + 28, Endian.little);
      final extraLen = bd.getUint16(p + 30, Endian.little);
      final commentLen = bd.getUint16(p + 32, Endian.little);
      final local = bd.getUint32(p + 42, Endian.little);
      final name = String.fromCharCodes(zip, p + 46, p + 46 + nameLen);
      p += 46 + nameLen + extraLen + commentLen;

      if (name.endsWith('/')) continue; // folder
      if (flags & 1 == 1) continue; // encrypted
      if (name.contains('..')) continue; // never trust odd paths
      if (usize > maxEntryBytes) continue;
      if (want != null && !want(name)) continue;
      if (local + 30 > zip.length || bd.getUint32(local, Endian.little) != 0x04034b50) continue;
      final start = local + 30 + bd.getUint16(local + 26, Endian.little) + bd.getUint16(local + 28, Endian.little);
      if (start + csize > zip.length) continue;
      final data = Uint8List.sublistView(zip, start, start + csize);
      try {
        if (method == 0) {
          out.add(CodeFile(name, data));
        } else if (method == 8) {
          final bytes = ZLibDecoder(raw: true).convert(data);
          if (bytes.length <= maxEntryBytes) out.add(CodeFile(name, bytes));
        }
      } catch (_) {
        // A damaged entry is skipped; the rest of the project is still scanned.
      }
    }
    return out;
  }
}
