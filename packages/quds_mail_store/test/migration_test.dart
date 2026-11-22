@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:quds_mail_store/src/codec.dart';
import 'package:quds_mail_store/src/schema/database.dart'
    show schemaV1, schemaV2, schemaV3, schemaV4, schemaV5, schemaV8;
import 'package:quds_mail_store/src/schema/flag_journal_schema.dart'
    show schemaV6, schemaV7;
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:test/test.dart';

void main() {
  late Directory directory;
  late File file;

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    directory = await Directory.systemTemp.createTemp('quds-mail-migration-');
    file = File('${directory.path}/mail.sqlite3');
    _seedV1(file);
  });
  tearDown(() async => directory.delete(recursive: true));

  test(
    'v1 upgrade preserves scoped records, draft, cache and immutable queue bytes',
    () async {
      final before = _snapshot(file);
      final repository = _value(await _open(file));
      try {
        final headers = _value(await repository.listHeaders(_mailbox));
        expect(headers.map((header) => header.id.value), [
          'message-1',
          'message-2',
        ]);
        expect(headers.map((header) => header.flags), everyElement(isNull));
        expect(
          _value(await repository.readCursor(_mailbox))!.value,
          'original-cursor',
        );

        final draft = _value(await repository.loadDraft(_account, _draft.id))!;
        final restoredDraft = MailStoreCodec.encodeDraft(draft);
        expect(restoredDraft.data, MailStoreCodec.encodeDraft(_draft).data);
        expect(draft.revision, 9);
        expect(draft.envelope.bcc.single.address, 'hidden@example.test');
        expect(
          draft.attachments.map((part) => part.content.sha256),
          _draft.attachments.map((part) => part.content.sha256),
        );

        final cache = _value(
          await repository.loadCachedMessage(
            _account,
            MailMessageId('message-1'),
          ),
        )!;
        expect(cache.raw.bytes, _raw.bytes);
        expect(cache.raw.sha256, _raw.sha256);
        expect(cache.body.plainText, 'cachedneedle retained decoded content');
        expect(cache.attachments.single.content.bytes, _attachmentA.bytes);
        expect(cache.remoteIdentity, _remote(1));

        final queue = _value(await repository.recoverOutbox(_account)).single;
        expect(queue.state, MailOutboxState.queued);
        expect(
          MailStoreCodec.encodeOutbox(queue).data,
          MailStoreCodec.encodeOutbox(_queued).data,
        );
        expect(queue.prepared.wire.bytes, _queued.prepared.wire.bytes);
        expect(queue.prepared.envelope.recipients, [
          'one@example.test',
          'hidden@example.test',
        ]);
      } finally {
        await repository.close();
      }
      expect(_snapshot(file), before);
      final database = sqlite.sqlite3.open(file.path);
      try {
        expect(database.userVersion, 16);
        expect(database.select('PRAGMA foreign_key_check'), isEmpty);
        expect(
          database.select('SELECT count(*) AS n FROM mail_fts').single['n'],
          0,
        );
        expect(
          database.select('SELECT count(*) AS n FROM index_state').single['n'],
          0,
        );
      } finally {
        database.close();
      }
    },
  );

  test(
    'v2 upgrade preserves existing search and flags survive file reopen',
    () async {
      _upgradeFixtureV2(file);
      final before = _snapshot(file);
      var repository = _value(await _open(file));
      const observed = MailMessageFlags(
        isRead: true,
        isAnswered: true,
        isDraft: true,
      );
      try {
        expect(
          _value(await repository.search(_account, 'seeded')).single.header.id,
          MailMessageId('message-1'),
        );
        final headers = _value(await repository.listHeaders(_mailbox));
        expect(headers.map((header) => header.flags), everyElement(isNull));
        expect(headers.map((header) => header.remote), [
          _remote(1),
          _remote(2),
        ]);
        _value(
          await repository.commitSyncPage(
            MailSyncPage(
              mailbox: _mailbox,
              upserts: [
                MailHeaderRecord(
                  id: headers.first.id,
                  remote: headers.first.remote,
                  envelope: headers.first.envelope,
                  flags: observed,
                ),
              ],
              tombstones: [],
              next: MailCursor(mailbox: _mailbox, value: 'original-cursor'),
              hasMore: false,
            ),
            expectedCursor: _value(await repository.readCursor(_mailbox)),
            lease: MailAccountSession(_account).begin(),
          ),
        );
      } finally {
        await repository.close();
      }
      expect(_snapshot(file), before);

      repository = _value(await _open(file));
      try {
        final headers = _value(await repository.listHeaders(_mailbox));
        expect(headers.first.flags, observed);
        expect(headers.last.flags, isNull);
        expect(headers.first.remote, _remote(1));
        expect(
          _value(
            await repository.search(_account, 'alpha'),
          ).single.header.flags,
          observed,
        );
        final queue = _value(await repository.recoverOutbox(_account)).single;
        expect(queue.prepared.wire.bytes, _queued.prepared.wire.bytes);
        expect(
          _value(await repository.loadDraft(_account, _draft.id))!.revision,
          9,
        );
      } finally {
        await repository.close();
      }

      final database = sqlite.sqlite3.open(file.path);
      try {
        expect(database.userVersion, 16);
        expect(database.select('PRAGMA foreign_key_check'), isEmpty);
        for (final invalid in <Object?>[-1, 32, 0.5, 'invalid']) {
          expect(
            () => database.execute('UPDATE messages SET flags=?', [invalid]),
            throwsA(isA<sqlite.SqliteException>()),
          );
        }
        expect(
          database
              .select('SELECT flags FROM messages ORDER BY id')
              .map((row) => row['flags']),
          [13, null],
        );
      } finally {
        database.close();
      }
    },
  );

  test(
    'interrupted v2 flag migration rolls back the column and retains FTS',
    () async {
      _upgradeFixtureV2(file);
      final before = _snapshot(file);
      final failed = await _open(
        file,
        faultInjector: (checkpoint) {
          if (checkpoint == MailStoreCheckpoint.migrationCreated) {
            throw const MailStoreStorageException(
              MailProblemCode.storageFailure,
            );
          }
        },
      );
      expect(_problem(failed), MailProblemCode.storageFailure);
      expect(_snapshot(file), before);
      final database = sqlite.sqlite3.open(file.path);
      try {
        expect(database.userVersion, 2);
        expect(
          database
              .select('PRAGMA table_info(messages)')
              .map((row) => row['name']),
          isNot(contains('flags')),
        );
        expect(
          database.select('SELECT content FROM mail_fts').single['content'],
          'seeded retained index',
        );
      } finally {
        database.close();
      }
      final repository = _value(await _open(file));
      try {
        expect(
          _value(await repository.listHeaders(_mailbox)).first.flags,
          isNull,
        );
        expect(
          _value(await repository.search(_account, 'seeded')).single.header.id,
          MailMessageId('message-1'),
        );
      } finally {
        await repository.close();
      }
    },
  );

  test(
    'upgraded FTS requires bounded backfill without loading attachment or raw bytes',
    () async {
      final capture = _SelectCapture();
      final repository = _value(await _open(file, capture: capture));
      try {
        expect(
          _value(await repository.search(_account, 'cachedneedle')),
          isEmpty,
        );
        expect(_value(await repository.search(_account, 'beta')), isEmpty);
        capture.statements.clear();
        expect(_value(await repository.reindex(_account, limit: 1)), 1);
        expect(
          _value(
            await repository.search(_account, 'cachedneedle'),
          ).single.header.id.value,
          'message-1',
        );
        expect(_value(await repository.search(_account, 'beta')), isEmpty);
        expect(capture.payloadSelects, isEmpty);
        expect(_value(await repository.reindex(_account, limit: 1)), 1);
        expect(
          _value(
            await repository.search(_account, 'beta'),
          ).single.header.id.value,
          'message-2',
        );
        expect(_value(await repository.reindex(_account, limit: 1)), 0);
        expect(capture.payloadSelects, isEmpty);
        expect(
          _problem(await repository.reindex(_account, limit: 0)),
          MailProblemCode.invalidInput,
        );
      } finally {
        await repository.close();
      }
    },
  );

  test(
    'interrupted v1 migration rolls back schema and version, then retries without losing data',
    () async {
      final before = _snapshot(file);
      var injected = false;
      final failed = await _open(
        file,
        faultInjector: (checkpoint) {
          if (checkpoint == MailStoreCheckpoint.migrationCreated) {
            injected = true;
            throw const MailStoreStorageException(
              MailProblemCode.quotaExceeded,
            );
          }
        },
      );
      expect(injected, isTrue);
      expect(_problem(failed), MailProblemCode.quotaExceeded);
      expect(_snapshot(file), before);
      final database = sqlite.sqlite3.open(file.path);
      try {
        expect(database.userVersion, 1);
        expect(
          database.select(
            "SELECT name FROM sqlite_master WHERE name LIKE 'mail_fts%' OR name='index_state'",
          ),
          isEmpty,
        );
        expect(database.select('PRAGMA foreign_key_check'), isEmpty);
      } finally {
        database.close();
      }

      final reopened = _value(await _open(file));
      try {
        final restored = _value(await reopened.loadDraft(_account, _draft.id))!;
        expect(restored.attachments.first.content.bytes, _attachmentA.bytes);
        expect(
          _value(
            await reopened.recoverOutbox(_account),
          ).single.prepared.wireHash,
          _queued.prepared.wireHash,
        );
      } finally {
        await reopened.close();
      }
      expect(_snapshot(file), before);
      final upgraded = sqlite.sqlite3.open(file.path);
      try {
        expect(upgraded.userVersion, 16);
      } finally {
        upgraded.close();
      }
    },
  );

  for (final interrupted in [false, true]) {
    test(
      'v3 account-directory migration preserves all content; interrupted=$interrupted',
      () async {
        _upgradeFixtureV2(file);
        final old = sqlite.sqlite3.open(file.path);
        for (final statement in schemaV3) {
          old.execute(statement);
        }
        old.execute('UPDATE messages SET flags=3');
        old.userVersion = 3;
        old.close();
        final before = _snapshot(file);
        if (interrupted) {
          final failed = await _open(
            file,
            faultInjector: (point) {
              if (point == MailStoreCheckpoint.migrationCreated) {
                throw const MailStoreStorageException(
                  MailProblemCode.storageFailure,
                );
              }
            },
          );
          expect(_problem(failed), MailProblemCode.storageFailure);
          final check = sqlite.sqlite3.open(file.path);
          expect(check.userVersion, 3);
          expect(
            check
                .select('PRAGMA table_info(store_profile)')
                .map((row) => row['name']),
            isNot(contains('local_account_revision')),
          );
          expect(
            check.select(
              "SELECT name FROM sqlite_master WHERE name='local_accounts'",
            ),
            isEmpty,
          );
          check.close();
          expect(_snapshot(file), before);
        }
        final repository = _value(await _open(file));
        expect(_value(await repository.listLocalAccounts()), isEmpty);
        expect(
          _value(
            await repository.listHeaders(_mailbox),
          ).map((row) => row.flags!.isRead),
          everyElement(isTrue),
        );
        expect(
          _value(
            await repository.loadDraft(_account, _draft.id),
          )!.attachments.first.content.bytes,
          _attachmentA.bytes,
        );
        expect(
          _value(
            await repository.recoverOutbox(_account),
          ).single.prepared.wireHash,
          _queued.prepared.wireHash,
        );
        expect(
          _value(await repository.search(_account, 'seeded')).single.header.id,
          MailMessageId('message-1'),
        );
        await repository.close();
        expect(_snapshot(file), before);
        final current = sqlite.sqlite3.open(file.path);
        expect(current.userVersion, 16);
        expect(current.select('PRAGMA foreign_key_check'), isEmpty);
        expect(
          current
              .select('SELECT flags FROM messages')
              .map((row) => row['flags']),
          everyElement(3),
        );
        current.close();
      },
    );
  }

  for (final interrupted in [false, true]) {
    test(
      'v4 mailbox-view migration preserves all original data; interrupted=$interrupted',
      () async {
        _upgradeFixtureV2(file);
        final old = sqlite.sqlite3.open(file.path);
        for (final statement in [...schemaV3, ...schemaV4]) {
          old.execute(statement);
        }
        old.execute('UPDATE messages SET flags=3');
        old.execute('UPDATE store_profile SET local_account_revision=67');
        old.execute(
          'INSERT INTO local_accounts(id,provider,endpoint,login,sender,connected_at,revision) '
          'VALUES(?,?,?,?,?,?,?)',
          [
            'verified',
            'imap',
            'imaps://imap.example.test:993',
            'Login',
            'sender@example.test',
            1234,
            67,
          ],
        );
        old.userVersion = 4;
        old.close();
        Map<String, List<List<Object?>>> original() {
          final database = sqlite.sqlite3.open(file.path);
          try {
            if (database.userVersion >= 5) {
              expect(
                database
                    .select('SELECT mailbox_view_revision FROM store_profile')
                    .single['mailbox_view_revision'],
                0,
              );
            }
            return {
              for (final table in [
                'store_profile',
                'accounts',
                'mailboxes',
                'messages',
                'memberships',
                'cursors',
                'tombstones',
                'blobs',
                'blob_refs',
                'cached_messages',
                'drafts',
                'outbox',
                'outbox_attempts',
                'pending_operations',
                'credential_cleanup',
                'mail_fts',
                'index_state',
                'local_accounts',
              ])
                table: [
                  for (final row in database.select(
                    table == 'store_profile'
                        ? 'SELECT singleton,host_id,profile_id,removed,local_account_revision '
                              'FROM store_profile ORDER BY rowid'
                        : 'SELECT * FROM $table ORDER BY rowid',
                  ))
                    [
                      for (final Object? value in row.values)
                        value is Uint8List ? Uint8List.fromList(value) : value,
                    ],
                ],
            };
          } finally {
            database.close();
          }
        }

        final before = original();
        if (interrupted) {
          final failed = await _open(
            file,
            faultInjector: (point) {
              if (point == MailStoreCheckpoint.migrationCreated) {
                throw const MailStoreStorageException(
                  MailProblemCode.storageFailure,
                );
              }
            },
          );
          expect(_problem(failed), MailProblemCode.storageFailure);
          expect(original(), before);
          final check = sqlite.sqlite3.open(file.path);
          try {
            expect(check.userVersion, 4);
            expect(
              check.select(
                "SELECT name FROM sqlite_master WHERE name LIKE 'mailbox_view%'",
              ),
              isEmpty,
            );
          } finally {
            check.close();
          }
        }
        final repository = _value(await _open(file));
        try {
          expect(_value(await repository.listMailboxViews(_account)), isEmpty);
          expect(_value(await repository.loadMailboxView(_mailbox)), isNull);
          expect(
            _value(await repository.listLocalAccounts()).single.revision,
            67,
          );
          expect(
            _value(
              await repository.loadDraft(_account, _draft.id),
            )!.attachments.first.content.bytes,
            _attachmentA.bytes,
          );
          expect(
            _value(
              await repository.recoverOutbox(_account),
            ).single.prepared.wireHash,
            _queued.prepared.wireHash,
          );
          expect(
            _value(
              await repository.loadCachedMessage(
                _account,
                MailMessageId('message-1'),
              ),
            )!.raw.sha256,
            _raw.sha256,
          );
        } finally {
          await repository.close();
        }
        expect(original(), before);
        final current = sqlite.sqlite3.open(file.path);
        try {
          expect(current.userVersion, 16);
          expect(current.select('PRAGMA foreign_key_check'), isEmpty);
          expect(
            current.select(
              "SELECT name FROM sqlite_master WHERE type='table' AND name LIKE 'mailbox_view%'",
            ),
            hasLength(2),
          );
        } finally {
          current.close();
        }
      },
    );
  }

  for (final interrupted in [false, true]) {
    test(
      'v5 journal migration preserves cached views and all local work; interrupted=$interrupted',
      () async {
        _upgradeFixtureV2(file);
        final old = sqlite.sqlite3.open(file.path);
        for (final statement in [...schemaV3, ...schemaV4, ...schemaV5]) {
          old.execute(statement);
        }
        old.execute('UPDATE messages SET flags=7');
        old.execute('UPDATE store_profile SET mailbox_view_revision=17');
        old.execute(
          'INSERT INTO mailbox_views(account,mailbox,revision,captured_at,header_count,has_more) VALUES(?,?,?,?,?,?)',
          [_account.value, _mailbox.value, 17, 123456, 1, 1],
        );
        old.execute(
          'INSERT INTO mailbox_view_members(account,mailbox,position,message) VALUES(?,?,0,?)',
          [_account.value, _mailbox.value, 'message-1'],
        );
        old.userVersion = 5;
        old.close();
        Map<String, List<List<Object?>>> original() {
          final database = sqlite.sqlite3.open(file.path);
          try {
            return {
              for (final table in [
                'store_profile',
                'accounts',
                'mailboxes',
                'messages',
                'memberships',
                'cursors',
                'tombstones',
                'blobs',
                'blob_refs',
                'cached_messages',
                'drafts',
                'outbox',
                'outbox_attempts',
                'pending_operations',
                'credential_cleanup',
                'local_accounts',
                'mailbox_views',
                'mailbox_view_members',
                'mail_fts',
                'index_state',
              ])
                table: [
                  for (final row in database.select(
                    table == 'store_profile'
                        ? 'SELECT singleton,host_id,profile_id,removed,local_account_revision,mailbox_view_revision FROM store_profile ORDER BY rowid'
                        : 'SELECT * FROM $table ORDER BY rowid',
                  ))
                    [
                      for (final Object? value in row.values)
                        value is Uint8List ? Uint8List.fromList(value) : value,
                    ],
                ],
            };
          } finally {
            database.close();
          }
        }

        final before = original();
        if (interrupted) {
          final failed = await _open(
            file,
            faultInjector: (point) {
              if (point == MailStoreCheckpoint.migrationCreated) {
                throw const MailStoreStorageException(
                  MailProblemCode.storageFailure,
                );
              }
            },
          );
          expect(_problem(failed), MailProblemCode.storageFailure);
          expect(original(), before);
          final check = sqlite.sqlite3.open(file.path);
          try {
            expect(check.userVersion, 5);
            expect(
              check.select(
                "SELECT name FROM sqlite_master WHERE name LIKE 'flag_batch%'",
              ),
              isEmpty,
            );
          } finally {
            check.close();
          }
        }
        final repository = _value(await _open(file));
        try {
          expect(
            _value(await repository.listFlagBatches(_account)).batches,
            isEmpty,
          );
          final view = _value(await repository.loadMailboxView(_mailbox))!;
          expect(view.revision, 17);
          expect(view.hasMore, isTrue);
          expect(view.headers.single.flags!.isRead, isTrue);
          expect(view.headers.single.flags!.isFlagged, isTrue);
          expect(
            _value(
              await repository.recoverOutbox(_account),
            ).single.prepared.wire.bytes,
            _queued.prepared.wire.bytes,
          );
        } finally {
          await repository.close();
        }
        expect(original(), before);
        final check = sqlite.sqlite3.open(file.path);
        try {
          expect(check.userVersion, 16);
          expect(check.select('PRAGMA foreign_key_check'), isEmpty);
        } finally {
          check.close();
        }
      },
    );
  }

  for (final interrupted in [false, true]) {
    test(
      'v8 saved-search migration preserves all existing tables; interrupted=$interrupted',
      () async {
        _upgradeFixtureV2(file);
        final old = sqlite.sqlite3.open(file.path);
        try {
          for (final statement in [
            ...schemaV3,
            ...schemaV4,
            ...schemaV5,
            ...schemaV6,
            ...schemaV7,
            ...schemaV8,
          ]) {
            old.execute(statement);
          }
          old.execute('UPDATE messages SET flags=3');
          old.execute(
            'UPDATE store_profile SET local_account_revision=7,mailbox_view_revision=17',
          );
          old.execute(
            'INSERT INTO local_accounts(id,provider,endpoint,login,sender,connected_at,revision) VALUES(?,?,?,?,?,?,?)',
            [
              'verified',
              'imap',
              'imaps://imap.example.test:993',
              'login',
              'me@example.test',
              1234,
              7,
            ],
          );
          old.execute(
            'INSERT INTO mailbox_views(account,mailbox,revision,captured_at,header_count,has_more) VALUES(?,?,?,?,?,?)',
            [_account.value, _mailbox.value, 17, 1234, 1, 1],
          );
          old.execute(
            'INSERT INTO mailbox_view_members(account,mailbox,position,message) VALUES(?,?,0,?)',
            [_account.value, _mailbox.value, 'message-1'],
          );
          old.execute(
            'INSERT INTO mailbox_sync_state(account,mailbox,revision,updated_at,has_more) VALUES(?,?,?,?,?)',
            [_account.value, _mailbox.value, 29, 5678, 1],
          );
          old.userVersion = 8;
        } finally {
          old.close();
        }
        final tables = <String, List<String>>{};
        final initial = sqlite.sqlite3.open(file.path);
        try {
          for (final row in initial.select(
            "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
          )) {
            final name = row['name']! as String;
            tables[name] = [
              for (final column in initial.select('PRAGMA table_info("$name")'))
                column['name']! as String,
            ];
          }
        } finally {
          initial.close();
        }
        Map<String, List<List<Object?>>> snapshotV8() {
          final database = sqlite.sqlite3.open(file.path);
          try {
            return {
              for (final table in tables.entries)
                table.key: [
                  for (final row in database.select(
                    'SELECT ${table.value.map((name) => '"$name"').join(',')} FROM "${table.key}" '
                    'ORDER BY ${table.value.map((name) => '"$name"').join(',')}',
                  ))
                    [
                      for (final value in row.values)
                        value is Uint8List ? Uint8List.fromList(value) : value,
                    ],
                ],
            };
          } finally {
            database.close();
          }
        }

        final before = snapshotV8();
        if (interrupted) {
          final failed = await _open(
            file,
            faultInjector: (point) {
              if (point == MailStoreCheckpoint.migrationCreated) {
                throw const MailStoreStorageException(
                  MailProblemCode.storageFailure,
                );
              }
            },
          );
          expect(_problem(failed), MailProblemCode.storageFailure);
          final check = sqlite.sqlite3.open(file.path);
          try {
            expect(check.userVersion, 8);
            expect(
              check.select(
                "SELECT name FROM sqlite_master WHERE name LIKE 'saved_header_search%'",
              ),
              isEmpty,
            );
            expect(
              check
                  .select('PRAGMA table_info(store_profile)')
                  .map((row) => row['name']),
              isNot(contains('saved_header_search_revision')),
            );
          } finally {
            check.close();
          }
          expect(snapshotV8(), before);
        }
        final repository = _value(await _open(file));
        try {
          expect(_value(await repository.listSavedHeaderSearches()), isEmpty);
          final saved = _value(
            await repository.saveSavedHeaderSearch(
              MailSavedHeaderSearch(
                id: 'view',
                name: 'Saved unread',
                query: 'is:unread',
                accountIds: ['verified'],
              ),
            ),
          );
          expect(saved.revision, 1);
          expect(
            _value(await repository.listLocalAccounts()).single.revision,
            7,
          );
          expect(
            _value(await repository.readCursor(_mailbox))!.value,
            'original-cursor',
          );
          expect(
            _value(
              await repository.loadDraft(_account, _draft.id),
            )!.attachments.first.content.bytes,
            _attachmentA.bytes,
          );
          expect(
            _value(
              await repository.recoverOutbox(_account),
            ).single.prepared.wireHash,
            _queued.prepared.wireHash,
          );
        } finally {
          await repository.close();
        }
        expect(snapshotV8(), before);
        final current = sqlite.sqlite3.open(file.path);
        try {
          expect(current.userVersion, 16);
          expect(current.select('PRAGMA foreign_key_check'), isEmpty);
          expect(
            current
                .select('SELECT revision FROM mailbox_sync_state')
                .single['revision'],
            29,
          );
          expect(
            current
                .select('SELECT account_id FROM saved_header_search_accounts')
                .single['account_id'],
            'verified',
          );
        } finally {
          current.close();
        }
      },
    );
  }

  for (final version in [16, 17]) {
    test(
      'future schema $version is rejected without changing existing data',
      () async {
        final database = sqlite.sqlite3.open(file.path);
        try {
          database.execute('CREATE TABLE future_marker (value TEXT NOT NULL)');
          database.execute('INSERT INTO future_marker(value) VALUES(?)', [
            'future-only-preserved',
          ]);
          database.userVersion = version;
        } finally {
          database.close();
        }
        final before = await file.readAsBytes();
        expect(_problem(await _open(file)), MailProblemCode.unsupported);
        expect(await file.readAsBytes(), before);
        final reopened = sqlite.sqlite3.open(file.path);
        try {
          expect(reopened.userVersion, version);
          expect(
            reopened.select('SELECT value FROM future_marker').single['value'],
            'future-only-preserved',
          );
        } finally {
          reopened.close();
        }
      },
    );
  }

  for (final (name, limits) in <(String, MailStoreLimits)>[
    ('individual blob', const MailStoreLimits(maxBlobBytes: 63)),
    (
      'aggregate payload',
      const MailStoreLimits(maxBlobBytes: 64, maxTransactionBlobBytes: 64),
    ),
  ]) {
    test(
      'stricter $name limits reject persisted draft before transferring blobs',
      () async {
        final capture = _SelectCapture();
        final repository = _value(
          await _open(file, limits: limits, capture: capture),
        );
        try {
          capture.statements.clear();
          expect(
            _problem(await repository.loadDraft(_account, _draft.id)),
            MailProblemCode.quotaExceeded,
          );
          expect(
            capture.statements.any((sql) => sql.contains('length(b.data)')),
            isTrue,
          );
          expect(capture.payloadSelects, isEmpty);
        } finally {
          await repository.close();
        }

        // Positive control: the same persisted draft is intact and ordinary
        // retrieval actually transfers its blobs when the read limits allow it.
        final normal = _value(await _open(file, capture: capture));
        try {
          capture.statements.clear();
          final draft = _value(await normal.loadDraft(_account, _draft.id))!;
          expect(draft.attachments.first.content.bytes, _attachmentA.bytes);
          expect(draft.attachments.last.content.bytes, _attachmentB.bytes);
          expect(capture.payloadSelects, isNotEmpty);
        } finally {
          await normal.close();
        }
      },
    );
  }
}

