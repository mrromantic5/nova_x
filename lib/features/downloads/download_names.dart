// lib/features/downloads/download_names.dart
//
// 3.13.1 download manager: working out a good file name for a download,
// like Chrome does: the name the site suggests, then the server's
// Content-Disposition header, then the last part of the link, with an
// extension added from the file type when the name has none. Pure Dart (no
// plugins) so it is unit-tested in test/browser/download_names_test.dart.

class DownloadNames {
  DownloadNames._();

  static const String fallback = 'download';

  /// Extensions for common types, used when the name has no extension.
  static const Map<String, String> _extByMime = {
    'application/pdf': 'pdf',
    'application/zip': 'zip',
    'application/x-zip-compressed': 'zip',
    'application/x-rar-compressed': 'rar',
    'application/vnd.rar': 'rar',
    'application/x-7z-compressed': '7z',
    'application/gzip': 'gz',
    'application/x-tar': 'tar',
    'application/json': 'json',
    'application/xml': 'xml',
    'application/msword': 'doc',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document': 'docx',
    'application/vnd.ms-excel': 'xls',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet': 'xlsx',
    'application/vnd.ms-powerpoint': 'ppt',
    'application/vnd.openxmlformats-officedocument.presentationml.presentation': 'pptx',
    'application/vnd.android.package-archive': 'apk',
    'application/epub+zip': 'epub',
    'text/plain': 'txt',
    'text/html': 'html',
    'text/csv': 'csv',
    'text/css': 'css',
    'text/javascript': 'js',
    'application/javascript': 'js',
    'image/jpeg': 'jpg',
    'image/png': 'png',
    'image/gif': 'gif',
    'image/webp': 'webp',
    'image/svg+xml': 'svg',
    'image/bmp': 'bmp',
    'image/heic': 'heic',
    'audio/mpeg': 'mp3',
    'audio/mp4': 'm4a',
    'audio/aac': 'aac',
    'audio/ogg': 'ogg',
    'audio/wav': 'wav',
    'audio/x-wav': 'wav',
    'audio/flac': 'flac',
    'video/mp4': 'mp4',
    'video/webm': 'webm',
    'video/x-matroska': 'mkv',
    'video/quicktime': 'mov',
    'video/3gpp': '3gp',
  };

  /// The extension for [mime] ("application/pdf; charset=x" → "pdf"), or null.
  static String? extensionForMime(String? mime) {
    if (mime == null) return null;
    final m = mime.split(';').first.trim().toLowerCase();
    if (m.isEmpty) return null;
    return _extByMime[m];
  }

  /// The type for a file name's extension (the reverse of [extensionForMime]).
  static String? mimeForName(String name) {
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return null;
    final ext = name.substring(dot + 1).toLowerCase();
    for (final e in _extByMime.entries) {
      if (e.value == ext) return e.key;
    }
    return null;
  }

  /// The file name from a Content-Disposition header, or null.
  /// Prefers RFC 5987 `filename*=UTF-8''…` over plain `filename=`.
  static String? fromContentDisposition(String? header) {
    if (header == null || header.trim().isEmpty) return null;
    final star = RegExp(r"""filename\*\s*=\s*([^']*)'[^']*'([^;]+)""", caseSensitive: false).firstMatch(header);
    if (star != null) {
      var v = star.group(2)!.trim();
      if (v.length >= 2 && v.startsWith('"') && v.endsWith('"')) v = v.substring(1, v.length - 1);
      try {
        v = Uri.decodeComponent(v);
      } catch (_) {}
      final s = sanitize(v);
      if (s.isNotEmpty) return s;
    }
    final quoted = RegExp(r'filename\s*=\s*"((?:[^"\\]|\\.)*)"', caseSensitive: false).firstMatch(header);
    if (quoted != null) {
      final s = sanitize(quoted.group(1)!.replaceAll(r'\"', '"'));
      if (s.isNotEmpty) return s;
    }
    final plain = RegExp(r'filename\s*=\s*([^;]+)', caseSensitive: false).firstMatch(header);
    if (plain != null) {
      var v = plain.group(1)!.trim();
      if (v.contains('%')) {
        try {
          v = Uri.decodeComponent(v);
        } catch (_) {}
      }
      final s = sanitize(v);
      if (s.isNotEmpty) return s;
    }
    return null;
  }

  /// The last part of the link's path ("…/files/Report%202024.pdf?x=1" →
  /// "Report 2024.pdf"), or null for links without one (data:, blob:, "/").
  static String? fromUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme == 'data' || uri.scheme == 'blob') return null;
    final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segs.isEmpty) return null;
    var last = segs.last;
    try {
      last = Uri.decodeComponent(last);
    } catch (_) {}
    final s = sanitize(last);
    return s.isEmpty ? null : s;
  }

  /// Makes [name] safe as a file name on Android: no folders, no characters
  /// that storage providers reject, no leading dots, at most 120 characters
  /// (keeping the extension).
  static String sanitize(String name) {
    var s = name.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F\x7F]'), '_').trim();
    s = s.replaceAll(RegExp(r'\s+'), ' ');
    while (s.startsWith('.')) {
      s = s.substring(1);
    }
    s = s.trim();
    if (s.length > 120) {
      final dot = s.lastIndexOf('.');
      final ext = (dot > 0 && s.length - dot <= 10) ? s.substring(dot) : '';
      s = s.substring(0, 120 - ext.length).trimRight() + ext;
    }
    return s;
  }

  static bool _hasExtension(String name) {
    final dot = name.lastIndexOf('.');
    return dot > 0 && dot < name.length - 1 && name.length - dot <= 10;
  }

  /// The best name for a download.
  static String resolve({String? suggested, String? contentDisposition, required String url, String? mime}) {
    String? name;
    if (suggested != null && suggested.trim().isNotEmpty) {
      final s = sanitize(suggested);
      if (s.isNotEmpty) name = s;
    }
    name ??= fromContentDisposition(contentDisposition);
    name ??= fromUrl(url);
    name ??= fallback;
    if (!_hasExtension(name)) {
      final ext = extensionForMime(mime);
      if (ext != null) name = '$name.$ext';
    }
    return name;
  }

  /// "1.4 MB", "820 KB", "12 B".
  static String size(int bytes) {
    if (bytes < 0) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(bytes < 10 * 1024 ? 1 : 0)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  /// "3 min left", "40 s left", "" when unknown.
  static String timeLeft(int remainingBytes, double bytesPerSecond) {
    if (bytesPerSecond <= 1 || remainingBytes <= 0) return '';
    final secs = (remainingBytes / bytesPerSecond).ceil();
    if (secs < 60) return '$secs s left';
    if (secs < 3600) return '${(secs / 60).ceil()} min left';
    final h = secs ~/ 3600;
    final m = ((secs % 3600) / 60).round();
    return m == 0 ? '$h h left' : '$h h $m min left';
  }

  /// The total size from a `Content-Range: bytes 100-199/1000` header, or -1.
  static int totalFromContentRange(String? header) {
    if (header == null) return -1;
    final m = RegExp(r'/\s*(\d+)\s*$').firstMatch(header.trim());
    return m == null ? -1 : int.tryParse(m.group(1)!) ?? -1;
  }
}
