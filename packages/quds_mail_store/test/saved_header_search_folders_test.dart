@TestOn('vm')
library;

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:test/test.dart';

final _profile = MailProfileId('folder-directory', hostId: 'office');
const _folders = [
  MailSavedHeaderSearchFolder(
    accountId: 'a',
    mailboxId: 'inbox',
    displayName: 'Inbox',
  ),
  MailSavedHeaderSearchFolder(
    accountId: 'b',
    mailboxId: ' inbox 📨 ',
    displayName: 'Inbox',
  ),
];

MailSavedHeaderSearch _search({
  List<MailSavedHeaderSearchFolder>? folders = _folders,
}) => MailSavedHeaderSearch(
  id: 'view',
  name: 'Selected folders',
  query: 'is:unread',
  accountIds: const ['a', 'b'],
  folders: folders,
);

T _value<T>(MailResult<T> result) {
  expect(result, isA<MailSuccess<T>>());
  return (result as MailSuccess<T>).value;
}

void _problem<T>(MailResult<T> result, MailProblemCode code) {
  expect(result, isA<MailFailure<T>>());
  expect((result as MailFailure<T>).problem.code, code);
}

final class _TransferProbe extends QueryInterceptor {
  bool oversizedTextTransferred = false;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final rows = await super.runSelect(executor, statement, args);
    oversizedTextTransferred |= rows.any(
      (row) =>
          row.values.any((value) => value is String && value.length > 16384),
    );
    return rows;
  }
}

