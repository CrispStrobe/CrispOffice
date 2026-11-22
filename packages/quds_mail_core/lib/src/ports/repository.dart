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

/// One atomic repository observation, including a mailbox without a cursor.
///
/// [revision] fences local membership changes independently of opaque provider
/// cursor bytes. It must be retained even when [cursor] is null, so an in-flight
/// first page cannot overwrite a move acknowledged after the read.
final class MailSyncRepositorySnapshot {
  MailSyncRepositorySnapshot({
    required this.mailbox,
    required this.cursor,
    required this.revision,
  }) {
    if (revision < 0 ||
        revision > 0x1fffffffffffff ||
        cursor != null && cursor!.mailbox != mailbox ||
        cursor?.repositoryRevision != null &&
            cursor!.repositoryRevision != revision) {
      throw ArgumentError('Sync snapshots require one mailbox and revision.');
    }
  }

  final MailMailboxId mailbox;
  final MailCursor? cursor;
  final int revision;
}

/// Optional atomic cursor/membership fence, preserving the legacy sync port.
abstract interface class MailSyncSnapshotRepository
    implements MailSyncRepository {
  Future<MailResult<MailSyncRepositorySnapshot>> readSyncSnapshot(
    MailMailboxId mailbox,
  );

  /// Compare both cursor and local revision in the same transaction as the
  /// page writes. A missing cursor still carries the snapshot's revision.
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
