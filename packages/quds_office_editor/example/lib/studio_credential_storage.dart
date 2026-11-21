import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import 'credentials/biometric_secret_store.dart';
import 'credentials/secure_storage_service.dart';
import 'credentials/secure_storage_web.dart';
import 'credentials/utils/async_lock.dart';
import 'credentials/secure_storage_file_io.dart';
import 'credentials/secure_storage_macos_keychain.dart';

enum StudioCredentialMode { system, customKeychain, encryptedVault, session }

/// Outcome of trying to open the encrypted vault with biometry.
enum StudioVaultBiometricUnlock {
  /// The vault is open; no password was needed.
  unlocked,

  /// Biometric unlock is not turned on for this vault.
  notEnabled,

  /// Turned on, but biometry or the keychain cannot be used right now.
  unavailable,

  /// The user dismissed the system sheet.
  cancelled,

  /// Authentication or the vault/keychain operation failed.
  failed,

  /// The stored key is gone or no longer opens the vault (fingerprints
  /// changed, vault replaced). Biometric unlock has been turned off; offer
  /// it again after the next master-password unlock.
  invalidated,
}

/// Non-secret selection. A failed selected store never falls back to another.
class StudioCredentialStorage extends ChangeNotifier {
  StudioCredentialStorage({
    Future<SecureStorage> Function()? systemStorageFactory,
    BiometricSecretStore? biometrics,
    @visibleForTesting this._vaultFactory,
  }) : _systemStorageFactory = systemStorageFactory ?? _createSystemStorage,
       biometrics = biometrics ?? const MethodChannelBiometricSecretStore();

  static final instance = StudioCredentialStorage();
  static const preferenceKey = 'crispoffice.credentials.selection.v1';

  /// Non-secret flag: a biometry-protected vault key was stored. The key
  /// itself lives only in the OS keychain item ([biometrics]).
  static const biometricPreferenceKey =
      'crispoffice.credentials.vault-biometric.v1';
  static const _biometricPayloadVersion = 1;
  StudioCredentialMode mode = StudioCredentialMode.system;
  String? customPath;
  final _stores = <String, SecureStorage>{};
  final _selectionOperations = AsyncLock();
  bool _loaded = false;
  int _selectionGeneration = 0;
  final Future<SecureStorage> Function() _systemStorageFactory;
  final Future<WebEncryptedStorage> Function()? _vaultFactory;
  final BiometricSecretStore biometrics;
  final _biometricOperations = AsyncLock();
  bool _biometricCleanupPending = false;

  /// A protected item or its preference still needs removal. No secret is
  /// exposed, and biometric unlock stays disabled until cleanup or enrolment
  /// completes successfully.
  bool get biometricCleanupPending => _biometricCleanupPending;

  /// Set when a stored biometric key was invalidated, so the next
  /// master-password unlock explains why biometric unlock is offered again.
  bool biometricReenrolmentSuggested = false;

  /// Changes only after a selected backend is successfully committed.
  int get revision => _selectionGeneration;

  static Future<SecureStorage> _createSystemStorage() async {
    // Determine capability before reading credentials. A denied or locked
    // store still fails explicitly rather than selecting another backend.
    await PlatformSecureStorage.detectMacOsKeychain();
    return PlatformSecureStorage();
  }

  String get label => switch (mode) {
    StudioCredentialMode.system => 'System credential store',
    StudioCredentialMode.customKeychain => 'Custom macOS keychain',
    StudioCredentialMode.encryptedVault => 'Encrypted credential vault',
    StudioCredentialMode.session => 'This session only',
  };
  bool get persistent => mode != StudioCredentialMode.session;
  Future<void> loadSelection() async {
    if (_loaded) return;
    final raw = (await SharedPreferences.getInstance()).getString(
      preferenceKey,
    );
    if (raw != null) {
      final value = jsonDecode(raw) as Map<String, Object?>;
      mode = StudioCredentialMode.values.byName(value['mode'] as String);
      customPath = value['path'] as String?;
      if (mode == StudioCredentialMode.customKeychain &&
          (customPath == null || customPath!.trim().isEmpty)) {
        throw const FormatException('A custom keychain path is required.');
      }
    }
    _loaded = true;
    // Also remove a key left by failed enrolment while the vault is selected:
    // its durable disabled preference deliberately does not authorize reads.
    unawaited(_clearStaleBiometricSecret());
  }

