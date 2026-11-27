import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:enough_mail/enough_mail.dart' as mail;
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:quds_mail_transport/quds_mail_transport.dart';

/// Owns bounded message operations for one foreground Studio account session.
abstract interface class StudioMailMessageLoader {
  Future<Uint8List> fetch(
    mail.Mailbox selectedMailbox,
    mail.MimeMessage header,
  );

  /// Marks the exact UID read only after the server confirms its current flags.
  Future<void> markRead(mail.Mailbox selectedMailbox, mail.MimeMessage header);

  /// Cancels the current operation, leaving the session available for another.
  void cancel();

  /// Cancels operations and releases this session's in-memory credentials.
  void dispose();
}

/// Immutable page membership; the message projections retain the existing
/// Studio header type and carry no synthesized message body.
final class StudioMailHeaderPage {
  StudioMailHeaderPage({required List<mail.MimeMessage> messages, this.next})
    : messages = List.unmodifiable(messages);

  final List<mail.MimeMessage> messages;
  final MailCursor? next;
}

/// Optional bounded, newest-first foreground browsing. Continue only with the
/// last returned cursor; omit it to refresh the selected mailbox snapshot.
abstract interface class StudioMailMailboxBrowser {
  Future<StudioMailHeaderPage> fetchHeaders(
    mail.Mailbox selectedMailbox, {
    MailCursor? cursor,
    int limit = 50,
  });
}

/// Optional durable foreground synchronization. The caller supplies the owned
/// repository; no cursor or message is committed by a transient browse request.
abstract interface class StudioMailMailboxSynchronizer {
  MailAccountId get account;
  Future<MailSyncRunReport> synchronizeMailbox(
    mail.Mailbox selectedMailbox, {
    required MailSyncRepository repository,
    required MailCancellationToken cancellation,
    required void Function(MailSyncRunProgress) onProgress,
  });
}

/// Explicit body retention for headers saved by the same account's sync.
/// Reader-only and older host adapters need not expose this capability.
abstract interface class StudioMailBodyDownloader {
  Future<MailBodyDownloadReport> downloadMessages(
    mail.Mailbox selectedMailbox, {
    required List<MailHeaderRecord> headers,
    required MailBodyDownloadCache cache,
    required MailCancellationToken cancellation,
    required void Function(MailBodyDownloadProgress) onProgress,
    required bool Function() isCurrent,
  });
}

/// Immutable provider observations for durable cached views. This optional
/// port never derives an identity from a mutable high-level message after a
/// fetch. Older reader-only host adapters remain valid without local caching.
abstract interface class StudioMailMailboxRecords {
  MailAccountId get account;
  MailHeaderRecord observedHeader(
    mail.Mailbox selectedMailbox,
    mail.MimeMessage header,
  );
  Future<MailMessage> fetchMessage(
    mail.Mailbox selectedMailbox,
    mail.MimeMessage header,
  );
}

/// Optional confirmed flag actions, separate from existing reader fakes.
abstract interface class StudioMailMessageActions {
  Future<void> setRead(
    mail.Mailbox selectedMailbox,
    mail.MimeMessage header, {
    required bool read,
  });

  Future<void> setFlagged(
    mail.Mailbox selectedMailbox,
    mail.MimeMessage header, {
    required bool flagged,
  });
}

/// Foreground bulk commands retain the provider's mutation evidence. Older
/// reader/action adapters stay valid without claiming this optional capability.
abstract interface class StudioMailBulkMessageActions {
  MailAccountId get account;

  /// Only a header observed by this loader may supply a bulk remote identity.
  MailImapIdentity bulkIdentity(
    mail.Mailbox selectedMailbox,
    mail.MimeMessage header,
  );

  Future<MailResult<MailUnit>> applyBulkFlag(
    MailOperation command,
    MailOperationLease hostLease,
  );
}

/// Optional exact-identity organization commands. Reader-only and older flag
/// adapters do not acquire Move/Delete controls merely by implementing flags.
abstract interface class StudioMailMembershipActions {
  Future<MailCapabilities> membershipCapabilities();

  Future<MailResult<MailUnit>> applyMembership(
    MailOperation command,
    MailOperationLease hostLease,
  );
}

/// Optional authoritative move receipts. Existing organization adapters remain
/// compatible and never gain destination identity evidence from unit success.
abstract interface class StudioMailMembershipReceiptActions {
  Future<MailResult<MailMutationReceipt>> applyMembershipWithReceipt(
    MailOperation command,
    MailOperationLease hostLease,
  );
}

/// Optional folder archiving capability, separate from existing reader fakes.
/// Hosts supply a stable mailbox profile and own the archive's lifetime.
abstract interface class StudioMailMailboxArchiver {
  Future<MailArchiveRunReport> archiveMailbox(
    mail.Mailbox selectedMailbox, {
    required SqliteMailArchive archive,
    required MailArchiveProfile profile,
    MailCancellationToken? cancellation,
    void Function(MailArchiveRunProgress)? onProgress,
  });
}

/// An injection seam for deterministic tests; production uses the bounded IMAP
/// provider, including its TLS verification, literal quotas and MIME budgets.
typedef StudioMailProviderFactory =
    MailProvider Function({
      required MailImapConfiguration configuration,
      required MailCredentialStore credentialStore,
      required MailTransportLimits limits,
    });

/// Fixed explanations never include server replies, message data or secrets.
final class StudioMailMessageLoadException implements Exception {
  const StudioMailMessageLoadException(
    this.code, {
    this.mutationMayHaveOccurred,
  });

  final MailProblemCode code;

  /// Only false certifies no remote mutation. Missing evidence stays unknown.
  final bool? mutationMayHaveOccurred;

