import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import 'credentials/secure_storage_service.dart';
import 'credentials/utils/async_lock.dart';
import 'credentials/secure_storage_file_io.dart';
import 'credentials/secure_storage_macos_keychain.dart';

enum StudioCredentialMode { system, customKeychain, encryptedVault, session }

/// Non-secret selection. A failed selected store never falls back to another.
class StudioCredentialStorage extends ChangeNotifier {
  StudioCredentialStorage({
    Future<SecureStorage> Function()? systemStorageFactory,
  }) : _systemStorageFactory = systemStorageFactory ?? _createSystemStorage;

  static final instance = StudioCredentialStorage();
  static const preferenceKey = 'crispoffice.credentials.selection.v1';
  StudioCredentialMode mode = StudioCredentialMode.system;
  String? customPath;
  final _stores = <String, SecureStorage>{};
  final _selectionOperations = AsyncLock();
  bool _loaded = false;
  int _selectionGeneration = 0;
  final Future<SecureStorage> Function() _systemStorageFactory;

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
              defaultTargetPlatform != TargetPlatform.macOS ||
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
      });
}
