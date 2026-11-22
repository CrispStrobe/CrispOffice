@TestOn('vm')
library;

import 'dart:io';

import 'package:drift/drift.dart';
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
    show schemaV6, schemaV7, schemaV13;
import 'package:quds_mail_store/src/schema/membership_observation_schema.dart'
    show schemaV14;
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:test/test.dart';

final _profile = MailProfileId('released-v14', hostId: 'move-migration');
final _account = MailAccountId('account', profile: _profile);
final _source = MailMailboxId('INBOX', account: _account);
final _identity = MailImapIdentity(mailbox: _source, uidValidity: 7, uid: 11);
final _time = DateTime.utc(2026, 11, 22);

void _seed(File file) {
  final db = sqlite.sqlite3.open(file.path);
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
    ...schemaV13,
    ...schemaV14,
  ]) {
    db.execute(sql);
  }
  db.execute(
    'INSERT INTO store_profile(singleton,host_id,profile_id) VALUES(1,?,?)',
    [_profile.hostId, _profile.value],
  );
  db.execute(
    "INSERT INTO accounts(id,provider,display_name,state) VALUES(?,'imap','Existing account','active')",
    [_account.value],
  );
  for (final state in ['confirmed', 'uncertain']) {
    db.execute(
      'INSERT INTO flag_batches(account,id,mailbox,provider,action,destination,created_at,updated_at,revision,complete,interrupted,item_count) '
      "VALUES(?,?,?,'imap','move','Archive',?,?,4,1,0,1)",
      [
        _account.value,
        state,
        _source.value,
        _time.millisecondsSinceEpoch,
        _time.millisecondsSinceEpoch,
      ],
    );
    db.execute(
      'INSERT INTO flag_batch_items(account,batch,position,remote,subject,state) VALUES(?,?,0,?,?,?)',
      [
        _account.value,
        state,
        MailStoreCodec.encodeRemote(_identity),
        'Existing subject',
        state,
      ],
    );
  }
  db.execute(
    'INSERT INTO membership_item_observations(account,batch,position,kind,mailboxes,checked_at) '
    "VALUES(?,'uncertain',0,'missing','[]',?)",
    [_account.value, _time.millisecondsSinceEpoch],
  );
  db.execute('PRAGMA user_version=14');
  db.close();
}

T _value<T>(MailResult<T> result) {
  expect(result, isA<MailSuccess<T>>());
  return (result as MailSuccess<T>).value;
}

Map<String, List<Map<String, Object?>>> _snapshot(sqlite.Database db) => {
  for (final table in [
    'store_profile',
    'accounts',
    'flag_batches',
    'flag_batch_items',
    'membership_item_observations',
  ])
    table: [
      for (final row in db.select('SELECT * FROM $table ORDER BY rowid'))
        Map<String, Object?>.from(row),
    ],
};

void main() {
  for (final failMigration in [false, true]) {
    test(
      'released v14 receipts migrate without inferred transitions; fault=$failMigration',
      () async {
        driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
        final directory = await Directory.systemTemp.createTemp(
          'move-migration-',
        );
        final file = File('${directory.path}/store.sqlite3');
        try {
          _seed(file);
          final beforeDb = sqlite.sqlite3.open(file.path);
          final before = _snapshot(beforeDb);
          beforeDb.close();
          Future<MailResult<SqliteMailRepository>> open(bool fail) =>
              SqliteMailRepository.open(
                executor: NativeDatabase(file),
                profile: _profile,
                clock: () => _time,
                faultInjector: (point) {
                  if (fail && point == MailStoreCheckpoint.migrationCreated) {
                    throw const MailStoreStorageException(
                      MailProblemCode.storageFailure,
                    );
                  }
                },
              );
          if (failMigration) {
            final failure = await open(true);
            expect(failure, isA<MailFailure<SqliteMailRepository>>());
            final rollback = sqlite.sqlite3.open(file.path);
            expect(rollback.userVersion, 14);
            expect(_snapshot(rollback), before);
            expect(
              rollback.select(
                "SELECT name FROM sqlite_master WHERE name='move_identity_transitions'",
              ),
              isEmpty,
            );
            expect(
              rollback.select(
                "SELECT name FROM sqlite_master WHERE name='mailbox_move_revisions'",
              ),
              isEmpty,
            );
            rollback.close();
          }
          final store = _value(await open(false));
          try {
            final confirmed = _value(
              await store.loadFlagBatch(_account, 'confirmed'),
            )!;
            final uncertain = _value(
              await store.loadFlagBatch(_account, 'uncertain'),
            )!;
            expect(confirmed.report.confirmedCount, 1);
            expect(confirmed.identityTransitions, isEmpty);
            expect(confirmed.report.items.single.identityTransition, null);
            expect(uncertain.summary.uncertainCount, 1);
            expect(uncertain.identityTransitions, isEmpty);
            expect(
              uncertain.membershipObservations.single.observation.kind,
              MailMembershipObservationKind.missing,
            );
          } finally {
            await store.close();
          }
          final after = sqlite.sqlite3.open(file.path);
          expect(after.userVersion, 16);
          expect(_snapshot(after), before);
          expect(after.select('PRAGMA foreign_key_check'), isEmpty);
          expect(
            after.select('SELECT * FROM move_identity_transitions'),
            isEmpty,
          );
          expect(after.select('SELECT * FROM mailbox_move_revisions'), isEmpty);
          after.close();
        } finally {
          await directory.delete(recursive: true);
        }
      },
    );
  }
}
