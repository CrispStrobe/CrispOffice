import 'package:drift/drift.dart';
import 'package:quds_mail_core/quds_mail_core.dart';

import '../errors.dart';
import '../models.dart';
import 'flag_journal_schema.dart';
import 'membership_observation_schema.dart';

/// Explicit SQL schema; public access is through typed repository DTOs.
/// Drift owns query execution and transaction zones. The repository publishes
/// domain notifications only after successful commit, outside the transaction.
final class MailStoreDatabase extends GeneratedDatabase {
  MailStoreDatabase(super.executor, {this.faultInjector});

  final MailStoreFaultInjector? faultInjector;

  @override
  int get schemaVersion => 14;

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
      for (final statement in schemaV4) {
        await customStatement(statement);
      }
      for (final statement in schemaV5) {
        await customStatement(statement);
      }
      for (final statement in schemaV6) {
        await customStatement(statement);
      }
      for (final statement in schemaV7) {
        await customStatement(statement);
      }
      for (final statement in schemaV8) {
        await customStatement(statement);
      }
      for (final statement in schemaV9) {
        await customStatement(statement);
      }
      for (final statement in schemaV10) {
        await customStatement(statement);
      }
      for (final statement in schemaV11) {
        await customStatement(statement);
      }
      for (final statement in schemaV12) {
        await customStatement(statement);
      }
      for (final statement in schemaV13) {
        await customStatement(statement);
      }
      for (final statement in schemaV14) {
        await customStatement(statement);
      }
      // Include the version in the same transaction as schema creation.
      await customStatement('PRAGMA user_version = 14');
    }),
    onUpgrade: (_, from, to) async {
      if (from < 1 || from > 13 || to != 14) {
        throw const MailStoreStorageException(MailProblemCode.unsupported);
      }
      await transaction(() async {
        if (from == 1) {
          for (final statement in schemaV2) {
            await customStatement(statement);
          }
        }
        if (from < 3) {
          for (final statement in schemaV3) {
            await customStatement(statement);
          }
        }
        if (from < 4) {
          for (final statement in schemaV4) {
            await customStatement(statement);
          }
        }
        if (from < 5) {
          for (final statement in schemaV5) {
            await customStatement(statement);
          }
        }
        if (from < 6) {
          for (final statement in schemaV6) {
            await customStatement(statement);
          }
        }
        if (from < 7) {
          for (final statement in schemaV7) {
            await customStatement(statement);
          }
        }
        if (from < 8) {
          for (final statement in schemaV8) {
            await customStatement(statement);
          }
        }
        if (from < 9) {
          for (final statement in schemaV9) {
            await customStatement(statement);
          }
        }
        if (from < 10) {
          for (final statement in schemaV10) {
            await customStatement(statement);
          }
        }
        if (from < 11) {
          for (final statement in schemaV11) {
            await customStatement(statement);
          }
        }
        if (from < 12) {
          await _validateFolderScopeUpgrade();
          for (final statement in schemaV12) {
            await customStatement(statement);
          }
        }
        if (from < 13) {
          await _validateCommandJournalUpgrade();
          for (final statement in schemaV13) {
            await customStatement(statement);
          }
        }
        for (final statement in schemaV14) {
          await customStatement(statement);
        }
        await faultInjector?.call(MailStoreCheckpoint.migrationCreated);
        await customStatement('PRAGMA user_version = 14');
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

  // Earlier schemas admit only flag actions. Refuse an unexplained action
  // rather than interpreting it as a new command with missing intent metadata.
  Future<void> _validateCommandJournalUpgrade() async {
    final invalid = await customSelect(
      "SELECT 1 AS invalid FROM flag_batches WHERE "
      "typeof(action)!='text' OR action NOT IN "
      "('markRead','markUnread','flag','unflag') LIMIT 1",
    ).get();
    if (invalid.isNotEmpty) {
      throw const MailStoreStorageException(MailProblemCode.storageFailure);
    }
  }

  // Published v11 folders reference definitions but not their account rows.
  // Refuse broken exact scopes before adding label metadata: an upgrade must
  // neither erase a foreign identity nor turn an empty explicit set into all.
  Future<void> _validateFolderScopeUpgrade() async {
    final invalid = await customSelect(
      'SELECT 1 AS invalid FROM saved_header_search_folders f '
      'LEFT JOIN saved_header_searches s ON s.id=f.search '
      'LEFT JOIN saved_header_search_accounts a '
      'ON a.search=f.search AND a.account_id=f.account_id '
      'WHERE s.id IS NULL OR a.account_id IS NULL OR s.has_folder_scope!=1 '
      'UNION ALL SELECT 1 AS invalid FROM saved_header_searches s WHERE '
      "typeof(s.has_folder_scope)!='integer' OR s.has_folder_scope NOT IN (0,1) OR "
      '(s.has_folder_scope=1 AND ('
      'NOT EXISTS(SELECT 1 FROM saved_header_search_folders f WHERE f.search=s.id) OR '
      'EXISTS(SELECT 1 FROM saved_header_search_accounts a WHERE a.search=s.id '
      'AND NOT EXISTS(SELECT 1 FROM saved_header_search_folders f '
      'WHERE f.search=a.search AND f.account_id=a.account_id)))) LIMIT 1',
    ).get();
    if (invalid.isNotEmpty) {
      throw const MailStoreStorageException(MailProblemCode.storageFailure);
    }
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

/// A profile-local directory only. Forgetting a route cannot cascade into
/// cached messages, drafts, Outbox payloads, credentials or provider mail.
const schemaV4 = <String>[
  '''ALTER TABLE store_profile ADD COLUMN local_account_revision INTEGER
    NOT NULL DEFAULT 0 CHECK(typeof(local_account_revision) = 'integer' AND
    local_account_revision BETWEEN 0 AND 9007199254740991)''',
  '''CREATE TABLE local_accounts (
    id TEXT PRIMARY KEY, provider TEXT NOT NULL, endpoint TEXT NOT NULL,
    login TEXT NOT NULL, sender TEXT NOT NULL, connected_at INTEGER NOT NULL
      CHECK(connected_at >= 0),
    revision INTEGER NOT NULL DEFAULT 0
      CHECK(typeof(revision) = 'integer' AND revision BETWEEN 0 AND 9007199254740991)
  )''',
];

/// Foreground browse windows have their own ordering and revision. They never
/// advance a provider sync cursor or claim authoritative server membership.
const schemaV5 = <String>[
  '''ALTER TABLE store_profile ADD COLUMN mailbox_view_revision INTEGER
    NOT NULL DEFAULT 0 CHECK(typeof(mailbox_view_revision) = 'integer' AND
    mailbox_view_revision BETWEEN 0 AND 9007199254740991)''',
  '''CREATE TABLE mailbox_views (
    account TEXT NOT NULL, mailbox TEXT NOT NULL,
    revision INTEGER NOT NULL CHECK(typeof(revision) = 'integer' AND
      revision BETWEEN 1 AND 9007199254740991),
    captured_at INTEGER NOT NULL CHECK(typeof(captured_at) = 'integer' AND
      captured_at BETWEEN 0 AND 8640000000000000),
    header_count INTEGER NOT NULL CHECK(typeof(header_count) = 'integer' AND
      header_count BETWEEN 0 AND 1000),
    has_more INTEGER NOT NULL CHECK(has_more IN (0,1)),
    PRIMARY KEY(account,mailbox),
    FOREIGN KEY(account,mailbox) REFERENCES mailboxes(account,id)
      ON DELETE CASCADE
  )''',
  '''CREATE TABLE mailbox_view_members (
    account TEXT NOT NULL, mailbox TEXT NOT NULL,
    position INTEGER NOT NULL CHECK(typeof(position) = 'integer' AND
      position BETWEEN 0 AND 999), message TEXT NOT NULL,
    PRIMARY KEY(account,mailbox,position), UNIQUE(account,mailbox,message),
    FOREIGN KEY(account,mailbox) REFERENCES mailbox_views(account,mailbox)
      ON DELETE CASCADE,
    FOREIGN KEY(account,message) REFERENCES messages(account,id)
  )''',
  'CREATE INDEX mailbox_view_message ON mailbox_view_members(account,message)',
];

/// Completion is only known after a page commits under this schema. Older
/// cursors remain intact but deliberately do not gain an invented checkpoint.
const schemaV8 = <String>[
  '''CREATE TABLE mailbox_sync_state (
    account TEXT NOT NULL, mailbox TEXT NOT NULL,
    revision INTEGER NOT NULL CHECK(typeof(revision) = 'integer' AND
      revision BETWEEN 1 AND 9007199254740991),
    updated_at INTEGER NOT NULL CHECK(typeof(updated_at) = 'integer' AND
      updated_at BETWEEN 0 AND 8640000000000000),
    has_more INTEGER NOT NULL CHECK(typeof(has_more) = 'integer' AND
      has_more IN (0,1)),
    PRIMARY KEY(account,mailbox),
    FOREIGN KEY(account,mailbox) REFERENCES mailboxes(account,id)
      ON DELETE CASCADE
  )''',
];

/// Saved header-search definitions belong to the host directory profile. Their
/// fixed account IDs can refer to separately owned account databases, so they
/// intentionally have no foreign key into this database's account rows.
const schemaV9 = <String>[
  '''ALTER TABLE store_profile ADD COLUMN saved_header_search_revision INTEGER
    NOT NULL DEFAULT 0 CHECK(typeof(saved_header_search_revision) = 'integer' AND
    saved_header_search_revision BETWEEN 0 AND 9007199254740991)''',
  '''CREATE TABLE saved_header_searches (
    id TEXT PRIMARY KEY, name TEXT NOT NULL, name_key TEXT NOT NULL UNIQUE,
    query TEXT NOT NULL,
    revision INTEGER NOT NULL CHECK(typeof(revision) = 'integer' AND
      revision BETWEEN 1 AND 9007199254740991)
  )''',
  '''CREATE TABLE saved_header_search_accounts (
    search TEXT NOT NULL REFERENCES saved_header_searches(id) ON DELETE CASCADE,
    position INTEGER NOT NULL CHECK(typeof(position) = 'integer' AND
      position BETWEEN 0 AND 99), account_id TEXT NOT NULL,
    PRIMARY KEY(search,position), UNIQUE(search,account_id)
  )''',
];

/// Account-owned compose defaults and ordered literal snippets. Account IDs are
/// retired rather than reused; settings revisions remain monotonic until the
/// account is explicitly removed. Existing schemas and mail payloads are intact.
const schemaV10 = <String>[
  '''CREATE TABLE account_compose_settings (
    account TEXT NOT NULL PRIMARY KEY REFERENCES accounts(id) ON DELETE CASCADE,
    revision INTEGER NOT NULL CHECK(typeof(revision) = 'integer' AND
      revision BETWEEN 1 AND 9007199254740991),
    signature TEXT NOT NULL CHECK(typeof(signature) = 'text'),
    signature_new INTEGER NOT NULL CHECK(typeof(signature_new) = 'integer' AND
      signature_new IN (0,1)),
    signature_replies INTEGER NOT NULL CHECK(typeof(signature_replies) = 'integer'
      AND signature_replies IN (0,1))
  )''',
  '''CREATE TABLE account_quick_texts (
    account TEXT NOT NULL REFERENCES account_compose_settings(account)
      ON DELETE CASCADE,
    position INTEGER NOT NULL CHECK(typeof(position) = 'integer' AND
      position BETWEEN 0 AND 31),
    id TEXT NOT NULL, name TEXT NOT NULL, name_key TEXT NOT NULL,
    text TEXT NOT NULL,
    PRIMARY KEY(account,id), UNIQUE(account,position), UNIQUE(account,name_key)
  )''',
];

/// Explicit saved-search folder sets live in the host directory profile.
/// Existing definitions retain their original all-retained-folders semantics.
/// Folder IDs are opaque local mailbox IDs, not display names or server paths.
const schemaV11 = <String>[
  '''ALTER TABLE saved_header_searches ADD COLUMN has_folder_scope INTEGER
    NOT NULL DEFAULT 0 CHECK(typeof(has_folder_scope) = 'integer' AND
    has_folder_scope IN (0,1))''',
  '''CREATE TABLE saved_header_search_folders (
    search TEXT NOT NULL REFERENCES saved_header_searches(id) ON DELETE CASCADE,
    position INTEGER NOT NULL CHECK(typeof(position) = 'integer' AND
      position BETWEEN 0 AND 199),
    account_id TEXT NOT NULL, mailbox_id TEXT NOT NULL,
    PRIMARY KEY(search,position), UNIQUE(search,account_id,mailbox_id)
  )''',
];

/// Preserve the published v11 identities, ordering, discriminator and 200-row
/// constraint. Labels are optional metadata; missing historical labels remain
/// null and never substitute for an exact account/folder identity.
const schemaV12 = <String>[
  'ALTER TABLE saved_header_search_folders ADD COLUMN display_name TEXT',
];
