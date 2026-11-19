import 'package:drift/drift.dart';
import 'package:quds_mail_core/quds_mail_core.dart';

import 'errors.dart';

/// Deliberately separate from the live-mail database and account lifecycle.
final class MailArchiveDatabase extends GeneratedDatabase {
  MailArchiveDatabase(super.executor);

  @override
  int get schemaVersion => 2;

  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (_) => transaction(() async {
      for (final statement in mailArchiveSchemaV1) {
        await customStatement(statement);
      }
      for (final statement in mailArchiveSchemaV2) {
        await customStatement(statement);
      }
      await customStatement('PRAGMA user_version = 2');
    }),
    onUpgrade: (_, from, to) async {
      if (from != 1 || to != 2) {
        throw const MailStoreStorageException(MailProblemCode.unsupported);
      }
      await transaction(() async {
        for (final statement in mailArchiveSchemaV2) {
          await customStatement(statement);
        }
      });
    },
    beforeOpen: (_) async {
      await customStatement('PRAGMA foreign_keys = ON');
      await customStatement('PRAGMA busy_timeout = 5000');
      await customSelect('SELECT rowid FROM archive_fts LIMIT 1').get();
    },
  );
}

const mailArchiveSchemaV1 = <String>[
  '''CREATE TABLE archive_owner (
    singleton INTEGER PRIMARY KEY CHECK(singleton=1),
    host_id TEXT NOT NULL, profile_id TEXT NOT NULL
  )''',
  '''CREATE TABLE archive_totals (
    singleton INTEGER PRIMARY KEY CHECK(singleton=1),
    messages INTEGER NOT NULL DEFAULT 0,
    raw_bytes INTEGER NOT NULL DEFAULT 0,
    logical_bytes INTEGER NOT NULL DEFAULT 0,
    origins INTEGER NOT NULL DEFAULT 0
  )''',
  'INSERT INTO archive_totals(singleton) VALUES(1)',
  '''CREATE TABLE archive_items (
    id TEXT PRIMARY KEY CHECK(length(id)=64),
    raw BLOB NOT NULL, raw_size INTEGER NOT NULL CHECK(raw_size>=0),
    envelope TEXT NOT NULL, index_data TEXT NOT NULL,
    metadata_hash TEXT NOT NULL CHECK(length(metadata_hash)=64),
    stored_size INTEGER NOT NULL CHECK(stored_size>=raw_size),
    archived_at INTEGER NOT NULL, sent_at INTEGER,
    subject TEXT NOT NULL, preview TEXT NOT NULL, attachment_count INTEGER NOT NULL,
    index_truncated INTEGER NOT NULL CHECK(index_truncated IN (0,1)),
    text_indexed INTEGER NOT NULL, text_skipped INTEGER NOT NULL,
    text_enabled INTEGER NOT NULL CHECK(text_enabled IN (0,1)),
    CHECK(length(raw)=raw_size)
  )''',
  '''CREATE TABLE archive_origins (
    message TEXT NOT NULL REFERENCES archive_items(id) ON DELETE RESTRICT,
    source TEXT NOT NULL, folder TEXT NOT NULL, source_message_id TEXT NOT NULL,
    stored_size INTEGER NOT NULL CHECK(stored_size>=0),
    PRIMARY KEY(message,source,folder,source_message_id)
  )''',
  'CREATE INDEX archive_source_folder ON archive_origins(source,folder,message)',
  'CREATE INDEX archive_sent_date ON archive_items(sent_at,id)',
  'CREATE INDEX archive_added_date ON archive_items(archived_at,id)',
  '''CREATE VIRTUAL TABLE archive_fts USING fts5(
    id UNINDEXED, subject, sender, recipients_to, recipients_cc,
    recipients_bcc, body, attachment_names, attachment_text,
    tokenize='unicode61 remove_diacritics 2'
  )''',
  '''CREATE TABLE archive_saved_searches (
    name TEXT PRIMARY KEY, data TEXT NOT NULL
  )''',
  '''CREATE TABLE archive_profiles (
    id TEXT PRIMARY KEY, data TEXT NOT NULL
  )''',
  '''CREATE TRIGGER archive_item_added AFTER INSERT ON archive_items BEGIN
    UPDATE archive_totals SET messages=messages+1,
      raw_bytes=raw_bytes+new.raw_size,
      logical_bytes=logical_bytes+new.stored_size WHERE singleton=1;
  END''',
  '''CREATE TRIGGER archive_item_updated AFTER UPDATE ON archive_items BEGIN
    UPDATE archive_totals SET raw_bytes=raw_bytes+new.raw_size-old.raw_size,
      logical_bytes=logical_bytes+new.stored_size-old.stored_size WHERE singleton=1;
  END''',
  '''CREATE TRIGGER archive_origin_added AFTER INSERT ON archive_origins BEGIN
    UPDATE archive_totals SET origins=origins+1,
      logical_bytes=logical_bytes+new.stored_size WHERE singleton=1;
  END''',
];

