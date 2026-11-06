// lib/features/playback/playback_api.dart
//
// AI Playback (3.12.0): asks the NOVA AI Worker (POST /playback) to write the
// two-host conversation from the page text read on the phone. The Worker
// holds the AI key; the app sends only the page's text, title and address.

import 'dart:convert';

import 'package:dio/dio.dart';

import '../nova/nova_config.dart';
import 'playback_models.dart';
import 'playback_page_reader.dart';

class PlaybackException implements Exception {
  const PlaybackException(this.message, {this.status});
  final String message;
  final int? status;
  @override
  String toString() => message;
}

class PlaybackApi {
  PlaybackApi({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: NovaConfig.apiBaseUrl,
              connectTimeout: const Duration(seconds: 12),
              receiveTimeout: const Duration(seconds: 60),
              sendTimeout: const Duration(seconds: 30),
              headers: {'Accept': 'application/json', 'Content-Type': 'application/json'},
            ));

  final Dio _dio;

  Future<PlaybackScript> script(PageSnapshot page, {required String lang, CancelToken? cancel}) async {
    try {
      final r = await _dio.post<Object>('/playback',
          data: {
            'url': page.url,
            'title': page.title,
            'lang': lang,
            'description': page.description,
            'text': page.text.length > 20000 ? page.text.substring(0, 20000) : page.text,
            'headings': page.headings.take(40).toList(),
          },
          cancelToken: cancel);
      var d = r.data;
      if (d is String) d = jsonDecode(d);
      if (d is! Map || d['success'] != true) throw const PlaybackException('AI Playback couldn’t be created. Please try again.');
      final s = PlaybackScript.fromJson(Map<String, dynamic>.from(d), host: page.host, url: page.url);
      if (s == null) throw const PlaybackException('AI Playback couldn’t be created for this page.');
      return s;
    } on DioException catch (e) {
      if (e.type == DioExceptionType.cancel) throw const PlaybackException('Stopped.');
      if (e.type == DioExceptionType.connectionError || e.type == DioExceptionType.connectionTimeout) {
        throw const PlaybackException('You’re offline. AI Playback needs the internet.');
      }
      if (e.type == DioExceptionType.receiveTimeout) {
        throw const PlaybackException('AI Playback is taking too long. Please try again.');
      }
      final status = e.response?.statusCode;
      var data = e.response?.data;
      if (data is String) {
        try {
          data = jsonDecode(data);
        } catch (_) {}
      }
      final msg = data is Map && data['error'] is String ? data['error'] as String : null;
      throw PlaybackException(
        switch (status) {
          422 => msg ?? 'This page doesn’t have enough text for AI Playback.',
          429 => 'Too many requests. Please wait a minute and try again.',
          _ => msg ?? 'AI Playback couldn’t be created. Please try again.',
        },
        status: status,
      );
    } on FormatException {
      throw const PlaybackException('AI Playback couldn’t be created. Please try again.');
    }
  }

  void dispose() => _dio.close(force: true);
}
