// test/nova/nova_command_parser_test.dart
//
// On-device command recognition. Anything ambiguous must return null so the
// NOVA AI decides — the parser never guesses.

import 'package:flutter_test/flutter_test.dart';
import 'package:nova_x/features/nova/models/nova_models.dart';
import 'package:nova_x/features/nova/services/nova_command_parser.dart';

void main() {
  // Monday 19 October 2026, 14:05
  final parser = NovaCommandParser(clock: () => DateTime(2026, 10, 19, 14, 5));

  List<NovaAction> actions(String input) {
    final plan = parser.parse(input);
    expect(plan, isA<NovaActionsPlan>(), reason: input);
    return (plan as NovaActionsPlan).actions;
  }

  NovaAction single(String input) {
    final list = actions(input);
    expect(list, hasLength(1), reason: input);
    return list.first;
  }

  group('apps', () {
    test('open an app, ignoring wake phrase and politeness', () {
      final a = single('Hey NOVA, open YouTube.');
      expect(a.type, NovaActionType.openApp);
      expect(a.args['app'], 'youtube');
      expect(single('Can you open the calculator app please').args['app'], 'calculator');
      expect(single('open camera').args['app'], 'camera');
    });

    test('NOVA X screens', () {
      expect(single('open my bookmarks').args['app'], 'bookmarks');
      expect(single('show downloads').args['app'], 'downloads');
      expect(single('open nova shield').args['app'], 'nova shield');
      expect(single('NOVA X settings').args['app'], 'nova x settings');
    });

    test('search inside apps', () {
      final a = single('Open YouTube and search for Flutter tutorials');
      expect(a.type, NovaActionType.searchInApp);
      expect(a.args, {'app': 'youtube', 'query': 'flutter tutorials'});
      expect(single('search flutter tutorials on youtube').args,
          {'app': 'youtube', 'query': 'flutter tutorials'});
      expect(single('play despacito on spotify').args, {'app': 'spotify', 'query': 'despacito'});
    });
  });

  group('web', () {
    test('web search', () {
      final a = single('Search for Flutter tutorials');
      expect(a.type, NovaActionType.webSearch);
      expect(a.args['query'], 'flutter tutorials');
      expect(single('look up the weather in accra').args['query'], 'the weather in accra');
      expect(single('search up jollof rice').args['query'], 'jollof rice');
      // "and" inside a query must not split it into steps
      expect(single('search for salt and pepper').args['query'], 'salt and pepper');
    });

    test('websites', () {
      expect(single('open bbc.com').args['url'], 'https://bbc.com');
      expect(single('youtube.com').args['url'], 'https://youtube.com');
      expect(single('go to news.bbc.co.uk/sport').args['url'], 'https://news.bbc.co.uk/sport');
    });

    test('unsafe schemes are rejected', () {
      expect(parser.parse('open javascript:alert(1)'), isNull);
    });
  });

  group('phone', () {
    test('call a contact by name', () {
      final a = single('call Ama');
      expect(a.type, NovaActionType.callContact);
      expect(a.args['name'], 'ama');
      expect(single('Can you call mum please').args['name'], 'mum');
    });

    test('dial a number', () {
      final a = single('dial 024 123 4567');
      expect(a.type, NovaActionType.dialNumber);
      expect(a.args['number'], '0241234567');
    });

    test('ambiguous "call" phrases go to the AI', () {
      expect(parser.parse('call me a taxi'), isNull);
      expect(parser.parse('call the police'), isNull);
    });
  });

  group('settings', () {
    test('settings screens', () {
      expect(single('open wifi settings').args, {'target': 'wifi'});
      expect(single('take me to wifi settings').args, {'target': 'wifi'});
      expect(single('settings').args, {'target': 'general'});
      expect(single('open settings').args, {'target': 'general'});
    });

    test('turning things on/off only opens the screen', () {
      expect(single('Turn on Wi-Fi').args, {'target': 'wifi', 'toggle': 'on'});
      expect(single('turn bluetooth off').args, {'target': 'bluetooth', 'toggle': 'off'});
    });

    test('unknown settings go to the AI', () {
      expect(parser.parse('whatsapp settings'), isNull);
    });
  });

  group('maps', () {
    test('directions', () {
      final a = single('directions to Accra Mall');
      expect(a.type, NovaActionType.navigate);
      expect(a.args['destination'], 'accra mall');
      expect(single('navigate to Kotoka airport').args['destination'], 'kotoka airport');
    });
  });

  group('multi-step', () {
    test('two commands', () {
      final list = actions('open youtube and open instagram');
      expect(list.map((a) => a.args['app']), ['youtube', 'instagram']);
      final mixed = actions('open whatsapp, then call ama');
      expect(mixed[0].type, NovaActionType.openApp);
      expect(mixed[1].type, NovaActionType.callContact);
    });
  });

  group('local answers & control', () {
    test('time and date', () {
      expect((parser.parse('what time is it') as NovaReplyPlan).reply, "It's 2:05 PM.");
      expect((parser.parse("what's the date") as NovaReplyPlan).reply,
          'Today is Monday, 19 October 2026.');
    });

    test('cancel', () {
      expect(parser.parse('never mind'), isA<NovaCancelPlan>());
      expect(parser.parse('Stop.'), isA<NovaCancelPlan>());
    });

    test('questions and vague requests go to the AI', () {
      expect(parser.parse('what is flutter'), isNull);
      expect(parser.parse('who created you'), isNull);
      expect(parser.parse('tell me about nova x'), isNull);
    });

    test('wake phrase only', () {
      expect(NovaCommandParser.isWakeOnly('Hey NOVA'), isTrue);
      expect(NovaCommandParser.isWakeOnly('Hello NOVA.'), isTrue);
      expect(NovaCommandParser.isWakeOnly('hey nova open youtube'), isFalse);
      expect(parser.parse('hey nova'), isNull);
    });
  });

  group("things NOVA can't do are answered honestly (never \"done\")", () {
    // Screenshots moved out of this list: NOVA Capture can take them now
    // (see test/nova_capture/capture_voice_test.dart).
    test('lock screen, power, alarms, messages, torch', () {
      for (final input in [
        'lock my screen',
        'Hey NOVA, lock the phone',
        'turn off the screen',
        'restart my phone',
        'turn off my phone',
        'set an alarm for 6am',
        'start a timer for 5 minutes',
        'start a timer',
        'remind me to call mum',
        'send a message to Ama',
        'text Wendy',
        'whatsapp kofi that I am late',
        'turn on the flashlight',
      ]) {
        final plan = parser.parse(input);
        expect(plan, isA<NovaReplyPlan>(), reason: input);
        expect((plan as NovaReplyPlan).reply, contains("can't"), reason: input);
      }
    });

    test('similar questions and settings still work', () {
      expect(parser.parse('text to speech apps'), isNull);
      expect(parser.parse('email etiquette tips'), isNull);
      expect(parser.parse('how do i lock my screen'), isNull);
      expect(parser.parse('remind me what the capital of france is'), isNull);
      expect(parser.parse('make a timer in flutter'), isNull);
      expect(parser.parse('text editor'), isNull);
      expect(parser.parse('message history'), isNull);
      expect(single('lock screen settings').args, {'target': 'security'});
      expect(single('open clock').args['app'], 'clock');
    });
  });

  group('music (NOVA Music, works offline)', () {
    test('play a song or an artist', () {
      final a = single('Hey NOVA, play me Tatiana Like You');
      expect(a.type, NovaActionType.playMusic);
      expect(a.args['query'], 'tatiana like you');
      expect(single('play the song called essence').args['query'], 'essence');
      expect(single('listen to burna boy').args['query'], 'burna boy');
      expect(single('play songs by sarkodie').args['query'], 'sarkodie');
    });

    test('any music', () {
      for (final input in [
        'play some music',
        'play music',
        'shuffle my songs',
        'put on some music',
        'listen to some music',
      ]) {
        final a = single(input);
        expect(a.type, NovaActionType.playMusic, reason: input);
        expect(a.args['query'], '', reason: input);
      }
    });

    test('player controls', () {
      String command(String input) {
        final a = single(input);
        expect(a.type, NovaActionType.musicControl, reason: input);
        return a.args['command']!;
      }

      expect(command('pause'), 'pause');
      expect(command('pause the music'), 'pause');
      expect(command('resume'), 'resume');
      expect(command('play'), 'resume');
      expect(command('continue playing'), 'resume');
      expect(command('next song'), 'next');
      expect(command('skip'), 'next');
      expect(command('previous song'), 'previous');
      expect(command('stop the music'), 'stop');
      expect(command("what's playing"), 'now_playing');
      expect(command('turn the volume up'), 'volume_up');
      expect(command('louder'), 'volume_up');
      expect(command('turn down the volume'), 'volume_down');
      expect(command('mute'), 'mute');
      expect(command('unmute'), 'unmute');
    });

    test('not songs', () {
      expect(single('play despacito on spotify').type, NovaActionType.searchInApp);
      expect(single('play a video of cats').args, {'app': 'youtube', 'query': 'cats'});
      expect(single('open play store').args['app'], 'play store');
      expect(parser.parse('play a game'), isNull);
      expect(parser.parse('play the guitar chords for amazing grace'), isNull);
      expect(parser.parse('listen to this article'), isNull);
      expect(parser.parse('continue'), isNull);
      expect(parser.parse('Stop.'), isA<NovaCancelPlan>());
    });

    test('NOVA Music screen', () {
      expect(single('open my music').args['app'], 'my music');
      expect(single('open nova music').args['app'], 'nova music');
      expect(single('open music player').args['app'], 'music player');
      expect(single('open my points').args['app'], 'my points');
    });
  });


  group('3.7: random songs, change the song, player modes', () {
    test('a song without a name plays a random one', () {
      for (final input in [
        'play me a song', 'play me song', 'play a random song', 'play any song', 'play anything',
        'play me some songs please', 'play something', 'Hey NOVA play me a song',
        'surprise me with a song', 'play some good music',
      ]) {
        final a = single(input);
        expect(a.type, NovaActionType.playMusic, reason: input);
        expect(a.args['query'], '', reason: input);
      }
      expect(single('play essence').args['query'], 'essence');
    });

    test('change the song, shuffle, repeat, restart', () {
      String command(String input) {
        final a = single(input);
        expect(a.type, NovaActionType.musicControl, reason: input);
        return a.args['command']!;
      }

      for (final i in [
        'change the song', 'change song', 'switch the track', 'another song', 'play another song',
        'play a different song', 'play something else', 'skip it', 'next song', 'skip',
      ]) {
        expect(command(i), 'next', reason: i);
      }
      expect(command('previous song'), 'previous');
      expect(command('turn on shuffle'), 'shuffle_on');
      expect(command('shuffle off'), 'shuffle_off');
      expect(command('repeat this song'), 'repeat_one');
      expect(command('loop'), 'repeat_one');
      expect(command('put it on repeat'), 'repeat_one');
      expect(command('repeat all'), 'repeat_all');
      expect(command('turn off repeat'), 'repeat_off');
      expect(command('restart the song'), 'restart');
      expect(command('play it again'), 'restart');
      expect(command('replay'), 'restart');
      final that = parser.parse('repeat that');
      expect(that is NovaActionsPlan && that.actions.first.type == NovaActionType.musicControl, isFalse);
    });
  });

  group('3.7: open any NOVA X page', () {
    test('pages by name', () {
      final cases = <String, String>{
        'open nova network': 'nova network',
        'open nova network page': 'nova network',
        'open the nova music screen': 'nova music',
        'open dev tools': 'dev tools',
        'open x coder': 'x coder',
        'go premium': 'go premium',
        'open a new tab': 'a new tab',
        'take me to my bookmarks': 'bookmarks',
        'launch nova music': 'nova music',
      };
      cases.forEach((input, app) {
        final a = single(input);
        expect(a.type, NovaActionType.openApp, reason: input);
        expect(a.args['app'], app, reason: input);
      });
    });

    test('bare common words are not commands', () {
      for (final w in ['network', 'home']) {
        expect(parser.parse(w), isNot(isA<NovaActionsPlan>()), reason: w);
      }
      expect(single('open settings').type, NovaActionType.openSettings); // the phone's Settings
    });
  });
}
