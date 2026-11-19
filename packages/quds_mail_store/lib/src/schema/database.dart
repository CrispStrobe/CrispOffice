import 'package:drift/drift.dart';
import 'package:quds_mail_core/quds_mail_core.dart';

import '../errors.dart';
import '../models.dart';

/// Explicit SQL schema; public access is through typed repository DTOs.
/// Drift owns query execution and transaction zones. The repository publishes
/// domain notifications only after successful commit, outside the transaction.
final class MailStoreDatabase extends GeneratedDatabase {
  MailStoreDatabase(super.executor, {this.faultInjector});

  final MailStoreFaultInjector? faultInjector;

  @override
  int get schemaVersion => 3;

  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (_) => transaction(() async {
      for (final statement in schemaV1) {
        await customStatement(statement);
      }
      await faultInjector?.call(MailStoreCheckpoint.migrationCreated);
      for (final statement in schemaV2) {
        await customStatement(statement);
      }
      for (final statement in schemaV3) {
        await customStatement(statement);
      }
      // Include the version in the same transaction as schema creation.
      await customStatement('PRAGMA user_version = 3');
    }),
    onUpgrade: (_, from, to) async {
      if ((from != 1 && from != 2) || to != 3) {
        throw const MailStoreStorageException(MailProblemCode.unsupported);
      }
      await transaction(() async {
        if (from == 1) {
          for (final statement in schemaV2) {
            await customStatement(statement);
          }
        }
        for (final statement in schemaV3) {
          await customStatement(statement);
        }
        await faultInjector?.call(MailStoreCheckpoint.migrationCreated);
        await customStatement('PRAGMA user_version = 3');
      });
    },
    beforeOpen: (_) async {
      await customStatement('PRAGMA foreign_keys = ON');
      await customStatement('PRAGMA busy_timeout = 5000');
      // Fail explicitly when an injected/host SQLite lacks the required FTS5.
      await customSelect('SELECT rowid FROM mail_fts LIMIT 1').get();
    },
  );

  Future<void> fault(MailStoreCheckpoint point) async {
    await faultInjector?.call(point);
  }
}

