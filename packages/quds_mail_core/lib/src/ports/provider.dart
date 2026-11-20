import '../model/capabilities.dart';
import '../model/identity.dart';
import '../model/message.dart';
import '../model/parse.dart';
import '../model/result.dart';
import '../sync/cancellation.dart';
import '../sync/outbox.dart';

final class MailMailbox {
  const MailMailbox({
    required this.id,
    required this.displayName,
    this.isLabel = false,
  });
  final MailMailboxId id;
  final String displayName;
  final bool isLabel;
}

/// Opaque cursors are scoped to a mailbox and cannot be reused across accounts.
final class MailCursor {
  const MailCursor({required this.mailbox, required this.value});
  final MailMailboxId mailbox;
  final String value;
}

final class MailHeaderRecord {
  const MailHeaderRecord({
    required this.id,
    required this.remote,
    required this.envelope,
    this.flags,
  });
  final MailMessageId id;
  final MailRemoteIdentity remote;
  final MailEnvelope envelope;

  /// Null means not observed. Persisting an unobserved snapshot must not clear
  /// previously observed flags for this exact remote identity.
  final MailMessageFlags? flags;
}

final class MailHeaderPage {
  MailHeaderPage({required List<MailHeaderRecord> messages, this.next})
    : messages = List.unmodifiable(messages);
  final List<MailHeaderRecord> messages;
  final MailCursor? next;
}

/// A completely observed, inclusive UID range in one IMAP mailbox generation.
///
/// When attached to a [MailSyncPage], that page's upserts are the authoritative
/// surviving identities in this range. Repositories reconcile only existing
/// memberships; unused numeric UIDs do not require invented tombstones.
final class MailImapSyncRange {
  MailImapSyncRange({
    required this.mailbox,
    required this.uidValidity,
    required this.firstUid,
    required this.lastUid,
  }) {
    if (uidValidity < 1 ||
        uidValidity > 0xffffffff ||
        firstUid < 1 ||
        firstUid > 0xffffffff ||
        lastUid < firstUid ||
        lastUid > 0xffffffff) {
      throw ArgumentError(
        'IMAP sync ranges require ordered unsigned nonzero 32-bit UIDs '
        'and UIDVALIDITY.',
      );
    }
  }

  final MailMailboxId mailbox;
  final int uidValidity;
  final int firstUid;
  final int lastUid;
}

/// A page and its next cursor must be persisted as a single transaction.
final class MailSyncPage {
  MailSyncPage({
    required this.mailbox,
    required List<MailHeaderRecord> upserts,
    required List<MailRemoteIdentity> tombstones,
    required this.next,
    required this.hasMore,
    this.resetRequired = false,
    this.imapRange,
  }) : upserts = List.unmodifiable(upserts),
       tombstones = List.unmodifiable(tombstones) {
    if (next.mailbox != mailbox ||
        (imapRange != null && imapRange!.mailbox != mailbox) ||
        upserts.any((record) => record.remote.account != mailbox.account) ||
        tombstones.any((identity) => identity.account != mailbox.account)) {
      throw ArgumentError(
        'Sync pages and cursors must belong to the same account and mailbox.',
      );
    }
    for (final identity in <MailRemoteIdentity>[
      ...upserts.map((record) => record.remote),
      ...tombstones,
    ]) {
      if (identity is MailImapIdentity && identity.mailbox != mailbox) {
        throw ArgumentError(
          'IMAP sync identity belongs to a different mailbox.',
        );
      }
      if (imapRange case final range?) {
        if (identity is! MailImapIdentity ||
            identity.uidValidity != range.uidValidity ||
            identity.uid < range.firstUid ||
            identity.uid > range.lastUid) {
          throw ArgumentError(
            'IMAP range records must belong to the observed UID range '
            'and UIDVALIDITY.',
          );
        }
      }
    }
  }
  final MailMailboxId mailbox;
  final List<MailHeaderRecord> upserts;
  final List<MailRemoteIdentity> tombstones;
  final MailCursor next;
  final bool hasMore;
  final bool resetRequired;

  /// All surviving identities in this closed range are present in [upserts].
  /// A repository removes only absent existing memberships in the same mailbox
  /// and UIDVALIDITY, atomically with this page and its cursor. [resetRequired]
  /// retains its independent full-mailbox reset and pending-edit semantics.
  final MailImapSyncRange? imapRange;
}

sealed class MailOperation {
  const MailOperation({required this.id, required this.message});
  final String id;
  final MailRemoteIdentity message;
}

final class MailSetRead extends MailOperation {
  const MailSetRead({
    required super.id,
    required super.message,
    required this.read,
  });
  final bool read;
}

final class MailSetFlagged extends MailOperation {
  const MailSetFlagged({
    required super.id,
    required super.message,
    required this.flagged,
  });
  final bool flagged;
}

final class MailMove extends MailOperation {
  MailMove({
    required super.id,
    required super.message,
    required this.destination,
  }) {
    if (message.account != destination.account) {
      throw ArgumentError('A move cannot cross account boundaries.');
    }
  }
  final MailMailboxId destination;
}

final class MailDelete extends MailOperation {
  const MailDelete({required super.id, required super.message});
}

/// A provider never represents unsupported operations as empty success.
abstract interface class MailProvider {
  MailAccountId get account;
  Future<MailResult<MailCapabilities>> capabilities(MailOperationLease lease);
  Future<MailResult<List<MailMailbox>>> listMailboxes(MailOperationLease lease);
  Future<MailResult<MailHeaderPage>> fetchHeaders(
    MailMailboxId mailbox, {
    MailCursor? cursor,
    required int limit,
    required MailOperationLease lease,
  });
  Future<MailResult<MailMessage>> fetchMessage(
    MailRemoteIdentity identity, {
    required MailReadBudget budget,
    required MailOperationLease lease,
  });
  Future<MailResult<MailSyncPage>> pullChanges(
    MailMailboxId mailbox, {
    MailCursor? cursor,
    required int limit,
    required MailOperationLease lease,
  });
  Future<MailResult<MailUnit>> apply(
    MailOperation operation,
    MailOperationLease lease,
  );
}

/// Optional foreground IMAP browsing, independent of durable sync cursors.
///
/// Pages descend by UID within the selected [uidValidity] generation. The first
/// page fixes an upper UID boundary; later arrivals appear only after a fresh
/// browse without a cursor. A changed generation is a conflict, including for
/// an empty mailbox, rather than permission to mix two mailbox generations.
/// A bounded sparse UID window may return no messages while [MailHeaderPage.next]
/// still identifies an older unexamined range; callers must preserve that cursor.
abstract interface class MailImapHeaderBrowser {
  Future<MailResult<MailHeaderPage>> fetchNewestHeaders(
    MailMailboxId mailbox, {
    required int uidValidity,
    MailCursor? cursor,
    required int limit,
    required MailOperationLease lease,
  });
}

abstract interface class MailSubmissionProvider {
  MailAccountId get account;

  /// Called only after the repository persists the submitting attempt identity.
  /// Cancellation after possible DATA acceptance must produce uncertain.
  Future<MailSubmissionResult> submit(
    MailPreparedMessage message, {
    required String attemptId,
    required MailOperationLease lease,
  });
}

/// Optional canonical composition boundary. Reader-only codecs need not pretend
/// to support composition; the host negotiates this port separately.
abstract interface class MailComposer {
  MailResult<MailPreparedMessage> prepare(
    MailDraft draft, {
    required MailReadBudget budget,
    MailCancellationToken? cancellation,
  });
}
