import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'credentials/secure_storage_service.dart';
import 'credentials/utils/async_lock.dart';
import 'studio_credential_storage.dart';
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

/// Host-owned credential record. Only the selected secure store receives its JSON;
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

/// Immutable snapshot of the bounded native credential catalog.
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
  }) => backend != null
      ? _PlatformStudioMailCredentialStore(selectedStorage: backend)
      : storage == null
      ? StudioMailAccountsStore()
      : _PlatformStudioMailCredentialStore(storage: storage);

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
    Future<SecureStorage> Function()? selectedStorage,
    int Function()? storageRevision,
  }) : _storage =
           selectedStorage ??
           (() async =>
               _FlutterMailStorage(storage ?? const FlutterSecureStorage())),
       _verifyWrites = true,
       _storageRevision = storageRevision;

  static const _legacyKey = 'crispoffice.mail.account.v1';
  static const _catalogKey = 'crispoffice.mail.accounts.v2';
  static const _maxLegacyCodeUnits = 256 * 1024;
  static const _maxCatalogCodeUnits = 4 * 1024 * 1024;
  static final _operations = AsyncLock();
  final Future<SecureStorage> Function() _storage;
  final bool _verifyWrites;
  final int Function()? _storageRevision;

  // Serialize even across dialog instances. A later Forget must not be undone
  // by an older slow keychain write, and a failed operation must release the queue.
  Future<T> _ordered<T>(Future<T> Function() operation) =>
      _operations.synchronized(operation);

  @override
  Future<StudioMailCredentials?> load() async =>
      (await loadAccounts()).catalog?.selectedAccount?.credentials;

  @override
  Future<bool> save(StudioMailCredentials credentials) async =>
      (await saveAccount(credentials)).isSuccess;

  @override
  Future<bool> clear() async => (await _perform((storage) async {
    final catalog = await _readCatalog(storage);
    final selected = catalog.selectedAccountId;
    return _forget(storage, catalog, selected);
  })).isSuccess;

  @override
  Future<StudioMailAccountCatalogResult> loadAccounts() =>
      _perform(_readCatalog);

  @override
  Future<StudioMailAccountCatalogResult> saveAccount(
    StudioMailCredentials credentials,
  ) {
    // Snapshot before any await or backend lookup. A subtype with computed
    // getters cannot change the accepted record while this operation queues.
    final StudioMailCredentials? snapshot;
    try {
      snapshot = StudioMailCredentials.fromJson(credentials.toJson());
    } on Object {
      return Future.value(
        const StudioMailAccountCatalogResult.failure(
          StudioMailAccountCatalogProblem.unavailable,
        ),
      );
    }
    if (snapshot == null) {
      return Future.value(
        const StudioMailAccountCatalogResult.failure(
          StudioMailAccountCatalogProblem.invalid,
        ),
      );
    }
    final StudioMailCredentials accepted = snapshot;
    return _perform((storage) async {
      final catalog = await _readCatalog(storage);
      final accounts = List<StudioMailSavedAccount>.of(catalog.accounts);
      final id = accepted.accountId;
      final index = accounts.indexWhere((account) => account.id == id);
      final saved = StudioMailSavedAccount(id: id, credentials: accepted);
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
        storage,
        StudioMailAccountCatalog(accounts: accounts, selectedAccountId: id),
      );
    });
  }

  @override
  Future<StudioMailAccountCatalogResult> selectAccount(String id) =>
      _perform((storage) async {
        final catalog = await _readCatalog(storage);
        if (!catalog.accounts.any((account) => account.id == id)) {
          throw const _CatalogFailure(StudioMailAccountCatalogProblem.notFound);
        }
        return _writeCatalog(
          storage,
          StudioMailAccountCatalog(
            accounts: catalog.accounts,
            selectedAccountId: id,
          ),
        );
      });

  @override
  Future<StudioMailAccountCatalogResult> forgetAccount(String id) =>
      _perform((storage) async {
        final catalog = await _readCatalog(storage);
        if (!catalog.accounts.any((account) => account.id == id)) {
          throw const _CatalogFailure(StudioMailAccountCatalogProblem.notFound);
        }
        return _forget(storage, catalog, id);
      });

  Future<StudioMailAccountCatalog> _forget(
    SecureStorage storage,
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
      storage,
      StudioMailAccountCatalog(accounts: accounts, selectedAccountId: selected),
    );
  }

  Future<StudioMailAccountCatalogResult> _perform(
    Future<StudioMailAccountCatalog> Function(SecureStorage) operation,
  ) {
    final acceptedRevision = _storageRevision?.call();
    return _ordered(() async {
      try {
        if (acceptedRevision != _storageRevision?.call()) {
          throw const _CatalogFailure(
            StudioMailAccountCatalogProblem.unavailable,
          );
        }
        final storage = await _storage();
        if (acceptedRevision != _storageRevision?.call()) {
          throw const _CatalogFailure(
            StudioMailAccountCatalogProblem.unavailable,
          );
        }
        // From this point every read, write and cleanup uses this backend,
        // even when another dialog changes the app-wide selection meanwhile.
        return StudioMailAccountCatalogResult.success(await operation(storage));
      } on _CatalogFailure catch (failure) {
        return StudioMailAccountCatalogResult.failure(failure.problem);
      } on Object {
        return const StudioMailAccountCatalogResult.failure(
          StudioMailAccountCatalogProblem.unavailable,
        );
      }
    });
  }

  Future<StudioMailAccountCatalog> _readCatalog(SecureStorage storage) async {
    final raw = await storage.read(_catalogKey);
    if (raw != null) {
      final catalog = _decodeCatalog(raw);
      if (_decodeObject(raw, _maxCatalogCodeUnits)['accounts'] is Map) {
        // The parallel selectable-store branch used a v2 map representation.
        // Validate and upgrade it in the same selected backend before cleanup.
        await _writeCatalog(storage, catalog);
      }
      // v2 is authoritative. Finish interrupted legacy cleanup before exposing
      // a successful operation, including after process restart. A failed
      // cleanup never falls back to or overwrites the obsolete record.
      await storage.delete(_legacyKey);
      return catalog;
    }
    final legacy = await storage.read(_legacyKey);
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
    await _writeCatalog(storage, migrated);
    await storage.delete(_legacyKey);
    return migrated;
  }

  Future<StudioMailAccountCatalog> _writeCatalog(
    SecureStorage storage,
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
    await storage.write(_catalogKey, raw);
    if (_verifyWrites && await storage.read(_catalogKey) != raw) {
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
    if (records is Map<String, Object?>) {
      return _decodeLegacyMapCatalog(value, records);
    }
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

  static StudioMailAccountCatalog _decodeLegacyMapCatalog(
    Map<String, Object?> value,
    Map<String, Object?> records,
  ) {
    final active = value['active'];
    if (value['version'] is! int ||
        value['version'] != 2 ||
        !value.containsKey('active') ||
        value.containsKey('selectedAccountId') ||
        records.length > StudioMailAccountCatalog.maxAccounts ||
        active != null && active is! String) {
      throw const _CatalogFailure(StudioMailAccountCatalogProblem.invalid);
    }
    final accounts = <StudioMailSavedAccount>[];
    final ids = <String>{};
    final migratedIds = <String, String>{};
    for (final entry in records.entries) {
      final encoded = entry.value;
      final credentials = encoded is Map<String, Object?>
          ? StudioMailCredentials.fromJson(encoded)
          : null;
      if (credentials == null) {
        throw const _CatalogFailure(StudioMailAccountCatalogProblem.invalid);
      }
      final oldId = sha256
          .convert(
            utf8.encode(
              [
                credentials.email.trim().toLowerCase(),
                credentials.imapHost.toLowerCase(),
                credentials.preset?.name ?? '',
              ].join('\n'),
            ),
          )
          .toString();
      final id = credentials.accountId;
      if (entry.key != oldId || !ids.add(id)) {
        throw const _CatalogFailure(StudioMailAccountCatalogProblem.invalid);
      }
      migratedIds[entry.key] = id;
      accounts.add(StudioMailSavedAccount(id: id, credentials: credentials));
    }
    final selected = active == null
        ? accounts.firstOrNull?.id
        : migratedIds[active];
    if (active != null && selected == null) {
      throw const _CatalogFailure(StudioMailAccountCatalogProblem.invalid);
    }
    return StudioMailAccountCatalog(
      accounts: accounts,
      selectedAccountId: selected,
    );
  }
}

final class _CatalogFailure implements Exception {
  const _CatalogFailure(this.problem);

  final StudioMailAccountCatalogProblem problem;

  @override
  String toString() => 'StudioMailAccountCatalogFailure(${problem.name})';
}

/// Selected secure storage with the same bounded catalog, stable account
/// identities, migration and operation ordering as the platform test seam.
/// A backend is captured once per serialized operation, so switching settings
/// cannot split a read/write across two credential stores.
final class StudioMailAccountsStore
    implements StudioMailCredentialStore, StudioMailAccountCatalogStore {
  StudioMailAccountsStore({
    Future<SecureStorage> Function()? storage,
    int Function()? selectionRevision,
  }) : _repository = _PlatformStudioMailCredentialStore(
         selectedStorage:
             storage ?? (() => StudioCredentialStorage.instance.storage),
         storageRevision:
             selectionRevision ??
             (storage == null
                 ? () => StudioCredentialStorage.instance.revision
                 : null),
       );

  final _PlatformStudioMailCredentialStore _repository;

  @override
  Future<StudioMailCredentials?> load() => _repository.load();

  @override
  Future<bool> save(StudioMailCredentials credentials) =>
      _repository.save(credentials);

  @override
  Future<bool> clear() => _repository.clear();

  @override
  Future<StudioMailAccountCatalogResult> loadAccounts() =>
      _repository.loadAccounts();

  @override
  Future<StudioMailAccountCatalogResult> saveAccount(
    StudioMailCredentials credentials,
  ) => _repository.saveAccount(credentials);

  /// Retains the selectable-store branch's credential-object call form while
  /// exposing canonical ID selection through [StudioMailAccountCatalogStore].
  @override
  Future<StudioMailAccountCatalogResult> selectAccount(Object account) {
    final id = switch (account) {
      String id => id,
      StudioMailCredentials credentials => credentials.accountId,
      _ => null,
    };
    if (id == null) {
      return Future.value(
        const StudioMailAccountCatalogResult.failure(
          StudioMailAccountCatalogProblem.invalid,
        ),
      );
    }
    return _repository.selectAccount(id);
  }

  @override
  Future<StudioMailAccountCatalogResult> forgetAccount(String id) =>
      _repository.forgetAccount(id);

  Future<List<StudioMailCredentials>> accounts() async {
    final result = await loadAccounts();
    if (!result.isSuccess) {
      throw StateError('Credential catalog is unavailable.');
    }
    final accounts = [
      for (final saved in result.catalog!.accounts) saved.credentials,
    ];
    accounts.sort((a, b) => a.email.compareTo(b.email));
    return accounts;
  }
}

/// Adapts the established injected Flutter keychain seam. Catalog writes are
/// verified by readback and no unrelated credential keys are touched.
final class _FlutterMailStorage extends SecureStorage {
  _FlutterMailStorage(this._storage);
  final FlutterSecureStorage _storage;

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
