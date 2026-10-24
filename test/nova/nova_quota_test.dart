// test/nova/nova_quota_test.dart
//
// 3.8.0: fair-use limits (5 photo uploads / 5 images every 2 hours), the
// tracked-reward setup checklist, and the NOVA X page labels.

import 'package:flutter_test/flutter_test.dart';
import 'package:nova_x/core/services/reward_device_sync.dart';
import 'package:nova_x/features/ai/services/nova_quota.dart';
import 'package:nova_x/features/nova/nova_features.dart';

void main() {
  const h = 3600 * 1000;
  final t0 = DateTime(2026, 10, 24, 9).millisecondsSinceEpoch;

  group('NovaQuotaWindow', () {
    test('five fit, the sixth does not', () {
      var (u, s) = (0, 0);
      for (var i = 0; i < 5; i++) {
        final next = NovaQuotaWindow.use(u, s, t0 + i * 1000, 1);
        expect(next, isNotNull, reason: 'use ${i + 1}');
        (u, s) = next!;
      }
      expect(u, 5);
      expect(s, t0); // the window starts with the first use
      expect(NovaQuotaWindow.use(u, s, t0 + 10 * 60 * 1000, 1), isNull);
    });

    test('several photos at once count together', () {
      final a = NovaQuotaWindow.use(0, 0, t0, 3)!;
      expect(a, (3, t0));
      expect(NovaQuotaWindow.use(a.$1, a.$2, t0 + 1000, 3), isNull); // 6 > 5
      expect(NovaQuotaWindow.use(a.$1, a.$2, t0 + 1000, 2), (5, t0));
    });

    test('the count resets 2 hours after the first use', () {
      expect(NovaQuotaWindow.current(5, t0, t0 + 2 * h - 1), (5, t0));
      expect(NovaQuotaWindow.current(5, t0, t0 + 2 * h), (0, 0));
      expect(NovaQuotaWindow.use(5, t0, t0 + 2 * h + 5, 1), (1, t0 + 2 * h + 5));
      expect(NovaQuotaWindow.resetAt(5, t0), DateTime.fromMillisecondsSinceEpoch(t0 + 2 * h));
      expect(NovaQuotaWindow.resetAt(0, 0), isNull);
    });

    test('a clock set back starts over; stored values are checked', () {
      expect(NovaQuotaWindow.current(4, t0, t0 - 1000), (0, 0));
      expect(NovaQuotaWindow.decode(NovaQuotaWindow.encode(3, t0)), (3, t0));
      expect(NovaQuotaWindow.decode('99|$t0'), (5, t0));
      expect(NovaQuotaWindow.decode('garbage'), (0, 0));
      expect(NovaQuotaWindow.decode(null), (0, 0));
    });

    test('status text helpers', () {
      final st = NovaQuotaStatus(
        kind: NovaQuotaKind.image,
        used: 5,
        resetAt: DateTime.fromMillisecondsSinceEpoch(t0 + 2 * h),
      );
      expect(st.exhausted, isTrue);
      expect(st.remaining, 0);
      expect(st.leftAt(DateTime.fromMillisecondsSinceEpoch(t0 + h)), const Duration(hours: 1));
      expect(st.leftAt(DateTime.fromMillisecondsSinceEpoch(t0 + 3 * h)), Duration.zero);
    });
  });

  group('NOVA setup reward checklist', () {
    test('complete only when all six settings are on', () {
      final all = {for (final k in NovaSetupStatus.keys) k: true};
      expect(NovaSetupStatus.fromMap(all).complete, isTrue);
      expect(NovaSetupStatus.fromMap({...all, 'battery': false}).complete, isFalse);
      expect(NovaSetupStatus.fromMap({...all, 'battery': false}).doneCount, 5);
      expect(NovaSetupStatus.fromMap(null).complete, isFalse);
      expect(NovaSetupStatus.keys, ['assistant', 'microphone', 'contacts', 'audio', 'overlay', 'battery']);
    });

    test('server events', () {
      final e = RewardSyncEvent.fromMap({'key': 'nova_setup', 'type': 'deducted', 'points': 100, 'message': 'x'});
      expect(e.type, 'deducted');
      expect(e.points, 100);
      expect(RewardSyncEvent.fromMap(const {}).points, 0);
    });
  });

  test('every NOVA X page has a name and opens', () {
    for (final id in NovaFeatures.ids) {
      expect(NovaFeatures.label(id), isNot('NOVA X'), reason: id);
      // 'home' pops back; 'new_tab' reads the search engine setting (needs the app's storage).
      if (id != 'home' && id != 'new_tab') expect(NovaFeatures.screenFor(id), isNotNull, reason: id);
    }
    expect(NovaFeatures.isValid('nova_music'), isTrue);
    expect(NovaFeatures.isValid('rm -rf'), isFalse);
    expect(NovaFeatures.isValid('unknown_page'), isFalse);
  });
}
