// lib/core/services/ai_flag_service.dart
//
// NOVA X — AI-Generated Content Report Service
// Google Play AI-Generated Content Policy compliance.
// v2.0.0 — Font Awesome icons, professional SaaS-grade design

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'api_service.dart';

// ── Category model ─────────────────────────────────────────────────────────
class AiFlagCategory {
  final String   key;
  final String   label;
  final String   description;
  final IconData icon;
  final Color    iconColor;
  final Color    iconBg;

  const AiFlagCategory({
    required this.key,
    required this.label,
    required this.description,
    required this.icon,
    required this.iconColor,
    required this.iconBg,
  });
}

// ── Service ────────────────────────────────────────────────────────────────
class AiFlagService {
  static const List<AiFlagCategory> categories = [
    AiFlagCategory(
      key:         'offensive',
      label:       'Offensive Content',
      description: 'Hate speech, slurs, or targeted harassment',
      icon:        FontAwesomeIcons.userSlash,
      iconColor:   Color(0xFFFF4444),
      iconBg:      Color(0x22FF4444),
    ),
    AiFlagCategory(
      key:         'harmful',
      label:       'Harmful / Dangerous',
      description: 'Content that could cause real-world harm',
      icon:        FontAwesomeIcons.triangleExclamation,
      iconColor:   Color(0xFFFFAB00),
      iconBg:      Color(0x22FFAB00),
    ),
    AiFlagCategory(
      key:         'sexual',
      label:       'Sexual / Explicit',
      description: 'Sexually explicit or inappropriate content',
      icon:        FontAwesomeIcons.eyeSlash,
      iconColor:   Color(0xFFFF6B9D),
      iconBg:      Color(0x22FF6B9D),
    ),
    AiFlagCategory(
      key:         'violent',
      label:       'Violence / Gore',
      description: 'Graphic violence, threats, or disturbing imagery',
      icon:        FontAwesomeIcons.bolt,
      iconColor:   Color(0xFFFF7043),
      iconBg:      Color(0x22FF7043),
    ),
    AiFlagCategory(
      key:         'misinformation',
      label:       'Misinformation',
      description: 'False, misleading, or deceptive content',
      icon:        FontAwesomeIcons.circleXmark,
      iconColor:   Color(0xFFFFC107),
      iconBg:      Color(0x22FFC107),
    ),
    AiFlagCategory(
      key:         'privacy',
      label:       'Privacy Violation',
      description: 'Exposes personal or private information',
      icon:        FontAwesomeIcons.lock,
      iconColor:   Color(0xFF00D4FF),
      iconBg:      Color(0x2200D4FF),
    ),
    AiFlagCategory(
      key:         'spam',
      label:       'Spam / Scam',
      description: 'Promotional spam, phishing, or scam content',
      icon:        FontAwesomeIcons.envelopeCircleCheck,
      iconColor:   Color(0xFF7C4DFF),
      iconBg:      Color(0x227C4DFF),
    ),
    AiFlagCategory(
      key:         'other',
      label:       'Other Issue',
      description: 'Another concern not listed above',
      icon:        FontAwesomeIcons.ellipsis,
      iconColor:   Color(0xFFB0C4DE),
      iconBg:      Color(0x22B0C4DE),
    ),
  ];

  static final Dio _dio = Dio(BaseOptions(
    baseUrl:        ApiService.baseUrl,
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
    validateStatus: (_) => true,
    headers:        const {'Accept': 'application/json'},
  ));

  /// Submit a flag report. Returns true on success.
  static Future<bool> submitReport({
    required String contentType,
    required String reasonKey,
    required String reasonLabel,
    String?         contentRef,
    String?         description,
  }) async {
    try {
      final token = await ApiService.getToken();
      final user  = await ApiService.getCachedUser();

      final payload = <String, dynamic>{
        'content_type': contentType,
        'reason':       reasonKey,
        'reason_label': reasonLabel,
        if (contentRef  != null && contentRef.isNotEmpty)
          'content_ref': contentRef,
        if (description != null && description.isNotEmpty)
          'description': description,
        if (user?['username'] != null) 'username': user!['username'],
        if (user?['email']    != null) 'email':    user!['email'],
      };

      final res = await _dio.post(
        '/api/v1/ai-flag-report',
        data:    payload,
        options: Options(headers: {
          'Content-Type':  'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        }),
      );
      return res.statusCode == 200 || res.statusCode == 201;
    } catch (_) {
      return false;
    }
  }
}
