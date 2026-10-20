// test/nova/nova_music_test.dart
//
// NOVA Music (Dart side): reading the song list and player state sent by
// Android, search in the music screen, and time labels.

import 'package:flutter_test/flutter_test.dart';
import 'package:nova_x/features/music/services/nova_music_service.dart';

void main() {
  group('songs', () {
    test('a song from Android', () {
      final song = NovaSongInfo.fromMap({
        'id': 42,
        'title': 'Like You',
        'artist': 'Tatiana Manaois',
        'album': 'Singles',
        'durationMs': 201000,
      });
      expect(song?.id, 42);
      expect(song?.artistLabel, 'Tatiana Manaois');
      expect(song?.matches('tatiana'), isTrue);
      expect(song?.matches('LIKE'), isTrue);
      expect(song?.matches('essence'), isFalse);
    });

    test('missing details are tolerated; broken entries are skipped', () {
      final song = NovaSongInfo.fromMap({'id': 7, 'title': 'Voice note'});
      expect(song?.artist, '');
      expect(song?.artistLabel, 'Unknown artist');
      expect(song?.durationMs, 0);
      expect(NovaSongInfo.fromMap({'title': 'no id'}), isNull);
      expect(NovaSongInfo.fromMap(null), isNull);
    });
  });

  group('player state', () {
    test('playing state from Android', () {
      final s = NovaMusicState.fromMap({
        'state': 'playing',
        'id': 42,
        'title': 'Like You',
        'durationMs': 200000,
        'positionMs': 1000,
        'index': 0,
        'queueLength': 12,
        'shuffle': true,
        'repeat': 'all',
      });
      expect(s.isPlaying, isTrue);
      expect(s.hasSong, isTrue);
      expect(s.queueLength, 12);
      expect(s.shuffle, isTrue);
      expect(s.repeat, 'all');
    });

    test('the position moves on while playing, never past the end', () {
      final at = DateTime(2026, 10, 20, 9);
      final s = NovaMusicState(state: 'playing', id: 1, durationMs: 10000, positionMs: 4000, receivedAt: at);
      expect(s.livePositionMs(at.add(const Duration(seconds: 3))), 7000);
      expect(s.livePositionMs(at.add(const Duration(minutes: 5))), 10000);
      final paused = NovaMusicState(state: 'paused', id: 1, durationMs: 10000, positionMs: 4000, receivedAt: at);
      expect(paused.livePositionMs(at.add(const Duration(seconds: 3))), 4000);
    });

    test('nothing playing', () {
      final s = NovaMusicState.fromMap('nonsense');
      expect(s.state, 'stopped');
      expect(s.hasSong, isFalse);
    });
  });

  test('time labels', () {
    expect(novaMusicDuration(0), '0:00');
    expect(novaMusicDuration(65000), '1:05');
    expect(novaMusicDuration(3725000), '1:02:05');
  });
}
