import 'dart:convert';
import 'credentials/secure_storage_service.dart';
import 'credentials/utils/async_lock.dart';
import 'studio_credential_storage.dart';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'studio_mail_presets.dart';
import 'studio_mail_recipients.dart';

/// Immutable effective route fields for account identity and chooser labels.
/// Credentials and tokens are deliberately absent from this presentation value.
typedef StudioMailConnectionIdentity = ({
  String sender,
  String imapHost,
  int imapPort,
  bool imapStartTls,
  String imapLogin,
  String smtpHost,
  int smtpPort,
  bool smtpStartTls,
  String smtpLogin,
});

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

  /// Uses the same preset precedence and login choices as account connection.
  /// Hostnames are canonicalized; complete login and sender casing stays exact.
  StudioMailConnectionIdentity get connectionIdentity {
    final sender = email.trim();
    final login = preset == null || primaryLogin.trim().isEmpty
        ? sender
        : primaryLogin.trim();
    final incomingLogin =
        preset == StudioMailImapPreset.icloud && !icloudFullAddressLogin
        ? login.split('@').first
        : login;
    final incomingStartTls = preset == null && startTls;
    final outgoingStartTls = preset == null
        ? startTls
        : preset == StudioMailImapPreset.icloud;
    return (
      sender: sender,
      imapHost: (preset?.imapHost ?? imapHost).trim().toLowerCase(),
      imapPort: incomingStartTls ? 143 : 993,
      imapStartTls: incomingStartTls,
      imapLogin: incomingLogin,
      smtpHost: (preset?.smtpHost ?? smtpHost).trim().toLowerCase(),
      smtpPort: outgoingStartTls ? 587 : 465,
      smtpStartTls: outgoingStartTls,
      smtpLogin: login,
    );
  }

  /// Stable identity of the effective endpoints, logins and sending address.
  /// Password rotation does not create another account. Hostname casing is
  /// insignificant; the complete authentication login and sending address stay
  /// exact, matching the existing connection and local-draft identity contract.
  /// The digest contains no credential bytes and is not a credential itself.
  String get accountId {
    final identity = connectionIdentity;
    return sha256
        .convert(
          utf8.encode(
            jsonEncode([
              'studio-imap-smtp-account-v2',
              identity.imapHost,
              identity.imapPort,
              identity.imapStartTls ? 'starttls' : 'tls',
              identity.imapLogin,
              identity.smtpHost,
              identity.smtpPort,
              identity.smtpStartTls ? 'starttls' : 'tls',
              identity.smtpLogin,
              identity.sender,
            ]),
          ),
        )
        .toString();
  }

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
        !StudioMailRecipients.isSupportedAddress(email) ||
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
            !StudioMailRecipients.isSupportedAddress(primaryLogin) ||
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

/// One remembered account. Credential material stays inside the host boundary;
/// neither this value nor a catalog should be included in diagnostics.
final class StudioMailSavedAccount {
  const StudioMailSavedAccount({required this.id, required this.credentials});

  final String id;
  final StudioMailCredentials credentials;

  @override
  String toString() => 'StudioMailSavedAccount(redacted)';
}

/// Immutable snapshot of the bounded native keychain catalog.
final class StudioMailAccountCatalog {
  StudioMailAccountCatalog({
    required List<StudioMailSavedAccount> accounts,
    this.selectedAccountId,
  }) : accounts = List.unmodifiable(accounts);

  static const maxAccounts = 20;

  final List<StudioMailSavedAccount> accounts;
  final String? selectedAccountId;

  StudioMailSavedAccount? get selectedAccount =>
      accounts.where((account) => account.id == selectedAccountId).firstOrNull;

  @override
  String toString() => 'StudioMailAccountCatalog(redacted)';
}

enum StudioMailAccountCatalogProblem {
  unavailable,
  invalid,
  limitReached,
  notFound,
}

