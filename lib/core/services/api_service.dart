// lib/core/services/api_service.dart
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  static const String baseUrl = 'https://api.browser.t-lyfe.com.ng';
  static const _kToken = 'nx_server_token';
  static const _kUser  = 'nx_server_user';

  static final Dio _dio = Dio(BaseOptions(
    baseUrl:        baseUrl,
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
    headers:        {'Accept': 'application/json'},
  ));

  // ── Session ──────────────────────────────────────────────────
  static Future<String?> getToken() async =>
      (await SharedPreferences.getInstance()).getString(_kToken);

  static Future<Map<String, dynamic>?> getCachedUser() async {
    final raw = (await SharedPreferences.getInstance()).getString(_kUser);
    if (raw == null) return null;
    try { return Map<String, dynamic>.from(jsonDecode(raw) as Map); }
    catch (_) { return null; }
  }

  static Future<void> _saveSession(String token, Map<String, dynamic> user) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kToken, token);
    await p.setString(_kUser,  jsonEncode(user));
  }

  static Future<void> clearSession() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kToken);
    await p.remove(_kUser);
  }

  static Future<bool> isLoggedIn() async => (await getToken()) != null;

  // ── Auth options ─────────────────────────────────────────────
  static Future<Options> _authOpts() async {
    final token = await getToken();
    return Options(headers: {
      'Authorization': 'Bearer $token',
      'Content-Type':  'application/json',
    });
  }

  // Multipart: let Dio set Content-Type with boundary
  static Future<Options> _authOptsMultipart() async {
    final token = await getToken();
    return Options(headers: {'Authorization': 'Bearer $token'});
  }

  // ── Register → sends OTP ────────────────────────────────────
  static Future<Map<String, dynamic>> register({
    required String username,
    required String email,
    required String password,
  }) async {
    try {
      final res = await _dio.post('/api/v1/register',
          data: {'username': username, 'email': email, 'password': password},
          options: Options(headers: {'Content-Type': 'application/json'}));
      final data = Map<String, dynamic>.from(res.data as Map);
      return {
        'success':            true,
        'needs_verification': data['needs_verification'] ?? false,
        'user_id':            data['user_id'],
        'message':            data['message'] ?? '',
      };
    } on DioException catch (e) {
      return {'success': false, 'message': _msg(e)};
    }
  }

  // ── Resend OTP ───────────────────────────────────────────────
  static Future<Map<String, dynamic>> resendOtp(int userId) async {
    try {
      await _dio.post('/api/v1/send-otp',
          data: {'user_id': userId},
          options: Options(headers: {'Content-Type': 'application/json'}));
      return {'success': true};
    } on DioException catch (e) {
      return {'success': false, 'message': _msg(e)};
    }
  }

  // ── Verify OTP → activates account → returns token ──────────
  static Future<Map<String, dynamic>> verifyOtp({
    required int    userId,
    required String code,
  }) async {
    try {
      final res = await _dio.post('/api/v1/verify-otp',
          data: {'user_id': userId, 'code': code},
          options: Options(headers: {'Content-Type': 'application/json'}));
      final data = Map<String, dynamic>.from(res.data as Map);
      await _saveSession(
          data['access_token'] as String,
          Map<String, dynamic>.from(data['user'] as Map));
      return {'success': true, 'user': data['user']};
    } on DioException catch (e) {
      return {'success': false, 'message': _msg(e)};
    }
  }

  // ── Login ────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    try {
      final res = await _dio.post('/api/v1/login',
          data: {'email': email, 'password': password},
          options: Options(headers: {'Content-Type': 'application/json'}));
      final data = Map<String, dynamic>.from(res.data as Map);
      await _saveSession(
          data['access_token'] as String,
          Map<String, dynamic>.from(data['user'] as Map));
      return {'success': true, 'user': data['user']};
    } on DioException catch (e) {
      final d = e.response?.data;
      if (d is Map && d['needs_verification'] == true) {
        return {
          'success':            false,
          'needs_verification': true,
          'user_id':            d['user_id'],
          'message':            d['message'] ?? 'Please verify your email.',
        };
      }
      return {'success': false, 'message': _msg(e)};
    }
  }

  // ── Logout ───────────────────────────────────────────────────
  static Future<void> logout() async {
    try { await _dio.post('/api/v1/sync/logout', options: await _authOpts()); }
    catch (_) {}
    await clearSession();
  }

  // ── Register FCM token with server ──────────────────────────
  static Future<void> registerFcmToken(String fcmToken) async {
    final loggedIn = await isLoggedIn();
    if (!loggedIn) return;
    try {
      await _dio.post('/api/v1/sync/fcm-token',
          data: {'token': fcmToken},
          options: await _authOpts());
    } catch (_) {}
  }

  // ── Profile ──────────────────────────────────────────────────
  static Future<Map<String, dynamic>?> getProfile() async {
    try {
      final res  = await _dio.get('/api/v1/sync/profile', options: await _authOpts());
      final prof = Map<String, dynamic>.from((res.data as Map)['profile'] as Map);
      final token  = await getToken() ?? '';
      final cached = await getCachedUser() ?? {};
      cached.addAll(prof);
      await _saveSession(token, cached);
      return prof;
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) await clearSession();
      return null;
    }
  }

  static Future<bool> updateProfile({
    required String username,
    required String avatarColor,
  }) async {
    try {
      await _dio.post('/api/v1/sync/profile',
          data: {'username': username, 'avatar_color': avatarColor},
          options: await _authOpts());
      final token  = await getToken() ?? '';
      final cached = await getCachedUser() ?? {};
      cached['username']     = username;
      cached['avatar_color'] = avatarColor;
      await _saveSession(token, cached);
      return true;
    } catch (_) { return false; }
  }

  // ── Businesses — global ──────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getBusinesses() async {
    try {
      final res = await _dio.get('/api/v1/businesses');
      return List<Map<String, dynamic>>.from(
          ((res.data as Map)['businesses'] as List)
              .map((e) => Map<String, dynamic>.from(e as Map)));
    } catch (_) { return []; }
  }

  static Future<Map<String, dynamic>?> searchBusiness(String query) async {
    try {
      final res  = await _dio.post('/api/v1/businesses/search',
          data: {'query': query},
          options: Options(headers: {'Content-Type': 'application/json'}));
      final data = Map<String, dynamic>.from(res.data as Map);
      if (data['status'] == 'success' && data['business'] != null) {
        return Map<String, dynamic>.from(data['business'] as Map);
      }
      return null;
    } catch (_) { return null; }
  }

  /// Call this when user taps "Visit Website" — increments visit_count server-side
  static Future<void> recordBusinessVisit(int businessId) async {
    try {
      await _dio.post('/api/v1/businesses/$businessId/visit',
          options: Options(headers: {'Content-Type': 'application/json'}));
    } catch (_) {}
  }

  // ── My businesses ────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getMyBusinesses() async {
    try {
      final res = await _dio.get('/api/v1/sync/businesses', options: await _authOpts());
      return List<Map<String, dynamic>>.from(
          ((res.data as Map)['businesses'] as List)
              .map((e) => Map<String, dynamic>.from(e as Map)));
    } catch (_) { return []; }
  }

  static Future<Map<String, dynamic>> addBusiness({
    required String name,
    required String description,
    required String category,
    required String location,
    required String website,
    File? imageFile,
  }) async {
    try {
      if (imageFile != null) {
        final formData = FormData.fromMap({
          'name': name, 'description': description, 'category': category,
          'location': location, 'website': website,
          'image': await MultipartFile.fromFile(imageFile.path,
              filename: 'biz_${DateTime.now().millisecondsSinceEpoch}.jpg'),
        });
        final res = await _dio.post('/api/v1/sync/businesses',
            data: formData, options: await _authOptsMultipart());
        return {'success': true, 'business': (res.data as Map)['business']};
      } else {
        final res = await _dio.post('/api/v1/sync/businesses',
            data: {'name': name, 'description': description, 'category': category,
                   'location': location, 'website': website},
            options: await _authOpts());
        return {'success': true, 'business': (res.data as Map)['business']};
      }
    } on DioException catch (e) {
      return {'success': false, 'message': _msg(e)};
    } catch (e) {
      return {'success': false, 'message': 'Unexpected error: $e'};
    }
  }

  static Future<bool> deleteBusiness(int id) async {
    try {
      await _dio.delete('/api/v1/sync/businesses',
          data: {'id': id}, options: await _authOpts());
      return true;
    } catch (_) { return false; }
  }

  // ── Bookmarks ────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getBookmarks() async {
    try {
      final res = await _dio.get('/api/v1/sync/bookmarks', options: await _authOpts());
      return List<Map<String, dynamic>>.from(
          ((res.data as Map)['bookmarks'] as List)
              .map((e) => Map<String, dynamic>.from(e as Map)));
    } catch (_) { return []; }
  }

  static Future<bool> syncBookmarks(List<Map<String, dynamic>> bookmarks) async {
    try {
      await _dio.post('/api/v1/sync/bookmarks',
          data: {'bookmarks': bookmarks}, options: await _authOpts());
      return true;
    } catch (_) { return false; }
  }

  // ── Error helper ─────────────────────────────────────────────
  static String _msg(DioException e) {
    try {
      final d = e.response?.data;
      if (d is Map && d['message'] != null) return d['message'] as String;
    } catch (_) {}
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return 'Connection timed out. Check your internet.';
    }
    if (e.type == DioExceptionType.connectionError) {
      return 'No internet connection.';
    }
    return 'Something went wrong. Please try again.';
  }
}
