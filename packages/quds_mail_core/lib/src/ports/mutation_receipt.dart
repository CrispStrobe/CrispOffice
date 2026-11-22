import '../model/identity.dart';
import '../model/result.dart';
import '../sync/cancellation.dart';
import 'provider.dart';

/// An acknowledged move's exact source and destination identities.
///
/// Providers construct this only from the mutation's authoritative response,
/// never from a missing original item or a search by subject or Message-ID.
/// The destination's local key is supplied by the provider's canonical identity
/// mapping so a later synchronization addresses the same cached message.
final class MailMoveIdentityTransition {
  MailMoveIdentityTransition({
    required this.operationId,
    required this.source,
    required this.sourceMailbox,
    required this.destination,
    required this.destinationMailbox,
    required this.destinationMessageId,
  }) {
    if (source.account != destination.account ||
        source.account != sourceMailbox.account ||
        source.account != destinationMailbox.account ||
        source.provider != destination.provider ||
        sourceMailbox == destinationMailbox ||
        (source.provider == MailProviderKind.imap &&
            sourceMailbox.value.toUpperCase() == 'INBOX' &&
            destinationMailbox.value.toUpperCase() == 'INBOX') ||
        !const {
          MailProviderKind.imap,
          MailProviderKind.graph,
          MailProviderKind.ews,
        }.contains(source.provider)) {
      throw ArgumentError(
        'Move transitions require different folders in one account/provider.',
      );
    }
    if (source is MailImapIdentity &&
            (source as MailImapIdentity).mailbox != sourceMailbox ||
        destination is MailImapIdentity &&
            (destination as MailImapIdentity).mailbox != destinationMailbox) {
      throw ArgumentError(
        'IMAP transition identities must match their folders.',
      );
    }
    for (final value in [
      operationId,
      source.account.value,
      source.account.profile.value,
      source.account.profile.hostId,
      sourceMailbox.value,
      destinationMailbox.value,
      destinationMessageId.value,
      if (source case MailOpaqueIdentity(:final value)) value,
      if (destination case MailOpaqueIdentity(:final value)) value,
    ]) {
      _checkIdentifier(value);
    }
  }

  static const maxIdentifierCodeUnits = 2048;

  static void _checkIdentifier(String value) {
    if (value.isEmpty ||
        value.length > maxIdentifierCodeUnits ||
        value.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
      throw ArgumentError('Move transition identifiers must be bounded.');
    }
    // Persisted exact identifiers must not change during UTF-8 encoding.
    for (var index = 0; index < value.length; index++) {
      final unit = value.codeUnitAt(index);
      if (unit >= 0xd800 && unit <= 0xdbff) {
        if (++index == value.length) {
          throw ArgumentError(
            'Move transition identifiers require valid UTF-16.',
          );
        }
        final low = value.codeUnitAt(index);
        if (low < 0xdc00 || low > 0xdfff) {
          throw ArgumentError(
            'Move transition identifiers require valid UTF-16.',
          );
        }
      } else if (unit >= 0xdc00 && unit <= 0xdfff) {
        throw ArgumentError(
          'Move transition identifiers require valid UTF-16.',
        );
      }
    }
  }

  final String operationId;
  final MailRemoteIdentity source;
  final MailMailboxId sourceMailbox;
  final MailRemoteIdentity destination;
  final MailMailboxId destinationMailbox;
  final MailMessageId destinationMessageId;

  /// Checks the frozen command and, when supplied, its observed source folder.
  /// Opaque message IDs alone do not establish a source folder.
  bool matches(MailOperation operation, {MailMailboxId? sourceMailbox}) =>
      operation is MailMove &&
      operation.id == operationId &&
      operation.message == source &&
      operation.destination == destinationMailbox &&
      (sourceMailbox == null || sourceMailbox == this.sourceMailbox);

  @override
  bool operator ==(Object other) =>
      other is MailMoveIdentityTransition &&
      operationId == other.operationId &&
      source == other.source &&
      sourceMailbox == other.sourceMailbox &&
      destination == other.destination &&
      destinationMailbox == other.destinationMailbox &&
      destinationMessageId == other.destinationMessageId;

  @override
  int get hashCode => Object.hash(
    operationId,
    source,
    sourceMailbox,
    destination,
    destinationMailbox,
    destinationMessageId,
  );
}

/// A confirmed mutation, optionally carrying an authoritative move identity.
/// Missing identity evidence remains a confirmed generic acknowledgement.
final class MailMutationReceipt {
  const MailMutationReceipt({this.identityTransition});

  final MailMoveIdentityTransition? identityTransition;
}

/// Optional additive port. Existing providers retain their [MailProvider.apply]
/// contract and need not fabricate destination identities to implement it.
abstract interface class MailMutationReceiptProvider {
  MailAccountId get account;

  Future<MailResult<MailMutationReceipt>> applyWithReceipt(
    MailOperation operation,
    MailOperationLease lease,
  );
}