final _profile = MailProfileId('migration-profile', hostId: 'office-test');
final _account = MailAccountId('account', profile: _profile);
final _mailbox = MailMailboxId('inbox', account: _account);
final _attachmentA = MailBytes(Uint8List.fromList(List.generate(64, (i) => i)));
final _attachmentB = MailBytes(
  Uint8List.fromList(List.generate(32, (i) => 255 - i)),
);
final _raw = MailBytes(
  Uint8List.fromList(
    ascii.encode('Subject: Migration alpha\r\n\r\nOriginal cached source\r\n'),
  ),
);

MailImapIdentity _remote(int uid) =>
    MailImapIdentity(mailbox: _mailbox, uidValidity: 7, uid: uid);

final _draft = MailDraft(
  id: 'draft-9',
  account: _account,
  revision: 9,
  envelope: MailEnvelope(
    subject: 'مسودة محفوظة',
    from: const [MailAddress('sender@example.test', displayName: 'Sender')],
    to: const [MailAddress('one@example.test')],
    bcc: const [MailAddress('hidden@example.test')],
    sentAt: DateTime.utc(2026, 11, 18, 12, 5, 8, 9, 10),
  ),
  body: const MailBody(
    plainText: 'Unsent work\nمرحبا',
    html: '<p>Unsent work</p>',
  ),
  attachments: [
    MailAttachment(
      partPath: '2',
      mediaType: 'application/octet-stream',
      displayName: 'first.bin',
      content: _attachmentA,
    ),
    MailAttachment(
      partPath: '3',
      mediaType: 'application/octet-stream',
      displayName: 'second.bin',
      content: _attachmentB,
    ),
  ],
);

