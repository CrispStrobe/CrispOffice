/// Mail, Calendar and People are independent provider capabilities.
enum MailCapability {
  mail,
  folders,
  labels,
  search,
  move,
  drafts,
  send,
  calendar,
  contacts,
  sharedAccounts,

  /// Provider-defined recoverable deletion, such as Trash or IMAP's Deleted
  /// flag. This does not authorize permanent purge or mailbox-wide expunge.
  delete,

  /// Provider-native Archive semantics. Gmail removes only the Inbox label;
  /// folder providers use an explicitly resolved or chosen [move] destination.
  archive,
}

final class MailCapabilities {
  MailCapabilities(Iterable<MailCapability> supported)
    : supported = Set.unmodifiable(supported);
  const MailCapabilities.none() : supported = const {};
  final Set<MailCapability> supported;
  bool supports(MailCapability capability) => supported.contains(capability);
}
