import '../model/identity.dart';
import '../model/result.dart';
import '../sync/cancellation.dart';

/// A current observation of one exact identity, never a command receipt.
enum MailMembershipObservationKind { present, missing, identityChanged }

/// Provider-specific current location evidence. An absent original identity
/// does not establish where a message moved or whether a prior command worked.
/// In particular, no Message-ID, subject or sequence-number matching is allowed.
final class MailMembershipObservation {
  MailMembershipObservation.imap({
    required MailImapIdentity identity,
    required bool isDeleted,
  }) : this._(
         identity: identity,
         kind: MailMembershipObservationKind.present,
         mailboxes: [identity.mailbox],
         isDeleted: isDeleted,
       );

  /// A complete current label set (Gmail) or one current parent folder
  /// (Microsoft 365/Exchange). [deletionMailbox], when provided, must be the
  /// provider-observed Deleted Items folder or Gmail's exact TRASH label.
  /// Its absence means that deletion status is unknown, not false.
  MailMembershipObservation.folders({
    required MailOpaqueIdentity identity,
    required List<MailMailboxId> mailboxes,
    MailMailboxId? deletionMailbox,
  }) : this._(
         identity: identity,
         kind: MailMembershipObservationKind.present,
         mailboxes: mailboxes,
         deletionMailbox: deletionMailbox,
         isDeleted: deletionMailbox == null
             ? null
             : mailboxes.contains(deletionMailbox),
       );

  MailMembershipObservation.missing({required MailRemoteIdentity identity})
    : this._(
        identity: identity,
        kind: MailMembershipObservationKind.missing,
        mailboxes: const [],
      );

  /// The requested UID is not looked up in the replacement generation.
  MailMembershipObservation.identityChanged({
    required MailImapIdentity identity,
  }) : this._(
         identity: identity,
         kind: MailMembershipObservationKind.identityChanged,
         mailboxes: const [],
       );

  MailMembershipObservation._({
    required this.identity,
    required this.kind,
    required List<MailMailboxId> mailboxes,
    this.deletionMailbox,
    this.isDeleted,
  }) : mailboxes = _freeze(mailboxes) {
    if (!const {
      MailProviderKind.imap,
      MailProviderKind.gmail,
      MailProviderKind.graph,
      MailProviderKind.ews,
    }.contains(identity.provider)) {
      throw ArgumentError(
        'Membership observations require a supported provider.',
      );
    }
    final identityValue = switch (identity) {
      MailImapIdentity(:final mailbox) => mailbox.value,
      MailOpaqueIdentity(:final value) => value,
    };
    _checkIdentifier(identityValue);
    final account = identity.account;
    _checkIdentifier(account.value);
    _checkIdentifier(account.profile.value);
    _checkIdentifier(account.profile.hostId);
    var units =
        identityValue.length +
        account.value.length +
        account.profile.value.length +
        account.profile.hostId.length;
    final seen = <MailMailboxId>{};
    for (final mailbox in this.mailboxes) {
      _checkIdentifier(mailbox.value);
      if (mailbox.account != identity.account || !seen.add(mailbox)) {
        throw ArgumentError(
          'Observed mailboxes must be unique and account-owned.',
        );
      }
      units += mailbox.value.length;
    }
    if (deletionMailbox case final mailbox?) {
      _checkIdentifier(mailbox.value);
      if (mailbox.account != identity.account ||
          identity.provider == MailProviderKind.gmail &&
              mailbox.value != 'TRASH') {
        throw ArgumentError(
          'The deletion mailbox must match the provider account.',
        );
      }
      units += mailbox.value.length;
    }
    if (units > maxMetadataCodeUnits) {
      throw ArgumentError('Membership observation metadata exceeds its bound.');
    }
    if (kind == MailMembershipObservationKind.present &&
        (identity.provider == MailProviderKind.graph ||
            identity.provider == MailProviderKind.ews) &&
        this.mailboxes.length != 1) {
      throw ArgumentError('A folder provider must observe exactly one parent.');
    }
  }

  static const maxMailboxes = 1000;
  static const maxIdentifierCodeUnits = 2048;
  static const maxMetadataCodeUnits = 64 * 1024;

  static List<MailMailboxId> _freeze(List<MailMailboxId> mailboxes) {
    if (mailboxes.length > maxMailboxes) {
      throw ArgumentError('Too many observed mailboxes.');
    }
    return List.unmodifiable(mailboxes);
  }

  static void _checkIdentifier(String value) {
    if (value.isEmpty ||
        value.length > maxIdentifierCodeUnits ||
        value.contains(RegExp(r'[\x00-\x1f\x7f]')) ||
        !_hasWellFormedUtf16(value)) {
      throw ArgumentError('Observed identifiers must be bounded and nonempty.');
    }
  }

  // SQLite stores UTF-8: an encoder must never replace an unpaired surrogate
  // and silently change an exact account/message/folder identifier on reopen.
  static bool _hasWellFormedUtf16(String value) {
    for (var index = 0; index < value.length; index++) {
      final unit = value.codeUnitAt(index);
      if (unit >= 0xd800 && unit <= 0xdbff) {
        if (++index == value.length) return false;
        final low = value.codeUnitAt(index);
        if (low < 0xdc00 || low > 0xdfff) return false;
      } else if (unit >= 0xdc00 && unit <= 0xdfff) {
        return false;
      }
    }
    return true;
  }

  final MailRemoteIdentity identity;
  final MailMembershipObservationKind kind;
  final List<MailMailboxId> mailboxes;
  final MailMailboxId? deletionMailbox;

  /// IMAP's current Deleted marker or membership in [deletionMailbox]. Null
  /// means the provider did not establish current deletion/trash status.
  final bool? isDeleted;
}

/// Optional, explicit, read-only recovery. Implementations inspect the exact
/// original identity, without fetching a body, changing flags, moving mail,
/// submitting mail, expunging messages or replaying an earlier operation.
/// A caller must revalidate its lease and local revision before saving evidence.
abstract interface class MailMembershipObserver {
  MailAccountId get account;

  Future<MailResult<MailMembershipObservation>> observeMembership(
    MailRemoteIdentity identity, {
    required MailOperationLease lease,
  });
}