  String get message => switch (code) {
    MailProblemCode.unsupported =>
      'This account does not support secure IMAP message reading.',
    MailProblemCode.cancelled => 'Message loading was cancelled.',
    MailProblemCode.staleOperation =>
      'The mail session changed. Select the message again.',
    MailProblemCode.authenticationRequired =>
      'The mail account needs to be connected again.',
    MailProblemCode.permissionDenied =>
      'The server did not allow this message to be read.',
    MailProblemCode.unavailable => 'The message is no longer available.',
    MailProblemCode.quotaExceeded =>
      'The message exceeds the supported reading limits.',
    MailProblemCode.invalidInput =>
      'The account or message identity is incomplete or invalid.',
    MailProblemCode.conflict =>
      'The mailbox changed. Refresh its message list before opening this message.',
    MailProblemCode.providerFailure || MailProblemCode.storageFailure =>
      'The message could not be loaded. Try again.',
  };

  @override
  String toString() => message;
}

/// Native, password-authenticated IMAP reads with a fresh bounded connection.
///
/// Callers pair an envelope with the selected mailbox observed while fetching
/// its list. Foreground pages use the bounded provider's separate browse port.
/// Sequence numbers and the library's collision-prone GUID are never identities.
/// The selected path, UIDVALIDITY and UID are frozen before any asynchronous
/// operation, and the provider checks the server's current UIDVALIDITY before
/// reading the exact UID. Original octets are never rendered back into a string.
final class NativeStudioMailMessageLoader
    implements
        StudioMailMessageLoader,
        StudioMailMailboxBrowser,
        StudioMailMailboxSynchronizer,
        StudioMailBodyDownloader,
        StudioMailMailboxRecords,
        StudioMailMessageActions,
        StudioMailBulkMessageActions,
        StudioMailMembershipActions,
        StudioMailMembershipReceiptActions,
        MailArchiveDestinationResolver,
        MailFlagObserver,
        MailMembershipObserver,
        StudioMailMailboxArchiver {
  factory NativeStudioMailMessageLoader(
    mail.MailAccount account, {
    StudioMailProviderFactory? providerFactory,
    MailReadBudget budget = const MailReadBudget(),
    MailTransportLimits limits = const MailTransportLimits(),
    MailAccountId? persistentAccount,
  }) {
    final incoming = account.incoming;
    final server = incoming.serverConfig;
    final authentication = incoming.authentication;
    if (server.type != mail.ServerType.imap ||
        authentication is! mail.PlainAuthentication ||
        (server.socketType != mail.SocketType.ssl &&
            server.socketType != mail.SocketType.starttls)) {
      throw const StudioMailMessageLoadException(MailProblemCode.unsupported);
    }
    try {
      budget.validate();
      limits.validate();
      if (budget.maxRawBytes > 64 * 1024 * 1024 ||
          authentication.password.isEmpty ||
          authentication.password.length > limits.maxCredentialBytes ||
          authentication.password.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
        throw const StudioMailMessageLoadException(
          MailProblemCode.invalidInput,
        );
      }
      final secret = Uint8List.fromList(utf8.encode(authentication.password));
      if (secret.length > limits.maxCredentialBytes) {
        secret.fillRange(0, secret.length, 0);
        throw const StudioMailMessageLoadException(
          MailProblemCode.invalidInput,
        );
      }
      final id =
          persistentAccount ??
          MailAccountId(
            'imap-session-${++_nextSession}',
            profile: MailProfileId('mail-dialog', hostId: 'quds-office-studio'),
          );
      final reference = MailCredentialReference(
        account: id,
        key: 'session-password',
      );
      final configuration = MailImapConfiguration(
        account: id,
        endpoint: MailServerEndpoint(
          host: server.hostname,
          port: server.port,
          tls: server.socketType == mail.SocketType.ssl
              ? MailTlsMode.implicitTls
              : MailTlsMode.startTls,
        ),
        username: authentication.userName,
        credential: reference,
      );
      return NativeStudioMailMessageLoader._(
        configuration,
        _SessionCredentials(reference, secret),
        account.email,
        providerFactory ?? _createProvider,
        budget: budget,
        limits: limits,
      );
    } on ArgumentError {
      throw const StudioMailMessageLoadException(MailProblemCode.invalidInput);
    }
  }

  NativeStudioMailMessageLoader._(
    this._configuration,
    this._credentials,
    this._email,
    this._providerFactory, {
    required this.budget,
    required this.limits,
  }) : _session = MailAccountSession(_configuration.account);

  static int _nextSession = 0;
  static final _browsedIdentities = Expando<MailImapIdentity>();
  static final _browsedRecords = Expando<MailHeaderRecord>();

  @override
  MailAccountId get account => _configuration.account;

  @override
  Future<MailSyncRunReport> synchronizeMailbox(
    mail.Mailbox selectedMailbox, {
    required MailSyncRepository repository,
    required MailCancellationToken cancellation,
    required void Function(MailSyncRunProgress) onProgress,
  }) async {
    final (mailbox, _) = _selectedMailbox(selectedMailbox);
    if (_active != null) {
      throw const StudioMailMessageLoadException(MailProblemCode.unavailable);
    }
    final operation = _MessageOperation();
    _active = operation;
    try {
      final provider = _providerFactory(
        configuration: _configuration,
        credentialStore: _credentials,
        limits: limits,
      );
      return await const MailSyncRunner().run(
        provider: provider,
        repository: repository,
        session: _session,
        mailbox: mailbox,
        pageSize: limits.maxPageSize < 100 ? limits.maxPageSize : 100,
        cancellation: cancellation,
        onProgress: onProgress,
      );
    } finally {
      if (identical(_active, operation)) _active = null;
    }
  }

  @override
  Future<MailBodyDownloadReport> downloadMessages(
    mail.Mailbox selectedMailbox, {
    required List<MailHeaderRecord> headers,
    required MailBodyDownloadCache cache,
    required MailCancellationToken cancellation,
    required void Function(MailBodyDownloadProgress) onProgress,
    required bool Function() isCurrent,
  }) async {
    final (mailbox, _) = _selectedMailbox(selectedMailbox);
    if (_active != null) {
      throw const StudioMailMessageLoadException(MailProblemCode.unavailable);
    }
    final operation = _MessageOperation();
    _active = operation;
    try {
      final provider = _providerFactory(
        configuration: _configuration,
        credentialStore: _credentials,
        limits: limits,
      );
      return await MailBodyDownloadRunner(
        provider: provider,
        cache: cache,
        session: _session,
        budget: budget,
      ).run(
        mailbox: mailbox,
        headers: headers,
        cancellation: cancellation,
        onProgress: onProgress,
        isCurrent: () => identical(_active, operation) && isCurrent(),
      );
    } finally {
      if (identical(_active, operation)) _active = null;
    }
  }

  @override
  MailHeaderRecord observedHeader(
    mail.Mailbox selectedMailbox,
    mail.MimeMessage header,
  ) {
    final identity = _identity(selectedMailbox, header);
    final record = _browsedRecords[header];
    if (record == null || record.remote != identity) {
      throw const StudioMailMessageLoadException(MailProblemCode.conflict);
    }
    return record;
  }

  Future<MailResult<MailMessage>> fetchForBodyCache(
    MailRemoteIdentity identity,
    MailReadBudget budget,
    MailOperationLease lease,
  ) => _providerFactory(
    configuration: _configuration,
    credentialStore: _credentials,
    limits: limits,
  ).fetchMessage(identity, budget: budget, lease: lease);

  static MailProvider _createProvider({
    required MailImapConfiguration configuration,
    required MailCredentialStore credentialStore,
    required MailTransportLimits limits,
  }) => createMailImapProvider(
    configuration: configuration,
    credentialStore: credentialStore,
    limits: limits,
  );

  final MailImapConfiguration _configuration;
  final _SessionCredentials _credentials;
  final String _email;
  final StudioMailProviderFactory _providerFactory;
  final MailAccountSession _session;
  final MailReadBudget budget;
  final MailTransportLimits limits;
  _MessageOperation? _active;
  int _nextOperation = 0;
  _MailboxBrowseContinuation? _browse;

  (MailMailboxId, int) _selectedMailbox(mail.Mailbox selectedMailbox) {
    if (_session.isDisposed) {
      throw const StudioMailMessageLoadException(
        MailProblemCode.staleOperation,
        mutationMayHaveOccurred: false,
      );
    }
    try {
      final path = selectedMailbox.path;
      final validity = selectedMailbox.uidValidity;
      if (selectedMailbox.isNotSelectable ||
          path.trim().isEmpty ||
          path.length > 1024 ||
          validity == null ||
          validity < 1 ||
          validity > 0xffffffff) {
        throw const StudioMailMessageLoadException(
          MailProblemCode.invalidInput,
          mutationMayHaveOccurred: false,
        );
      }
      return (MailMailboxId(path, account: _configuration.account), validity);
    } on ArgumentError {
      throw const StudioMailMessageLoadException(
        MailProblemCode.invalidInput,
        mutationMayHaveOccurred: false,
      );
    }
  }

  MailImapIdentity _identity(
    mail.Mailbox selectedMailbox,
    mail.MimeMessage header,
  ) {
    final (mailbox, uidValidity) = _selectedMailbox(selectedMailbox);
    final MailImapIdentity identity;
    try {
      final uid = header.uid;
      if (uid == null) {
        throw const StudioMailMessageLoadException(
          MailProblemCode.invalidInput,
          mutationMayHaveOccurred: false,
        );
      }
      identity = MailImapIdentity(
        mailbox: mailbox,
        uidValidity: uidValidity,
        uid: uid,
      );
      final bound = _browsedIdentities[header];
      if (bound != null && bound != identity) {
        throw const StudioMailMessageLoadException(
          MailProblemCode.conflict,
          mutationMayHaveOccurred: false,
        );
      }
      // This optional high-level-client hint can reject an obvious stale list;
      // its XOR collisions mean it is never used instead of the full identity.
      if (header.guid != null &&
          header.guid !=
              mail.MimeMessage.calculateGuid(
                email: _email,
                encodedMailboxName: selectedMailbox.encodedName,
                mailboxUidValidity: uidValidity,
                messageUid: uid,
              )) {
        throw const StudioMailMessageLoadException(
          MailProblemCode.conflict,
          mutationMayHaveOccurred: false,
        );
      }
    } on ArgumentError {
      throw const StudioMailMessageLoadException(
        MailProblemCode.invalidInput,
        mutationMayHaveOccurred: false,
      );
    }
    return identity;
  }

  /// A separate browse chain for an approved local MCP grant. Its cursors and
  /// headers never replace the foreground view's browse state.
  Future<MailHeaderPage> browseMcpFolder(
    mail.Mailbox selectedMailbox, {
    required String? after,
    required int limit,
  }) async {
    final (mailbox, validity) = _selectedMailbox(selectedMailbox);
    if (_active != null) {
      throw const StudioMailMessageLoadException(MailProblemCode.unavailable);
    }
    if (limit < 1 || limit > limits.maxPageSize) {
      throw const StudioMailMessageLoadException(MailProblemCode.invalidInput);
    }
    final page = await _run((provider, lease) {
      if (provider is! MailImapHeaderBrowser) {
        return Future<MailResult<MailHeaderPage>>.value(
          const MailFailure(MailProblem(MailProblemCode.unsupported)),
        );
      }
      return (provider as MailImapHeaderBrowser).fetchNewestHeaders(
        mailbox,
        uidValidity: validity,
        cursor: after == null
            ? null
            : MailCursor(mailbox: mailbox, value: after),
        limit: limit,
        lease: lease,
      );
    });
    if (page.messages.length > limit ||
        page.messages.any((record) {
          final identity = record.remote;
          return identity is! MailImapIdentity ||
              identity.mailbox != mailbox ||
              identity.uidValidity != validity;
        }) ||
        (page.next != null && page.next!.mailbox != mailbox)) {
      throw const StudioMailMessageLoadException(MailProblemCode.conflict);
    }
    return page;
  }

  Future<MailMessage> fetchMcpMessage(
    mail.Mailbox selectedMailbox,
    MailImapIdentity identity,
  ) async {
    final (mailbox, validity) = _selectedMailbox(selectedMailbox);
    if (_active != null ||
        identity.mailbox != mailbox ||
        identity.uidValidity != validity) {
      throw const StudioMailMessageLoadException(MailProblemCode.conflict);
    }
    const readBudget = MailReadBudget(maxRawBytes: 2 * 1024 * 1024);
    final message = await _run(
      (provider, lease) =>
          provider.fetchMessage(identity, budget: readBudget, lease: lease),
    );
    if (message.remoteIdentity != identity ||
        message.raw.length > readBudget.maxRawBytes) {
      throw const StudioMailMessageLoadException(MailProblemCode.conflict);
    }
    return message;
  }

  @override
  Future<StudioMailHeaderPage> fetchHeaders(
    mail.Mailbox selectedMailbox, {
    MailCursor? cursor,
    int limit = 50,
  }) async {
    final (mailbox, validity) = _selectedMailbox(selectedMailbox);
    final encodedName = selectedMailbox.encodedName;
    final previous = _browse;
    if (limit < 1 ||
        limit > limits.maxPageSize ||
        (cursor != null &&
            (cursor.mailbox != mailbox ||
                previous == null ||
                previous.mailbox != mailbox ||
                previous.uidValidity != validity ||
                previous.nextValue != cursor.value))) {
      throw const StudioMailMessageLoadException(MailProblemCode.invalidInput);
    }
    final page = await _run((provider, lease) {
      if (provider is! MailImapHeaderBrowser) {
        return Future<MailResult<MailHeaderPage>>.value(
          const MailFailure(MailProblem(MailProblemCode.unsupported)),
        );
      }
      return (provider as MailImapHeaderBrowser).fetchNewestHeaders(
        mailbox,
        uidValidity: validity,
        cursor: cursor,
        limit: limit,
        lease: lease,
      );
    });
    if (page.messages.length > limit) {
      throw const StudioMailMessageLoadException(
        MailProblemCode.providerFailure,
      );
    }
    var lastUid = cursor == null ? 0x100000000 : previous!.lastUid;
    final ids = <MailMessageId>{};
    for (final record in page.messages) {
      final identity = record.remote;
      if (identity is! MailImapIdentity || identity.mailbox != mailbox) {
        throw const StudioMailMessageLoadException(
          MailProblemCode.providerFailure,
        );
      }
      if (identity.uidValidity != validity) {
        throw const StudioMailMessageLoadException(MailProblemCode.conflict);
      }
      if (identity.uid >= lastUid || !ids.add(record.id)) {
        throw const StudioMailMessageLoadException(
          MailProblemCode.providerFailure,
        );
      }
      lastUid = identity.uid;
    }
    final values = cursor == null ? <String>{} : {...previous!.cursorValues};
    final next = page.next;
    if (next != null &&
        (next.mailbox != mailbox ||
            next.value.isEmpty ||
            next.value.length > 256 ||
            !values.add(next.value))) {
      throw const StudioMailMessageLoadException(
        MailProblemCode.providerFailure,
      );
    }
    // Retain at most the host's bounded foreground browse chain. A refresh
    // starts a new chain, and a failed/cancelled page never consumes its cursor.
    if (values.length > 10000) {
      throw const StudioMailMessageLoadException(MailProblemCode.quotaExceeded);
    }
    final messages = <mail.MimeMessage>[];
    for (final record in page.messages) {
      final identity = record.remote as MailImapIdentity;
      final envelope = record.envelope;
      final flags = record.flags;
      final header = mail.MimeMessage.fromEnvelope(
        mail.Envelope(
          date: envelope.sentAt,
          subject: envelope.subject,
          from: _displayAddresses(envelope.from),
          to: _displayAddresses(envelope.to),
          cc: _displayAddresses(envelope.cc),
          bcc: _displayAddresses(envelope.bcc),
          replyTo: _displayAddresses(envelope.replyTo),
          inReplyTo: envelope.inReplyTo,
          messageId: envelope.messageId,
        ),
        uid: identity.uid,
        flags: flags == null
            ? null
            : [
                if (flags.isRead) mail.MessageFlags.seen,
                if (flags.isFlagged) mail.MessageFlags.flagged,
                if (flags.isAnswered) mail.MessageFlags.answered,
                if (flags.isDraft) mail.MessageFlags.draft,
                if (flags.isDeleted) mail.MessageFlags.deleted,
              ],
      );
      if (envelope.references.isNotEmpty) {
        header.addHeader('References', envelope.references.join(' '));
      }
      header.setGuid(
        email: _email,
        encodedMailboxName: encodedName,
        mailboxUidValidity: validity,
      );
      _browsedIdentities[header] = identity;
      _browsedRecords[header] = record;
      messages.add(header);
    }
    _browse = next == null
        ? null
        : _MailboxBrowseContinuation(
            mailbox: mailbox,
            uidValidity: validity,
            nextValue: next.value,
            lastUid: lastUid,
            cursorValues: values,
          );
    return StudioMailHeaderPage(messages: messages, next: next);
  }

  @override
  Future<Uint8List> fetch(
    mail.Mailbox selectedMailbox,
    mail.MimeMessage header,
  ) async => (await fetchMessage(selectedMailbox, header)).raw.copyBytes();

  @override
  Future<MailMessage> fetchMessage(
    mail.Mailbox selectedMailbox,
    mail.MimeMessage header, {
    MailReadBudget? readBudget,
  }) async {
    final effectiveBudget = readBudget ?? budget;
    final identity = _identity(selectedMailbox, header);
    final message = await _run(
      (provider, lease) => provider.fetchMessage(
        identity,
        budget: effectiveBudget,
        lease: lease,
      ),
    );
    final record = _browsedRecords[header];
    if (message.remoteIdentity != identity ||
        record != null &&
            message.localId != null &&
            message.localId != record.id) {
      throw const StudioMailMessageLoadException(MailProblemCode.conflict);
    }
    if (message.raw.length > effectiveBudget.maxRawBytes) {
      throw const StudioMailMessageLoadException(MailProblemCode.quotaExceeded);
    }
    return message;
  }

  @override
  Future<void> markRead(
    mail.Mailbox selectedMailbox,
    mail.MimeMessage header,
  ) => setRead(selectedMailbox, header, read: true);

  @override
  Future<void> setRead(
    mail.Mailbox selectedMailbox,
    mail.MimeMessage header, {
    required bool read,
  }) async {
    final identity = _identity(selectedMailbox, header);
    // The provider opens a bounded connection, compares UIDVALIDITY, verifies
    // this UID exists, performs UID STORE, then reads back the flag. It never
    // replays a write after reconnecting or falls back to a sequence number.
    await _run(
      (provider, lease) => provider.apply(
        MailSetRead(
          id: 'set-read-${++_nextOperation}',
          message: identity,
          read: read,
        ),
        lease,
      ),
    );
  }

  @override
  Future<void> setFlagged(
    mail.Mailbox selectedMailbox,
    mail.MimeMessage header, {
    required bool flagged,
  }) async {
    final identity = _identity(selectedMailbox, header);
    await _run(
      (provider, lease) => provider.apply(
        MailSetFlagged(
          id: 'set-flagged-${++_nextOperation}',
          message: identity,
          flagged: flagged,
        ),
        lease,
      ),
    );
  }

  @override
  MailImapIdentity bulkIdentity(
    mail.Mailbox selectedMailbox,
    mail.MimeMessage header,
  ) => observedHeader(selectedMailbox, header).remote as MailImapIdentity;

  @override
  Future<MailResult<MailUnit>> applyBulkFlag(
    MailOperation command,
    MailOperationLease hostLease,
  ) async {
    if (command is! MailSetRead && command is! MailSetFlagged) {
      return const MailFailure(
        MailProblem(
          MailProblemCode.invalidInput,
          mutationMayHaveOccurred: false,
        ),
      );
    }
    return _applyCommand(command, hostLease);
  }

  @override
  Future<MailCapabilities> membershipCapabilities() async {
    if (_session.isDisposed) {
      throw const StudioMailMessageLoadException(
        MailProblemCode.staleOperation,
        mutationMayHaveOccurred: false,
      );
    }
    if (_active != null) {
      throw const StudioMailMessageLoadException(
        MailProblemCode.unavailable,
        mutationMayHaveOccurred: false,
      );
    }
    return _run((provider, lease) => provider.capabilities(lease));
  }

  @override
  Future<MailResult<MailMailbox>> resolveArchiveDestination(
    MailOperationLease lease,
  ) async {
    if (lease.account != account) {
      return const MailFailure(MailProblem(MailProblemCode.invalidInput));
    }
    if (_active != null) {
      return const MailFailure(MailProblem(MailProblemCode.unavailable));
    }
    final operation = _MessageOperation();
    _active = operation;
    try {
      lease.checkCurrent();
      final localLease = _session.begin(cancellation: lease.cancellation);
      final provider = _providerFactory(
        configuration: _configuration,
        credentialStore: _credentials,
        limits: limits,
      );
      if (provider.account != account) {
        return const MailFailure(MailProblem(MailProblemCode.invalidInput));
      }
      if (provider is! MailArchiveDestinationResolver) {
        return const MailFailure(MailProblem(MailProblemCode.unsupported));
      }
      localLease.checkCurrent();
      lease.checkCurrent();
      final result = await Future.any<MailResult<MailMailbox>>([
        (provider as MailArchiveDestinationResolver).resolveArchiveDestination(
          localLease,
        ),
        operation.cancelled.future.then(
          (code) => MailFailure(MailProblem(code)),
        ),
      ]);
      localLease.checkCurrent();
      lease.checkCurrent();
      if (result case MailSuccess<MailMailbox>(:final value)) {
        if (value.id.account != account || value.isLabel) {
          return const MailFailure(MailProblem(MailProblemCode.invalidInput));
        }
      }
      return result;
    } on MailCancelled catch (error) {
      return MailFailure(
        MailProblem(
          error.reason == MailCancellationReason.user ||
                  error.reason == MailCancellationReason.budgetExpired
              ? MailProblemCode.cancelled
              : MailProblemCode.staleOperation,
        ),
      );
    } on Object {
      return const MailFailure(MailProblem(MailProblemCode.providerFailure));
    } finally {
      if (identical(_active, operation)) _active = null;
    }
  }

  @override
  Future<MailResult<MailUnit>> applyMembership(
    MailOperation command,
    MailOperationLease hostLease,
  ) async {
    if (!_validMembershipCommand(command)) {
      return const MailFailure(
        MailProblem(
          MailProblemCode.invalidInput,
          mutationMayHaveOccurred: false,
        ),
      );
    }
    return _applyCommand(command, hostLease);
  }

  bool _validMembershipCommand(MailOperation command) =>
      (command is MailMove || command is MailDelete) &&
      (command is! MailMove ||
          command.destination.account == account &&
              (command.message is! MailImapIdentity ||
                  (command.message as MailImapIdentity).mailbox !=
                      command.destination));

  @override
  Future<MailResult<MailMutationReceipt>> applyMembershipWithReceipt(
    MailOperation command,
    MailOperationLease hostLease,
  ) async {
    if (!_validMembershipCommand(command)) {
      return const MailFailure(
        MailProblem(
          MailProblemCode.invalidInput,
          mutationMayHaveOccurred: false,
        ),
      );
    }
    return _applyCommandResult(command, hostLease, (provider, lease) async {
      if (provider is MailMutationReceiptProvider) {
        return (provider as MailMutationReceiptProvider).applyWithReceipt(
          command,
          lease,
        );
      }
      return switch (await provider.apply(command, lease)) {
        MailSuccess<MailUnit>() => const MailSuccess(MailMutationReceipt()),
        MailFailure<MailUnit>(:final problem) => MailFailure(problem),
      };
    });
  }

  Future<MailResult<MailUnit>> _applyCommand(
    MailOperation command,
    MailOperationLease hostLease,
  ) => _applyCommandResult(
    command,
    hostLease,
    (provider, lease) => provider.apply(command, lease),
  );

  Future<MailResult<T>> _applyCommandResult<T>(
    MailOperation command,
    MailOperationLease hostLease,
    Future<MailResult<T>> Function(MailProvider, MailOperationLease) apply,
  ) async {
    MailFailure<T> failure(MailProblemCode code, bool dispatched) =>
        MailFailure(MailProblem(code, mutationMayHaveOccurred: dispatched));
    if (command.message is! MailImapIdentity ||
        command.message.account != account ||
        hostLease.account != account) {
      return failure(MailProblemCode.invalidInput, false);
    }
    if (_active != null) return failure(MailProblemCode.unavailable, false);
    final operation = _MessageOperation();
    var dispatched = false;
    try {
      hostLease.checkCurrent();
      final lease = _session.begin(cancellation: operation.cancellation.token);
      _active = operation;
      final provider = _providerFactory(
        configuration: _configuration,
        credentialStore: _credentials,
        limits: limits,
      );
      if (provider.account != account) {
        return failure(MailProblemCode.invalidInput, false);
      }
      hostLease.checkCurrent();
      lease.checkCurrent();
      dispatched = true;
      // Do not race cancellation against a provider acknowledgment or erase its
      // explicit pre-mutation evidence. The bounded provider owns completion;
      // the runner and host separately reject stale UI projection.
      return await apply(provider, lease);
    } on MailCancelled catch (error) {
      return failure(
        error.reason == MailCancellationReason.user ||
                error.reason == MailCancellationReason.budgetExpired
            ? MailProblemCode.cancelled
            : MailProblemCode.staleOperation,
        dispatched,
      );
    } on Object {
      return failure(MailProblemCode.providerFailure, dispatched);
    } finally {
      if (identical(_active, operation)) _active = null;
    }
  }

  /// Reads an exact historical UID without requiring it to remain in the
  /// currently loaded page. The provider verifies its original UIDVALIDITY.
  @override
  Future<MailResult<MailFlagObservation>> observeFlags(
    MailRemoteIdentity identity, {
    required MailOperationLease lease,
  }) async {
    if (identity is! MailImapIdentity ||
        identity.account != account ||
        lease.account != account) {
      return const MailFailure(MailProblem(MailProblemCode.invalidInput));
    }
    if (_active != null) {
      return const MailFailure(MailProblem(MailProblemCode.unavailable));
    }
    final operation = _MessageOperation();
    _active = operation;
    try {
      lease.checkCurrent();
      final localLease = _session.begin(cancellation: lease.cancellation);
      final provider = _providerFactory(
        configuration: _configuration,
        credentialStore: _credentials,
        limits: limits,
      );
      if (provider.account != account) {
        return const MailFailure(MailProblem(MailProblemCode.invalidInput));
      }
      if (provider is! MailFlagObserver) {
        return const MailFailure(MailProblem(MailProblemCode.unsupported));
      }
      localLease.checkCurrent();
      lease.checkCurrent();
      final result = await Future.any<MailResult<MailFlagObservation>>([
        (provider as MailFlagObserver).observeFlags(
          identity,
          lease: localLease,
        ),
        operation.cancelled.future.then(
          (code) => MailFailure(MailProblem(code)),
        ),
      ]);
      localLease.checkCurrent();
      lease.checkCurrent();
      return result;
    } on MailCancelled catch (error) {
      return MailFailure(
        MailProblem(
          error.reason == MailCancellationReason.user ||
                  error.reason == MailCancellationReason.budgetExpired
              ? MailProblemCode.cancelled
              : MailProblemCode.staleOperation,
        ),
      );
    } on Object {
      return const MailFailure(MailProblem(MailProblemCode.providerFailure));
    } finally {
      if (identical(_active, operation)) _active = null;
    }
  }

  /// Reads an exact historical UID without requiring it to remain in the
  /// currently loaded page. This never retries a Move/Delete command.
  @override
  Future<MailResult<MailMembershipObservation>> observeMembership(
    MailRemoteIdentity identity, {
    required MailOperationLease lease,
  }) async {
    if (identity is! MailImapIdentity ||
        identity.account != account ||
        lease.account != account) {
      return const MailFailure(MailProblem(MailProblemCode.invalidInput));
    }
    if (_active != null) {
      return const MailFailure(MailProblem(MailProblemCode.unavailable));
    }
    final operation = _MessageOperation();
    _active = operation;
    try {
      lease.checkCurrent();
      final localLease = _session.begin(cancellation: lease.cancellation);
      final provider = _providerFactory(
        configuration: _configuration,
        credentialStore: _credentials,
        limits: limits,
      );
      if (provider.account != account) {
        return const MailFailure(MailProblem(MailProblemCode.invalidInput));
      }
      if (provider is! MailMembershipObserver) {
        return const MailFailure(MailProblem(MailProblemCode.unsupported));
      }
      localLease.checkCurrent();
      lease.checkCurrent();
      final result = await Future.any<MailResult<MailMembershipObservation>>([
        (provider as MailMembershipObserver).observeMembership(
          identity,
          lease: localLease,
        ),
        operation.cancelled.future.then(
          (code) => MailFailure(MailProblem(code)),
        ),
      ]);
      localLease.checkCurrent();
      lease.checkCurrent();
      return result;
    } on MailCancelled catch (error) {
      return MailFailure(
        MailProblem(
          error.reason == MailCancellationReason.user ||
                  error.reason == MailCancellationReason.budgetExpired
              ? MailProblemCode.cancelled
              : MailProblemCode.staleOperation,
        ),
      );
    } on Object {
      return const MailFailure(MailProblem(MailProblemCode.providerFailure));
    } finally {
      if (identical(_active, operation)) _active = null;
    }
  }

  @override
  Future<MailArchiveRunReport> archiveMailbox(
    mail.Mailbox selectedMailbox, {
    required SqliteMailArchive archive,
    required MailArchiveProfile profile,
    MailCancellationToken? cancellation,
    void Function(MailArchiveRunProgress)? onProgress,
  }) async {
    final watch = Stopwatch()..start();
    _MessageOperation? operation;
    Timer? externalCancellation;
    try {
      final (mailbox, validity) = _selectedMailbox(selectedMailbox);
      cancellation?.throwIfCancelled();
      cancel();
      final active = _MessageOperation();
      operation = active;
      _active = active;
      final provider = _providerFactory(
        configuration: _configuration,
        credentialStore: _credentials,
        limits: limits,
      );
      if (provider.account != _configuration.account) {
        throw const StudioMailMessageLoadException(
          MailProblemCode.invalidInput,
        );
      }
      final source = _SelectedArchiveProvider(
        provider,
        mailbox,
        validity,
        active,
        cancellation,
      );
      if (cancellation != null) {
        externalCancellation = Timer.periodic(
          limits.cancellationPollInterval,
          (_) => source.checkCancellation(),
        );
      }
      source.checkCancellation();
      return await MailArchiveRunner(
        archive: archive,
        provider: source,
        session: _session,
      ).archiveMailbox(
        MailMailbox(id: mailbox, displayName: mailbox.value),
        profile: profile,
        pageSize: limits.maxPageSize < 100 ? limits.maxPageSize : 100,
        budget: budget,
        cancellation: active.cancellation.token,
        onProgress: (progress) {
          source.checkCancellation();
          try {
            if (identical(_active, active) && !_session.isDisposed) {
              onProgress?.call(progress);
            }
          } finally {
            source.checkCancellation();
          }
        },
      );
    } on StudioMailMessageLoadException catch (error) {
      return _archiveFailure(error.code, watch.elapsedMicroseconds);
    } on MailCancelled catch (error) {
      return _archiveFailure(
        _archiveCancellationCode(error.reason),
        watch.elapsedMicroseconds,
      );
    } on Object {
      return _archiveFailure(
        MailProblemCode.providerFailure,
        watch.elapsedMicroseconds,
      );
    } finally {
      externalCancellation?.cancel();
      if (operation != null && identical(_active, operation)) _active = null;
    }
  }

  Future<T> _run<T>(
    Future<MailResult<T>> Function(MailProvider, MailOperationLease) action,
  ) async {
    cancel();
    final operation = _MessageOperation();
    _active = operation;
    final lease = _session.begin(cancellation: operation.cancellation.token);
    var actionInvoked = false;
    try {
      final provider = _providerFactory(
        configuration: _configuration,
        credentialStore: _credentials,
        limits: limits,
      );
      if (provider.account != _configuration.account) {
        throw const StudioMailMessageLoadException(
          MailProblemCode.invalidInput,
          mutationMayHaveOccurred: false,
        );
      }
      lease.checkCurrent();
      actionInvoked = true;
      final result = await Future.any<MailResult<T>>([
        action(provider, lease),
        operation.cancelled.future.then(
          (code) => MailFailure(MailProblem(code)),
        ),
      ]);
      lease.checkCurrent();
      if (result case MailFailure<T>(:final problem)) {
        throw StudioMailMessageLoadException(
          problem.code,
          mutationMayHaveOccurred: problem.mutationMayHaveOccurred,
        );
      }
      return (result as MailSuccess<T>).value;
    } on StudioMailMessageLoadException {
      rethrow;
    } on MailCancelled catch (error) {
      throw StudioMailMessageLoadException(
        error.reason == MailCancellationReason.user
            ? MailProblemCode.cancelled
            : MailProblemCode.staleOperation,
        mutationMayHaveOccurred: actionInvoked ? null : false,
      );
    } on Object {
      throw StudioMailMessageLoadException(
        MailProblemCode.providerFailure,
        mutationMayHaveOccurred: actionInvoked ? null : false,
      );
    } finally {
      if (identical(_active, operation)) _active = null;
    }
  }

  @override
  void cancel() {
    _session.invalidate();
    _active?.cancel(MailProblemCode.cancelled);
    _active = null;
  }

  @override
  void dispose() {
    if (_session.isDisposed) return;
    _session.dispose();
    _active?.cancel(MailProblemCode.staleOperation);
    _active = null;
    _credentials.dispose();
    _browse = null;
  }
}

