@TestOn('vm')
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:test/test.dart';

final _profile = MailProfileId('cached-search', hostId: 'test-office');
final _account = MailAccountId('account', profile: _profile);
final _inbox = MailMailboxId('inbox', account: _account);
final _now = DateTime.utc(2026, 11, 21, 12);

T _value<T>(MailResult<T> result) {
  expect(result, isA<MailSuccess<T>>());
  return (result as MailSuccess<T>).value;
}

void _problem<T>(MailResult<T> result, MailProblemCode code) {
  expect(result, isA<MailFailure<T>>());
  expect((result as MailFailure<T>).problem.code, code);
}

MailHeaderRecord _header(
  int uid, {
  MailMailboxId? mailbox,
  String? subject,
  MailMessageFlags? flags,
  DateTime? sentAt,
}) => MailHeaderRecord(
  id: MailMessageId('id-${uid.toString().padLeft(4, '0')}'),
  remote: MailImapIdentity(
    mailbox: mailbox ?? _inbox,
    uidValidity: 7,
    uid: uid,
  ),
  envelope: MailEnvelope(
    subject: subject ?? 'Report $uid',
    from: const [MailAddress('alice@example.test', displayName: 'Älice')],
    to: const [MailAddress('team@example.test', displayName: 'Team')],
    cc: const [MailAddress('manager@example.test')],
    bcc: const [MailAddress('private@example.test')],
    sentAt: sentAt,
  ),
  flags: flags,
);

final class _ReadProbe extends QueryInterceptor {
  bool bodyRead = false;
  bool oversizedTransferred = false;

  void reset() {
    bodyRead = false;
    oversizedTransferred = false;
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    bodyRead |=
        RegExp(r'\bblobs\b|\bdrafts\b|\boutbox\b').hasMatch(statement) ||
        (statement.contains('cached_messages') &&
            RegExp(r'\bdata\b|\braw_hash\b').hasMatch(statement));
    final rows = await super.runSelect(executor, statement, args);
    oversizedTransferred |= rows.any(
      (row) =>
          row.values.any((value) => value is String && value.length > 32768),
    );
    return rows;
  }
}

