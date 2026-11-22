@TestOn('vm')
library;

import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:quds_mail_store/src/codec.dart';
import 'package:quds_mail_store/src/schema/database.dart'
    show
        schemaV1,
        schemaV2,
        schemaV3,
        schemaV4,
        schemaV5,
        schemaV8,
        schemaV9,
        schemaV10,
        schemaV11,
        schemaV12;
import 'package:quds_mail_store/src/schema/flag_journal_schema.dart'
    show schemaV6, schemaV7;
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:test/test.dart';

final _profile = MailProfileId('v12', hostId: 'membership-migration');
final _account = MailAccountId('account', profile: _profile);
final _mailbox = MailMailboxId('inbox', account: _account);
final _time = DateTime.utc(2026, 11, 22);
final _draft = MailDraft(
  id: 'draft',
  account: _account,
  revision: 4,
  envelope: MailEnvelope(subject: 'Retained draft'),
  body: const MailBody(plainText: 'Original draft body'),
);

void _seed(File file, {String action = 'markRead'}) {
  final db = sqlite.sqlite3.open(file.path);
  try {
    for (final sql in [
      ...schemaV1,
      ...schemaV2,
      ...schemaV3,
      ...schemaV4,
      ...schemaV5,
      ...schemaV6,
      ...schemaV7,
      ...schemaV8,
      ...schemaV9,
      ...schemaV10,
      ...schemaV11,
      ...schemaV12,
    ]) {
      db.execute(sql);
    }
    db.execute(
      'INSERT INTO store_profile(singleton,host_id,profile_id) VALUES(1,?,?)',
      [_profile.hostId, _profile.value],
    );
    db.execute(
      "INSERT INTO accounts(id,provider,display_name,state) VALUES(?,'imap','Original account','active')",
      [_account.value],
    );
    db.execute('INSERT INTO drafts(account,id,revision,data) VALUES(?,?,?,?)', [
      _account.value,
      _draft.id,
      _draft.revision,
      MailStoreCodec.encodeDraft(_draft).data,
    ]);
    db.execute(
      'INSERT INTO flag_batches(account,id,mailbox,provider,action,created_at,updated_at,revision,complete,interrupted,item_count) VALUES(?,?,?,?,?,?,?,4,1,0,1)',
      [
        _account.value,
        'prior-flags',
        _mailbox.value,
        'imap',
        action,
        _time.millisecondsSinceEpoch,
        _time.millisecondsSinceEpoch,
      ],
    );
    db.execute(
      "INSERT INTO flag_batch_items(account,batch,position,remote,subject,state,problem_code,mutation_possible) VALUES(?,? ,0,?,?,'uncertain','providerFailure',1)",
      [
        _account.value,
        'prior-flags',
        MailStoreCodec.encodeRemote(
          MailImapIdentity(mailbox: _mailbox, uidValidity: 9, uid: 17),
        ),
        'Frozen original subject',
      ],
    );
    db.userVersion = 12;
  } finally {
    db.close();
  }
}

Map<String, List<List<Object?>>> _snapshot(sqlite.Database db) => {
  for (final table in [
    'accounts',
    'drafts',
    'flag_batches',
    'flag_batch_items',
  ])
    table: [
      for (final row in db.select('SELECT * FROM $table ORDER BY rowid'))
        row.entries
            .where((entry) => entry.key != 'destination')
            .map((entry) => entry.value)
            .toList(),
    ],
};

T _value<T>(MailResult<T> result) {
  expect(result, isA<MailSuccess<T>>());
  return (result as MailSuccess<T>).value;
}

void main() {
  late Directory directory;
  late File file;
  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    directory = await Directory.systemTemp.createTemp('membership-migration-');
    file = File('${directory.path}/mail.sqlite3');
  });
  tearDown(() async => directory.delete(recursive: true));

  Future<MailResult<SqliteMailRepository>> open({bool interrupt = false}) =>
      SqliteMailRepository.open(
        executor: NativeDatabase(file),
        profile: _profile,
        clock: () => _time,
        faultInjector: (point) {
          if (interrupt && point == MailStoreCheckpoint.migrationCreated) {
            throw const MailStoreStorageException(
              MailProblemCode.storageFailure,
            );
          }
        },
      );

  for (final interrupt in [false, true]) {
    test(
      'schema v12 migration interrupted=$interrupt preserves original receipts and draft bytes',
      () async {
        _seed(file);
        final beforeDb = sqlite.sqlite3.open(file.path);
        final before = _snapshot(beforeDb);
        beforeDb.close();
        if (interrupt) {
          final failed = await open(interrupt: true);
          expect(failed, isA<MailFailure<SqliteMailRepository>>());
          expect(
            (failed as MailFailure<SqliteMailRepository>).problem.code,
            MailProblemCode.storageFailure,
          );
          final rollback = sqlite.sqlite3.open(file.path);
          expect(rollback.userVersion, 12);
          expect(
            rollback
                .select('PRAGMA table_info(flag_batches)')
                .map((row) => row['name']),
            isNot(contains('destination')),
          );
          expect(_snapshot(rollback), before);
          rollback.close();
        }
        final store = _value(await open());
        try {
          final batch = _value(
            await store.loadFlagBatch(_account, 'prior-flags'),
          )!;
          expect(batch.report.plan.action, MailBulkFlagAction.markRead);
          expect(batch.report.plan.destination, isNull);
          expect(batch.summary.canCheckFlags, isTrue);
          expect(batch.summary.unresolvedCount, 1);
          expect(batch.summary.revision, 4);
          expect(batch.subjects, ['Frozen original subject']);
          final draft = _value(await store.loadDraft(_account, _draft.id))!;
          expect(
            MailStoreCodec.encodeDraft(draft).data,
            MailStoreCodec.encodeDraft(_draft).data,
          );
        } finally {
          await store.close();
        }
        final migrated = sqlite.sqlite3.open(file.path);
        expect(migrated.userVersion, 14);
        expect(_snapshot(migrated), before);
        expect(
          migrated
              .select('SELECT destination FROM flag_batches')
              .single['destination'],
          isNull,
        );
        expect(migrated.select('PRAGMA foreign_key_check'), isEmpty);
        migrated.close();
      },
    );
  }

  for (final action in ['move', 'delete', 'unrecognized']) {
    test(
      'schema v12 unexplained $action intent refuses migration without changing data',
      () async {
        _seed(file, action: action);
        final original = await file.readAsBytes();
        final failed = await open();
        expect(failed, isA<MailFailure<SqliteMailRepository>>());
        expect(
          (failed as MailFailure<SqliteMailRepository>).problem.code,
          MailProblemCode.storageFailure,
        );
        expect(await file.readAsBytes(), original);
        final db = sqlite.sqlite3.open(file.path);
        expect(db.userVersion, 12);
        expect(
          db
              .select('PRAGMA table_info(flag_batches)')
              .map((row) => row['name']),
          isNot(contains('destination')),
        );
        db.close();
      },
    );
  }
}
