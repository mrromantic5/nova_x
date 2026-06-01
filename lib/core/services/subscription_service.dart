// lib/core/services/subscription_service.dart
//
// Typed client for the NOVA X Premium Subscription backend (subscription.php).
// Paystack verify-on-demand flow (no webhook). The server is the source of truth;
// this client only initiates payments and asks the server to verify/report.

import 'package:dio/dio.dart';
import 'api_service.dart';
import 'rewards_entitlements.dart';

class SubStatus {
  final bool active;
  final String? plan;        // 'monthly' | 'sixmonth'
  final String? country;     // 'GH' | 'NG'
  final String? currency;    // 'GHS' | 'NGN'
  final int amount;
  final DateTime? expiresAt;
  final String? lastPlan;
  final String? lastCountry;
  SubStatus({
    required this.active,
    this.plan,
    this.country,
    this.currency,
    this.amount = 0,
    this.expiresAt,
    this.lastPlan,
    this.lastCountry,
  });
}

class InitResult {
  final bool success;
  final String message;
  final String? authorizationUrl;
  final String? reference;
  final String? publicKey;
  InitResult(this.success, this.message,
      {this.authorizationUrl, this.reference, this.publicKey});
}

class VerifyResult {
  final bool success;
  final bool active;
  final String message;
  final Map<String, dynamic> receipt;
  VerifyResult(this.success, this.active, this.message, this.receipt);
}

class SubscriptionService {
  static const String _url = '${ApiService.baseUrl}/subscription.php';

  // Plan + price catalog (must match subscription.php). USD shown as reference.
  static const Map<String, Map<String, dynamic>> plans = {
    'monthly':  {'label': 'Monthly',  'days': 30,  'GH': 20,  'NG': 2000,  'usd': 2},
    'sixmonth': {'label': '6 Months', 'days': 180, 'GH': 100, 'NG': 11000, 'usd': 9},
  };
  static const Map<String, Map<String, String>> countries = {
    'GH': {'name': 'Ghana',   'flag': '🇬🇭', 'currency': 'GHS'},
    'NG': {'name': 'Nigeria', 'flag': '🇳🇬', 'currency': 'NGN'},
  };

  static final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 20),
    receiveTimeout: const Duration(seconds: 40),
    headers:        {'Accept': 'application/json'},
    validateStatus: (_) => true,
  ));

  static Future<Options> _opts() async {
    final token = await ApiService.getToken();
    return Options(headers: {
      'Authorization': 'Bearer $token',
      'Content-Type':  'application/json',
    });
  }

  static Map<String, dynamic> _asMap(dynamic d) =>
      d is Map ? Map<String, dynamic>.from(d) : {};

  static DateTime? _date(dynamic v) {
    if (v == null) return null;
    return DateTime.tryParse(v.toString().replaceFirst(' ', 'T'));
  }

  /// Fetch current subscription status and update the premium gate.
  static Future<SubStatus> fetchStatus() async {
    try {
      final r = await _dio.get('$_url?action=status', options: await _opts());
      final m = _asMap(r.data);
      final active = m['active'] == true;
      await RewardsEntitlements.setPremium(active);
      return SubStatus(
        active:      active,
        plan:        m['plan'] as String?,
        country:     m['country'] as String?,
        currency:    m['currency'] as String?,
        amount:      (m['amount'] is num) ? (m['amount'] as num).toInt() : 0,
        expiresAt:   _date(m['expires_at']),
        lastPlan:    m['last_plan'] as String?,
        lastCountry: m['last_country'] as String?,
      );
    } catch (_) {
      return SubStatus(active: RewardsEntitlements.isPremium);
    }
  }

  /// Start a Paystack transaction. Returns the checkout URL to open.
  static Future<InitResult> init(String plan, String country) async {
    try {
      final r = await _dio.post('$_url?action=init',
          data: {'plan': plan, 'country': country}, options: await _opts());
      final m = _asMap(r.data);
      if (m['success'] != true) {
        return InitResult(false, (m['message'] as String?) ?? 'Could not start payment');
      }
      return InitResult(true, '',
          authorizationUrl: m['authorization_url'] as String?,
          reference:        m['reference'] as String?,
          publicKey:        m['public_key'] as String?);
    } catch (e) {
      return InitResult(false, 'Network error. Try again.');
    }
  }

  /// Ask the server to verify a Paystack reference and activate premium.
  static Future<VerifyResult> verify(String reference) async {
    try {
      final r = await _dio.get('$_url?action=verify&reference=$reference',
          options: await _opts());
      final m = _asMap(r.data);
      final active = m['active'] == true;
      if (active) await RewardsEntitlements.setPremium(true);
      return VerifyResult(
        m['success'] == true,
        active,
        (m['message'] as String?) ?? '',
        _asMap(m['receipt']),
      );
    } catch (e) {
      return VerifyResult(false, false, 'Verification failed. Try again.', {});
    }
  }

  static int priceFor(String plan, String country) {
    final p = plans[plan];
    if (p == null) return 0;
    final v = p[country];
    return v is num ? v.toInt() : 0;
  }
}
