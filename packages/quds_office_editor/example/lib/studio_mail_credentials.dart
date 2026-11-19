import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Host-owned credential record for the native Studio Mail session.
///
/// The password is stored in the platform keychain, never in the example
/// directory or preferences. Browser builds do not use this class.
class StudioMailCredentials {
  const StudioMailCredentials({
    required this.email,
    required this.password,
    required this.imapHost,
    required this.smtpHost,
    required this.manual,
    required this.startTls,
  });

  final String email;
  final String password;
  final String imapHost;
  final String smtpHost;
  final bool manual;
  final bool startTls;

  Map<String, Object?> toJson() => <String, Object?>{
    'email': email,
    'password': password,
    'imapHost': imapHost,
    'smtpHost': smtpHost,
    'manual': manual,
    'startTls': startTls,
  };

  static StudioMailCredentials? fromJson(Map<String, Object?> json) {
    final email = json['email'];
    final password = json['password'];
    final imapHost = json['imapHost'];
    final smtpHost = json['smtpHost'];
    if (email is! String ||
        password is! String ||
        imapHost is! String ||
        smtpHost is! String) {
      return null;
    }
    return StudioMailCredentials(
      email: email,
      password: password,
      imapHost: imapHost,
      smtpHost: smtpHost,
      manual: json['manual'] == true,
      startTls: json['startTls'] == true,
    );
  }
}

/// Persists one Mail account in the platform keychain.
///
/// Operations are ordered so a pending save cannot complete after a later
/// deletion. Native dialogs share [shared], including across dialog lifetimes.
class StudioMailCredentialStore {
  StudioMailCredentialStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static final shared = StudioMailCredentialStore();
  static const _key = 'crispoffice.mail.account.v1';
  final FlutterSecureStorage _storage;
  Future<void> _pending = Future<void>.value();

  Future<T> _ordered<T>(Future<T> Function() operation) {
    final result = _pending.then((_) => operation());
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<StudioMailCredentials?> load() => _ordered(() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      return decoded is Map<String, Object?>
          ? StudioMailCredentials.fromJson(decoded)
          : null;
    } on Object {
      return null;
    }
  });

  /// True only when the platform confirms the write. Failure is nonthrowing.
  Future<bool> save(StudioMailCredentials credentials) => _ordered(() async {
    try {
      await _storage.write(key: _key, value: jsonEncode(credentials.toJson()));
      return true;
    } on Object {
      return false;
    }
  });

  /// True only when the platform confirms deletion. Failure is nonthrowing.
  Future<bool> clear() => _ordered(() async {
    try {
      await _storage.delete(key: _key);
      return true;
    } on Object {
      return false;
    }
  });
}
