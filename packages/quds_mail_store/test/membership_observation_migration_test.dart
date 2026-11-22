@TestOn('vm')
library;

import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
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
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:test/test.dart';

final _profile = MailProfileId(
  'v13',
  hostId: 'membership-observation-migration',
);
final _account = MailAccountId('account', profile: _profile);
final _mailbox = MailMailboxId('INBOX', account: _account);
final _identity = MailImapIdentity(mailbox: _mailbox, uidValidity: 7, uid: 19);
final _time = DateTime.utc(2026, 11, 22);

void _seed(File file) {
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
      ...schemaV13,
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
    for (final action in ['move', 'delete', 'markRead']) {
      db.execute(
        'INSERT INTO flag_batches(account,id,mailbox,provider,action,destination,created_at,updated_at,revision,complete,interrupted,item_count) '
        'VALUES(?,?,?,?,?,?,?,?,4,1,0,1)',
        [
          _account.value,
          action,
          _mailbox.value,
          'imap',
          action,
          action == 'move' ? 'archive' : null,
          _time.millisecondsSinceEpoch,
          _time.millisecondsSinceEpoch,
        ],
      );
      db.execute(
        "INSERT INTO flag_batch_items(account,batch,position,remote,subject,state,problem_code,mutation_possible) VALUES(?,?,0,?,?,'uncertain','providerFailure',1)",
        [
          _account.value,
          action,
          MailStoreCodec.encodeRemote(_identity),
          'Original $action subject',
        ],
      );
    }
    db.execute(
      "INSERT INTO flag_item_resolutions(account,batch,position,kind,checked_at) VALUES(?,'markRead',0,'matches',?)",
      [_account.value, _time.millisecondsSinceEpoch],
    );
    db.execute('INSERT INTO drafts(account,id,revision,data) VALUES(?,?,?,?)', [
      _account.value,
      'original-draft',
      5,
      MailStoreCodec.encodeDraft(
        MailDraft(
          id: 'original-draft',
          account: _account,
          revision: 5,
          envelope: MailEnvelope(subject: 'Draft subject'),
          body: const MailBody(plainText: 'Original draft bytes'),
        ),
      ).data,
    ]);
    db.userVersion = 13;
  } finally {
    db.close();
  }
}

Map<String, List<Map<String, Object?>>> _snapshot(sqlite.Database db) => {
  for (final table in [
    'accounts',
    'drafts',
    'flag_batches',
    'flag_batch_items',
    'flag_item_resolutions',
  ])
    table: db
        .select('SELECT * FROM $table ORDER BY rowid')
        .map((row) => Map<String, Object?>.from(row))
        .toList(),
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
    directory = await Directory.systemTemp.createTemp('mail-membership-v13-');
    file = File('${directory.path}/mail.sqlite3');
    _seed(file);
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
      'v13 upgrade interrupted=$interrupt retains move/delete and prior flags exactly',
      () async {
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
          expect(rollback.userVersion, 13);
          expect(_snapshot(rollback), before);
          expect(
            rollback.select(
              "SELECT name FROM sqlite_master WHERE name='membership_item_observations'",
            ),
            isEmpty,
          );
          rollback.close();
        }
        final store = _value(await open());
        try {
          for (final action in ['move', 'delete']) {
            final receipt = _value(
              await store.loadFlagBatch(_account, action),
            )!;
            expect(receipt.summary.action.name, action);
            expect(
              receipt.summary.destination?.value,
              action == 'move' ? 'archive' : null,
            );
            expect(receipt.summary.unresolvedCount, 1);
            expect(receipt.summary.reconciledCount, 0);
            expect(receipt.summary.revision, 4);
            expect(receipt.membershipObservations, isEmpty);
            expect(receipt.subjects, ['Original $action subject']);
          }
          final flags = _value(
            await store.loadFlagBatch(_account, 'markRead'),
          )!;
          expect(flags.resolutions.single.kind, MailFlagResolutionKind.matches);
          expect(flags.membershipObservations, isEmpty);
          expect(flags.summary.unresolvedCount, 0);
          expect(
            _value(await store.loadDraft(_account, 'original-draft'))!.revision,
            5,
          );
        } finally {
          await store.close();
        }
        final afterDb = sqlite.sqlite3.open(file.path);
        expect(afterDb.userVersion, 18);
        expect(_snapshot(afterDb), before);
        expect(afterDb.select('PRAGMA foreign_key_check'), isEmpty);
        expect(
          afterDb.select('SELECT * FROM membership_item_observations'),
          isEmpty,
        );
        afterDb.close();
      },
    );
  }

  test(
    'upgraded v13 uncertain move can retain evidence without becoming clean',
    () async {
      final store = _value(await open());
      final session = MailAccountSession(_account);
      try {
        final lease = session.begin();
        final handle = _value(
          await store.beginMembershipReconciliation(
            _account,
            'move',
            0,
            expectedRevision: 4,
            lease: lease,
          ),
        );
        _value(
          await store.recordMembershipObservation(
            handle,
            MailMembershipObservation.missing(identity: _identity),
            lease: lease,
          ),
        );
        final receipt = _value(await store.loadFlagBatch(_account, 'move'))!;
        expect(
          receipt.membershipObservations.single.observation.identity,
          _identity,
        );
        expect(receipt.summary.unresolvedCount, 1);
        expect(receipt.summary.revision, 5);
        // Only the pre-existing resolved flag batch is removable.
        expect(_value(await store.clearCompletedFlagBatches(_account)), 1);
        expect(_value(await store.loadFlagBatch(_account, 'move')), isNotNull);
        expect(
          _value(await store.loadFlagBatch(_account, 'delete')),
          isNotNull,
        );
      } finally {
        session.dispose();
        await store.close();
      }
    },
  );
}
