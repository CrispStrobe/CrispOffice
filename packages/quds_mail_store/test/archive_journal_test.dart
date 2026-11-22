@TestOn('vm')
library;

import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:quds_mail_store/src/codec.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:test/test.dart';

final _profile = MailProfileId('archive', hostId: 'journal-tests');
final _account = MailAccountId('gmail', profile: _profile);
final _inbox = MailMailboxId('INBOX', account: _account);
final _label = MailMailboxId('Label_42', account: _account);
final _time = DateTime.utc(2026, 11, 22, 12);
const _uncertain = MailProblem(
  MailProblemCode.providerFailure,
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

MailOpaqueIdentity _remote(int index) => MailOpaqueIdentity(
  account: _account,
  provider: MailProviderKind.gmail,
  value: 'gmail-message-$index',
);

MailHeaderRecord _header(int index) => MailHeaderRecord(
  id: MailMessageId('local-$index'),
  remote: _remote(index),
  envelope: MailEnvelope(subject: 'Retained subject $index'),
  flags: const MailMessageFlags(isFlagged: true, isAnswered: true),
);

MailBulkFlagPlan _plan({String id = 'archive', int count = 2}) =>
    MailBulkFlagPlan(
      id: id,
      mailbox: _inbox,
      action: MailBulkFlagAction.archive,
      messages: [for (var i = 0; i < count; i++) _remote(i)],
    );

MailBulkFlagItemResult _confirmed(MailBulkFlagPlan plan, int index) =>
    MailBulkFlagItemResult.restore(
      operation: plan.operationAt(index),
      outcome: MailBulkFlagOutcome.confirmed,
    );

MailBulkFlagReport _report(MailBulkFlagPlan plan, {int confirmed = 1}) =>
    MailBulkFlagReport.restore(
      plan: plan,
      results: [
        for (var i = 0; i < plan.messages.length; i++)
          MailBulkFlagItemResult.restore(
            operation: plan.operationAt(i),
            outcome: i < confirmed
                ? MailBulkFlagOutcome.confirmed
                : MailBulkFlagOutcome.unattempted,
          ),
      ],
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
  var now = _time;
  var commits = 0;
  var failExactly = 0;
  var failFrom = 0;

  Future<SqliteMailRepository> open() async => _value(
    await SqliteMailRepository.open(
      executor: NativeDatabase(file),
      profile: _profile,
      clock: () => now,
      faultInjector: (point) {
        if (point != MailStoreCheckpoint.beforeCommit) return;
        commits++;
        if (commits == failExactly || (failFrom != 0 && commits >= failFrom)) {
          throw const MailStoreStorageException(MailProblemCode.storageFailure);
        }
      },
    ),
  );

  Future<void> reopen() async {
    await store.close();
    failExactly = failFrom = 0;
    store = await open();
  }

  Future<MailFlagBatchHandle> create(MailBulkFlagPlan plan) async => _value(
    await store.createFlagBatch(
      plan,
      subjects: [for (var i = 0; i < plan.messages.length; i++) 'Subject $i'],
      lease: session.begin(),
    ),
  );

  Future<void> saveRetainedViews() async {
    for (final mailbox in [_inbox, _label]) {
      _value(
        await store.saveMailboxView(
          MailMailbox(id: mailbox, displayName: mailbox.value, isLabel: true),
          [_header(0)],
          expectedRevision: null,
          hasMore: false,
          lease: session.begin(),
        ),
      );
    }
  }

  Future<void> editDatabase(void Function(sqlite.Database db) edit) async {
    await store.close();
    final db = sqlite.sqlite3.open(file.path);
    try {
      db.execute('PRAGMA ignore_check_constraints = ON');
      edit(db);
    } finally {
      db.close();
    }
    store = await open();
  }

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    directory = await Directory.systemTemp.createTemp('archive-journal-');
    file = File('${directory.path}/mail.sqlite3');
    session = MailAccountSession(_account);
    now = _time;
    commits = failExactly = failFrom = 0;
    store = await open();
    _value(
      await store.createAccount(
        MailStoreAccount(
          id: _account,
          provider: MailProviderKind.gmail,
          displayName: 'Gmail',
        ),
      ),
    );
    commits = 0;
  });

  tearDown(() async {
    session.dispose();
    await store.close();
    await directory.delete(recursive: true);
  });

  test(
    'Archive receipt round-trips without inventing label or cache state',
    () async {
      await saveRetainedViews();
      final beforeInbox = _value(await store.loadMailboxView(_inbox))!;
      final beforeLabel = _value(await store.loadMailboxView(_label))!;
      final plan = _plan();
      final handle = await create(plan);
      _value(await store.beginFlagAttempt(handle, 0, lease: session.begin()));
      _value(await store.recordFlagResult(handle, 0, _confirmed(plan, 0)));
      _value(await store.finishFlagBatch(handle, _report(plan)));
      now = now.add(const Duration(minutes: 5));
      await reopen();

      final batch = _value(await store.loadFlagBatch(_account, plan.id))!;
      expect(batch.summary.action, MailBulkFlagAction.archive);
      expect(batch.summary.mailbox, _inbox);
      expect(batch.summary.destination, isNull);
      expect(batch.summary.canCheckFlags, isFalse);
      expect(batch.report.plan.operationAt(0), isA<MailArchive>());
      expect(batch.report.confirmedCount, 1);
      expect(batch.report.unattemptedCount, 1);
      expect(batch.report.requiresRefresh, isTrue);
      expect(batch.identityTransitions, isEmpty);
      for (final before in [beforeInbox, beforeLabel]) {
        final after = _value(await store.loadMailboxView(before.mailbox.id))!;
        expect(after.revision, before.revision);
        expect(after.capturedAt, before.capturedAt);
        expect(after.headers.single.remote, _remote(0));
        expect(after.headers.single.flags, _header(0).flags);
      }
      expect(_value(await store.clearCompletedFlagBatches(_account)), 1);
    },
  );

  test(
    'interrupted Archive stays uncertain, protected, and cannot replay',
    () async {
      final plan = _plan();
      final handle = await create(plan);
      _value(await store.beginFlagAttempt(handle, 0, lease: session.begin()));
      await reopen();
      final batch = _value(await store.loadFlagBatch(_account, plan.id))!;
      expect(batch.summary.interrupted, isTrue);
      expect(batch.summary.unresolvedCount, 1);
      expect(batch.report.uncertainCount, 1);
      expect(batch.report.unattemptedCount, 1);
      expect(
        batch.report.results.first.problem?.mutationMayHaveOccurred,
        isTrue,
      );
      _problem(
        await store.beginFlagAttempt(handle, 0, lease: session.begin()),
        MailProblemCode.conflict,
      );
      _problem(
        await store.recordFlagResult(handle, 0, _confirmed(plan, 0)),
        MailProblemCode.conflict,
      );
      _problem(
        await store.beginFlagReconciliation(
          _account,
          plan.id,
          0,
          expectedRevision: batch.summary.revision,
          lease: session.begin(),
        ),
        MailProblemCode.unsupported,
      );
      expect(_value(await store.clearCompletedFlagBatches(_account)), 0);
    },
  );

  test(
    'bulk Archive stops on uncertainty and location checks retain historical uncertainty',
    () async {
      await saveRetainedViews();
      final before = _value(await store.loadMailboxView(_inbox))!;
      final plan = _plan(count: 3);
      final dispatched = <MailOperation>[];
      final lease = session.begin();
      final report = await MailBulkFlagCoordinator().run(
        plan: plan,
        lease: lease,
        journal: _Journal(store, lease),
        isScopeCurrent: () => true,
        apply: (operation, lease) async {
          dispatched.add(operation);
          return dispatched.length == 1
              ? const MailBulkFlagAttempt.confirmed()
              : const MailBulkFlagAttempt.uncertain(_uncertain);
        },
      );
      expect(dispatched.map((operation) => operation.message), [
        _remote(0),
        _remote(1),
      ]);
      expect(dispatched.every((operation) => operation is MailArchive), isTrue);
      expect(report.confirmedCount, 1);
      expect(report.uncertainCount, 1);
      expect(report.unattemptedCount, 1);
      expect(report.stopReason, MailBulkFlagStopReason.uncertain);
      await reopen();
      final batch = _value(await store.loadFlagBatch(_account, plan.id))!;
      final checkLease = session.begin();
      final check = _value(
        await store.beginMembershipReconciliation(
          _account,
          plan.id,
          1,
          expectedRevision: batch.summary.revision,
          lease: checkLease,
        ),
      );
      now = now.add(const Duration(minutes: 1));
      _value(
        await store.recordMembershipObservation(
          check,
          MailMembershipObservation.folders(
            identity: _remote(1),
            mailboxes: [_label],
            deletionMailbox: MailMailboxId('TRASH', account: _account),
          ),
          lease: checkLease,
        ),
      );
      await reopen();
      final checked = _value(await store.loadFlagBatch(_account, plan.id))!;
      expect(checked.summary.unresolvedCount, 1);
      expect(checked.summary.reconciledCount, 0);
      expect(checked.report.confirmedCount, 1);
      expect(checked.report.uncertainCount, 1);
      expect(checked.report.unattemptedCount, 1);
      final evidence = checked.membershipObservations.single;
      expect(evidence.index, 1);
      expect(evidence.checkedAt, now);
      expect(evidence.observation.identity, _remote(1));
      expect(evidence.observation.mailboxes, [_label]);
      expect(evidence.observation.isDeleted, isFalse);
      expect(_value(await store.clearCompletedFlagBatches(_account)), 0);
      final after = _value(await store.loadMailboxView(_inbox))!;
      expect(after.revision, before.revision);
      expect(after.capturedAt, before.capturedAt);
      expect(after.headers.single.remote, _remote(0));
    },
  );

  for (final failure in [1, 2, 3, 4]) {
    test(
      'Archive commit failure $failure bounds dispatch and preserves evidence',
      () async {
        final plan = _plan(count: 1);
        failExactly = failure;
        var calls = 0;
        final lease = session.begin();
        final report = await MailBulkFlagCoordinator().run(
          plan: plan,
          lease: lease,
          journal: _Journal(store, lease),
          isScopeCurrent: () => true,
          apply: (operation, lease) async {
            calls++;
            return const MailBulkFlagAttempt.confirmed();
          },
        );
        expect(calls, failure >= 3 ? 1 : 0);
        expect(report.persistenceProblem?.code, MailProblemCode.storageFailure);
        await reopen();
        final batch = _value(await store.loadFlagBatch(_account, plan.id));
        if (failure == 1) {
          expect(batch, isNull);
        } else {
          expect(batch!.summary.action, MailBulkFlagAction.archive);
          expect(batch.summary.destination, isNull);
          expect(batch.report.confirmedCount, failure >= 3 ? 1 : 0);
          expect(batch.report.uncertainCount, 0);
          expect(batch.summary.interrupted, failure == 4);
        }
      },
    );
  }

  test(
    'lost Archive receipt and finalization recover as uncertain after restart',
    () async {
      final plan = _plan();
      failFrom = 3;
      var calls = 0;
      final lease = session.begin();
      final report = await MailBulkFlagCoordinator().run(
        plan: plan,
        lease: lease,
        journal: _Journal(store, lease),
        isScopeCurrent: () => true,
        apply: (operation, lease) async {
          calls++;
          return const MailBulkFlagAttempt.confirmed();
        },
      );
      expect(calls, 1);
      expect(report.confirmedCount, 1);
      await reopen();
      final batch = _value(await store.loadFlagBatch(_account, plan.id))!;
      expect(batch.report.confirmedCount, 0);
      expect(batch.report.uncertainCount, 1);
      expect(batch.report.unattemptedCount, 1);
      expect(batch.report.plan.action, MailBulkFlagAction.archive);
      expect(_value(await store.clearCompletedFlagBatches(_account)), 0);
    },
  );

  test('foreign account lease cannot save Archive intent', () async {
    final foreign = MailAccountSession(
      MailAccountId('other', profile: _profile),
    );
    try {
      _problem(
        await store.createFlagBatch(
          _plan(count: 1),
          subjects: ['Subject'],
          lease: foreign.begin(),
        ),
        MailProblemCode.invalidInput,
      );
      expect(_value(await store.listFlagBatches(_account)).batches, isEmpty);
    } finally {
      foreign.dispose();
    }
  });

  for (final corruption in <String, String>{
    'provider': "UPDATE flag_batches SET provider='graph'",
    'source': "UPDATE flag_batches SET mailbox='Label_42'",
    'destination': "UPDATE flag_batches SET destination='Archive'",
  }.entries) {
    test(
      'corrupt Archive ${corruption.key} is refused before loading or cleanup',
      () async {
        final plan = _plan(count: 1);
        final handle = await create(plan);
        _value(
          await store.finishFlagBatch(handle, _report(plan, confirmed: 0)),
        );
        await editDatabase((db) => db.execute(corruption.value));
        _problem(
          await store.loadFlagBatch(_account, plan.id),
          MailProblemCode.storageFailure,
        );
        _problem(
          await store.clearCompletedFlagBatches(_account),
          MailProblemCode.storageFailure,
        );
      },
    );
  }

  test(
    'Archive acknowledgement cannot substitute a Delete operation',
    () async {
      final plan = _plan(count: 1);
      final handle = await create(plan);
      _value(await store.beginFlagAttempt(handle, 0, lease: session.begin()));
      _problem(
        await store.recordFlagResult(
          handle,
          0,
          MailBulkFlagItemResult.restore(
            operation: MailDelete(
              id: plan.operationAt(0).id,
              message: _remote(0),
            ),
            outcome: MailBulkFlagOutcome.confirmed,
          ),
        ),
        MailProblemCode.conflict,
      );
      await reopen();
      final batch = _value(await store.loadFlagBatch(_account, plan.id))!;
      expect(batch.report.uncertainCount, 1);
      expect(batch.report.confirmedCount, 0);
    },
  );

  test(
    'pending Archive round-trips and interrupted apply requires explicit reconciliation',
    () async {
      await saveRetainedViews();
      final operation = MailArchive(id: 'queued-archive', message: _remote(0));
      _value(await store.enqueueOperation(operation, session.begin()));
      await reopen();
      final queued = _value(await store.pendingOperations(_account)).single;
      expect(queued.operation, isA<MailArchive>());
      expect(queued.operation.message, operation.message);
      expect(queued.state, MailPendingState.queued);
      _value(
        await store.transitionOperation(
          _account,
          operation.id,
          expectedRevision: queued.revision,
          state: MailPendingState.applying,
          lease: session.begin(),
        ),
      );
      await reopen();
      final interrupted = _value(
        await store.pendingOperations(_account),
      ).single;
      expect(interrupted.operation, isA<MailArchive>());
      expect(interrupted.state, MailPendingState.reconcile);
      _problem(
        await store.transitionOperation(
          _account,
          operation.id,
          expectedRevision: interrupted.revision,
          state: MailPendingState.queued,
          lease: session.begin(),
        ),
        MailProblemCode.conflict,
      );
      expect(
        _value(await store.loadMailboxView(_label))!.headers.single.remote,
        _remote(0),
      );
    },
  );

  for (final corruption in ['argument', 'provider']) {
    test('corrupt pending Archive $corruption is refused', () async {
      await saveRetainedViews();
      _value(
        await store.enqueueOperation(
          MailArchive(id: 'queued-archive', message: _remote(0)),
          session.begin(),
        ),
      );
      await editDatabase((db) {
        if (corruption == 'argument') {
          db.execute("UPDATE pending_operations SET argument='Archive'");
        } else {
          db.execute('UPDATE pending_operations SET remote=?', [
            MailStoreCodec.encodeRemote(
              MailOpaqueIdentity(
                account: _account,
                provider: MailProviderKind.graph,
                value: 'other',
              ),
            ),
          ]);
        }
      });
      _problem(
        await store.pendingOperations(_account),
        MailProblemCode.storageFailure,
      );
    });
  }
}
