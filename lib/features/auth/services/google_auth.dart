// lib/features/auth/services/google_auth.dart
//
// 3.13.2: "Continue with Google".
//
// Google Sign-In on the phone (Firebase project nova-x-d9e27) gives an ID
// token made for NOVA X's Web client; the NOVA X server checks it
// (google_auth.php → POST /api/v1/auth/google) and signs the user in or
// creates the account. The Web client ID is a public identifier, not a
// secret; nothing secret is in the app.

import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:nova_x/core/services/api_service.dart';

import 'google_web_signin.dart';

class GoogleAuth {
  GoogleAuth._();

  static const String webClientId =
      '813671405483-t06l7jn2an58brj3477s3uth3b44p09h.apps.googleusercontent.com';

  static final GoogleSignIn _google = GoogleSignIn(
    scopes: const ['email', 'profile'],
    serverClientId: webClientId,
  );

  /// Opens Google's account chooser and signs in to NOVA X.
  /// Returns {success, is_new, user} or {success:false, cancelled?, message}.
  static Future<Map<String, dynamic>> signIn() async {
    GoogleSignInAccount? account;
    try {
      // Always show the account chooser (not the last account silently).
      try {
        await _google.signOut();
      } catch (_) {}
      account = await _google.signIn();
    } on PlatformException catch (e) {
      return {'success': false, 'message': messageFor(e.code, e.message)};
    } catch (e) {
      return {'success': false, 'message': 'Google sign-in failed. Please try again.'};
    }
    if (account == null) return {'success': false, 'cancelled': true};

    String? idToken;
    try {
      idToken = (await account.authentication).idToken;
    } catch (_) {}
    if (idToken == null || idToken.isEmpty) {
      return {'success': false, 'message': 'Google didn\'t return a sign-in token. Please try again.'};
    }

    final res = await ApiService.googleLogin(idToken);
    if (res['success'] == true) {
      // The browser can be signed in to the same Google account next.
      await GoogleWebSignIn.offer(account.email, fromGoogle: true);
    } else {
      // Don't keep a half-finished Google session on the phone.
      try {
        await _google.signOut();
      } catch (_) {}
    }
    return res;
  }

  /// Signs the phone's Google session out of NOVA X (on NOVA X log out).
  static Future<void> signOut() async {
    try {
      await _google.signOut();
    } catch (_) {}
  }

  /// Readable messages for Google Sign-In errors.
  static String messageFor(String code, String? detail) {
    final d = detail ?? '';
    if (code == 'network_error' || d.contains(': 7')) {
      return 'No internet connection. Check your connection and try again.';
    }
    if (d.contains('ApiException: 10') || d.contains(': 10:')) {
      return 'Google sign-in isn\'t set up for this version of NOVA X yet. Please update the app or use email.';
    }
    if (d.contains('12501') || code == 'sign_in_canceled') return 'Google sign-in was cancelled.';
    if (d.contains('12500')) {
      return 'Google Play services couldn\'t sign you in. Update Google Play services and try again.';
    }
    return 'Google sign-in failed. Please try again.';
  }
}
