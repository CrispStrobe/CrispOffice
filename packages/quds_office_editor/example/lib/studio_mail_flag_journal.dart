import 'dart:async';
import 'dart:math';

import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';

import 'studio_mail_mailbox_store.dart';

part 'studio_mail_flag_reconciliation.dart';
part 'studio_mail_membership_reconciliation.dart';

/// The enclosing draft owner serializes and closes this shared repository.
abstract interface class StudioMailFlagJournalOwner {
  StudioMailFlagJournalStore get flagJournal;
}

abstract interface class StudioMailFlagJournalStore {
  MailAccountId get account;

  MailBulkFlagJournal bind({
    required MailAccountId sourceAccount,
    required MailProviderKind provider,
    required List<String> subjects,
    required bool Function() isCurrent,
  });

  Future<MailStoredFlagBatchPage> list({int limit = 20, int offset = 0});
  Future<MailStoredFlagBatch?> load(String id);
  Future<int> clearCompleted();
}

MailBulkFlagJournal? studioMailFlagJournal({
  required Object? owner,
  required bool requireDurable,
  required MailAccountId sourceAccount,
  required MailProviderKind provider,
  required List<String> subjects,
  required bool Function() isCurrent,
}) => switch (owner) {
  StudioMailFlagJournalOwner(:final flagJournal) => flagJournal.bind(
    sourceAccount: sourceAccount,
    provider: provider,
    subjects: subjects,
    isCurrent: isCurrent,
  ),
  _ when requireDurable || owner == null =>
    const UnavailableStudioMailFlagJournal(),
  _ => null,
};

final class StudioMailFlagJournalException implements Exception {
  const StudioMailFlagJournalException(this.code);
  final MailProblemCode code;
}

/// IDs remain distinct when a process restarts or two profiles act together.
/// They contain neither provider identifiers nor subjects.
String newStudioMailFlagOperationId() {
  final random = Random.secure();
  final suffix = List.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  return 'flags-${DateTime.now().microsecondsSinceEpoch}-$suffix';
}

/// A real host whose local storage failed must never silently send without it.
/// Explicit custom hosts may continue to use the core's foreground-only seam.
final class UnavailableStudioMailFlagJournal implements MailBulkFlagJournal {
  const UnavailableStudioMailFlagJournal();

  static const MailResult<MailUnit> _failure = MailFailure(
    MailProblem(MailProblemCode.storageFailure),
  );

  @override
  Future<MailResult<MailUnit>> prepare(MailBulkFlagPlan plan) async => _failure;
  @override
  Future<MailResult<MailUnit>> beginAttempt(int index) async => _failure;
  @override
  Future<MailResult<MailUnit>> recordResult(
    int index,
    MailBulkFlagItemResult result,
  ) async => _failure;
  @override
  Future<MailResult<MailUnit>> finish(MailBulkFlagReport report) async =>
      _failure;
}

final class SqliteStudioMailFlagJournalStore
    implements
        StudioMailFlagJournalStore,
        StudioMailFlagReconciliationStore,
        StudioMailMembershipReconciliationStore {
  SqliteStudioMailFlagJournalStore({
    required this._repository,
    required this.account,
    required this._serialize,
  });

  final SqliteMailRepository _repository;
  final StudioMailStorageQueue _serialize;
  @override
  final MailAccountId account;

  static T _value<T>(MailResult<T> result) => switch (result) {
    MailSuccess<T>(:final value) => value,
    MailFailure<T>(:final problem) => throw StudioMailFlagJournalException(
      problem.code,
    ),
  };

  @override
  MailBulkFlagJournal bind({
    required MailAccountId sourceAccount,
    required MailProviderKind provider,
    required List<String> subjects,
    required bool Function() isCurrent,
  }) => _StudioMailFlagJournal(
    store: this,
    sourceAccount: sourceAccount,
    provider: provider,
    subjects: List.unmodifiable(subjects),
    isCurrent: isCurrent,
  );

  @override
  Future<MailStoredFlagBatchPage> list({int limit = 20, int offset = 0}) =>
      _serialize(
        () async => _value(
          await _repository.listFlagBatches(
            account,
            limit: limit,
            offset: offset,
          ),
        ),
      );

  @override
  Future<MailStoredFlagBatch?> load(String id) => _serialize(
    () async => _value(await _repository.loadFlagBatch(account, id)),
  );

  @override
  Future<int> clearCompleted() => _serialize(
    () async => _value(await _repository.clearCompletedFlagBatches(account)),
  );

  @override
  Future<MailStoredFlagBatch> reconcile({
    required String id,
    required int expectedRevision,
    required MailAccountId sourceAccount,
    required MailProviderKind provider,
    required MailFlagObserver observer,
    required bool Function() isCurrent,
    MailCancellationToken? cancellation,
  }) => _reconcileFlagBatch(
    this,
    id: id,
    expectedRevision: expectedRevision,
    sourceAccount: sourceAccount,
    provider: provider,
    observer: observer,
    isCurrent: isCurrent,
    cancellation: cancellation,
  );

  @override
  Future<MailStoredFlagBatch> reconcileMembership({
    required String id,
    required int expectedRevision,
    required MailAccountId sourceAccount,
    required MailProviderKind provider,
    required MailMembershipObserver observer,
    required bool Function() isCurrent,
    MailCancellationToken? cancellation,
  }) => _reconcileMembershipBatch(
    this,
    id: id,
    expectedRevision: expectedRevision,
    sourceAccount: sourceAccount,
    provider: provider,
    observer: observer,
    isCurrent: isCurrent,
    cancellation: cancellation,
  );
}

