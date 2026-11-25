import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_mime/quds_mail_mime.dart';
import 'package:quds_tasks_core/quds_tasks_core.dart';

import 'configuration.dart';
import 'tasks.dart';

/// Browsers cannot provide this native integrated-auth transport. The fallback
/// touches neither credentials nor the codec and advertises no empty success.
MailEwsProvider createMailEwsProvider({
  required MailEwsConfiguration configuration,
  required MailCredentialStore credentialStore,
  MailCodec codec = const QudsMimeCodec(),
  MailEwsLimits limits = const MailEwsLimits(),
}) {
  limits.validate();
  return _UnsupportedEwsProvider(configuration.account);
}

final class _UnsupportedEwsProvider
    implements MailEwsProvider, MailFlagObserver, MailMembershipObserver {
  _UnsupportedEwsProvider(this.account);
  @override
  final MailAccountId account;

  MailResult<T> _unsupported<T>() => const MailFailure(
    MailProblem(MailProblemCode.unsupported, mutationMayHaveOccurred: false),
  );

  @override
  Future<MailResult<MailCapabilities>> capabilities(
    MailOperationLease lease,
  ) async => _unsupported();

  @override
  Future<MailResult<MailFlagObservation>> observeFlags(
    MailRemoteIdentity identity, {
    required MailOperationLease lease,
  }) async => _unsupported();

  @override
  Future<MailResult<MailMembershipObservation>> observeMembership(
    MailRemoteIdentity identity, {
    required MailOperationLease lease,
  }) async => _unsupported();

  @override
  Future<MailResult<List<MailMailbox>>> listMailboxes(
    MailOperationLease lease,
  ) async => _unsupported();

  @override
  Future<MailResult<MailHeaderPage>> fetchHeaders(
    MailMailboxId mailbox, {
    MailCursor? cursor,
    required int limit,
    required MailOperationLease lease,
  }) async => _unsupported();

  @override
  Future<MailResult<MailMessage>> fetchMessage(
    MailRemoteIdentity identity, {
    required MailReadBudget budget,
    required MailOperationLease lease,
  }) async => _unsupported();

  @override
  Future<MailResult<MailSyncPage>> pullChanges(
    MailMailboxId mailbox, {
    MailCursor? cursor,
    required int limit,
    required MailOperationLease lease,
  }) async => _unsupported();

  @override
  Future<MailResult<MailUnit>> apply(
    MailOperation operation,
    MailOperationLease lease,
  ) async => _unsupported();

  @override
  Future<MailSubmissionResult> submit(
    MailPreparedMessage message, {
    required String attemptId,
    required MailOperationLease lease,
  }) async => MailSubmissionResult(
    attemptId: attemptId,
    outcome: MailSubmissionOutcome.rejected,
    problem: const MailProblem(MailProblemCode.unsupported),
  );
}

EwsTaskReader createEwsTaskReader({
  required TaskAccountId account,
  required MailEwsConfiguration configuration,
  required MailCredentialStore credentialStore,
  MailEwsLimits limits = const MailEwsLimits(),
}) {
  limits.validate();
  return const _UnsupportedEwsTaskReader();
}

final class _UnsupportedEwsTaskReader implements EwsTaskReader {
  const _UnsupportedEwsTaskReader();

  @override
  Future<TaskResult<List<TaskList>>> taskLists(
    MailOperationLease lease,
  ) async => const TaskFailure(TaskProblem(TaskProblemCode.unsupported));

  @override
  Future<TaskResult<TaskList>> defaultTaskList(
    MailOperationLease lease,
  ) async => const TaskFailure(TaskProblem(TaskProblemCode.unsupported));

  @override
  Future<TaskResult<TaskSyncPage>> pullTasks(
    TaskListId list, {
    String? cursor,
    required MailOperationLease lease,
  }) async => const TaskFailure(TaskProblem(TaskProblemCode.unsupported));
}
