// lib/features/music/services/nova_music_service.dart
//
// Dart side of NOVA Music (channel "com.tlyfe.nova_x/music", see
// NovaMusicBridge.kt). Playback runs natively (NovaMusicPlayer +
// NovaMusicService), so music keeps playing when NOVA X is in the
// background and works fully offline. Songs never leave the phone.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// "3:07" or "1:02:05".
String novaMusicDuration(int ms) {
  if (ms <= 0) return '0:00';
  final total = ms ~/ 1000;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = (total % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
}

class NovaSongInfo {
  const NovaSongInfo({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.durationMs,
  });

  final int id;
  final String title;
  final String artist;
  final String album;
  final int durationMs;

  String get artistLabel => artist.isEmpty ? 'Unknown artist' : artist;

  static NovaSongInfo? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final title = raw['title'];
    if (id is! num || title is! String) return null;
    final artist = raw['artist'];
    final album = raw['album'];
    final duration = raw['durationMs'];
    return NovaSongInfo(
      id: id.toInt(),
      title: title,
      artist: artist is String ? artist : '',
      album: album is String ? album : '',
      durationMs: duration is num ? duration.toInt() : 0,
    );
  }

  bool matches(String query) {
    final q = query.toLowerCase();
    return title.toLowerCase().contains(q) ||
        artist.toLowerCase().contains(q) ||
        album.toLowerCase().contains(q);
  }
}

/// What NOVA Music is doing right now.
class NovaMusicState {
  const NovaMusicState({
    this.state = 'stopped',
    this.id,
    this.title,
    this.artist,
    this.album,
    this.durationMs = 0,
    this.positionMs = 0,
    this.index = -1,
    this.queueLength = 0,
    this.shuffle = false,
    this.repeat = 'off',
    this.receivedAt,
  });

  /// playing · paused · buffering · stopped
  final String state;
  final int? id;
  final String? title;
  final String? artist;
  final String? album;
  final int durationMs;
  final int positionMs;
  final int index;
  final int queueLength;
  final bool shuffle;

  /// off · all · one
  final String repeat;
  final DateTime? receivedAt;

  bool get isPlaying => state == 'playing';
  bool get hasSong => state != 'stopped' && id != null;

  /// Position now, moving forward while playing.
  int livePositionMs(DateTime now) {
    final at = receivedAt;
    var p = positionMs;
    if (isPlaying && at != null) p += now.difference(at).inMilliseconds;
    if (p < 0) return 0;
    if (durationMs > 0 && p > durationMs) return durationMs;
    return p;
  }

  static NovaMusicState fromMap(Object? raw) {
    if (raw is! Map) return const NovaMusicState();
    int asInt(Object? v, int fallback) => v is num ? v.toInt() : fallback;
    String? asString(Object? v) => v is String ? v : null;
    final id = raw['id'];
    return NovaMusicState(
      state: asString(raw['state']) ?? 'stopped',
      id: id is num ? id.toInt() : null,
      title: asString(raw['title']),
      artist: asString(raw['artist']),
      album: asString(raw['album']),
      durationMs: asInt(raw['durationMs'], 0),
      positionMs: asInt(raw['positionMs'], 0),
      index: asInt(raw['index'], -1),
      queueLength: asInt(raw['queueLength'], 0),
      shuffle: raw['shuffle'] == true,
      repeat: asString(raw['repeat']) ?? 'off',
      receivedAt: DateTime.now(),
    );
  }
}

/// Songs on the phone, or why they can't be read.
class NovaLibrary {
  const NovaLibrary(this.status, this.songs);

  /// ok · permission_required · error
  final String status;
  final List<NovaSongInfo> songs;
}

class NovaMusicService {
  NovaMusicService._() {
    _channel.setMethodCallHandler(_onNativeCall);
  }

  /// One per Flutter engine (main app and floating assistant each have one).
  static final NovaMusicService instance = NovaMusicService._();

  static const MethodChannel _channel = MethodChannel('com.tlyfe.nova_x/music');

  final ValueNotifier<NovaMusicState> state = ValueNotifier<NovaMusicState>(const NovaMusicState());

  Future<dynamic> _onNativeCall(MethodCall call) async {
    if (call.method == 'onMusicState') state.value = NovaMusicState.fromMap(call.arguments);
    return null;
  }

  Future<NovaLibrary> library({bool refresh = false}) async {
    try {
      final res = await _channel.invokeMethod<Object>('library', {'refresh': refresh});
      if (res is! Map) return const NovaLibrary('error', []);
      final status = res['status'];
      final raw = res['songs'];
      final songs = <NovaSongInfo>[];
      if (raw is List) {
        for (final item in raw) {
          final song = NovaSongInfo.fromMap(item);
          if (song != null) songs.add(song);
        }
      }
      return NovaLibrary(status is String ? status : 'error', songs);
    } on PlatformException {
      return const NovaLibrary('error', []);
    } on MissingPluginException {
      return const NovaLibrary('error', []);
    }
  }

  /// Plays [ids] (in this order) starting at [index].
  Future<bool> playSongs(List<int> ids, int index, {bool? shuffle}) async {
    try {
      final ok = await _channel.invokeMethod<bool>('playSongs', {
        'ids': ids,
        'index': index,
        if (shuffle != null) 'shuffle': shuffle,
      });
      return ok ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Shuffles every song on the phone.
  Future<bool> playAll() async {
    try {
      return await _channel.invokeMethod<bool>('playAll') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<void> toggle() => _call('toggle');
  Future<void> pause() => _call('pause');
  Future<void> resume() => _call('resume');
  Future<void> next() => _call('next');
  Future<void> previous() => _call('previous');
  Future<void> stop() => _call('stop');
  Future<void> seekTo(int ms) => _call('seekTo', {'ms': ms});
  Future<void> setShuffle(bool on) => _call('setShuffle', {'on': on});

  /// off · all · one
  Future<void> setRepeat(String mode) => _call('setRepeat', {'mode': mode});

  Future<void> refreshState() async {
    try {
      final res = await _channel.invokeMethod<Object>('state');
      if (res is Map) state.value = NovaMusicState.fromMap(res);
    } on PlatformException {
      // keep the last known state
    } on MissingPluginException {
      // no native side (tests)
    }
  }

  Future<void> _call(String method, [Map<String, Object?>? args]) async {
    try {
      await _channel.invokeMethod<void>(method, args);
    } on PlatformException {
      // ignore — best effort
    } on MissingPluginException {
      // ignore — no native side (tests)
    }
  }
}
