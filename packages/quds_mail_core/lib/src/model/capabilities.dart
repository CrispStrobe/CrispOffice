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
}

final class MailCapabilities {
  MailCapabilities(Iterable<MailCapability> supported)
    : supported = Set.unmodifiable(supported);
  const MailCapabilities.none() : supported = const {};
  final Set<MailCapability> supported;
  bool supports(MailCapability capability) => supported.contains(capability);
}
