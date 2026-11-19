@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:quds_mail_store/src/codec.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:test/test.dart';

T _value<T>(MailResult<T> result) {
  expect(result, isA<MailSuccess<T>>());
  return (result as MailSuccess<T>).value;
}

void _problem<T>(MailResult<T> result, MailProblemCode code) {
  expect(result, isA<MailFailure<T>>());
  expect((result as MailFailure<T>).problem.code, code);
}

final class _Fixture {
  _Fixture(this.database, this.store, this.account)
    : mailbox = MailMailboxId('INBOX', account: account),
      session = MailAccountSession(account);

  final sqlite.Database database;
  SqliteMailRepository store;
  final MailAccountId account;
  final MailMailboxId mailbox;
  final MailAccountSession session;

  MailHeaderRecord header(
    int uid, {
    int validity = 1,
    MailMailboxId? mailbox,
    String? id,
    String subject = 'Observed message',
  }) {
    final target = mailbox ?? this.mailbox;
    return MailHeaderRecord(
      id: MailMessageId(id ?? '${target.value}-$validity-$uid'),
      remote: MailImapIdentity(
        mailbox: target,
        uidValidity: validity,
        uid: uid,
      ),
      envelope: MailEnvelope(subject: subject),
    );
  }

  MailSyncPage page(
    String cursor, {
    List<MailHeaderRecord> upserts = const [],
    List<MailRemoteIdentity> tombstones = const [],
    MailMailboxId? mailbox,
    int validity = 1,
    int? first,
    int last = 0xffffffff,
    bool reset = false,
  }) {
    final target = mailbox ?? this.mailbox;
    return MailSyncPage(
      mailbox: target,
      upserts: upserts,
      tombstones: tombstones,
      next: MailCursor(mailbox: target, value: cursor),
      hasMore: false,
      resetRequired: reset,
      imapRange: first == null
          ? null
          : MailImapSyncRange(
              mailbox: target,
              uidValidity: validity,
              firstUid: first,
              lastUid: last,
            ),
    );
  }

  Future<MailResult<MailUnit>> commit(
    MailSyncPage page, {
    String? expected,
    MailOperationLease? lease,
  }) => store.commitSyncPage(
    page,
    expectedCursor: expected == null
        ? null
        : MailCursor(mailbox: page.mailbox, value: expected),
    lease:
        lease ??
        (page.mailbox.account == account
            ? session.begin()
            : MailAccountSession(page.mailbox.account).begin()),
  );

  Future<List<MailRemoteIdentity>> identities([MailMailboxId? target]) async =>
      [
        for (final record in _value(
          await store.listHeaders(
            target ?? mailbox,
            limit: store.limits.maxPageSize,
          ),
        ))
          record.remote,
      ];

  List<MailRemoteIdentity> tombstones() => [
    for (final row in database.select(
      'SELECT remote FROM tombstones WHERE account=? AND mailbox=? ORDER BY remote',
      [account.value, mailbox.value],
    ))
      MailStoreCodec.decodeRemote(row['remote'] as String, account: account),
  ];

  Map<String, List<Map<String, Object?>>> snapshot() => {
    for (final (table, order) in const [
      ('accounts', 'id'),
      ('mailboxes', 'account,id'),
      ('messages', 'account,id'),
      ('memberships', 'account,mailbox,message'),
      ('cursors', 'account,mailbox'),
      ('tombstones', 'account,mailbox,remote'),
      ('pending_operations', 'account,id'),
      ('mail_fts', 'account,message'),
      ('index_state', 'account,message'),
    ])
      table: [
        for (final row in database.select(
          'SELECT * FROM $table ORDER BY $order',
        ))
          Map<String, Object?>.from(row),
      ],
  };
}

Future<_Fixture> _fixture({
  MailStoreLimits limits = const MailStoreLimits(),
  MailStoreFaultInjector? fault,
}) async {
  final profile = MailProfileId('range-tests', hostId: 'office');
  final account = MailAccountId('account', profile: profile);
  final database = sqlite.sqlite3.openInMemory();
  final store = _value(
    await SqliteMailRepository.open(
      executor: NativeDatabase.opened(database, closeUnderlyingOnClose: false),
      profile: profile,
      limits: limits,
      faultInjector: fault,
    ),
  );
  final fixture = _Fixture(database, store, account);
  addTearDown(() async {
    await fixture.store.close();
    database.close();
  });
  _value(
    await store.createAccount(
      MailStoreAccount(
        id: account,
        provider: MailProviderKind.imap,
        displayName: 'Range fixture',
      ),
    ),
  );
  return fixture;
}

