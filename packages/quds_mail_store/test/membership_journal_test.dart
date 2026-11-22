@TestOn('vm')
library;

import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:test/test.dart';

final _profile = MailProfileId('membership', hostId: 'journal-tests');
final _account = MailAccountId('account', profile: _profile);
final _source = MailMailboxId('inbox', account: _account);
final _destination = MailMailboxId('archive', account: _account);
final _time = DateTime.utc(2026, 11, 22);

T _value<T>(MailResult<T> result) {
  expect(result, isA<MailSuccess<T>>());
  return (result as MailSuccess<T>).value;
}

void _problem<T>(MailResult<T> result, MailProblemCode code) {
  expect(result, isA<MailFailure<T>>());
  expect((result as MailFailure<T>).problem.code, code);
}

MailBulkFlagPlan _plan(
  MailBulkFlagAction action, {
  String id = 'membership',
  MailMailboxId? destination,
  int count = 2,
}) => MailBulkFlagPlan(
  id: id,
  mailbox: _source,
  action: action,
  destination: action == MailBulkFlagAction.move
      ? destination ?? _destination
      : null,
  messages: [
    for (var uid = 1; uid <= count; uid++)
      MailImapIdentity(mailbox: _source, uidValidity: 7, uid: uid),
  ],
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

final class _ReadProbe extends QueryInterceptor {
  bool oversizedTransferred = false;
  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final rows = await super.runSelect(executor, statement, args);
    oversizedTransferred |= rows.any(
      (row) =>
          row.values.any((value) => value is String && value.length > 32768),
    );
    return rows;
  }
}

