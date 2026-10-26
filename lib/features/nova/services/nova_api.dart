// lib/features/nova/services/nova_api.dart
//
// Client for the NOVA AI Worker (Cloudflare). Contracts verified against the
// Worker source (v3.0.0):
//
//   POST /chat        {message, history[]}          → {success, reply, tokens_used}
//   POST /transcribe  multipart "audio"             → {success, transcript}
//   POST /plan        {message, history[]}          → {success, type, …}   (optional,
//                     backward-compatible extension; 404 ⇒ not deployed yet)
//   POST /vision      {message, history[], images[{mime, data}]} → {success, reply}
//                     (Worker 3.3.0+; 404 ⇒ not deployed yet)
//
// Errors use {success:false, error, code} with HTTP 400/413/415/429/5xx.
// All responses are treated as untrusted data.
//
// 3.9.0: every request carries "context": {tz, offset_min} (the phone's time
// zone) so NOVA knows the user's local date and time; questions that reach
// NOVA AI count toward the plan's daily message limit (NovaQuota).

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import '../../../core/services/device_clock.dart';
import '../../ai/services/nova_quota.dart';
import '../models/nova_models.dart';
import '../nova_config.dart';
import 'nova_validator.dart';
import '../../../core/services/analytics_service.dart';

enum NovaApiErrorKind {
  network,
  timeout,
  badRequest,
  tooLarge,
  unsupportedMedia,
  rateLimited,
  server,
  malformed,
  cancelled,
}

class NovaApiException implements Exception {
  const NovaApiException(this.kind, this.userMessage, {this.statusCode, this.quota});

  final NovaApiErrorKind kind;

  /// Safe, friendly sentence to show/speak to the user.
  final String userMessage;
  final int? statusCode;

  /// Set when today's NOVA AI message limit is used up (3.9.0).
  final NovaQuotaStatus? quota;

  @override
  String toString() => 'NovaApiException($kind, $statusCode)';
}

/// What the planner decided (already validated client-side).
class NovaPlannerResult {
  const NovaPlannerResult(this.plan, {this.tokensUsed = 0});
  final NovaPlan plan;
  final int tokensUsed;
}

/// An image for POST /vision (JPEG, PNG or WebP bytes, already resized).
class NovaVisionImage {
  const NovaVisionImage(this.bytes, this.mime);
  final List<int> bytes;
  final String mime;
}

/// Abstraction so the controller can be unit-tested with a fake.
abstract class NovaApi {
  Future<String> chat(String message, List<Map<String, String>> history, {CancelToken? cancel});
  Future<String> transcribe(String filePath, {CancelToken? cancel});

  /// Returns null when the Worker has no /plan endpoint (older deployment).
  Future<NovaPlannerResult?> plan(String message, List<Map<String, String>> history,
      {CancelToken? cancel});

  /// Question about 1–3 images (photos, screenshots, a captured screen).
  Future<String> vision(String message, List<Map<String, String>> history, List<NovaVisionImage> images,
      {CancelToken? cancel});

  void dispose();
}

/// Counts one NOVA AI question; throws [NovaApiException] (with `quota`) when
/// the daily limit is used up.
typedef NovaMessageMeter = Future<void> Function(String text);

class NovaApiClient implements NovaApi {
  NovaApiClient({Dio? dio, String? baseUrl, NovaMessageMeter? meter})
      : _meter = meter ?? meterMessage,
        _dio = dio ??
            Dio(BaseOptions(
              baseUrl: baseUrl ?? NovaConfig.apiBaseUrl,
              connectTimeout: NovaConfig.connectTimeout,
              receiveTimeout: NovaConfig.chatTimeout,
              sendTimeout: NovaConfig.voiceTimeout,
              responseType: ResponseType.json,
              headers: {'Accept': 'application/json'},
            ));

  final Dio _dio;
  final NovaMessageMeter _meter;

  static String? _lastCounted;
  static int _lastCountedAt = 0;