final _queued = MailOutboxEntry.queued(
  id: 'queued',
  prepared: MailPreparedMessage(
    account: _account,
    draftId: _draft.id,
    draftRevision: _draft.revision,
    wire: MailBytes(
      Uint8List.fromList(
        ascii.encode(
          'From: sender@example.test\r\nSubject: Frozen\r\n\r\nFrozen wire\r\n',
        ),
      ),
    ),
    envelope: MailTransportEnvelope(
      sender: 'sender@example.test',
      recipients: ['one@example.test', 'hidden@example.test'],
    ),
  ),
  now: DateTime.utc(2026, 11, 18),
);

void _seedV1(File file) {
  final database = sqlite.sqlite3.open(file.path);
  try {
    database.execute('PRAGMA foreign_keys=ON');
    database.execute('BEGIN');
    for (final statement in schemaV1) {
      database.execute(statement);
    }
    database.execute(
      'INSERT INTO store_profile(singleton,host_id,profile_id) VALUES(1,?,?)',
      [_profile.hostId, _profile.value],
    );
    database.execute(
      'INSERT INTO accounts(id,provider,display_name,credential_ref,state) VALUES(?,?,?,?,?)',
      [
        _account.value,
        'imap',
        'Migration account',
        'opaque-vault-ref',
        'active',
      ],
    );
    database.execute(
      'INSERT INTO mailboxes(account,id,display_name) VALUES(?,?,?)',
      [_account.value, _mailbox.value, 'Inbox'],
    );
    for (final (uid, subject) in [
      (1, 'Migration alpha'),
      (2, 'Migration beta'),
    ]) {
      database.execute(
        'INSERT INTO messages(account,id,remote,envelope) VALUES(?,?,?,?)',
        [
          _account.value,
          'message-$uid',
          MailStoreCodec.encodeRemote(_remote(uid)),
          MailStoreCodec.encodeEnvelope(MailEnvelope(subject: subject)),
        ],
      );
      database.execute(
        'INSERT INTO memberships(account,mailbox,message) VALUES(?,?,?)',
        [_account.value, _mailbox.value, 'message-$uid'],
      );
    }
    database.execute(
      'INSERT INTO cursors(account,mailbox,cursor) VALUES(?,?,?)',
      [_account.value, _mailbox.value, 'original-cursor'],
    );

    final draft = MailStoreCodec.encodeDraft(_draft);
    _seedPayload(database, 'draft', _draft.id, draft);
    database.execute(
      'INSERT INTO drafts(account,id,revision,data) VALUES(?,?,?,?)',
      [_account.value, _draft.id, _draft.revision, draft.data],
    );
    final queue = MailStoreCodec.encodeOutbox(_queued);
    _seedPayload(database, 'outbox', _queued.id, queue);
    database.execute(
      'INSERT INTO outbox(account,id,state,attempt_id,data) VALUES(?,?,?,?,?)',
      [_account.value, _queued.id, 'queued', null, queue.data],
    );

    final cache = MailStoreCodec.encodeDraft(
      MailDraft(
        id: 'message-1',
        account: _account,
        revision: 0,
        envelope: MailEnvelope(subject: 'Migration alpha'),
        body: const MailBody(
          plainText: 'cachedneedle retained decoded content',
        ),
        attachments: [_draft.attachments.first],
      ),
    );
    _seedPayload(
      database,
      'cache',
      'message-1',
      MailStorePayload(
        data: cache.data,
        blobs: {...cache.blobs, _raw.sha256: _raw},
      ),
    );
    database.execute(
      'INSERT INTO cached_messages(account,message,raw_hash,data) VALUES(?,?,?,?)',
      [_account.value, 'message-1', _raw.sha256, cache.data],
    );
    database.userVersion = 1;
    database.execute('COMMIT');
  } finally {
    database.close();
  }
}

