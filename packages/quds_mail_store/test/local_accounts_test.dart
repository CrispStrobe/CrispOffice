@TestOn('vm')
library;

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:test/test.dart';

final _profile = MailProfileId('directory', hostId: 'test-office');
final _now = DateTime.utc(2026, 11, 20);

MailLocalAccountRecord _record({
  String id = 'account',
  MailProviderKind provider = MailProviderKind.imap,
  String endpoint = 'imaps://imap.example.test:1993',
  String login = 'Login@Example.test',
  String sender = 'Sender@example.test',
  DateTime? time,
}) => MailLocalAccountRecord(
  id: id,
  provider: provider,
  endpoint: endpoint,
  login: login,
  sender: sender,
  lastConnectedAt: time ?? _now,
);

T _value<T>(MailResult<T> result) {
  expect(result, isA<MailSuccess<T>>());
  return (result as MailSuccess<T>).value;
}

void _problem<T>(MailResult<T> result, MailProblemCode code) {
  expect(result, isA<MailFailure<T>>());
  expect((result as MailFailure<T>).problem.code, code);
}

final class _TransferProbe extends QueryInterceptor {
  bool oversizedTextTransferred = false;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final rows = await super.runSelect(executor, statement, args);
    oversizedTextTransferred |= rows.any(
      (row) =>
          row.values.any((value) => value is String && value.length > 16384),
    );
    return rows;
  }
}

