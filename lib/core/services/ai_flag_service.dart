// lib/core/services/ai_flag_service.dart
//
// NOVA X — AI-Generated Content Report Service
// Google Play AI-Generated Content Policy compliance.
// v1.0.0 — verified clean

import 'package:dio/dio.dart';
import 'api_service.dart';

// ── Category model ─────────────────────────────────────────────────────────
class AiFlagCategory {
  final String key;
  final String label;
  final String emoji;
  final String description;

  const AiFlagCategory({
    required this.key,
    required this.label,
    required this.emoji,
    required this.description,
  });
}

// ── Service ────────────────────────────────────────────────────────────────
class AiFlagService {
  // All report categories — keys must match PHP whitelist in index.php
  static const List<AiFlagCategory> categories = [
    AiFlagCategory(
      key:         'offensive',
      label:       'Offensive Content',
      emoji:       '\u{1F6AB}',
      description: 'Hate speech, slurs, or targeted harassment',
    ),
    AiFlagCategory(
      key:         'harmful',
      label:       'Harmful / Dangerous',
      emoji:       '\u26A0\uFE0F',
      description: 'Content that could cause real-world harm',
    ),
    AiFlagCategory(
      key:         'sexual',
      label:       'Sexual / Explicit',
      emoji:       '\u{1F51E}',
      description: 'Sexually explicit or inappropriate content',
    ),
    AiFlagCategory(
      key:         'violent',
      label:       'Violence / Gore',
      emoji:       '\u{1F4A2}',
      description: 'Graphic violence, threats, or disturbing imagery',
    ),
    AiFlagCategory(
      key:         'misinformation',
      label:       'Misinformation',
      emoji:       '\u{1F4E2}',
      description: 'False, misleading, or deceptive content',
    ),
    AiFlagCategory(
      key:         'privacy',
      label:       'Privacy Violation',
      emoji:       '\u{1F510}',
      description: 'Exposes personal or private information',
    ),
    AiFlagCategory(
      key:         'spam',
      label:       'Spam / Scam',
      emoji:       '\u{1F4E7}',
      description: 'Promotional spam, phishing, or scam content',
    ),
    AiFlagCategory(
      key:         'other',
      label:       'Other Issue',
      emoji:       '\u{1F4DD}',
      description: 'Another concern not listed above',
    ),
  ];

  static final Dio _dio = Dio(BaseOptions(
    baseUrl:         ApiService.baseUrl,
    connectTimeout:  const Duration(seconds: 15),
    receiveTimeout:  const Duration(seconds: 30),
    validateStatus:  (_) => true, // handle errors ourselves
    headers:         const {'Accept': 'application/json'},
  ));

  /// Submit a flag report to the backend. Returns true on success.
  /// Works for both authenticated and guest users.
  static Future<bool> submitReport({
    required String contentType,  // 'text' | 'image' | 'video'
    required String reasonKey,
    required String reasonLabel,
    String?         contentRef,   // URL or first 500 chars of AI text
    String?         description,  // optional extra detail from user
  }) async {
    try {
      final token = await ApiService.getToken();
      final user  = await ApiService.getCachedUser();

      final Map<String, dynamic> payload = {
        'content_type': contentType,
        'reason':        reasonKey,
        'reason_label':  reasonLabel,
        if (contentRef  != null && contentRef.isNotEmpty)
          'content_ref':  contentRef,
        if (description != null && description.isNotEmpty)
          'description':  description,
        if (user != null && user['username'] != null)
          'username': user['username'],
        if (user != null && user['email'] != null)
          'email': user['email'],
      };

      final headers = <String, String>{
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

      final res = await _dio.post(
        '/api/v1/ai-flag-report',
        data:    payload,
        options: Options(headers: headers),
      );

      // Accept 200 or 201 as success
      return res.statusCode == 200 || res.statusCode == 201;
    } catch (_) {
      return false;
    }
  }
}
