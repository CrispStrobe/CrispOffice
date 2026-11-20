import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'credentials/secure_storage_service.dart';
import 'credentials/utils/async_lock.dart';
import 'studio_credential_storage.dart';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'studio_mail_compose.dart';
import 'studio_mail_presets.dart';

/// Host-owned credential record. Only the platform keychain receives its JSON;
/// diagnostics and exception messages must never include the record's values.
class StudioMailCredentials {
  const StudioMailCredentials({
    required this.email,
    required this.password,
    required this.imapHost,
    required this.smtpHost,
    required this.manual,
    required this.startTls,
    this.preset,
    this.primaryLogin = '',
    this.icloudFullAddressLogin = false,
  });

  final String email;
  final String password;
  final String imapHost;
  final String smtpHost;
  final bool manual;
  final bool startTls;
  final StudioMailImapPreset? preset;
  final String primaryLogin;
  final bool icloudFullAddressLogin;

  Map<String, Object?> toJson() => <String, Object?>{
    'email': email,
    'password': password,
    'imapHost': imapHost,
    'smtpHost': smtpHost,
    'manual': manual,
    'startTls': startTls,
    'preset': preset?.name,
    'primaryLogin': primaryLogin,
    'icloudFullAddressLogin': icloudFullAddressLogin,
  };

  static StudioMailCredentials? fromJson(Map<String, Object?> json) {
    final email = json['email'];
    final password = json['password'];
    final imapHost = json['imapHost'];
    final smtpHost = json['smtpHost'];
    final manual = json['manual'];
    final startTls = json['startTls'];
    final primaryLogin = json['primaryLogin'] ?? '';
    final fullIcloudLogin = json['icloudFullAddressLogin'] ?? false;
    final presetName = json['preset'];
    final preset = StudioMailImapPreset.values
        .where((item) => item.name == presetName)
        .firstOrNull;
    bool validHost(String value) =>
        value.length <= 1024 && !value.contains(RegExp(r'[\x00-\x20\x7f]'));
    if (email is! String ||
        !StudioMailDraft.isSupportedAddress(email) ||
        password is! String ||
        password.isEmpty ||
        password.length > 64 * 1024 ||
        password.contains(RegExp(r'[\x00-\x1f\x7f]')) ||
        imapHost is! String ||
        !validHost(imapHost) ||
        smtpHost is! String ||
        !validHost(smtpHost) ||
        manual is! bool ||
        startTls is! bool ||
        primaryLogin is! String ||
        primaryLogin.isNotEmpty &&
            !StudioMailDraft.isSupportedAddress(primaryLogin) ||
        fullIcloudLogin is! bool ||
        presetName != null && preset == null ||
        manual && (imapHost.isEmpty || smtpHost.isEmpty)) {
      return null;
    }
    return StudioMailCredentials(
      email: email,
      password: password,
      imapHost: imapHost,
      smtpHost: smtpHost,
      manual: manual,
      startTls: startTls,
      preset: preset,
      primaryLogin: primaryLogin,
      icloudFullAddressLogin: fullIcloudLogin,
    );
  }

  @override
  String toString() => 'StudioMailCredentials(redacted)';
}

/// Persists one account in the native platform keychain. Writes report actual
/// success; failure must never be presented as a saved or forgotten account.
abstract interface class StudioMailCredentialStore {
  factory StudioMailCredentialStore({FlutterSecureStorage? storage}) =>
      storage == null
      ? StudioMailAccountsStore()
      : _PlatformStudioMailCredentialStore(storage: storage);

  Future<StudioMailCredentials?> load();

  /// True only when the platform confirms the write. Failure is nonthrowing.
  Future<bool> save(StudioMailCredentials credentials);

  /// True only when the platform confirms deletion. Failure is nonthrowing.
  Future<bool> clear();
}

