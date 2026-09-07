import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

import '../core/storage/secure_storage_service.dart';
import 'settings_repository.dart';

/// Gate-keeps the Safe Media vault: PIN setup/verification (hash-only, via
/// SecureStorageService) and optional biometric unlock (via local_auth).
class SafeMediaRepository {
  final SecureStorageService _secureStorage = SecureStorageService();
  final SettingsRepository settingsRepository;
  final LocalAuthentication _localAuth = LocalAuthentication();

  SafeMediaRepository(this.settingsRepository);

  Future<bool> hasPinSet() => _secureStorage.hasPin();

  Future<void> setPin(String pin) => _secureStorage.setPin(pin);

  Future<bool> verifyPin(String pin) => _secureStorage.verifyPin(pin);

  Future<void> changePin(String currentPin, String newPin) async {
    final ok = await verifyPin(currentPin);
    if (!ok) throw Exception('Current PIN is incorrect');
    await _secureStorage.setPin(newPin);
  }

  Future<void> disableSafeMedia(String currentPin) async {
    final ok = await verifyPin(currentPin);
    if (!ok) throw Exception('Current PIN is incorrect');
    await _secureStorage.clearPin();
    settingsRepository.biometricEnabled = false;
  }

  Future<bool> isBiometricAvailable() async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isSupported = await _localAuth.isDeviceSupported();
      return canCheck && isSupported;
    } catch (_) {
      return false;
    }
  }

  bool get isBiometricEnabled => settingsRepository.biometricEnabled;

  set isBiometricEnabled(bool v) => settingsRepository.biometricEnabled = v;

  /// Human-readable reason the *last* [authenticateWithBiometrics] call
  /// failed, or null if it succeeded / hasn't run yet. Previously every
  /// failure (including ones that mean the OS never even shows a
  /// fingerprint/face prompt, like no biometrics enrolled) was swallowed
  /// silently, so tapping "Use biometrics" could look like it did nothing at
  /// all. The UI reads this after a failed attempt to tell the user why.
  String? lastAuthError;

  bool _authInFlight = false;

  Future<bool> authenticateWithBiometrics() async {
    // The Now-Playing... err, Safe Media screen fires one attempt silently on
    // open and another when the user taps "Use biometrics" — if those two
    // land close together, local_auth's `authenticate()` throws
    // `auth_in_progress` for the second call (Android only allows one
    // BiometricPrompt at a time), which used to fall through to the generic
    // "try again" message even though nothing was actually wrong. Skip
    // starting a second attempt instead of racing the first.
    if (_authInFlight) return false;
    _authInFlight = true;
    lastAuthError = null;
    try {
      return await _localAuth.authenticate(
        localizedReason: 'Unlock Safe Media',
        options: const AuthenticationOptions(biometricOnly: true, stickyAuth: true),
      );
    } on PlatformException catch (e) {
      lastAuthError = _describeAuthError(e.code);
      return false;
    } catch (_) {
      lastAuthError = 'Biometric authentication failed. Please try again.';
      return false;
    } finally {
      _authInFlight = false;
    }
  }

  String _describeAuthError(String code) {
    switch (code) {
      case 'NotAvailable':
        return 'Biometric hardware isn\'t available right now.';
      case 'NotEnrolled':
        return 'No fingerprint or face is set up on this device yet. '
            'Add one in your phone\'s Settings, then try again.';
      case 'PasscodeNotSet':
        return 'Set a screen lock (PIN, pattern or password) on your device first.';
      case 'LockedOut':
        return 'Too many attempts — biometric unlock is temporarily locked. Use your PIN.';
      case 'PermanentlyLockedOut':
        return 'Biometric unlock is locked. Unlock your device screen once to reset it, or use your PIN.';
      case 'auth_in_progress':
        return 'Already checking — please wait a moment and try again.';
      case 'no_fragment_activity':
        return 'This screen can\'t show the biometric prompt right now. Please restart the app.';
      default:
        // Unrecognized code — surface it so the exact reason is visible
        // instead of a dead-end generic message (this is what previously
        // showed up as an unexplained "authentication failed").
        return 'Biometric authentication failed ($code). Try again or use your PIN.';
    }
  }
}