/// A failed read is distinct from an empty catalog. Mutations never replace
/// unreadable, malformed or newer-version data with an empty account list.
final class StudioMailAccountCatalogResult {
  const StudioMailAccountCatalogResult.success(StudioMailAccountCatalog value)
    : catalog = value,
      problem = null;

  const StudioMailAccountCatalogResult.failure(
    StudioMailAccountCatalogProblem value,
  ) : catalog = null,
      problem = value;

  final StudioMailAccountCatalog? catalog;
  final StudioMailAccountCatalogProblem? problem;
  bool get isSuccess => catalog != null && problem == null;

  @override
  String toString() => isSuccess
      ? 'StudioMailAccountCatalogResult(success)'
      : 'StudioMailAccountCatalogResult(${problem?.name})';
}

/// Optional capability beside the legacy single-account host seam.
/// Selecting a record never connects or sends a provider request.
abstract interface class StudioMailAccountCatalogStore {
  Future<StudioMailAccountCatalogResult> loadAccounts();
  Future<StudioMailAccountCatalogResult> saveAccount(
    StudioMailCredentials credentials,
  );
  Future<StudioMailAccountCatalogResult> selectAccount(String id);
  Future<StudioMailAccountCatalogResult> forgetAccount(String id);
}

/// Legacy selected-account facade. Existing host fakes remain compatible; the
/// platform implementation also offers [StudioMailAccountCatalogStore]. Writes
/// report actual success. [clear] forgets only the selected remembered account.
abstract interface class StudioMailCredentialStore {
  factory StudioMailCredentialStore({
    FlutterSecureStorage? storage,
    Future<SecureStorage> Function()? backend,
  }) = _PlatformStudioMailCredentialStore;

  Future<StudioMailCredentials?> load();

  /// True only when the platform confirms the write. Failure is nonthrowing.
  Future<bool> save(StudioMailCredentials credentials);

  /// True only when the platform confirms removal. Failure is nonthrowing.
  /// Other remembered accounts, local drafts and archives are unaffected.
  Future<bool> clear();
}

