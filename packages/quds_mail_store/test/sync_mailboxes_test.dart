@TestOn('vm')
library;

import 'dart:async';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:test/test.dart';

final _profile = MailProfileId('sync-snapshots', hostId: 'test-office');
final _account = MailAccountId('account', profile: _profile);
final _mailbox = MailMailboxId('INBOX', account: _account);
final _now = DateTime.utc(2026, 11, 21);

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
  int validity = 7,
  MailMailboxId? mailbox,
  String? id,
  String? subject,
}) => MailHeaderRecord(
  id: MailMessageId(id ?? 'message-$validity-$uid'),
  remote: MailImapIdentity(
    mailbox: mailbox ?? _mailbox,
    uidValidity: validity,
    uid: uid,
  ),
  envelope: MailEnvelope(subject: subject ?? 'Subject $uid'),
  flags: const MailMessageFlags(isRead: true),
);

MailSyncPage _page(
  String cursor, {
  List<MailHeaderRecord> headers = const [],
  List<MailRemoteIdentity> tombstones = const [],
  bool more = false,
  bool reset = false,
  MailMailboxId? mailbox,
}) {
  final target = mailbox ?? _mailbox;
  return MailSyncPage(
    mailbox: target,
    upserts: headers,
    tombstones: tombstones,
    next: MailCursor(mailbox: target, value: cursor),
    hasMore: more,
    resetRequired: reset,
  );
}

final class _ReadProbe extends QueryInterceptor {
  bool bodyRead = false;
  bool oversizedTransferred = false;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    bodyRead |=
        statement.contains('SELECT b.hash,b.data') ||
        statement.contains('SELECT data FROM cached_messages');
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
  late MailAccountSession session;
  late _ReadProbe probe;
  var now = _now;
  MailStoreCheckpoint? failAt;
  var invalidateCommit = false;

  Future<MailResult<SqliteMailRepository>> open({
    MailStoreLimits limits = const MailStoreLimits(),
  }) => SqliteMailRepository.open(
    executor: NativeDatabase.opened(
      database,
      closeUnderlyingOnClose: false,
    ).interceptWith(probe),
    profile: _profile,
    limits: limits,
    clock: () => now,
    faultInjector: (point) {
      if (point == MailStoreCheckpoint.beforeCommit && invalidateCommit) {
        session.invalidate();
      }
      if (point == failAt) {
        throw const MailStoreStorageException(MailProblemCode.storageFailure);
      }
    },
  );

  Future<MailResult<MailUnit>> commit(
    MailSyncPage page, {
    String? expected,
    MailOperationLease? lease,
  }) => store.commitSyncPage(
    page,
    expectedCursor: expected == null
        ? null
        : MailCursor(mailbox: page.mailbox, value: expected),
    lease: lease ?? session.begin(),
  );

