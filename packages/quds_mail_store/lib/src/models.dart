import 'dart:async';

import 'package:quds_mail_core/quds_mail_core.dart';

/// Work and logical-byte limits, independent of filesystem/browser quotas.
final class MailStoreLimits {
  const MailStoreLimits({
    this.maxBlobBytes = 32 * 1024 * 1024,
    this.maxTransactionBlobBytes = 64 * 1024 * 1024,
    this.maxMetadataCodeUnits = 2 * 1024 * 1024,
    this.maxAccountBytes = 256 * 1024 * 1024,
    this.maxMessagesPerAccount = 100000,
    this.maxIndexCodeUnits = 65536,
    this.maxQueryCodeUnits = 256,
    this.maxQueryTerms = 16,
    this.maxPageSize = 1000,
    this.maxSearchResults = 200,
  });

  final int maxBlobBytes;
  final int maxTransactionBlobBytes;
  final int maxMetadataCodeUnits;
  final int maxAccountBytes;
  final int maxMessagesPerAccount;
  final int maxIndexCodeUnits;
  final int maxQueryCodeUnits;
  final int maxQueryTerms;
  final int maxPageSize;
  final int maxSearchResults;

  bool get isValid =>
      maxBlobBytes > 0 &&
      maxTransactionBlobBytes >= maxBlobBytes &&
      maxMetadataCodeUnits > 0 &&
      maxAccountBytes > 0 &&
      maxMessagesPerAccount > 0 &&
      maxIndexCodeUnits > 0 &&
      maxQueryCodeUnits > 0 &&
      maxQueryTerms > 0 &&
      maxPageSize > 0 &&
      maxSearchResults > 0;
}

enum MailStoredAccountState { active, loggedOut, removed }

/// Non-secret route observed during a successful foreground connection.
/// This is a local access directory, not an authentication or reconnect record.
/// The host owns [id] and verifies it against its existing draft namespace.
final class MailLocalAccountRecord {
  const MailLocalAccountRecord({
    required this.id,
    required this.provider,
    required this.endpoint,
    required this.login,
    required this.sender,
    required this.lastConnectedAt,
    this.revision = 0,
  });

  final String id;
  final MailProviderKind provider;
  final String endpoint;
  final String login;
  final String sender;
  final DateTime lastConnectedAt;

  /// Monotonic connection revision, independent of wall-clock precision.
  final int revision;

  bool get isValid {
    bool text(String value, int limit) =>
        value.isNotEmpty &&
        value.length <= limit &&
        value == value.trim() &&
        !RegExp(r'[\x00-\x1f\x7f]').hasMatch(value);
    final uri = Uri.tryParse(endpoint);
    return text(id, 1024) &&
        text(endpoint, 4096) &&
        text(login, 4096) &&
        text(sender, 320) &&
        RegExp(r'^[^\s@]+@[^\s@]+$').hasMatch(sender) &&
        lastConnectedAt.millisecondsSinceEpoch >= 0 &&
        revision >= 0 &&
        revision <= 9007199254740991 &&
        uri != null &&
        uri.hasAuthority &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty &&
        !uri.hasQuery &&
        !uri.hasFragment &&
        uri.toString() == endpoint &&
        switch (provider) {
          MailProviderKind.imap =>
            (uri.scheme == 'imap' || uri.scheme == 'imaps') && uri.path.isEmpty,
          MailProviderKind.ews ||
          MailProviderKind.gmail ||
          MailProviderKind.graph => uri.scheme == 'https',
          _ => false,
        };
  }

  bool hasSameIdentity(MailLocalAccountRecord other) =>
      id == other.id &&
      provider == other.provider &&
      endpoint == other.endpoint &&
      login == other.login &&
      sender == other.sender;

  @override
  String toString() => 'MailLocalAccountRecord(redacted)';
}

/// Configuration contains an opaque vault reference, never a password/token.
final class MailStoreAccount {
  const MailStoreAccount({
    required this.id,
    required this.provider,
    required this.displayName,
    this.credentialReference,
    this.state = MailStoredAccountState.active,
  });

  final MailAccountId id;
  final MailProviderKind provider;
  final String displayName;
  final String? credentialReference;
  final MailStoredAccountState state;
}

/// A draft's metadata and revision without its body or attachment payloads.
/// Opening the draft separately verifies and loads its retained blob bytes.
final class MailDraftSummary {
  const MailDraftSummary({
    required this.id,
    required this.account,
    required this.revision,
    required this.envelope,
    required this.attachmentCount,
    this.editorState,
  });

  final String id;
  final MailAccountId account;
  final int revision;
  final MailEnvelope envelope;
  final int attachmentCount;
  final MailDraftEditorState? editorState;
}

/// A bounded, stable-ID-ordered metadata page. A continuation explicitly
/// exposes additional drafts instead of presenting a truncated catalog.
final class MailDraftPage {
  MailDraftPage({required List<MailDraftSummary> drafts, this.nextAfterId})
    : drafts = List.unmodifiable(drafts);

  final List<MailDraftSummary> drafts;
  final String? nextAfterId;
}

final class MailSearchHit {
  const MailSearchHit({
    required this.header,
    required this.preview,
    required this.rank,
  });
  final MailHeaderRecord header;
  final String preview;
  final double rank;
}

enum MailPendingState { queued, applying, applied, reconcile, cancelled }

/// Durable remote intent. Reconciliation never automatically retries a command.
final class MailPendingOperation {
  const MailPendingOperation({
    required this.operation,
    required this.revision,
    required this.state,
    required this.createdAt,
    required this.updatedAt,
  });
  final MailOperation operation;
  final int revision;
  final MailPendingState state;
  final DateTime createdAt;
  final DateTime updatedAt;
}

/// A local snapshot remains pinned until the owning editor explicitly releases it.
final class MailBlobPin {
  const MailBlobPin({
    required this.account,
    required this.id,
    required this.hash,
  });
  final MailAccountId account;
  final String id;
  final String hash;
}

/// Durable intent for a host-owned vault deletion, acknowledged after it succeeds.
final class MailCredentialCleanup {
  const MailCredentialCleanup({required this.account, required this.reference});
  final MailAccountId account;
  final String reference;
}

/// Fault injection is optional, content-free, and never used to emulate success.
enum MailStoreCheckpoint {
  migrationCreated,
  afterSyncRecords,
  beforeSyncCursor,
  afterDraftBlobs,
  afterOutboxWrite,
  beforeCommit,
}

typedef MailStoreFaultInjector =
    FutureOr<void> Function(MailStoreCheckpoint checkpoint);
