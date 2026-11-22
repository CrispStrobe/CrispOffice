import 'identity.dart';

/// One account's explicitly chosen ordinary Archive destination.
///
/// This is a local routing preference, not evidence that a provider supports
/// moves or that the destination still exists. Hosts must resolve the exact
/// folder in a current account session before reviewing and dispatching a move.
/// Null restores the provider's default selection behavior. Resetting a saved
/// preference retains a positive revision so stale choices cannot recreate it.
final class MailArchiveDestinationSettings {
  const MailArchiveDestinationSettings({
    required this.account,
    this.revision = 0,
    this.destination,
  });

  static const maxIdCodeUnits = 1024;
  static const maxDestinationCodeUnits = 1024;
  static const maxMetadataCodeUnits = 4096;
  static const maxRevision = 9007199254740991;

  final MailAccountId account;

  /// Zero denotes unsaved defaults. Successful saves assign the next revision.
  final int revision;
  final MailMailboxId? destination;

  int get metadataCodeUnits =>
      account.value.length +
      account.profile.value.length +
      account.profile.hostId.length +
      (destination?.value.length ?? 0);

  bool get isValid =>
      _validArchiveIdentity(account.value, trim: true) &&
      _validArchiveIdentity(account.profile.value, trim: true) &&
      _validArchiveIdentity(account.profile.hostId, trim: true) &&
      revision >= 0 &&
      revision <= maxRevision &&
      (destination == null ||
          (destination!.account == account &&
              _validArchiveIdentity(destination!.value, trim: false))) &&
      metadataCodeUnits <= maxMetadataCodeUnits;

  /// Preserve the destination unless explicitly replaced or cleared.
  MailArchiveDestinationSettings copyWith({
    int? revision,
    MailMailboxId? destination,
    bool clearDestination = false,
  }) => MailArchiveDestinationSettings(
    account: account,
    revision: revision ?? this.revision,
    destination: clearDestination ? null : destination ?? this.destination,
  );

  @override
  String toString() => 'MailArchiveDestinationSettings(redacted)';
}

bool _validArchiveIdentity(String value, {required bool trim}) {
  if (value.isEmpty ||
      value.length > MailArchiveDestinationSettings.maxIdCodeUnits ||
      (trim && value != value.trim())) {
    return false;
  }
  // Mailbox whitespace and case are significant. Reject malformed UTF-16
  // before a UTF-8 encoder can silently substitute a different folder path.
  for (var index = 0; index < value.length; index++) {
    final unit = value.codeUnitAt(index);
    if (unit < 0x20 || (unit >= 0x7f && unit <= 0x9f)) return false;
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
