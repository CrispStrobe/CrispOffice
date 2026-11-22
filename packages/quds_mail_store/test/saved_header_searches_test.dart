@TestOn('vm')
library;

import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:test/test.dart';

final _profile = MailProfileId('search-directory', hostId: 'test-office');

MailSavedHeaderSearch _search({
  String id = 'saved-view',
  String name = 'Work unread',
  String query = 'from:example.test AND is:unread',
  List<String> accountIds = const ['verified-account-a', 'verified-account-b'],
  List<MailSavedHeaderSearchFolder>? folderScopes,
  int revision = 0,
}) => MailSavedHeaderSearch(
  id: id,
  name: name,
  query: query,
  accountIds: accountIds,
  folderScopes: folderScopes,
  revision: revision,
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
  // Test databases deliberately use independent executors for reopen/quota cases.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late SqliteMailRepository store;
  var failCommit = false;
  setUp(() async {
    failCommit = false;
    store = _value(
      await SqliteMailRepository.open(
        executor: NativeDatabase.memory(),
        profile: _profile,
        faultInjector: (point) {
          if (failCommit && point == MailStoreCheckpoint.beforeCommit) {
            throw const MailStoreStorageException(
              MailProblemCode.storageFailure,
            );
          }
        },
      ),
    );
  });
  tearDown(() => store.close());

  test(
    'creates definitions without account rows and preserves exact scope',
    () async {
      final saved = _value(await store.saveSavedHeaderSearch(_search()));
      expect(saved.revision, 1);
      expect(saved.id, 'saved-view');
      expect(saved.name, 'Work unread');
      expect(saved.query, 'from:example.test AND is:unread');
      expect(saved.accountIds, ['verified-account-a', 'verified-account-b']);
      expect(_value(await store.listAccounts()), isEmpty);
      final loaded = _value(await store.listSavedHeaderSearches());
      expect(loaded.single.accountIds, saved.accountIds);
      expect(() => loaded.clear(), throwsUnsupportedError);
      expect(() => loaded.single.accountIds.clear(), throwsUnsupportedError);
    },
  );

  test('people queries preserve saved account and folder scope', () async {
    const query = 'participant:alice NOT recipient:team';
    const folder = MailSavedHeaderSearchFolder(
      accountId: 'verified-account-a',
      mailboxId: 'INBOX',
    );
    _value(
      await store.saveSavedHeaderSearch(
        _search(
          query: query,
          accountIds: ['verified-account-a'],
          folderScopes: [folder],
        ),
      ),
    );
    final loaded = _value(await store.listSavedHeaderSearches()).single;
    expect(loaded.query, query);
    expect(loaded.accountIds, ['verified-account-a']);
    expect(loaded.folderScopes, [folder]);
    final parsed = MailHeaderSearchQuery.parse(loaded.query);
    expect(
      parsed.matches(
        const MailHeaderSearchDocument(
          subject: 'Review',
          sender: 'Alice <alice@example.test>',
          to: 'owner@example.test',
        ),
      ),
      isTrue,
    );
    expect(
      parsed.matches(
        const MailHeaderSearchDocument(
          subject: 'Review',
          sender: 'Alice <alice@example.test>',
          to: 'team@example.test',
        ),
      ),
      isFalse,
    );
  });

  test(
    'exact folder sets are transactional and legacy searches stay broad',
    () async {
      final a = const MailSavedHeaderSearchFolder(
        accountId: 'verified-account-a',
        mailboxId: 'INBOX',
      );
      final b = const MailSavedHeaderSearchFolder(
        accountId: 'verified-account-b',
        mailboxId: 'Archive',
      );
      final legacy = _value(
        await store.saveSavedHeaderSearch(
          _search(id: 'legacy', name: 'Legacy'),
        ),
      );
      expect(legacy.folderScopes, isNull);
      final saved = _value(
        await store.saveSavedHeaderSearch(_search(folderScopes: [a, b])),
      );
      expect(
        _value(
          await store.listSavedHeaderSearches(),
        ).singleWhere((item) => item.id == saved.id).folderScopes,
        [a, b],
      );
      failCommit = true;
      _problem(
        await store.saveSavedHeaderSearch(
          saved.copyWith(folderScopes: [b, a]),
          expectedRevision: saved.revision,
        ),
        MailProblemCode.storageFailure,
      );
      failCommit = false;
      expect(
        _value(
          await store.listSavedHeaderSearches(),
        ).singleWhere((item) => item.id == saved.id).folderScopes,
        [a, b],
      );
      final updated = _value(
        await store.saveSavedHeaderSearch(
          saved.copyWith(
            folderScopes: [
              const MailSavedHeaderSearchFolder(
                accountId: 'verified-account-a',
                mailboxId: 'Sent',
              ),
              b,
            ],
          ),
          expectedRevision: saved.revision,
        ),
      );
      expect(updated.revision, greaterThan(saved.revision));
      _problem(
        await store.saveSavedHeaderSearch(
          saved.copyWith(allFolders: true),
          expectedRevision: saved.revision,
        ),
        MailProblemCode.conflict,
      );
      final broad = _value(
        await store.saveSavedHeaderSearch(
          updated.copyWith(allFolders: true),
          expectedRevision: updated.revision,
        ),
      );
      expect(broad.folderScopes, isNull);
      expect(
        _value(
          await store.listSavedHeaderSearches(),
        ).singleWhere((item) => item.id == saved.id).folderScopes,
        isNull,
      );
      expect(
        _value(
          await store.listSavedHeaderSearches(),
        ).singleWhere((item) => item.id == legacy.id).folderScopes,
        isNull,
      );
    },
  );

  test(
    'names sort deterministically and Unicode spelling is retained',
    () async {
      for (final (id, name) in [
        ('z', 'Zebra'),
        ('b', 'Beta'),
        ('a', 'alpha'),
        ('ar', 'عمل'),
      ]) {
        _value(await store.saveSavedHeaderSearch(_search(id: id, name: name)));
      }
      expect(
        _value(await store.listSavedHeaderSearches()).map((item) => item.name),
        ['alpha', 'Beta', 'Zebra', 'عمل'],
      );
    },
  );

  test(
    'case-insensitive name and separate ID collisions fail atomically',
    () async {
      final saved = _value(await store.saveSavedHeaderSearch(_search()));
      for (final duplicate in [
        _search(id: 'another', name: 'WORK UNREAD'),
        _search(name: 'Different name'),
      ]) {
        _problem(
          await store.saveSavedHeaderSearch(duplicate),
          MailProblemCode.conflict,
        );
      }
      final second = _value(
        await store.saveSavedHeaderSearch(
          _search(id: 'other', name: 'Flagged'),
        ),
      );
      _problem(
        await store.saveSavedHeaderSearch(
          second.copyWith(name: 'work unread'),
          expectedRevision: second.revision,
        ),
        MailProblemCode.conflict,
      );
      expect(
        _value(
          await store.listSavedHeaderSearches(),
        ).singleWhere((item) => item.id == saved.id).revision,
        saved.revision,
      );
    },
  );

  test(
    'update replaces scope and query only at the displayed revision',
    () async {
      final saved = _value(await store.saveSavedHeaderSearch(_search()));
      final updated = _value(
        await store.saveSavedHeaderSearch(
          saved.copyWith(
            name: 'All saved work',
            query: '',
            accountIds: ['verified-account-b'],
          ),
          expectedRevision: saved.revision,
        ),
      );
      expect(updated.revision, 2);
      expect(updated.accountIds, ['verified-account-b']);
      expect(updated.query, '');
      _problem(
        await store.saveSavedHeaderSearch(
          saved,
          expectedRevision: saved.revision,
        ),
        MailProblemCode.conflict,
      );
      _problem(
        await store.deleteSavedHeaderSearch(
          saved.id,
          expectedRevision: saved.revision,
        ),
        MailProblemCode.conflict,
      );
      expect(
        _value(await store.listSavedHeaderSearches()).single.name,
        'All saved work',
      );
      _value(
        await store.deleteSavedHeaderSearch(
          updated.id,
          expectedRevision: updated.revision,
        ),
      );
      expect(_value(await store.listSavedHeaderSearches()), isEmpty);
    },
  );

  test('create and update require explicit matching revision intent', () async {
    _problem(
      await store.saveSavedHeaderSearch(_search(revision: 3)),
      MailProblemCode.invalidInput,
    );
    _problem(
      await store.saveSavedHeaderSearch(_search(), expectedRevision: 0),
      MailProblemCode.invalidInput,
    );
    _problem(
      await store.saveSavedHeaderSearch(_search(), expectedRevision: 3),
      MailProblemCode.invalidInput,
    );
    _problem(
      await store.saveSavedHeaderSearch(
        _search(revision: 3),
        expectedRevision: 3,
      ),
      MailProblemCode.conflict,
    );
    _problem(
      await store.deleteSavedHeaderSearch('missing', expectedRevision: 1),
      MailProblemCode.conflict,
    );
    _problem(
      await store.deleteSavedHeaderSearch('missing', expectedRevision: 0),
      MailProblemCode.invalidInput,
    );
    _problem(
      await store.deleteSavedHeaderSearch('', expectedRevision: 1),
      MailProblemCode.invalidInput,
    );
    expect(_value(await store.listSavedHeaderSearches()), isEmpty);
  });

  test(
    'failed create update and delete roll back records, scope and counter',
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
          saved.copyWith(query: '', accountIds: ['new-scope']),
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
      final stillSaved = _value(await store.listSavedHeaderSearches()).single;
      expect(stillSaved.revision, 1);
      expect(stillSaved.accountIds, saved.accountIds);
      expect(stillSaved.query, saved.query);
      failCommit = false;
      final updated = _value(
        await store.saveSavedHeaderSearch(
          saved.copyWith(query: ''),
          expectedRevision: saved.revision,
        ),
      );
      expect(updated.revision, 2);
    },
  );

  test(
    'independent queued writes cannot both consume the same revision',
    () async {
      final saved = _value(await store.saveSavedHeaderSearch(_search()));
      final outcomes = await Future.wait([
        store.saveSavedHeaderSearch(
          saved.copyWith(name: 'First change'),
          expectedRevision: saved.revision,
        ),
        store.saveSavedHeaderSearch(
          saved.copyWith(name: 'Second change'),
          expectedRevision: saved.revision,
        ),
      ]);
      expect(
        outcomes.whereType<MailSuccess<MailSavedHeaderSearch>>(),
        hasLength(1),
      );
      expect(
        outcomes
            .whereType<MailFailure<MailSavedHeaderSearch>>()
            .single
            .problem
            .code,
        MailProblemCode.conflict,
      );
      expect(_value(await store.listSavedHeaderSearches()).single.revision, 2);
    },
  );

  test('hundred-definition cap still allows revision-guarded edits', () async {
    for (var i = 0; i < MailSavedHeaderSearches.maxSearches; i++) {
      _value(
        await store.saveSavedHeaderSearch(
          _search(id: 'view-$i', name: 'View $i'),
        ),
      );
    }
    _problem(
      await store.saveSavedHeaderSearch(_search()),
      MailProblemCode.quotaExceeded,
    );
    final first = _value(await store.listSavedHeaderSearches()).first;
    _value(
      await store.saveSavedHeaderSearch(
        first.copyWith(query: ''),
        expectedRevision: first.revision,
      ),
    );
    final last = _value(await store.listSavedHeaderSearches()).last;
    _value(
      await store.deleteSavedHeaderSearch(
        last.id,
        expectedRevision: last.revision,
      ),
    );
    _value(await store.saveSavedHeaderSearch(_search()));
    expect(_value(await store.listSavedHeaderSearches()), hasLength(100));
  });

  test(
    'profile metadata budget bounds the whole catalog without partial writes',
    () async {
      final bounded = _value(
        await SqliteMailRepository.open(
          executor: NativeDatabase.memory(),
          profile: _profile,
          limits: const MailStoreLimits(maxMetadataCodeUnits: 32),
        ),
      );
      try {
        _value(
          await bounded.saveSavedHeaderSearch(
            _search(id: 'v', name: 'A', query: '', accountIds: ['a']),
          ),
        );
        _problem(
          await bounded.saveSavedHeaderSearch(_search(id: 'larger')),
          MailProblemCode.quotaExceeded,
        );
        expect(_value(await bounded.listSavedHeaderSearches()).single.id, 'v');
      } finally {
        await bounded.close();
      }
    },
  );

  test(
    'deleting a definition preserves account metadata drafts and Outbox',
    () async {
      final account = MailAccountId('account', profile: _profile);
      _value(
        await store.createAccount(
          MailStoreAccount(
            id: account,
            provider: MailProviderKind.imap,
            displayName: 'Owned account',
            credentialReference: 'opaque-vault-reference',
          ),
        ),
      );
      _value(
        await store.saveDraft(
          MailDraft(
            id: 'draft',
            account: account,
            revision: 1,
            envelope: MailEnvelope(subject: 'Keep draft'),
            body: const MailBody(plainText: 'Unsent work'),
          ),
          expectedRevision: null,
        ),
      );
      _value(
        await store.saveOutbox(
          MailOutboxEntry.queued(
            id: 'outbox',
            prepared: MailPreparedMessage(
              account: account,
              draftId: 'draft',
              draftRevision: 1,
              wire: MailBytes(Uint8List.fromList([1, 2, 3])),
              envelope: MailTransportEnvelope(
                sender: 'me@example.test',
                recipients: ['you@example.test'],
              ),
            ),
            now: DateTime.utc(2026, 11, 21),
          ),
          expectedState: null,
          expectedAttemptId: null,
        ),
      );
      final saved = _value(await store.saveSavedHeaderSearch(_search()));
      _value(
        await store.deleteSavedHeaderSearch(
          saved.id,
          expectedRevision: saved.revision,
        ),
      );
      expect(
        _value(await store.listAccounts()).single.credentialReference,
        'opaque-vault-reference',
      );
      expect(
        _value(await store.loadDraft(account, 'draft'))!.body.plainText,
        'Unsent work',
      );
      expect(
        _value(await store.recoverOutbox(account)).single.prepared.wire.bytes,
        [1, 2, 3],
      );
    },
  );

  test(
    'profile removal clears definitions and cannot resurrect them',
    () async {
      final saved = _value(await store.saveSavedHeaderSearch(_search()));
      _value(await store.removeProfile());
      expect(_value(await store.listSavedHeaderSearches()), isEmpty);
      _problem(
        await store.saveSavedHeaderSearch(_search()),
        MailProblemCode.unavailable,
      );
      _problem(
        await store.deleteSavedHeaderSearch(
          saved.id,
          expectedRevision: saved.revision,
        ),
        MailProblemCode.unavailable,
      );
    },
  );

  for (final (label, invalid) in [
    ('empty scope', _search(accountIds: [])),
    ('duplicate scope', _search(accountIds: ['a', 'a'])),
    ('oversized scope', _search(accountIds: List.generate(101, (i) => '$i'))),
    ('invalid account', _search(accountIds: ['bad\u0000account'])),
    ('oversized account', _search(accountIds: ['a' * 1025])),
    ('empty name', _search(name: '')),
    ('untrimmed name', _search(name: ' padded ')),
    ('oversized name', _search(name: 'x' * 129)),
    ('invalid query', _search(query: 'from:')),
    ('long query', _search(query: 'x' * 1025)),
  ]) {
    test('rejects $label as invalid input with no saved definition', () async {
      _problem(
        await store.saveSavedHeaderSearch(invalid),
        MailProblemCode.invalidInput,
      );
      expect(_value(await store.listSavedHeaderSearches()), isEmpty);
    });
  }

  test(
    'file reopen retains definitions and blocks delete/recreate ABA',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'saved-header-search-reopen-',
      );
      final file = File('${directory.path}/mail.sqlite3');
      Future<SqliteMailRepository> open() async => _value(
        await SqliteMailRepository.open(
          executor: NativeDatabase(file),
          profile: _profile,
        ),
      );
      try {
        var disk = await open();
        final original = _value(await disk.saveSavedHeaderSearch(_search()));
        await disk.close();
        disk = await open();
        final restored = _value(await disk.listSavedHeaderSearches()).single;
        expect(restored.id, original.id);
        expect(restored.accountIds, original.accountIds);
        expect(restored.query, original.query);
        expect(restored.revision, original.revision);
        _value(
          await disk.deleteSavedHeaderSearch(
            restored.id,
            expectedRevision: restored.revision,
          ),
        );
        await disk.close();
        disk = await open();
        try {
          final replacement = _value(
            await disk.saveSavedHeaderSearch(_search()),
          );
          expect(replacement.revision, greaterThan(original.revision));
          _problem(
            await disk.saveSavedHeaderSearch(
              original,
              expectedRevision: original.revision,
            ),
            MailProblemCode.conflict,
          );
          _problem(
            await disk.deleteSavedHeaderSearch(
              original.id,
              expectedRevision: original.revision,
            ),
            MailProblemCode.conflict,
          );
        } finally {
          await disk.close();
        }
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );

  for (final (kind, surrogate) in [('high', '\uD800'), ('low', '\uDC00')]) {
    for (final field in ['id', 'name', 'query', 'account']) {
      test(
        'refuses lone $kind surrogate in $field without changing scope',
        () async {
          final broken = 'prefix${surrogate}suffix';
          final search = _search(
            id: field == 'id' ? broken : 'view',
            name: field == 'name' ? broken : 'Saved search',
            query: field == 'query' ? broken : '',
            accountIds: [field == 'account' ? broken : 'account'],
          );
          _problem(
            await store.saveSavedHeaderSearch(search),
            MailProblemCode.invalidInput,
          );
          expect(_value(await store.listSavedHeaderSearches()), isEmpty);
          expect(
            _value(await store.saveSavedHeaderSearch(_search())).revision,
            1,
          );
        },
      );
    }
  }

  test(
    'valid surrogate pairs round-trip unchanged through SQLite restart',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'saved-header-search-unicode-',
      );
      final file = File('${directory.path}/mail.sqlite3');
      Future<SqliteMailRepository> open() async => _value(
        await SqliteMailRepository.open(
          executor: NativeDatabase(file),
          profile: _profile,
        ),
      );
      final original = _search(
        id: 'view-📨',
        name: 'رسائل 📨',
        query: 'subject:"📨"',
        accountIds: ['account-📨'],
      );
      try {
        var disk = await open();
        try {
          _value(await disk.saveSavedHeaderSearch(original));
        } finally {
          await disk.close();
        }
        disk = await open();
        try {
          final restored = _value(await disk.listSavedHeaderSearches()).single;
          expect(restored.id.codeUnits, original.id.codeUnits);
          expect(restored.name.codeUnits, original.name.codeUnits);
          expect(restored.query.codeUnits, original.query.codeUnits);
          expect(
            restored.accountIds.single.codeUnits,
            original.accountIds.single.codeUnits,
          );
          _value(
            await disk.saveSavedHeaderSearch(
              restored.copyWith(name: 'Updated 📨'),
              expectedRevision: restored.revision,
            ),
          );
          expect(
            _value(await disk.listSavedHeaderSearches()).single.name,
            'Updated 📨',
          );
        } finally {
          await disk.close();
        }
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );

  for (final (label, sql, arguments) in <(String, String, List<Object?>)>[
    (
      'oversized query',
      'UPDATE saved_header_searches SET query=?',
      ['x\u0000${'a' * 100000}'],
    ),
    (
      'oversized account',
      'UPDATE saved_header_search_accounts SET account_id=? WHERE position=0',
      ['x' * 100000],
    ),
    (
      'wrong name key',
      'UPDATE saved_header_searches SET name_key=?',
      ['unrelated'],
    ),
    (
      'malformed query',
      'UPDATE saved_header_searches SET query=?',
      ['is:unread OR'],
    ),
    ('missing scope', 'DELETE FROM saved_header_search_accounts', []),
    (
      'scope gap',
      'DELETE FROM saved_header_search_accounts WHERE position=0',
      [],
    ),
    ('future revision', 'UPDATE saved_header_searches SET revision=42', []),
  ]) {
    test(
      'corrupt $label is refused without overwrite or oversized transfer',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'saved-header-search-corrupt-',
        );
        final file = File('${directory.path}/mail.sqlite3');
        final probe = _TransferProbe();
        Future<SqliteMailRepository> open() async => _value(
          await SqliteMailRepository.open(
            executor: NativeDatabase(file).interceptWith(probe),
            profile: _profile,
          ),
        );
        try {
          var disk = await open();
          final saved = _value(await disk.saveSavedHeaderSearch(_search()));
          await disk.close();
          final raw = sqlite.sqlite3.open(file.path);
          raw.execute(sql, arguments);
          raw.close();
          disk = await open();
          try {
            _problem(
              await disk.listSavedHeaderSearches(),
              MailProblemCode.storageFailure,
            );
            _problem(
              await disk.saveSavedHeaderSearch(_search(id: 'new', name: 'New')),
              MailProblemCode.storageFailure,
            );
            _problem(
              await disk.deleteSavedHeaderSearch(
                saved.id,
                expectedRevision: saved.revision,
              ),
              MailProblemCode.storageFailure,
            );
            expect(probe.oversizedTextTransferred, isFalse);
          } finally {
            await disk.close();
          }
        } finally {
          await directory.delete(recursive: true);
        }
      },
    );
  }
}