List<mail.MailAddress> _displayAddresses(List<MailAddress> addresses) => [
  for (final address in addresses)
    mail.MailAddress(address.displayName, address.address),
];

final class _MailboxBrowseContinuation {
  _MailboxBrowseContinuation({
    required this.mailbox,
    required this.uidValidity,
    required this.nextValue,
    required this.lastUid,
    required Set<String> cursorValues,
  }) : cursorValues = Set.unmodifiable(cursorValues);

  final MailMailboxId mailbox;
  final int uidValidity;
  final String nextValue;
  final int lastUid;
  final Set<String> cursorValues;
}

MailProblemCode _archiveCancellationCode(MailCancellationReason? reason) =>
    reason == MailCancellationReason.user ||
        reason == MailCancellationReason.budgetExpired
    ? MailProblemCode.cancelled
    : MailProblemCode.staleOperation;

MailArchiveRunReport _archiveFailure(MailProblemCode code, int elapsed) =>
    MailArchiveRunReport(
      status:
          code == MailProblemCode.cancelled ||
              code == MailProblemCode.staleOperation
          ? MailArchiveRunStatus.cancelled
          : MailArchiveRunStatus.failed,
      pages: 0,
      processed: 0,
      saved: 0,
      duplicates: 0,
      failed: 0,
      bytes: 0,
      elapsedMicroseconds: elapsed,
      observerErrors: 0,
      failures: const [],
      droppedFailures: 0,
      problem: MailProblem(code),
    );

