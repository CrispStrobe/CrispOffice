import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import 'credentials/secure_storage_service.dart';
import 'credentials/secure_storage_file_io.dart';
import 'credentials/secure_storage_macos_keychain.dart';

enum StudioCredentialMode { system, customKeychain, encryptedVault, session }

/// Non-secret selection. A failed selected store never falls back to another.
class StudioCredentialStorage extends ChangeNotifier {
  static final instance = StudioCredentialStorage();
  static const preferenceKey = 'crispoffice.credentials.selection.v1';
  StudioCredentialMode mode = StudioCredentialMode.system;
  String? customPath;
  final _stores = <String, SecureStorage>{};
  bool _loaded = false;
  String get label => switch (mode) {
    StudioCredentialMode.system => 'System credential store',
    StudioCredentialMode.customKeychain => 'Custom macOS keychain',
    StudioCredentialMode.encryptedVault => 'Encrypted credential vault',
    StudioCredentialMode.session => 'This session only',
  };
  String get _identity => '${mode.name}:${customPath ?? ''}';
  bool get persistent => mode != StudioCredentialMode.session;
  Future<void> loadSelection() async {
    if (_loaded) return;
    final raw = (await SharedPreferences.getInstance()).getString(
      preferenceKey,
    );
    if (raw != null) {
      final value = jsonDecode(raw) as Map<String, dynamic>;
      mode = StudioCredentialMode.values.byName(value['mode'] as String);
      customPath = value['path'] as String?;
      if (mode == StudioCredentialMode.customKeychain &&
          (customPath == null || customPath!.trim().isEmpty)) {
        throw const FormatException('A custom keychain path is required.');
      }
    }
    _loaded = true;
  }

  Future<File> get vaultFile async => File(
    p.join(
      (await getApplicationSupportDirectory()).path,
      'credential-vault.json',
    ),
  );
  Future<bool> vaultExists() async =>
      EncryptedFileStorage(await vaultFile).hasVault();
  Future<void> unlockVault(String password, {required bool create}) async {
    if (password.isEmpty) throw ArgumentError('Enter a master password.');
    final vault = EncryptedFileStorage(await vaultFile);
    await vault.initialize(password, expectedExisting: !create);
    _stores['${StudioCredentialMode.encryptedVault.name}:'] = vault;
  }

  Future<SecureStorage> get storage async {
    await loadSelection();
    final cached = _stores[_identity];
    if (cached != null) return cached;
    final SecureStorage result;
    switch (mode) {
      case StudioCredentialMode.system:
        // Use CrispCloud's capability check before reading any credential:
        // a missing Data Protection entitlement selects the OS file keychain.
        // Locked/denied/unavailable stores never trigger credential fallbacks.
        await PlatformSecureStorage.detectMacOsKeychain();
        result = PlatformSecureStorage();
      case StudioCredentialMode.session:
        result = InMemorySecureStorage();
      case StudioCredentialMode.customKeychain:
        final selected = MacOsCustomKeychainStorage(path: customPath!);
        await selected.initialize();
        result = selected;
      case StudioCredentialMode.encryptedVault:
        throw StateError(
          'Unlock the encrypted credential vault in Credential storage.',
        );
    }
    _stores[_identity] = result;
    return result;
  }

  Future<void> select(StudioCredentialMode next, {String? path}) async {
    await loadSelection();
    if (next == StudioCredentialMode.customKeychain) {
      if (!Platform.isMacOS || path == null || path.trim().isEmpty) {
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
    mode = next;
    customPath = next == StudioCredentialMode.customKeychain ? path : null;
    notifyListeners();
  }
}