  Future<void> _clearStaleBiometricSecret() =>
      _biometricOperations.synchronized(() async {
        try {
          if (mode != StudioCredentialMode.encryptedVault ||
              _biometricCleanupPending ||
              !await biometricUnlockEnabled()) {
            await _removeBiometricSecret(bestEffort: true);
          }
        } on Object {
          // Preferences unavailable: retried on the next start.
        }
      });

  Future<File> get vaultFile async => File(
    p.join(
      (await getApplicationSupportDirectory()).path,
      'credential-vault.json',
    ),
  );
  Future<WebEncryptedStorage> _openVaultHandle() async =>
      await _vaultFactory?.call() ?? EncryptedFileStorage(await vaultFile);
  static final _vaultIdentity = '${StudioCredentialMode.encryptedVault.name}:';
  Future<bool> vaultExists() async => (await _openVaultHandle()).hasVault();

  /// Whether this process currently holds an unlocked vault handle.
  bool get vaultUnlocked => _stores.containsKey(_vaultIdentity);

  Future<void> unlockVault(String password, {required bool create}) async {
    if (password.isEmpty) throw ArgumentError('Enter a master password.');
    final vault = await _openVaultHandle();
    await vault.initialize(password, expectedExisting: !create);
    _stores[_vaultIdentity] = vault;
    if (create) {
      // A new vault replaces a removed or reset one; a key stored for the old
      // vault must never linger in the keychain.
      await _removeBiometricSecret(bestEffort: true);
    }
  }

  // ---- Biometric (Touch ID) unlock of the encrypted vault ----------------
  //
  // The derived 256-bit vault key, not the master password, is stored: the
  // native vault (pure-Dart PBKDF2/AES-GCM) can be opened directly with that
  // key via WebEncryptedStorage.initializeWithKey. A key is bound to the
  // vault's salt, so a vault created again or re-keyed under another password
  // rejects it and the item is deleted. The master password never leaves the
  // unlock dialog. Neither key nor payload is ever logged.

  Future<BiometricUnlockAvailability> biometricAvailability() async {
    try {
      return await biometrics.availability();
    } on Object {
      return BiometricUnlockAvailability.error;
    }
  }

  Future<bool> biometricUnlockEnabled() async =>
      !_biometricCleanupPending &&
      ((await SharedPreferences.getInstance()).getBool(
            biometricPreferenceKey,
          ) ??
          false);