void main() {
  late sqlite.Database database;
  late SqliteMailRepository store;
  late _TransferProbe probe;
  var failCommit = false;

  Future<SqliteMailRepository> open({
    MailStoreLimits limits = const MailStoreLimits(),
  }) async => _value(
    await SqliteMailRepository.open(
      executor: NativeDatabase.opened(
        database,
        closeUnderlyingOnClose: false,
      ).interceptWith(probe),
      profile: _profile,
      limits: limits,
      faultInjector: (point) {
        if (failCommit && point == MailStoreCheckpoint.beforeCommit) {
          throw const MailStoreStorageException(MailProblemCode.storageFailure);
        }
      },
    ),
  );

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    database = sqlite.sqlite3.openInMemory();
    probe = _TransferProbe();
    failCommit = false;
    store = await open();
  });
  tearDown(() async {
    await store.close();
    database.close();
  });

  test(
    'cross-profile folder identities and labels survive owner reopen',
    () async {
      final saved = _value(await store.saveSavedHeaderSearch(_search()));
      expect(_value(await store.listAccounts()), isEmpty);
      await store.close();
      store = await open();
      final restored = _value(await store.listSavedHeaderSearches()).single;
      expect(restored.folders, _folders);
      expect(restored.folders!.map((folder) => folder.displayName), [
        'Inbox',
        'Inbox',
      ]);
      expect(restored.folders!.last.mailboxId, ' inbox \uD83D\uDCE8 ');
      expect(restored.revision, saved.revision);
      expect(() => restored.folders!.clear(), throwsUnsupportedError);
      expect(database.select('PRAGMA foreign_key_check'), isEmpty);
    },
  );

  test(
    'revision-guarded edits and explicit reset replace the entire folder set',
    () async {
      final initial = _value(
        await store.saveSavedHeaderSearch(_search(folders: null)),
      );
      expect(initial.folders, isNull);
      final selected = _value(
        await store.saveSavedHeaderSearch(
          initial.copyWith(folders: _folders),
          expectedRevision: initial.revision,
        ),
      );
      expect(selected.folders, _folders);
      final narrowed = _value(
        await store.saveSavedHeaderSearch(
          selected.copyWith(accountIds: ['a'], folders: [_folders.first]),
          expectedRevision: selected.revision,
        ),
      );
      _problem(
        await store.saveSavedHeaderSearch(
          selected.copyWith(allFolders: true),
          expectedRevision: selected.revision,
        ),
        MailProblemCode.conflict,
      );
      expect(_value(await store.listSavedHeaderSearches()).single.folders, [
        _folders.first,
      ]);
      final all = _value(
        await store.saveSavedHeaderSearch(
          narrowed.copyWith(allFolders: true),
          expectedRevision: narrowed.revision,
        ),
      );
      expect(all.folders, isNull);
      expect(
        database.select('SELECT * FROM saved_header_search_folders'),
        isEmpty,
      );
      expect(
        database
            .select('SELECT has_folder_scope FROM saved_header_searches')
            .single['has_folder_scope'],
        0,
      );
    },
  );

  test(
    'failed create and scope replacement roll back rows and revision',
    () async {
      failCommit = true;
      _problem(
        await store.saveSavedHeaderSearch(_search()),
        MailProblemCode.storageFailure,
      );
      expect(_value(await store.listSavedHeaderSearches()), isEmpty);
      failCommit = false;
      final saved = _value(await store.saveSavedHeaderSearch(_search()));
      expect(saved.revision, 1);
      failCommit = true;
      _problem(
        await store.saveSavedHeaderSearch(
          saved.copyWith(allFolders: true),
          expectedRevision: saved.revision,
        ),
        MailProblemCode.storageFailure,
      );
      final unchanged = _value(await store.listSavedHeaderSearches()).single;
      expect(unchanged.revision, 1);
      expect(unchanged.folders, _folders);
      failCommit = false;
      expect(
        _value(
          await store.saveSavedHeaderSearch(
            unchanged.copyWith(allFolders: true),
            expectedRevision: unchanged.revision,
          ),
        ).revision,
        2,
      );
    },
  );

  test(
    'deleting a definition and removing a profile cascade only its folder rows',
    () async {
      final saved = _value(await store.saveSavedHeaderSearch(_search()));
      _value(
        await store.deleteSavedHeaderSearch(
          saved.id,
          expectedRevision: saved.revision,
        ),
      );
      expect(
        database.select('SELECT * FROM saved_header_search_folders'),
        isEmpty,
      );
      _value(await store.saveSavedHeaderSearch(_search()));
      _value(await store.removeProfile());
      expect(
        database.select('SELECT * FROM saved_header_search_folders'),
        isEmpty,
      );
      expect(_value(await store.listSavedHeaderSearches()), isEmpty);
    },
  );

  test(
    'folder identities and labels consume the shared metadata budget',
    () async {
      await store.close();
      store = await open(
        limits: const MailStoreLimits(maxMetadataCodeUnits: 128),
      );
      final saved = _value(await store.saveSavedHeaderSearch(_search()));
      _problem(
        await store.saveSavedHeaderSearch(
          saved.copyWith(
            folders: [
              MailSavedHeaderSearchFolder(
                accountId: 'a',
                mailboxId: 'inbox',
                displayName: 'x' * 128,
              ),
              _folders.last,
            ],
          ),
          expectedRevision: saved.revision,
        ),
        MailProblemCode.quotaExceeded,
      );
      expect(
        _value(await store.listSavedHeaderSearches()).single.folders,
        _folders,
      );
    },
  );

  test('the maximum folder count round-trips without truncation', () async {
    final folders = List.generate(
      MailSavedHeaderSearch.maxFolders,
      (index) => MailSavedHeaderSearchFolder(
        accountId: index.isEven ? 'a' : 'b',
        mailboxId: '$index',
      ),
    );
    _value(await store.saveSavedHeaderSearch(_search(folders: folders)));
    expect(
      _value(await store.listSavedHeaderSearches()).single.folders,
      folders,
    );
    expect(database.select('PRAGMA foreign_key_check'), isEmpty);
  });

  for (final (label, folders) in <(String, List<MailSavedHeaderSearchFolder>)>[
    ('empty', []),
    ('unrepresented account', [_folders.first]),
    ('duplicate', [..._folders, _folders.first]),
    (
      'foreign account',
      [
        ..._folders,
        const MailSavedHeaderSearchFolder(accountId: 'c', mailboxId: 'inbox'),
      ],
    ),
    (
      'malformed folder',
      [
        _folders.first,
        const MailSavedHeaderSearchFolder(
          accountId: 'b',
          mailboxId: 'bad\uD800',
        ),
      ],
    ),
    (
      'overlong list',
      List.generate(
        201,
        (index) => MailSavedHeaderSearchFolder(
          accountId: index.isEven ? 'a' : 'b',
          mailboxId: '$index',
        ),
      ),
    ),
  ]) {
    test('rejects $label folder scope without allocating a revision', () async {
      _problem(
        await store.saveSavedHeaderSearch(_search(folders: folders)),
        MailProblemCode.invalidInput,
      );
      expect(_value(await store.listSavedHeaderSearches()), isEmpty);
      expect(_value(await store.saveSavedHeaderSearch(_search())).revision, 1);
    });
  }

  for (final (label, sql, args) in <(String, String, List<Object?>)>[
    ('empty explicit scope', 'DELETE FROM saved_header_search_folders', []),
    (
      'position gap',
      'DELETE FROM saved_header_search_folders WHERE position=0',
      [],
    ),
    (
      'foreign account',
      "UPDATE saved_header_search_folders SET account_id='foreign' WHERE position=0",
      [],
    ),
    (
      'legacy scope with folders',
      'UPDATE saved_header_searches SET has_folder_scope=0',
      [],
    ),
    (
      'oversized mailbox',
      'UPDATE saved_header_search_folders SET mailbox_id=? WHERE position=0',
      ['m' * 100000],
    ),
    (
      'oversized label',
      'UPDATE saved_header_search_folders SET display_name=? WHERE position=0',
      ['x\u0000${'x' * 100000}'],
    ),
    (
      'control identity',
      'UPDATE saved_header_search_folders SET mailbox_id=? WHERE position=0',
      ['bad\u0000id'],
    ),
  ]) {
    test(
      'corrupt $label fails before overwrite or unbounded transfer',
      () async {
        final saved = _value(await store.saveSavedHeaderSearch(_search()));
        await store.close();
        database.execute('PRAGMA foreign_keys=OFF');
        database.execute(sql, args);
        store = await open();
        _problem(
          await store.listSavedHeaderSearches(),
          MailProblemCode.storageFailure,
        );
        _problem(
          await store.saveSavedHeaderSearch(
            saved.copyWith(allFolders: true),
            expectedRevision: saved.revision,
          ),
          MailProblemCode.storageFailure,
        );
        _problem(
          await store.deleteSavedHeaderSearch(
            saved.id,
            expectedRevision: saved.revision,
          ),
          MailProblemCode.storageFailure,
        );
        expect(probe.oversizedTextTransferred, isFalse);
      },
    );
  }
}
