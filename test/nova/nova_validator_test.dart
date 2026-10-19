// test/nova/nova_validator_test.dart
//
// Validation is the security boundary for AI-planned actions: anything that
// isn't an allow-listed action with safe, bounded arguments is rejected.

import 'package:flutter_test/flutter_test.dart';
import 'package:nova_x/features/nova/models/nova_models.dart';
import 'package:nova_x/features/nova/nova_config.dart';
import 'package:nova_x/features/nova/services/nova_api.dart';
import 'package:nova_x/features/nova/services/nova_history.dart';
import 'package:nova_x/features/nova/services/nova_validator.dart';

void main() {
  group('URLs', () {
    test('bare domains become https', () {
      expect(NovaActionValidator.normaliseUrl('bbc.com'), 'https://bbc.com');
      expect(NovaActionValidator.normaliseUrl('https://example.org/a?b=1'),
          'https://example.org/a?b=1');
      expect(NovaActionValidator.normaliseUrl('http://example.org'), 'http://example.org');
    });

    test('unsafe or malformed URLs are rejected', () {
      for (final bad in [
        'javascript:alert(1)',
        'file:///sdcard/secret.txt',
        'intent://scan/#Intent;scheme=zxing;end',
        'content://contacts/people',
        'data:text/html,hi',
        'https://user:pass@example.com',
        'https://exa mple.com',
        'not a url',
        '',
      ]) {
        expect(NovaActionValidator.normaliseUrl(bad), isNull, reason: bad);
      }
    });
  });

  group('arguments', () {
    test('phone numbers', () {
      expect(NovaActionValidator.sanitisePhone('+233 (24) 111-2222'), '+233241112222');
      expect(NovaActionValidator.sanitisePhone('12'), isNull);
      expect(NovaActionValidator.sanitisePhone('024+1234'), isNull);
      expect(NovaActionValidator.sanitisePhone('1' * 25), isNull);
    });

    test('settings synonyms', () {
      expect(NovaActionValidator.settingsTarget('Wi-Fi'), 'wifi');
      expect(NovaActionValidator.settingsTarget('flight mode'), 'airplane');
      expect(NovaActionValidator.settingsTarget('default_apps'), 'default_apps');
      expect(NovaActionValidator.settingsTarget('kernel'), isNull);
    });

    test('app names', () {
      expect(NovaActionValidator.cleanAppName('Google Maps'), 'Google Maps');
      expect(NovaActionValidator.cleanAppName('rm -rf /'), isNull);
      expect(NovaActionValidator.cleanAppName('a' * 41), isNull);
      expect(NovaActionValidator.canonicalApp('Twitter'), 'x');
    });
  });

  group('planner actions', () {
    test('unknown actions are rejected', () {
      expect(NovaActionValidator.fromPlanner('send_sms', {'to': '123'}), isNull);
      expect(NovaActionValidator.fromPlanner('run_shell', {'cmd': 'ls'}), isNull);
      expect(NovaActionValidator.fromPlanner(null, null), isNull);
    });

    test('valid actions are normalised', () {
      final a = NovaActionValidator.fromPlanner('open_url', {'url': 'example.com'});
      expect(a, const NovaAction(NovaActionType.openUrl, {'url': 'https://example.com'}));
      final s = NovaActionValidator.fromPlanner('search_in_app', {'app': 'YouTube', 'query': 'cats'});
      expect(s?.args, {'app': 'youtube', 'query': 'cats'});
      expect(NovaActionValidator.fromPlanner('search_in_app', {'app': 'tiktok', 'query': 'x'}), isNull);
      expect(NovaActionValidator.fromPlanner('open_settings', {'target': 'root'}), isNull);
    });

    test('plan response: invalid actions dropped, steps capped', () {
      final plan = NovaApiClient.parsePlanResponse({
        'type': 'actions',
        'actions': [
          {'name': 'open_app', 'args': {'app': 'YouTube'}},
          {'name': 'open_url', 'args': {'url': 'javascript:alert(1)'}},
          {'name': 'web_search', 'args': {'query': 'flutter'}},
          {'name': 'navigate', 'args': {'destination': 'Accra Mall'}},
          {'name': 'open_app', 'args': {'app': 'Spotify'}},
        ],
      });
      expect(plan, isA<NovaActionsPlan>());
      final types = (plan as NovaActionsPlan).actions.map((a) => a.type).toList();
      // first 3 entries considered; the unsafe URL is dropped
      expect(types, [NovaActionType.openApp, NovaActionType.webSearch]);
      expect(types.length, lessThanOrEqualTo(NovaConfig.maxPlanSteps));
    });

    test('plan response: nothing valid falls back to the reply text', () {
      final plan = NovaApiClient.parsePlanResponse({
        'type': 'actions',
        'actions': [
          {'name': 'delete_files', 'args': {}},
        ],
        'reply': "I can't do that, but I can open Settings for you.",
      });
      expect(plan, isA<NovaReplyPlan>());
    });

    test('plan response: clarify and chat', () {
      final clarify = NovaApiClient.parsePlanResponse({
        'type': 'clarify',
        'question': 'Which Ama?',
        'options': ['Ama Mensah', 'Ama Boateng'],
      });
      expect(clarify, isA<NovaClarifyPlan>());
      expect((clarify as NovaClarifyPlan).options, hasLength(2));

      final chat = NovaApiClient.parsePlanResponse({'type': 'chat', 'reply': 'Hello!'});
      expect((chat as NovaReplyPlan).reply, 'Hello!');

      expect(NovaApiClient.parsePlanResponse({'type': 'chat'}), isNull);
      expect(NovaApiClient.parsePlanResponse({'type': 'weird'}), isNull);
    });
  });

  group('history', () {
    test('is bounded like the Worker expects', () {
      final h = NovaHistory();
      for (var i = 0; i < 15; i++) {
        h.addUser('q$i');
        h.addAssistant('a$i');
      }
      expect(h.length, NovaConfig.maxHistoryMessages);
      expect(h.toJson().first, {'role': 'user', 'content': 'q10'});
      h.addUser('x' * 5000);
      expect(h.messages.last.content.length, NovaConfig.maxHistoryChars);
      expect(h.toJson().every((m) => m['role'] == 'user' || m['role'] == 'assistant'), isTrue);
    });

    test('ignores empty messages', () {
      final h = NovaHistory()..addUser('   ');
      expect(h.isEmpty, isTrue);
    });
  });
}