/// Frozen mailbox generation and cancellation boundary for archive reads.
/// A cancelled network future remains observed; it cannot reach archive writes.
/// Storage is awaited by the runner so its confirmed committed counts stay true.
final class _SelectedArchiveProvider implements MailProvider {
  _SelectedArchiveProvider(
    this.delegate,
    this.mailbox,
    this.uidValidity,
    this.operation,
    this.externalCancellation,
  );

  final MailProvider delegate;
  final MailMailboxId mailbox;
  final int uidValidity;
  final _MessageOperation operation;
  final MailCancellationToken? externalCancellation;

  @override
  MailAccountId get account => mailbox.account;

  void checkCancellation() {
    if (externalCancellation?.isCancelled ?? false) {
      operation.cancel(_archiveCancellationCode(externalCancellation!.reason));
    }
  }

  Future<MailResult<T>> _read<T>(
    Future<MailResult<T>> Function() action,
    MailOperationLease lease,
  ) async {
    checkCancellation();
    lease.checkCurrent();
    final result = await Future.any<MailResult<T>>([
      Future<MailResult<T>>.sync(action),
      operation.cancelled.future.then(
        (code) => MailFailure<T>(MailProblem(code)),
      ),
    ]);
    checkCancellation();
    lease.checkCurrent();
    return result;
  }

