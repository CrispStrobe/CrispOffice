import 'package:quds_mail_core/quds_mail_core.dart';

import 'studio_mail_mailbox_store.dart';

/// Adapts the account's existing, exclusively owned cache. Downloading bodies
/// does not open another repository or alter synchronization checkpoints.
final class StudioMailBodyDownloadCache implements MailBodyDownloadCache {
  const StudioMailBodyDownloadCache(this.store);

  final StudioMailMailboxStore store;

  @override
  MailAccountId get account => store.account;

  Future<MailResult<T>> _result<T>(Future<T> Function() action) async {
    try {
      return MailSuccess(await action());
    } on StudioMailMailboxStoreException catch (error) {
      return MailFailure(MailProblem(error.code));
    } on MailCancelled catch (error) {
      return MailFailure(
        MailProblem(
          error.reason == MailCancellationReason.user ||
                  error.reason == MailCancellationReason.budgetExpired
              ? MailProblemCode.cancelled
              : MailProblemCode.staleOperation,
        ),
      );
    } on Object {
      return const MailFailure(MailProblem(MailProblemCode.storageFailure));
    }
  }

  @override
  Future<MailResult<MailMessage?>> load(MailHeaderRecord header) =>
      _result(() => store.loadMessage(header));

  @override
  Future<MailResult<MailUnit>> save(
    MailHeaderRecord header,
    MailMessage message, {
    required MailOperationLease lease,
  }) => _result(() async {
    await store.cacheMessage(header, message, lease: lease);
    return MailUnit.value;
  });
}
