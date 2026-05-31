// lib/core/services/rewards_service.dart
//
// Typed client for the NOVA X Rewards backend (rewards.php).
// The SERVER decides everything — this just asks and reports the result.
//
// Endpoints: state, entitlements, claim-daily, heartbeat, earn, redeem,
//            track-business, track-notif.

import 'package:dio/dio.dart';
import 'api_service.dart';

// ── Feature + task keys (must match rewards.php) ─────────────────────────────
class RewardFeature {
  static const customization = 'customization';
  static const shield        = 'shield';
  static const cyber         = 'cyber';
  static const devtools      = 'devtools';
  static const speeddial     = 'speeddial';
  static const cookie        = 'cookie';
  static const business      = 'business';

  static const all = [
    customization, shield, cyber, devtools, speeddial, cookie, business,
  ];

  static String label(String key) {
    switch (key) {
      case customization: return 'Customization';
      case shield:        return 'NOVA Shield';
      case cyber:         return 'NOVA Cyber';
      case devtools:      return 'Developer Tools';
      case speeddial:     return 'Custom Speed Dial';
      case cookie:        return 'Cookie Editor';
      case business:      return 'NOVA Business';
      default:            return key;
    }
  }
}

class RewardTaskKey {
  static const dailyClaim       = 'daily_claim';
  static const browse10min      = 'browse_10min';
  static const useAi            = 'use_ai';
  static const businessClicks   = 'business_clicks';
  static const readNews         = 'read_news';
  static const completeProfile  = 'complete_profile';
  static const openNotifications= 'open_notifications';
  static const visualSearch     = 'visual_search';
  static const dailyStreak      = 'daily_streak';
}

// ── Models ───────────────────────────────────────────────────────────────────
class RewardTask {
  final String key;
  final int points;
  final bool done;
  final bool claimable;
  final Map<String, dynamic> raw;   // extra fields (count, target, progress_sec, etc.)
  RewardTask(this.key, this.points, this.done, this.claimable, this.raw);

  int    i(String k, [int d = 0])   => (raw[k] is num) ? (raw[k] as num).toInt() : d;
  bool   b(String k, [bool d = false]) => raw[k] is bool ? raw[k] as bool : d;
}

class FeatureCatalogItem {
  final String key;
  final int cost;
  final int days;
  FeatureCatalogItem(this.key, this.cost, this.days);
}

class RewardsState {
  final int balance;
  final int lifetimeEarned;
  final int todayGained;
  final String day;
  final Map<String, RewardTask> tasks;
  final Map<String, FeatureCatalogItem> catalog;
  RewardsState({
    required this.balance,
    required this.lifetimeEarned,
    required this.todayGained,
    required this.day,
    required this.tasks,
    required this.catalog,
  });
}

class Entitlement {
  final bool active;
  final DateTime? expiresAt;
  final String source;          // 'trial' | 'points'
  Entitlement(this.active, this.expiresAt, this.source);
}

// Generic result for claim/earn/redeem/heartbeat
class RewardResult {
  final bool success;
  final String message;
  final String reason;          // e.g. 'full', 'already', 'not_yet', 'insufficient'
  final Map<String, dynamic> data;
  RewardResult(this.success, this.message, this.reason, this.data);

  int?      get balance    => (data['balance'] is num) ? (data['balance'] as num).toInt() : null;
  int       get points     => (data['points'] is num) ? (data['points'] as num).toInt() : 0;
  int       get seconds    => (data['seconds'] is num) ? (data['seconds'] as num).toInt() : 0;
  bool      get claimable  => data['claimable'] == true;
  int       get count      => (data['count'] is num) ? (data['count'] as num).toInt() : 0;
  String?   get expiresAt  => data['expires_at'] as String?;
  String?   get featureKey => data['feature_key'] as String?;
}