void main() {
  late SqliteMailRepository store;
  bool failCommit = false;
  setUp(() async {
    failCommit = false;
    store = _value(
      await SqliteMailRepository.open(
        executor: NativeDatabase.memory(),
        profile: _profile,
        faultInjector: (point) {
          if (failCommit && point == MailStoreCheckpoint.beforeCommit) {
            throw const MailStoreStorageException(
              MailProblemCode.storageFailure,
            );
          }
        },
      ),
    );
  });
  tearDown(() => store.close());

  test(
    'four providers retain exact routes with deterministic recent ordering',
    () async {
      final rows = [
        _record(id: 'imap'),
        _record(
          id: 'ews',
          provider: MailProviderKind.ews,
          endpoint: 'https://ews.example.test/EWS/Exchange.asmx',
          login: '["DOMAIN","login"]',
        ),
        _record(
          id: 'gmail',
          provider: MailProviderKind.gmail,
          endpoint: 'https://gmail.googleapis.com/gmail/v1',
        ),
        _record(
          id: 'graph',
          provider: MailProviderKind.graph,
          endpoint: 'https://graph.microsoft.com/v1.0',
          login: '["tenant","Sender@example.test"]',
        ),
      ];
      for (final row in rows) {
        _value(await store.rememberLocalAccount(row));
      }
      final saved = _value(await store.listLocalAccounts());
      expect(saved.map((row) => row.id), ['ews', 'gmail', 'graph', 'imap']);
      for (final row in saved) {
        expect(
          row.hasSameIdentity(rows.singleWhere((item) => item.id == row.id)),
          isTrue,
        );
      }
      expect(saved.last.endpoint, 'imaps://imap.example.test:1993');
      expect(saved.last.login, 'Login@Example.test');
      expect(saved.last.sender, 'Sender@example.test');
      expect(() => saved.clear(), throwsUnsupportedError);
    },
  );

  test('older confirmations cannot reorder an account backwards', () async {
    final later = _record(time: _now.add(const Duration(hours: 1)));
    _value(await store.rememberLocalAccount(later));
    _value(await store.rememberLocalAccount(_record()));
    expect(
      _value(await store.listLocalAccounts()).single.lastConnectedAt,
      later.lastConnectedAt,
    );
  });

  test('the same id cannot be redirected to another account', () async {
    _value(await store.rememberLocalAccount(_record()));
    for (final replacement in [
      _record(sender: 'Other@example.test'),
      _record(login: 'other'),
      _record(endpoint: 'imaps://other.example.test:993'),
      _record(
        provider: MailProviderKind.ews,
        endpoint: 'https://ews.example.test/EWS',
      ),
    ]) {
      _problem(
        await store.rememberLocalAccount(replacement),
        MailProblemCode.conflict,
      );
    }
    expect(
      _value(await store.listLocalAccounts()).single.hasSameIdentity(_record()),
      isTrue,
    );
  });

  test(
    'same-clock and older reconnects invalidate removal snapshots',
    () async {
      _value(await store.rememberLocalAccount(_record()));
      final original = _value(await store.listLocalAccounts()).single;
      _value(await store.rememberLocalAccount(_record()));
      final refreshed = _value(await store.listLocalAccounts()).single;
      expect(refreshed.lastConnectedAt, original.lastConnectedAt);
      expect(refreshed.revision, original.revision + 1);
      _problem(
        await store.forgetLocalAccount(original),
        MailProblemCode.conflict,
      );
      _value(
        await store.rememberLocalAccount(
          _record(time: _now.subtract(const Duration(days: 1))),
        ),
      );
      _problem(
        await store.forgetLocalAccount(refreshed),
        MailProblemCode.conflict,
      );
      final latest = _value(await store.listLocalAccounts()).single;
      expect(latest.lastConnectedAt, original.lastConnectedAt);
      expect(latest.revision, original.revision + 2);
      _value(await store.forgetLocalAccount(latest));
    },
  );

  test(
    'host metadata budget rejects admission without a partial row',
    () async {
      final bounded = _value(
        await SqliteMailRepository.open(
          executor: NativeDatabase.memory(),
          profile: _profile,
          limits: const MailStoreLimits(maxMetadataCodeUnits: 16),
        ),
      );
      try {
        _problem(
          await bounded.rememberLocalAccount(_record()),
          MailProblemCode.quotaExceeded,
        );
        expect(_value(await bounded.listLocalAccounts()), isEmpty);
      } finally {
        await bounded.close();
      }
    },
  );

  test(
    'directory admission is bounded but existing rows remain refreshable',
    () async {
      for (var i = 0; i < MailLocalAccountDirectory.maxAccounts; i++) {
        _value(await store.rememberLocalAccount(_record(id: 'account-$i')));
      }
      _problem(
        await store.rememberLocalAccount(_record()),
        MailProblemCode.quotaExceeded,
      );
      _value(
        await store.rememberLocalAccount(
          _record(id: 'account-0', time: _now.add(const Duration(days: 1))),
        ),
      );
      final rows = _value(await store.listLocalAccounts());
      expect(rows.length, 100);
      expect(rows.first.id, 'account-0');
      _value(await store.forgetLocalAccount(rows.last));
      _value(await store.rememberLocalAccount(_record()));
      expect(_value(await store.listLocalAccounts()).length, 100);
    },
  );

  test('stale removal refuses a more recent connection', () async {
    _value(await store.rememberLocalAccount(_record()));
    _value(
      await store.rememberLocalAccount(
        _record(time: _now.add(const Duration(seconds: 1))),
      ),
    );
    _problem(
      await store.forgetLocalAccount(_record()),
      MailProblemCode.conflict,
    );
    _value(
      await store.forgetLocalAccount(
        _value(await store.listLocalAccounts()).single,
      ),
    );
    expect(_value(await store.listLocalAccounts()), isEmpty);
    _problem(
      await store.forgetLocalAccount(_record()),
      MailProblemCode.conflict,
    );
    _value(await store.rememberLocalAccount(_record()));
  });

  test('failed registration and removal roll back atomically', () async {
    failCommit = true;
    _problem(
      await store.rememberLocalAccount(_record()),
      MailProblemCode.storageFailure,
    );
    expect(_value(await store.listLocalAccounts()), isEmpty);
    failCommit = false;
    _value(await store.rememberLocalAccount(_record()));
    final saved = _value(await store.listLocalAccounts()).single;
    expect(saved.revision, 1);
    failCommit = true;
    _problem(
      await store.forgetLocalAccount(saved),
      MailProblemCode.storageFailure,
    );
    _problem(
      await store.rememberLocalAccount(_record()),
      MailProblemCode.storageFailure,
    );
    expect(_value(await store.listLocalAccounts()).single.revision, 1);
    failCommit = false;
    _value(await store.rememberLocalAccount(_record()));
    expect(_value(await store.listLocalAccounts()).single.revision, 2);
  });

  test(
    'forgetting a shortcut preserves account, credentials reference, draft and Outbox',
    () async {
      final account = MailAccountId('account', profile: _profile);
      _value(
        await store.createAccount(
          MailStoreAccount(
            id: account,
            provider: MailProviderKind.imap,
            displayName: 'Original',
            credentialReference: 'vault-reference',
          ),
        ),
      );
      final draft = MailDraft(
        id: 'work',
        account: account,
        revision: 0,
        envelope: MailEnvelope(subject: 'Unsent'),
        body: const MailBody(plainText: 'Keep me'),
      );
      _value(await store.saveDraft(draft, expectedRevision: null));
      final queue = MailOutboxEntry.queued(
        id: 'queued',
        prepared: MailPreparedMessage(
          account: account,
          draftId: draft.id,
          draftRevision: draft.revision,
          wire: MailBytes(Uint8List.fromList([1, 2, 3])),
          envelope: MailTransportEnvelope(
            sender: 'a@example.test',
            recipients: ['b@example.test'],
          ),
        ),
        now: _now,
      );
      _value(
        await store.saveOutbox(
          queue,
          expectedState: null,
          expectedAttemptId: null,
        ),
      );
      _value(await store.rememberLocalAccount(_record()));
      _value(
        await store.forgetLocalAccount(
          _value(await store.listLocalAccounts()).single,
        ),
      );
      expect(
        _value(await store.listAccounts()).single.credentialReference,
        'vault-reference',
      );
      expect(
        _value(await store.loadDraft(account, 'work'))!.body.plainText,
        'Keep me',
      );
      expect(
        _value(await store.recoverOutbox(account)).single.prepared.wire.bytes,
        [1, 2, 3],
      );
    },
  );

  test('profile removal erases directory and prevents registration', () async {
    _value(await store.rememberLocalAccount(_record()));
    _value(await store.removeProfile());
    expect(_value(await store.listLocalAccounts()), isEmpty);
    _problem(
      await store.rememberLocalAccount(_record()),
      MailProblemCode.unavailable,
    );
  });

  for (final (label, invalid) in [
    (
      'password in endpoint',
      _record(endpoint: 'imaps://user:secret@imap.example.test:993'),
    ),
    ('query', _record(endpoint: 'imaps://imap.example.test:993?token=secret')),
    ('fragment', _record(endpoint: 'imaps://imap.example.test:993#secret')),
    (
      'cleartext EWS',
      _record(
        provider: MailProviderKind.ews,
        endpoint: 'http://ews.example.test/EWS',
      ),
    ),
    ('local provider', _record(provider: MailProviderKind.local)),
    ('missing host', _record(endpoint: 'imaps:relative')),
    ('control', _record(login: 'user\nsecret')),
    ('invalid sender', _record(sender: 'not-an-address')),
    ('oversized login', _record(login: 'x' * 4097)),
    ('negative date', _record(time: DateTime.fromMillisecondsSinceEpoch(-1))),
  ]) {
    test('rejects $label without writing metadata', () async {
      _problem(
        await store.rememberLocalAccount(invalid),
        MailProblemCode.invalidInput,
      );
      expect(_value(await store.listLocalAccounts()), isEmpty);
      expect(invalid.toString(), 'MailLocalAccountRecord(redacted)');
    });
  }

  test('file reopen retains metadata and corrupt rows fail closed', () async {
    final directory = await Directory.systemTemp.createTemp(
      'mail-local-account-',
    );
    final file = File('${directory.path}/mail.sqlite3');
    Future<SqliteMailRepository> open() async => _value(
      await SqliteMailRepository.open(
        executor: NativeDatabase(file),
        profile: _profile,
      ),
    );
    try {
      var disk = await open();
      _value(await disk.rememberLocalAccount(_record()));
      await disk.close();
      disk = await open();
      expect(
        _value(
          await disk.listLocalAccounts(),
        ).single.hasSameIdentity(_record()),
        isTrue,
      );
      await disk.close();
      final raw = sqlite.sqlite3.open(file.path);
      raw.execute(
        "UPDATE local_accounts SET endpoint='https://user:secret@example.test'",
      );
      raw.close();
      disk = await open();
      _problem(await disk.listLocalAccounts(), MailProblemCode.storageFailure);
      _problem(
        await disk.rememberLocalAccount(_record()),
        MailProblemCode.storageFailure,
      );
      await disk.close();
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test(
    'oversized stored metadata fails before copying or overwriting it',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'mail-account-limit-',
      );
      final file = File('${directory.path}/mail.sqlite3');
      Future<SqliteMailRepository> open() async => _value(
        await SqliteMailRepository.open(
          executor: NativeDatabase(file),
          profile: _profile,
        ),
      );
      try {
        var disk = await open();
        _value(await disk.rememberLocalAccount(_record()));
        await disk.close();
        final raw = sqlite.sqlite3.open(file.path);
        raw.execute('UPDATE local_accounts SET login=?', ['x' * 4097]);
        raw.close();
        disk = await open();
        try {
          _problem(
            await disk.listLocalAccounts(),
            MailProblemCode.storageFailure,
          );
          _problem(
            await disk.rememberLocalAccount(_record()),
            MailProblemCode.storageFailure,
          );
          _problem(
            await disk.forgetLocalAccount(_record()),
            MailProblemCode.storageFailure,
          );
        } finally {
          await disk.close();
        }
        final check = sqlite.sqlite3.open(file.path);
        expect(
          check
              .select('SELECT length(login) AS n FROM local_accounts')
              .single['n'],
          4097,
        );
        check.close();
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );

  test(
    'remove, reopen and re-add cannot revive an old removal snapshot',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'mail-directory-aba-',
      );
      final file = File('${directory.path}/mail.sqlite3');
      Future<SqliteMailRepository> open() async => _value(
        await SqliteMailRepository.open(
          executor: NativeDatabase(file),
          profile: _profile,
        ),
      );
      try {
        var disk = await open();
        _value(await disk.rememberLocalAccount(_record()));
        final original = _value(await disk.listLocalAccounts()).single;
        _value(await disk.forgetLocalAccount(original));
        await disk.close();
        disk = await open();
        try {
          _value(await disk.rememberLocalAccount(_record()));
          final replacement = _value(await disk.listLocalAccounts()).single;
          expect(replacement.hasSameIdentity(original), isTrue);
          expect(replacement.lastConnectedAt, original.lastConnectedAt);
          expect(replacement.revision, greaterThan(original.revision));
          _problem(
            await disk.forgetLocalAccount(original),
            MailProblemCode.conflict,
          );
          _value(await disk.forgetLocalAccount(replacement));
        } finally {
          await disk.close();
        }
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );

  for (final (field, corrupt) in [
    ('login', 'x\u0000${'a' * 100000}'),
    ('provider', 'x' * 100000),
  ]) {
    test(
      'corrupt $field is rejected before oversized text reaches Dart rows',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'mail-directory-bytes-',
        );
        final file = File('${directory.path}/mail.sqlite3');
        final probe = _TransferProbe();
        Future<SqliteMailRepository> open() async => _value(
          await SqliteMailRepository.open(
            executor: NativeDatabase(file).interceptWith(probe),
            profile: _profile,
          ),
        );
        try {
          var disk = await open();
          _value(await disk.rememberLocalAccount(_record()));
          final saved = _value(await disk.listLocalAccounts()).single;
          await disk.close();
          final raw = sqlite.sqlite3.open(file.path);
          raw.execute('UPDATE local_accounts SET $field=?', [corrupt]);
          raw.close();
          disk = await open();
          try {
            _problem(
              await disk.listLocalAccounts(),
              MailProblemCode.storageFailure,
            );
            _problem(
              await disk.rememberLocalAccount(_record()),
              MailProblemCode.storageFailure,
            );
            _problem(
              await disk.forgetLocalAccount(saved),
              MailProblemCode.storageFailure,
            );
            expect(probe.oversizedTextTransferred, isFalse);
          } finally {
            await disk.close();
          }
          final check = sqlite.sqlite3.open(file.path);
          expect(
            check.select('SELECT $field FROM local_accounts').single[field],
            corrupt,
          );
          check.close();
        } finally {
          await directory.delete(recursive: true);
        }
      },
    );
  }

  test(
    'reopening under a lowered UTF-16 budget retains but refuses Unicode metadata',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'mail-directory-unicode-',
      );
      final file = File('${directory.path}/mail.sqlite3');
      Future<SqliteMailRepository> open(MailStoreLimits limits) async => _value(
        await SqliteMailRepository.open(
          executor: NativeDatabase(file),
          profile: _profile,
          limits: limits,
        ),
      );
      final unicode = _record(login: '😀' * 1000);
      try {
        var disk = await open(const MailStoreLimits());
        _value(await disk.rememberLocalAccount(unicode));
        final original = _value(await disk.listLocalAccounts()).single;
        await disk.close();
        disk = await open(const MailStoreLimits(maxMetadataCodeUnits: 1500));
        try {
          _problem(
            await disk.listLocalAccounts(),
            MailProblemCode.quotaExceeded,
          );
          _problem(
            await disk.rememberLocalAccount(unicode),
            MailProblemCode.quotaExceeded,
          );
          _problem(
            await disk.forgetLocalAccount(original),
            MailProblemCode.quotaExceeded,
          );
        } finally {
          await disk.close();
        }
        disk = await open(const MailStoreLimits());
        try {
          final restored = _value(await disk.listLocalAccounts()).single;
          expect(restored.hasSameIdentity(unicode), isTrue);
          expect(restored.revision, original.revision);
        } finally {
          await disk.close();
        }
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );
}
