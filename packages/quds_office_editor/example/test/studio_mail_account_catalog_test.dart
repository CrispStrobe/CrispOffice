import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_studio/studio_mail_credentials.dart';
import 'package:quds_office_studio/studio_mail_presets.dart';

const _legacyKey = 'crispoffice.mail.account.v1';
const _catalogKey = 'crispoffice.mail.accounts.v2';

StudioMailCredentials _credentials({
  String email = 'reader@example.test',
  String password = 'fixture-password',
  String imapHost = 'imap.example.test',
  String smtpHost = 'smtp.example.test',
  bool manual = true,
  bool startTls = false,
  StudioMailImapPreset? preset,
  String primaryLogin = '',
  bool icloudFullAddressLogin = false,
}) => StudioMailCredentials(
  email: email,
  password: password,
  imapHost: imapHost,
  smtpHost: smtpHost,
  manual: manual,
  startTls: startTls,
  preset: preset,
  primaryLogin: primaryLogin,
  icloudFullAddressLogin: icloudFullAddressLogin,
);

final class _Storage extends Fake implements FlutterSecureStorage {
  final records = <String, String>{};
  final calls = <String>[];
  final unreadableKeys = <String>{};
  bool writeFails = false;
  bool deleteFails = false;
  Future<void> Function()? beforeRead;
  Future<void> Function()? beforeWrite;

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    calls.add('read:$key');
    await beforeRead?.call();
    if (unreadableKeys.contains(key)) {
      throw StateError('private-keychain-read-detail');
    }
    return records[key];
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    calls.add('write:$key');
    await beforeWrite?.call();
    if (writeFails) throw StateError('private-keychain-write-detail');
    records[key] = value!;
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    calls.add('delete:$key');
    if (deleteFails) throw StateError('private-keychain-delete-detail');
    records.remove(key);
  }
}

final class _MutableCredentials extends StudioMailCredentials {
  _MutableCredentials()
    : super(
        email: 'reader@example.test',
        password: 'fixture-password',
        imapHost: 'imap.example.test',
        smtpHost: 'smtp.example.test',
        manual: true,
        startTls: false,
      );

  String currentEmail = 'reader@example.test';

  @override
  String get email => currentEmail;
}

StudioMailAccountCatalogStore _store(_Storage storage) =>
    StudioMailCredentialStore(storage: storage)
        as StudioMailAccountCatalogStore;

StudioMailAccountCatalog _success(StudioMailAccountCatalogResult result) {
  expect(result.isSuccess, isTrue, reason: result.toString());
  expect(result.problem, isNull);
  return result.catalog!;
}

void _failure(
  StudioMailAccountCatalogResult result,
  StudioMailAccountCatalogProblem problem,
) {
  expect(result.isSuccess, isFalse);
  expect(result.catalog, isNull);
  expect(result.problem, problem);
  expect(result.toString(), isNot(contains('private-keychain')));
}

Map<String, Object?> _encoded(
  List<StudioMailCredentials> accounts, {
  String? selected,
}) => <String, Object?>{
  'version': 2,
  'selectedAccountId': selected ?? accounts.firstOrNull?.accountId,
  'accounts': [
    for (final credentials in accounts)
      <String, Object?>{
        'id': credentials.accountId,
        'credentials': credentials.toJson(),
      },
  ],
};

