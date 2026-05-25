// lib/core/services/news_service.dart
//
// Cascade priority:
//   1. GNews API      — 100 req/day,  best coverage, has images
//   2. SerpAPI        — 100 req/month, scrapes Google News, good images
//   3. NewsAPI.org    — 100 req/day,  dev-mode only (production needs paid plan)
//   4. HackerNews     — unlimited, tech-only, no images — always works

import 'package:dio/dio.dart';

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
}

// ─────────────────────────────────────────────────────────────────────────────
class NewsService {
  // ── API Keys ──────────────────────────────────────────────────────────────
  static const _gNewsKey   = 'dddac3111ff3a0f86578effcad1cf01c';
  static const _newsApiKey = 'f047822f6e36405980259abb8d12afc3';
  static const _serpApiKey =
      '794180687cbc34a9eb77cece2a5ec05212ce4f4c7d200ec93c2eb61de18e56c6';

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

  static const Map<String, String> _newsApiCategory = {
    'For You':       'general',
    'World':         'general',   // newsapi has no "world" category
    'Sports':        'sports',
    'Tech':          'technology',
    'Entertainment': 'entertainment',
    'Business':      'business',
    'Health':        'health',
    'Science':       'science',
  };

  static String _serpQuery(String label) {
    if (label == 'For You') return 'top news today';
    return '${label.toLowerCase()} news';
  }

  static List<String> get categoryLabels => _gNewsCategory.keys.toList();

  // ── HTTP client ───────────────────────────────────────────────────────────
  static final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 12),
  ));

  // ── 1. GNews ──────────────────────────────────────────────────────────────
  static Future<List<NewsArticle>> _fromGNews(String category) async {
    try {
      final res = await _dio.get(
        'https://gnews.io/api/v4/top-headlines',
        queryParameters: {
          'token':    _gNewsKey,
          'lang':     'en',       // global English news (all countries)
          'max':      10,
          'category': _gNewsCategory[category] ?? 'general',
          'expand':   'content',
        },
      );
      final articles = (res.data['articles'] as List?) ?? [];
      return articles
          .map((a) => NewsArticle(
                title:       _clean(a['title']),
                description: _clean(a['description']),
                url:         a['url']         ?? '',
                imageUrl:    a['image']        ?? '',
                source:      a['source']?['name'] ?? 'GNews',
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
      final res = await _dio.get(
        'https://serpapi.com/search',
        queryParameters: {
          'engine':  'google_news',
          'api_key': _serpApiKey,
          'q':       _serpQuery(category),
          'hl':      'en',
          'gl':      'us',
        },
      );
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
      final res = await _dio.get(
        'https://newsapi.org/v2/top-headlines',
        queryParameters: {
          'apiKey':   _newsApiKey,
          'category': _newsApiCategory[category] ?? 'general',
          'language': 'en',
          'pageSize': 10,
        },
      );
      if (res.data['status'] != 'ok') return [];
      final articles = (res.data['articles'] as List?) ?? [];
      return articles
          .map((a) => NewsArticle(
                title:       _clean(a['title']        ?? ''),
                description: _clean(a['description']  ?? ''),
                url:         a['url']                  ?? '',
                imageUrl:    a['urlToImage']            ?? '',
                source:      a['source']?['name']       ?? 'NewsAPI',
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
  static Future<List<NewsArticle>> _fromHackerNews() async {
    try {
      final top = await _dio
          .get('https://hacker-news.firebaseio.com/v0/topstories.json');
      final ids = ((top.data as List).take(8)).toList();
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
  static Future<List<NewsArticle>> fetchNews(String category) async {
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
