import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_mime/quds_mail_mime.dart';

import 'configuration.dart';

MailCloudProvider createMailCloudProvider({
  required MailCloudConfiguration configuration,
  required MailCloudTokenSource tokenSource,
  MailCodec codec = const QudsMimeCodec(),
  MailCloudLimits limits = const MailCloudLimits(),
  MailCloudLogSink? log,
}) {
  limits.validate();
  return _UnsupportedCloudProvider(configuration.account);
}

Future<MailResult<MailCloudTokenSource>> authorizeMailCloud({
  required MailOAuthConfiguration configuration,
  required MailAccountId account,
  required Future<bool> Function(Uri) openBrowser,
  required MailOperationLease lease,
  MailCloudLogSink? log,
  Duration timeout = const Duration(minutes: 5),
}) async => const MailFailure(MailProblem(MailProblemCode.unsupported));

Future<MailResult<MailCloudTokenSource>> authorizeTasksCloud({
  required MailOAuthConfiguration configuration,
  required MailAccountId account,
  required Future<bool> Function(Uri) openBrowser,
  required MailOperationLease lease,
  required Future<void> Function(String) saveRefreshToken,
}) async => const MailFailure(MailProblem(MailProblemCode.unsupported));

MailCloudTokenSource restoreTasksCloud({
  required MailOAuthConfiguration configuration,
  required MailAccountId account,
  required String refreshToken,
  required Future<void> Function(String) saveRefreshToken,
}) => throw UnsupportedError(
  'Tasks authorization requires a native browser callback.',
);

final class _UnsupportedCloudProvider
    implements MailCloudProvider, MailFlagObserver, MailMembershipObserver {
  _UnsupportedCloudProvider(this.account);
  @override
  final MailAccountId account;
  MailFailure<T> _failure<T>() => const MailFailure(
    MailProblem(MailProblemCode.unsupported, mutationMayHaveOccurred: false),
  );
  @override
  Future<MailResult<MailCapabilities>> capabilities(
    MailOperationLease lease,
  ) async => _failure();
  @override
  Future<MailResult<MailFlagObservation>> observeFlags(
    MailRemoteIdentity identity, {
    required MailOperationLease lease,
  }) async => _failure();
  @override
  Future<MailResult<MailMembershipObservation>> observeMembership(
    MailRemoteIdentity identity, {
    required MailOperationLease lease,
  }) async => _failure();
  @override
  Future<MailResult<List<MailMailbox>>> listMailboxes(
    MailOperationLease lease,
  ) async => _failure();
  @override
  Future<MailResult<MailHeaderPage>> fetchHeaders(
    MailMailboxId mailbox, {
    MailCursor? cursor,
    required int limit,
    required MailOperationLease lease,
  }) async => _failure();
  @override
  Future<MailResult<MailMessage>> fetchMessage(
    MailRemoteIdentity identity, {
    required MailReadBudget budget,
    required MailOperationLease lease,
  }) async => _failure();
  @override
  Future<MailResult<MailSyncPage>> pullChanges(
    MailMailboxId mailbox, {
    MailCursor? cursor,
    required int limit,
    required MailOperationLease lease,
  }) async => _failure();
  @override
  Future<MailResult<MailUnit>> apply(
    MailOperation operation,
    MailOperationLease lease,
  ) async => _failure();
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
  @override
  void dispose() {}
}
