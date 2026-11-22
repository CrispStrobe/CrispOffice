@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
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
import 'package:quds_mail_store/src/schema/move_identity_schema.dart'
    show schemaV15;
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:test/test.dart';

final _profile = MailProfileId('released-v15', hostId: 'archive-migration');
final _account = MailAccountId('gmail', profile: _profile);
final _inbox = MailMailboxId('INBOX', account: _account);
final _identity = MailOpaqueIdentity(
  account: _account,
  provider: MailProviderKind.gmail,
  value: 'original-message',
);
final _time = DateTime.utc(2026, 11, 22, 12);
final _draft = MailDraft(
  id: 'original-draft',
  account: _account,
  revision: 7,
  envelope: MailEnvelope(subject: 'Retained draft — مسودة'),
  body: const MailBody(plainText: 'Exact original draft text'),
  attachments: [
    MailAttachment(
      partPath: '1',
      mediaType: 'application/octet-stream',
      displayName: 'original.bin',
      content: MailBytes(Uint8List.fromList([0, 1, 2, 127, 255])),
    ),
  ],
);
final _outbox = MailOutboxEntry.queued(
  id: 'original-outbox',
  prepared: MailPreparedMessage(
    account: _account,
    draftId: _draft.id,
    draftRevision: _draft.revision,
    wire: MailBytes(
      Uint8List.fromList(
        utf8.encode(
          'From: sender@example.invalid\r\nTo: recipient@example.invalid\r\n'
          'Subject: Frozen message\r\n\r\nOriginal queued payload\r\n',
        ),
      ),
    ),
    envelope: MailTransportEnvelope(
      sender: 'sender@example.invalid',
      recipients: ['recipient@example.invalid'],
    ),
  ),
  now: _time,
);

T _value<T>(MailResult<T> result) {
  expect(result, isA<MailSuccess<T>>());
  return (result as MailSuccess<T>).value;
}

void _payload(
  sqlite.Database db,
  MailStorePayload payload,
  String kind,
  String id,
) {
  for (final entry in payload.blobs.entries) {
    db.execute('INSERT INTO blobs(account,hash,data,size) VALUES(?,?,?,?)', [
      _account.value,
      entry.key,
      entry.value.copyBytes(),
      entry.value.length,
    ]);
    db.execute(
      'INSERT INTO blob_refs(account,owner_kind,owner_id,hash) VALUES(?,?,?,?)',
      [_account.value, kind, id, entry.key],
    );
  }
}

void _seed(File file, {String? unexplainedArchive, int version = 15}) {
  final db = sqlite.sqlite3.open(file.path);
  try {
    // Build the released v15 schema directly. Do not create today's schema
    // and relabel it with an old version, which would hide migration mistakes.
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
      ...schemaV15,
    ]) {
      db.execute(sql);
    }
    db.execute(
      'INSERT INTO store_profile(singleton,host_id,profile_id) VALUES(1,?,?)',
      [_profile.hostId, _profile.value],
    );
    db.execute(
      "INSERT INTO accounts(id,provider,display_name,state) VALUES(?,'gmail','Original Gmail','active')",
      [_account.value],
    );
    final draftPayload = MailStoreCodec.encodeDraft(_draft);
    _payload(db, draftPayload, 'draft', _draft.id);
    db.execute('INSERT INTO drafts(account,id,revision,data) VALUES(?,?,?,?)', [
      _account.value,
      _draft.id,
      _draft.revision,
      draftPayload.data,
    ]);
    final outboxPayload = MailStoreCodec.encodeOutbox(_outbox);
    _payload(db, outboxPayload, 'outbox', _outbox.id);
    db.execute(
      "INSERT INTO outbox(account,id,state,data) VALUES(?,?,'queued',?)",
      [_account.value, _outbox.id, outboxPayload.data],
    );
    for (final action in ['markRead', 'move']) {
      db.execute(
        'INSERT INTO flag_batches(account,id,mailbox,provider,action,destination,created_at,updated_at,revision,complete,interrupted,item_count) '
        "VALUES(?,?,?,'gmail',?,?,?,?,4,1,0,1)",
        [
          _account.value,
          action,
          _inbox.value,
          action,
          action == 'move' ? 'Label_Archive' : null,
          _time.millisecondsSinceEpoch,
          _time.millisecondsSinceEpoch,
        ],
      );
      db.execute(
        'INSERT INTO flag_batch_items(account,batch,position,remote,subject,state,problem_code,mutation_possible) '
        'VALUES(?,?,0,?,?,?,?,?)',
        [
          _account.value,
          action,
          MailStoreCodec.encodeRemote(_identity),
          'Original $action subject',
          action == 'move' ? 'confirmed' : 'uncertain',
          action == 'move' ? null : 'providerFailure',
          action == 'move' ? null : 1,
        ],
      );
    }
    db.execute(
      'INSERT INTO pending_operations(account,id,remote,kind,argument,state,revision,created_at,updated_at) '
      "VALUES(?,'prior-pending',?,'read','1','queued',3,?,?)",
      [
        _account.value,
        MailStoreCodec.encodeRemote(_identity),
        _time.millisecondsSinceEpoch,
        _time.millisecondsSinceEpoch,
      ],
    );
    if (unexplainedArchive == 'journal') {
      db.execute(
        "UPDATE flag_batches SET action='archive' WHERE id='markRead'",
      );
    } else if (unexplainedArchive == 'pending') {
      db.execute("UPDATE pending_operations SET kind='archive',argument=NULL");
    }
    db.userVersion = version;
  } finally {
    db.close();
  }
}

