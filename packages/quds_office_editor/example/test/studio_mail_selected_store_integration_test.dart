import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_studio/credentials/secure_storage_service.dart';
import 'package:quds_office_studio/studio_mail_credentials.dart';

const _catalogKey = 'crispoffice.mail.accounts.v2';
const _legacyKey = 'crispoffice.mail.account.v1';

StudioMailCredentials _account({
  String email = 'reader@example.test',
  String smtpHost = 'smtp.example.test',
  String password = 'synthetic-test-password',
}) => StudioMailCredentials(
  email: email,
  password: password,
  imapHost: 'imap.example.test',
  smtpHost: smtpHost,
  manual: true,
  startTls: false,
);

String _oldId(StudioMailCredentials credentials) => sha256.convert(
  utf8.encode([
    credentials.email.trim().toLowerCase(),
    credentials.imapHost.toLowerCase(),
    credentials.preset?.name ?? '',
  ].join('\n')),
).toString();

String _oldCatalog(List<StudioMailCredentials> accounts, {String? active}) =>
    jsonEncode({
      'version': 2,
      'active': active ?? (accounts.isEmpty ? null : _oldId(accounts.last)),
      'accounts': {
        for (final credentials in accounts)
          _oldId(credentials): credentials.toJson(),
      },
    });

final class _Storage extends InMemorySecureStorage {
  final calls = <String>[];
  bool dropWrites = false;
  Completer<void>? enteredRead;
  Completer<void>? releaseRead;
  bool _heldRead = false;

  @override
  Future<String?> read(String key) async {
    calls.add('read:$key');
    if (key == _catalogKey && !_heldRead && enteredRead != null) {
      _heldRead = true;
      enteredRead!.complete();
      await releaseRead!.future;
    }
    return super.read(key);
  }

  @override
  Future<void> write(String key, String value) async {
    calls.add('write:$key');
    if (!dropWrites) await super.write(key, value);
  }

  @override
  Future<void> delete(String key) async {
    calls.add('delete:$key');
    await super.delete(key);
  }
}

