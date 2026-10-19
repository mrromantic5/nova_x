// test/nova/nova_voice_test.dart
//
// Brains Jet voice helpers: what is sent to the voice API and which audio
// URLs are accepted back.

import 'package:flutter_test/flutter_test.dart';
import 'package:nova_x/features/nova/services/nova_voice.dart';

void main() {
  group('clip', () {
    test('plain text, markdown removed', () {
      expect(NovaBrainsVoice.clip('**Hello** _there_ #1'), 'Hello there 1');
    });

    test('long text is cut at a sentence end within the limit', () {
      final long = List.filled(40, 'This is a sentence.').join(' ');
      final clipped = NovaBrainsVoice.clip(long);
      expect(clipped.length, lessThanOrEqualTo(NovaBrainsVoice.maxChars));
      expect(clipped, endsWith('.'));
    });

    test('long text without sentence ends is cut at the limit', () {
      final clipped = NovaBrainsVoice.clip('a' * 1000);
      expect(clipped.length, NovaBrainsVoice.maxChars);
    });
  });

  group('parseAudioUrl', () {
    test('accepts http(s) URLs from a map or a JSON string', () {
      expect(NovaBrainsVoice.parseAudioUrl({'url': 'https://cdn.test/a.mp3'}), 'https://cdn.test/a.mp3');
      expect(NovaBrainsVoice.parseAudioUrl('{"url":"https://cdn.test/b.mp3"}'), 'https://cdn.test/b.mp3');
    });

    test('rejects anything else', () {
      expect(NovaBrainsVoice.parseAudioUrl(null), isNull);
      expect(NovaBrainsVoice.parseAudioUrl({'url': ''}), isNull);
      expect(NovaBrainsVoice.parseAudioUrl({'url': 'javascript:alert(1)'}), isNull);
      expect(NovaBrainsVoice.parseAudioUrl({'url': 'file:///sdcard/x.mp3'}), isNull);
      expect(NovaBrainsVoice.parseAudioUrl('not json'), isNull);
      expect(NovaBrainsVoice.parseAudioUrl({'audio': 'https://cdn.test/c.mp3'}), isNull);
    });
  });
}
