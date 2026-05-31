// lib/core/services/biometric_service.dart
//
// "Verify it's you" gate using the device OS (fingerprint / face, with PIN /
// pattern / password fallback) via local_auth + Android BiometricPrompt.
// Used before autofilling saved passwords and before opening the vault.

import 'package:local_auth/local_auth.dart';
import '../database/local_db.dart';

class BiometricService {
  static final LocalAuthentication _auth = LocalAuthentication();

  /// Can the device authenticate at all (biometrics enrolled OR a device PIN)?
  static Future<bool> isAvailable() async {
    try {
      final supported = await _auth.isDeviceSupported();
      return supported;
    } catch (_) {
      return false;
    }
  }

  /// Prompt the user. Returns true only on a successful verification.
  /// If the biometric lock setting is OFF, returns true immediately.
  /// If the device has no security set up, returns true (can't gate safely).
  static Future<bool> verify(String reason) async {
    if (!LocalDB.getBiometricLockEnabled()) return true;
    try {
      if (!await _auth.isDeviceSupported()) return true;
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: false,   // allow device PIN/pattern/password fallback
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
    } catch (_) {
      // On a plugin/hardware error, fail closed (deny) so secrets stay protected.
      return false;
    }
  }
}
