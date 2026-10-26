// test/nova/platform_39_test.dart
//
// 3.9.0: server times in the phone's time zone, plan limits, the time-zone
// context sent to NOVA AI, the daily message limit, the update popup data and
// analytics page names.

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nova_x/core/services/analytics_service.dart';
import 'package:nova_x/core/services/device_clock.dart';
import 'package:nova_x/core/services/platform_api.dart';
import 'package:nova_x/core/services/update_service.dart';
import 'package:nova_x/features/ai/services/nova_quota.dart';
import 'package:nova_x/features/nova/services/nova_api.dart';

class _Adapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? c) async {
    requests.add(o);
    return ResponseBody.fromString(jsonEncode({'success': true, 'reply': 'It is Monday.'}), 200,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]});
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('ServerTime', () {
    test('server times without a zone are UTC', () {
      final t = ServerTime.parse('2026-10-26 08:15:00')!;
      expect(t.isUtc, isFalse); // shown in local time
      expect(t.toUtc(), DateTime.utc(2026, 10, 26, 8, 15));
    });
    test('ISO times keep their zone; empty values are null', () {
      expect(ServerTime.parse('2026-10-26T08:15:00Z')!.toUtc(), DateTime.utc(2026, 10, 26, 8, 15));
      expect(ServerTime.parse('2026-10-26T12:15:00+04:00')!.toUtc(), DateTime.utc(2026, 10, 26, 8, 15));
      expect(ServerTime.parse('2026-10-26')!.toUtc(), DateTime.utc(2026, 10, 26));
      expect(ServerTime.parse(null), isNull);
      expect(ServerTime.parse(''), isNull);
      expect(ServerTime.parse('0000-00-00 00:00:00'), isNull);
      expect(ServerTime.parse('garbage'), isNull);
    });
  });

  group('DeviceClock', () {
    test('offset labels and the context sent to NOVA AI', () {
      expect(DeviceClock.offsetLabel(240), '+04:00');
      expect(DeviceClock.offsetLabel(-330), '-05:30');
      expect(DeviceClock.offsetLabel(0), '+00:00');
      final c = DeviceClock.context();
      expect(c['offset_min'], DateTime.now().timeZoneOffset.inMinutes);
    });
  });

  group('Plans', () {
    test('limits per plan', () {
      expect(NovaQuotaRules.limitFor(NovaQuotaKind.chat, NovaTier.free), 40);
      expect(NovaQuotaRules.limitFor(NovaQuotaKind.chat, NovaTier.boost), 80);
      expect(NovaQuotaRules.limitFor(NovaQuotaKind.chat, NovaTier.premium), 300);
      expect(NovaQuotaRules.limitFor(NovaQuotaKind.upload, NovaTier.free), 5);
      expect(NovaQuotaRules.limitFor(NovaQuotaKind.image, NovaTier.boost), 10);
      expect(NovaQuotaRules.limitFor(NovaQuotaKind.image, NovaTier.premium), 20);
      expect(NovaQuotaRules.limitFor(NovaQuotaKind.video, NovaTier.free), 0);
      expect(NovaQuotaRules.limitFor(NovaQuotaKind.video, NovaTier.premium), 3);
    });
    test('the window uses the plan limit', () {
      final t0 = DateTime(2026, 10, 26, 9).millisecondsSinceEpoch;
      expect(NovaQuotaWindow.use(39, t0, t0 + 1000, 1, 40), (40, t0));
      expect(NovaQuotaWindow.use(40, t0, t0 + 1000, 1, 40), isNull);
      expect(NovaQuotaWindow.decode('120|$t0', NovaQuotaRules.maxStored), (120, t0));
      const st = NovaQuotaStatus(kind: NovaQuotaKind.chat, used: 120, limit: 300, plan: NovaTier.premium);
      expect(st.remaining, 180);
      expect(st.exhausted, isFalse);
    });
  });

  group('NOVA AI client', () {
    test('sends the phone time zone with /chat', () async {
      final a = _Adapter();
      final api = NovaApiClient(dio: Dio(BaseOptions(baseUrl: 'https://nova.test'))..httpClientAdapter = a,
          meter: (_) async {});
      expect(await api.chat('What day is it?', const []), 'It is Monday.');
      final body = a.requests.single.data as Map;
      expect((body['context'] as Map)['offset_min'], DateTime.now().timeZoneOffset.inMinutes);
    });

    test('the daily message limit stops the request before it is sent', () async {
      final a = _Adapter();
      const blocked = NovaQuotaStatus(kind: NovaQuotaKind.chat, used: 40, limit: 40);
      final api = NovaApiClient(
        dio: Dio(BaseOptions(baseUrl: 'https://nova.test'))..httpClientAdapter = a,
        meter: (_) async => throw NovaApiException(NovaApiErrorKind.rateLimited,
            NovaApiClient.quotaMessage(blocked), statusCode: 429, quota: blocked),
      );
      await expectLater(
        api.chat('hi', const []),
        throwsA(isA<NovaApiException>()
            .having((e) => e.quota?.limit, 'limit', 40)
            .having((e) => e.userMessage, 'message', contains('40 NOVA AI messages'))),
      );
      expect(a.requests, isEmpty);
    });

    test('limit message suggests the next plan', () {
      String msg(NovaTier p) => NovaApiClient.quotaMessage(
          NovaQuotaStatus(kind: NovaQuotaKind.chat, used: 40, limit: 40, plan: p));
      expect(msg(NovaTier.free), contains('AI Boost'));
      expect(msg(NovaTier.boost), contains('Premium'));
      expect(msg(NovaTier.premium), isNot(contains('Premium gives')));
    });
  });

  group('App update popup', () {
    test('version comparison', () {
      expect(UpdateService.isNewerVersion('3.10.0', '3.9.1'), isTrue);
      expect(UpdateService.isNewerVersion('3.9.1', '3.9.0'), isTrue);
      expect(UpdateService.isNewerVersion('3.9.0', '3.9.0'), isFalse);
      expect(UpdateService.isNewerVersion('3.8.9', '3.9.0'), isFalse);
      expect(UpdateService.isNewerVersion('3.9.0+18', '3.9.0'), isFalse);
      expect(UpdateService.isNewerVersion('abc', '3.9.0'), isFalse);
    });
    test('release data from the dashboard', () {
      final r = AppRelease.fromJson({
        'version': '3.9.1', 'build': 18, 'title': '', 'message': 'Faster',
        'whats_new': '- One\n• Two\n\n* Three', 'force_update': true, 'play_url': 'https://evil.example',
      })!;
      expect(r.title, 'A new version of NOVA X is ready');
      expect(r.whatsNew, ['One', 'Two', 'Three']);
      expect(r.forceUpdate, isTrue);
      expect(r.playUrl, PlatformApi.playStoreUrl);
      expect(AppRelease.fromJson({'version': '', 'build': 3}), isNull);
      expect(AppRelease.fromJson(null), isNull);
    });
  });

  group('Analytics', () {
    test('page names from screen classes', () {
      expect(AnalyticsService.featureFromType('NovaShieldScreen'), 'nova_shield');
      expect(AnalyticsService.featureFromType('AIAssistantScreen'), 'ai_assistant');
      expect(AnalyticsService.featureFromType('SupportScreen'), 'support');
      expect(AnalyticsService.featureFromType('NovaMusicPage'), 'nova_music');
      expect(AnalyticsService.featureFromType('X'), isNull);
    });
  });

  group('Support data', () {
    test('tickets and inbox items parse server JSON (UTC → local)', () {
      final t = SupportTicket.fromJson({
        'id': 3, 'ticket_no': 'NX-ABC123', 'category': 'billing', 'subject': 'Hi', 'status': 'answered',
        'priority': 'high', 'user_unread': 1, 'created_at': '2026-10-26T08:00:00Z', 'last_sender': 'admin',
      });
      expect(t.inInbox, isTrue);
      expect(t.createdAt!.toUtc(), DateTime.utc(2026, 10, 26, 8));
      final n = InboxItem.fromJson({'id': 1, 'kind': 'support_reply', 'title': 'x', 'ref_id': 3, 'is_read': false});
      expect(n.isSupport, isTrue);
      expect(n.refId, 3);
    });
  });
}