void main() {
  late sqlite.Database database;
  late SqliteMailRepository store;
  late _ReadProbe probe;
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
      clock: () => _now,
      faultInjector: (point) {
        if (point == MailStoreCheckpoint.beforeCommit && failCommit) {
          throw const MailStoreStorageException(MailProblemCode.storageFailure);
        }
      },
    ),
  );

  Future<void> saveView(
    List<MailHeaderRecord> headers, {
    MailMailboxId? mailbox,
    int? revision,
    bool more = false,
  }) async {
    final target = mailbox ?? _inbox;
    _value(
      await store.saveMailboxView(
        MailMailbox(id: target, displayName: 'Folder ${target.value}'),
        headers,
        expectedRevision: revision,
        hasMore: more,
        lease: MailAccountSession(target.account).begin(),
      ),
    );
  }

  Future<void> sync(
    MailMailboxId mailbox,
    List<MailHeaderRecord> headers, {
    bool more = false,
  }) async {
    _value(
      await store.commitSyncPage(
        MailSyncPage(
          mailbox: mailbox,
          upserts: headers,
          tombstones: const [],
          next: MailCursor(mailbox: mailbox, value: 'next'),
          hasMore: more,
        ),
        expectedCursor: null,
        lease: MailAccountSession(mailbox.account).begin(),
      ),
    );
  }

  Future<void> account(MailAccountId id, MailProviderKind provider) async {
    _value(
      await store.createAccount(
        MailStoreAccount(id: id, provider: provider, displayName: 'Account'),
      ),
    );
  }

  Map<String, List<Map<String, Object?>>> snapshot() => {
    for (final table
        in database
            .select("SELECT name FROM sqlite_master WHERE type='table'")
            .map((row) => row['name']! as String))
      table: [
        for (final row in database.select('SELECT * FROM "$table"'))
          Map<String, Object?>.from(row),
      ],
  };

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    database = sqlite.sqlite3.openInMemory();
    probe = _ReadProbe();
    failCommit = false;
    store = await open();
    await account(_account, MailProviderKind.imap);
  });

  tearDown(() async {
    await store.close();
    database.close();
  });

  test('exact folder sets constrain counts, hits and cursor ownership', () async {
    final archive = MailMailboxId('archive', account: _account);
    await saveView([_header(1), _header(2)]);
    await saveView([
      _header(3, mailbox: archive),
      _header(4, mailbox: archive),
    ], mailbox: archive);
    // A duplicate observation of inbox membership must not duplicate a hit.
    await sync(_inbox, [_header(1), _header(2)]);

    final all = _value(await store.searchCachedHeaders(_account, ''));
    expect(all.totalCount, 4);
    expect(all.hits.map((hit) => hit.header.id.value), [
      'id-0001', 'id-0002', 'id-0003', 'id-0004',
    ]);
    final inbox = _value(await store.searchCachedHeaders(
      _account, '', folderIds: ['inbox'], limit: 1,
    ));
    expect(inbox.totalCount, 2);
    expect(inbox.scannedCount, 1);
    expect(inbox.hits.single.header.id.value, 'id-0001');
    expect(inbox.hits.single.folders.map((folder) => folder.id.value), ['inbox']);
    expect(inbox.nextCursor, isNotNull);

    _problem(await store.searchCachedHeaders(
      _account, '', folderIds: ['archive'], cursor: inbox.nextCursor,
    ), MailProblemCode.conflict);
    _problem(await store.searchCachedHeaders(
      _account, '', cursor: inbox.nextCursor,
    ), MailProblemCode.conflict);
    final next = _value(await store.searchCachedHeaders(
      _account, '', folderIds: ['inbox'], cursor: inbox.nextCursor, limit: 1,
    ));
    expect(next.hits.single.header.id.value, 'id-0002');
    expect(next.nextCursor, isNull);
    expect(next.totalCount, 2);

    final archived = _value(await store.searchCachedHeaders(
      _account, '', folderIds: ['archive'],
    ));
    expect(archived.totalCount, 2);
    expect(archived.hits.map((hit) => hit.header.id.value), [
      'id-0003', 'id-0004',
    ]);
    expect(archived.hits.every(
      (hit) => hit.folders.every((folder) => folder.id == archive),
    ), isTrue);
    final both = _value(await store.searchCachedHeaders(
      _account, '', folderIds: ['inbox', 'archive'],
    ));
    expect(both.totalCount, 4);
    expect(both.hits.map((hit) => hit.header.id.value).toSet(), hasLength(4));
  });

  test('missing or malformed folders fail without a broader fallback', () async {
    await saveView([_header(1), _header(2)]);
    for (final bad in [
      <String>[],
      ['inbox', 'inbox'],
      [''],
      ['invalid\nfolder'],
      ['x' * 1025],
      List.generate(201, (index) => 'folder-$index'),
    ]) {
      _problem(await store.searchCachedHeaders(
        _account, '', folderIds: bad,
      ), MailProblemCode.invalidInput);
    }
    for (final missing in ['archive', "' OR 1=1 --"]) {
      _problem(await store.searchCachedHeaders(
        _account, '', folderIds: [missing],
      ), MailProblemCode.unavailable);
    }
    final observed = _value(await store.searchCachedHeaders(
      _account, '', folderIds: ['inbox'],
    ));
    expect(observed.hits, hasLength(2));
    expect(_value(await store.searchCachedHeaders(_account, '')).totalCount, 2);
  });

  test('empty saved coverage is a successful empty local search', () async {
    final page = _value(await store.searchCachedHeaders(_account, ''));
    expect(page.hits, isEmpty);
    expect(page.totalCount, 0);
    expect(page.scannedCount, 0);
    expect(page.nextCursor, isNull);
    expect(page.browsed, isEmpty);
    expect(page.synchronized, isEmpty);
  });

  test(
    'finds matches after empty scan pages without truncating scope',
    () async {
      await saveView([
        for (var index = 1; index <= 8; index++)
          _header(index, subject: index == 8 ? 'Needle' : 'Unrelated'),
      ], more: true);
      var page = _value(
        await store.searchCachedHeaders(
          _account,
          'subject:needle',
          scanLimit: 3,
        ),
      );
      expect(page.hits, isEmpty);
      expect(page.scannedCount, 3);
      expect(page.totalCount, 8);
      expect(page.nextCursor, isNotNull);
      expect(page.browsed.single.hasMore, isTrue);
      page = _value(
        await store.searchCachedHeaders(
          _account,
          'subject:needle',
          scanLimit: 3,
          cursor: page.nextCursor,
        ),
      );
      expect(page.hits, isEmpty);
      expect(page.scannedCount, 3);
      expect(page.nextCursor, isNotNull);
      page = _value(
        await store.searchCachedHeaders(
          _account,
          'subject:needle',
          scanLimit: 3,
          cursor: page.nextCursor,
        ),
      );
      expect(page.hits.single.header.id.value, 'id-0008');
      expect(page.scannedCount, 2);
      expect(page.nextCursor, isNull);
    },
  );

  test(
    'hit limits continue after consumed rows rather than prefetched rows',
    () async {
      await saveView([_header(3), _header(1), _header(4), _header(2)]);
      var page = _value(
        await store.searchCachedHeaders(_account, '', limit: 1, scanLimit: 4),
      );
      final ids = <String>[];
      while (true) {
        ids.addAll(page.hits.map((hit) => hit.header.id.value));
        expect(page.scannedCount, 1);
        if (page.nextCursor == null) break;
        page = _value(
          await store.searchCachedHeaders(
            _account,
            '',
            limit: 1,
            scanLimit: 4,
            cursor: page.nextCursor,
          ),
        );
      }
      expect(ids, ['id-0001', 'id-0002', 'id-0003', 'id-0004']);
    },
  );

  test('searches beyond the first thousand saved headers', () async {
    final archive = MailMailboxId('archive', account: _account);
    await saveView([
      for (var uid = 1; uid <= 1000; uid++) _header(uid, subject: 'Ordinary'),
    ]);
    await saveView([
      _header(1001, mailbox: archive, subject: 'Ordinary'),
      _header(1002, mailbox: archive, subject: 'Final needle'),
    ], mailbox: archive);
    var page = _value(await store.searchCachedHeaders(_account, 'needle'));
    expect(page.totalCount, 1002);
    expect(page.hits, isEmpty);
    expect(page.scannedCount, 500);
    page = _value(
      await store.searchCachedHeaders(
        _account,
        'needle',
        cursor: page.nextCursor,
      ),
    );
    expect(page.hits, isEmpty);
    expect(page.scannedCount, 500);
    page = _value(
      await store.searchCachedHeaders(
        _account,
        'needle',
        cursor: page.nextCursor,
      ),
    );
    expect(page.hits.single.header.id.value, 'id-1002');
    expect(page.scannedCount, 2);
    expect(page.nextCursor, isNull);
  });

  test(
    'deduplicates sync and browse labels with complete provenance',
    () async {
      final gmail = MailAccountId('gmail', profile: _profile);
      await account(gmail, MailProviderKind.gmail);
      final inbox = MailMailboxId('INBOX', account: gmail);
      final label = MailMailboxId('Work', account: gmail);
      final header = MailHeaderRecord(
        id: MailMessageId('shared'),
        remote: MailOpaqueIdentity(
          account: gmail,
          provider: MailProviderKind.gmail,
          value: 'provider-id',
        ),
        envelope: MailEnvelope(subject: 'Shared report'),
      );
      await sync(inbox, [header], more: true);
      await saveView([header], mailbox: inbox);
      await saveView([header], mailbox: label);
      final page = _value(await store.searchCachedHeaders(gmail, 'report'));
      expect(page.totalCount, 1);
      expect(page.scannedCount, 1);
      expect(page.hits.single.folders.map((folder) => folder.id.value), [
        'INBOX',
        'Work',
      ]);
      expect(page.browsed.length, 2);
      expect(page.synchronized.single.hasMore, isTrue);
      expect(page.synchronized.single.updatedAt, _now);
      expect(() => page.hits.clear(), throwsUnsupportedError);
      expect(() => page.hits.single.folders.clear(), throwsUnsupportedError);
      expect(() => page.browsed.clear(), throwsUnsupportedError);
      expect(() => page.synchronized.clear(), throwsUnsupportedError);
    },
  );

  test(
    'covers other folders and excludes old unreferenced cached headers',
    () async {
      final archive = MailMailboxId('archive', account: _account);
      await saveView([_header(1), _header(2)]);
      await sync(archive, [_header(3, mailbox: archive)]);
      await saveView([_header(2)], revision: 1);
      expect(database.select('SELECT id FROM messages').length, 3);
      final page = _value(await store.searchCachedHeaders(_account, ''));
      expect(page.hits.map((hit) => hit.header.id.value), [
        'id-0002',
        'id-0003',
      ]);
      expect(page.totalCount, 2);
      expect(page.browsed.single.headerCount, 1);
      expect(page.synchronized.single.headerCount, 1);
    },
  );

  test(
    'known and unknown Boolean state uses shared three-valued semantics',
    () async {
      await saveView([
        _header(1, subject: 'Invoice'),
        _header(2, subject: 'Report'),
        _header(3, subject: 'Invoice', flags: const MailMessageFlags()),
        _header(
          4,
          subject: 'Invoice',
          flags: const MailMessageFlags(isRead: true),
        ),
      ]);
      var page = _value(
        await store.searchCachedHeaders(_account, 'NOT is:read'),
      );
      expect(page.hits.map((hit) => hit.header.id.value), ['id-0003']);
      page = _value(
        await store.searchCachedHeaders(
          _account,
          'NOT (is:read AND subject:invoice)',
        ),
      );
      expect(page.hits.map((hit) => hit.header.id.value), [
        'id-0002',
        'id-0003',
      ]);
      page = _value(
        await store.searchCachedHeaders(
          _account,
          '(subject:report OR is:read) from:älice',
        ),
      );
      expect(page.hits.map((hit) => hit.header.id.value), [
        'id-0002',
        'id-0004',
      ]);
    },
  );

  test(
    'searches public address fields and local dates without Bcc or bodies',
    () async {
      final date = DateTime(2026, 11, 21, 0, 30);
      final first = _header(1, sentAt: date);
      await saveView([first, _header(2)]);
      _value(
        await store.cacheMessage(
          _account,
          first.id,
          MailMessage(
            raw: MailBytes(Uint8List.fromList([1, 2, 3])),
            envelope: first.envelope,
            body: const MailBody(plainText: 'bodyneedle'),
            localId: first.id,
            remoteIdentity: first.remote,
          ),
        ),
      );
      final before = snapshot();
      probe.reset();
      final page = _value(
        await store.searchCachedHeaders(
          _account,
          'to:team cc:manager on:2026-11-21',
        ),
      );
      expect(page.hits.single.header.id, first.id);
      expect(page.hits.single.hasCachedBody, isTrue);
      for (final query in [
        'private@example.test',
        'bodyneedle',
        'NOT on:2026-11-21',
      ]) {
        expect(
          _value(await store.searchCachedHeaders(_account, query)).hits,
          isEmpty,
        );
      }
      expect(probe.bodyRead, isFalse);
      expect(snapshot(), before);
    },
  );

  test(
    'profiles and accounts cannot leak through query or cursor reuse',
    () async {
      final other = MailAccountId('other', profile: _profile);
      final otherBox = MailMailboxId('inbox', account: other);
      await account(other, MailProviderKind.imap);
      await saveView([_header(1), _header(2)]);
      await saveView([
        _header(9, mailbox: otherBox, subject: 'Other'),
      ], mailbox: otherBox);
      final page = _value(
        await store.searchCachedHeaders(_account, '', limit: 1),
      );
      expect(
        _value(
          await store.searchCachedHeaders(other, ''),
        ).hits.single.header.remote.account,
        other,
      );
      _problem(
        await store.searchCachedHeaders(other, '', cursor: page.nextCursor),
        MailProblemCode.conflict,
      );
      _problem(
        await store.searchCachedHeaders(
          MailAccountId(
            'account',
            profile: MailProfileId('foreign', hostId: 'test-office'),
          ),
          '',
        ),
        MailProblemCode.permissionDenied,
      );
    },
  );

  test('cursor is query-bound, repeatable and content-redacted', () async {
    await saveView([_header(1), _header(2), _header(3)]);
    final first = _value(
      await store.searchCachedHeaders(_account, 'report', limit: 1),
    );
    expect(
      first.nextCursor.toString(),
      'MailCachedHeaderSearchCursor(redacted)',
    );
    for (var repeat = 0; repeat < 2; repeat++) {
      final next = _value(
        await store.searchCachedHeaders(
          _account,
          'report',
          cursor: first.nextCursor,
          limit: 1,
        ),
      );
      expect(next.hits.single.header.id.value, 'id-0002');
    }
    _problem(
      await store.searchCachedHeaders(
        _account,
        'subject:report',
        cursor: first.nextCursor,
      ),
      MailProblemCode.conflict,
    );
  });

  test(
    'committed changes invalidate continuation but failed writes do not',
    () async {
      await saveView([_header(1), _header(2)]);
      final first = _value(
        await store.searchCachedHeaders(_account, '', limit: 1),
      );
      failCommit = true;
      _problem(
        await store.saveMailbox(
          MailMailbox(id: _inbox, displayName: 'Rejected'),
        ),
        MailProblemCode.storageFailure,
      );
      failCommit = false;
      expect(
        _value(
          await store.searchCachedHeaders(
            _account,
            '',
            cursor: first.nextCursor,
          ),
        ).hits.single.header.id.value,
        'id-0002',
      );
      _value(
        await store.saveMailbox(
          MailMailbox(id: _inbox, displayName: 'Changed'),
        ),
      );
      _problem(
        await store.searchCachedHeaders(_account, '', cursor: first.nextCursor),
        MailProblemCode.conflict,
      );
    },
  );

  test(
    'reopen preserves search results and rejects the retired owner cursor',
    () async {
      await saveView([_header(1), _header(2)]);
      final first = _value(
        await store.searchCachedHeaders(_account, '', limit: 1),
      );
      await store.close();
      _problem(
        await store.searchCachedHeaders(_account, ''),
        MailProblemCode.unavailable,
      );
      store = await open();
      _problem(
        await store.searchCachedHeaders(_account, '', cursor: first.nextCursor),
        MailProblemCode.conflict,
      );
      expect(
        _value(await store.searchCachedHeaders(_account, '')).totalCount,
        2,
      );
    },
  );

  test(
    'malformed expressions and excessive work bounds fail explicitly',
    () async {
      for (final query in [
        'a OR',
        'from:',
        'bcc:private',
        'x' * 1025,
        'NOT (is:read',
      ]) {
        _problem(
          await store.searchCachedHeaders(_account, query),
          MailProblemCode.invalidInput,
        );
      }
      for (final limit in [0, -1, 201]) {
        _problem(
          await store.searchCachedHeaders(_account, '', limit: limit),
          MailProblemCode.invalidInput,
        );
      }
      for (final scan in [0, -1, 1001]) {
        _problem(
          await store.searchCachedHeaders(_account, '', scanLimit: scan),
          MailProblemCode.invalidInput,
        );
      }
    },
  );

  test(
    'unknown legacy checkpoint does not hide authoritative local headers',
    () async {
      await sync(_inbox, [_header(1)]);
      database.execute('DELETE FROM mailbox_sync_state');
      final page = _value(await store.searchCachedHeaders(_account, ''));
      expect(page.hits.single.folders.single.id, _inbox);
      expect(page.synchronized, isEmpty);
      expect(page.browsed, isEmpty);
      expect(page.totalCount, 1);
    },
  );

  test('oversized candidate metadata is rejected before transfer', () async {
    await saveView([_header(1)]);
    database.execute('UPDATE messages SET envelope=?', [
      'x' * (9 * 1024 * 1024),
    ]);
    probe.reset();
    _problem(
      await store.searchCachedHeaders(_account, ''),
      MailProblemCode.quotaExceeded,
    );
    expect(probe.oversizedTransferred, isFalse);
  });

  test(
    'corrupt selected header metadata never becomes a successful empty result',
    () async {
      await saveView([_header(1)]);
      database.execute('UPDATE messages SET envelope=?', ['{bad-json']);
      _problem(
        await store.searchCachedHeaders(_account, 'unmatched'),
        MailProblemCode.storageFailure,
      );
    },
  );

  test(
    'corrupt view count and foreign IMAP folder membership fail closed',
    () async {
      await saveView([_header(1)]);
      database.execute('UPDATE mailbox_views SET header_count=2');
      _problem(
        await store.searchCachedHeaders(_account, ''),
        MailProblemCode.storageFailure,
      );
      database.execute('UPDATE mailbox_views SET header_count=1');
      final other = MailMailboxId('other', account: _account);
      _value(
        await store.saveMailbox(MailMailbox(id: other, displayName: 'Other')),
      );
      database.execute(
        'INSERT INTO memberships(account,mailbox,message) VALUES(?,?,?)',
        [_account.value, other.value, 'id-0001'],
      );
      _problem(
        await store.searchCachedHeaders(_account, ''),
        MailProblemCode.storageFailure,
      );
      _problem(
        await store.searchCachedHeaders(_account, 'unmatched'),
        MailProblemCode.storageFailure,
      );
    },
  );

  test(
    'orphaned browse membership cannot appear as current saved mail',
    () async {
      await saveView([_header(1)]);
      database.execute('PRAGMA foreign_keys=OFF');
      database.execute('DELETE FROM mailbox_views');
      database.execute('PRAGMA foreign_keys=ON');
      expect(database.select('SELECT * FROM mailbox_view_members').length, 1);
      _problem(
        await store.searchCachedHeaders(_account, ''),
        MailProblemCode.storageFailure,
      );
    },
  );

  test(
    'lowered per-account and metadata budgets preserve quota errors',
    () async {
      await saveView([_header(1), _header(2)]);
      await store.close();
      store = await open(
        limits: const MailStoreLimits(maxMessagesPerAccount: 1),
      );
      _problem(
        await store.searchCachedHeaders(_account, ''),
        MailProblemCode.quotaExceeded,
      );
      await store.close();
      store = await open(
        limits: const MailStoreLimits(maxMetadataCodeUnits: 32),
      );
      _problem(
        await store.searchCachedHeaders(_account, ''),
        MailProblemCode.quotaExceeded,
      );
    },
  );
}