Map<String, List<Map<String, Object?>>> _snapshot(sqlite.Database db) => {
  for (final table in db.select(
    "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
  ))
    table['name'] as String: [
      for (final row in db.select(
        'SELECT * FROM "${(table['name'] as String).replaceAll('"', '""')}" ORDER BY 1',
      ))
        Map<String, Object?>.from(row),
    ],
};

List<Map<String, Object?>> _schema(sqlite.Database db) => [
  for (final row in db.select(
    'SELECT type,name,tbl_name,sql FROM sqlite_master ORDER BY type,name',
  ))
    if (row['name'] != 'messages_conversation')
      {
        ...Map<String, Object?>.from(row),
        if (row['name'] == 'messages')
          'sql': (row['sql'] as String?)?.replaceFirst(
            RegExp(r', conversation TEXT'),
            '',
          ),
      },
];

void main() {
  late Directory directory;
  late File file;
  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    directory = await Directory.systemTemp.createTemp('archive-v15-');
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
      'released v15 migration preserves every table and payload; interrupted=$interrupt',
      () async {
        _seed(file);
        final beforeDb = sqlite.sqlite3.open(file.path);
        final before = _snapshot(beforeDb);
        final beforeSchema = _schema(beforeDb);
        beforeDb.close();
        if (interrupt) {
          final failure = await open(interrupt: true);
          expect(failure, isA<MailFailure<SqliteMailRepository>>());
          expect(
            (failure as MailFailure<SqliteMailRepository>).problem.code,
            MailProblemCode.storageFailure,
          );
          final rollback = sqlite.sqlite3.open(file.path);
          expect(rollback.userVersion, 15);
          expect(_snapshot(rollback), before);
          expect(_schema(rollback), beforeSchema);
          rollback.close();
        }
        final store = _value(await open());
        try {
          final draft = _value(await store.loadDraft(_account, _draft.id))!;
          expect(
            MailStoreCodec.encodeDraft(draft).data,
            MailStoreCodec.encodeDraft(_draft).data,
          );
          expect(
            draft.attachments.single.content.copyBytes(),
            _draft.attachments.single.content.copyBytes(),
          );
          final queued = _value(await store.recoverOutbox(_account)).single;
          expect(queued.state, MailOutboxState.queued);
          expect(
            queued.prepared.wire.copyBytes(),
            _outbox.prepared.wire.copyBytes(),
          );
          expect(
            queued.prepared.envelope.recipients,
            _outbox.prepared.envelope.recipients,
          );
          expect(
            MailStoreCodec.encodeOutbox(queued).data,
            MailStoreCodec.encodeOutbox(_outbox).data,
          );
          final flags = _value(
            await store.loadFlagBatch(_account, 'markRead'),
          )!;
          expect(flags.summary.action, MailBulkFlagAction.markRead);
          expect(flags.summary.revision, 4);
          expect(flags.summary.unresolvedCount, 1);
          expect(
            flags.report.results.single.problem?.mutationMayHaveOccurred,
            isTrue,
          );
          final move = _value(await store.loadFlagBatch(_account, 'move'))!;
          expect(move.summary.action, MailBulkFlagAction.move);
          expect(move.summary.destination?.value, 'Label_Archive');
          expect(move.report.confirmedCount, 1);
          expect(move.identityTransitions, isEmpty);
          final pending = _value(
            await store.pendingOperations(_account),
          ).single;
          expect(pending.operation, isA<MailSetRead>());
          expect(pending.revision, 3);
          expect(pending.state, MailPendingState.queued);
        } finally {
          await store.close();
        }
        final after = sqlite.sqlite3.open(file.path);
        try {
          expect(after.userVersion, 20);
          expect(
            _schema(after).where(
              (row) =>
                  row['tbl_name'] != 'account_archive_settings' &&
                  row['tbl_name'] != 'message_tags' &&
                  row['tbl_name'] != 'mail_rules',
            ),
            beforeSchema,
          );
          expect(
            _snapshot(after)
              ..remove('account_archive_settings')
              ..remove('message_tags')
              ..remove('mail_rules'),
            before,
          );
          expect(
            after.select('SELECT * FROM account_archive_settings'),
            isEmpty,
          );
          expect(after.select('PRAGMA foreign_key_check'), isEmpty);
        } finally {
          after.close();
        }
      },
    );
  }

  for (final target in ['journal', 'pending']) {
    for (final interrupt in [false, true]) {
      test(
        'released v16 with legitimate Archive $target upgrades additively; interrupted=$interrupt',
        () async {
          // v16 changed the admitted journal actions without adding tables.
          // Build the released layout, retaining real Archive intent.
          _seed(file, unexplainedArchive: target, version: 16);
          final original = sqlite.sqlite3.open(file.path);
          final before = _snapshot(original);
          final schema = _schema(original);
          original.close();
          if (interrupt) {
            final failure = await open(interrupt: true);
            expect(failure, isA<MailFailure<SqliteMailRepository>>());
            final rollback = sqlite.sqlite3.open(file.path);
            try {
              expect(rollback.userVersion, 16);
              expect(_snapshot(rollback), before);
              expect(_schema(rollback), schema);
            } finally {
              rollback.close();
            }
          }
          final store = _value(await open());
          try {
            final settings = _value(await store.loadArchiveSettings(_account));
            expect(settings.revision, 0);
            expect(settings.destination, isNull);
            if (target == 'journal') {
              final receipt = _value(
                await store.loadFlagBatch(_account, 'markRead'),
              )!;
              expect(receipt.summary.action, MailBulkFlagAction.archive);
              expect(receipt.summary.unresolvedCount, 1);
            } else {
              expect(
                _value(
                  await store.pendingOperations(_account),
                ).single.operation,
                isA<MailArchive>(),
              );
            }
            final queued = _value(await store.recoverOutbox(_account)).single;
            expect(
              queued.prepared.wire.copyBytes(),
              _outbox.prepared.wire.copyBytes(),
            );
            expect(
              _value(
                await store.loadDraft(_account, _draft.id),
              )!.attachments.single.content.copyBytes(),
              _draft.attachments.single.content.copyBytes(),
            );
          } finally {
            await store.close();
          }
          final migrated = sqlite.sqlite3.open(file.path);
          try {
            expect(migrated.userVersion, 20);
            expect(
              _snapshot(migrated)
                ..remove('account_archive_settings')
                ..remove('message_tags')
                ..remove('mail_rules'),
              before,
            );
            expect(
              _schema(migrated).where(
                (row) =>
                    row['tbl_name'] != 'account_archive_settings' &&
                    row['tbl_name'] != 'message_tags' &&
                    row['tbl_name'] != 'mail_rules',
              ),
              schema,
            );
            expect(migrated.select('PRAGMA foreign_key_check'), isEmpty);
          } finally {
            migrated.close();
          }
        },
      );
    }

    test(
      'unexplained v15 Archive in $target refuses migration with exact rollback',
      () async {
        _seed(file, unexplainedArchive: target);
        final beforeDb = sqlite.sqlite3.open(file.path);
        final before = _snapshot(beforeDb);
        final beforeSchema = _schema(beforeDb);
        beforeDb.close();
        final bytes = await file.readAsBytes();
        final failure = await open();
        expect(failure, isA<MailFailure<SqliteMailRepository>>());
        expect(
          (failure as MailFailure<SqliteMailRepository>).problem.code,
          MailProblemCode.storageFailure,
        );
        expect(await file.readAsBytes(), bytes);
        final after = sqlite.sqlite3.open(file.path);
        try {
          expect(after.userVersion, 15);
          expect(_snapshot(after), before);
          expect(_schema(after), beforeSchema);
        } finally {
          after.close();
        }
      },
    );
  }
}