// ── Service ────────────────────────────────────────────────────────────────────
class RewardsService {
  static const String _url = '${ApiService.baseUrl}/rewards.php';

  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 20),
    headers:        {'Accept': 'application/json'},
    validateStatus: (_) => true,   // we read success flag, not HTTP code
  ));

  static Future<Options> _opts() async {
    final token = await ApiService.getToken();
    return Options(headers: {
      'Authorization': 'Bearer $token',
      'Content-Type':  'application/json',
    });
  }

  static Map<String, dynamic> _asMap(dynamic d) {
    if (d is Map) return Map<String, dynamic>.from(d);
    return {};
  }

  static RewardResult _result(dynamic respData) {
    final m = _asMap(respData);
    return RewardResult(
      m['success'] == true,
      (m['message'] as String?) ?? '',
      (m['reason'] as String?) ?? '',
      m,
    );
  }

  // ── GET state ──────────────────────────────────────────────────────────────
  static Future<RewardsState?> fetchState() async {
    try {
      final r = await _dio.get('$_url?action=state', options: await _opts());
      final m = _asMap(r.data);
      if (m['success'] != true) return null;

      final tasks = <String, RewardTask>{};
      final tm = _asMap(m['tasks']);
      tm.forEach((k, v) {
        final raw = _asMap(v);
        tasks[k] = RewardTask(
          k,
          (raw['points'] is num) ? (raw['points'] as num).toInt() : 0,
          raw['done'] == true,
          raw['claimable'] == true,
          raw,
        );
      });

      final catalog = <String, FeatureCatalogItem>{};
      final cm = _asMap(m['catalog']);
      cm.forEach((k, v) {
        final raw = _asMap(v);
        catalog[k] = FeatureCatalogItem(
          k,
          (raw['cost'] is num) ? (raw['cost'] as num).toInt() : 0,
          (raw['days'] is num) ? (raw['days'] as num).toInt() : 0,
        );
      });

      return RewardsState(
        balance:        (m['balance'] is num) ? (m['balance'] as num).toInt() : 0,
        lifetimeEarned: (m['lifetime_earned'] is num) ? (m['lifetime_earned'] as num).toInt() : 0,
        todayGained:    (m['today_gained'] is num) ? (m['today_gained'] as num).toInt() : 0,
        day:            (m['day'] as String?) ?? '',
        tasks:          tasks,
        catalog:        catalog,
      );
    } catch (_) {
      return null;
    }
  }

  // ── GET entitlements ─────────────────────────────────────────────────────────
  static Future<Map<String, Entitlement>> fetchEntitlements() async {
    try {
      final r = await _dio.get('$_url?action=entitlements', options: await _opts());
      final m = _asMap(r.data);
      final out = <String, Entitlement>{};
      if (m['success'] == true) {
        final em = _asMap(m['entitlements']);
        em.forEach((k, v) {
          final raw = _asMap(v);
          DateTime? exp;
          final s = raw['expires_at'] as String?;
          if (s != null) exp = DateTime.tryParse(s.replaceFirst(' ', 'T'));
          out[k] = Entitlement(raw['active'] == true, exp, (raw['source'] as String?) ?? 'points');
        });
      }
      return out;
    } catch (_) {
      return {};
    }
  }

  // ── POST actions ───────────────────────────────────────────────────────────
  static Future<RewardResult> claimDaily() async =>
      _post('claim-daily');

  static Future<RewardResult> earn(String taskKey) async =>
      _post('earn', {'task_key': taskKey});

  static Future<RewardResult> redeem(String featureKey) async =>
      _post('redeem', {'feature_key': featureKey});

  static Future<RewardResult> heartbeat() async =>
      _post('heartbeat');

  static Future<RewardResult> trackBusiness(int businessId) async =>
      _post('track-business', {'business_id': businessId});

  static Future<RewardResult> trackNotif(int advertId) async =>
      _post('track-notif', {'advert_id': advertId});

  static Future<RewardResult> _post(String action, [Map<String, dynamic>? body]) async {
    try {
      final r = await _dio.post('$_url?action=$action',
          data: body ?? {}, options: await _opts());
      return _result(r.data);
    } catch (_) {
      return RewardResult(false, 'Network error. Please try again.', 'network', {});
    }
  }
}
