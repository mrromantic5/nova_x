// lib/core/services/news_service.dart
//
// Cascade priority:
//   1. GNews API      — 100 req/day,  best coverage, has images
//   2. SerpAPI        — 100 req/month, scrapes Google News, good images
//   3. NewsAPI.org    — 100 req/day,  dev-mode only (production needs paid plan)
//   4. HackerNews     — unlimited, tech-only, no images — always works

import 'package:dio/dio.dart';
import 'api_service.dart';
import 'offline_cache.dart';

// ─────────────────────────────────────────────────────────────────────────────
class NewsArticle {
  final String title;
  final String description;
  final String url;
  final String imageUrl;
  final String source;
  final String timeAgo;
  final String category;

  const NewsArticle({
    required this.title,
    required this.description,
    required this.url,
    required this.imageUrl,
    required this.source,
    required this.timeAgo,
    required this.category,
  });

  Map<String, String> toJson() => {
        't': title, 'd': description, 'u': url, 'i': imageUrl,
        's': source, 'a': timeAgo, 'c': category,
      };

  static NewsArticle? fromJson(Object? j) {
    if (j is! Map) return null;
    String g(String k) => j[k] is String ? j[k] as String : '';
    if (g('t').isEmpty || g('u').isEmpty) return null;
    return NewsArticle(
      title: g('t'), description: g('d'), url: g('u'), imageUrl: g('i'),
      source: g('s'), timeAgo: g('a'), category: g('c'),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
class NewsService {
  // 3.9.1: no API keys in the app. The NOVA X server fetches the news with
  // its own keys and caches each category for 20 minutes.
  static const _feed = '${ApiService.baseUrl}/api/v1/feed';

  // ── Category maps ─────────────────────────────────────────────────────────
  static const Map<String, String> _gNewsCategory = {
    'For You':       'general',
    'World':         'world',
    'Sports':        'sports',
    'Tech':          'technology',
    'Entertainment': 'entertainment',
    'Business':      'business',
    'Health':        'health',
    'Science':       'science',
  };

  static List<String> get categoryLabels => _gNewsCategory.keys.toList();

  // ── HTTP client ───────────────────────────────────────────────────────────
  static final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 12),
  ));

