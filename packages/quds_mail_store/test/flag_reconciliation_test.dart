@TestOn('vm')
library;

import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:quds_mail_store/src/codec.dart';
import 'package:quds_mail_store/src/schema/database.dart'
    show schemaV1, schemaV2, schemaV3, schemaV4, schemaV5;
import 'package:quds_mail_store/src/schema/flag_journal_schema.dart'
    show schemaV6;
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:test/test.dart';

final _profile = MailProfileId('reconciliation', hostId: 'test-office');
final _account = MailAccountId('account', profile: _profile);
final _mailbox = MailMailbox(
  id: MailMailboxId('INBOX', account: _account),
  displayName: 'Inbox',
);
final _now = DateTime.utc(2026, 11, 21);
const _uncertainProblem = MailProblem(
  MailProblemCode.providerFailure,
  retryAfter: Duration(seconds: 37),
  mutationMayHaveOccurred: true,
);

T _value<T>(MailResult<T> result) {
  expect(result, isA<MailSuccess<T>>());
  return (result as MailSuccess<T>).value;
}

void _problem<T>(MailResult<T> result, MailProblemCode code) {
  expect(result, isA<MailFailure<T>>());
  expect((result as MailFailure<T>).problem.code, code);
}

MailBulkFlagPlan _plan({
  String id = 'batch',
  MailBulkFlagAction action = MailBulkFlagAction.markRead,
  int validity = 7,
}) => MailBulkFlagPlan(
  id: id,
  mailbox: _mailbox.id,
  action: action,
  messages: [
    MailImapIdentity(mailbox: _mailbox.id, uidValidity: validity, uid: 1),
  ],
);

