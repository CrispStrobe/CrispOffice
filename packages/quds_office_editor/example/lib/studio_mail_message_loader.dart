import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:enough_mail/enough_mail.dart' as mail;
import 'package:quds_mail_core/quds_mail_core.dart';
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
  const StudioMailMessageLoadException(this.code);

  final MailProblemCode code;

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
/// Envelope fetching remains owned by Studio's high-level client. Callers must
/// pair an envelope with the selected mailbox observed while fetching its list.
/// Sequence numbers and the library's collision-prone GUID are never identities.
/// The selected path, UIDVALIDITY and UID are frozen before any asynchronous
/// operation, and the provider checks the server's current UIDVALIDITY before
/// reading the exact UID. Original octets are never rendered back into a string.
final class NativeStudioMailMessageLoader implements StudioMailMessageLoader {
  factory NativeStudioMailMessageLoader(
    mail.MailAccount account, {
    StudioMailProviderFactory? providerFactory,
    MailReadBudget budget = const MailReadBudget(),
    MailTransportLimits limits = const MailTransportLimits(),
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
      final id = MailAccountId(
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

  MailImapIdentity _identity(
    mail.Mailbox selectedMailbox,
    mail.MimeMessage header,
  ) {
    if (_session.isDisposed) {
      throw const StudioMailMessageLoadException(
        MailProblemCode.staleOperation,
      );
    }
    final MailImapIdentity identity;
    try {
      final uidValidity = selectedMailbox.uidValidity;
      final uid = header.uid;
      if (uidValidity == null ||
          uid == null ||
          selectedMailbox.isNotSelectable ||
          selectedMailbox.path.length > 1024) {
        throw const StudioMailMessageLoadException(
          MailProblemCode.invalidInput,
        );
      }
      identity = MailImapIdentity(
        mailbox: MailMailboxId(
          selectedMailbox.path,
          account: _configuration.account,
        ),
        uidValidity: uidValidity,
        uid: uid,
      );
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
        throw const StudioMailMessageLoadException(MailProblemCode.conflict);
      }
    } on ArgumentError {
      throw const StudioMailMessageLoadException(MailProblemCode.invalidInput);
    }
    return identity;
  }

  @override
  Future<Uint8List> fetch(
    mail.Mailbox selectedMailbox,
    mail.MimeMessage header,
  ) async {
    final identity = _identity(selectedMailbox, header);
    final message = await _run(
      (provider, lease) =>
          provider.fetchMessage(identity, budget: budget, lease: lease),
    );
    if (message.remoteIdentity != identity) {
      throw const StudioMailMessageLoadException(MailProblemCode.conflict);
    }
    if (message.raw.length > budget.maxRawBytes) {
      throw const StudioMailMessageLoadException(MailProblemCode.quotaExceeded);
    }
    return message.raw.copyBytes();
  }

  @override
  Future<void> markRead(
    mail.Mailbox selectedMailbox,
    mail.MimeMessage header,
  ) async {
    final identity = _identity(selectedMailbox, header);
    // The provider opens a bounded connection, compares UIDVALIDITY, verifies
    // this UID exists, performs UID STORE, then reads back the flag. It never
    // replays a write after reconnecting or falls back to a sequence number.
    await _run(
      (provider, lease) => provider.apply(
        MailSetRead(
          id: 'mark-read-${++_nextOperation}',
          message: identity,
          read: true,
        ),
        lease,
      ),
    );
  }

  Future<T> _run<T>(
    Future<MailResult<T>> Function(MailProvider, MailOperationLease) action,
  ) async {
    cancel();
    final operation = _MessageOperation();
    _active = operation;
    final lease = _session.begin(cancellation: operation.cancellation.token);
    try {
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
      lease.checkCurrent();
      final result = await Future.any<MailResult<T>>([
        action(provider, lease),
        operation.cancelled.future.then(
          (code) => MailFailure(MailProblem(code)),
        ),
      ]);
      lease.checkCurrent();
      if (result case MailFailure<T>(:final problem)) {
        throw StudioMailMessageLoadException(problem.code);
      }
      return (result as MailSuccess<T>).value;
    } on StudioMailMessageLoadException {
      rethrow;
    } on MailCancelled catch (error) {
      throw StudioMailMessageLoadException(
        error.reason == MailCancellationReason.user
            ? MailProblemCode.cancelled
            : MailProblemCode.staleOperation,
      );
    } on Object {
      throw const StudioMailMessageLoadException(
        MailProblemCode.providerFailure,
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
  }
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
