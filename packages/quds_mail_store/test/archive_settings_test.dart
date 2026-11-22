@TestOn('vm')
library;

import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:test/test.dart';

final _profile = MailProfileId('archive-settings', hostId: 'test-office');
final _account = MailAccountId('account', profile: _profile);
final _other = MailAccountId('other', profile: _profile);

T _value<T>(MailResult<T> result) {
  expect(result, isA<MailSuccess<T>>());
  return (result as MailSuccess<T>).value;
}

void _problem<T>(MailResult<T> result, MailProblemCode code) {
  expect(result, isA<MailFailure<T>>());
  expect((result as MailFailure<T>).problem.code, code);
}

Future<void> _register(
  SqliteMailRepository store,
  MailAccountId account,
) async => _value(
  await store.createAccount(
    MailStoreAccount(
      id: account,
      provider: MailProviderKind.imap,
      displayName: 'Synthetic account',
      credentialReference: 'opaque-credential',
    ),
  ),
);

MailArchiveDestinationSettings _settings({
  MailAccountId? account,
  int revision = 0,
  String folder = ' Archive/أرشيف/Ärger 📨 ',
}) {
  final owner = account ?? _account;
  return MailArchiveDestinationSettings(
    account: owner,
    revision: revision,
    destination: MailMailboxId(folder, account: owner),
  );
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late sqlite.Database database;
  late SqliteMailRepository store;
  var failCommit = false;

  Future<SqliteMailRepository> open({
    MailStoreLimits limits = const MailStoreLimits(),
    QueryInterceptor? interceptor,
  }) async {
    QueryExecutor executor = NativeDatabase.opened(
      database,
      closeUnderlyingOnClose: false,
    );
    if (interceptor != null) executor = executor.interceptWith(interceptor);
    return _value(
      await SqliteMailRepository.open(
        executor: executor,
        profile: _profile,
        limits: limits,
        faultInjector: (point) {
          if (failCommit && point == MailStoreCheckpoint.beforeCommit) {
            throw const MailStoreStorageException(
              MailProblemCode.storageFailure,
            );
          }
        },
      ),
    );
  }

  setUp(() async {
    failCommit = false;
    database = sqlite.sqlite3.openInMemory();
    store = await open();
    await _register(store, _account);
  });
  tearDown(() async {
    await store.close();
    database.close();
  });

  test(
    'optional port returns defaults only for an existing owned account',
    () async {
      final MailArchiveSettingsRepository port = store;
      final defaults = _value(await port.loadArchiveSettings(_account));
      expect(defaults.revision, 0);
      expect(defaults.destination, isNull);
      _problem(
        await port.loadArchiveSettings(_other),
        MailProblemCode.unavailable,
      );
      final foreign = MailAccountId(
        _account.value,
        profile: MailProfileId(_profile.value, hostId: 'other-host'),
      );
      _problem(
        await port.loadArchiveSettings(foreign),
        MailProblemCode.permissionDenied,
      );
      _problem(
        await port.saveArchiveSettings(
          _settings(account: foreign),
          expectedRevision: 0,
        ),
        MailProblemCode.permissionDenied,
      );
      _problem(
        await port.saveArchiveSettings(
          MailArchiveDestinationSettings(
            account: _account,
            destination: MailMailboxId('Archive', account: _other),
          ),
          expectedRevision: 0,
        ),
        MailProblemCode.invalidInput,
      );
    },
  );

  test(
    'round-trips exact paths independently without a cached mailbox',
    () async {
      await _register(store, _other);
      final first = _value(
        await store.saveArchiveSettings(_settings(), expectedRevision: 0),
      );
      final second = _value(
        await store.saveArchiveSettings(
          _settings(account: _other, folder: 'archive'),
          expectedRevision: 0,
        ),
      );
      expect(first.revision, 1);
      expect(second.revision, 1);
      expect(
        _value(await store.loadArchiveSettings(_account)).destination,
        first.destination,
      );
      expect(
        _value(await store.loadArchiveSettings(_other)).destination,
        second.destination,
      );
      expect(database.select('SELECT * FROM mailboxes'), isEmpty);
    },
  );

  test(
    'reset retains revision and rejects stale first-save and ABA writes',
    () async {
      final saved = _value(
        await store.saveArchiveSettings(_settings(), expectedRevision: 0),
      );
      final reset = _value(
        await store.saveArchiveSettings(
          saved.copyWith(clearDestination: true),
          expectedRevision: 1,
        ),
      );
      expect(reset.revision, 2);
      expect(reset.destination, isNull);
      expect(
        database
            .select('SELECT revision,destination FROM account_archive_settings')
            .single,
        containsPair('revision', 2),
      );
      _problem(
        await store.saveArchiveSettings(_settings(), expectedRevision: 0),
        MailProblemCode.conflict,
      );
      _problem(
        await store.saveArchiveSettings(saved, expectedRevision: 1),
        MailProblemCode.conflict,
      );
      _problem(
        await store.saveArchiveSettings(saved, expectedRevision: 2),
        MailProblemCode.invalidInput,
      );
      final restored = _value(await store.loadArchiveSettings(_account));
      expect(restored.revision, 2);
      expect(restored.destination, isNull);
    },
  );

  test(
    'two concurrent edits cannot consume the same displayed revision',
    () async {
      final results = await Future.wait([
        store.saveArchiveSettings(
          _settings(folder: 'First'),
          expectedRevision: 0,
        ),
        store.saveArchiveSettings(
          _settings(folder: 'Second'),
          expectedRevision: 0,
        ),
      ]);
      expect(
        results.whereType<MailSuccess<MailArchiveDestinationSettings>>(),
        hasLength(1),
      );
      expect(
        results
            .whereType<MailFailure<MailArchiveDestinationSettings>>()
            .single
            .problem
            .code,
        MailProblemCode.conflict,
      );
      expect(_value(await store.loadArchiveSettings(_account)).revision, 1);
    },
  );

  test(
    'failed initial saves and resets roll back the entire preference',
    () async {
      failCommit = true;
      _problem(
        await store.saveArchiveSettings(_settings(), expectedRevision: 0),
        MailProblemCode.storageFailure,
      );
      expect(_value(await store.loadArchiveSettings(_account)).revision, 0);
      failCommit = false;
      final saved = _value(
        await store.saveArchiveSettings(_settings(), expectedRevision: 0),
      );
      failCommit = true;
      _problem(
        await store.saveArchiveSettings(
          saved.copyWith(clearDestination: true),
          expectedRevision: 1,
        ),
        MailProblemCode.storageFailure,
      );
      final restored = _value(await store.loadArchiveSettings(_account));
      expect(restored.revision, 1);
      expect(restored.destination, saved.destination);
    },
  );

  test('logout retains settings and permits explicit local reset', () async {
    final saved = _value(
      await store.saveArchiveSettings(_settings(), expectedRevision: 0),
    );
    _value(await store.logout(MailAccountSession(_account)));
    expect(
      _value(await store.loadArchiveSettings(_account)).destination,
      saved.destination,
    );
    _value(
      await store.saveArchiveSettings(
        saved.copyWith(clearDestination: true),
        expectedRevision: 1,
      ),
    );
    expect(_value(await store.loadArchiveSettings(_account)).revision, 2);
    expect(
      _value(await store.listAccounts()).single.state,
      MailStoredAccountState.loggedOut,
    );
  });

  test('cache eviction cannot erase a chosen route', () async {
    final settings = _settings();
    _value(
      await store.saveMailbox(
        MailMailbox(id: settings.destination!, displayName: 'Cached label'),
      ),
    );
    _value(await store.saveArchiveSettings(settings, expectedRevision: 0));
    database.execute('DELETE FROM mailboxes WHERE account=?', [_account.value]);
    final retained = _value(await store.loadArchiveSettings(_account));
    expect(retained.destination, settings.destination);
    expect(retained.revision, 1);
  });

  for (final profileRemoval in [false, true]) {
    test(
      '${profileRemoval ? 'profile' : 'account'} removal erases only intended settings and prevents resurrection',
      () async {
        await _register(store, _other);
        final saved = _value(
          await store.saveArchiveSettings(_settings(), expectedRevision: 0),
        );
        _value(
          await store.saveArchiveSettings(
            _settings(account: _other),
            expectedRevision: 0,
          ),
        );
        _value(
          await (profileRemoval
              ? store.removeProfile()
              : store.removeAccount(_account)),
        );
        _problem(
          await store.loadArchiveSettings(_account),
          MailProblemCode.unavailable,
        );
        _problem(
          await store.saveArchiveSettings(saved, expectedRevision: 1),
          MailProblemCode.unavailable,
        );
        if (profileRemoval) {
          expect(
            database.select('SELECT * FROM account_archive_settings'),
            isEmpty,
          );
        } else {
          expect(_value(await store.loadArchiveSettings(_other)).revision, 1);
          expect(
            database
                .select('SELECT account FROM account_archive_settings')
                .single['account'],
            _other.value,
          );
        }
      },
    );
  }

  test(
    'schema rejects missing ownership while admitting a persisted null reset',
    () {
      for (final account in [null, 'unknown']) {
        expect(
          () => database.execute(
            'INSERT INTO account_archive_settings(account,revision,destination) VALUES(?,1,NULL)',
            [account],
          ),
          throwsA(isA<sqlite.SqliteException>()),
        );
      }
      database.execute(
        'INSERT INTO account_archive_settings(account,revision,destination) VALUES(?,1,NULL)',
        [_account.value],
      );
      expect(
        database
            .select('SELECT destination FROM account_archive_settings')
            .single['destination'],
        isNull,
      );
    },
  );

  for (final (name, sql, args) in <(String, String, List<Object?>)>[
    ('zero revision', 'UPDATE account_archive_settings SET revision=0', []),
    (
      'overflow revision',
      'UPDATE account_archive_settings SET revision=9007199254740992',
      [],
    ),
    (
      'text revision',
      "UPDATE account_archive_settings SET revision='broken'",
      [],
    ),
    (
      'binary folder',
      "UPDATE account_archive_settings SET destination=X'0102'",
      [],
    ),
    ('empty folder', "UPDATE account_archive_settings SET destination=''", []),
    (
      'NUL folder',
      'UPDATE account_archive_settings SET destination=?',
      ['a\u0000b'],
    ),
    (
      'invalid UTF-8',
      "UPDATE account_archive_settings SET destination=CAST(X'EDA080' AS TEXT)",
      [],
    ),
    (
      'oversized UTF-16',
      'UPDATE account_archive_settings SET destination=?',
      ['📨' * 513],
    ),
  ]) {
    test(
      'corrupt $name fails explicitly and cannot be silently overwritten',
      () async {
        final saved = _value(
          await store.saveArchiveSettings(_settings(), expectedRevision: 0),
        );
        database.execute('PRAGMA ignore_check_constraints=ON');
        database.execute(sql, args);
        _problem(
          await store.loadArchiveSettings(_account),
          MailProblemCode.storageFailure,
        );
        _problem(
          await store.saveArchiveSettings(saved, expectedRevision: 1),
          MailProblemCode.storageFailure,
        );
      },
    );
  }

  test(
    'invalid caller Unicode and revisions never create a preference',
    () async {
      for (final settings in [
        _settings(folder: '\uD800'),
        _settings(revision: -1),
        _settings(folder: 'x' * 1025),
      ]) {
        _problem(
          await store.saveArchiveSettings(
            settings,
            expectedRevision: settings.revision,
          ),
          MailProblemCode.invalidInput,
        );
      }
      expect(
        database.select('SELECT * FROM account_archive_settings'),
        isEmpty,
      );
    },
  );

  test('last representable revision cannot wrap or reset', () async {
    _value(await store.saveArchiveSettings(_settings(), expectedRevision: 0));
    database.execute('UPDATE account_archive_settings SET revision=?', [
      MailArchiveDestinationSettings.maxRevision,
    ]);
    final saved = _value(await store.loadArchiveSettings(_account));
    _problem(
      await store.saveArchiveSettings(
        saved.copyWith(clearDestination: true),
        expectedRevision: saved.revision,
      ),
      MailProblemCode.quotaExceeded,
    );
    expect(
      _value(await store.loadArchiveSettings(_account)).revision,
      MailArchiveDestinationSettings.maxRevision,
    );
  });

  for (final (label, limits) in [
    ('metadata', const MailStoreLimits(maxMetadataCodeUnits: 120)),
    ('logical bytes', const MailStoreLimits(maxAccountBytes: 512)),
  ]) {
    test(
      '$label quota rejects a replacement without consuming revision',
      () async {
        await store.close();
        store = await open(limits: limits);
        final saved = _value(
          await store.saveArchiveSettings(
            _settings(folder: 'Small'),
            expectedRevision: 0,
          ),
        );
        _problem(
          await store.saveArchiveSettings(
            saved.copyWith(
              destination: MailMailboxId('x' * 1000, account: _account),
            ),
            expectedRevision: 1,
          ),
          MailProblemCode.quotaExceeded,
        );
        expect(
          _value(await store.loadArchiveSettings(_account)).destination?.value,
          'Small',
        );
        expect(_value(await store.loadArchiveSettings(_account)).revision, 1);
      },
    );
  }

  test(
    'preflights oversized corrupt folder and revision without transferring payloads',
    () async {
      _value(await store.saveArchiveSettings(_settings(), expectedRevision: 0));
      await store.close();
      database.execute('PRAGMA ignore_check_constraints=ON');
      database.execute('UPDATE account_archive_settings SET destination=?', [
        's' * 100000,
      ]);
      final probe = _TransferProbe();
      store = await open(interceptor: probe);
      _problem(
        await store.loadArchiveSettings(_account),
        MailProblemCode.storageFailure,
      );
      expect(probe.largeValueTransferred, isFalse);
      database.execute(
        'UPDATE account_archive_settings SET destination=NULL,revision=?',
        ['r' * 100000],
      );
      _problem(
        await store.loadArchiveSettings(_account),
        MailProblemCode.storageFailure,
      );
      expect(probe.largeValueTransferred, isFalse);
    },
  );

  test(
    'file restart retains exact settings and reset fencing without changing local mail',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'archive-settings-',
      );
      final file = File('${directory.path}/mail.sqlite3');
      Future<SqliteMailRepository> diskOpen() async => _value(
        await SqliteMailRepository.open(
          executor: NativeDatabase(file),
          profile: _profile,
        ),
      );
      try {
        var disk = await diskOpen();
        await _register(disk, _account);
        final draft = MailDraft(
          id: 'draft',
          account: _account,
          revision: 1,
          envelope: MailEnvelope(subject: 'Retained work'),
          body: const MailBody(plainText: 'Exact draft'),
        );
        _value(await disk.saveDraft(draft, expectedRevision: null));
        final saved = _value(
          await disk.saveArchiveSettings(_settings(), expectedRevision: 0),
        );
        await disk.close();
        disk = await diskOpen();
        try {
          final restored = _value(await disk.loadArchiveSettings(_account));
          expect(restored.destination, saved.destination);
          expect(restored.revision, saved.revision);
          _value(
            await disk.saveArchiveSettings(
              restored.copyWith(clearDestination: true),
              expectedRevision: 1,
            ),
          );
          expect(
            _value(await disk.loadDraft(_account, 'draft'))!.body.plainText,
            'Exact draft',
          );
        } finally {
          await disk.close();
        }
        disk = await diskOpen();
        try {
          final reset = _value(await disk.loadArchiveSettings(_account));
          expect(reset.destination, isNull);
          expect(reset.revision, 2);
          _problem(
            await disk.saveArchiveSettings(saved, expectedRevision: 1),
            MailProblemCode.conflict,
          );
        } finally {
          await disk.close();
        }
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );
}

final class _TransferProbe extends QueryInterceptor {
  bool largeValueTransferred = false;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final rows = await super.runSelect(executor, statement, args);
    for (final row in rows) {
      for (final value in row.values) {
        if (value is String && value.length > 4096 ||
            value is Uint8List && value.length > 4096) {
          largeValueTransferred = true;
        }
      }
    }
    return rows;
  }
}
