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
  });
  final MailMessageId id;
  final MailRemoteIdentity remote;
  final MailEnvelope envelope;
}

final class MailHeaderPage {
  MailHeaderPage({required List<MailHeaderRecord> messages, this.next})
    : messages = List.unmodifiable(messages);
  final List<MailHeaderRecord> messages;
  final MailCursor? next;
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
  }) : upserts = List.unmodifiable(upserts),
       tombstones = List.unmodifiable(tombstones) {
    if (next.mailbox != mailbox ||
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
    }
  }
  final MailMailboxId mailbox;
  final List<MailHeaderRecord> upserts;
  final List<MailRemoteIdentity> tombstones;
  final MailCursor next;
  final bool hasMore;
  final bool resetRequired;
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
