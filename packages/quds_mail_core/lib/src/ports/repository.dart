import '../model/identity.dart';
import '../model/result.dart';
import '../sync/cancellation.dart';
import '../sync/outbox.dart';
import 'provider.dart';

abstract interface class MailSyncRepository {
  Future<MailResult<MailCursor?>> readCursor(MailMailboxId mailbox);

  /// Commit records, memberships, tombstones and cursor atomically. Recheck the
  /// lease inside the transaction before commit, not just before opening it.
  /// Compare [expectedCursor] inside the same transaction; null requires that
  /// no cursor exists. A concurrently advanced cursor returns conflict rather
  /// than allowing an older page to overwrite newer mailbox state.
  /// A reset must reconcile pending local edits instead of discarding them.
  /// An IMAP authoritative range reconciles absent existing memberships in
  /// that mailbox and UIDVALIDITY; numeric holes do not create stored records.
  Future<MailResult<MailUnit>> commitSyncPage(
    MailSyncPage page, {
    required MailCursor? expectedCursor,
    required MailOperationLease lease,
  });
}

/// One atomic read of a mailbox's provider cursor and local membership fence.
///
/// A null cursor still carries [revision]: a local move can change retained
/// membership before the mailbox's first provider synchronization. Capturing
/// both values together prevents an older first page from restoring that mail.
final class MailSyncRepositorySnapshot {
  MailSyncRepositorySnapshot({
    required this.mailbox,
    required this.cursor,
    required this.revision,
  }) {
    if (revision < 0 || revision > 0x1fffffffffffff) {
      throw ArgumentError('Sync snapshot revisions must be bounded.');
    }
    if (cursor != null && cursor!.mailbox != mailbox) {
      throw ArgumentError('Sync snapshots must retain their exact mailbox.');
    }
    if (cursor?.repositoryRevision != null &&
        cursor!.repositoryRevision != revision) {
      throw ArgumentError(
        'Sync snapshot cursor and local revision must agree.',
      );
    }
  }

  final MailMailboxId mailbox;
  final MailCursor? cursor;
  final int revision;
}

/// Optional null-safe synchronization fence for repositories with local moves.
/// Legacy repositories retain [MailSyncRepository]'s cursor-only contract.
abstract interface class MailSyncSnapshotRepository
    implements MailSyncRepository {
  /// Read the cursor and membership revision from the same database snapshot.
  Future<MailResult<MailSyncRepositorySnapshot>> readSyncSnapshot(
    MailMailboxId mailbox,
  );

  /// Compare the complete [expectedSnapshot], including a null cursor, inside
  /// the transaction that commits the page. A changed local revision conflicts
  /// even when provider cursor bytes did not change. Preserve the regular
  /// [MailSyncRepository.commitSyncPage] lease and atomicity requirements.
  Future<MailResult<MailUnit>> commitSyncPageWithSnapshot(
    MailSyncPage page, {
    required MailSyncRepositorySnapshot expectedSnapshot,
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
  /// Once either snapshot has a schedule revision, [expectedScheduleRevision]
  /// must explicitly match the persisted revision. Clearing a schedule retains
  /// its revision, so stale send/cancel decisions cannot bypass a reschedule.
  Future<MailResult<MailUnit>> saveOutbox(
    MailOutboxEntry entry, {
    required MailOutboxState? expectedState,
    required String? expectedAttemptId,
    int? expectedScheduleRevision,
  });
  Future<MailResult<List<MailOutboxEntry>>> recoverOutbox(
    MailAccountId account,
  );

  /// Local removal only. Never deletes a provider mailbox or remote messages.
  Future<MailResult<MailUnit>> removeAccount(MailAccountId account);
}
