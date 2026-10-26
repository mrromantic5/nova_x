// lib/core/services/platform_api.dart
//
// 3.9.0 — client for the NOVA X platform API (nova_platform.php):
// support tickets, issue reports, the personal inbox (support replies),
// the "update available" release published from the admin dashboard and
// privacy-light usage analytics. All server times are UTC and are shown in
// the phone's local time (ServerTime).

import 'package:dio/dio.dart';

import 'api_service.dart';
import 'device_clock.dart';

/// A failed call with a message that can be shown as is.
class NovaServiceError implements Exception {
  const NovaServiceError(this.message, {this.status});
  final String message;
  final int? status;
  @override
  String toString() => message;
}

class SupportTicket {
  const SupportTicket({
    required this.id,
    required this.ticketNo,
    required this.category,
    required this.subject,
    required this.status,
    required this.priority,
    required this.userUnread,
    this.rating,
    this.createdAt,
    this.lastMessageAt,
    this.closedAt,
    this.lastMessage,
    this.lastSender,
  });

  final int id;
  final String ticketNo;
  final String category;
  final String subject;

  /// open · pending · answered · closed
  final String status;
  final String priority;
  final int userUnread;
  final int? rating;
  final DateTime? createdAt;
  final DateTime? lastMessageAt;
  final DateTime? closedAt;
  final String? lastMessage;

  /// user · admin · system
  final String? lastSender;

  bool get isClosed => status == 'closed';

  /// Inbox = NOVA Support has answered (or the ticket has unread replies).
  bool get inInbox => userUnread > 0 || lastSender == 'admin' || status == 'answered';

  factory SupportTicket.fromJson(Map<String, dynamic> j) => SupportTicket(
        id: _int(j['id']),
        ticketNo: '${j['ticket_no'] ?? ''}',
        category: '${j['category'] ?? 'other'}',
        subject: '${j['subject'] ?? ''}',
        status: '${j['status'] ?? 'open'}',
        priority: '${j['priority'] ?? 'normal'}',
        userUnread: _int(j['user_unread']),
        rating: j['rating'] == null ? null : _int(j['rating']),
        createdAt: ServerTime.parse(j['created_at']),
        lastMessageAt: ServerTime.parse(j['last_message_at']),
        closedAt: ServerTime.parse(j['closed_at']),
        lastMessage: j['last_message'] as String?,
        lastSender: j['last_sender'] as String?,
      );
}

class SupportMessage {
  const SupportMessage({required this.id, required this.sender, required this.body, this.senderName, this.createdAt});
  final int id;

  /// user · admin · system
  final String sender;
  final String? senderName;
  final String body;
  final DateTime? createdAt;

  factory SupportMessage.fromJson(Map<String, dynamic> j) => SupportMessage(
        id: _int(j['id']),
        sender: '${j['sender'] ?? 'system'}',
        senderName: j['sender_name'] as String?,
        body: '${j['body'] ?? ''}',
        createdAt: ServerTime.parse(j['created_at']),
      );
}

class IssueReport {
  const IssueReport({
    required this.id,
    required this.reportNo,
    required this.category,
    required this.severity,
    required this.title,
    required this.status,
    this.createdAt,
    this.updatedAt,
  });
  final int id;
  final String reportNo;
  final String category;
  final String severity;
  final String title;

  /// new · reviewing · resolved · wont_fix
  final String status;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory IssueReport.fromJson(Map<String, dynamic> j) => IssueReport(
        id: _int(j['id']),
        reportNo: '${j['report_no'] ?? ''}',
        category: '${j['category'] ?? 'other'}',
        severity: '${j['severity'] ?? 'medium'}',
        title: '${j['title'] ?? ''}',
        status: '${j['status'] ?? 'new'}',
        createdAt: ServerTime.parse(j['created_at']),
        updatedAt: ServerTime.parse(j['updated_at']),
      );
}

class InboxItem {
  const InboxItem({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.isRead,
    this.refId,
    this.createdAt,
  });
  final int id;

  /// support_reply · support_closed · system
  final String kind;
  final String title;
  final String body;
  final int? refId;
  final bool isRead;
  final DateTime? createdAt;