  @override
  Future<MailResult<MailHeaderPage>> fetchHeaders(
    MailMailboxId requested, {
    MailCursor? cursor,
    required int limit,
    required MailOperationLease lease,
  }) async {
    if (requested != mailbox || lease.account != account) {
      return const MailFailure(MailProblem(MailProblemCode.invalidInput));
    }
    final result = await _read(
      () => delegate.fetchHeaders(
        mailbox,
        cursor: cursor,
        limit: limit,
        lease: lease,
      ),
      lease,
    );
    if (result case MailSuccess<MailHeaderPage>(:final value)) {
      if (value.messages.length > limit) {
        return const MailFailure(MailProblem(MailProblemCode.providerFailure));
      }
      for (final header in value.messages) {
        final remote = header.remote;
        if (remote is! MailImapIdentity || remote.mailbox != mailbox) {
          return const MailFailure(
            MailProblem(MailProblemCode.providerFailure),
          );
        }
        if (remote.uidValidity != uidValidity) {
          return const MailFailure(MailProblem(MailProblemCode.conflict));
        }
      }
    }
    return result;
  }

  @override
  Future<MailResult<MailMessage>> fetchMessage(
    MailRemoteIdentity identity, {
    required MailReadBudget budget,
    required MailOperationLease lease,
  }) {
    if (identity is! MailImapIdentity ||
        identity.mailbox != mailbox ||
        identity.uidValidity != uidValidity ||
        lease.account != account) {
      return Future.value(
        const MailFailure(MailProblem(MailProblemCode.invalidInput)),
      );
    }
    return _read(
      () => delegate.fetchMessage(identity, budget: budget, lease: lease),
      lease,
    );
  }