void _seedPayload(
  sqlite.Database database,
  String kind,
  String id,
  MailStorePayload payload,
) {
  for (final entry in payload.blobs.entries) {
    database.execute(
      'INSERT INTO blobs(account,hash,data,size) VALUES(?,?,?,?) ON CONFLICT DO NOTHING',
      [_account.value, entry.key, entry.value.bytes, entry.value.length],
    );
    database.execute(
      'INSERT INTO blob_refs(account,owner_kind,owner_id,hash) VALUES(?,?,?,?)',
      [_account.value, kind, id, entry.key],
    );
  }
}

void _upgradeFixtureV2(File file) {
  final database = sqlite.sqlite3.open(file.path);
  try {
    database.execute('BEGIN');
    for (final statement in schemaV2) {
      database.execute(statement);
    }
    database.execute(
      'INSERT INTO mail_fts(account,message,content) VALUES(?,?,?)',
      [_account.value, 'message-1', 'seeded retained index'],
    );
    database.execute('INSERT INTO index_state(account,message) VALUES(?,?)', [
      _account.value,
      'message-1',
    ]);
    database.userVersion = 2;
    database.execute('COMMIT');
  } finally {
    database.close();
  }
}

Future<MailResult<SqliteMailRepository>> _open(
  File file, {
  MailStoreLimits limits = const MailStoreLimits(),
  MailStoreFaultInjector? faultInjector,
  _SelectCapture? capture,
}) {
  QueryExecutor executor = NativeDatabase(file);
  if (capture != null) executor = executor.interceptWith(capture);
  return SqliteMailRepository.open(
    executor: executor,
    profile: _profile,
    limits: limits,
    faultInjector: faultInjector,
  );
}