/// Additive restore metadata. Original messages, provenance, index projections,
/// and FTS tables are untouched by the version-one migration. Fixed logical
/// overhead accounts for keys, scalar fields and conservative per-row storage;
/// it is a quota estimate, not a measurement of SQLite's physical file size.
const mailArchiveSchemaV2 = <String>[
  'ALTER TABLE archive_totals ADD COLUMN restore_jobs INTEGER NOT NULL DEFAULT 0',
  'ALTER TABLE archive_totals ADD COLUMN restore_receipts INTEGER NOT NULL DEFAULT 0',
  '''CREATE TABLE archive_restore_jobs (
    manifest TEXT PRIMARY KEY CHECK(length(manifest)=64),
    planned INTEGER NOT NULL CHECK(planned>=0 AND planned<=100000),
    total_bytes INTEGER NOT NULL CHECK(total_bytes>=0 AND total_bytes<=4398046511104),
    stored_size INTEGER NOT NULL DEFAULT 192 CHECK(stored_size=192)
  )''',
  '''CREATE TABLE archive_restore_receipts (
    manifest TEXT NOT NULL REFERENCES archive_restore_jobs(manifest) ON DELETE CASCADE,
    ordinal INTEGER NOT NULL CHECK(ordinal>=1 AND ordinal<=100000),
    message TEXT NOT NULL REFERENCES archive_items(id) ON DELETE RESTRICT,
    byte_length INTEGER NOT NULL CHECK(byte_length>0 AND byte_length<=268435456),
    index_warning INTEGER NOT NULL CHECK(index_warning IN (0,1)),
    stored_size INTEGER NOT NULL DEFAULT 256 CHECK(stored_size=256),
    PRIMARY KEY(manifest,ordinal), UNIQUE(manifest,message)
  )''',
  '''CREATE TRIGGER archive_restore_job_added AFTER INSERT ON archive_restore_jobs BEGIN
    UPDATE archive_totals SET restore_jobs=restore_jobs+1,
      logical_bytes=logical_bytes+new.stored_size WHERE singleton=1;
  END''',
  '''CREATE TRIGGER archive_restore_job_removed AFTER DELETE ON archive_restore_jobs BEGIN
    UPDATE archive_totals SET restore_jobs=restore_jobs-1,
      logical_bytes=logical_bytes-old.stored_size WHERE singleton=1;
  END''',
  '''CREATE TRIGGER archive_restore_receipt_added AFTER INSERT ON archive_restore_receipts BEGIN
    UPDATE archive_totals SET restore_receipts=restore_receipts+1,
      logical_bytes=logical_bytes+new.stored_size WHERE singleton=1;
  END''',
  '''CREATE TRIGGER archive_restore_receipt_removed AFTER DELETE ON archive_restore_receipts BEGIN
    UPDATE archive_totals SET restore_receipts=restore_receipts-1,
      logical_bytes=logical_bytes-old.stored_size WHERE singleton=1;
  END''',
];
