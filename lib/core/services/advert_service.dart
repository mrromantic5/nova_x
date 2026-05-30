// lib/core/services/advert_service.dart
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AdvertModel {
  final int    id;
  final String title;
  final String description;
  final String? mediaUrl;
  final String  mediaType; // 'none' | 'image' | 'video'
  final String? url;
  final int     recipients;
  final DateTime createdAt;

  const AdvertModel({
    required this.id,
    required this.title,
    required this.description,
    this.mediaUrl,
    required this.mediaType,
    this.url,
    required this.recipients,
    required this.createdAt,
  });

  factory AdvertModel.fromJson(Map<String, dynamic> j) => AdvertModel(
    id:          int.tryParse(j['id'].toString()) ?? 0,
    title:       j['title']       as String? ?? '',
    description: j['description'] as String? ?? '',
    mediaUrl:    j['media_url']   as String?,
    mediaType:   j['media_type']  as String? ?? 'none',
    url:         j['url']         as String?,
    recipients:  int.tryParse(j['recipients'].toString()) ?? 0,
    createdAt:   DateTime.tryParse(j['created_at'] as String? ?? '') ??
                 DateTime.now(),
  );
}

// ═══════════════════════════════════════════════════════════════════════════
class AdvertService {
  static const _baseUrl     = 'https://api.browser.t-lyfe.com.ng/adverts.php';
  static const _kReadIds    = 'nx_advert_read_ids';
  static const _kDismissIds = 'nx_advert_dismiss_ids';

  static final _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 8),
    validateStatus: (_) => true,
  ));

  static SharedPreferences? _prefs;
  static Future<void> init() async =>
      _prefs = await SharedPreferences.getInstance();

  // ── Fetch from server ────────────────────────────────────────────────────
  static Future<List<AdvertModel>> fetchAdverts() async {
    try {
      final r = await _dio.get(_baseUrl);
      if (r.statusCode != 200) return [];
      final data = r.data as Map<String, dynamic>?;
      if (data == null || data['success'] != true) return [];
      final list = data['adverts'] as List? ?? [];
      return list
          .map((e) => AdvertModel.fromJson(e as Map<String, dynamic>))
          .where((a) => !_isDismissed(a.id))
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ── Badge count ─────────────────────────────────────────────────────────
  // Returns count of adverts that haven't been read yet.
  // Call after fetchAdverts to pass the full list.
  static int getUnreadCount(List<AdvertModel> adverts) {
    final read = _getReadIds();
    return adverts.where((a) => !read.contains(a.id)).length;
  }

  // ── Mark all as read ────────────────────────────────────────────────────
  static Future<void> markAllRead(List<AdvertModel> adverts) async {
    final ids = adverts.map((a) => a.id.toString()).toList();
    await _prefs?.setStringList(_kReadIds, ids);
  }

  // ── Dismiss (swipe to delete) ───────────────────────────────────────────
  static Future<void> dismiss(int id) async {
    final ids = _getDismissIds()..add(id);
    await _prefs?.setStringList(
        _kDismissIds, ids.map((e) => e.toString()).toList());
  }

  // ── Private helpers ──────────────────────────────────────────────────────
  static Set<int> _getReadIds() =>
      (_prefs?.getStringList(_kReadIds) ?? [])
          .map((s) => int.tryParse(s) ?? -1)
          .toSet();

  static Set<int> _getDismissIds() =>
      (_prefs?.getStringList(_kDismissIds) ?? [])
          .map((s) => int.tryParse(s) ?? -1)
          .toSet();

  static bool _isDismissed(int id) => _getDismissIds().contains(id);
}