void main() {
  group('reconciled selected credential store', () {
    test('same sender and IMAP with different SMTP routes remain distinct',
        () async {
      final storage = _Storage();
      final store = StudioMailAccountsStore(storage: () async => storage);
      final first = _account();
      final second = _account(smtpHost: 'smtp.other.example.test');
      expect(await store.save(first), isTrue);
      expect(await store.save(second), isTrue);
      final catalog = await store.loadAccounts();
      expect(catalog.isSuccess, isTrue);
      expect(catalog.catalog!.accounts.map((entry) => entry.id),
          [first.accountId, second.accountId]);
      expect(catalog.catalog!.selectedAccountId, second.accountId);
      expect((jsonDecode((await storage.read(_catalogKey))!) as Map)['accounts'],
          isA<List<Object?>>());
    });

    test('both credential-object and ID selection use the persisted catalog',
        () async {
      final storage = _Storage();
      final first = _account();
      final second = _account(email: 'second@example.test');
      final store = StudioMailAccountsStore(storage: () async => storage);
      expect(await store.save(first), isTrue);
      expect(await store.save(second), isTrue);
      final selected = await store.selectAccount(first);
      expect(selected.isSuccess, isTrue);
      final reopened = StudioMailAccountsStore(storage: () async => storage);
      expect((await reopened.load())!.accountId, first.accountId);
      final StudioMailAccountCatalogStore capability = reopened;
      expect((await capability.selectAccount(second.accountId)).isSuccess, isTrue);
      expect(await reopened.clear(), isTrue);
      expect((await reopened.accounts()).single.accountId, first.accountId);
    });

    test('alternate v2 map upgrades without losing selected credentials',
        () async {
      final storage = _Storage();
      final first = _account();
      final second = _account(email: 'second@example.test');
      await storage.write(
        _catalogKey,
        _oldCatalog([first, second], active: _oldId(first)),
      );
      await storage.write(_legacyKey, jsonEncode(second.toJson()));
      final store = StudioMailAccountsStore(storage: () async => storage);
      final result = await store.loadAccounts();
      expect(result.isSuccess, isTrue);
      expect(result.catalog!.accounts.map((entry) => entry.id),
          [first.accountId, second.accountId]);
      expect(result.catalog!.selectedAccountId, first.accountId);
      final encoded = jsonDecode((await storage.read(_catalogKey))!) as Map;
      expect(encoded['selectedAccountId'], first.accountId);
      expect(encoded['accounts'], isA<List<Object?>>());
      expect(encoded.containsKey('active'), isFalse);
      expect(await storage.read(_legacyKey), isNull);
      expect((await StudioMailAccountsStore(storage: () async => storage).load())!
          .toJson(), first.toJson());
    });

    test('authoritative empty alternate map never resurrects stale v1',
        () async {
      final storage = _Storage();
      await storage.write(_catalogKey, _oldCatalog([]));
      await storage.write(_legacyKey, jsonEncode(_account().toJson()));
      final result = await StudioMailAccountsStore(storage: () async => storage)
          .loadAccounts();
      expect(result.isSuccess, isTrue);
      expect(result.catalog!.accounts, isEmpty);
      expect(result.catalog!.selectedAccountId, isNull);
      expect(await storage.read(_legacyKey), isNull);
      final encoded = jsonDecode((await storage.read(_catalogKey))!) as Map;
      expect(encoded['accounts'], isEmpty);
    });

    for (final variant in ['mixed discriminator', 'bad old ID', 'bad active']) {
      test('rejects $variant without overwriting or removing legacy bytes',
          () async {
        final storage = _Storage();
        final credentials = _account();
        final value = jsonDecode(_oldCatalog([credentials])) as Map<String, Object?>;
        if (variant == 'mixed discriminator') {
          value['selectedAccountId'] = credentials.accountId;
        } else if (variant == 'bad old ID') {
          value['accounts'] = {'forged': credentials.toJson()};
        } else {
          value['active'] = 'absent';
        }
        final encoded = jsonEncode(value);
        final legacy = jsonEncode(credentials.toJson());
        await storage.write(_catalogKey, encoded);
        await storage.write(_legacyKey, legacy);
        storage.calls.clear();
        final store = StudioMailAccountsStore(storage: () async => storage);
        final result = await store.loadAccounts();
        expect(result.problem, StudioMailAccountCatalogProblem.invalid);
        expect(await store.save(_account(email: 'new@example.test')), isFalse);
        expect(storage.calls, everyElement('read:$_catalogKey'));
        expect(await storage.read(_catalogKey), encoded);
        expect(await storage.read(_legacyKey), legacy);
      });
    }

    test('failed map upgrade readback retains source and legacy records',
        () async {
      final storage = _Storage();
      final credentials = _account();
      final map = _oldCatalog([credentials]);
      final legacy = jsonEncode(credentials.toJson());
      await storage.write(_catalogKey, map);
      await storage.write(_legacyKey, legacy);
      storage.dropWrites = true;
      storage.calls.clear();
      final result = await StudioMailAccountsStore(storage: () async => storage)
          .loadAccounts();
      expect(result.problem, StudioMailAccountCatalogProblem.unavailable);
      expect(storage.calls, isNot(contains('delete:$_legacyKey')));
      expect(await storage.read(_catalogKey), map);
      expect(await storage.read(_legacyKey), legacy);
    });

    test('a silent failed v1 migration does not remove the only credential copy',
        () async {
      final storage = _Storage();
      final legacy = jsonEncode(_account().toJson());
      await storage.write(_legacyKey, legacy);
      storage.dropWrites = true;
      final result = await StudioMailAccountsStore(storage: () async => storage)
          .loadAccounts();
      expect(result.problem, StudioMailAccountCatalogProblem.unavailable);
      expect(await storage.read(_legacyKey), legacy);
      expect(await storage.read(_catalogKey), isNull);
    });

    test('captures one backend for an entire delayed read/write transaction',
        () async {
      final first = _Storage()
        ..enteredRead = Completer<void>()
        ..releaseRead = Completer<void>();
      final second = _Storage();
      SecureStorage selected = first;
      var resolutions = 0;
      final store = StudioMailAccountsStore(storage: () async {
        resolutions++;
        return selected;
      });
      final pending = store.save(_account());
      await first.enteredRead!.future;
      selected = second;
      first.releaseRead!.complete();
      expect(await pending, isTrue);
      expect(resolutions, 1);
      expect(await first.read(_catalogKey), isNotNull);
      expect(await second.read(_catalogKey), isNull);
      final current = await store.loadAccounts();
      expect(resolutions, 2);
      expect(current.catalog!.accounts, isEmpty);
    });

    test('a queued save cannot move to a newly selected backend', () async {
      final first = _Storage()
        ..enteredRead = Completer<void>()
        ..releaseRead = Completer<void>();
      final second = _Storage();
      SecureStorage selected = first;
      var revision = 0;
      var resolutions = 0;
      final store = StudioMailAccountsStore(
        storage: () async {
          resolutions++;
          return selected;
        },
        selectionRevision: () => revision,
      );
      final accepted = _account();
      final firstSave = store.saveAccount(accepted);
      await first.enteredRead!.future;
      final queuedSave = store.saveAccount(
        _account(email: 'queued@example.test'),
      );
      selected = second;
      revision++;
      first.releaseRead!.complete();
      expect((await firstSave).isSuccess, isTrue);
      expect((await queuedSave).problem,
          StudioMailAccountCatalogProblem.unavailable);
      expect(resolutions, 1);
      expect(second.calls, isEmpty);
      final persisted = await StudioMailAccountsStore(
        storage: () async => first,
      ).loadAccounts();
      expect(persisted.catalog!.accounts.map((account) => account.id),
          [accepted.accountId]);
      expect(await second.read(_catalogKey), isNull);
    });

    test('a backend resolved after its accepted revision changed is refused',
        () async {
      final first = _Storage();
      final second = _Storage();
      final entered = Completer<void>();
      final release = Completer<SecureStorage>();
      var revision = 0;
      final store = StudioMailAccountsStore(
        storage: () {
          entered.complete();
          return release.future;
        },
        selectionRevision: () => revision,
      );
      final pending = store.saveAccount(_account());
      await entered.future;
      revision++;
      release.complete(second);
      expect((await pending).problem,
          StudioMailAccountCatalogProblem.unavailable);
      expect(first.calls, isEmpty);
      expect(second.calls, isEmpty);
    });

    test('a queued Forget cannot erase the matching account in another store',
        () async {
      final first = _Storage();
      final second = _Storage();
      final credentials = _account();
      for (final storage in [first, second]) {
        final result = await StudioMailAccountsStore(
          storage: () async => storage,
        ).saveAccount(credentials);
        expect(result.isSuccess, isTrue);
      }
      final firstBytes = await first.read(_catalogKey);
      final secondBytes = await second.read(_catalogKey);
      first
        ..enteredRead = Completer<void>()
        ..releaseRead = Completer<void>();
      SecureStorage selected = first;
      var revision = 0;
      var resolutions = 0;
      final store = StudioMailAccountsStore(
        storage: () async {
          resolutions++;
          return selected;
        },
        selectionRevision: () => revision,
      );
      final acceptedLoad = store.loadAccounts();
      await first.enteredRead!.future;
      final queuedForget = store.forgetAccount(credentials.accountId);
      selected = second;
      revision++;
      first.releaseRead!.complete();
      expect((await acceptedLoad).isSuccess, isTrue);
      expect((await queuedForget).problem,
          StudioMailAccountCatalogProblem.unavailable);
      expect(resolutions, 1);
      expect(await first.read(_catalogKey), firstBytes);
      expect(await second.read(_catalogKey), secondBytes);
    });

    test('the selected backend retains the canonical twenty-account bound',
        () async {
      final storage = _Storage();
      final store = StudioMailAccountsStore(storage: () async => storage);
      for (var index = 0; index < StudioMailAccountCatalog.maxAccounts; index++) {
        expect(await store.save(_account(email: 'user$index@example.test')), isTrue);
      }
      final previous = await storage.read(_catalogKey);
      final result = await store.saveAccount(_account(email: 'overflow@example.test'));
      expect(result.problem, StudioMailAccountCatalogProblem.limitReached);
      expect(await storage.read(_catalogKey), previous);
      expect((await store.accounts()).length, StudioMailAccountCatalog.maxAccounts);
    });
  });
}
