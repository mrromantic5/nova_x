// test/browser/download_names_test.dart (3.13.1)
//
// The download manager names files like Chrome: the site's suggested name,
// then Content-Disposition, then the link, with an extension from the type.

import 'package:flutter_test/flutter_test.dart';
import 'package:nova_x/features/downloads/download_manager.dart';
import 'package:nova_x/features/downloads/download_names.dart';

void main() {
  group('Content-Disposition', () {
    test('plain quoted filename', () {
      expect(DownloadNames.fromContentDisposition('attachment; filename="report.pdf"'), 'report.pdf');
    });
    test('unquoted filename', () {
      expect(DownloadNames.fromContentDisposition('attachment; filename=data.csv'), 'data.csv');
    });
    test('RFC 5987 filename* wins and is decoded', () {
      expect(
        DownloadNames.fromContentDisposition("attachment; filename=\"fallback.txt\"; filename*=UTF-8''r%C3%A9sum%C3%A9%20final.pdf"),
        'résumé final.pdf',
      );
    });
    test('folders and unsafe characters are removed', () {
      expect(DownloadNames.fromContentDisposition('attachment; filename="../../etc/pass:wd"'), '_.._etc_pass_wd');
    });
    test('missing header', () {
      expect(DownloadNames.fromContentDisposition(null), isNull);
      expect(DownloadNames.fromContentDisposition('inline'), isNull);
    });
  });

  group('from the link', () {
    test('last path segment, decoded, without query', () {
      expect(DownloadNames.fromUrl('https://ex.com/files/Report%202024.pdf?x=1#y'), 'Report 2024.pdf');
    });
    test('no file name in the link', () {
      expect(DownloadNames.fromUrl('https://ex.com/'), isNull);
      expect(DownloadNames.fromUrl('data:text/plain,hi'), isNull);
      expect(DownloadNames.fromUrl('blob:https://ex.com/1234'), isNull);
    });
  });

  group('resolve', () {
    test('suggested name first', () {
      expect(
        DownloadNames.resolve(suggested: 'song.mp3', contentDisposition: 'attachment; filename="x.bin"', url: 'https://a.b/c.zip'),
        'song.mp3',
      );
    });
    test('adds an extension from the type', () {
      expect(DownloadNames.resolve(url: 'https://a.b/download', mime: 'application/pdf; charset=binary'), 'download.pdf');
      expect(DownloadNames.resolve(url: 'data:image/png;base64,AAAA', mime: 'image/png'), 'download.png');
    });
    test('keeps an existing extension', () {
      expect(DownloadNames.resolve(url: 'https://a.b/app.apk', mime: 'application/octet-stream'), 'app.apk');
    });
    test('long names are shortened but keep the extension', () {
      final n = DownloadNames.resolve(suggested: '${'a' * 300}.mp4', url: 'https://a.b/');
      expect(n.length, 120);
      expect(n.endsWith('.mp4'), isTrue);
    });
    test('hidden-file dots are stripped', () {
      expect(DownloadNames.sanitize('...profile'), 'profile');
    });
  });

  group('sizes and time', () {
    test('sizes', () {
      expect(DownloadNames.size(512), '512 B');
      expect(DownloadNames.size(1536), '1.5 KB');
      expect(DownloadNames.size(5 * 1024 * 1024), '5.0 MB');
    });
    test('time left', () {
      expect(DownloadNames.timeLeft(1000, 100), '10 s left');
      expect(DownloadNames.timeLeft(600000, 1000), '10 min left');
      expect(DownloadNames.timeLeft(100, 0), '');
    });
    test('Content-Range total', () {
      expect(DownloadNames.totalFromContentRange('bytes 100-199/1000'), 1000);
      expect(DownloadNames.totalFromContentRange('bytes 100-199/*'), -1);
      expect(DownloadNames.totalFromContentRange(null), -1);
    });
    test('type from name', () {
      expect(DownloadNames.mimeForName('a.pdf'), 'application/pdf');
      expect(DownloadNames.mimeForName('noext'), isNull);
    });
  });

  group('saved list', () {
    test('a running download comes back paused after a restart', () {
      final t = DownloadTask(
        id: 'x1',
        url: 'https://a.b/c.zip',
        name: 'c.zip',
        total: 1000,
        received: 400,
        status: DlStatus.running,
        createdAt: DateTime(2026, 11, 1),
      );
      final back = DownloadTask.fromJson(t.toJson());
      expect(back.status, DlStatus.paused);
      expect(back.received, 400);
      expect(back.total, 1000);
      expect(back.name, 'c.zip');
      expect(back.fraction, closeTo(0.4, 1e-9));
    });
    test('completed downloads keep where they were saved', () {
      final t = DownloadTask(
        id: 'x2',
        url: 'https://a.b/d.pdf',
        name: 'd.pdf',
        status: DlStatus.completed,
        savedUri: 'content://media/external/downloads/12',
        savedLocation: 'Download/NOVA X',
        createdAt: DateTime(2026, 11, 1),
      );
      final back = DownloadTask.fromJson(t.toJson());
      expect(back.status, DlStatus.completed);
      expect(back.savedUri, 'content://media/external/downloads/12');
      expect(back.savedLocation, 'Download/NOVA X');
    });
  });
}
