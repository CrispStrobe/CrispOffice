@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

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
    failCommit = true;
    _problem(
      await store.forgetLocalAccount(_record()),
      MailProblemCode.storageFailure,
    );
    expect(_value(await store.listLocalAccounts()), hasLength(1));
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
      _value(await store.forgetLocalAccount(_record()));
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
}
