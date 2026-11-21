// lib/services/secure_storage_service.dart
//
// Abstraction over platform-specific secure storage.
//
// Persistent implementations encrypt at rest or delegate to OS credential
// storage. Session-only storage deliberately keeps no durable credentials.

import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'log_service.dart';
import 'credential_storage_diagnostics.dart';

const _secureLog = Log('SecureStorage');

/// Abstract interface for secure key-value storage of credentials.
///
/// Persistent implementations must encrypt data at rest (or delegate to a
/// platform mechanism that does). Ephemeral implementations must override
/// [isPersistent] so migration never treats an in-memory write as durable.
abstract class SecureStorage {
  bool get isPersistent => true;

  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
  Future<bool> containsKey(String key);
  Future<void> deleteAll();

  /// Convenience: store a JSON-serialisable map.
  Future<void> writeMap(String key, Map<String, String> data) async {
    await write(key, json.encode(data));
  }

  /// Convenience: read a stored JSON map.
  Future<Map<String, String>?> readMap(String key) async {
    final raw = await read(key);
    if (raw == null) return null;
    try {
      return Map<String, String>.from(
        json.decode(raw) as Map<Object?, Object?>,
      );
    } catch (e) {
      _secureLog.warn('Failed to decode map for key "$key"', e);
      return null;
    }
  }
}

/// Native implementation backed by flutter_secure_storage.
class PlatformSecureStorage extends SecureStorage
    implements CredentialStorageIdentity {
  // flutter_secure_storage handles Keychain (macOS/iOS), Keystore (Android),
  // libsecret (Linux), DPAPI (Windows).
  //
  // Browser startup uses WebEncryptedStorage instead of this implementation.
  PlatformSecureStorage({bool? useDataProtectionKeyChain})
    : _useDataProtectionKeyChain =
          useDataProtectionKeyChain ?? _macOsDataProtection,
      _storage = FlutterSecureStorage(
        aOptions: const AndroidOptions(encryptedSharedPreferences: true),
        iOptions: const IOSOptions(
          accessibility: KeychainAccessibility.first_unlock,
        ),
        mOptions: MacOsOptions(
          useDataProtectionKeyChain:
              useDataProtectionKeyChain ?? _macOsDataProtection,
        ),
      );

  final FlutterSecureStorage _storage;
  final bool _useDataProtectionKeyChain;

  @override
  String get credentialStoreName => switch (defaultTargetPlatform) {
    TargetPlatform.macOS =>
      _useDataProtectionKeyChain
          ? 'macOS Data Protection Keychain'
          : 'macOS default file keychain',
    TargetPlatform.iOS => 'iOS Keychain',
    TargetPlatform.android => 'Android Keystore / encrypted preferences',
    TargetPlatform.windows => 'Windows credential storage',
    TargetPlatform.linux => 'Linux Secret Service',
    _ => 'Platform credential storage',
  };

  @override
  String get credentialStoreLocation =>
      'OS-managed store; flutter_secure_storage service. '
      'This backend does not expose a selected file path.';

  /// A unique, non-secret sentinel avoids races between app instances.
  Future<void> verifyAvailable() async {
    final random = Random.secure();
    final nonce = List.generate(
      4,
      (_) => random.nextInt(1 << 30).toRadixString(16),
    ).join();
    final key =
        '__crispcloud_keychain_probe_${DateTime.now().microsecondsSinceEpoch}_$nonce';
    Object? failure;
    StackTrace? failureStack;
    try {
      await _storage.write(key: key, value: 'ok');
      if (await _storage.read(key: key) != 'ok') {
        throw StateError(
          'Credential store probe read-back did not match its write.',
        );
      }
    } catch (error, stack) {
      failure = error;
      failureStack = stack;
    }
    try {
      await _storage.delete(key: key);
    } catch (error, stack) {
      failure ??= error;
      failureStack ??= stack;
    }
    if (failure != null) Error.throwWithStackTrace(failure, failureStack!);
  }

  // macOS only: whether this build may use the data-protection keychain.
  static bool _macOsDataProtection = true;

  /// macOS builds without a provisioning profile (ad-hoc signed nightlies,
  /// local builds) lack the keychain-access-groups entitlement, so every
  /// data-protection keychain call fails with errSecMissingEntitlement
  /// (-34018). Such a build can never have stored anything there, so it uses
  /// the user's login keychain instead. Locked or denied keychains are NOT
  /// treated this way; they still surface as unavailable. Call once at
  /// startup, before any credential is read.
  static Future<void> detectMacOsKeychain() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.macOS) return;
    // A read probe is insufficient: an unentitled build returns item-not-found
    // rather than -34018. Probe the write path instead, which is the first
    // operation that actually needs the keychain-access-group entitlement.
    final probe = PlatformSecureStorage(useDataProtectionKeyChain: true);
    try {
      await probe.verifyAvailable();
      _macOsDataProtection = true;
    } catch (error) {
      _macOsDataProtection = !isMissingEntitlementError(error);
      if (!_macOsDataProtection) {
        _secureLog.info(
          'This build is not entitled to the data-protection keychain '
          '(-34018); using the login keychain.',
        );
      }
      // A locked or denied keychain is not an entitlement failure. Keep the
      // selected backend so later operations report the real unavailability
      // instead of silently moving credentials to a different store.
    }
  }

  /// Whether the current macOS build uses the data-protection keychain.
  static bool get usesMacOsDataProtection => _macOsDataProtection;

  /// errSecMissingEntitlement as reported by flutter_secure_storage.
  static bool isMissingEntitlementError(Object error) =>
      error.toString().contains('-34018');

  /// Probe the OS keychain without exposing a secret. A locked or unavailable
  /// keychain throws/returns false instead of making every later read fail.
  Future<bool> isAvailable() async {
    try {
      await verifyAvailable();
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);

  @override
  Future<bool> containsKey(String key) => _storage.containsKey(key: key);

  @override
  Future<void> deleteAll() => _storage.deleteAll();
}

/// Ephemeral storage for session-only mode and tests. No legacy credentials
/// may be imported or deleted on the strength of writes to this store.
class InMemorySecureStorage extends SecureStorage {
  final Map<String, String> _store = {};

  @override
  bool get isPersistent => false;

  @override
  Future<String?> read(String key) async => _store[key];

  @override
  Future<void> write(String key, String value) async {
    _store[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _store.remove(key);
  }

  @override
  Future<bool> containsKey(String key) async => _store.containsKey(key);

  @override
  Future<void> deleteAll() async {
    _store.clear();
  }
}
