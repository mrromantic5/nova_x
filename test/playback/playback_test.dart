// test/playback/playback_test.dart
//
// 3.12.0 AI Playback: script parsing + intro, timing, voice choice, the free
// daily limit and the page snapshot.

import 'package:flutter_test/flutter_test.dart';
import 'package:nova_x/core/services/ai_feedback_service.dart';
import 'package:nova_x/features/playback/playback_engine.dart';
import 'package:nova_x/features/playback/playback_models.dart';
import 'package:nova_x/features/playback/playback_page_reader.dart';
import 'package:nova_x/features/playback/playback_quota.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('script', () {
    final s = PlaybackScript.fromJson({
      'title': 'NOVA X for Windows',
      'lang': 'en',
      'lines': [
        {'s': 'f', 't': 'So what is this page about?'},
        {'s': 'm', 't': 'It is NOVA X Browser for Windows, a modern browser with workspaces.'},
        {'s': 'x', 't': 'ignored'},
        {'s': 'f', 't': ''},
      ],
    }, host: 'nova-x.t-lyfe.com.ng', url: 'https://nova-x.t-lyfe.com.ng/')!;

    test('the app\'s intro comes first, spoken by Leo', () {
      expect(s.lines.first.text, 'This AI playback is powered by NOVA X.');
      expect(s.lines.first.female, isFalse);
      expect(s.lines.length, 3);
      expect(s.lines[1].speaker, 'Ava');
      expect(s.lines[2].speaker, 'Leo');
    });

    test('times: starts, total and line at a time', () {
      final starts = s.starts;
      expect(starts.first, 0);
      expect(starts[1], closeTo(s.lines[0].seconds, 1e-9));
      expect(s.totalSeconds, greaterThan(starts.last));
      expect(s.lineAt(0), 0);
      expect(s.lineAt(starts[2] + 0.1), 2);
      expect(playbackClock(91), '1:31');
    });

    test('localized intro; too few lines → null', () {
      expect(PlaybackScript.introFor('fr'), contains('NOVA X'));
      expect(PlaybackScript.fromJson({'lines': [{'s': 'f', 't': 'hi'}]}, host: 'a', url: 'b'), isNull);
    });
  });

  group('names are not spoken as labels', () {
    test('"Ava:" / "Leo -" / "**Ava:**" are removed; names inside a sentence stay', () {
      expect(PlaybackLine.stripSpeaker('Ava: How do I get it installed?'), 'How do I get it installed?');
      expect(PlaybackLine.stripSpeaker('Leo - Just download it.'), 'Just download it.');
      expect(PlaybackLine.stripSpeaker('**Ava:** Is it free?'), 'Is it free?');
      expect(PlaybackLine.stripSpeaker('Yes, Ava, it is free.'), 'Yes, Ava, it is free.');
      expect(PlaybackLine.stripSpeaker('M-Pesa works here.'), 'M-Pesa works here.');
      expect(PlaybackLine.fromJson({'s': 'f', 't': 'Ava: Hi'})!.text, 'Hi');
    });
  });

  group('NOVA voices', () {
    test('Ava female / Leo male per language; regional English; unknown → none', () {
      expect(PlaybackCloudVoices.pick('en', 'US'), ('en-US-AvaNeural', 'en-US-AndrewNeural'));
      expect(PlaybackCloudVoices.pick('en', 'NG')!.$1, 'en-NG-EzinneNeural');
      expect(PlaybackCloudVoices.pick('fr', 'FR')!.$2, 'fr-FR-HenriNeural');
      expect(PlaybackCloudVoices.pick('xx', ''), isNull);
    });
  });

  group('voices', () {
    test('gender from Google voice codes and names', () {
      expect(PlaybackVoicePicker.genderOf('en-us-x-sfg-local'), 'f');
      expect(PlaybackVoicePicker.genderOf('en-us-x-iom-network'), 'm');
      expect(PlaybackVoicePicker.genderOf('English Female 2'), 'f');
      expect(PlaybackVoicePicker.genderOf('english male'), 'm');
      expect(PlaybackVoicePicker.genderOf('en-US-SMTl01'), '');
    });

    test('picks an offline female and male voice for the language and region', () {
      final (f, m) = PlaybackVoicePicker.pick([
        {'name': 'fr-fr-x-frc-local', 'locale': 'fr-FR'},
        {'name': 'en-gb-x-gba-local', 'locale': 'en-GB', 'network_required': '0'},
        {'name': 'en-us-x-sfg-network', 'locale': 'en-US', 'network_required': '1'},
        {'name': 'en-us-x-tpf-local', 'locale': 'en-US', 'network_required': '0'},
        {'name': 'en-us-x-iom-local', 'locale': 'en-US', 'network_required': '0'},
      ], 'en', region: 'US');
      expect(f, {'name': 'en-us-x-tpf-local', 'locale': 'en-US'});
      expect(m, {'name': 'en-us-x-iom-local', 'locale': 'en-US'});
    });

    test('unknown names still give two different voices; none for the language → nulls', () {
      final (f, m) = PlaybackVoicePicker.pick([
        {'name': 'voice-a', 'locale': 'sw-KE'},
        {'name': 'voice-b', 'locale': 'sw-KE'},
      ], 'sw');
      expect(f, isNotNull);
      expect(m, isNotNull);
      expect(f!['name'], isNot(m!['name']));
      final (f2, m2) = PlaybackVoicePicker.pick([{'name': 'x', 'locale': 'de-DE'}], 'ja');
      expect(f2, isNull);
      expect(m2, isNull);
    });
  });

  group('free daily limit', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      PlaybackQuota.isPremium = () => false;
    });

    test('10 plays per 24 hours, then 0 left', () async {
      expect(await PlaybackQuota.left(), 10);
      for (var i = 0; i < 10; i++) {
        await PlaybackQuota.recordUse();
      }
      expect(await PlaybackQuota.left(), 0);
      expect(await PlaybackQuota.nextFreeAt(), isNotNull);
    });

    test('plays older than 24 hours no longer count', () async {
      final old = DateTime.now().subtract(const Duration(hours: 25)).millisecondsSinceEpoch;
      SharedPreferences.setMockInitialValues({'nx_playback_uses': '[${List.filled(10, old).join(',')}]'});
      expect(await PlaybackQuota.left(), 10);
    });

    test('Premium: unlimited and nothing is counted', () async {
      PlaybackQuota.isPremium = () => true;
      expect(await PlaybackQuota.left(), isNull);
      await PlaybackQuota.recordUse();
      PlaybackQuota.isPremium = () => false;
      expect(await PlaybackQuota.left(), 10);
    });
  });

  group('feedback', () {
    test('the page address sent with feedback has no query or #part', () {
      expect(AiFeedbackService.pageRef('https://shop.test/item/42?token=abc&u=me#reviews'), 'https://shop.test/item/42');
      expect(AiFeedbackService.pageRef('not a url'), '');
    });
  });

  group('page snapshot', () {
    test('parsed from the reader\'s JSON; sensitive pages are not playable', () {
      final text = 'word ' * 120;
      final p = PageSnapshot.fromJson('https://www.example.com/a',
          '{"ok":true,"title":"T","lang":"en-GB","description":"D","text":"$text","headings":["H"],"words":120,"sensitive":false}')!;
      expect(p.playable, isTrue);
      expect(p.host, 'example.com');
      expect(p.headings, ['H']);
      final s = PageSnapshot.fromJson('https://bank.test', {'ok': true, 'text': text, 'sensitive': true})!;
      expect(s.playable, isFalse);
      expect(PageSnapshot.fromJson('x', '{"ok":false}'), isNull);
      expect(PageSnapshot.fromJson('x', 'not json'), isNull);
    });

    test('only normal web pages', () {
      expect(PlaybackPageReader.isWebPage('https://a.test'), isTrue);
      expect(PlaybackPageReader.isWebPage('nova://code'), isFalse);
      expect(PlaybackPageReader.isWebPage('file:///x.html'), isFalse);
    });
  });
}
