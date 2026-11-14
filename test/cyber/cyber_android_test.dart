// test/cyber/cyber_android_test.dart
//
// NOVA Cyber on Android (3.13.0): the code scan reads a picked .zip in memory
// (no storage permission). These tests use a small zip made by Python's
// zipfile (one deflated file, one stored file, one folder, one file inside
// node_modules).

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:nova_x/features/cyber/engine/cyber_code_scan.dart';
import 'package:nova_x/features/cyber/engine/zip_reader.dart';

const _zipB64 =
    'UEsDBBQAAAAAAAAAIQAAAAAAAAAAAAAAAAAEAAAAYXBwL1BLAwQUAAAACAAyG25dwQ4X8ycAAAAlAAAADgAAAGFwcC9jb25maWcucGhws7EvyCjgUslOrVSwVVBy9PZ0dHRydnF1c/fw9PL28fXzD1Cy5gIAUEsDBBQAAAAAADIbbl2GphA2BQAAAAUAAAAOAAAAYXBwL3JlYWRtZS50eHRoZWxsb1BLAwQUAAAACAAyG25dWfZEyh8AAAAdAAAAGwAAAGFwcC9ub2RlX21vZHVsZXMveC9pbmRleC5qcytLLFLItlVy9PZ0dHRydnF1c/fw9PL28fXzD1CyBgBQSwECFAMUAAAAAAAAACEAAAAAAAAAAAAAAAAABAAAAAAAAAAAAAAAgAEAAAAAYXBwL1BLAQIUAxQAAAAIADIbbl3BDhfzJwAAACUAAAAOAAAAAAAAAAAAAACAASIAAABhcHAvY29uZmlnLnBocFBLAQIUAxQAAAAAADIbbl2GphA2BQAAAAUAAAAOAAAAAAAAAAAAAACAAXUAAABhcHAvcmVhZG1lLnR4dFBLAQIUAxQAAAAIADIbbl1Z9kTKHwAAAB0AAAAbAAAAAAAAAAAAAACAAaYAAABhcHAvbm9kZV9tb2R1bGVzL3gvaW5kZXguanNQSwUGAAAAAAQABADzAAAA/gAAAAAA';

void main() {
  final zip = Uint8List.fromList(base64Decode(_zipB64));

  group('ZipReader', () {
    test('reads stored and deflated files, skips folders', () {
      final files = ZipReader.read(zip);
      final byPath = {for (final f in files) f.path: utf8.decode(f.bytes)};
      expect(byPath.keys, containsAll(['app/config.php', 'app/readme.txt', 'app/node_modules/x/index.js']));
      expect(byPath.containsKey('app/'), isFalse);
      expect(byPath['app/readme.txt'], 'hello');
      expect(byPath['app/config.php'], contains('AKIAABCDEFGHIJKLMNOP'));
    });

    test('want() decides which entries are inflated', () {
      final files = ZipReader.read(zip, want: (p) => p.endsWith('.txt'));
      expect(files.map((f) => f.path), ['app/readme.txt']);
    });

    test('rejects a file that is not a zip', () {
      expect(() => ZipReader.read(Uint8List.fromList(utf8.encode('not a zip at all, just some text here'))), throwsA(isA<ZipReadException>()));
    });
  });

  group('CodeScanner.scanFiles', () {
    test('finds a hard-coded AWS key and skips node_modules', () async {
      final res = await CodeScanner.scanFiles(ZipReader.read(zip));
      // config.php and readme.txt are read; node_modules is skipped.
      expect(res.files, 2);
      final aws = res.findings.where((f) => f.id == 'code.secret.aws').toList();
      expect(aws, hasLength(1));
      expect(aws.first.title, contains('(1)'));
      expect(aws.first.location, startsWith('/app/config.php:2'));
      // The key itself is never shown in full.
      expect(aws.first.evidence, isNot(contains('AKIAABCDEFGHIJKLMNOP')));
    });

    test('picked single files are scanned by name', () async {
      final res = await CodeScanner.scanFiles([
        CodeFile('db.php', utf8.encode(r'<?php mysqli_query($db, "SELECT * FROM u WHERE id=" . $_GET["id"]);')),
        CodeFile('photo.png', [0x89, 0x50, 0x4e, 0x47]),
      ]);
      expect(res.files, 1);
      expect(res.findings.any((f) => f.id == 'code.sqli.php'), isTrue);
    });
  });
}
