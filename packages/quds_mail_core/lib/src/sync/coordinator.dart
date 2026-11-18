import '../model/identity.dart';
import '../model/result.dart';
import '../ports/provider.dart';
import '../ports/repository.dart';
import 'cancellation.dart';

/// One bounded synchronization transaction. Scheduling, persistence and clocks
/// belong to the host. Provider cursors advance only in commitSyncPage.
final class MailSyncCoordinator {
  const MailSyncCoordinator();

  Future<MailResult<MailSyncPage>> pullPage({
    required MailProvider provider,
    required MailSyncRepository repository,
    required MailAccountSession session,
    required MailMailboxId mailbox,
    int limit = 100,
    MailCancellationToken? cancellation,
  }) async {
    if (limit < 1 ||
        limit > 1000 ||
        provider.account != session.account ||
        mailbox.account != session.account) {
      return const MailFailure(MailProblem(MailProblemCode.invalidInput));
    }
    try {
      final lease = session.begin(cancellation: cancellation);
      final cursorResult = await repository.readCursor(mailbox);
      lease.checkCurrent();
      if (cursorResult case MailFailure<MailCursor?>(:final problem)) {
        return MailFailure(problem);
      }
      final cursor = (cursorResult as MailSuccess<MailCursor?>).value;
      if (cursor != null && cursor.mailbox != mailbox) {
        return const MailFailure(MailProblem(MailProblemCode.storageFailure));
      }
      final pageResult = await provider.pullChanges(
        mailbox,
        cursor: cursor,
        limit: limit,
        lease: lease,
      );
      lease.checkCurrent();
      if (pageResult case MailFailure<MailSyncPage>(:final problem)) {
        return MailFailure(problem);
      }
      final page = (pageResult as MailSuccess<MailSyncPage>).value;
      if (page.mailbox != mailbox ||
          page.upserts.length + page.tombstones.length > limit) {
        return const MailFailure(MailProblem(MailProblemCode.providerFailure));
      }
      final committed = await repository.commitSyncPage(page, lease: lease);
      lease.checkCurrent();
      if (committed case MailFailure<MailUnit>(:final problem)) {
        return MailFailure(problem);
      }
      return MailSuccess(page);
    } on MailCancelled catch (cancelled) {
      return MailFailure(
        MailProblem(
          cancelled.reason == MailCancellationReason.user ||
                  cancelled.reason == MailCancellationReason.budgetExpired
              ? MailProblemCode.cancelled
              : MailProblemCode.staleOperation,
        ),
      );
    }
  }
}
