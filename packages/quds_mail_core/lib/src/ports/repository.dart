import '../model/identity.dart';
import '../model/result.dart';
import '../sync/cancellation.dart';
import '../sync/outbox.dart';
import 'provider.dart';

abstract interface class MailSyncRepository {
  Future<MailResult<MailCursor?>> readCursor(MailMailboxId mailbox);

  /// Commit records, memberships, tombstones and cursor atomically. Recheck the
  /// lease inside the transaction before commit, not just before opening it.
  /// A reset must reconcile pending local edits instead of discarding them.
  Future<MailResult<MailUnit>> commitSyncPage(
    MailSyncPage page, {
    required MailOperationLease lease,
  });
}

/// Product/profile-scoped durable domain storage. No implementation is implied.
abstract interface class MailRepository implements MailSyncRepository {
  MailProfileId get profile;
  Stream<MailResult<List<MailHeaderRecord>>> watchHeaders(
    MailMailboxId mailbox,
  );
  Future<MailResult<MailUnit>> saveDraft(
    MailDraft draft, {
    required int? expectedRevision,
  });
  Future<MailResult<MailDraft?>> loadDraft(
    MailAccountId account,
    String draftId,
  );

  /// Compare and persist the whole state, including frozen payload references,
  /// before a provider is invoked. Never evict drafts/queued/active snapshots.
  Future<MailResult<MailUnit>> saveOutbox(
    MailOutboxEntry entry, {
    required MailOutboxState? expectedState,
    required String? expectedAttemptId,
  });
  Future<MailResult<List<MailOutboxEntry>>> recoverOutbox(
    MailAccountId account,
  );

  /// Local removal only. Never deletes a provider mailbox or remote messages.
  Future<MailResult<MailUnit>> removeAccount(MailAccountId account);
}