final class _PlatformStudioMailCredentialStore
    implements StudioMailCredentialStore, StudioMailAccountCatalogStore {
  _PlatformStudioMailCredentialStore({
    FlutterSecureStorage? storage,
    Future<SecureStorage> Function()? backend,
  }) : _storage = storage,
       _backend = backend ?? (() => StudioCredentialStorage.instance.storage);

  static const _legacyKey = 'crispoffice.mail.account.v1';
  static const _catalogKey = 'crispoffice.mail.accounts.v2';
  static const _maxLegacyCodeUnits = 256 * 1024;
  static const _maxCatalogCodeUnits = 4 * 1024 * 1024;
  static final _operations = AsyncLock();
  final FlutterSecureStorage? _storage;
  final Future<SecureStorage> Function() _backend;
  SecureStorage? _currentStorage;
  Future<String?> _read(String key) =>
      _storage != null ? _storage.read(key: key) : _currentStorage!.read(key);
  Future<void> _write(String key, String value) => _storage != null
      ? _storage.write(key: key, value: value)
      : _currentStorage!.write(key, value);
  Future<void> _delete(String key) => _storage != null
      ? _storage.delete(key: key)
      : _currentStorage!.delete(key);

  Future<T> _ordered<T>(Future<T> Function() operation) =>
      _operations.synchronized(operation);

  @override
  Future<StudioMailCredentials?> load() async =>
      (await loadAccounts()).catalog?.selectedAccount?.credentials;

  @override
  Future<bool> save(StudioMailCredentials credentials) async =>
      (await saveAccount(credentials)).isSuccess;

  @override
  Future<bool> clear() async => (await _perform(() async {
    final catalog = await _readCatalog();
    final selected = catalog.selectedAccountId;
    return _forget(catalog, selected);
  })).isSuccess;

  @override
  Future<StudioMailAccountCatalogResult> loadAccounts() =>
      _perform(_readCatalog);

  @override
  Future<StudioMailAccountCatalogResult> saveAccount(
    StudioMailCredentials credentials,
  ) => _perform(() async {
    // Snapshot the validated host value before awaiting IO. Callers may supply
    // a subtype with computed getters; delayed reads cannot change the record
    // whose identity and validation were accepted for this operation.
    final snapshot = StudioMailCredentials.fromJson(credentials.toJson());
    if (snapshot == null) {
      throw const _CatalogFailure(StudioMailAccountCatalogProblem.invalid);
    }
    final catalog = await _readCatalog();
    final accounts = List<StudioMailSavedAccount>.of(catalog.accounts);
    final id = snapshot.accountId;
    final index = accounts.indexWhere((account) => account.id == id);
    final saved = StudioMailSavedAccount(id: id, credentials: snapshot);
    if (index < 0) {
      if (accounts.length >= StudioMailAccountCatalog.maxAccounts) {
        throw const _CatalogFailure(
          StudioMailAccountCatalogProblem.limitReached,
        );
      }
      accounts.add(saved);
    } else {
      accounts[index] = saved;
    }
    return _writeCatalog(
      StudioMailAccountCatalog(accounts: accounts, selectedAccountId: id),
    );
  });

  @override
  Future<StudioMailAccountCatalogResult> selectAccount(String id) =>
      _perform(() async {
        final catalog = await _readCatalog();
        if (!catalog.accounts.any((account) => account.id == id)) {
          throw const _CatalogFailure(StudioMailAccountCatalogProblem.notFound);
        }
        return _writeCatalog(
          StudioMailAccountCatalog(
            accounts: catalog.accounts,
            selectedAccountId: id,
          ),
        );
      });

  @override
  Future<StudioMailAccountCatalogResult> forgetAccount(String id) =>
      _perform(() async {
        final catalog = await _readCatalog();
        if (!catalog.accounts.any((account) => account.id == id)) {
          throw const _CatalogFailure(StudioMailAccountCatalogProblem.notFound);
        }
        return _forget(catalog, id);
      });

  Future<StudioMailAccountCatalog> _forget(
    StudioMailAccountCatalog catalog,
    String? id,
  ) async {
    final accounts = [
      for (final account in catalog.accounts)
        if (account.id != id) account,
    ];
    final selected = catalog.selectedAccountId == id
        ? accounts.firstOrNull?.id
        : catalog.selectedAccountId;
    // Retain even an empty v2 record. Deleting the catalog could let an old v1
    // record left by an interrupted migration resurrect a forgotten account.
    return _writeCatalog(
      StudioMailAccountCatalog(accounts: accounts, selectedAccountId: selected),
    );
  }

  Future<StudioMailAccountCatalogResult> _perform(
    Future<StudioMailAccountCatalog> Function() operation,
  ) => _ordered(() async {
    try {
      // Pin one explicitly selected backend for the whole account transaction.
      // A Settings change cannot redirect a pending write to another store.
      if (_storage == null) _currentStorage = await _backend();
      return StudioMailAccountCatalogResult.success(await operation());
    } on _CatalogFailure catch (failure) {
      return StudioMailAccountCatalogResult.failure(failure.problem);
    } on Object {
      return const StudioMailAccountCatalogResult.failure(
        StudioMailAccountCatalogProblem.unavailable,
      );
    } finally {
      _currentStorage = null;
    }
  });

  Future<StudioMailAccountCatalog> _readCatalog() async {
    final raw = await _read(_catalogKey);
    if (raw != null) {
      final catalog = _decodeCatalog(raw);
      // v2 is authoritative. Finish interrupted legacy cleanup before exposing
      // a successful operation, including after process restart. A failed
      // cleanup never falls back to or overwrites the obsolete record.
      await _delete(_legacyKey);
      return catalog;
    }
    final legacy = await _read(_legacyKey);
    if (legacy == null) return StudioMailAccountCatalog(accounts: const []);
    final value = _decodeObject(legacy, _maxLegacyCodeUnits);
    final credentials = StudioMailCredentials.fromJson(value);
    if (credentials == null) {
      throw const _CatalogFailure(StudioMailAccountCatalogProblem.invalid);
    }
    final id = credentials.accountId;
    final migrated = StudioMailAccountCatalog(
      accounts: [StudioMailSavedAccount(id: id, credentials: credentials)],
      selectedAccountId: id,
    );
    // Do not delete v1 until its complete replacement is durably acknowledged.
    // If either write or cleanup fails, the next operation re-reads actual
    // keychain state; it never trusts a partially updated in-memory catalog.
    await _writeCatalog(migrated);
    await _delete(_legacyKey);
    return migrated;
  }

  Future<StudioMailAccountCatalog> _writeCatalog(
    StudioMailAccountCatalog catalog,
  ) async {
    final raw = jsonEncode(<String, Object?>{
      'version': 2,
      'selectedAccountId': catalog.selectedAccountId,
      'accounts': [
        for (final account in catalog.accounts)
          <String, Object?>{
            'id': account.id,
            'credentials': account.credentials.toJson(),
          },
      ],
    });
    if (raw.length > _maxCatalogCodeUnits) {
      throw const _CatalogFailure(StudioMailAccountCatalogProblem.limitReached);
    }
    await _write(_catalogKey, raw);
    if (await _read(_catalogKey) != raw) {
      throw const _CatalogFailure(StudioMailAccountCatalogProblem.unavailable);
    }
    return catalog;
  }

  static Map<String, Object?> _decodeObject(String raw, int limit) {
    if (raw.isEmpty || raw.length > limit) {
      throw const _CatalogFailure(StudioMailAccountCatalogProblem.invalid);
    }
    try {
      final Object? value = jsonDecode(raw);
      if (value is Map<String, Object?>) return value;
    } on Object {
      throw const _CatalogFailure(StudioMailAccountCatalogProblem.invalid);
    }
    throw const _CatalogFailure(StudioMailAccountCatalogProblem.invalid);
  }

  static StudioMailAccountCatalog _decodeCatalog(String raw) {
    final value = _decodeObject(raw, _maxCatalogCodeUnits);
    final records = value['accounts'];
    final selected = value['selectedAccountId'];
    if (value['version'] is! int ||
        value['version'] != 2 ||
        records is! List<Object?> ||
        records.length > StudioMailAccountCatalog.maxAccounts ||
        selected != null && selected is! String) {
      throw const _CatalogFailure(StudioMailAccountCatalogProblem.invalid);
    }
    final accounts = <StudioMailSavedAccount>[];
    final ids = <String>{};
    for (final record in records) {
      if (record is! Map<String, Object?>) {
        throw const _CatalogFailure(StudioMailAccountCatalogProblem.invalid);
      }
      final id = record['id'];
      final encoded = record['credentials'];
      final credentials = encoded is Map<String, Object?>
          ? StudioMailCredentials.fromJson(encoded)
          : null;
      if (id is! String ||
          credentials == null ||
          id != credentials.accountId ||
          !ids.add(id)) {
        throw const _CatalogFailure(StudioMailAccountCatalogProblem.invalid);
      }
      accounts.add(StudioMailSavedAccount(id: id, credentials: credentials));
    }
    if (accounts.isEmpty ? selected != null : !ids.contains(selected)) {
      throw const _CatalogFailure(StudioMailAccountCatalogProblem.invalid);
    }
    return StudioMailAccountCatalog(
      accounts: accounts,
      selectedAccountId: selected as String?,
    );
  }
}

final class _CatalogFailure implements Exception {
  const _CatalogFailure(this.problem);

  final StudioMailAccountCatalogProblem problem;

  @override
  String toString() => 'StudioMailAccountCatalogFailure(${problem.name})';
}
