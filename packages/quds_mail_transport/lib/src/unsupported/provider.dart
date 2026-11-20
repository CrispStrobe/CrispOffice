import 'package:quds_mail_core/quds_mail_core.dart';

import '../configuration.dart';

/// Generic IMAP sockets are not available in a browser. No vault is accessed.
MailProvider createMailImapProvider({
  required MailImapConfiguration configuration,
  required MailCredentialStore credentialStore,
  MailCodec? codec,
  MailTransportLimits limits = const MailTransportLimits(),
}) {
  limits.validate();
  return _UnsupportedMailProvider(configuration.account);
}

final class _UnsupportedMailProvider implements MailProvider {
  _UnsupportedMailProvider(this.account);
  @override
  final MailAccountId account;

  MailResult<T> _unavailable<T>() => const MailFailure(
    MailProblem(MailProblemCode.unsupported, mutationMayHaveOccurred: false),
  );

  @override
  Future<MailResult<MailCapabilities>> capabilities(
    MailOperationLease lease,
  ) async => _unavailable();
  @override
  Future<MailResult<List<MailMailbox>>> listMailboxes(
    MailOperationLease lease,
  ) async => _unavailable();
  @override
  Future<MailResult<MailHeaderPage>> fetchHeaders(
    MailMailboxId mailbox, {
    MailCursor? cursor,
    required int limit,
    required MailOperationLease lease,
  }) async => _unavailable();
  @override
  Future<MailResult<MailMessage>> fetchMessage(
    MailRemoteIdentity identity, {
    required MailReadBudget budget,
    required MailOperationLease lease,
  }) async => _unavailable();
  @override
  Future<MailResult<MailSyncPage>> pullChanges(
    MailMailboxId mailbox, {
    MailCursor? cursor,
    required int limit,
    required MailOperationLease lease,
  }) async => _unavailable();
  @override
  Future<MailResult<MailUnit>> apply(
    MailOperation operation,
    MailOperationLease lease,
  ) async => _unavailable();
}