  Map<String, List<Map<String, Object?>>> snapshot() => {
    for (final table in const [
      'mailboxes',
      'messages',
      'memberships',
      'cursors',
      'mailbox_sync_state',
      'tombstones',
      'pending_operations',
      'mailbox_views',
      'mailbox_view_members',
      'drafts',
      'outbox',
      'flag_batches',
      'flag_batch_items',
      'mail_fts',
    ])
      table: [
        for (final row in database.select(
          'SELECT * FROM $table ORDER BY rowid',
        ))
          Map<String, Object?>.from(row),
      ],
  };

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    database = sqlite.sqlite3.openInMemory();
    session = MailAccountSession(_account);
    probe = _ReadProbe();
    now = _now;
    failAt = null;
    invalidateCommit = false;
    store = _value(await open());
    _value(
      await store.createAccount(
        MailStoreAccount(
          id: _account,
          provider: MailProviderKind.imap,
          displayName: 'Sync account',
        ),
      ),
    );
    _value(
      await store.saveMailbox(
        MailMailbox(id: _mailbox, displayName: 'Inbox · البريد الوارد'),
      ),
    );
  });

  tearDown(() async {
    await store.close();
    database.close();
  });

  test(
    'unknown, partial, completed and empty checkpoints remain distinct',
    () async {
      expect(_value(await store.loadSyncMailbox(_mailbox)), isNull);
      expect(_value(await store.listSyncMailboxes(_account)), isEmpty);
      _value(await commit(_page('first', headers: [_header(3)], more: true)));
      final partial = _value(await store.loadSyncMailbox(_mailbox))!;
      expect(partial.revision, 1);
      expect(partial.updatedAt, _now);
      expect(partial.hasMore, isTrue);
      expect(partial.hasMoreHeaders, isFalse);
      expect(partial.headerCount, 1);
      expect(partial.mailbox.displayName, 'Inbox · البريد الوارد');

      now = _now.add(const Duration(minutes: 1));
      _value(
        await commit(_page('last', headers: [_header(1)]), expected: 'first'),
      );
      final complete = _value(await store.loadSyncMailbox(_mailbox))!;
      expect(complete.revision, 2);
      expect(complete.updatedAt, now);
      expect(complete.hasMore, isFalse);
      expect(complete.headerCount, 2);
      expect(complete.headers.map((header) => header.id.value), [
        'message-7-1',
        'message-7-3',
      ]);
      expect(() => complete.headers.clear(), throwsUnsupportedError);
      _value(await commit(_page('empty', reset: true), expected: 'last'));
      final empty = _value(await store.loadSyncMailbox(_mailbox))!;
      expect(empty.revision, 3);
      expect(empty.headerCount, 0);
      expect(empty.headers, isEmpty);
      expect(empty.hasMore, isFalse);
      expect(probe.bodyRead, isFalse);
    },
  );

  test(
    'local pages have independent continuation and checkpoint survives reopen',
    () async {
      _value(
        await commit(
          _page(
            'done',
            headers: [
              _header(9, id: 'c'),
              _header(2, id: 'a'),
              _header(4, id: 'b'),
            ],
          ),
        ),
      );
      final first = _value(await store.loadSyncMailbox(_mailbox, limit: 2))!;
      expect(first.headers.map((header) => header.id.value), ['a', 'b']);
      expect(first.headerCount, 3);
      expect(first.offset, 0);
      expect(first.hasMore, isFalse);
      expect(first.hasMoreHeaders, isTrue);
      await store.close();
      store = _value(await open());
      final last = _value(
        await store.loadSyncMailbox(_mailbox, limit: 2, offset: 2),
      )!;
      expect(last.headers.single.id.value, 'c');
      expect(last.offset, 2);
      expect(last.revision, first.revision);
      expect(last.updatedAt, first.updatedAt);
      expect(last.hasMoreHeaders, isFalse);
      final past = _value(await store.loadSyncMailbox(_mailbox, offset: 4))!;
      expect(past.headers, isEmpty);
      expect(past.hasMoreHeaders, isFalse);
    },
  );

  test('catalog ordering and account scopes are deterministic', () async {
    final archive = MailMailboxId('Archive', account: _account);
    final otherAccount = MailAccountId('other', profile: _profile);
    final otherInbox = MailMailboxId('INBOX', account: otherAccount);
    _value(
      await store.createAccount(
        MailStoreAccount(
          id: otherAccount,
          provider: MailProviderKind.imap,
          displayName: 'Other',
        ),
      ),
    );
    _value(await commit(_page('a', mailbox: archive)));
    _value(await commit(_page('i', headers: [_header(1)])));
    _value(
      await commit(
        _page(
          'o',
          mailbox: otherInbox,
          headers: [_header(1, mailbox: otherInbox)],
        ),
        lease: MailAccountSession(otherAccount).begin(),
      ),
    );
    expect(
      _value(
        await store.listSyncMailboxes(_account),
      ).map((box) => box.mailbox.id.value),
      ['Archive', 'INBOX'],
    );
    expect(
      _value(await store.listSyncMailboxes(otherAccount)).single.headerCount,
      1,
    );
    now = _now.add(const Duration(seconds: 1));
    _value(await commit(_page('i2'), expected: 'i'));
    expect(
      _value(await store.listSyncMailboxes(_account)).first.mailbox.id,
      _mailbox,
    );
    final foreign = MailAccountId(
      'account',
      profile: MailProfileId('foreign', hostId: _profile.hostId),
    );
    _problem(
      await store.listSyncMailboxes(foreign),
      MailProblemCode.permissionDenied,
    );
    _problem(
      await store.loadSyncMailbox(MailMailboxId('INBOX', account: foreign)),
      MailProblemCode.permissionDenied,
    );
  });

  test(
    'browse-window replacement and cleanup do not replace sync membership',
    () async {
      _value(await commit(_page('sync', headers: [_header(1), _header(2)])));
      _value(
        await store.saveMailboxView(
          MailMailbox(id: _mailbox, displayName: 'Inbox'),
          [_header(9)],
          expectedRevision: null,
          hasMore: true,
          lease: session.begin(),
        ),
      );
      final synchronized = _value(await store.loadSyncMailbox(_mailbox))!;
      expect(synchronized.headerCount, 2);
      expect(synchronized.headers.map((header) => header.remote), [
        _header(1).remote,
        _header(2).remote,
      ]);
      expect(
        _value(await store.loadMailboxView(_mailbox))!.headers.single.remote,
        _header(9).remote,
      );
      _value(await store.clearMailboxCache(_account));
      expect(_value(await store.loadMailboxView(_mailbox)), isNull);
      expect(_value(await store.loadSyncMailbox(_mailbox))!.headerCount, 2);
      expect(_value(await store.loadSyncMailbox(_mailbox))!.revision, 1);
    },
  );

  for (final point in [
    MailStoreCheckpoint.afterSyncRecords,
    MailStoreCheckpoint.beforeSyncCursor,
    MailStoreCheckpoint.beforeCommit,
  ]) {
    test('page and checkpoint roll back together at ${point.name}', () async {
      _value(await commit(_page('first', headers: [_header(1)], more: true)));
      final before = snapshot();
      failAt = point;
      now = _now.add(const Duration(minutes: 1));
      _problem(
        await commit(
          _page('done', reset: true, headers: [_header(2)]),
          expected: 'first',
        ),
        MailProblemCode.storageFailure,
      );
      expect(snapshot(), before);
      expect(_value(await store.loadSyncMailbox(_mailbox))!.hasMore, isTrue);
      failAt = null;
      _value(
        await commit(
          _page('done', reset: true, headers: [_header(2)]),
          expected: 'first',
        ),
      );
      expect(_value(await store.loadSyncMailbox(_mailbox))!.revision, 2);
      expect(_value(await store.readCursor(_mailbox))!.value, 'done');
    });
  }

  test(
    'cursor conflict and invalidated lease cannot alter completion',
    () async {
      _value(await commit(_page('done', headers: [_header(1)])));
      final before = snapshot();
      _problem(
        await commit(_page('stale', more: true), expected: 'wrong'),
        MailProblemCode.conflict,
      );
      expect(snapshot(), before);
      invalidateCommit = true;
      _problem(
        await commit(_page('late', more: true), expected: 'done'),
        MailProblemCode.staleOperation,
      );
      expect(snapshot(), before);
      expect(_value(await store.loadSyncMailbox(_mailbox))!.hasMore, isFalse);
    },
  );

  test(
    'reset reconciles pending operations while preserving local drafts and journal',
    () async {
      final original = _header(1);
      _value(await commit(_page('old', headers: [original])));
      _value(
        await store.saveDraft(
          MailDraft(
            id: 'draft',
            account: _account,
            revision: 0,
            envelope: MailEnvelope(subject: 'Unsent'),
            body: const MailBody(plainText: 'Retained work'),
          ),
          expectedRevision: null,
        ),
      );
      _value(
        await store.enqueueOperation(
          MailSetRead(id: 'edit', message: original.remote, read: false),
          session.begin(),
        ),
      );
      final plan = MailBulkFlagPlan(
        id: 'journal',
        mailbox: _mailbox,
        action: MailBulkFlagAction.flag,
        messages: [original.remote],
      );
      _value(
        await store.createFlagBatch(
          plan,
          subjects: ['Retained subject'],
          lease: session.begin(),
        ),
      );
      final journal = database
          .select('SELECT * FROM flag_batch_items')
          .map((row) => Map<String, Object?>.from(row))
          .toList();
      _value(
        await commit(
          _page('new', reset: true, headers: [_header(1, validity: 8)]),
          expected: 'old',
        ),
      );
      final synced = _value(await store.loadSyncMailbox(_mailbox))!;
      expect(synced.headers.single.remote, _header(1, validity: 8).remote);
      expect(synced.revision, 2);
      expect(
        _value(await store.pendingOperations(_account)).single.state,
        MailPendingState.reconcile,
      );
      expect(
        _value(await store.loadDraft(_account, 'draft'))!.body.plainText,
        'Retained work',
      );
      expect(
        database
            .select('SELECT * FROM flag_batch_items')
            .map((row) => Map<String, Object?>.from(row))
            .toList(),
        journal,
      );
    },
  );

  test(
    'tombstones change header count without deleting the checkpoint',
    () async {
      _value(await commit(_page('first', headers: [_header(1), _header(2)])));
      _value(
        await commit(
          _page('second', tombstones: [_header(1).remote]),
          expected: 'first',
        ),
      );
      final view = _value(await store.loadSyncMailbox(_mailbox))!;
      expect(view.headerCount, 1);
      expect(view.headers.single.remote, _header(2).remote);
      expect(view.revision, 2);
    },
  );

  test('read bounds and catalog truncation are explicit', () async {
    _value(await commit(_page('one')));
    _value(
      await commit(
        _page('two', mailbox: MailMailboxId('Archive', account: _account)),
      ),
    );
    for (final limit in [0, 1001]) {
      _problem(
        await store.loadSyncMailbox(_mailbox, limit: limit),
        MailProblemCode.invalidInput,
      );
      _problem(
        await store.listSyncMailboxes(_account, limit: limit),
        MailProblemCode.invalidInput,
      );
    }
    for (final offset in [-1, 100001]) {
      _problem(
        await store.loadSyncMailbox(_mailbox, offset: offset),
        MailProblemCode.invalidInput,
      );
    }
    _problem(
      await store.listSyncMailboxes(_account, limit: 1),
      MailProblemCode.quotaExceeded,
    );
    await store.close();
    store = _value(await open(limits: const MailStoreLimits(maxPageSize: 1)));
    _problem(
      await store.loadSyncMailbox(_mailbox, limit: 2),
      MailProblemCode.invalidInput,
    );
  });

  test(
    'oversized persisted headers are rejected before text transfer',
    () async {
      _value(await commit(_page('one', headers: [_header(1)])));
      database.execute('UPDATE messages SET envelope=?', [
        'x' * (9 * 1024 * 1024),
      ]);
      _problem(
        await store.loadSyncMailbox(_mailbox),
        MailProblemCode.quotaExceeded,
      );
      expect(probe.oversizedTransferred, isFalse);
      expect(probe.bodyRead, isFalse);
    },
  );

  for (final mutation in [
    "UPDATE mailbox_sync_state SET has_more='unknown'",
    'UPDATE mailbox_sync_state SET revision=0',
    'UPDATE mailbox_sync_state SET updated_at=-1',
    'DELETE FROM cursors',
    "UPDATE messages SET remote='invalid-json'",
    "UPDATE messages SET flags='unknown'",
  ]) {
    test(
      'invalid persisted snapshot returns a typed failure: $mutation',
      () async {
        _value(await commit(_page('one', headers: [_header(1)])));
        database.execute('PRAGMA ignore_check_constraints=ON');
        database.execute(mutation);
        _problem(
          await store.loadSyncMailbox(_mailbox),
          MailProblemCode.storageFailure,
        );
      },
    );
  }

  test(
    'revision exhaustion and invalid clock roll back the next page',
    () async {
      _value(await commit(_page('one', headers: [_header(1)])));
      database.execute(
        'UPDATE mailbox_sync_state SET revision=9007199254740991',
      );
      final before = snapshot();
      _problem(
        await commit(_page('two', headers: [_header(2)]), expected: 'one'),
        MailProblemCode.quotaExceeded,
      );
      expect(snapshot(), before);
      database.execute('UPDATE mailbox_sync_state SET revision=1');
      final valid = snapshot();
      now = DateTime.fromMillisecondsSinceEpoch(-1, isUtc: true);
      _problem(
        await commit(_page('two'), expected: 'one'),
        MailProblemCode.invalidInput,
      );
      expect(snapshot(), valid);
    },
  );

  test('account removal cleans checkpoint and blocks late access', () async {
    _value(await commit(_page('one')));
    _value(await store.removeAccount(_account));
    expect(database.select('SELECT * FROM mailbox_sync_state'), isEmpty);
    _problem(
      await store.loadSyncMailbox(_mailbox),
      MailProblemCode.unavailable,
    );
    _problem(
      await store.listSyncMailboxes(_account),
      MailProblemCode.unavailable,
    );
  });

  for (final interrupted in [false, true]) {
    test(
      'v7 migration retains legacy cursor and does not invent completion; interrupted=$interrupted',
      () async {
        _value(await commit(_page('legacy', headers: [_header(1)])));
        _value(
          await store.saveDraft(
            MailDraft(
              id: 'saved',
              account: _account,
              revision: 0,
              envelope: MailEnvelope(subject: 'Keep'),
              body: const MailBody(plainText: 'Original'),
            ),
            expectedRevision: null,
          ),
        );
        final prior = snapshot()..remove('mailbox_sync_state');
        await store.close();
        // Reconstruct the actual old schema, including removal of every
        // additive table/column introduced after v7.
        for (final trigger in database.select(
          "SELECT name FROM sqlite_master WHERE type='trigger' "
          "AND name LIKE 'membership_observation_%'",
        )) {
          database.execute('DROP TRIGGER "${trigger['name']}"');
        }
        database.execute('DROP TABLE membership_item_observations');
        database.execute('DROP TABLE saved_header_search_folders');
        database.execute('DROP TABLE account_quick_texts');
        database.execute('DROP TABLE account_compose_settings');
        database.execute('DROP TABLE saved_header_search_accounts');
        database.execute('DROP TABLE saved_header_searches');
        database.execute(
          'ALTER TABLE store_profile DROP COLUMN saved_header_search_revision',
        );
        database.execute('DROP TABLE mailbox_sync_state');
        database.execute('ALTER TABLE flag_batches DROP COLUMN destination');
        database.userVersion = 7;
        if (interrupted) {
          failAt = MailStoreCheckpoint.migrationCreated;
          _problem(await open(), MailProblemCode.storageFailure);
          expect(database.userVersion, 7);
          expect(
            database.select(
              "SELECT name FROM sqlite_master WHERE name IN "
              "('mailbox_sync_state','account_compose_settings','account_quick_texts',"
              "'saved_header_search_folders')",
            ),
            isEmpty,
          );
          failAt = null;
        }
        store = _value(await open());
        expect(database.userVersion, 14);
        expect(_value(await store.loadComposeSettings(_account)).revision, 0);
        expect(snapshot()..remove('mailbox_sync_state'), prior);
        expect(_value(await store.loadSyncMailbox(_mailbox)), isNull);
        expect(_value(await store.listSyncMailboxes(_account)), isEmpty);
        expect(_value(await store.readCursor(_mailbox))!.value, 'legacy');
        _value(await commit(_page('known'), expected: 'legacy'));
        expect(_value(await store.loadSyncMailbox(_mailbox))!.headerCount, 1);
        expect(_value(await store.loadSyncMailbox(_mailbox))!.revision, 1);
        expect(
          _value(await store.loadDraft(_account, 'saved'))!.body.plainText,
          'Original',
        );
        expect(database.select('PRAGMA foreign_key_check'), isEmpty);
      },
    );
  }

  test(
    'streams publish committed snapshots, coalesce paused reads and close',
    () async {
      final events = <MailResult<MailMailboxSyncSnapshot?>>[];
      final catalogEvents = <MailResult<List<MailMailboxSyncSummary>>>[];
      final done = Completer<void>();
      final subscription = store
          .watchSyncMailbox(_mailbox, limit: 1)
          .listen(events.add, onDone: done.complete);
      final catalog = store
          .watchSyncMailboxes(_account)
          .listen(catalogEvents.add);
      await _until(() => events.isNotEmpty && catalogEvents.isNotEmpty);
      expect(_value(events.single), isNull);
      expect(_value(catalogEvents.single), isEmpty);
      _value(await commit(_page('first', headers: [_header(1)], more: true)));
      await _until(
        () => events.any(
          (event) =>
              event is MailSuccess<MailMailboxSyncSnapshot?> &&
              event.value?.revision == 1,
        ),
      );
      subscription.pause();
      _value(
        await commit(_page('second', headers: [_header(2)]), expected: 'first'),
      );
      _value(
        await commit(
          _page('third', tombstones: [_header(1).remote]),
          expected: 'second',
        ),
      );
      failAt = MailStoreCheckpoint.beforeCommit;
      _problem(
        await commit(_page('failed', more: true), expected: 'third'),
        MailProblemCode.storageFailure,
      );
      failAt = null;
      subscription.resume();
      await _until(
        () => events.any(
          (event) =>
              event is MailSuccess<MailMailboxSyncSnapshot?> &&
              event.value?.revision == 3,
        ),
      );
      final last = _value(events.last)!;
      expect(last.headers.single.remote, _header(2).remote);
      expect(last.hasMore, isFalse);
      expect(
        events.whereType<MailSuccess<MailMailboxSyncSnapshot?>>().any(
          (event) => event.value?.revision == 4,
        ),
        isFalse,
      );
      await store.close();
      await done.future.timeout(const Duration(seconds: 3));
      final closed = await store.watchSyncMailbox(_mailbox).toList();
      expect(closed, hasLength(1));
      _problem(closed.single, MailProblemCode.unavailable);
      await subscription.cancel();
      await catalog.cancel();
    },
  );
}

Future<void> _until(bool Function() complete) async {
  for (var attempt = 0; attempt < 300; attempt++) {
    if (complete()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Snapshot was not delivered');
}