void main() {
  late Directory directory;
  late File file;
  late SqliteMailRepository store;
  late MailAccountSession session;
  late _ReadProbe probe;
  var commits = 0;
  var failExactly = 0;
  var failFrom = 0;

  Future<SqliteMailRepository> open({
    MailStoreLimits limits = const MailStoreLimits(),
  }) async => _value(
    await SqliteMailRepository.open(
      executor: NativeDatabase(file).interceptWith(probe),
      profile: _profile,
      clock: () => _time,
      limits: limits,
      faultInjector: (point) {
        if (point != MailStoreCheckpoint.beforeCommit) return;
        commits++;
        if (commits == failExactly || (failFrom != 0 && commits >= failFrom)) {
          throw const MailStoreStorageException(MailProblemCode.storageFailure);
        }
      },
    ),
  );

  Future<void> reopen({
    MailStoreLimits limits = const MailStoreLimits(),
  }) async {
    await store.close();
    failExactly = failFrom = 0;
    store = await open(limits: limits);
  }

  Future<MailFlagBatchHandle> create(MailBulkFlagPlan plan) async => _value(
    await store.createFlagBatch(
      plan,
      subjects: [for (var i = 0; i < plan.messages.length; i++) 'Subject $i'],
      lease: session.begin(),
    ),
  );

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    directory = await Directory.systemTemp.createTemp('membership-journal-');
    file = File('${directory.path}/mail.sqlite3');
    probe = _ReadProbe();
    session = MailAccountSession(_account);
    commits = failExactly = failFrom = 0;
    store = await open();
    _value(
      await store.createAccount(
        MailStoreAccount(
          id: _account,
          provider: MailProviderKind.imap,
          displayName: 'Synthetic',
        ),
      ),
    );
    commits = 0;
  });
  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });

  for (final action in [MailBulkFlagAction.move, MailBulkFlagAction.delete]) {
    test(
      '${action.name} confirmation retains history without inventing cache membership',
      () async {
        final plan = _plan(action);
        final header = MailHeaderRecord(
          id: MailMessageId('cached'),
          remote: plan.messages.first,
          envelope: MailEnvelope(subject: 'Original subject'),
          flags: const MailMessageFlags(isFlagged: true, isAnswered: true),
        );
        final before = _value(
          await store.saveMailboxView(
            MailMailbox(id: _source, displayName: 'Inbox'),
            [header],
            expectedRevision: null,
            hasMore: false,
            lease: session.begin(),
          ),
        );
        final handle = await create(plan);
        _value(await store.beginFlagAttempt(handle, 0, lease: session.begin()));
        _value(await store.recordFlagResult(handle, 0, _confirmed(plan, 0)));
        _value(await store.finishFlagBatch(handle, _report(plan)));
        await reopen();
        final stored = _value(await store.loadFlagBatch(_account, plan.id))!;
        expect(stored.report.plan.action, action);
        expect(stored.report.plan.destination, plan.destination);
        expect(stored.summary.destination, plan.destination);
        expect(stored.summary.canCheckFlags, isFalse);
        expect(stored.summary.requiresRefresh, isTrue);
        expect(stored.report.requiresRefresh, isTrue);
        expect(stored.report.confirmedCount, 1);
        expect(stored.report.unattemptedCount, 1);
        final after = _value(await store.loadMailboxView(_source))!;
        expect(after.revision, before.revision);
        expect(after.capturedAt, before.capturedAt);
        expect(after.headers.single.remote, header.remote);
        expect(after.headers.single.flags, header.flags);
        expect(_value(await store.loadMailboxView(_destination)), isNull);
        expect(_value(await store.clearCompletedFlagBatches(_account)), 1);
      },
    );

    test(
      '${action.name} interrupted dispatch stays unresolved and cannot replay or check flags',
      () async {
        final plan = _plan(action);
        final handle = await create(plan);
        _value(await store.beginFlagAttempt(handle, 0, lease: session.begin()));
        await reopen();
        final batch = _value(await store.loadFlagBatch(_account, plan.id))!;
        expect(batch.summary.interrupted, isTrue);
        expect(batch.summary.unresolvedCount, 1);
        expect(batch.report.plan.destination, plan.destination);
        expect(batch.report.unattemptedCount, 1);
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
        expect(
          _value(
            await store.loadFlagBatch(_account, plan.id),
          )!.summary.unresolvedCount,
          1,
        );
      },
    );

    for (final failure in [1, 2, 3]) {
      test(
        '${action.name} failed journal write $failure bounds dispatch and retains exact intent',
        () async {
          final plan = _plan(action);
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
          expect(calls, failure == 3 ? 1 : 0);
          expect(
            report.persistenceProblem?.code,
            MailProblemCode.storageFailure,
          );
          await reopen();
          final stored = _value(await store.loadFlagBatch(_account, plan.id));
          if (failure == 1) {
            expect(stored, isNull);
          } else {
            expect(stored!.report.plan.destination, plan.destination);
            expect(stored.report.confirmedCount, failure == 3 ? 1 : 0);
            expect(stored.report.uncertainCount, 0);
          }
        },
      );
    }

    test(
      '${action.name} failed receipt and finalization recover possible acceptance conservatively',
      () async {
        final plan = _plan(action);
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
        final stored = _value(await store.loadFlagBatch(_account, plan.id))!;
        expect(stored.report.confirmedCount, 0);
        expect(stored.report.uncertainCount, 1);
        expect(stored.report.unattemptedCount, 1);
        expect(stored.report.plan.destination, plan.destination);
      },
    );
  }

  test(
    'changed move destination cannot forge an acknowledgement or finalized receipt',
    () async {
      final plan = _plan(MailBulkFlagAction.move);
      final handle = await create(plan);
      _value(await store.beginFlagAttempt(handle, 0, lease: session.begin()));
      final substituted = _plan(
        MailBulkFlagAction.move,
        destination: MailMailboxId('different', account: _account),
      );
      _problem(
        await store.recordFlagResult(handle, 0, _confirmed(substituted, 0)),
        MailProblemCode.conflict,
      );
      _problem(
        await store.finishFlagBatch(handle, _report(substituted)),
        MailProblemCode.conflict,
      );
      final stored = _value(await store.loadFlagBatch(_account, plan.id))!;
      expect(stored.report.plan.destination, _destination);
      expect(stored.summary.uncertainCount, 1);
      _value(await store.recordFlagResult(handle, 0, _confirmed(plan, 0)));
      _value(await store.finishFlagBatch(handle, _report(plan)));
    },
  );

  test(
    'move destination contributes to metadata and logical account quotas',
    () async {
      final plan = _plan(
        MailBulkFlagAction.move,
        count: 1,
        destination: MailMailboxId('x' * 1000, account: _account),
      );
      for (final limits in [
        const MailStoreLimits(maxMetadataCodeUnits: 1000),
        const MailStoreLimits(maxAccountBytes: 1000),
      ]) {
        await reopen(limits: limits);
        _problem(
          await store.createFlagBatch(
            plan,
            subjects: ['subject'],
            lease: session.begin(),
          ),
          MailProblemCode.quotaExceeded,
        );
        expect(_value(await store.listFlagBatches(_account)).batches, isEmpty);
        final control = _plan(MailBulkFlagAction.delete, count: 1);
        final handle = await create(control);
        _value(
          await store.finishFlagBatch(handle, _report(control, confirmed: 0)),
        );
        expect(_value(await store.clearCompletedFlagBatches(_account)), 1);
      }
    },
  );

  for (final corrupt in <Object?>[
    null,
    '',
    'inbox',
    'bad\nfolder',
    'x' * 40000,
    Uint8List.fromList([1, 2]),
  ]) {
    test(
      'corrupt destination ${corrupt == null ? 'null' : corrupt.runtimeType} ${corrupt is String ? corrupt.length : ''} cannot be loaded or cleaned',
      () async {
        final plan = _plan(MailBulkFlagAction.move, count: 1);
        final handle = await create(plan);
        _value(
          await store.finishFlagBatch(handle, _report(plan, confirmed: 0)),
        );
        await store.close();
        final db = sqlite.sqlite3.open(file.path);
        try {
          db.execute('PRAGMA ignore_check_constraints = ON');
          db.execute('UPDATE flag_batches SET destination=?', [corrupt]);
        } finally {
          db.close();
        }
        store = await open();
        probe.oversizedTransferred = false;
        _problem(
          await store.loadFlagBatch(_account, plan.id),
          MailProblemCode.storageFailure,
        );
        _problem(
          await store.clearCompletedFlagBatches(_account),
          MailProblemCode.storageFailure,
        );
        expect(probe.oversizedTransferred, isFalse);
      },
    );
  }

  test(
    'injected flag resolution cannot release uncertain move retention',
    () async {
      final plan = _plan(MailBulkFlagAction.move);
      final handle = await create(plan);
      _value(await store.beginFlagAttempt(handle, 0, lease: session.begin()));
      await reopen();
      await store.close();
      final db = sqlite.sqlite3.open(file.path);
      try {
        db.execute(
          'INSERT INTO flag_item_resolutions(account,batch,position,kind,checked_at) VALUES(?,?,0,?,?)',
          [_account.value, plan.id, 'missing', _time.millisecondsSinceEpoch],
        );
      } finally {
        db.close();
      }
      store = await open();
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