final class _PlatformStudioMailCredentialStore
    implements StudioMailCredentialStore {
  _PlatformStudioMailCredentialStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'crispoffice.mail.account.v1';
  static final _operations = AsyncLock();
  final FlutterSecureStorage _storage;

  Future<T> _ordered<T>(Future<T> Function() operation) => _operations.synchronized(operation);

  @override
  Future<StudioMailCredentials?> load() => _ordered(() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null || raw.isEmpty || raw.length > 256 * 1024) return null;
      final Object? decoded = jsonDecode(raw);
      return decoded is Map<String, Object?>
          ? StudioMailCredentials.fromJson(decoded)
          : null;
    } on Object {
      return null;
    }
  });

  @override
  Future<bool> save(StudioMailCredentials credentials) => _ordered(() async {
    try {
      final json = credentials.toJson();
      if (StudioMailCredentials.fromJson(json) == null) return false;
      await _storage.write(key: _key, value: jsonEncode(json));
      return true;
    } on Object {
      return false;
    }
  });

  @override
  Future<bool> clear() => _ordered(() async {
    try {
      await _storage.delete(key: _key);
      return true;
    } on Object {
      return false;
    }
  });
}

/// Multiple remembered accounts; the foreground transport remains explicitly
/// selected by the user. Every record stays inside the selected secure store.
class StudioMailAccountsStore implements StudioMailCredentialStore {
  StudioMailAccountsStore({Future<SecureStorage> Function()? storage})
    : _storage = storage ?? (() => StudioCredentialStorage.instance.storage);
  final Future<SecureStorage> Function() _storage;
  static const _key = 'crispoffice.mail.accounts.v2';
  static const _legacyKey = 'crispoffice.mail.account.v1';
  static final _lock = AsyncLock();
  String? _active;
  String _id(StudioMailCredentials c) => sha256
      .convert(
        utf8.encode(
          '${c.email.trim().toLowerCase()}\n${c.imapHost.toLowerCase()}\n${c.preset?.name ?? ''}',
        ),
      )
      .toString();
  Future<Map<String, StudioMailCredentials>> _read(SecureStorage s) async {
    final raw = await s.read(_key);
    if (raw == null) {
      final legacy = await s.read(_legacyKey);
      if (legacy == null) return {};
      final old = StudioMailCredentials.fromJson(
        jsonDecode(legacy) as Map<String, Object?>,
      );
      return old == null ? {} : {_id(old): old};
    }
    if (raw.length > 2 * 1024 * 1024)
      throw const FormatException('Account store is too large.');
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    if (decoded['version'] != 2 || decoded['accounts'] is! Map) {
      throw const FormatException('Unsupported account store.');
    }
    _active ??= decoded['active'] as String?;
    final result = <String, StudioMailCredentials>{};
    for (final e in (decoded['accounts'] as Map<String, dynamic>).entries) {
      final c = StudioMailCredentials.fromJson(e.value as Map<String, Object?>);
      if (c == null || e.key != _id(c))
        throw const FormatException('Invalid saved account.');
      result[e.key] = c;
    }
    return result;
  }

  Future<void> _write(
    SecureStorage s,
    Map<String, StudioMailCredentials> accounts,
  ) async {
    final raw = jsonEncode({
      'version': 2,
      'active': _active,
      'accounts': accounts.map((k, v) => MapEntry(k, v.toJson())),
    });
    await s.write(_key, raw);
    if (await s.read(_key) != raw)
      throw StateError('Credential-store verification failed.');
    // v1 belongs to this app only; retain it if the verified v2 write fails.
    await s.delete(_legacyKey);
  }

  Future<List<StudioMailCredentials>> accounts() =>
      _lock.synchronized(() async {
        final values = (await _read(await _storage())).values.toList();
        values.sort((a, b) => a.email.compareTo(b.email));
        return values;
      });
  void selectAccount(StudioMailCredentials c) {
    _active = _id(c);
  }

  @override
  Future<StudioMailCredentials?> load() => _lock.synchronized(() async {
    final all = await _read(await _storage());
    _active = all.containsKey(_active) ? _active : all.keys.firstOrNull;
    return all[_active];
  });
  @override
  Future<bool> save(StudioMailCredentials c) => _lock.synchronized(() async {
    try {
      if (StudioMailCredentials.fromJson(c.toJson()) == null) return false;
      final s = await _storage();
      final all = await _read(s);
      _active = _id(c);
      all[_active!] = c;
      await _write(s, all);
      return true;
    } on Object {
      return false;
    }
  });
  @override
  Future<bool> clear() => _lock.synchronized(() async {
    try {
      final s = await _storage();
      final all = await _read(s);
      final active = _active ?? all.keys.firstOrNull;
      all.remove(active);
      _active = all.keys.firstOrNull;
      await _write(s, all);
      return true;
    } on Object {
      return false;
    }
  });
}