void main() {
  late Directory directory;
  late File file;
  late SqliteMailRepository store;
  late MailAccountSession session;
  var failCommit = false;
  void Function()? beforeCommit;
  var now = _now;

  Future<MailResult<SqliteMailRepository>> open({
    bool failMigration = false,
  }) => SqliteMailRepository.open(
    executor: NativeDatabase(file),
    profile: _profile,
    clock: () => now,
    faultInjector: (point) {
      if (point == MailStoreCheckpoint.migrationCreated && failMigration) {
        throw const MailStoreStorageException(MailProblemCode.storageFailure);
      }
      if (point != MailStoreCheckpoint.beforeCommit) return;
      beforeCommit?.call();
      if (failCommit) {
        throw const MailStoreStorageException(MailProblemCode.storageFailure);
      }
    },
  );

  Future<void> reopen() async {
    await store.close();
    store = _value(await open());
  }

  Future<MailStoredFlagBatch> load([String id = 'batch']) async =>
      _value<MailStoredFlagBatch?>(await store.loadFlagBatch(_account, id))!;

  Future<MailFlagBatchHandle> create(MailBulkFlagPlan plan) async => _value(
    await store.createFlagBatch(
      plan,
      subjects: const ['Retained subject'],
      lease: session.begin(),
    ),
  );

  Future<MailStoredFlagBatch> uncertain(MailBulkFlagPlan plan) async {
    final handle = await create(plan);
    _value(await store.beginFlagAttempt(handle, 0, lease: session.begin()));
    final result = MailBulkFlagItemResult.restore(
      operation: plan.operationAt(0),
      outcome: MailBulkFlagOutcome.uncertain,
      problem: _uncertainProblem,
    );
    _value(await store.recordFlagResult(handle, 0, result));
    _value(
      await store.finishFlagBatch(
        handle,
        MailBulkFlagReport.restore(
          plan: plan,
          results: [result],
          stopReason: MailBulkFlagStopReason.uncertain,
          stopProblem: _uncertainProblem,
        ),
      ),
    );
    return load(plan.id);
  }

  Future<MailFlagReconciliationHandle> begin(
    MailOperationLease lease, {
    String id = 'batch',
    bool Function()? isCurrent,
  }) async {
    final batch = await load(id);
    return _value(
      await store.beginFlagReconciliation(
        _account,
        id,
        0,
        expectedRevision: batch.summary.revision,
        lease: lease,
        isCurrent: isCurrent,
      ),
    );
  }

  Future<MailCachedMailboxView> cache(
    MailBulkFlagPlan plan,
    MailMessageFlags? flags,
  ) async => _value(
    await store.saveMailboxView(
      _mailbox,
      [
        MailHeaderRecord(
          id: MailMessageId('cached'),
          remote: plan.messages.single,
          envelope: MailEnvelope(subject: 'Cached subject'),
          flags: flags,
        ),
      ],
      expectedRevision: _value(
        await store.loadMailboxView(_mailbox.id),
      )?.revision,
      hasMore: true,
      lease: session.begin(),
    ),
  );

  MailFlagObservation present(
    MailRemoteIdentity identity, {
    bool read = true,
    bool flagged = false,
  }) => MailFlagObservation.present(
    identity: identity,
    flags: MailMessageFlags(isRead: read, isFlagged: flagged),
  );

  void preserved(MailStoredFlagBatch batch) {
    expect(batch.report.uncertainCount, 1);
    expect(batch.report.confirmedCount, 0);
    expect(batch.report.results.single.outcome, MailBulkFlagOutcome.uncertain);
    expect(batch.report.results.single.problem!.code, _uncertainProblem.code);
    expect(
      batch.report.results.single.problem!.retryAfter,
      _uncertainProblem.retryAfter,
    );
    expect(
      batch.report.results.single.problem!.mutationMayHaveOccurred,
      isTrue,
    );
    expect(batch.report.stopReason, MailBulkFlagStopReason.uncertain);
    expect(batch.report.stopProblem!.retryAfter, _uncertainProblem.retryAfter);
    expect(batch.subjects, ['Retained subject']);
  }

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    directory = await Directory.systemTemp.createTemp('quds-flag-check-');
    file = File('${directory.path}/mail.sqlite3');
    session = MailAccountSession(_account);
    failCommit = false;
    beforeCommit = null;
    now = _now;
    store = _value(await open());
    _value(
      await store.createAccount(
        MailStoreAccount(
          id: _account,
          provider: MailProviderKind.imap,
          displayName: 'Account',
        ),
      ),
    );
  });
  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });

  for (final action in MailBulkFlagAction.values.where((a) => a.isFlagAction)) {
    for (final matches in [true, false]) {
      test(
        '$action observed matches=$matches preserves history and other bits',
        () async {
          final plan = _plan(action: action);
          final before = await cache(
            plan,
            const MailMessageFlags(
              isRead: true,
              isFlagged: true,
              isAnswered: true,
              isDraft: true,
              isDeleted: true,
            ),
          );
          final original = await uncertain(plan);
          final lease = session.begin();
          final handle = await begin(lease);
          final requested =
              action == MailBulkFlagAction.markRead ||
              action == MailBulkFlagAction.flag;
          final observed = matches ? requested : !requested;
          final readAction =
              action == MailBulkFlagAction.markRead ||
              action == MailBulkFlagAction.markUnread;
          now = now.add(const Duration(minutes: 1));
          _value(
            await store.recordFlagObservation(
              handle,
              present(
                handle.message,
                read: readAction && observed,
                flagged: !readAction && observed,
              ),
              lease: lease,
            ),
          );
          final saved = await load();
          preserved(saved);
          expect(saved.summary.uncertainCount, 1);
          expect(saved.summary.reconciledCount, 1);
          expect(saved.summary.unresolvedCount, 0);
          expect(saved.summary.requiresRefresh, isFalse);
          expect(saved.summary.revision, original.summary.revision + 1);
          expect(saved.resolutions.single.index, 0);
          expect(
            saved.resolutions.single.kind,
            matches
                ? MailFlagResolutionKind.matches
                : MailFlagResolutionKind.differs,
          );
          expect(saved.resolutions.single.checkedAt, now);
          expect(() => saved.resolutions.clear(), throwsUnsupportedError);
          final view = _value(await store.loadMailboxView(_mailbox.id))!;
          final flags = view.headers.single.flags!;
          expect(flags.isRead, readAction ? observed : isTrue);
          expect(flags.isFlagged, readAction ? isTrue : observed);
          expect(flags.isAnswered, isTrue);
          expect(flags.isDraft, isTrue);
          expect(flags.isDeleted, isTrue);
          expect(view.capturedAt, before.capturedAt);
          expect(view.hasMore, before.hasMore);
          expect(view.revision, greaterThan(before.revision));
          _problem(
            await store.saveMailboxView(
              _mailbox,
              before.headers,
              expectedRevision: before.revision,
              hasMore: false,
              lease: session.begin(),
            ),
            MailProblemCode.conflict,
          );
          await reopen();
          final reopened = await load();
          preserved(reopened);
          expect(
            reopened.resolutions.single.kind,
            saved.resolutions.single.kind,
          );
          expect(reopened.resolutions.single.checkedAt, now);
          expect(reopened.summary.reconciledCount, 1);
        },
      );
    }
  }

  for (final changed in [false, true]) {
    test(
      'definitive ${changed ? 'generation change' : 'absence'} resolves without cache eviction',
      () async {
        final plan = _plan();
        final current = _plan(validity: 8);
        final before = await cache(
          current,
          const MailMessageFlags(isFlagged: true),
        );
        await uncertain(plan);
        final lease = session.begin();
        final handle = await begin(lease);
        _value(
          await store.recordFlagObservation(
            handle,
            changed
                ? MailFlagObservation.identityChanged(
                    identity: handle.message as MailImapIdentity,
                  )
                : MailFlagObservation.missing(identity: handle.message),
            lease: lease,
          ),
        );
        final saved = await load();
        preserved(saved);
        expect(saved.summary.unresolvedCount, 0);
        expect(
          saved.resolutions.single.kind,
          changed
              ? MailFlagResolutionKind.identityChanged
              : MailFlagResolutionKind.missing,
        );
        final after = _value(await store.loadMailboxView(_mailbox.id))!;
        expect(after.revision, before.revision);
        expect(after.headers.single.remote, current.messages.single);
        expect(after.headers.single.flags, before.headers.single.flags);
      },
    );
  }

  test(
    'unknown flags remain unknown while an observed check fences old view writers',
    () async {
      final plan = _plan();
      final before = await cache(plan, null);
      await uncertain(plan);
      final lease = session.begin();
      final handle = await begin(lease);
      _value(
        await store.recordFlagObservation(
          handle,
          present(handle.message),
          lease: lease,
        ),
      );
      final after = _value(await store.loadMailboxView(_mailbox.id))!;
      expect(after.headers.single.flags, isNull);
      expect(after.revision, greaterThan(before.revision));
    },
  );

  test(
    'a present old UIDVALIDITY cannot change a newer cached identity',
    () async {
      final plan = _plan();
      final before = await cache(_plan(validity: 8), const MailMessageFlags());
      await uncertain(plan);
      final lease = session.begin();
      final handle = await begin(lease);
      _value(
        await store.recordFlagObservation(
          handle,
          present(handle.message),
          lease: lease,
        ),
      );
      final after = _value(await store.loadMailboxView(_mailbox.id))!;
      expect(after.headers.single.flags!.isRead, isFalse);
      expect(after.revision, before.revision);
    },
  );

  for (final mutation in [
    'uid',
    'validity',
    'mailbox',
    'account',
    'provider',
  ]) {
    test(
      'observation with mismatched $mutation cannot resolve another target',
      () async {
        await uncertain(_plan());
        final lease = session.begin();
        final handle = await begin(lease);
        final original = handle.message as MailImapIdentity;
        final identity = mutation == 'provider'
            ? MailOpaqueIdentity(
                account: _account,
                provider: MailProviderKind.graph,
                value: '1',
              )
            : MailImapIdentity(
                mailbox: MailMailboxId(
                  mutation == 'mailbox' ? 'Other' : original.mailbox.value,
                  account: mutation == 'account'
                      ? MailAccountId('other', profile: _profile)
                      : _account,
                ),
                uidValidity: mutation == 'validity' ? 8 : 7,
                uid: mutation == 'uid' ? 2 : 1,
              );
        _problem(
          await store.recordFlagObservation(
            handle,
            present(identity),
            lease: lease,
          ),
          MailProblemCode.conflict,
        );
        expect((await load()).resolutions, isEmpty);
      },
    );
  }

  test(
    'completed uncertain receipt and exact revision are mandatory before a check',
    () async {
      final plan = _plan();
      final pending = await create(plan);
      final revision = (await load()).summary.revision;
      _problem(
        await store.beginFlagReconciliation(
          _account,
          plan.id,
          0,
          expectedRevision: revision,
          lease: session.begin(),
        ),
        MailProblemCode.conflict,
      );
      _value(await store.beginFlagAttempt(pending, 0, lease: session.begin()));
      await reopen();
      final batch = await load();
      for (final (index, rev) in [
        (0, revision),
        (-1, batch.summary.revision),
        (1, batch.summary.revision),
      ]) {
        _problem(
          await store.beginFlagReconciliation(
            _account,
            plan.id,
            index,
            expectedRevision: rev,
            lease: session.begin(),
          ),
          MailProblemCode.conflict,
        );
      }
      final other = MailAccountSession(
        MailAccountId('other', profile: _profile),
      );
      _problem(
        await store.beginFlagReconciliation(
          _account,
          plan.id,
          0,
          expectedRevision: batch.summary.revision,
          lease: other.begin(),
        ),
        MailProblemCode.invalidInput,
      );
      final lease = session.begin();
      final handle = await begin(lease);
      _value(
        await store.recordFlagObservation(
          handle,
          present(handle.message),
          lease: lease,
        ),
      );
      _problem(
        await store.beginFlagReconciliation(
          _account,
          plan.id,
          0,
          expectedRevision: (await load()).summary.revision,
          lease: session.begin(),
        ),
        MailProblemCode.conflict,
      );
    },
  );

  test(
    'a second handle and a repeated observation cannot replace immutable resolution',
    () async {
      await uncertain(_plan());
      final lease = session.begin();
      final first = await begin(lease);
      final second = await begin(lease);
      _value(
        await store.recordFlagObservation(
          first,
          present(first.message),
          lease: lease,
        ),
      );
      for (final handle in [first, second]) {
        _problem(
          await store.recordFlagObservation(
            handle,
            present(handle.message, read: false),
            lease: lease,
          ),
          MailProblemCode.conflict,
        );
      }
      expect(
        (await load()).resolutions.single.kind,
        MailFlagResolutionKind.matches,
      );
    },
  );

  for (final replace in [false, true]) {
    test(
      'intervening ${replace ? 'cache replacement' : 'empty cached view'} retires observation',
      () async {
        final plan = _plan();
        final before = await cache(plan, const MailMessageFlags());
        await uncertain(plan);
        final lease = session.begin();
        final handle = await begin(lease);
        _value(
          await store.saveMailboxView(
            _mailbox,
            replace ? before.headers : [],
            expectedRevision: before.revision,
            hasMore: false,
            lease: session.begin(),
          ),
        );
        _problem(
          await store.recordFlagObservation(
            handle,
            present(handle.message),
            lease: lease,
          ),
          MailProblemCode.conflict,
        );
        expect((await load()).resolutions, isEmpty);
        final view = _value(await store.loadMailboxView(_mailbox.id))!;
        if (replace) {
          expect(view.headers.single.flags!.isRead, isFalse);
        } else {
          expect(view.headers, isEmpty);
        }
      },
    );
  }

  test(
    'a newer dispatch marker invalidates an observation before any acknowledgement',
    () async {
      await uncertain(_plan());
      final newer = await create(
        _plan(id: 'newer', action: MailBulkFlagAction.markUnread),
      );
      final lease = session.begin();
      final handle = await begin(lease);
      _value(await store.beginFlagAttempt(newer, 0, lease: session.begin()));
      _problem(
        await store.recordFlagObservation(
          handle,
          present(handle.message),
          lease: lease,
        ),
        MailProblemCode.conflict,
      );
      expect((await load()).resolutions, isEmpty);
    },
  );

  test(
    'new batch intent also invalidates an outstanding observation',
    () async {
      await uncertain(_plan());
      final lease = session.begin();
      final handle = await begin(lease);
      await create(_plan(id: 'newer'));
      _problem(
        await store.recordFlagObservation(
          handle,
          present(handle.message),
          lease: lease,
        ),
        MailProblemCode.conflict,
      );
    },
  );

  test('a reopened owner cannot accept an earlier handle', () async {
    await uncertain(_plan());
    final lease = session.begin();
    final handle = await begin(lease);
    await reopen();
    _problem(
      await store.recordFlagObservation(
        handle,
        present(handle.message),
        lease: lease,
      ),
      MailProblemCode.conflict,
    );
    expect((await load()).resolutions, isEmpty);
  });

  test('a fresh substitute lease cannot revive a captured operation', () async {
    await uncertain(_plan());
    final lease = session.begin();
    final handle = await begin(lease);
    _problem(
      await store.recordFlagObservation(
        handle,
        present(handle.message),
        lease: session.begin(),
      ),
      MailProblemCode.conflict,
    );
    session.invalidate();
    _problem(
      await store.recordFlagObservation(
        handle,
        present(handle.message),
        lease: session.begin(),
      ),
      MailProblemCode.staleOperation,
    );
  });

  test(
    'logout and resume never revive a prior observation authority',
    () async {
      await uncertain(_plan());
      final lease = session.begin();
      final handle = await begin(lease);
      _value(await store.logout(session));
      _value(
        await store.resumeAccount(
          _account,
          credentialReference: 'fresh-credential-reference',
        ),
      );
      _problem(
        await store.recordFlagObservation(
          handle,
          present(handle.message),
          lease: session.begin(),
        ),
        MailProblemCode.staleOperation,
      );
      expect((await load()).resolutions, isEmpty);
    },
  );

  for (final retired in ['cancel', 'view', 'session']) {
    test(
      '$retired retirement during commit rolls back resolution and cache atomically',
      () async {
        final plan = _plan();
        final before = await cache(plan, const MailMessageFlags());
        await uncertain(plan);
        final cancellation = MailCancellationSource();
        final lease = session.begin(cancellation: cancellation.token);
        var current = true;
        final handle = await begin(lease, isCurrent: () => current);
        beforeCommit = () {
          if (retired == 'cancel') cancellation.cancel();
          if (retired == 'view') current = false;
          if (retired == 'session') session.invalidate();
        };
        _problem(
          await store.recordFlagObservation(
            handle,
            present(handle.message),
            lease: lease,
            isCurrent: () => current,
          ),
          retired == 'cancel'
              ? MailProblemCode.cancelled
              : MailProblemCode.staleOperation,
        );
        beforeCommit = null;
        expect((await load()).resolutions, isEmpty);
        final view = _value(await store.loadMailboxView(_mailbox.id))!;
        expect(view.revision, before.revision);
        expect(view.headers.single.flags!.isRead, isFalse);
        await reopen();
        expect((await load()).summary.unresolvedCount, 1);
      },
    );
  }

  test('cancelled and retired scopes cannot begin an observation', () async {
    final batch = await uncertain(_plan());
    final cancel = MailCancellationSource();
    final lease = session.begin(cancellation: cancel.token);
    cancel.cancel();
    _problem(
      await store.beginFlagReconciliation(
        _account,
        'batch',
        0,
        expectedRevision: batch.summary.revision,
        lease: lease,
      ),
      MailProblemCode.cancelled,
    );
    _problem(
      await store.beginFlagReconciliation(
        _account,
        'batch',
        0,
        expectedRevision: batch.summary.revision,
        lease: session.begin(),
        isCurrent: () => false,
      ),
      MailProblemCode.staleOperation,
    );
  });

  test(
    'failed storage rolls back evidence, epoch and projection for a safe retry',
    () async {
      final plan = _plan();
      final before = await cache(plan, const MailMessageFlags());
      final original = await uncertain(plan);
      final lease = session.begin();
      final handle = await begin(lease);
      failCommit = true;
      _problem(
        await store.recordFlagObservation(
          handle,
          present(handle.message),
          lease: lease,
        ),
        MailProblemCode.storageFailure,
      );
      failCommit = false;
      expect((await load()).summary.revision, original.summary.revision);
      expect((await load()).resolutions, isEmpty);
      expect(
        _value(await store.loadMailboxView(_mailbox.id))!.revision,
        before.revision,
      );
      _value(
        await store.recordFlagObservation(
          handle,
          present(handle.message),
          lease: lease,
        ),
      );
      expect((await load()).summary.unresolvedCount, 0);
    },
  );

  test(
    'a backwards clock cannot give an earlier check new authority',
    () async {
      await uncertain(_plan());
      final lease = session.begin();
      final handle = await begin(lease);
      now = now.subtract(const Duration(seconds: 1));
      _problem(
        await store.recordFlagObservation(
          handle,
          present(handle.message),
          lease: lease,
        ),
        MailProblemCode.conflict,
      );
      expect((await load()).resolutions, isEmpty);
    },
  );

  test(
    'definitive reconciliation releases unresolved quota and cleanup preserves the remainder',
    () async {
      await uncertain(_plan());
      for (var i = 1; i < 100; i++) {
        await create(_plan(id: 'pending-$i'));
      }
      _problem(
        await store.createFlagBatch(
          _plan(id: 'overflow'),
          subjects: const ['Overflow'],
          lease: session.begin(),
        ),
        MailProblemCode.quotaExceeded,
      );
      final lease = session.begin();
      final handle = await begin(lease);
      _value(
        await store.recordFlagObservation(
          handle,
          MailFlagObservation.missing(identity: handle.message),
          lease: lease,
        ),
      );
      await create(_plan(id: 'new-capacity'));
      expect(_value(await store.clearCompletedFlagBatches(_account)), 1);
      expect(_value(await store.loadFlagBatch(_account, 'batch')), isNull);
      expect(
        _value(await store.listFlagBatches(_account, limit: 100)).batches,
        hasLength(100),
      );
      expect(_value(await store.clearCompletedFlagBatches(_account)), 0);
    },
  );

  for (final provider in [
    MailProviderKind.ews,
    MailProviderKind.gmail,
    MailProviderKind.graph,
  ]) {
    test(
      '$provider opaque identity observation remains account scoped',
      () async {
        final account = MailAccountId(provider.name, profile: _profile);
        final owner = MailAccountSession(account);
        _value(
          await store.createAccount(
            MailStoreAccount(
              id: account,
              provider: provider,
              displayName: provider.name,
            ),
          ),
        );
        final plan = MailBulkFlagPlan(
          id: 'opaque',
          mailbox: MailMailboxId('inbox', account: account),
          action: MailBulkFlagAction.flag,
          messages: [
            MailOpaqueIdentity(
              account: account,
              provider: provider,
              value: 'same-id',
            ),
          ],
        );
        final batchHandle = _value(
          await store.createFlagBatch(
            plan,
            subjects: const ['Opaque'],
            lease: owner.begin(),
          ),
        );
        _value(
          await store.beginFlagAttempt(batchHandle, 0, lease: owner.begin()),
        );
        final uncertain = MailBulkFlagItemResult.restore(
          operation: plan.operationAt(0),
          outcome: MailBulkFlagOutcome.uncertain,
          problem: _uncertainProblem,
        );
        _value(await store.recordFlagResult(batchHandle, 0, uncertain));
        _value(
          await store.finishFlagBatch(
            batchHandle,
            MailBulkFlagReport.restore(
              plan: plan,
              results: [uncertain],
              stopReason: MailBulkFlagStopReason.uncertain,
            ),
          ),
        );
        final batch = _value(await store.loadFlagBatch(account, 'opaque'))!;
        final lease = owner.begin();
        final handle = _value(
          await store.beginFlagReconciliation(
            account,
            'opaque',
            0,
            expectedRevision: batch.summary.revision,
            lease: lease,
          ),
        );
        final wrongAccount = MailOpaqueIdentity(
          account: _account,
          provider: provider,
          value: 'same-id',
        );
        _problem(
          await store.recordFlagObservation(
            handle,
            present(wrongAccount, flagged: true),
            lease: lease,
          ),
          MailProblemCode.conflict,
        );
        _value(
          await store.recordFlagObservation(
            handle,
            present(handle.message, flagged: true),
            lease: lease,
          ),
        );
        final resolved = _value(await store.loadFlagBatch(account, 'opaque'))!;
        expect(
          resolved.resolutions.single.kind,
          MailFlagResolutionKind.matches,
        );
        expect(
          resolved.report.results.single.outcome,
          MailBulkFlagOutcome.uncertain,
        );
        expect(resolved.summary.unresolvedCount, 0);
      },
    );
  }

  for (final corruption in ['kind', 'time', 'state', 'orphan']) {
    test(
      'corrupt $corruption evidence cannot release uncertainty or be cleaned',
      () async {
        await uncertain(_plan());
        final lease = session.begin();
        final handle = await begin(lease);
        _value(
          await store.recordFlagObservation(
            handle,
            present(handle.message),
            lease: lease,
          ),
        );
        await store.close();
        final db = sqlite.sqlite3.open(file.path);
        db.execute('PRAGMA ignore_check_constraints=ON');
        switch (corruption) {
          case 'kind':
            db.execute('UPDATE flag_item_resolutions SET kind=?', [
              'x' * 100000,
            ]);
          case 'time':
            db.execute('UPDATE flag_item_resolutions SET checked_at=-1');
          case 'state':
            db.execute(
              "UPDATE flag_batch_items SET state='unattempted',problem_code=NULL,retry_after_us=NULL,mutation_possible=NULL",
            );
          case 'orphan':
            db.execute('UPDATE flag_item_resolutions SET position=999');
        }
        db.close();
        store = _value(await open());
        _problem(
          await store.listFlagBatches(_account),
          MailProblemCode.storageFailure,
        );
        _problem(
          await store.loadFlagBatch(_account, 'batch'),
          MailProblemCode.storageFailure,
        );
        _problem(
          await store.clearCompletedFlagBatches(_account),
          MailProblemCode.storageFailure,
        );
      },
    );
  }

  for (final interrupted in [false, true]) {
    test(
      'v6 migration interrupted=$interrupted preserves exact uncertain receipts and cache',
      () async {
        await store.close();
        await file.delete();
        final db = sqlite.sqlite3.open(file.path);
        for (final statement in [
          ...schemaV1,
          ...schemaV2,
          ...schemaV3,
          ...schemaV4,
          ...schemaV5,
          ...schemaV6,
        ]) {
          db.execute(statement);
        }
        db.execute(
          'INSERT INTO store_profile(singleton,host_id,profile_id,mailbox_view_revision) VALUES(1,?,?,9)',
          [_profile.hostId, _profile.value],
        );
        db.execute(
          "INSERT INTO accounts(id,provider,display_name,state) VALUES(?,'imap','Account','active')",
          [_account.value],
        );
        db.execute(
          "INSERT INTO mailboxes(account,id,display_name) VALUES(?,'INBOX','Inbox')",
          [_account.value],
        );
        final remote = MailStoreCodec.encodeRemote(_plan().messages.single);
        db.execute(
          'INSERT INTO messages(account,id,remote,envelope,flags) VALUES(?,?,?,?,?)',
          [
            _account.value,
            'cached',
            remote,
            MailStoreCodec.encodeEnvelope(MailEnvelope(subject: 'Original')),
            6,
          ],
        );
        db.execute(
          "INSERT INTO mailbox_views(account,mailbox,revision,captured_at,header_count,has_more) VALUES(?,'INBOX',9,1234,1,0)",
          [_account.value],
        );
        db.execute(
          "INSERT INTO mailbox_view_members(account,mailbox,position,message) VALUES(?,'INBOX',0,'cached')",
          [_account.value],
        );
        db.execute(
          "INSERT INTO flag_batches(account,id,mailbox,provider,action,created_at,updated_at,revision,complete,interrupted,item_count,stop_reason,problem_code,retry_after_us,mutation_possible) VALUES(?,'batch','INBOX','imap','markRead',?,?,4,1,0,1,'uncertain','providerFailure',37000000,1)",
          [
            _account.value,
            _now.millisecondsSinceEpoch,
            _now.millisecondsSinceEpoch,
          ],
        );
        db.execute(
          "INSERT INTO flag_batch_items(account,batch,position,remote,subject,state,problem_code,retry_after_us,mutation_possible) VALUES(?,'batch',0,?,'Retained subject','uncertain','providerFailure',37000000,1)",
          [_account.value, remote],
        );
        db.userVersion = 6;
        Map<String, List<List<Object?>>> snapshot(sqlite.Database database) => {
          for (final table in [
            'flag_batches',
            'flag_batch_items',
            'messages',
            'mailbox_views',
            'mailbox_view_members',
          ])
            table: [
              for (final row in database.select(
                'SELECT * FROM $table ORDER BY rowid',
              ))
                row.entries
                    .where((entry) => entry.key != 'destination')
                    .map((entry) => entry.value)
                    .toList(),
            ],
        };
        final original = snapshot(db);
        db.close();
        if (interrupted) {
          _problem(
            await open(failMigration: true),
            MailProblemCode.storageFailure,
          );
          final failed = sqlite.sqlite3.open(file.path);
          expect(failed.userVersion, 6);
          expect(
            failed.select(
              "SELECT name FROM sqlite_master WHERE name='flag_item_resolutions'",
            ),
            isEmpty,
          );
          expect(
            failed
                .select('PRAGMA table_info(store_profile)')
                .map((row) => row['name']),
            isNot(contains('flag_observation_epoch')),
          );
          expect(snapshot(failed), original);
          failed.close();
        }
        store = _value(await open());
        final saved = await load();
        preserved(saved);
        expect(saved.summary.unresolvedCount, 1);
        expect(saved.resolutions, isEmpty);
        final check = sqlite.sqlite3.open(file.path);
        expect(check.userVersion, 18);
        expect(snapshot(check), original);
        expect(check.select('PRAGMA foreign_key_check'), isEmpty);
        check.close();
        final lease = session.begin();
        final handle = await begin(lease);
        _value(
          await store.recordFlagObservation(
            handle,
            present(handle.message),
            lease: lease,
          ),
        );
        expect((await load()).summary.unresolvedCount, 0);
      },
    );
  }
}
