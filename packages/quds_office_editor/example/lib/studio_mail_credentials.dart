import 'dart:convert';

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
  factory StudioMailCredentialStore({FlutterSecureStorage? storage}) =
      _PlatformStudioMailCredentialStore;

  Future<StudioMailCredentials?> load();
  Future<bool> save(StudioMailCredentials credentials);
  Future<bool> clear();
}

final class _PlatformStudioMailCredentialStore
    implements StudioMailCredentialStore {
  _PlatformStudioMailCredentialStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'crispoffice.mail.account.v1';
  static Future<void> _queue = Future<void>.value();
  final FlutterSecureStorage _storage;

  // Serialize even across dialog instances. A later Forget must not be undone
  // by an older slow keychain write, and a failed operation must release the queue.
  Future<T> _ordered<T>(Future<T> Function() operation) {
    final result = _queue.then((_) => operation());
    _queue = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

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