  /// The default meter: one question = one message, even when it goes to the
  /// planner first and then to /chat (same text within 2 minutes counts once).
  /// If the phone's storage can't be read, nothing is blocked.
  static Future<void> meterMessage(String text) async {
    final key = text.length > 300 ? text.substring(0, 300) : text;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (key == _lastCounted && now - _lastCountedAt < 120000) return;
    NovaQuotaStatus? blocked;
    try {
      blocked = await NovaQuota.tryUse(NovaQuotaKind.chat);
    } catch (_) {
      return;
    }
    if (blocked != null) {
      throw NovaApiException(NovaApiErrorKind.rateLimited, quotaMessage(blocked),
          statusCode: 429, quota: blocked);
    }
    _lastCounted = key;
    _lastCountedAt = now;
  }

  /// "You've used all 40 NOVA AI messages for today…"
  static String quotaMessage(NovaQuotaStatus q) {
    final at = q.resetAt;
    String when = 'later today';
    if (at != null) {
      final h = at.hour.toString().padLeft(2, '0');
      final m = at.minute.toString().padLeft(2, '0');
      final sameDay = at.day == DateTime.now().day;
      when = sameDay ? 'at $h:$m' : 'tomorrow at $h:$m';
    }
    final more = switch (q.plan) {
      NovaTier.free => ' Get double with AI Boost (Rewards) or 300 a day with NOVA X Premium.',
      NovaTier.boost => ' NOVA X Premium gives you 300 a day.',
      NovaTier.premium => '',
    };
    return "You've used all ${q.limit} NOVA AI messages for this 24-hour period. "
        'You can ask again $when.$more';
  }

  /// null = unknown, false = Worker without /plan (cached for this session).
  bool? _planSupported;

  @override
  Future<String> chat(String message, List<Map<String, String>> history,
      {CancelToken? cancel}) async {
    final text = _boundMessage(message);
    await _meter(text);
    final data = await _withRetry(() => _dio.post<Object>(
          '/chat',
          data: {'message': text, 'history': history, 'context': DeviceClock.context()},
          cancelToken: cancel,
        ));
    final reply = data['reply'];
    if (reply is! String || reply.trim().isEmpty) {
      throw const NovaApiException(NovaApiErrorKind.malformed,
          'NOVA sent an empty reply. Please try again.');
    }
    AnalyticsService.log('ai_chat', feature: 'nova_ai');
    return reply.trim();
  }

  /// Chat about 1–3 images (NOVA AI chat and the assistant panel). Not
  /// retried automatically: the upload can be large on slow connections.
  @override
  Future<String> vision(String message, List<Map<String, String>> history, List<NovaVisionImage> images,
      {CancelToken? cancel}) async {
    if (images.isEmpty) {
      throw const NovaApiException(NovaApiErrorKind.badRequest, 'Add a photo first.');
    }
    final text = message.trim();
    await _meter(text.isEmpty ? '(photo)' : text);
    final Map<String, dynamic> data;
    try {
      data = _decode(await _dio.post<Object>(
        '/vision',
        data: {
          'message': text.length > NovaConfig.maxVisionMessageChars
              ? text.substring(0, NovaConfig.maxVisionMessageChars)
              : text,
          'history': history,
          'context': DeviceClock.context(),
          'images': [
            for (final img in images.take(3)) {'mime': img.mime, 'data': base64Encode(img.bytes)},
          ],
        },
        cancelToken: cancel,
        options: Options(sendTimeout: NovaConfig.voiceTimeout, receiveTimeout: NovaConfig.voiceTimeout),
      ));
    } on DioException catch (e) {
      final error = mapError(e);
      if (error.statusCode == 404 || error.statusCode == 405) {
        throw const NovaApiException(NovaApiErrorKind.badRequest,
            "Reading photos isn't switched on yet on the NOVA AI server (needs the 3.3.0 update).",
            statusCode: 404);
      }
      if (error.statusCode == 413) {
        throw const NovaApiException(NovaApiErrorKind.tooLarge,
            'That photo is too large. Try a smaller one.', statusCode: 413);
      }
      throw error;
    }
    final reply = data['reply'];
    if (reply is! String || reply.trim().isEmpty) {
      throw const NovaApiException(NovaApiErrorKind.malformed,
          'NOVA sent an empty reply. Please try again.');
    }
    return reply.trim();
  }