  @override
  Future<MailResult<MailCapabilities>> capabilities(
    MailOperationLease lease,
  ) async => const MailFailure(MailProblem(MailProblemCode.unsupported));

  @override
  Future<MailResult<List<MailMailbox>>> listMailboxes(
    MailOperationLease lease,
  ) async => const MailFailure(MailProblem(MailProblemCode.unsupported));

  @override
  Future<MailResult<MailSyncPage>> pullChanges(
    MailMailboxId mailbox, {
    MailCursor? cursor,
    required int limit,
    required MailOperationLease lease,
  }) async => const MailFailure(MailProblem(MailProblemCode.unsupported));

  @override
  Future<MailResult<MailUnit>> apply(
    MailOperation operation,
    MailOperationLease lease,
  ) async => const MailFailure(MailProblem(MailProblemCode.unsupported));
}

final class _MessageOperation {
  final cancellation = MailCancellationSource();
  final cancelled = Completer<MailProblemCode>();

  void cancel(MailProblemCode code) {
    cancellation.cancel(
      code == MailProblemCode.staleOperation
          ? MailCancellationReason.disposed
          : MailCancellationReason.user,
    );
    if (!cancelled.isCompleted) {
      cancelled.complete(code);
    }
  }
}

/// This adapter never persists credentials. Dispose overwrites the byte buffer
/// it owns; it does not claim to erase copies held by an active TLS operation.
final class _SessionCredentials implements MailCredentialStore {
  _SessionCredentials(this.reference, this._secret);

