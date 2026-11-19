void _checkId(String value) {
  if (value.isEmpty || value.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
    throw ArgumentError(
      'Identifiers must be nonempty and contain no controls.',
    );
  }
}

/// A local profile namespace belongs to exactly one host application.
final class MailProfileId {
  MailProfileId(this.value, {required this.hostId}) {
    _checkId(value);
    _checkId(hostId);
  }

  final String value;
  final String hostId;

  @override
  bool operator ==(Object other) =>
      other is MailProfileId && value == other.value && hostId == other.hostId;
  @override
  int get hashCode => Object.hash(value, hostId);
}

/// Account identity includes its owner; identical local IDs cannot cross hosts.
final class MailAccountId {
  MailAccountId(this.value, {required this.profile}) {
    _checkId(value);
  }

  final String value;
  final MailProfileId profile;

  @override
  bool operator ==(Object other) =>
      other is MailAccountId &&
      value == other.value &&
      profile == other.profile;
  @override
  int get hashCode => Object.hash(value, profile);
}

final class MailMessageId {
  MailMessageId(this.value) {
    _checkId(value);
  }
  final String value;

  @override
  bool operator ==(Object other) =>
      other is MailMessageId && value == other.value;
  @override
  int get hashCode => value.hashCode;
}

final class MailMailboxId {
  MailMailboxId(this.value, {required this.account}) {
    _checkId(value);
  }
  final String value;
  final MailAccountId account;

  @override
  bool operator ==(Object other) =>
      other is MailMailboxId &&
      value == other.value &&
      account == other.account;
  @override
  int get hashCode => Object.hash(value, account);
}

enum MailProviderKind { imap, graph, gmail, jmap, local, ews }

sealed class MailRemoteIdentity {
  const MailRemoteIdentity();
  MailAccountId get account;
  MailProviderKind get provider;
}

/// IMAP sequence numbers are deliberately absent: they are never stable IDs.
final class MailImapIdentity extends MailRemoteIdentity {
  MailImapIdentity({
    required this.mailbox,
    required this.uidValidity,
    required this.uid,
  }) {
    if (uidValidity < 1 ||
        uidValidity > 0xffffffff ||
        uid < 1 ||
        uid > 0xffffffff) {
      throw ArgumentError(
        'IMAP UID and UIDVALIDITY must be unsigned nonzero 32-bit values.',
      );
    }
  }

  final MailMailboxId mailbox;
  final int uidValidity;
  final int uid;

  @override
  MailAccountId get account => mailbox.account;
  @override
  MailProviderKind get provider => MailProviderKind.imap;
  @override
  bool operator ==(Object other) =>
      other is MailImapIdentity &&
      mailbox == other.mailbox &&
      uidValidity == other.uidValidity &&
      uid == other.uid;
  @override
  int get hashCode => Object.hash(mailbox, uidValidity, uid);
}

/// An opaque HTTPS-provider ID is namespaced by provider and local account.
final class MailOpaqueIdentity extends MailRemoteIdentity {
  MailOpaqueIdentity({
    required this.account,
    required this.provider,
    required this.value,
  }) {
    _checkId(value);
    if (provider == MailProviderKind.imap ||
        provider == MailProviderKind.local) {
      throw ArgumentError(
        'Use MailImapIdentity for IMAP; local messages have no remote identity.',
      );
    }
  }

  @override
  final MailAccountId account;
  @override
  final MailProviderKind provider;
  final String value;

  @override
  bool operator ==(Object other) =>
      other is MailOpaqueIdentity &&
      account == other.account &&
      provider == other.provider &&
      value == other.value;
  @override
  int get hashCode => Object.hash(account, provider, value);
}