Map<String, List<List<Object?>>> _snapshot(File file) {
  final database = sqlite.sqlite3.open(file.path);
  try {
    if (database.userVersion >= 5) {
      expect(
        database
            .select('SELECT mailbox_view_revision FROM store_profile')
            .single['mailbox_view_revision'],
        0,
      );
    }
    if (database.userVersion >= 4) {
      expect(
        database
            .select('SELECT local_account_revision FROM store_profile')
            .single['local_account_revision'],
        0,
      );
    }
    return {
      for (final table in const [
        'store_profile',
        'accounts',
        'mailboxes',
        'messages',
        'memberships',
        'cursors',
        'tombstones',
        'blobs',
        'blob_refs',
        'cached_messages',
        'drafts',
        'outbox',
        'outbox_attempts',
        'pending_operations',
        'credential_cleanup',
      ])
        table: [
          for (final row in database.select(
            // Preserve every pre-existing column across the additive v3/v4
            // migrations. Flags and the new counter are checked separately.
            switch (table) {
              'messages' =>
                'SELECT account,id,remote,envelope FROM messages ORDER BY rowid',
              'store_profile' =>
                'SELECT singleton,host_id,profile_id,removed FROM store_profile ORDER BY rowid',
              _ => 'SELECT * FROM $table ORDER BY rowid',
            },
          ))
            [
              for (final Object? value in row.values)
                value is Uint8List ? Uint8List.fromList(value) : value,
            ],
        ],
    };
  } finally {
    database.close();
  }
}

T _value<T>(MailResult<T> result) {
  expect(result, isA<MailSuccess<T>>());
  return (result as MailSuccess<T>).value;
}

MailProblemCode _problem<T>(MailResult<T> result) {
  expect(result, isA<MailFailure<T>>());
  return (result as MailFailure<T>).problem.code;
}

final class _SelectCapture extends QueryInterceptor {
  final List<String> statements = [];

  Iterable<String> get payloadSelects => statements.where((statement) {
    if (!statement.contains('FROM blobs')) return false;
    final projection = statement
        .split(' FROM ')
        .first
        .replaceAll(RegExp(r'length\([^)]*\)'), '');
    return RegExp(r'\bdata\b|\*').hasMatch(projection);
  });

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    statements.add(statement);
    return super.runSelect(executor, statement, args);
  }
}