void main() {
  group('remembered account identity', () {
    // Frozen pre-refactor SHA-256 values of the exact v2 canonical identity
    // encoding. Loading these literal IDs also guards existing keychain data.
    for (final vector in [
      (
        name: 'manual STARTTLS',
        credentials: _credentials(
          email: 'CaseSensitive@Example.TEST',
          imapHost: 'IMAP.Example.TEST',
          smtpHost: 'SMTP.Example.TEST',
          startTls: true,
          primaryLogin: 'ignored@example.test',
        ),
        id: '7d2517cddbed9ca0f96383320b510ac0a5443396ac5da7aabe23f5eafb3047c3',
      ),
      (
        name: 'iCloud local-part login',
        credentials: _credentials(
          email: 'Alias@Example.TEST',
          preset: StudioMailImapPreset.icloud,
          primaryLogin: 'Primary@iCloud.COM',
        ),
        id: 'f23c81845bae3c057aa300361619f6a89f0996dfe7fb2fdced5e39a9bea4bf44',
      ),
      (
        name: 'iCloud full-address login',
        credentials: _credentials(
          email: 'Alias@Example.TEST',
          preset: StudioMailImapPreset.icloud,
          primaryLogin: 'Primary@iCloud.COM',
          icloudFullAddressLogin: true,
        ),
        id: '5ebf9f7fddb945727690d7e3da0e1d3d29b345b044644a72c72defe12b5aa858',
      ),
    ]) {
      test(
        '${vector.name} keeps its existing v2 identity and catalog',
        () async {
          expect(vector.credentials.accountId, vector.id);
          final storage = _Storage()
            ..records[_catalogKey] = jsonEncode(<String, Object?>{
              'version': 2,
              'selectedAccountId': vector.id,
              'accounts': [
                <String, Object?>{
                  'id': vector.id,
                  'credentials': vector.credentials.toJson(),
                },
              ],
            });
          final before = storage.records[_catalogKey];
          final loaded = _success(await _store(storage).loadAccounts());
          expect(loaded.selectedAccountId, vector.id);
          expect(
            loaded.selectedAccount!.credentials.toJson(),
            vector.credentials.toJson(),
          );
          expect(storage.records[_catalogKey], before);
        },
      );
    }

    test(
      'effective manual descriptors expose exact routes without secrets',
      () {
        final credentials = _credentials(
          email: 'CaseSensitive@Example.TEST',
          imapHost: 'IMAP.Example.TEST',
          smtpHost: 'SMTP.Example.TEST',
          startTls: true,
          primaryLogin: 'ignored@example.test',
        );
        expect(credentials.connectionIdentity, (
          sender: 'CaseSensitive@Example.TEST',
          imapHost: 'imap.example.test',
          imapPort: 143,
          imapStartTls: true,
          imapLogin: 'CaseSensitive@Example.TEST',
          smtpHost: 'smtp.example.test',
          smtpPort: 587,
          smtpStartTls: true,
          smtpLogin: 'CaseSensitive@Example.TEST',
        ));
        expect(
          credentials.connectionIdentity.toString(),
          isNot(contains(credentials.password)),
        );
      },
    );

    test(
      'iCloud descriptor distinguishes incoming and outgoing identities',
      () {
        final credentials = _credentials(
          email: 'Alias@Example.TEST',
          preset: StudioMailImapPreset.icloud,
          primaryLogin: 'Primary@iCloud.COM',
        );
        expect(credentials.connectionIdentity, (
          sender: 'Alias@Example.TEST',
          imapHost: 'imap.mail.me.com',
          imapPort: 993,
          imapStartTls: false,
          imapLogin: 'Primary',
          smtpHost: 'smtp.mail.me.com',
          smtpPort: 587,
          smtpStartTls: true,
          smtpLogin: 'Primary@iCloud.COM',
        ));
        final rotated = StudioMailCredentials.fromJson({
          ...credentials.toJson(),
          'password': 'rotated-private-secret',
        })!;
        expect(rotated.connectionIdentity, credentials.connectionIdentity);
        expect(rotated.accountId, credentials.accountId);
        expect(
          rotated.connectionIdentity.toString(),
          isNot(contains(rotated.password)),
        );
      },
    );

    test('password rotation retains identity without disclosing input', () {
      final original = _credentials();
      final rotated = _credentials(password: 'different-private-password');
      expect(original.accountId, rotated.accountId);
      expect(original.accountId, matches(RegExp(r'^[a-f0-9]{64}$')));
      expect(original.accountId, isNot(contains('reader')));
      expect(original.accountId, isNot(contains('password')));
    });

    test('hostname case does not duplicate an account', () {
      expect(
        _credentials().accountId,
        _credentials(
          imapHost: 'IMAP.EXAMPLE.TEST',
          smtpHost: 'SMTP.EXAMPLE.TEST',
        ).accountId,
      );
    });

    test('sender local part and login local part remain case-sensitive', () {
      expect(
        _credentials().accountId,
        isNot(_credentials(email: 'Reader@example.test').accountId),
      );
      expect(
        _credentials(
          preset: StudioMailImapPreset.fastmail,
          primaryLogin: 'Login@example.test',
        ).accountId,
        isNot(
          _credentials(
            preset: StudioMailImapPreset.fastmail,
            primaryLogin: 'login@example.test',
          ).accountId,
        ),
      );
    });

    test('complete login and sender case retain existing draft identities', () {
      expect(
        _credentials().accountId,
        isNot(_credentials(email: 'reader@EXAMPLE.TEST').accountId),
      );
      expect(
        _credentials(
          preset: StudioMailImapPreset.fastmail,
          primaryLogin: 'login@example.test',
        ).accountId,
        isNot(
          _credentials(
            preset: StudioMailImapPreset.fastmail,
            primaryLogin: 'login@EXAMPLE.TEST',
          ).accountId,
        ),
      );
    });

    test('different endpoints, senders and TLS routes remain isolated', () {
      final ids = {
        _credentials().accountId,
        _credentials(imapHost: 'other.example.test').accountId,
        _credentials(smtpHost: 'other.example.test').accountId,
        _credentials(email: 'alias@example.test').accountId,
        _credentials(startTls: true).accountId,
      };
      expect(ids, hasLength(5));
    });

    test('effective preset settings ignore unused form fields', () {
      final first = _credentials(preset: StudioMailImapPreset.fastmail);
      final sameConnection = _credentials(
        preset: StudioMailImapPreset.fastmail,
        imapHost: 'unused.example.test',
        smtpHost: 'unused.example.test',
        startTls: true,
        manual: false,
        primaryLogin: 'reader@example.test',
      );
      expect(first.accountId, sameConnection.accountId);
    });

    test('iCloud local and full-address authentication remain distinct', () {
      final shortLogin = _credentials(preset: StudioMailImapPreset.icloud);
      final fullLogin = _credentials(
        preset: StudioMailImapPreset.icloud,
        icloudFullAddressLogin: true,
      );
      expect(shortLogin.accountId, isNot(fullLogin.accountId));
    });

    test('manual and discovered configuration for the same route agree', () {
      expect(_credentials().accountId, _credentials(manual: false).accountId);
    });
  });

  group('catalog snapshots and normal operations', () {
    test('empty keychain is distinct from a failed read', () async {
      final storage = _Storage();
      final catalog = _success(await _store(storage).loadAccounts());
      expect(catalog.accounts, isEmpty);
      expect(catalog.selectedAccount, isNull);
      expect(storage.records, isEmpty);
      storage.unreadableKeys.add(_catalogKey);
      _failure(
        await _store(storage).loadAccounts(),
        StudioMailAccountCatalogProblem.unavailable,
      );
    });

    test('snapshot copies the list and redacts diagnostic representations', () {
      final credentials = _credentials();
      final saved = StudioMailSavedAccount(
        id: credentials.accountId,
        credentials: credentials,
      );
      final input = [saved];
      final catalog = StudioMailAccountCatalog(
        accounts: input,
        selectedAccountId: saved.id,
      );
      input.clear();
      expect(catalog.accounts, [saved]);
      expect(() => catalog.accounts.clear(), throwsUnsupportedError);
      expect(catalog.selectedAccount, same(saved));
      for (final value in [credentials, saved, catalog]) {
        expect(value.toString(), isNot(contains(credentials.email)));
        expect(value.toString(), isNot(contains(credentials.password)));
      }
    });

    test(
      'saving, selecting and reopening retain independent accounts',
      () async {
        final storage = _Storage();
        final store = _store(storage);
        final first = _credentials();
        final second = _credentials(email: 'second@example.test');
        _success(await store.saveAccount(first));
        final both = _success(await store.saveAccount(second));
        expect(both.accounts.map((item) => item.id), [
          first.accountId,
          second.accountId,
        ]);
        expect(both.selectedAccountId, second.accountId);
        _success(await store.selectAccount(first.accountId));
        final reopened = _success(await _store(storage).loadAccounts());
        expect(reopened.accounts, hasLength(2));
        expect(reopened.selectedAccount!.credentials.toJson(), first.toJson());
      },
    );

    test(
      'password rotation replaces one record and preserves others',
      () async {
        final storage = _Storage();
        final store = _store(storage);
        final first = _credentials();
        final second = _credentials(email: 'second@example.test');
        _success(await store.saveAccount(first));
        _success(await store.saveAccount(second));
        final rotated = _credentials(password: 'rotated-fixture-password');
        final catalog = _success(await store.saveAccount(rotated));
        expect(catalog.accounts, hasLength(2));
        expect(catalog.accounts.last.credentials.toJson(), second.toJson());
        expect(catalog.selectedAccount!.credentials.password, rotated.password);
        expect(catalog.selectedAccountId, first.accountId);
      },
    );

    test(
      'validated credentials are frozen before a delayed keychain read',
      () async {
        final started = Completer<void>();
        final release = Completer<void>();
        final storage = _Storage()
          ..beforeRead = () {
            if (!started.isCompleted) started.complete();
            return release.future;
          };
        final mutable = _MutableCredentials();
        final saving = _store(storage).saveAccount(mutable);
        await started.future;
        mutable.currentEmail = 'changed@example.test';
        release.complete();
        final saved = _success(await saving).selectedAccount!;
        expect(saved.credentials.email, 'reader@example.test');
        expect(saved.id, _credentials().accountId);
        expect(saved.id, isNot(mutable.accountId));
        expect(
          _success(
            await _store(storage).loadAccounts(),
          ).selectedAccount!.credentials.email,
          'reader@example.test',
        );
      },
    );

    test(
      'forgetting a nonselected account preserves selection and neighbors',
      () async {
        final storage = _Storage();
        final store = _store(storage);
        final first = _credentials();
        final second = _credentials(email: 'second@example.test');
        _success(await store.saveAccount(first));
        _success(await store.saveAccount(second));
        final catalog = _success(await store.forgetAccount(first.accountId));
        expect(catalog.accounts.single.credentials.toJson(), second.toJson());
        expect(catalog.selectedAccountId, second.accountId);
      },
    );

    test(
      'forgetting the selected account chooses a retained account',
      () async {
        final storage = _Storage();
        final store = _store(storage);
        final first = _credentials();
        final second = _credentials(email: 'second@example.test');
        _success(await store.saveAccount(first));
        _success(await store.saveAccount(second));
        final catalog = _success(await store.forgetAccount(second.accountId));
        expect(catalog.accounts.single.credentials.toJson(), first.toJson());
        expect(catalog.selectedAccountId, first.accountId);
      },
    );

    test(
      'forgetting the last account persists an empty authoritative catalog',
      () async {
        final storage = _Storage();
        final credentials = _credentials();
        final store = _store(storage);
        _success(await store.saveAccount(credentials));
        final catalog = _success(
          await store.forgetAccount(credentials.accountId),
        );
        expect(catalog.accounts, isEmpty);
        expect(catalog.selectedAccountId, isNull);
        expect(storage.records.keys, [_catalogKey]);
        expect(
          _success(await _store(storage).loadAccounts()).accounts,
          isEmpty,
        );
      },
    );

    test(
      'legacy facade operates on the selected account without clearing others',
      () async {
        final storage = _Storage();
        final legacy = StudioMailCredentialStore(storage: storage);
        final first = _credentials();
        final second = _credentials(email: 'second@example.test');
        expect(await legacy.save(first), isTrue);
        expect(await legacy.save(second), isTrue);
        expect((await legacy.load())!.toJson(), second.toJson());
        expect(await legacy.clear(), isTrue);
        expect((await legacy.load())!.toJson(), first.toJson());
        expect(await legacy.clear(), isTrue);
        expect(await legacy.load(), isNull);
        expect(await legacy.clear(), isTrue);
        expect(storage.records.keys, [_catalogKey]);
      },
    );

    test('unknown selections and removals never mutate the catalog', () async {
      final storage = _Storage();
      final store = _store(storage);
      _success(await store.saveAccount(_credentials()));
      final before = Map<String, String>.of(storage.records);
      _failure(
        await store.selectAccount('unknown'),
        StudioMailAccountCatalogProblem.notFound,
      );
      _failure(
        await store.forgetAccount('unknown'),
        StudioMailAccountCatalogProblem.notFound,
      );
      expect(storage.records, before);
    });

    test(
      'twenty accounts are admitted, while rotation works at the limit',
      () async {
        final storage = _Storage();
        final store = _store(storage);
        for (
          var index = 0;
          index < StudioMailAccountCatalog.maxAccounts;
          index++
        ) {
          _success(
            await store.saveAccount(
              _credentials(email: 'user$index@example.test'),
            ),
          );
        }
        final before = storage.records[_catalogKey];
        _failure(
          await store.saveAccount(_credentials(email: 'overflow@example.test')),
          StudioMailAccountCatalogProblem.limitReached,
        );
        expect(storage.records[_catalogKey], before);
        final rotated = _success(
          await store.saveAccount(
            _credentials(email: 'user0@example.test', password: 'rotated'),
          ),
        );
        expect(
          rotated.accounts,
          hasLength(StudioMailAccountCatalog.maxAccounts),
        );
        expect(rotated.selectedAccount!.credentials.password, 'rotated');
      },
    );
  });

  group('migration and recovery', () {
    test('v1 is copied before deletion and reopens from v2', () async {
      final credentials = _credentials();
      final storage = _Storage()
        ..records[_legacyKey] = jsonEncode(credentials.toJson());
      final migrated = _success(await _store(storage).loadAccounts());
      expect(
        migrated.selectedAccount!.credentials.toJson(),
        credentials.toJson(),
      );
      expect(storage.calls, [
        'read:$_catalogKey',
        'read:$_legacyKey',
        'write:$_catalogKey',
        'read:$_catalogKey',
        'delete:$_legacyKey',
      ]);
      expect(storage.records.keys, [_catalogKey]);
      expect(
        _success(await _store(storage).loadAccounts()).selectedAccountId,
        credentials.accountId,
      );
    });

    test(
      'failed migration write leaves the entire legacy record untouched',
      () async {
        final legacy = jsonEncode(_credentials().toJson());
        final storage = _Storage()
          ..records[_legacyKey] = legacy
          ..writeFails = true;
        _failure(
          await _store(storage).loadAccounts(),
          StudioMailAccountCatalogProblem.unavailable,
        );
        expect(storage.records, {_legacyKey: legacy});
        expect(storage.calls, isNot(contains('delete:$_legacyKey')));
        storage.writeFails = false;
        expect(
          _success(await _store(storage).loadAccounts()).accounts,
          hasLength(1),
        );
      },
    );

    test(
      'interrupted cleanup uses the durable catalog and retries deletion',
      () async {
        final credentials = _credentials();
        final storage = _Storage()
          ..records[_legacyKey] = jsonEncode(credentials.toJson())
          ..deleteFails = true;
        _failure(
          await _store(storage).loadAccounts(),
          StudioMailAccountCatalogProblem.unavailable,
        );
        expect(storage.records.keys, containsAll([_catalogKey, _legacyKey]));
        final durable = storage.records[_catalogKey];
        storage
          ..deleteFails = false
          ..writeFails = true;
        final reopened = _success(await _store(storage).loadAccounts());
        expect(
          reopened.selectedAccount!.credentials.toJson(),
          credentials.toJson(),
        );
        expect(storage.records, {_catalogKey: durable});
      },
    );

    test(
      'empty v2 cannot resurrect a stale legacy account after restart',
      () async {
        final credentials = _credentials();
        final storage = _Storage()
          ..records[_legacyKey] = jsonEncode(credentials.toJson());
        final store = _store(storage);
        _success(await store.loadAccounts());
        _success(await store.forgetAccount(credentials.accountId));
        storage.records[_legacyKey] = jsonEncode(credentials.toJson());
        final reopened = _success(await _store(storage).loadAccounts());
        expect(reopened.accounts, isEmpty);
        expect(storage.records.keys, [_catalogKey]);
      },
    );

    test(
      'adding during migration retains the old account and selects the new one',
      () async {
        final old = _credentials();
        final incoming = _credentials(email: 'new@example.test');
        final storage = _Storage()
          ..records[_legacyKey] = jsonEncode(old.toJson());
        final catalog = _success(await _store(storage).saveAccount(incoming));
        expect(catalog.accounts.map((item) => item.credentials.email), [
          old.email,
          incoming.email,
        ]);
        expect(catalog.selectedAccountId, incoming.accountId);
      },
    );
  });

  group('untrusted or unavailable storage', () {
    final valid = _credentials();
    final invalidCatalogs = <String, Object?>{
      'invalid JSON': '{',
      'empty value': '',
      'wrong root': jsonEncode([]),
      'future schema': jsonEncode({
        ..._encoded([valid]),
        'version': 3,
      }),
      'noninteger schema': jsonEncode({
        ..._encoded([valid]),
        'version': 2.0,
      }),
      'missing accounts': jsonEncode({'version': 2}),
      'wrong account list type': jsonEncode({
        ..._encoded([valid]),
        'accounts': <String, Object?>{},
      }),
      'invalid selected identity': jsonEncode({
        ..._encoded([valid]),
        'selectedAccountId': 'absent',
      }),
      'missing selection': jsonEncode({
        ..._encoded([valid]),
        'selectedAccountId': null,
      }),
      'selection in empty catalog': jsonEncode({
        ..._encoded([]),
        'selectedAccountId': valid.accountId,
      }),
      'duplicate account': jsonEncode(_encoded([valid, valid])),
      'identity substitution': jsonEncode({
        ..._encoded([valid]),
        'accounts': [
          {'id': 'forged', 'credentials': valid.toJson()},
        ],
      }),
      'malformed credentials': jsonEncode({
        ..._encoded([valid]),
        'accounts': [
          {
            'id': valid.accountId,
            'credentials': {...valid.toJson(), 'password': 42},
          },
        ],
      }),
      'too many accounts': jsonEncode(
        _encoded([
          for (var index = 0; index < 21; index++)
            _credentials(email: 'user$index@example.test'),
        ]),
      ),
      'oversized catalog': 'x' * (4 * 1024 * 1024 + 1),
    };
    for (final entry in invalidCatalogs.entries) {
      test('${entry.key} never falls back to v1 or overwrites data', () async {
        final storage = _Storage()
          ..records[_catalogKey] = entry.value! as String
          ..records[_legacyKey] = jsonEncode(valid.toJson());
        final before = Map<String, String>.of(storage.records);
        final store = _store(storage);
        for (final result in [
          await store.loadAccounts(),
          await store.saveAccount(_credentials(email: 'new@example.test')),
          await store.selectAccount(valid.accountId),
          await store.forgetAccount(valid.accountId),
        ]) {
          _failure(result, StudioMailAccountCatalogProblem.invalid);
        }
        expect(storage.records, before);
        expect(storage.calls, everyElement('read:$_catalogKey'));
      });
    }

    test(
      'unreadable catalog blocks saves and legacy facade clearing',
      () async {
        final storage = _Storage()
          ..records[_catalogKey] = jsonEncode(_encoded([valid]))
          ..unreadableKeys.add(_catalogKey);
        final before = Map<String, String>.of(storage.records);
        _failure(
          await _store(
            storage,
          ).saveAccount(_credentials(email: 'new@example.test')),
          StudioMailAccountCatalogProblem.unavailable,
        );
        expect(
          await StudioMailCredentialStore(storage: storage).clear(),
          isFalse,
        );
        expect(storage.records, before);
      },
    );

    test(
      'malformed or unreadable v1 is not overwritten by a new account',
      () async {
        final storage = _Storage()..records[_legacyKey] = '{private-invalid';
        _failure(
          await _store(storage).saveAccount(_credentials()),
          StudioMailAccountCatalogProblem.invalid,
        );
        expect(storage.records, {_legacyKey: '{private-invalid'});
        storage.unreadableKeys.add(_legacyKey);
        _failure(
          await _store(storage).saveAccount(_credentials()),
          StudioMailAccountCatalogProblem.unavailable,
        );
        expect(storage.records.keys, [_legacyKey]);
      },
    );

    test(
      'failed selection, save and forget leave the durable snapshot intact',
      () async {
        final first = _credentials();
        final second = _credentials(email: 'second@example.test');
        final storage = _Storage()
          ..records[_catalogKey] = jsonEncode(_encoded([first, second]))
          ..writeFails = true;
        final before = Map<String, String>.of(storage.records);
        final store = _store(storage);
        for (final result in [
          await store.selectAccount(second.accountId),
          await store.saveAccount(_credentials(password: 'new-password')),
          await store.forgetAccount(first.accountId),
        ]) {
          _failure(result, StudioMailAccountCatalogProblem.unavailable);
        }
        expect(storage.records, before);
        storage.writeFails = false;
        expect(
          _success(
            await store.forgetAccount(first.accountId),
          ).accounts.single.id,
          second.accountId,
        );
      },
    );

    test('invalid new credentials cause no keychain reads or writes', () async {
      final storage = _Storage();
      _failure(
        await _store(storage).saveAccount(_credentials(password: 'bad\r\n')),
        StudioMailAccountCatalogProblem.invalid,
      );
      expect(storage.calls, isEmpty);
    });
  });

  group('serialized read-modify-write', () {
    test('concurrent saves across instances preserve both records', () async {
      final started = Completer<void>();
      final release = Completer<void>();
      final storage = _Storage()
        ..beforeWrite = () {
          if (!started.isCompleted) started.complete();
          return release.future;
        };
      final first = _credentials();
      final second = _credentials(email: 'second@example.test');
      final firstSave = _store(storage).saveAccount(first);
      await started.future;
      final secondSave = _store(storage).saveAccount(second);
      await Future<void>.delayed(Duration.zero);
      expect(storage.calls, [
        'read:$_catalogKey',
        'read:$_legacyKey',
        'write:$_catalogKey',
      ]);
      release.complete();
      _success(await firstSave);
      _success(await secondSave);
      final catalog = _success(await _store(storage).loadAccounts());
      expect(catalog.accounts.map((item) => item.id), [
        first.accountId,
        second.accountId,
      ]);
      expect(catalog.selectedAccountId, second.accountId);
    });

    test(
      'later forget waits for an older save and preserves another account',
      () async {
        final first = _credentials();
        final second = _credentials(email: 'second@example.test');
        final storage = _Storage();
        _success(await _store(storage).saveAccount(second));
        final started = Completer<void>();
        final release = Completer<void>();
        storage.beforeWrite = () {
          if (!started.isCompleted) started.complete();
          return release.future;
        };
        final saving = _store(storage).saveAccount(first);
        await started.future;
        final forgetting = _store(storage).forgetAccount(first.accountId);
        await Future<void>.delayed(Duration.zero);
        release.complete();
        _success(await saving);
        final finalCatalog = _success(await forgetting);
        expect(
          finalCatalog.accounts.single.credentials.toJson(),
          second.toJson(),
        );
        expect(finalCatalog.selectedAccountId, second.accountId);
        expect(
          _success(await _store(storage).loadAccounts()).accounts.single.id,
          second.accountId,
        );
      },
    );

    test('failed queued mutation releases later operations', () async {
      final storage = _Storage();
      final store = _store(storage);
      final account = _credentials();
      _success(await store.saveAccount(account));
      final invalid = store.selectAccount('missing');
      final valid = _store(
        storage,
      ).saveAccount(_credentials(email: 'second@example.test'));
      _failure(await invalid, StudioMailAccountCatalogProblem.notFound);
      expect(_success(await valid).accounts, hasLength(2));
    });
  });
}