/// Kept immutable for reproducible upgrade fixtures. No released schema is reset.
const schemaV1 = <String>[
  '''CREATE TABLE store_profile (
    singleton INTEGER PRIMARY KEY CHECK(singleton = 1),
    host_id TEXT NOT NULL, profile_id TEXT NOT NULL,
    removed INTEGER NOT NULL DEFAULT 0 CHECK(removed IN (0,1))
  )''',
  '''CREATE TABLE accounts (
    id TEXT PRIMARY KEY, provider TEXT NOT NULL, display_name TEXT NOT NULL,
    credential_ref TEXT, state TEXT NOT NULL
      CHECK(state IN ('active','loggedOut','removed'))
  )''',
  '''CREATE TABLE mailboxes (
    account TEXT NOT NULL REFERENCES accounts(id), id TEXT NOT NULL,
    display_name TEXT NOT NULL, is_label INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY(account,id)
  )''',
  '''CREATE TABLE messages (
    account TEXT NOT NULL REFERENCES accounts(id), id TEXT NOT NULL,
    remote TEXT NOT NULL, envelope TEXT NOT NULL,
    PRIMARY KEY(account,id), UNIQUE(account,remote)
  )''',
  '''CREATE TABLE memberships (
    account TEXT NOT NULL, mailbox TEXT NOT NULL, message TEXT NOT NULL,
    PRIMARY KEY(account,mailbox,message),
    FOREIGN KEY(account,mailbox) REFERENCES mailboxes(account,id) ON DELETE CASCADE,
    FOREIGN KEY(account,message) REFERENCES messages(account,id) ON DELETE CASCADE
  )''',
  '''CREATE TABLE cursors (
    account TEXT NOT NULL, mailbox TEXT NOT NULL, cursor TEXT NOT NULL,
    PRIMARY KEY(account,mailbox),
    FOREIGN KEY(account,mailbox) REFERENCES mailboxes(account,id) ON DELETE CASCADE
  )''',
  '''CREATE TABLE tombstones (
    account TEXT NOT NULL REFERENCES accounts(id), mailbox TEXT NOT NULL,
    remote TEXT NOT NULL, observed_at INTEGER NOT NULL,
    PRIMARY KEY(account,mailbox,remote)
  )''',
  '''CREATE TABLE blobs (
    account TEXT NOT NULL REFERENCES accounts(id), hash TEXT NOT NULL,
    data BLOB NOT NULL, size INTEGER NOT NULL CHECK(size >= 0),
    PRIMARY KEY(account,hash), CHECK(length(data) = size)
  )''',
  '''CREATE TABLE blob_refs (
    account TEXT NOT NULL, owner_kind TEXT NOT NULL, owner_id TEXT NOT NULL,
    hash TEXT NOT NULL,
    PRIMARY KEY(account,owner_kind,owner_id,hash),
    FOREIGN KEY(account,hash) REFERENCES blobs(account,hash) ON DELETE CASCADE
  )''',
  '''CREATE TABLE cached_messages (
    account TEXT NOT NULL, message TEXT NOT NULL, raw_hash TEXT NOT NULL,
    data TEXT NOT NULL,
    PRIMARY KEY(account,message),
    FOREIGN KEY(account,message) REFERENCES messages(account,id) ON DELETE CASCADE,
    FOREIGN KEY(account,raw_hash) REFERENCES blobs(account,hash)
  )''',
  '''CREATE TABLE drafts (
    account TEXT NOT NULL REFERENCES accounts(id), id TEXT NOT NULL,
    revision INTEGER NOT NULL CHECK(revision >= 0), data TEXT NOT NULL,
    PRIMARY KEY(account,id)
  )''',
  '''CREATE TABLE outbox (
    account TEXT NOT NULL REFERENCES accounts(id), id TEXT NOT NULL,
    state TEXT NOT NULL, attempt_id TEXT, data TEXT NOT NULL,
    PRIMARY KEY(account,id)
  )''',
  '''CREATE TABLE outbox_attempts (
    account TEXT NOT NULL, outbox TEXT NOT NULL, attempt_id TEXT NOT NULL,
    PRIMARY KEY(account,outbox,attempt_id),
    FOREIGN KEY(account,outbox) REFERENCES outbox(account,id) ON DELETE CASCADE
  )''',
  '''CREATE TABLE pending_operations (
    account TEXT NOT NULL REFERENCES accounts(id), id TEXT NOT NULL,
    remote TEXT NOT NULL, kind TEXT NOT NULL, argument TEXT,
    state TEXT NOT NULL, revision INTEGER NOT NULL,
    created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
    PRIMARY KEY(account,id)
  )''',
  '''CREATE TABLE credential_cleanup (
    account TEXT NOT NULL REFERENCES accounts(id), reference TEXT NOT NULL,
    PRIMARY KEY(account,reference)
  )''',
  'CREATE INDEX membership_message ON memberships(account,message)',
  'CREATE INDEX pending_remote ON pending_operations(account,remote,state)',
  'CREATE INDEX blob_reference_hash ON blob_refs(account,hash)',
];

/// FTS5 indexes bounded metadata and plain text only. The v1->v2 migration
/// preserves content; the host explicitly backfills with bounded reindex calls.
const schemaV2 = <String>[
  '''CREATE VIRTUAL TABLE mail_fts USING fts5(
    account UNINDEXED, message UNINDEXED, content,
    tokenize = 'unicode61 remove_diacritics 2'
  )''',
  '''CREATE TABLE index_state (
    account TEXT NOT NULL, message TEXT NOT NULL,
    PRIMARY KEY(account,message),
    FOREIGN KEY(account,message) REFERENCES messages(account,id) ON DELETE CASCADE
  )''',
];

/// Existing v1/v2 rows have unknown flags until a provider observes them. The
/// constrained bitset adds no invented read/unread or deletion state.
const schemaV3 = <String>[
  '''ALTER TABLE messages ADD COLUMN flags INTEGER
    CHECK(flags IS NULL OR (typeof(flags) = 'integer' AND flags BETWEEN 0 AND 31))''',
];
