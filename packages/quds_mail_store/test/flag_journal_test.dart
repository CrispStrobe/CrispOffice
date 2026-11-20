@TestOn('vm')
library;

import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:test/test.dart';

final _profile = MailProfileId('journal', hostId: 'test-office');
final _account = MailAccountId('account', profile: _profile);
final _box = MailMailbox(
  id: MailMailboxId('INBOX', account: _account),
  displayName: 'Inbox',
);
final _now = DateTime.utc(2026, 11, 21);

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
  int count = 3,
  int validity = 7,
  MailBulkFlagAction action = MailBulkFlagAction.markRead,
  MailAccountId? account,
}) {
  final mailbox = MailMailboxId('INBOX', account: account ?? _account);
  return MailBulkFlagPlan(
    id: id,
    mailbox: mailbox,
    action: action,
    messages: [
      for (var uid = 1; uid <= count; uid++)
        MailImapIdentity(mailbox: mailbox, uidValidity: validity, uid: uid),
    ],
  );
}

MailBulkFlagItemResult _result(
  MailBulkFlagPlan plan,
  int index,
  MailBulkFlagOutcome outcome, {
  MailProblem? problem,
}) => MailBulkFlagItemResult.restore(
  operation: plan.operationAt(index),
  outcome: outcome,
  problem: problem,
);

MailBulkFlagReport _report(
  MailBulkFlagPlan plan,
  List<MailBulkFlagItemResult> settled, {
  MailBulkFlagStopReason? stopReason,
  MailProblem? stopProblem,
}) => MailBulkFlagReport.restore(
  plan: plan,
  results: [
    for (var i = 0; i < plan.messages.length; i++)
      i < settled.length
          ? settled[i]
          : _result(plan, i, MailBulkFlagOutcome.unattempted),
  ],
  stopReason: stopReason,
  stopProblem: stopProblem,
);

final class _Journal implements MailBulkFlagJournal {
  _Journal(this.store, this.lease);
  final SqliteMailRepository store;
  final MailOperationLease lease;
  MailFlagBatchHandle? handle;
  @override
  Future<MailResult<MailUnit>> prepare(MailBulkFlagPlan plan) async {
    final result = await store.createFlagBatch(
      plan,
      subjects: [for (var i = 0; i < plan.messages.length; i++) 'Subject $i'],
      lease: lease,
    );
    return switch (result) {
      MailSuccess<MailFlagBatchHandle>(:final value) => () {
        handle = value;
        return const MailSuccess(MailUnit.value);
      }(),
      MailFailure<MailFlagBatchHandle>(:final problem) => MailFailure(problem),
    };
  }

  @override
  Future<MailResult<MailUnit>> beginAttempt(int index) =>
      store.beginFlagAttempt(handle!, index, lease: lease);
  @override
  Future<MailResult<MailUnit>> recordResult(
    int index,
    MailBulkFlagItemResult result,
  ) => store.recordFlagResult(handle!, index, result);
  @override
  Future<MailResult<MailUnit>> finish(MailBulkFlagReport report) =>
      store.finishFlagBatch(handle!, report);
}

