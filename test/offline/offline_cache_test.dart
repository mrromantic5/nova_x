// test/offline/offline_cache_test.dart
//
// Offline snapshots (business listings, coin balance) survive without
// internet; storage keys are stable. (3.11.3: news and pictures are no
// longer cached.)

import 'package:flutter_test/flutter_test.dart';
import 'package:nova_x/core/services/offline_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('storage keys are stable and distinct', () {
    final a = OfflineCache.keyFor('https://www.google.com/s2/favicons?domain=github.com&sz=64');
    expect(a, OfflineCache.keyFor('https://www.google.com/s2/favicons?domain=github.com&sz=64'));
    expect(a, isNot(OfflineCache.keyFor('https://www.google.com/s2/favicons?domain=gitlab.com&sz=64')));
    expect(a, matches(RegExp(r'^[0-9a-f]{16}$')));
  });

  test('JSON snapshots keep the value and the time saved', () async {
    await OfflineCache.putJson('t', {'x': 1});
    final r = await OfflineCache.getJson('t');
    expect(r, isNotNull);
    expect(r!.$1, {'x': 1});
    expect(DateTime.now().difference(r.$2).inSeconds, lessThan(5));
    await OfflineCache.remove('t');
    expect(await OfflineCache.getJson('t'), isNull);
  });

  test('business listings are kept for offline use', () async {
    await OfflineCache.putJson('businesses', [
      {'id': 1, 'name': 'Kobby Tech', 'category': 'Technology', 'image_url': 'https://x.test/a.png'},
    ]);
    final saved = await OfflineCache.getJson('businesses');
    expect((saved!.$1 as List).single, containsPair('name', 'Kobby Tech'));
  });

  test('age labels', () {
    expect(OfflineCache.age(DateTime.now()), 'just now');
    expect(OfflineCache.age(DateTime.now().subtract(const Duration(minutes: 5))), '5 min ago');
    expect(OfflineCache.age(DateTime.now().subtract(const Duration(hours: 3))), '3 h ago');
    expect(OfflineCache.age(DateTime.now().subtract(const Duration(days: 1))), '1 day ago');
  });
}