  bool get isSupport => kind.startsWith('support');

  factory InboxItem.fromJson(Map<String, dynamic> j) => InboxItem(
        id: _int(j['id']),
        kind: '${j['kind'] ?? 'system'}',
        title: '${j['title'] ?? ''}',
        body: '${j['body'] ?? ''}',
        refId: j['ref_id'] == null ? null : _int(j['ref_id']),
        isRead: j['is_read'] == true || j['is_read'] == 1,
        createdAt: ServerTime.parse(j['created_at']),
      );
}

/// A release published from the admin dashboard.
class AppRelease {
  const AppRelease({
    required this.version,
    required this.build,
    required this.title,
    required this.message,
    required this.whatsNew,
    required this.forceUpdate,
    required this.playUrl,
  });
  final String version;
  final int build;
  final String title;
  final String message;
  final List<String> whatsNew;
  final bool forceUpdate;
  final String playUrl;

  static AppRelease? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final j = Map<String, dynamic>.from(raw);
    final version = '${j['version'] ?? ''}'.trim();
    final build = _int(j['build']);
    if (version.isEmpty || build <= 0) return null;
    final url = '${j['play_url'] ?? ''}';
    return AppRelease(
      version: version,
      build: build,
      title: '${j['title'] ?? ''}'.trim().isEmpty ? 'A new version of NOVA X is ready' : '${j['title']}',
      message: '${j['message'] ?? ''}',
      whatsNew: '${j['whats_new'] ?? ''}'
          .split('\n')
          .map((l) => l.replaceFirst(RegExp(r'^\s*[-•*]\s*'), '').trim())
          .where((l) => l.isNotEmpty)
          .take(8)
          .toList(),
      forceUpdate: j['force_update'] == true || j['force_update'] == 1,
      playUrl: url.startsWith('https://play.google.com/') ? url : PlatformApi.playStoreUrl,
    );
  }
}

