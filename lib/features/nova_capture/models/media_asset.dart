// lib/features/nova_capture/models/media_asset.dart
//
// One screenshot or recording saved by NOVA Capture. The uri is a MediaStore
// content:// address on the phone (Pictures/NOVA X/Screenshots or
// Movies/NOVA X/Recordings) — never a raw file path.

enum MediaKind {
  screenshot('screenshot'),
  recording('recording');

  const MediaKind(this.wire);
  final String wire;

  static MediaKind fromWire(Object? v) => v == 'recording' ? MediaKind.recording : MediaKind.screenshot;
}

class MediaAsset {
  const MediaAsset({
    required this.uri,
    required this.name,
    required this.kind,
    this.sizeBytes = 0,
    this.createdMs = 0,
    this.mime = '',
    this.width = 0,
    this.height = 0,
    this.durationMs = 0,
  });

  final String uri;
  final String name;
  final MediaKind kind;
  final int sizeBytes;
  final int createdMs;
  final String mime;
  final int width;
  final int height;
  final int durationMs;

  bool get isImage => kind == MediaKind.screenshot;
  bool get isVideo => kind == MediaKind.recording;

  DateTime get created => DateTime.fromMillisecondsSinceEpoch(createdMs);

  /// Null for anything that isn't a valid NOVA Capture item.
  static MediaAsset? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final uri = raw['uri'];
    final name = raw['name'];
    if (uri is! String || !uri.startsWith('content://') || name is! String) return null;
    int i(String k) {
      final v = raw[k];
      return v is num ? v.toInt() : 0;
    }

    final mime = raw['mime'];
    return MediaAsset(
      uri: uri,
      name: name,
      kind: MediaKind.fromWire(raw['kind']),
      sizeBytes: i('size'),
      createdMs: i('createdMs'),
      mime: mime is String ? mime : '',
      width: i('width'),
      height: i('height'),
      durationMs: i('durationMs'),
    );
  }

  MediaAsset copyWith({String? name, int? durationMs}) => MediaAsset(
        uri: uri,
        name: name ?? this.name,
        kind: kind,
        sizeBytes: sizeBytes,
        createdMs: createdMs,
        mime: mime,
        width: width,
        height: height,
        durationMs: durationMs ?? this.durationMs,
      );

  @override
  bool operator ==(Object other) => other is MediaAsset && other.uri == uri && other.name == name;

  @override
  int get hashCode => Object.hash(uri, name);
}

/// "1.4 MB", "820 KB".
String formatBytes(int bytes) {
  if (bytes <= 0) return '0 KB';
  const kb = 1024;
  const mb = kb * 1024;
  const gb = mb * 1024;
  if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(1)} GB';
  if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(1)} MB';
  return '${(bytes / kb).ceil()} KB';
}

/// "0:42", "12:05", "1:02:03".
String formatDuration(Duration d) {
  final total = d.inSeconds < 0 ? 0 : d.inSeconds;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  final ss = s.toString().padLeft(2, '0');
  if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:$ss';
  return '$m:$ss';
}

/// "27 Oct 2026, 14:05".
String formatCaptureDate(DateTime t) {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final hh = t.hour.toString().padLeft(2, '0');
  final mm = t.minute.toString().padLeft(2, '0');
  return '${t.day} ${months[t.month - 1]} ${t.year}, $hh:$mm';
}
