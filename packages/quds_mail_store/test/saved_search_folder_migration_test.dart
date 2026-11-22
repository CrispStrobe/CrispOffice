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
        expect(database.userVersion, 16);
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
        isNot(contains('has_folder_scope')),
      );
      expect(
        database.select(
          "SELECT name FROM sqlite_master WHERE name='saved_header_search_folders'",
        ),
        isEmpty,
      );
      final store = _value(await open());
      try {
        expect(database.userVersion, 16);
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

  void installPublishedV11() {
    // Literal SQL published by PR #354, independent of today's schemaV11
    // declaration. A future accidental rewrite cannot silently alter this
    // regression fixture into the current schema before migration is exercised.
    database.execute(
      '''ALTER TABLE saved_header_searches ADD COLUMN has_folder_scope INTEGER
      NOT NULL DEFAULT 0 CHECK(typeof(has_folder_scope) = 'integer' AND
      has_folder_scope IN (0,1))''',
    );
    database.execute('''CREATE TABLE saved_header_search_folders (
      search TEXT NOT NULL REFERENCES saved_header_searches(id) ON DELETE CASCADE,
      position INTEGER NOT NULL CHECK(typeof(position) = 'integer' AND
        position BETWEEN 0 AND 199),
      account_id TEXT NOT NULL, mailbox_id TEXT NOT NULL,
      PRIMARY KEY(search,position), UNIQUE(search,account_id,mailbox_id)
    )''');
    database.execute(
      "UPDATE saved_header_searches SET has_folder_scope=1 WHERE id='existing'",
    );
    database.execute(
      "INSERT INTO saved_header_search_folders(search,position,account_id,mailbox_id) VALUES('existing',0,'account','INBOX')",
    );
    database.execute(
      "INSERT INTO saved_header_search_folders(search,position,account_id,mailbox_id) VALUES('existing',1,'account','Unavailable')",
    );
    database.execute(
      "INSERT INTO saved_header_searches(id,name,name_key,query,revision) VALUES('legacy','Legacy','legacy','',17)",
    );
    database.execute(
      "INSERT INTO saved_header_search_accounts(search,position,account_id) VALUES('legacy',0,'account')",
    );
    database.userVersion = 11;
  }

  List<Map<String, Object?>> publishedFolders() => [
    for (final row in database.select(
      'SELECT search,position,account_id,mailbox_id FROM saved_header_search_folders ORDER BY search,position',
    ))
      Map<String, Object?>.from(row),
  ];

  test(
    'literal published v11 scopes migrate to v12 with identities and revisions intact',
    () async {
      installPublishedV11();
      final original = preservedRows();
      final originalFolders = publishedFolders();
      final store = _value(await open());
      try {
        expect(database.userVersion, 16);
        expect(preservedRows(), original);
        expect(publishedFolders(), originalFolders);
        final saved = _value(await store.listSavedHeaderSearches());
        final scoped = saved.singleWhere((item) => item.id == 'existing');
        expect(scoped.revision, 41);
        expect(scoped.folderScopes!.map((folder) => folder.mailboxId), [
          'INBOX',
          'Unavailable',
        ]);
        expect(
          scoped.folders!.map((folder) => folder.displayName),
          everyElement(isNull),
        );
        expect(
          saved.singleWhere((item) => item.id == 'legacy').folders,
          isNull,
        );
        expect(
          database
              .select('SELECT saved_header_search_revision FROM store_profile')
              .single['saved_header_search_revision'],
          41,
        );
        final updated = _value(
          await store.saveSavedHeaderSearch(
            scoped.copyWith(
              folders: [
                const MailSavedHeaderSearchFolder(
                  accountId: 'account',
                  mailboxId: 'INBOX',
                  displayName: 'Inbox',
                ),
                scoped.folders!.last,
              ],
            ),
            expectedRevision: scoped.revision,
          ),
        );
        expect(updated.revision, 42);
        expect(updated.folderScopes!.first.displayName, 'Inbox');
        expect(publishedFolders(), originalFolders);
        expect(database.select('PRAGMA foreign_key_check'), isEmpty);
        final cleared = _value(
          await store.saveSavedHeaderSearch(
            updated.copyWith(allFolders: true),
            expectedRevision: updated.revision,
          ),
        );
        expect(cleared.folderScopes, isNull);
        expect(publishedFolders(), isEmpty);
      } finally {
        await store.close();
      }
    },
  );

  test(
    'interrupted literal v11 label migration rolls back without altering exact scope',
    () async {
      installPublishedV11();
      final original = preservedRows();
      final originalFolders = publishedFolders();
      final failed = await open(failMigration: true);
      expect(failed, isA<MailFailure<SqliteMailRepository>>());
      expect(
        (failed as MailFailure<SqliteMailRepository>).problem.code,
        MailProblemCode.storageFailure,
      );
      expect(database.userVersion, 11);
      expect(preservedRows(), original);
      expect(publishedFolders(), originalFolders);
      expect(
        database
            .select('PRAGMA table_info(saved_header_search_folders)')
            .map((row) => row['name']),
        isNot(contains('display_name')),
      );
      final store = _value(await open());
      try {
        expect(database.userVersion, 16);
        final saved = _value(await store.listSavedHeaderSearches());
        expect(
          saved.singleWhere((item) => item.id == 'existing').folders,
          hasLength(2),
        );
        expect(
          saved.singleWhere((item) => item.id == 'legacy').folders,
          isNull,
        );
        expect(preservedRows(), original);
        expect(publishedFolders(), originalFolders);
        expect(database.select('PRAGMA foreign_key_check'), isEmpty);
      } finally {
        await store.close();
      }
    },
  );

  test(
    'an invalid empty published explicit scope cannot migrate into all folders',
    () async {
      installPublishedV11();
      database.execute('DELETE FROM saved_header_search_folders');
      final failed = await open();
      expect(failed, isA<MailFailure<SqliteMailRepository>>());
      expect(
        (failed as MailFailure<SqliteMailRepository>).problem.code,
        MailProblemCode.storageFailure,
      );
      expect(database.userVersion, 11);
      expect(
        database
            .select(
              "SELECT has_folder_scope FROM saved_header_searches WHERE id='existing'",
            )
            .single['has_folder_scope'],
        1,
      );
    },
  );

  test(
    'published v11 foreign-account folder rows fail migration without losing data',
    () async {
      installPublishedV11();
      // Published v11's definition-level foreign key allows this malformed row;
      // the upgrade must independently verify membership of the saved account set.
      database.execute(
        "UPDATE saved_header_search_folders SET account_id='foreign' WHERE position=1",
      );
      final original = publishedFolders();
      final failed = await open();
      expect(failed, isA<MailFailure<SqliteMailRepository>>());
      expect(
        (failed as MailFailure<SqliteMailRepository>).problem.code,
        MailProblemCode.storageFailure,
      );
      expect(database.userVersion, 11);
      expect(publishedFolders(), original);
      expect(
        database
            .select('PRAGMA table_info(saved_header_search_folders)')
            .map((row) => row['name']),
        isNot(contains('display_name')),
      );
    },
  );
}