void main() {
  late Directory directory;
  late File file;
  late SqliteMailRepository store;
  late MailAccountSession session;
  var failAfter = 0;
  var failExactly = 0;
  var commits = 0;
  var invalidateCommit = false;
  var now = _now;

  Future<SqliteMailRepository> open({
    MailStoreLimits limits = const MailStoreLimits(),
  }) async => _value(
    await SqliteMailRepository.open(
      executor: NativeDatabase(file),
      profile: _profile,
      limits: limits,
      clock: () => now,
      faultInjector: (point) {
        if (point != MailStoreCheckpoint.beforeCommit) return;
        commits++;
        if (invalidateCommit) session.invalidate();
        if ((failAfter != 0 && commits >= failAfter) ||
            commits == failExactly) {
          throw const MailStoreStorageException(MailProblemCode.storageFailure);
        }
      },
    ),
  );

  Future<MailFlagBatchHandle> create(
    MailBulkFlagPlan plan, {
    List<String>? subjects,
  }) async => _value(
    await store.createFlagBatch(
      plan,
      subjects:
          subjects ??
          [for (var i = 0; i < plan.messages.length; i++) 'Subject $i'],
      lease: session.begin(),
    ),
  );

  Future<void> reopen() async {
    await store.close();
    failAfter = failExactly = 0;
    invalidateCommit = false;
    store = await open();
  }

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    directory = await Directory.systemTemp.createTemp('quds-flag-journal-');
    file = File('${directory.path}/mail.sqlite3');
    session = MailAccountSession(_account);
    failAfter = failExactly = commits = 0;
    invalidateCommit = false;
    now = _now;
    store = await open();
    _value(
      await store.createAccount(
        MailStoreAccount(
          id: _account,
          provider: MailProviderKind.imap,
          displayName: 'Journal account',
        ),
      ),
    );
    commits = 0;
  });
  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });

  test(
    'prepared selection and frozen subjects survive restart as not attempted',
    () async {
      final plan = _plan();
      final subjects = ['First', 'العنوان', 'Betreff'];
      await create(plan, subjects: subjects);
      subjects.clear();
      await reopen();
      final batch = _value(await store.loadFlagBatch(_account, plan.id))!;
      expect(batch.subjects, ['First', 'العنوان', 'Betreff']);
      expect(batch.report.unattemptedCount, 3);
      expect(batch.report.uncertainCount, 0);
      expect(batch.summary.complete, isTrue);
      expect(batch.summary.interrupted, isTrue);
      expect(batch.report.stopReason, MailBulkFlagStopReason.cancelled);
      expect(() => batch.subjects.clear(), throwsUnsupportedError);
    },
  );

  test(
    'recovery retains confirmed, converts applying to uncertain, leaves the tail untouched',
    () async {
      final plan = _plan();
      final handle = await create(plan);
      _value(await store.beginFlagAttempt(handle, 0, lease: session.begin()));
      _value(
        await store.recordFlagResult(
          handle,
          0,
          _result(plan, 0, MailBulkFlagOutcome.confirmed),
        ),
      );
      _value(await store.beginFlagAttempt(handle, 1, lease: session.begin()));
      await reopen();
      final batch = _value(await store.loadFlagBatch(_account, plan.id))!;
      expect(batch.report.results.map((item) => item.outcome), [
        MailBulkFlagOutcome.confirmed,
        MailBulkFlagOutcome.uncertain,
        MailBulkFlagOutcome.unattempted,
      ]);
      expect(batch.report.requiresRefresh, isTrue);
      expect(batch.summary.interrupted, isTrue);
      expect(batch.report.items[1].problem!.mutationMayHaveOccurred, isTrue);
      _problem(
        await store.recordFlagResult(
          handle,
          1,
          _result(plan, 1, MailBulkFlagOutcome.confirmed),
        ),
        MailProblemCode.conflict,
      );
      _problem(
        await store.beginFlagAttempt(handle, 2, lease: session.begin()),
        MailProblemCode.conflict,
      );
      await reopen();
      expect(
        _value(await store.loadFlagBatch(_account, plan.id))!.summary.revision,
        batch.summary.revision,
      );
    },
  );

  test(
    'completed receipts retain exact typed rejection and retry delay across restart',
    () async {
      final plan = _plan();
      final handle = await create(plan);
      const problem = MailProblem(
        MailProblemCode.quotaExceeded,
        retryAfter: Duration(seconds: 45),
        mutationMayHaveOccurred: false,
      );
      final failed = _result(
        plan,
        0,
        MailBulkFlagOutcome.failed,
        problem: problem,
      );
      _value(await store.beginFlagAttempt(handle, 0, lease: session.begin()));
      _value(await store.recordFlagResult(handle, 0, failed));
      _value(
        await store.finishFlagBatch(
          handle,
          _report(
            plan,
            [failed],
            stopReason: MailBulkFlagStopReason.rateLimited,
            stopProblem: problem,
          ),
        ),
      );
      await reopen();
      final batch = _value(await store.loadFlagBatch(_account, plan.id))!;
      expect(batch.report.failedCount, 1);
      expect(batch.report.unattemptedCount, 2);
      expect(
        batch.report.items.first.problem!.retryAfter,
        const Duration(seconds: 45),
      );
      expect(batch.report.stopReason, MailBulkFlagStopReason.rateLimited);
      expect(batch.summary.interrupted, isFalse);
    },
  );

  test(
    'duplicate batch and out-of-order/repeated dispatch are rejected',
    () async {
      final plan = _plan();
      final handle = await create(plan);
      _problem(
        await store.createFlagBatch(
          plan,
          subjects: ['a', 'b', 'c'],
          lease: session.begin(),
        ),
        MailProblemCode.conflict,
      );
      _problem(
        await store.beginFlagAttempt(handle, 1, lease: session.begin()),
        MailProblemCode.conflict,
      );
      _value(await store.beginFlagAttempt(handle, 0, lease: session.begin()));
      _problem(
        await store.beginFlagAttempt(handle, 0, lease: session.begin()),
        MailProblemCode.conflict,
      );
      _problem(
        await store.beginFlagAttempt(handle, 1, lease: session.begin()),
        MailProblemCode.conflict,
      );
    },
  );

  test(
    'recording an undispatched or substituted command cannot forge success',
    () async {
      final plan = _plan();
      final handle = await create(plan);
      _problem(
        await store.recordFlagResult(
          handle,
          0,
          _result(plan, 0, MailBulkFlagOutcome.confirmed),
        ),
        MailProblemCode.conflict,
      );
      _value(await store.beginFlagAttempt(handle, 0, lease: session.begin()));
      final other = _plan(validity: 8);
      _problem(
        await store.recordFlagResult(
          handle,
          0,
          _result(other, 0, MailBulkFlagOutcome.confirmed),
        ),
        MailProblemCode.conflict,
      );
      _problem(
        await store.finishFlagBatch(
          handle,
          _report(plan, [
            _result(plan, 0, MailBulkFlagOutcome.confirmed),
            _result(plan, 1, MailBulkFlagOutcome.confirmed),
          ]),
        ),
        MailProblemCode.conflict,
      );
      final batch = _value(await store.loadFlagBatch(_account, plan.id))!;
      expect(batch.summary.uncertainCount, 1);
      expect(batch.summary.confirmedCount, 0);
    },
  );

  test(
    'scope retirement before commit rolls back intent and dispatch markers',
    () async {
      invalidateCommit = true;
      _problem(
        await store.createFlagBatch(
          _plan(),
          subjects: ['a', 'b', 'c'],
          lease: session.begin(),
        ),
        MailProblemCode.staleOperation,
      );
      invalidateCommit = false;
      expect(_value(await store.listFlagBatches(_account)).batches, isEmpty);
      final handle = await create(_plan());
      invalidateCommit = true;
      _problem(
        await store.beginFlagAttempt(handle, 0, lease: session.begin()),
        MailProblemCode.staleOperation,
      );
      invalidateCommit = false;
      expect(
        _value(
          await store.loadFlagBatch(_account, 'batch'),
        )!.report.unattemptedCount,
        3,
      );
    },
  );

  test('late confirmed reply persists after view lease retires', () async {
    final plan = _plan();
    final handle = await create(plan);
    _value(await store.beginFlagAttempt(handle, 0, lease: session.begin()));
    session.invalidate();
    final confirmed = _result(plan, 0, MailBulkFlagOutcome.confirmed);
    _value(await store.recordFlagResult(handle, 0, confirmed));
    _value(
      await store.finishFlagBatch(
        handle,
        _report(plan, [
          confirmed,
        ], stopReason: MailBulkFlagStopReason.staleScope),
      ),
    );
    expect(
      _value(
        await store.loadFlagBatch(_account, plan.id),
      )!.report.confirmedCount,
      1,
    );
  });

  test(
    'logout retires completion authority even if the account later resumes',
    () async {
      final plan = _plan();
      final handle = await create(plan);
      _value(await store.beginFlagAttempt(handle, 0, lease: session.begin()));
      _value(await store.logout(session));
      _problem(
        await store.recordFlagResult(
          handle,
          0,
          _result(plan, 0, MailBulkFlagOutcome.confirmed),
        ),
        MailProblemCode.authenticationRequired,
      );
      _value(
        await store.resumeAccount(
          _account,
          credentialReference: 'new-vault-reference',
        ),
      );
      _problem(
        await store.recordFlagResult(
          handle,
          0,
          _result(plan, 0, MailBulkFlagOutcome.confirmed),
        ),
        MailProblemCode.conflict,
      );
      expect(
        _value(
          await store.loadFlagBatch(_account, plan.id),
        )!.report.uncertainCount,
        1,
      );
    },
  );

  for (final removeProfile in [false, true]) {
    test(
      '${removeProfile ? 'profile' : 'account'} removal clears journal and rejects late replies',
      () async {
        final plan = _plan();
        final handle = await create(plan);
        _value(await store.beginFlagAttempt(handle, 0, lease: session.begin()));
        _value(
          await (removeProfile
              ? store.removeProfile()
              : store.removeLocalAccount(_account)),
        );
        _problem(
          await store.recordFlagResult(
            handle,
            0,
            _result(plan, 0, MailBulkFlagOutcome.confirmed),
          ),
          MailProblemCode.unavailable,
        );
        await store.close();
        final db = sqlite.sqlite3.open(file.path);
        expect(
          db.select('SELECT count(*) AS n FROM flag_batches').single['n'],
          0,
        );
        expect(
          db.select('SELECT count(*) AS n FROM flag_batch_items').single['n'],
          0,
        );
        db.close();
      },
    );
  }

  test(
    'confirmed cache projection preserves other bits and invalidates stale view CAS',
    () async {
      final plan = _plan(count: 1);
      final header = MailHeaderRecord(
        id: MailMessageId('cached'),
        remote: plan.messages.first,
        envelope: MailEnvelope(subject: 'cached'),
        flags: const MailMessageFlags(isFlagged: true, isAnswered: true),
      );
      final view = _value(
        await store.saveMailboxView(
          _box,
          [header],
          expectedRevision: null,
          hasMore: true,
          lease: session.begin(),
        ),
      );
      final handle = await create(plan);
      _value(await store.beginFlagAttempt(handle, 0, lease: session.begin()));
      final confirmed = _result(plan, 0, MailBulkFlagOutcome.confirmed);
      _value(await store.recordFlagResult(handle, 0, confirmed));
      final updated = _value(await store.loadMailboxView(_box.id))!;
      expect(updated.headers.single.flags!.isRead, isTrue);
      expect(updated.headers.single.flags!.isFlagged, isTrue);
      expect(updated.headers.single.flags!.isAnswered, isTrue);
      expect(updated.capturedAt, view.capturedAt);
      expect(updated.hasMore, isTrue);
      expect(updated.revision, greaterThan(view.revision));
      _problem(
        await store.saveMailboxView(
          _box,
          [header],
          expectedRevision: view.revision,
          hasMore: false,
          lease: session.begin(),
        ),
        MailProblemCode.conflict,
      );
      _value(await store.finishFlagBatch(handle, _report(plan, [confirmed])));
    },
  );

  test(
    'unknown cached flags remain unknown and old UIDVALIDITY cannot change newer message',
    () async {
      final old = _plan(count: 1);
      final current = _plan(count: 1, validity: 8);
      final headers = [
        MailHeaderRecord(
          id: MailMessageId('unknown'),
          remote: old.messages.first,
          envelope: MailEnvelope(),
        ),
        MailHeaderRecord(
          id: MailMessageId('new'),
          remote: current.messages.first,
          envelope: MailEnvelope(),
          flags: const MailMessageFlags(),
        ),
      ];
      _value(
        await store.saveMailboxView(
          _box,
          [headers.first],
          expectedRevision: null,
          hasMore: false,
          lease: session.begin(),
        ),
      );
      final handle = await create(old);
      _value(await store.beginFlagAttempt(handle, 0, lease: session.begin()));
      _value(
        await store.recordFlagResult(
          handle,
          0,
          _result(old, 0, MailBulkFlagOutcome.confirmed),
        ),
      );
      expect(
        _value(await store.loadMailboxView(_box.id))!.headers.single.flags,
        isNull,
      );
      final second = await create(_plan(id: 'old-generation', count: 1));
      final before = _value(await store.loadMailboxView(_box.id))!;
      _value(
        await store.saveMailboxView(
          _box,
          [headers.last],
          expectedRevision: before.revision,
          hasMore: false,
          lease: session.begin(),
        ),
      );
      _value(await store.beginFlagAttempt(second, 0, lease: session.begin()));
      _value(
        await store.recordFlagResult(
          second,
          0,
          _result(
            _plan(id: 'old-generation', count: 1),
            0,
            MailBulkFlagOutcome.confirmed,
          ),
        ),
      );
      expect(
        _value(
          await store.loadMailboxView(_box.id),
        )!.headers.single.flags!.isRead,
        isFalse,
      );
    },
  );

  test(
    'failed acknowledgement transaction rolls back cache flag and receipt together',
    () async {
      final plan = _plan(count: 1);
      final header = MailHeaderRecord(
        id: MailMessageId('cached'),
        remote: plan.messages.first,
        envelope: MailEnvelope(),
        flags: const MailMessageFlags(),
      );
      _value(
        await store.saveMailboxView(
          _box,
          [header],
          expectedRevision: null,
          hasMore: false,
          lease: session.begin(),
        ),
      );
      final handle = await create(plan);
      _value(await store.beginFlagAttempt(handle, 0, lease: session.begin()));
      failExactly = commits + 1;
      _problem(
        await store.recordFlagResult(
          handle,
          0,
          _result(plan, 0, MailBulkFlagOutcome.confirmed),
        ),
        MailProblemCode.storageFailure,
      );
      expect(
        _value(
          await store.loadMailboxView(_box.id),
        )!.headers.single.flags!.isRead,
        isFalse,
      );
      await reopen();
      expect(
        _value(
          await store.loadFlagBatch(_account, plan.id),
        )!.report.uncertainCount,
        1,
      );
    },
  );

  for (final at in [1, 2]) {
    test(
      'failure at durable pre-dispatch write $at causes zero provider calls',
      () async {
        failAfter = at;
        var calls = 0;
        final report = await MailBulkFlagCoordinator().run(
          plan: _plan(),
          lease: session.begin(),
          isScopeCurrent: () => true,
          journal: _Journal(store, session.begin()),
          apply: (_, _) async {
            calls++;
            return const MailBulkFlagAttempt.confirmed();
          },
        );
        expect(calls, 0);
        expect(report.unattemptedCount, 3);
        expect(report.persistenceProblem, isNotNull);
      },
    );
  }

  test(
    'lost local receipt write never permits the next command and recovers uncertainty',
    () async {
      failAfter = 3;
      var calls = 0;
      final report = await MailBulkFlagCoordinator().run(
        plan: _plan(),
        lease: session.begin(),
        isScopeCurrent: () => true,
        journal: _Journal(store, session.begin()),
        apply: (_, _) async {
          calls++;
          return const MailBulkFlagAttempt.confirmed();
        },
      );
      expect(calls, 1);
      expect(report.confirmedCount, 1);
      expect(report.persistenceProblem, isNotNull);
      await reopen();
      final recovered = _value(await store.loadFlagBatch(_account, 'batch'))!;
      expect(recovered.report.uncertainCount, 1);
      expect(recovered.report.unattemptedCount, 2);
    },
  );

  test(
    'one transient receipt failure can be finalized without replaying the provider',
    () async {
      failExactly = 3;
      var calls = 0;
      final report = await MailBulkFlagCoordinator().run(
        plan: _plan(),
        lease: session.begin(),
        isScopeCurrent: () => true,
        journal: _Journal(store, session.begin()),
        apply: (_, _) async {
          calls++;
          return const MailBulkFlagAttempt.confirmed();
        },
      );
      expect(calls, 1);
      expect(report.confirmedCount, 1);
      await reopen();
      final recovered = _value(await store.loadFlagBatch(_account, 'batch'))!;
      expect(recovered.report.confirmedCount, 1);
      expect(recovered.report.uncertainCount, 0);
      expect(
        recovered.report.persistenceProblem!.code,
        MailProblemCode.storageFailure,
      );
    },
  );

  test(
    'history paging exposes continuation and cleanup retains uncertain receipts',
    () async {
      for (var i = 0; i < 4; i++) {
        final plan = _plan(id: 'batch-$i', count: 1);
        final handle = await create(plan);
        if (i == 2) {
          _value(
            await store.beginFlagAttempt(handle, 0, lease: session.begin()),
          );
          final uncertain = _result(
            plan,
            0,
            MailBulkFlagOutcome.uncertain,
            problem: const MailProblem(MailProblemCode.providerFailure),
          );
          _value(await store.recordFlagResult(handle, 0, uncertain));
          _value(
            await store.finishFlagBatch(
              handle,
              _report(plan, [
                uncertain,
              ], stopReason: MailBulkFlagStopReason.uncertain),
            ),
          );
        } else {
          _value(await store.finishFlagBatch(handle, _report(plan, [])));
        }
        now = now.add(const Duration(seconds: 1));
      }
      final first = _value(await store.listFlagBatches(_account, limit: 2));
      expect(first.batches.map((b) => b.id), ['batch-3', 'batch-2']);
      expect(first.nextOffset, 2);
      final second = _value(
        await store.listFlagBatches(
          _account,
          limit: 2,
          offset: first.nextOffset!,
        ),
      );
      expect(second.batches.map((b) => b.id), ['batch-1', 'batch-0']);
      expect(second.nextOffset, isNull);
      expect(_value(await store.clearCompletedFlagBatches(_account)), 3);
      expect(
        _value(await store.listFlagBatches(_account)).batches.single.id,
        'batch-2',
      );
    },
  );

  test(
    'clean receipt retention is bounded without deleting unresolved work',
    () async {
      final unresolved = _plan(id: 'unresolved', count: 1);
      final outstanding = await create(unresolved);
      _value(
        await store.beginFlagAttempt(outstanding, 0, lease: session.begin()),
      );
      for (var i = 0; i < 102; i++) {
        final plan = _plan(
          id: 'clean-${i.toString().padLeft(3, '0')}',
          count: 1,
        );
        final handle = await create(plan);
        _value(await store.finishFlagBatch(handle, _report(plan, [])));
        now = now.add(const Duration(seconds: 1));
      }
      expect(_value(await store.loadFlagBatch(_account, 'clean-000')), isNull);
      expect(
        _value(await store.loadFlagBatch(_account, 'unresolved')),
        isNotNull,
      );
      expect(
        _value(await store.listFlagBatches(_account, limit: 100)).nextOffset,
        100,
      );
      expect(
        _value(
          await store.listFlagBatches(_account, offset: 100),
        ).batches.length,
        1,
      );
    },
  );

  test(
    '100 unresolved receipts enforce a fail-closed bound and are not cleaned',
    () async {
      for (var i = 0; i < 100; i++) {
        await create(_plan(id: 'pending-$i', count: 1));
      }
      final extra = _plan(id: 'overflow', count: 1);
      _problem(
        await store.createFlagBatch(
          extra,
          subjects: ['extra'],
          lease: session.begin(),
        ),
        MailProblemCode.quotaExceeded,
      );
      expect(_value(await store.clearCompletedFlagBatches(_account)), 0);
    },
  );

  test(
    'foreign profiles/accounts and oversized subject metadata fail before intent is saved',
    () async {
      final foreign = MailAccountId(
        'account',
        profile: MailProfileId('other', hostId: 'test-office'),
      );
      _problem(
        await store.createFlagBatch(
          _plan(account: foreign),
          subjects: ['a', 'b', 'c'],
          lease: session.begin(),
        ),
        MailProblemCode.permissionDenied,
      );
      _problem(
        await store.createFlagBatch(
          _plan(),
          subjects: ['x' * 4097, 'b', 'c'],
          lease: session.begin(),
        ),
        MailProblemCode.quotaExceeded,
      );
      expect(_value(await store.listFlagBatches(_account)).batches, isEmpty);
    },
  );
}