int _int(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;

class PlatformApi {
  PlatformApi._();

  static const playStoreUrl = 'https://play.google.com/store/apps/details?id=com.tlyfe.nova_x';

  static final Dio _dio = Dio(BaseOptions(
    baseUrl: ApiService.baseUrl,
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 25),
    headers: {'Accept': 'application/json'},
    validateStatus: (_) => true,
  ));

  static Future<Options> _opts({bool auth = true}) async {
    final token = auth ? await ApiService.getToken() : null;
    return Options(headers: {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    });
  }

  static Map<String, dynamic> _ok(Response<dynamic> r) {
    final d = r.data;
    final map = d is Map ? Map<String, dynamic>.from(d) : <String, dynamic>{};
    final code = r.statusCode ?? 0;
    if (code >= 200 && code < 300) return map;
    if (code == 401) {
      throw const NovaServiceError('Please sign in to NOVA X first.', status: 401);
    }
    final msg = map['message'];
    throw NovaServiceError(
        msg is String && msg.isNotEmpty ? msg : 'Something went wrong. Please try again.',
        status: code);
  }

  static Future<T> _guard<T>(Future<T> Function() f) async {
    try {
      return await f();
    } on NovaServiceError {
      rethrow;
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        throw const NovaServiceError("You're offline. Check your internet and try again.");
      }
      throw const NovaServiceError('Something went wrong. Please try again.');
    } catch (_) {
      throw const NovaServiceError('Something went wrong. Please try again.');
    }
  }

  // ── Support ──────────────────────────────────────────────────
  static Future<({List<SupportTicket> tickets, int unread})> tickets() => _guard(() async {
        final m = _ok(await _dio.get('/api/v1/support/tickets', options: await _opts()));
        final list = (m['tickets'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => SupportTicket.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        return (tickets: list, unread: _int(m['unread']));
      });

  static Future<({SupportTicket ticket, List<SupportMessage> messages})> ticket(int id) => _guard(() async {
        final m = _ok(await _dio.get('/api/v1/support/tickets/$id', options: await _opts()));
        return (
          ticket: SupportTicket.fromJson(Map<String, dynamic>.from(m['ticket'] as Map)),
          messages: (m['messages'] as List? ?? const [])
              .whereType<Map>()
              .map((e) => SupportMessage.fromJson(Map<String, dynamic>.from(e)))
              .toList(),
        );
      });

  /// Returns (id, ticket number, message).
  static Future<({int id, String ticketNo, String message})> createTicket({
    required String category,
    required String subject,
    required String message,
    String? appVersion,
    String? deviceInfo,
  }) =>
      _guard(() async {
        final m = _ok(await _dio.post('/api/v1/support/tickets',
            data: {
              'category': category,
              'subject': subject,
              'message': message,
              if (appVersion != null) 'app_version': appVersion,
              if (deviceInfo != null) 'device_info': deviceInfo,
            },
            options: await _opts()));
        final t = m['ticket'] is Map ? Map<String, dynamic>.from(m['ticket'] as Map) : const <String, dynamic>{};
        return (id: _int(t['id']), ticketNo: '${t['ticket_no'] ?? ''}', message: '${m['message'] ?? ''}');
      });

  static Future<void> reply(int ticketId, String message) => _guard(() async {
        _ok(await _dio.post('/api/v1/support/tickets/$ticketId/reply',
            data: {'message': message}, options: await _opts()));
      });

  static Future<void> closeTicket(int ticketId, {int? rating}) => _guard(() async {
        _ok(await _dio.post('/api/v1/support/tickets/$ticketId/close',
            data: {if (rating != null) 'rating': rating}, options: await _opts()));
      });

  // ── Issue reports ────────────────────────────────────────────
  static Future<List<IssueReport>> issues() => _guard(() async {
        final m = _ok(await _dio.get('/api/v1/issues', options: await _opts()));
        return (m['reports'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => IssueReport.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      });

  static Future<({String reportNo, String message})> reportIssue({
    required String category,
    required String severity,
    required String title,
    required String description,
    String? steps,
    String? appVersion,
    String? deviceInfo,
  }) =>
      _guard(() async {
        final m = _ok(await _dio.post('/api/v1/issues',
            data: {
              'category': category,
              'severity': severity,
              'title': title,
              'description': description,
              if (steps != null && steps.trim().isNotEmpty) 'steps': steps.trim(),
              if (appVersion != null) 'app_version': appVersion,
              if (deviceInfo != null) 'device_info': deviceInfo,
            },
            options: await _opts()));
        return (reportNo: '${m['report_no'] ?? ''}', message: '${m['message'] ?? ''}');
      });

  // ── Personal inbox ───────────────────────────────────────────
  static Future<({List<InboxItem> items, int unread})> inbox() => _guard(() async {
        final m = _ok(await _dio.get('/api/v1/inbox', options: await _opts()));
        return (
          items: (m['notifications'] as List? ?? const [])
              .whereType<Map>()
              .map((e) => InboxItem.fromJson(Map<String, dynamic>.from(e)))
              .toList(),
          unread: _int(m['unread']),
        );
      });

  static Future<void> markInboxRead([List<int>? ids]) async {
    try {
      await _dio.post('/api/v1/inbox/read',
          data: {if (ids != null && ids.isNotEmpty) 'ids': ids}, options: await _opts());
    } catch (_) {}
  }

  // ── App update (admin dashboard) ─────────────────────────────
  /// The newest published release when it is newer than [build]; null when
  /// there is none, or the server can't be reached.
  static Future<AppRelease?> latestRelease(int build) async {
    try {
      final r = await _dio.get('/api/v1/app/update',
          queryParameters: {'build': build},
          options: Options(receiveTimeout: const Duration(seconds: 10)));
      if ((r.statusCode ?? 0) != 200 || r.data is! Map) return null;
      final rel = AppRelease.fromJson((r.data as Map)['update']);
      return rel != null && rel.build > build ? rel : null;
    } catch (_) {
      return null;
    }
  }

  // ── Analytics ────────────────────────────────────────────────
  static Future<bool> sendEvents(Map<String, dynamic> body) async {
    try {
      final r = await _dio.post('/api/v1/analytics/events',
          data: body, options: await _opts());
      return (r.statusCode ?? 0) == 200;
    } catch (_) {
      return false;
    }
  }
}
