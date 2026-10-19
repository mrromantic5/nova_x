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
      expect(parser.parse('start a timer for 5 minutes'), isNull);
      expect(parser.parse('start a timer'), isNull);
    });

    test('wake phrase only', () {
      expect(NovaCommandParser.isWakeOnly('Hey NOVA'), isTrue);
      expect(NovaCommandParser.isWakeOnly('hey nova open youtube'), isFalse);
      expect(parser.parse('hey nova'), isNull);
    });
  });
}