/// Rebinds a frozen connection namespace into its stable local account.
/// Dispatch authority expires with the view, while a settled reply can still
/// be recorded by the original, active repository owner. Neither method holds
/// a transport or offers an automatic retry.
final class _StudioMailFlagJournal implements MailBulkFlagJournal {
  _StudioMailFlagJournal({
    required this.store,
    required this.sourceAccount,
    required this.provider,
    required this.subjects,
    required this._isCurrent,
  }) : _session = MailAccountSession(store.account);

  final SqliteStudioMailFlagJournalStore store;
  final MailAccountId sourceAccount;
  final MailProviderKind provider;
  final List<String> subjects;
  final bool Function() _isCurrent;
  final MailAccountSession _session;
  MailFlagBatchHandle? _handle;
  MailBulkFlagPlan? _source;
  MailBulkFlagPlan? _local;
  bool _prepared = false;

  MailOperationLease _lease() {
    if (!_isCurrent()) _session.dispose();
    final lease = _session.begin();
    lease.checkCurrent();
    return lease;
  }

  Future<MailResult<MailUnit>> _write(
    Future<MailResult<MailUnit>> Function() action,
  ) async {
    try {
      return await store._serialize(action);
    } on Object {
      return const MailFailure(MailProblem(MailProblemCode.storageFailure));
    }
  }

  MailRemoteIdentity _remote(MailRemoteIdentity source) {
    if (source.account != sourceAccount || source.provider != provider) {
      throw const StudioMailFlagJournalException(
        MailProblemCode.permissionDenied,
      );
    }
    return switch (source) {
      MailImapIdentity(:final mailbox, :final uidValidity, :final uid) =>
        MailImapIdentity(
          mailbox: MailMailboxId(mailbox.value, account: store.account),
          uidValidity: uidValidity,
          uid: uid,
        ),
      MailOpaqueIdentity(:final value) => MailOpaqueIdentity(
        account: store.account,
        provider: provider,
        value: value,
      ),
    };
  }

  @override
  Future<MailResult<MailUnit>> prepare(MailBulkFlagPlan plan) =>
      _write(() async {
        if (_prepared ||
            plan.mailbox.account != sourceAccount ||
            plan.provider != provider ||
            subjects.length != plan.messages.length) {
          return const MailFailure(MailProblem(MailProblemCode.conflict));
        }
        _prepared = true;
        final lease = _lease();
        final local = MailBulkFlagPlan(
          id: plan.id,
          mailbox: MailMailboxId(plan.mailbox.value, account: store.account),
          provider: provider,
          messages: [for (final remote in plan.messages) _remote(remote)],
          action: plan.action,
          destination: plan.destination == null
              ? null
              : MailMailboxId(plan.destination!.value, account: store.account),
        );
        final created = await store._repository.createFlagBatch(
          local,
          subjects: subjects,
          lease: lease,
        );
        switch (created) {
          case MailFailure<MailFlagBatchHandle>(:final problem):
            return MailFailure(problem);
          case MailSuccess<MailFlagBatchHandle>(:final value):
            _handle = value;
            _source = plan;
            _local = local;
            return const MailSuccess(MailUnit.value);
        }
      });

  @override
  Future<MailResult<MailUnit>> beginAttempt(int index) => _write(() async {
    final handle = _handle;
    if (handle == null) {
      return const MailFailure(MailProblem(MailProblemCode.conflict));
    }
    return store._repository.beginFlagAttempt(handle, index, lease: _lease());
  });

  MailBulkFlagItemResult _result(int index, MailBulkFlagItemResult result) {
    final source = _source!;
    final expected = source.operationAt(index);
    if (result.operation.id != expected.id ||
        result.message != expected.message ||
        result.operation.runtimeType != expected.runtimeType ||
        result.operation is MailSetRead &&
            (result.operation as MailSetRead).read !=
                (expected as MailSetRead).read ||
        result.operation is MailSetFlagged &&
            (result.operation as MailSetFlagged).flagged !=
                (expected as MailSetFlagged).flagged ||
        result.operation is MailMove &&
            (result.operation as MailMove).destination !=
                (expected as MailMove).destination) {
      throw const StudioMailFlagJournalException(MailProblemCode.conflict);
    }
    return MailBulkFlagItemResult.restore(
      operation: _local!.operationAt(index),
      outcome: result.outcome,
      problem: result.problem,
    );
  }

  @override
  Future<MailResult<MailUnit>> recordResult(
    int index,
    MailBulkFlagItemResult result,
  ) => _write(() async {
    final handle = _handle;
    if (handle == null) {
      return const MailFailure(MailProblem(MailProblemCode.conflict));
    }
    return store._repository.recordFlagResult(
      handle,
      index,
      _result(index, result),
    );
  });

  @override
  Future<MailResult<MailUnit>> finish(MailBulkFlagReport report) =>
      _write(() async {
        try {
          final handle = _handle;
          if (handle == null || !identical(report.plan, _source)) {
            return const MailFailure(MailProblem(MailProblemCode.conflict));
          }
          return await store._repository.finishFlagBatch(
            handle,
            MailBulkFlagReport.restore(
              plan: _local!,
              results: [
                for (var i = 0; i < report.items.length; i++)
                  _result(i, report.items[i]),
              ],
              stopProblem: report.stopProblem,
              stopReason: report.stopReason,
              persistenceProblem: report.persistenceProblem,
            ),
          );
        } finally {
          _session.dispose();
        }
      });
}
