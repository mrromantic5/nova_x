// lib/core/services/ai_feedback_service.dart
//
// 3.12.2: 👍 / 👎 on NOVA AI features (AI Playback first), with an optional
// comment for 👎. Goes to POST /api/v1/ai-feedback and shows up in the admin
// dashboard under AI reports › AI feedback. Works signed out too.

import 'package:dio/dio.dart';

import 'api_service.dart';
import 'app_info.dart';

class AiFeedbackService {
  AiFeedbackService._();

  static Dio dio = Dio(BaseOptions(
    baseUrl: ApiService.baseUrl,
    connectTimeout: const Duration(seconds: 12),
    receiveTimeout: const Duration(seconds: 20),
    validateStatus: (_) => true,
    headers: const {'Accept': 'application/json', 'Content-Type': 'application/json'},
  ));

  /// Web address without the query or #part (they can hold private data).
  static String pageRef(String url) {
    final u = Uri.tryParse(url);
    if (u == null || !u.hasScheme || u.host.isEmpty) return '';
    final path = u.path.length > 300 ? u.path.substring(0, 300) : u.path;
    return '${u.scheme}://${u.host}$path';
  }

  /// [feature]: playback | chat | coder | voice | vision | image | other.
  /// [rating]: 1 = 👍, -1 = 👎. Returns true when the server saved it.
  static Future<bool> send({
    required String feature,
    required int rating,
    String? comment,
    String? contentRef,
    String? title,
  }) async {
    try {
      final token = await ApiService.getToken();
      final res = await dio.post<Object>(
        '/api/v1/ai-feedback',
        data: {
          'feature': feature,
          'rating': rating > 0 ? 1 : -1,
          if (comment != null && comment.trim().isNotEmpty) 'comment': comment.trim(),
          if (contentRef != null && contentRef.isNotEmpty) 'content_ref': contentRef,
          if (title != null && title.isNotEmpty) 'title': title,
          'app_version': AppInfo.version,
        },
        options: Options(headers: {if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token'}),
      );
      return res.statusCode == 200 || res.statusCode == 201;
    } catch (_) {
      return false;
    }
  }
}
