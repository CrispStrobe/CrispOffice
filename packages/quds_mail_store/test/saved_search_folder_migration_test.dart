@TestOn('vm')
library;

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:quds_mail_store/src/schema/database.dart'
    show
        schemaV1,
        schemaV2,
        schemaV3,
        schemaV4,
        schemaV5,
        schemaV8,
        schemaV9,
        schemaV10;
import 'package:quds_mail_store/src/schema/flag_journal_schema.dart'
    show schemaV6, schemaV7;
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:test/test.dart';

final _profile = MailProfileId('directory', hostId: 'office');

T _value<T>(MailResult<T> result) {
  expect(result, isA<MailSuccess<T>>());
  return (result as MailSuccess<T>).value;
}

void main() {
  late sqlite.Database database;
  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    database = sqlite.sqlite3.openInMemory();
    for (final schema in [
      schemaV1,
      schemaV2,
      schemaV3,
      schemaV4,
      schemaV5,
      schemaV6,
      schemaV7,
      schemaV8,
      schemaV9,
      schemaV10,
    ]) {
      for (final statement in schema) {
        database.execute(statement);
      }
    }
    database.execute(
      'INSERT INTO store_profile(singleton,host_id,profile_id,saved_header_search_revision) VALUES(1,?,?,41)',
      [_profile.hostId, _profile.value],
    );
    database.execute(
      "INSERT INTO saved_header_searches(id,name,name_key,query,revision) VALUES('existing','Existing','existing','is:unread',41)",
    );
    database.execute(
      "INSERT INTO saved_header_search_accounts(search,position,account_id) VALUES('existing',0,'account')",
    );
    database.execute(
      "INSERT INTO accounts(id,provider,display_name,state) VALUES('account','gmail','Account','active')",
    );
    database.execute(
      "INSERT INTO account_compose_settings(account,revision,signature,signature_new,signature_replies) VALUES('account',8,'Keep signature',1,0)",
    );
    database.execute(
      "INSERT INTO account_quick_texts(account,position,id,name,name_key,text) VALUES('account',0,'thanks','Thanks','thanks','Thank you')",
    );
    database.userVersion = 10;
  });
  tearDown(() => database.close());

  Future<MailResult<SqliteMailRepository>> open({
    bool failMigration = false,
  }) => SqliteMailRepository.open(
    executor: NativeDatabase.opened(database, closeUnderlyingOnClose: false),
    profile: _profile,
    faultInjector: (point) {
      if (failMigration && point == MailStoreCheckpoint.migrationCreated) {
        throw const MailStoreStorageException(MailProblemCode.storageFailure);
      }
    },
  );

  Map<String, List<Map<String, Object?>>> preservedRows() => {
    for (final table in [
      'saved_header_search_accounts',
      'accounts',
      'account_compose_settings',
      'account_quick_texts',
    ])
      table: [
        for (final row in database.select('SELECT * FROM $table'))
          Map<String, Object?>.from(row),
      ],
    'saved_header_searches': [
      for (final row in database.select(
        'SELECT id,name,name_key,query,revision FROM saved_header_searches',
      ))
        Map<String, Object?>.from(row),
    ],
  };

  test(
    'v10 upgrade preserves definitions as all folders and unrelated compose rows',
    () async {
      final before = preservedRows();
      final store = _value(await open());
      try {
        expect(database.userVersion, 11);
        expect(preservedRows(), before);
        final saved = _value(await store.listSavedHeaderSearches()).single;
        expect(saved.folders, isNull);
        expect(saved.accountIds, ['account']);
        expect(saved.revision, 41);
        final next = _value(
          await store.saveSavedHeaderSearch(
            saved.copyWith(
              folders: const [
                MailSavedHeaderSearchFolder(
                  accountId: 'account',
                  mailboxId: 'missing-on-purpose',
                  displayName: 'Retained selection',
                ),
              ],
            ),
            expectedRevision: saved.revision,
          ),
        );
        expect(next.revision, 42);
        expect(next.folders!.single.mailboxId, 'missing-on-purpose');
        expect(database.select('PRAGMA foreign_key_check'), isEmpty);
        expect(
          database
              .select('SELECT signature FROM account_compose_settings')
              .single['signature'],
          'Keep signature',
        );
      } finally {
        await store.close();
      }
    },
  );

  test(
    'interrupted v10 migration rolls back schema and retries without data loss',
    () async {
      final before = preservedRows();
      final failed = await open(failMigration: true);
      expect(failed, isA<MailFailure<SqliteMailRepository>>());
      expect(
        (failed as MailFailure<SqliteMailRepository>).problem.code,
        MailProblemCode.storageFailure,
      );
      expect(database.userVersion, 10);
      expect(preservedRows(), before);
      expect(
        database
            .select('PRAGMA table_info(saved_header_searches)')
            .map((row) => row['name']),
        isNot(contains('folder_scope')),
      );
      expect(
        database.select(
          "SELECT name FROM sqlite_master WHERE name='saved_header_search_folders'",
        ),
        isEmpty,
      );
      final store = _value(await open());
      try {
        expect(database.userVersion, 11);
        expect(
          _value(await store.listSavedHeaderSearches()).single.folders,
          isNull,
        );
        expect(preservedRows(), before);
        expect(database.select('PRAGMA foreign_key_check'), isEmpty);
      } finally {
        await store.close();
      }
    },
  );
}