  final MailCredentialReference reference;
  Uint8List? _secret;

  bool _matches(MailCredentialReference candidate) =>
      candidate.account == reference.account && candidate.key == reference.key;

  void dispose() {
    final secret = _secret;
    _secret = null;
    secret?.fillRange(0, secret.length, 0);
  }

  @override
  Future<MailResult<MailCredentialRecord?>> load(
    MailCredentialReference candidate,
  ) async {
    if (!_matches(candidate)) {
      return const MailFailure(MailProblem(MailProblemCode.invalidInput));
    }
    final secret = _secret;
    return MailSuccess(
      secret == null
          ? null
          : MailCredentialRecord(
              reference: reference,
              opaqueData: MailBytes(secret),
            ),
    );
  }

  @override
  Future<MailResult<MailUnit>> store(MailCredentialRecord record) async =>
      const MailFailure(MailProblem(MailProblemCode.unsupported));

  @override
  Future<MailResult<MailUnit>> delete(MailCredentialReference candidate) async {
    if (!_matches(candidate)) {
      return const MailFailure(MailProblem(MailProblemCode.invalidInput));
    }
    dispose();
    return const MailSuccess(MailUnit.value);
  }

  @override
  Future<MailResult<MailUnit>> deleteAccount(MailAccountId account) async {
    if (account != reference.account) {
      return const MailFailure(MailProblem(MailProblemCode.invalidInput));
    }
    dispose();
    return const MailSuccess(MailUnit.value);
  }
}