  // ── 1. GNews ──────────────────────────────────────────────────────────────
  static Future<List<NewsArticle>> _fromGNews(String category) async {
    try {
      final res = await _dio.get('$_feed/gnews', queryParameters: {'category': category});
      final articles = (res.data['articles'] as List?) ?? [];
      return articles
          .map((a) => NewsArticle(
                title:       _clean(a['title']),
                description: _clean(a['description']),
                url:         a['url']         ?? '',
                imageUrl:    a['image']        ?? '',
                source:      a['source']?['name'] ?? 'News',
                timeAgo:     _formatTime(a['publishedAt'] ?? ''),
                category:    category,
              ))
          .where((a) => a.title.isNotEmpty && a.url.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ── 2. SerpAPI (Google News) ──────────────────────────────────────────────
  static Future<List<NewsArticle>> _fromSerpApi(String category) async {
    try {
      final res = await _dio.get('$_feed/serp', queryParameters: {'category': category});
      final results = (res.data['news_results'] as List?) ?? [];
      final articles = <NewsArticle>[];

      for (final r in results) {
        // Some results are "story clusters" with nested stories
        if (r['stories'] != null) {
          for (final s in (r['stories'] as List).take(3)) {
            articles.add(NewsArticle(
              title:       _clean(s['title'] ?? r['title'] ?? ''),
              description: _clean(s['snippet'] ?? ''),
              url:         s['link']      ?? r['link'] ?? '',
              imageUrl:    s['thumbnail'] ?? r['thumbnail'] ?? '',
              source:      _serpSource(s['source'] ?? r['source']),
              timeAgo:     s['date'] ?? r['date'] ?? '',
              category:    category,
            ));
          }
        } else {
          articles.add(NewsArticle(
            title:       _clean(r['title']   ?? ''),
            description: _clean(r['snippet'] ?? ''),
            url:         r['link']      ?? '',
            imageUrl:    r['thumbnail'] ?? '',
            source:      _serpSource(r['source']),
            timeAgo:     r['date']      ?? '',
            category:    category,
          ));
        }
      }

      return articles
          .where((a) => a.title.isNotEmpty && a.url.isNotEmpty)
          .take(10)
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ── 3. NewsAPI.org (dev-mode fallback) ────────────────────────────────────
  static Future<List<NewsArticle>> _fromNewsApi(String category) async {
    try {
      final res = await _dio.get('$_feed/newsapi', queryParameters: {'category': category});
      if (res.data['status'] != 'ok') return [];
      final articles = (res.data['articles'] as List?) ?? [];
      return articles
          .map((a) => NewsArticle(
                title:       _clean(a['title']        ?? ''),
                description: _clean(a['description']  ?? ''),
                url:         a['url']                  ?? '',
                imageUrl:    a['urlToImage']            ?? '',
                source:      a['source']?['name']       ?? 'News',
                timeAgo:     _formatTime(a['publishedAt'] ?? ''),
                category:    category,
              ))
          .where((a) =>
              a.title.isNotEmpty &&
              a.url.isNotEmpty &&
              !a.title.contains('[Removed]'))
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ── 4. HackerNews (always works, tech only) ───────────────────────────────
  static Future<List<NewsArticle>> _fromHackerNews({int offset = 0, int count = 8}) async {
    try {
      final top = await _dio
          .get('https://hacker-news.firebaseio.com/v0/topstories.json');
      final ids = ((top.data as List).skip(offset).take(count)).toList();
      final articles = <NewsArticle>[];
      for (final id in ids) {
        try {
          final item = await _dio
              .get('https://hacker-news.firebaseio.com/v0/item/$id.json');
          final d = item.data;
          if (d?['title'] != null && d?['url'] != null) {
            articles.add(NewsArticle(
              title:       d['title'],
              description: '',
              url:         d['url'],
              imageUrl:    '',
              source:      'HackerNews',
              timeAgo:     'Now',
              category:    'Tech',
            ));
          }
        } catch (_) {}
      }
      return articles;
    } catch (_) {
      return [];
    }
  }

  // ── Public API ─────────────────────────────────────────────────────────────
  /// Returns up to 10 articles for [category].
  /// Tries all APIs in cascade order; falls back gracefully.
  /// 3.11.0 offline: true when the last page-1 result came from the copy
  /// saved on the phone (no internet), with the time it was saved.
  static bool lastFromCache = false;
  static DateTime? lastSavedAt;

  static Future<List<NewsArticle>> fetchNews(String category, {int page = 1}) async {
    if (page > 1) return _fetchLive(category, page: page);
    final live = await _fetchLive(category, page: 1);
    if (live.isNotEmpty) {
      lastFromCache = false;
      lastSavedAt = DateTime.now();
      OfflineCache.putJson('news_$category', live.take(20).map((a) => a.toJson()).toList());
      return live;
    }
    final saved = await savedNews(category);
    if (saved != null && saved.$1.isNotEmpty) {
      lastFromCache = true;
      lastSavedAt = saved.$2;
      return saved.$1;
    }
    lastFromCache = false;
    lastSavedAt = null;
    return live;
  }

  /// The last news saved for [category] (shown when offline).
  static Future<(List<NewsArticle>, DateTime)?> savedNews(String category) async {
    final r = await OfflineCache.getJson('news_$category');
    if (r == null || r.$1 is! List) return null;
    final list = (r.$1 as List).map(NewsArticle.fromJson).whereType<NewsArticle>().toList();
    return (list, r.$2);
  }

  static Future<List<NewsArticle>> _fetchLive(String category, {int page = 1}) async {
    if (page <= 1) {
      // 1. GNews — best: images + global coverage + 100 req/day
      var articles = await _fromGNews(category);
      if (articles.isNotEmpty) return articles;

      // 2. SerpAPI Google News — good images, 100 req/month
      articles = await _fromSerpApi(category);
      if (articles.isNotEmpty) return articles;

      // 3. NewsAPI — dev mode only
      articles = await _fromNewsApi(category);
      if (articles.isNotEmpty) return articles;

      // 4. HackerNews — always available, no images
      return _fromHackerNews();
    }

    // ── Load-more pages (caller de-duplicates by URL) ───────────────────────
    // page 2: a second image-rich source for variety
    if (page == 2) {
      final serp = await _fromSerpApi(category);
      if (serp.isNotEmpty) return serp;
      return _fromHackerNews(offset: 8, count: 12);
    }
    // page 3+: page deeper through HackerNews (always-available backfill)
    return _fromHackerNews(offset: (page - 2) * 12 + 8, count: 12);
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  static String _clean(String? s) {
    if (s == null) return '';
    // Remove trailing source attribution GNews sometimes appends
    final idx = s.lastIndexOf(' - ');
    return (idx > 40) ? s.substring(0, idx).trim() : s.trim();
  }

  static String _serpSource(dynamic src) {
    if (src is Map)    return src['name'] ?? 'News';
    if (src is String) return src;
    return 'News';
  }

  static String _formatTime(String iso) {
    if (iso.isEmpty) return '';
    try {
      final dt   = DateTime.parse(iso).toLocal();
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours   < 24) return '${diff.inHours}h ago';
      return '${diff.inDays}d ago';
    } catch (_) {
      return '';
    }
  }
}
