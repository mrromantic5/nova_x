// test/offline/offline_cache_test.dart
//
// 3.11.0 offline home: saved news and coin balance survive without
// internet; image cache file names are stable.

import 'package:flutter_test/flutter_test.dart';
import 'package:nova_x/core/services/news_service.dart';
import 'package:nova_x/core/services/offline_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('image cache keys are stable and distinct', () {
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

  test('saved news round-trips', () async {
    const a = NewsArticle(
        title: 'T', description: 'D', url: 'https://x.test/a', imageUrl: 'https://x.test/a.jpg', source: 'S', timeAgo: '1h', category: 'Tech');
    await OfflineCache.putJson('news_Tech', [a.toJson()]);
    final saved = await NewsService.savedNews('Tech');
    expect(saved, isNotNull);
    expect(saved!.$1.single.title, 'T');
    expect(saved.$1.single.imageUrl, 'https://x.test/a.jpg');
    expect(await NewsService.savedNews('Sports'), isNull);
  });

  test('broken entries are skipped', () {
    expect(NewsArticle.fromJson({'t': '', 'u': 'x'}), isNull);
    expect(NewsArticle.fromJson('nope'), isNull);
    expect(NewsArticle.fromJson({'t': 'ok', 'u': 'https://x'})?.title, 'ok');
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