  Future<void> _setBiometricFlag(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final saved = enabled
          ? await prefs.setBool(biometricPreferenceKey, true)
          : await prefs.remove(biometricPreferenceKey);
      if (!saved) {
        throw StateError('Could not save the biometric unlock setting.');
      }
    } on Object {
      // SharedPreferences mutates its cache before the platform confirms a
      // write. A rejected enable must not look successful in this process.
      try {
        await prefs.reload();
      } on Object {
        // The pending-cleanup guard still prevents using the uncommitted key.
      }
      rethrow;
    }
  }

  /// Stores the key of the currently unlocked vault behind biometry. The
  /// vault must have been unlocked in this process (normally just now, with
  /// its master password).
  Future<void> enableBiometricUnlock() =>
      _biometricOperations.synchronized(() async {
        await loadSelection();
        if (mode != StudioCredentialMode.encryptedVault) {
          throw StateError('Select the encrypted credential vault first.');
        }
        final generation = _selectionGeneration;
        final vault = _stores[_vaultIdentity];
        if (vault is! WebEncryptedStorage) {
          throw StateError('Unlock the encrypted credential vault first.');
        }
        void checkContext() {
          if (mode != StudioCredentialMode.encryptedVault ||
              generation != _selectionGeneration ||
              !identical(_stores[_vaultIdentity], vault)) {
            throw StateError(
              'Credential storage changed during biometric enrolment.',
            );
          }
        }

        final availability = await biometricAvailability();
        checkContext();
        if (availability != BiometricUnlockAvailability.available) {
          throw StateError('Biometric unlock is not available.');
        }
        final key = await vault.exportUnlockKey();
        if (key == null) {
          throw StateError('This vault cannot be unlocked with a stored key.');
        }
        final String payload;
        try {
          checkContext();
          payload = jsonEncode({
            'v': _biometricPayloadVersion,
            'key': base64.encode(key),
          });
        } finally {
          key.fillRange(0, key.length, 0);
        }
        _biometricCleanupPending = true;
        try {
          // Write the disabled state first. A crash or rejected enable after
          // storing the key then leaves durable evidence that startup must
          // remove it, even when the vault remains the selected backend.
          await _setBiometricFlag(false);
          checkContext();
          await biometrics.store(payload);
          checkContext();
          await _setBiometricFlag(true);
          checkContext();
          _biometricCleanupPending = false;
        } on Object {
          await _removeBiometricSecret(bestEffort: true);
          rethrow;
        }
        biometricReenrolmentSuggested = false;
      });

  /// Turns biometric unlock off and deletes the keychain item.
  Future<void> disableBiometricUnlock() =>
      _biometricOperations.synchronized(() => _removeBiometricSecret());

  Future<void> _removeBiometricSecret({bool bestEffort = false}) async {
    _biometricCleanupPending = true;
    Object? failure;
    StackTrace? failureStack;
    try {
      // Persist the disabled state before deleting. If the OS refuses removal,
      // next startup retries even while the encrypted vault remains selected.
      await _setBiometricFlag(false);
    } on Object catch (error, stack) {
      failure = error;
      failureStack = stack;
    }
    try {
      await biometrics.delete();
    } on Object catch (error, stack) {
      failure ??= error;
      failureStack ??= stack;
    }
    if (failure == null) {
      _biometricCleanupPending = false;
    } else if (!bestEffort) {
      Error.throwWithStackTrace(failure, failureStack!);
    }
  }

  Future<void> _invalidateBiometricUnlock() async {
    biometricReenrolmentSuggested = true;
    await _removeBiometricSecret(bestEffort: true);
  }

  /// Opens the encrypted vault with the biometry-protected key. Anything but
  /// [StudioVaultBiometricUnlock.unlocked] leaves the vault locked; callers
  /// then fall back to the master-password prompt.
  Future<StudioVaultBiometricUnlock> unlockVaultWithBiometrics({
    required String reason,
    String? cancelTitle,
    String? fallbackTitle,
  }) => _biometricOperations.synchronized(() async {
    try {
      if (!await biometricUnlockEnabled()) {
        return StudioVaultBiometricUnlock.notEnabled;
      }
    } on Object {
      return StudioVaultBiometricUnlock.failed;
    }
    if (await biometricAvailability() !=
        BiometricUnlockAvailability.available) {
      return StudioVaultBiometricUnlock.unavailable;
    }
    final BiometricSecretRead read;
    try {
      read = await biometrics.read(
        reason: reason,
        cancelTitle: cancelTitle,
        fallbackTitle: fallbackTitle,
      );
    } on Object {
      return StudioVaultBiometricUnlock.failed;
    }
    switch (read.status) {
      case BiometricSecretReadStatus.success:
        break;
      case BiometricSecretReadStatus.cancelled:
        return StudioVaultBiometricUnlock.cancelled;
      case BiometricSecretReadStatus.unavailable:
        return StudioVaultBiometricUnlock.unavailable;
      case BiometricSecretReadStatus.failed:
        return StudioVaultBiometricUnlock.failed;
      case BiometricSecretReadStatus.notFound:
        await _invalidateBiometricUnlock();
        return StudioVaultBiometricUnlock.invalidated;
    }
    final secret = read.secret;
    final key = secret == null ? null : _decodeBiometricPayload(secret);
    if (key == null) {
      await _invalidateBiometricUnlock();
      return StudioVaultBiometricUnlock.invalidated;
    }
    final WebEncryptedStorage vault;
    try {
      vault = await _openVaultHandle();
      await vault.initializeWithKey(key);
    } on CredentialVaultKeyRejected {
      await _invalidateBiometricUnlock();
      return StudioVaultBiometricUnlock.invalidated;
    } on Object {
      // Missing/damaged vault, lock contention or I/O: the key may still be
      // valid, so keep it and let the password path report the problem.
      return StudioVaultBiometricUnlock.failed;
    } finally {
      key.fillRange(0, key.length, 0);
    }
    _stores[_vaultIdentity] = vault;
    return StudioVaultBiometricUnlock.unlocked;
  });

  static Uint8List? _decodeBiometricPayload(String payload) {
    try {
      final value = jsonDecode(payload);
      if (value is! Map<String, Object?> ||
          value['v'] != _biometricPayloadVersion ||
          value['key'] is! String) {
        return null;
      }
      final key = base64.decode(value['key'] as String);
      return key.length == 32 ? key : null;
    } on FormatException {
      return null;
    }
  }

  Future<SecureStorage> get storage async {
    if (!_loaded) await loadSelection();
    // Capture identity and generation before native initialization yields.
    final selectedMode = mode;
    final selectedPath = customPath;
    final selectedIdentity = '${selectedMode.name}:${selectedPath ?? ''}';
    final generation = _selectionGeneration;
    final cached = _stores[selectedIdentity];
    if (cached != null) return cached;
    final SecureStorage result;
    switch (selectedMode) {
      case StudioCredentialMode.system:
        result = await _systemStorageFactory();
      case StudioCredentialMode.session:
        result = InMemorySecureStorage();
      case StudioCredentialMode.customKeychain:
        final selected = MacOsCustomKeychainStorage(path: selectedPath!);
        await selected.initialize();
        result = selected;
      case StudioCredentialMode.encryptedVault:
        throw StateError(
          'Unlock the encrypted credential vault in Credential storage.',
        );
    }
    // This instance belongs to the selection captured above, including its
    // persistence policy. Never cache it under a later selection or replace a
    // newer instance after switching away and back to the same store.
    if (generation == _selectionGeneration &&
        mode == selectedMode &&
        customPath == selectedPath) {
      return _stores.putIfAbsent(selectedIdentity, () => result);
    }
    // An operation already opening the old backend stays with that backend;
    // changing selection cannot redirect an in-flight credential transaction.
    return result;
  }

  Future<void> select(StudioCredentialMode next, {String? path}) =>
      _selectionOperations.synchronized(() async {
        await loadSelection();
        if (next == StudioCredentialMode.customKeychain) {
          if (kIsWeb ||
              !Platform.isMacOS ||
              path == null ||
              path.trim().isEmpty) {
            throw ArgumentError('Choose a macOS keychain file.');
          }
          final store = MacOsCustomKeychainStorage(path: path);
          await store.initialize();
          _stores['${next.name}:$path'] = store;
        }
        if (next == StudioCredentialMode.encryptedVault &&
            !_stores.containsKey('${next.name}:')) {
          throw StateError('Unlock or create the vault first.');
        }
        final record = jsonEncode({
          'mode': next.name,
          'path': next == StudioCredentialMode.customKeychain ? path : null,
        });
        final prefs = await SharedPreferences.getInstance();
        if (!await prefs.setString(preferenceKey, record)) {
          throw StateError('Could not save the credential-store selection.');
        }
        _selectionGeneration++;
        mode = next;
        customPath = next == StudioCredentialMode.customKeychain ? path : null;
        notifyListeners();
        if (next != StudioCredentialMode.encryptedVault) {
          // Leaving the vault: its biometric key must not outlive the choice.
          await _clearStaleBiometricSecret();
        }
      });
}
