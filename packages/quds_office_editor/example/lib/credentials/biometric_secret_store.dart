// Biometry-protected storage for one credential-vault unlock secret.
//
// The secret is held by the OS keychain under an access control that requires
// the current biometric enrolment (macOS: data protection keychain item with
// kSecAttrAccessibleWhenUnlockedThisDeviceOnly + .biometryCurrentSet). Reading
// it is what shows the system Touch ID sheet; the OS, not this code, enforces
// biometry on the secret. There is no boolean "authenticated" gate here.
//
// Only macOS is enabled. The channel contract is platform neutral, so iOS
// (Face ID / Touch ID) can be enabled by adding a Runner handler and listing
// the platform in [MethodChannelBiometricSecretStore.supportedPlatforms].

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Whether biometric unlock can be offered right now.
enum BiometricUnlockAvailability {
  /// Biometry is enrolled and the data protection keychain is usable.
  available,

  /// This platform has no biometric vault unlock (yet).
  unsupportedPlatform,

  /// The Mac has no biometric sensor (or none is reachable, e.g. a closed
  /// laptop lid without a Touch ID keyboard).
  noHardware,

  /// No fingerprint is enrolled in System Settings.
  notEnrolled,

  /// Biometry is locked after too many failed attempts until the user signs
  /// in with the Mac password. Temporary; the setting stays on.
  lockedOut,

  /// The build is not entitled to the data protection keychain
  /// (errSecMissingEntitlement, -34018: ad hoc or unsigned builds).
  keychainUnavailable,

  /// Any other probe failure.
  error,
}

/// Outcome of reading the protected secret.
enum BiometricSecretReadStatus {
  success,

  /// The user dismissed the system sheet or chose the password fallback.
  cancelled,

  /// No readable item: never stored, removed, or invalidated because the
  /// enrolled fingerprints changed (.biometryCurrentSet).
  notFound,

  /// Authentication failed or the keychain refused the read.
  failed,

  /// Biometry or the keychain became unavailable.
  unavailable,
}

@immutable
class BiometricSecretRead {
  const BiometricSecretRead(this.status, [this.secret]);
  final BiometricSecretReadStatus status;

  /// Present only for [BiometricSecretReadStatus.success]. Never log it.
  final String? secret;

  @override
  String toString() => 'BiometricSecretRead(${status.name})';
}

/// A single biometry-protected secret slot.
abstract interface class BiometricSecretStore {
  Future<BiometricUnlockAvailability> availability();

  /// Replaces the stored secret. Throws when the OS refuses to store it.
  Future<void> store(String secret);

  /// Shows the system biometric sheet with [reason] and returns the secret.
  Future<BiometricSecretRead> read({
    required String reason,
    String? cancelTitle,
    String? fallbackTitle,
  });

  /// Removes the secret. Succeeds when nothing is stored.
  Future<void> delete();
}

/// Runner bridge (macos/Runner/BiometricVaultKeychain.swift).
class MethodChannelBiometricSecretStore implements BiometricSecretStore {
  const MethodChannelBiometricSecretStore({this._channel = defaultChannel});

  static const defaultChannel = MethodChannel(
    'com.crispoffice/biometric_vault',
  );

  /// Platforms with a native handler. iOS can follow by adding its handler.
  static const supportedPlatforms = {TargetPlatform.macOS};

  final MethodChannel _channel;

  bool get _supported =>
      !kIsWeb && supportedPlatforms.contains(defaultTargetPlatform);

  @override
  Future<BiometricUnlockAvailability> availability() async {
    if (!_supported) return BiometricUnlockAvailability.unsupportedPlatform;
    try {
      final status = await _channel.invokeMethod<String>('isAvailable');
      return BiometricUnlockAvailability.values.firstWhere(
        (value) => value.name == status,
        orElse: () => BiometricUnlockAvailability.error,
      );
    } on MissingPluginException {
      return BiometricUnlockAvailability.unsupportedPlatform;
    } on PlatformException {
      return BiometricUnlockAvailability.error;
    }
  }

  @override
  Future<void> store(String secret) async {
    if (!_supported) throw UnsupportedError('Biometric unlock is unavailable');
    await _channel.invokeMethod<void>('store', {'secret': secret});
  }

  @override
  Future<BiometricSecretRead> read({
    required String reason,
    String? cancelTitle,
    String? fallbackTitle,
  }) async {
    if (!_supported) {
      return const BiometricSecretRead(BiometricSecretReadStatus.unavailable);
    }
    try {
      final result = await _channel.invokeMapMethod<String, Object?>('read', {
        'reason': reason,
        'cancelTitle': ?cancelTitle,
        'fallbackTitle': ?fallbackTitle,
      });
      final status = BiometricSecretReadStatus.values.firstWhere(
        (value) => value.name == result?['status'],
        orElse: () => BiometricSecretReadStatus.failed,
      );
      final secret = result?['secret'];
      if (status == BiometricSecretReadStatus.success) {
        return secret is String && secret.isNotEmpty
            ? BiometricSecretRead(status, secret)
            : const BiometricSecretRead(BiometricSecretReadStatus.failed);
      }
      return BiometricSecretRead(status);
    } on MissingPluginException {
      return const BiometricSecretRead(BiometricSecretReadStatus.unavailable);
    } on PlatformException {
      return const BiometricSecretRead(BiometricSecretReadStatus.failed);
    }
  }

  @override
  Future<void> delete() async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod<void>('delete');
    } on MissingPluginException {
      // No native handler: nothing can have been stored by this build.
    }
  }
}