  @override
  Future<String> transcribe(String filePath, {CancelToken? cancel}) async {
    final file = File(filePath);
    if (!await file.exists() || await file.length() == 0) {
      throw const NovaApiException(NovaApiErrorKind.badRequest, "I didn't catch any audio.");
    }
    final data = await _withRetry(() async {
      // FormData can only be sent once, so it is rebuilt for each attempt.
      final form = FormData.fromMap({
        'audio': await MultipartFile.fromFile(
          filePath,
          filename: 'nova_voice.m4a',
          contentType: DioMediaType('audio', 'mp4'),
        ),
      });
      return _dio.post<Object>(
        '/transcribe',
        data: form,
        cancelToken: cancel,
        options: Options(receiveTimeout: NovaConfig.voiceTimeout),
      );
    });
    final transcript = data['transcript'];
    return transcript is String ? transcript.trim() : '';
  }

  @override
  Future<NovaPlannerResult?> plan(String message, List<Map<String, String>> history,
      {CancelToken? cancel}) async {
    if (_planSupported == false) return null;
    await _meter(_boundMessage(message));
    final Map<String, dynamic> data;
    try {
      data = await _withRetry(() => _dio.post<Object>(
            '/plan',
            data: {'message': _boundMessage(message), 'history': history, 'context': DeviceClock.context()},
            cancelToken: cancel,
          ));
    } on NovaApiException catch (e) {
      if (e.statusCode == 404 || e.statusCode == 405) {
        _planSupported = false; // older Worker — use /chat for this session
        return null;
      }
      rethrow;
    }
    _planSupported = true;
    final tokens = data['tokens_used'];
    final plan = parsePlanResponse(data);
    if (plan == null) return null;
    return NovaPlannerResult(plan, tokensUsed: tokens is int ? tokens : 0);
  }

  /// Validates a /plan response. Invalid actions are dropped; if nothing
  /// valid remains, falls back to the planner's reply text (or null).
  static NovaPlan? parsePlanResponse(Map<String, dynamic> data) {
    final type = data['type'];
    String? str(Object? v) => v is String && v.trim().isNotEmpty ? v.trim() : null;

    if (type == 'actions') {
      final raw = data['actions'];
      final actions = <NovaAction>[];
      if (raw is List) {
        for (final item in raw.take(NovaConfig.maxPlanSteps)) {
          if (item is Map) {
            final a = NovaActionValidator.fromPlanner(item['name']?.toString(), item['args']);
            if (a != null) actions.add(a);
          }
        }
      }
      if (actions.isNotEmpty) {
        return NovaActionsPlan(actions, speak: str(data['speak']));
      }
      final fallback = str(data['reply']) ?? str(data['speak']);
      return fallback == null ? null : NovaReplyPlan(fallback, fromAi: true);
    }
    if (type == 'clarify') {
      final q = str(data['question']);
      if (q == null) return null;
      final opts = <String>[];
      final rawOpts = data['options'];
      if (rawOpts is List) {
        for (final o in rawOpts.take(5)) {
          final s = str(o);
          if (s != null && s.length <= 60) opts.add(s);
        }
      }
      return NovaClarifyPlan(q, options: opts);
    }
    final reply = str(data['reply']);
    return reply == null ? null : NovaReplyPlan(reply, fromAi: true);
  }

  // ── Transport ───────────────────────────────────────────────────────────

