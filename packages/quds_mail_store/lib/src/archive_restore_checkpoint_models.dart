/// Destination-scoped progress for one exact exported manifest. Counts describe
/// committed receipts; each receipt is revalidated before a message is skipped.
/// Source paths, credentials and message content are never stored in a job.
final class MailArchiveRestoreCheckpoint {
  const MailArchiveRestoreCheckpoint({
    required this.manifestSha256,
    required this.planned,
    required this.totalBytes,
    required this.completedMessages,
    required this.completedBytes,
  });

  final String manifestSha256;
  final int planned;
  final int totalBytes;
  final int completedMessages;
  final int completedBytes;
}

/// One committed manifest ordinal, verified against the destination original,
/// retained metadata/index and expected provenance before being returned.
final class MailArchiveRestoreReceipt {
  const MailArchiveRestoreReceipt({
    required this.ordinal,
    required this.byteLength,
    required this.indexWarning,
  });

  /// One-based position in the exported manifest.
  final int ordinal;
  final int byteLength;
  final bool indexWarning;
}