void main() {
  test(
    'sparse full-width ranges create tombstones only for stored absences',
    () async {
      final f = await _fixture();
      _value(
        await f.commit(
          f.page(
            'seed',
            upserts: [f.header(1), f.header(500000), f.header(0xfffffffe)],
          ),
        ),
      );
      final survivor = f.header(0xffffffff);
      _value(
        await f.commit(
          f.page('observed', first: 100000, upserts: [survivor]),
          expected: 'seed',
        ),
      );
      expect(
        await f.identities(),
        unorderedEquals([f.header(1).remote, survivor.remote]),
      );
      expect(
        f.tombstones(),
        unorderedEquals([f.header(500000).remote, f.header(0xfffffffe).remote]),
      );
      expect(f.database.select('SELECT * FROM messages'), hasLength(2));
      expect(_value(await f.store.readCursor(f.mailbox))!.value, 'observed');
      _value(
        await f.commit(
          f.page('repeat', first: 100000, upserts: [survivor]),
          expected: 'observed',
        ),
      );
      expect(f.tombstones(), hasLength(2));
    },
  );

  test(
    'empty observations advance the cursor without materializing UID holes',
    () async {
      final f = await _fixture();
      _value(await f.commit(f.page('empty', first: 1)));
      expect(await f.identities(), isEmpty);
      expect(f.tombstones(), isEmpty);
      expect(f.database.select('SELECT * FROM messages'), isEmpty);
      expect(_value(await f.store.readCursor(f.mailbox))!.value, 'empty');
    },
  );

  test(
    'inclusive range removal preserves mailbox, account and validity isolation',
    () async {
      final f = await _fixture();
      final archive = MailMailboxId('Archive', account: f.account);
      final other = MailAccountId('other', profile: f.account.profile);
      final otherInbox = MailMailboxId('INBOX', account: other);
      _value(
        await f.store.createAccount(
          MailStoreAccount(
            id: other,
            provider: MailProviderKind.imap,
            displayName: 'Other',
          ),
        ),
      );
      final original = [
        for (final uid in [9, 10, 15, 20, 21]) f.header(uid),
        f.header(10, validity: 2),
      ];
      _value(await f.commit(f.page('seed', upserts: original)));
      for (final target in [archive, otherInbox]) {
        _value(
          await f.commit(
            f.page(
              'independent',
              mailbox: target,
              upserts: [f.header(10, mailbox: target)],
            ),
          ),
        );
      }
      _value(
        await f.commit(
          f.page('observed', first: 10, last: 20, upserts: [f.header(15)]),
          expected: 'seed',
        ),
      );
      expect(
        await f.identities(),
        unorderedEquals([
          f.header(9).remote,
          f.header(15).remote,
          f.header(21).remote,
          f.header(10, validity: 2).remote,
        ]),
      );
      for (final target in [archive, otherInbox]) {
        expect(await f.identities(target), [
          f.header(10, mailbox: target).remote,
        ]);
        expect(_value(await f.store.readCursor(target))!.value, 'independent');
      }
      expect(
        f.tombstones(),
        unorderedEquals([f.header(10).remote, f.header(20).remote]),
      );
      expect(f.database.select('SELECT * FROM tombstones'), hasLength(2));
    },
  );

  test(
    'absent queued and applying edits reconcile while their cached bytes survive',
    () async {
      final f = await _fixture();
      final headers = [
        for (final uid in [10, 11, 12]) f.header(uid),
      ];
      _value(await f.commit(f.page('seed', upserts: headers)));
      final bytes = MailBytes(Uint8List.fromList([1, 3, 5, 7]));
      _value(
        await f.store.cacheMessage(
          f.account,
          headers.first.id,
          MailMessage(
            raw: bytes,
            localId: headers.first.id,
            remoteIdentity: headers.first.remote,
            envelope: headers.first.envelope,
            body: const MailBody(plainText: 'Pending edit evidence'),
          ),
        ),
      );
      for (var i = 0; i < headers.length; i++) {
        _value(
          await f.store.enqueueOperation(
            MailSetRead(id: 'edit-$i', message: headers[i].remote, read: true),
            f.session.begin(),
          ),
        );
      }
      _value(
        await f.store.transitionOperation(
          f.account,
          'edit-1',
          expectedRevision: 0,
          state: MailPendingState.applying,
          lease: f.session.begin(),
        ),
      );
      _value(
        await f.commit(
          f.page('observed', first: 1, upserts: [headers.last]),
          expected: 'seed',
        ),
      );
      final pending = {
        for (final entry in _value(await f.store.pendingOperations(f.account)))
          entry.operation.id: entry,
      };
      expect(pending['edit-0']!.state, MailPendingState.reconcile);
      expect(pending['edit-0']!.revision, 1);
      expect(pending['edit-1']!.state, MailPendingState.reconcile);
      expect(pending['edit-1']!.revision, 2);
      expect(pending['edit-2']!.state, MailPendingState.queued);
      expect(pending['edit-2']!.revision, 0);
      expect(await f.identities(), [headers.last.remote]);
      expect(
        _value(
          await f.store.loadCachedMessage(f.account, headers.first.id),
        )!.raw.sha256,
        bytes.sha256,
      );
    },
  );

  for (final point in [
    MailStoreCheckpoint.afterSyncRecords,
    MailStoreCheckpoint.beforeSyncCursor,
    MailStoreCheckpoint.beforeCommit,
  ]) {
    test(
      'range deletes, edits, indexes and cursor roll back at ${point.name} then retry',
      () async {
        var fail = false;
        final f = await _fixture(
          fault: (observed) {
            if (fail && observed == point) {
              throw const MailStoreStorageException(
                MailProblemCode.storageFailure,
              );
            }
          },
        );
        _value(
          await f.commit(
            f.page('seed', upserts: [f.header(1), f.header(2), f.header(3)]),
          ),
        );
        _value(
          await f.store.enqueueOperation(
            MailDelete(id: 'pending', message: f.header(1).remote),
            f.session.begin(),
          ),
        );
        final before = f.snapshot();
        final update = f.page(
          'observed',
          first: 1,
          upserts: [
            f.header(2, subject: 'Changed survivor'),
            f.header(4),
          ],
        );
        fail = true;
        _problem(
          await f.commit(update, expected: 'seed'),
          MailProblemCode.storageFailure,
        );
        expect(f.snapshot(), before);
        fail = false;
        _value(await f.commit(update, expected: 'seed'));
        expect(
          await f.identities(),
          unorderedEquals([f.header(2).remote, f.header(4).remote]),
        );
        expect(
          f.tombstones(),
          unorderedEquals([f.header(1).remote, f.header(3).remote]),
        );
        expect(
          _value(await f.store.pendingOperations(f.account)).single.state,
          MailPendingState.reconcile,
        );
        expect(_value(await f.store.readCursor(f.mailbox))!.value, 'observed');
        expect(
          _value(await f.store.search(f.account, 'Changed')).single.header.id,
          f.header(2).id,
        );
      },
    );
  }

  test(
    'stale range observations cannot delete the winning page or its pending edits',
    () async {
      final f = await _fixture();
      _value(
        await f.commit(f.page('seed', upserts: [f.header(1), f.header(2)])),
      );
      _value(
        await f.store.enqueueOperation(
          MailSetFlagged(
            id: 'pending',
            message: f.header(2).remote,
            flagged: true,
          ),
          f.session.begin(),
        ),
      );
      _value(
        await f.commit(
          f.page('winner', first: 1, upserts: [f.header(2), f.header(3)]),
          expected: 'seed',
        ),
      );
      final before = f.snapshot();
      _problem(
        await f.commit(f.page('stale', first: 1), expected: 'seed'),
        MailProblemCode.conflict,
      );
      expect(f.snapshot(), before);
    },
  );

  test(
    'account lease invalidation rolls back range removals and reconciliation',
    () async {
      MailAccountSession? invalidate;
      final f = await _fixture(
        fault: (point) {
          if (point == MailStoreCheckpoint.beforeSyncCursor) {
            invalidate?.invalidate();
          }
        },
      );
      _value(await f.commit(f.page('seed', upserts: [f.header(1)])));
      _value(
        await f.store.enqueueOperation(
          MailDelete(id: 'pending', message: f.header(1).remote),
          f.session.begin(),
        ),
      );
      final before = f.snapshot();
      invalidate = f.session;
      _problem(
        await f.commit(f.page('invalidated', first: 1), expected: 'seed'),
        MailProblemCode.staleOperation,
      );
      expect(f.snapshot(), before);
    },
  );

  test(
    'page limits, duplicate identities and metadata fail before range removals',
    () async {
      final f = await _fixture(
        limits: const MailStoreLimits(
          maxPageSize: 2,
          maxMetadataCodeUnits: 100,
        ),
      );
      _value(await f.commit(f.page('seed', upserts: [f.header(1)])));
      final before = f.snapshot();
      for (final invalid in [
        f.page(
          'too-many',
          first: 1,
          upserts: [f.header(2), f.header(3), f.header(4)],
        ),
        f.page(
          'duplicate-remote',
          first: 1,
          upserts: [
            f.header(2),
            f.header(2, id: 'other-id'),
          ],
        ),
        f.page(
          'duplicate-id',
          first: 1,
          upserts: [
            f.header(2),
            f.header(3, id: f.header(2).id.value),
          ],
        ),
        f.page(
          'overlap',
          first: 1,
          upserts: [f.header(2)],
          tombstones: [f.header(2).remote],
        ),
      ]) {
        _problem(
          await f.commit(invalid, expected: 'seed'),
          MailProblemCode.invalidInput,
        );
        expect(f.snapshot(), before);
      }
      _problem(
        await f.commit(
          f.page(
            'metadata',
            first: 1,
            upserts: [f.header(2, subject: 'x' * 101)],
          ),
          expected: 'seed',
        ),
        MailProblemCode.quotaExceeded,
      );
      expect(f.snapshot(), before);
    },
  );

  test(
    'empty IMAP ranges reject a non-IMAP account and foreign account lease',
    () async {
      final f = await _fixture();
      final other = MailAccountId('graph', profile: f.account.profile);
      final graphInbox = MailMailboxId('INBOX', account: other);
      _value(
        await f.store.createAccount(
          MailStoreAccount(
            id: other,
            provider: MailProviderKind.graph,
            displayName: 'Graph',
          ),
        ),
      );
      final before = f.snapshot();
      _problem(
        await f.commit(
          f.page('unsupported-account', first: 1, mailbox: graphInbox),
        ),
        MailProblemCode.invalidInput,
      );
      expect(f.snapshot(), before);
      _problem(
        await f.commit(
          f.page('foreign-lease', first: 1),
          lease: MailAccountSession(other).begin(),
        ),
        MailProblemCode.invalidInput,
      );
      expect(f.snapshot(), before);
    },
  );

  test(
    'reopening above the configured scan bound refuses range work without data loss',
    () async {
      final f = await _fixture(
        limits: const MailStoreLimits(maxMessagesPerAccount: 3),
      );
      _value(
        await f.commit(
          f.page('seed', upserts: [f.header(1), f.header(2), f.header(3)]),
        ),
      );
      await f.store.close();
      f.store = _value(
        await SqliteMailRepository.open(
          executor: NativeDatabase.opened(
            f.database,
            closeUnderlyingOnClose: false,
          ),
          profile: f.account.profile,
          limits: const MailStoreLimits(maxMessagesPerAccount: 2),
        ),
      );
      final before = f.snapshot();
      _problem(
        await f.commit(f.page('too-large', first: 1), expected: 'seed'),
        MailProblemCode.quotaExceeded,
      );
      expect(f.snapshot(), before);
    },
  );

  test(
    'existing range removals may exceed the incoming page row count',
    () async {
      final f = await _fixture(
        limits: const MailStoreLimits(maxPageSize: 1, maxMessagesPerAccount: 4),
      );
      for (var uid = 1; uid <= 4; uid++) {
        _value(
          await f.commit(
            f.page('seed-$uid', upserts: [f.header(uid)]),
            expected: uid == 1 ? null : 'seed-${uid - 1}',
          ),
        );
      }
      _value(
        await f.commit(
          f.page('observed', first: 1, upserts: [f.header(4)]),
          expected: 'seed-4',
        ),
      );
      expect(await f.identities(), [f.header(4).remote]);
      expect(f.tombstones(), hasLength(3));
    },
  );

  test(
    'explicit tombstones coexist with authoritative range removals',
    () async {
      final f = await _fixture();
      _value(
        await f.commit(
          f.page('seed', upserts: [f.header(1), f.header(2), f.header(3)]),
        ),
      );
      _value(
        await f.store.enqueueOperation(
          MailDelete(id: 'pending', message: f.header(1).remote),
          f.session.begin(),
        ),
      );
      _value(
        await f.commit(
          f.page(
            'observed',
            first: 1,
            upserts: [f.header(3)],
            tombstones: [f.header(1).remote],
          ),
          expected: 'seed',
        ),
      );
      expect(await f.identities(), [f.header(3).remote]);
      expect(
        f.tombstones(),
        unorderedEquals([f.header(1).remote, f.header(2).remote]),
      );
      expect(
        _value(await f.store.pendingOperations(f.account)).single.revision,
        1,
      );
    },
  );

  test(
    'resetRequired retains full-mailbox reset across ranges and UID generations',
    () async {
      final f = await _fixture();
      _value(
        await f.commit(
          f.page('seed', upserts: [f.header(1), f.header(100, validity: 2)]),
        ),
      );
      _value(
        await f.store.enqueueOperation(
          MailDelete(id: 'pending', message: f.header(1).remote),
          f.session.begin(),
        ),
      );
      final replacement = f.header(100000, validity: 3);
      _value(
        await f.commit(
          f.page(
            'reset',
            first: 100000,
            validity: 3,
            upserts: [replacement],
            reset: true,
          ),
          expected: 'seed',
        ),
      );
      expect(await f.identities(), [replacement.remote]);
      expect(
        f.tombstones(),
        unorderedEquals([
          f.header(1).remote,
          f.header(100, validity: 2).remote,
        ]),
      );
      expect(
        _value(await f.store.pendingOperations(f.account)).single.state,
        MailPendingState.reconcile,
      );
    },
  );
}