  String _boundMessage(String message) {
    final t = message.trim();
    return t.length > NovaConfig.maxMessageChars
        ? t.substring(0, NovaConfig.maxMessageChars)
        : t;
  }

  /// One retry, only for fast transient failures (no connection, 502, 503).
  Future<Map<String, dynamic>> _withRetry(Future<Response<Object>> Function() send) async {
    try {
      return _decode(await send());
    } on DioException catch (e) {
      final error = mapError(e);
      final retryable = error.kind == NovaApiErrorKind.network ||
          error.statusCode == 502 ||
          error.statusCode == 503;
      if (!retryable) throw error;
      await Future<void>.delayed(const Duration(milliseconds: 700));
      try {
        return _decode(await send());
      } on DioException catch (e2) {
        throw mapError(e2);
      }
    }
  }

  static Map<String, dynamic> _decode(Response<Object> res) {
    Object? body = res.data;
    if (body is String) {
      try {
        body = jsonDecode(body);
      } catch (_) {
        body = null;
      }
    }
    if (body is! Map) {
      throw const NovaApiException(
          NovaApiErrorKind.malformed, 'NOVA sent an unexpected response. Please try again.');
    }
    final map = Map<String, dynamic>.from(body);
    if (map['success'] == false) {
      throw NovaApiException(NovaApiErrorKind.server, _serverMessage(map),
          statusCode: res.statusCode);
    }
    return map;
  }

  /// Maps transport/HTTP failures to safe user-facing messages.
  static NovaApiException mapError(DioException e) {
    switch (e.type) {
      case DioExceptionType.cancel:
        return const NovaApiException(NovaApiErrorKind.cancelled, 'Cancelled.');
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return const NovaApiException(NovaApiErrorKind.timeout,
            'NOVA is taking too long to respond. Please try again.');
      case DioExceptionType.connectionError:
        return const NovaApiException(NovaApiErrorKind.network,
            "You're offline or the connection dropped. Check your internet and try again.");
      case DioExceptionType.badResponse:
        final code = e.response?.statusCode ?? 0;
        return _forStatus(code);
      case DioExceptionType.badCertificate:
        return const NovaApiException(NovaApiErrorKind.network,
            "NOVA couldn't make a secure connection. Please try again later.");
      default: // DioExceptionType.unknown and any type added by future Dio versions
        if (e.error is SocketException) {
          return const NovaApiException(NovaApiErrorKind.network,
              "You're offline or the connection dropped. Check your internet and try again.");
        }
        return const NovaApiException(
            NovaApiErrorKind.network, 'Something went wrong reaching NOVA. Please try again.');
    }
  }

  static NovaApiException _forStatus(int code) {
    switch (code) {
      case 400:
        return const NovaApiException(NovaApiErrorKind.badRequest,
            "NOVA couldn't understand that request.", statusCode: 400);
      case 404:
      case 405:
        return NovaApiException(NovaApiErrorKind.badRequest,
            'That NOVA feature is not available yet.', statusCode: code);
      case 413:
        return const NovaApiException(NovaApiErrorKind.tooLarge,
            "That's too long for me. Please try something shorter.", statusCode: 413);
      case 415:
        return const NovaApiException(NovaApiErrorKind.unsupportedMedia,
            "I couldn't process that audio. Please try again.", statusCode: 415);
      case 429:
        return const NovaApiException(NovaApiErrorKind.rateLimited,
            "I'm getting a lot of requests right now. Please wait a moment and try again.",
            statusCode: 429);
      default:
        return NovaApiException(NovaApiErrorKind.server,
            'NOVA is temporarily unavailable. Please try again shortly.', statusCode: code);
    }
  }

  static String _serverMessage(Map<String, dynamic> map) {
    final code = map['code'];
    if (code is int && code != 200) return _forStatus(code).userMessage;
    return 'NOVA is temporarily unavailable. Please try again shortly.';
  }

  @override
  void dispose() => _dio.close(force: true);
}
