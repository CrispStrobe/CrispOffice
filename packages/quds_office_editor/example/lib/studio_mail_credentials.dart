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
final class StudioMailCredentialStore {
  StudioMailCredentialStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'crispoffice.mail.account.v1';
  final FlutterSecureStorage _storage;

  Future<StudioMailCredentials?> load() async {
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
  }

  Future<void> save(StudioMailCredentials credentials) async {
    try {
      await _storage.write(key: _key, value: jsonEncode(credentials.toJson()));
    } on Object {
      // A missing keychain entitlement must not lose the active session.
    }
  }

  Future<void> clear() async {
    try {
      await _storage.delete(key: _key);
    } on Object {
      // Ignore unavailable platform keychains in the example host.
    }
  }
}
