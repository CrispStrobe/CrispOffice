import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:enough_mail/imap.dart' as imap;
import 'package:quds_mail_core/quds_mail_core.dart';

import '../configuration.dart';
import '../cursor.dart';
import 'copy_uid.dart';

/// Internal test seam. The supported package API never exposes library clients.
typedef ImapClientFactory =
    imap.ImapClient Function({
      required int maxLiteralBytes,
      required int maxResponseBytes,
      required MailTransportLimits limits,
    });

imap.ImapClient _client({
  required int maxLiteralBytes,
  required int maxResponseBytes,
  required MailTransportLimits limits,
}) => imap.ImapClient(
  isLogEnabled: false,
  defaultResponseTimeout: limits.operationTimeout,
  defaultWriteTimeout: limits.operationTimeout,
  maxLiteralSize: maxLiteralBytes,
  maxProtocolLineBytes: limits.maxProtocolLineBytes,
  maxResponseBytes: maxResponseBytes,
);

final class _Failure implements Exception {
  const _Failure(this.code);
  final MailProblemCode code;
}

final class _Operation {
  _Operation(this.lease);
  final MailOperationLease lease;
  bool stopped = false;
  bool mutationStarted = false;
  bool authenticating = false;

  void check() {
    lease.checkCurrent();
    if (stopped) throw const _Failure(MailProblemCode.staleOperation);
  }
}

/// Stateless connections keep account generations and credentials isolated.
/// A provider allows one active operation, and never automatically replays one.
final class NativeMailImapProvider
    implements
        MailProvider,
        MailImapHeaderBrowser,
        MailFlagObserver,
        MailMembershipObserver,
        MailMutationReceiptProvider,
        MailArchiveDestinationResolver {
  NativeMailImapProvider({
    required this.configuration,
    required this.credentialStore,
    required this.codec,
    this.limits = const MailTransportLimits(),
    ImapClientFactory? clientFactory,
  }) : _clientFactory = clientFactory ?? _client {
    limits.validate();
  }

  final MailImapConfiguration configuration;
  final MailCredentialStore credentialStore;
  final MailCodec codec;
  final MailTransportLimits limits;
  final ImapClientFactory _clientFactory;
  bool _busy = false;

  @override
  MailAccountId get account => configuration.account;

  MailResult<T> _failure<T>(
    MailProblemCode code, {
    bool mutationMayHaveOccurred = false,
  }) => MailFailure(
    MailProblem(
      code,
      mutationMayHaveOccurred: mutationMayHaveOccurred,
      retryAfter:
          code == MailProblemCode.unavailable ||
              code == MailProblemCode.providerFailure
          ? limits.retryAfter
          : null,
    ),
  );

  bool _mailboxValid(MailMailboxId mailbox) =>
      mailbox.account == account && mailbox.value.length <= 1024;

  Future<MailResult<T>> _run<T>(
    MailOperationLease lease,
    Future<T> Function(imap.ImapClient client, _Operation operation) action, {
    int? literalBytes,
    int? responseBytes,
  }) async {
    if (lease.account != account) return _failure(MailProblemCode.invalidInput);
    if (_busy) return _failure(MailProblemCode.unavailable);
    _busy = true;
    final operation = _Operation(lease);
    imap.ImapClient? client;
    Timer? cancellationPoll;
    try {
      operation.check();
      client = _clientFactory(
        maxLiteralBytes: literalBytes ?? limits.maxHeaderBytes,
        maxResponseBytes: responseBytes ?? limits.maxResponseBytes,
        limits: limits,
      );
      final current = client;
      final cancellation = Completer<T>();
      cancellationPoll = Timer.periodic(limits.cancellationPollInterval, (_) {
        try {
          operation.check();
        } on Object catch (error, stack) {
          if (!cancellation.isCompleted) {
            cancellation.completeError(error, stack);
          }
        }
      });
      final work = runZoned(
        () async {
          try {
            await _authenticate(current, operation);
            operation.check();
            final result = await action(current, operation);
            operation.check();
            return result;
          } finally {
            if (operation.stopped) await current.abort();
          }
        },
        zoneSpecification: ZoneSpecification(
          print: (self, parent, zone, line) {
            // Legacy protocol-library print calls must not disclose server content.
            // Callers receive only the typed, content-free result of this operation.
          },
        ),
      );
      final result = await Future.any(<Future<T>>[
        work,
        cancellation.future,
      ]).timeout(limits.operationTimeout);
      operation.check();
      return MailSuccess(result);
    } on MailCancelled catch (error) {
      if (operation.mutationStarted) {
        return _failure(
          MailProblemCode.conflict,
          mutationMayHaveOccurred: true,
        );
      }
      return _failure(
        error.reason == MailCancellationReason.user ||
                error.reason == MailCancellationReason.budgetExpired
            ? MailProblemCode.cancelled
            : MailProblemCode.staleOperation,
      );
    } on _Failure catch (error) {
      return _failure(
        operation.mutationStarted ? MailProblemCode.conflict : error.code,
        mutationMayHaveOccurred: operation.mutationStarted,
      );
    } on TimeoutException {
      return _failure(
        operation.mutationStarted
            ? MailProblemCode.conflict
            : MailProblemCode.unavailable,
        mutationMayHaveOccurred: operation.mutationStarted,
      );
    } on Object {
      return _failure(
        operation.mutationStarted
            ? MailProblemCode.conflict
            : client?.responseLimitExceeded == true
            ? MailProblemCode.quotaExceeded
            : operation.authenticating
            ? MailProblemCode.authenticationRequired
            : MailProblemCode.providerFailure,
        mutationMayHaveOccurred: operation.mutationStarted,
      );
    } finally {
      operation.stopped = true;
      cancellationPoll?.cancel();
      try {
        await client?.abort().timeout(const Duration(seconds: 1));
      } on Object {
        // A closed/failed transport cannot turn an uncertain command into success.
      }
      _busy = false;
    }
  }

  Future<void> _authenticate(
    imap.ImapClient client,
    _Operation operation,
  ) async {
    final result = await credentialStore.load(configuration.credential);
    operation.check();
    if (result case MailFailure<MailCredentialRecord?>(:final problem)) {
      throw _Failure(problem.code);
    }
    final record = (result as MailSuccess<MailCredentialRecord?>).value;
    if (record == null) {
      throw const _Failure(MailProblemCode.authenticationRequired);
    }
    if (record.reference.account != account ||
        record.reference.key != configuration.credential.key ||
        record.opaqueData.length < 1 ||
        record.opaqueData.length > limits.maxCredentialBytes) {
      throw const _Failure(MailProblemCode.invalidInput);
    }
    String secret;
    try {
      secret = utf8.decode(record.opaqueData.bytes);
    } on FormatException {
      throw const _Failure(MailProblemCode.invalidInput);
    }
    if (secret.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
      throw const _Failure(MailProblemCode.invalidInput);
    }
    final endpoint = configuration.endpoint;
    await client.connectToServer(
      endpoint.host,
      endpoint.port,
      isSecure: endpoint.tls == MailTlsMode.implicitTls,
      timeout: limits.operationTimeout,
    );
    operation.check();
    await client.capability();
    operation.check();
    if (endpoint.tls == MailTlsMode.startTls) {
      if (!client.serverInfo.supportsStartTls) {
        throw const _Failure(MailProblemCode.permissionDenied);
      }
      await client.startTls();
      operation.check();
    }
    operation.authenticating = true;
    switch (configuration.authentication) {
      case MailImapAuthentication.password:
        if (client.serverInfo.supports('LOGINDISABLED')) {
          throw const _Failure(MailProblemCode.unsupported);
        }
        await client.login(configuration.username, secret);
      case MailImapAuthentication.xoauth2:
        if (!client.serverInfo.supports('AUTH=XOAUTH2') ||
            !client.serverInfo.supports('SASL-IR')) {
          throw const _Failure(MailProblemCode.unsupported);
        }
        await client.authenticateWithOAuth2(configuration.username, secret);
      case MailImapAuthentication.oauthBearer:
        if (!client.serverInfo.supports('AUTH=OAUTHBEARER') ||
            !client.serverInfo.supports('SASL-IR')) {
          throw const _Failure(MailProblemCode.unsupported);
        }
        await client.authenticateWithOAuthBearer(
          configuration.username,
          secret,
        );
    }
    operation.authenticating = false;
    operation.check();
    // Capabilities can change after authentication; never trust pre-auth MOVE.
    await client.capability();
    operation.check();
  }

  @override
  Future<MailResult<MailCapabilities>> capabilities(MailOperationLease lease) =>
      _run(
        lease,
        (client, operation) async => MailCapabilities([
          MailCapability.mail,
          MailCapability.folders,
          MailCapability.delete,
          if (client.serverInfo.supportsMove) MailCapability.move,
        ]),
      );

  @override
  Future<MailResult<List<MailMailbox>>> listMailboxes(
    MailOperationLease lease,
  ) => _run(lease, (client, operation) async {
    final boxes = await client.listMailboxes();
    operation.check();
    if (boxes.length > limits.maxMailboxes) {
      throw const _Failure(MailProblemCode.quotaExceeded);
    }
    final ids = <String>{};
    final result = <MailMailbox>[];
    for (final box in boxes) {
      if (box.flags.contains(imap.MailboxFlag.noSelect) ||
          box.flags.contains(imap.MailboxFlag.nonExistent)) {
        continue;
      }
      if (box.path.isEmpty ||
          box.path.length > 1024 ||
          box.path.contains(RegExp(r'[\x00-\x1f\x7f]')) ||
          !ids.add(box.path)) {
        throw const _Failure(MailProblemCode.providerFailure);
      }
      result.add(
        MailMailbox(
          id: MailMailboxId(box.path, account: account),
          displayName: box.name,
        ),
      );
    }
    return List.unmodifiable(result);
  });

  @override
  Future<MailResult<MailMailbox>> resolveArchiveDestination(
    MailOperationLease lease,
  ) => _run(lease, (client, operation) async {
    if (!client.serverInfo.supportsMove) {
      throw const _Failure(MailProblemCode.unsupported);
    }
    final boxes = await client.listMailboxes();
    operation.check();
    if (boxes.length > limits.maxMailboxes) {
      throw const _Failure(MailProblemCode.quotaExceeded);
    }
    final ids = <String>{};
    MailMailbox? destination;
    for (final box in boxes) {
      if (box.flags.contains(imap.MailboxFlag.noSelect) ||
          box.flags.contains(imap.MailboxFlag.nonExistent)) {
        continue;
      }
      if (box.path.isEmpty ||
          box.path.length > 1024 ||
          box.path.contains(RegExp(r'[\x00-\x1f\x7f]')) ||
          !ids.add(box.path)) {
        throw const _Failure(MailProblemCode.providerFailure);
      }
      if (!box.flags.contains(imap.MailboxFlag.archive)) continue;
      if (destination != null) {
        throw const _Failure(MailProblemCode.unsupported);
      }
      destination = MailMailbox(
        id: MailMailboxId(box.path, account: account),
        displayName: box.name,
      );
    }
    if (destination == null) {
      throw const _Failure(MailProblemCode.unsupported);
    }
    return destination;
  });

  Future<imap.Mailbox> _select(
    imap.ImapClient client,
    _Operation operation,
    MailMailboxId mailbox,
  ) async {
    final selected = await client.selectMailboxByPath(mailbox.value);
    operation.check();
    final validity = selected.uidValidity;
    final next = selected.uidNext;
    if (validity == null ||
        validity < 1 ||
        validity > 0xffffffff ||
        next == null ||
        next < 1 ||
        next > 0xffffffff) {
      throw const _Failure(MailProblemCode.providerFailure);
    }
    return selected;
  }

  MailHeaderRecord _header(
    imap.RawImapMessage source,
    MailMailboxId mailbox,
    int validity,
    _Operation operation,
  ) {
    operation.check();
    final parsed = codec.parse(
      source.bytes,
      budget: MailReadBudget(
        maxRawBytes: limits.maxHeaderBytes,
        maxHeaderBytes: limits.maxHeaderBytes,
        maxHeaderFieldBytes: math.min(64 * 1024, limits.maxHeaderBytes),
      ),
      cancellation: operation.lease.cancellation,
    );
    final message = parsed.message;
    if (message == null ||
        parsed.status != MailParseStatus.complete &&
            parsed.status != MailParseStatus.partial) {
      throw _Failure(
        parsed.status == MailParseStatus.rejected
            ? MailProblemCode.quotaExceeded
            : MailProblemCode.providerFailure,
      );
    }
    final identity = MailImapIdentity(
      mailbox: mailbox,
      uidValidity: validity,
      uid: source.uid,
    );
    final flags = source.flags?.map((flag) => flag.toLowerCase()).toSet();
    return MailHeaderRecord(
      id: imapMessageId(identity),
      remote: identity,
      envelope: message.envelope,
      flags: flags == null
          ? null
          : MailMessageFlags(
              isRead: flags.contains(r'\seen'),
              isFlagged: flags.contains(r'\flagged'),
              isAnswered: flags.contains(r'\answered'),
              isDraft: flags.contains(r'\draft'),
              isDeleted: flags.contains(r'\deleted'),
            ),
    );
  }

  @override
  Future<MailResult<MailSyncPage>> pullChanges(
    MailMailboxId mailbox, {
    MailCursor? cursor,
    required int limit,
    required MailOperationLease lease,
  }) async {
    if (!_mailboxValid(mailbox) || limit < 1 || limit > limits.maxPageSize) {
      return _failure(MailProblemCode.invalidInput);
    }
    ImapScanCursor? previous;
    try {
      previous = ImapScanCursor.decode(cursor, mailbox);
    } on FormatException {
      return _failure(MailProblemCode.invalidInput);
    }
    final revision = previous?.revision ?? 0;
    if (revision == ImapScanCursor.maxRevision) {
      // Never wrap or round a durable comparison token back to an old value.
      return _failure(MailProblemCode.invalidInput);
    }
    return _run(lease, (client, operation) async {
      final selected = await _select(client, operation, mailbox);
      final validity = selected.uidValidity!;
      final reset = previous != null && previous.uidValidity != validity;
      final legacyCeiling = limits.maxUidScan;
      if (legacyCeiling != null &&
          (selected.uidNext! - 1 > legacyCeiling ||
              (!reset && (previous?.ceiling ?? 0) > legacyCeiling))) {
        throw const _Failure(MailProblemCode.unsupported);
      }
      final beginning = previous == null || reset || previous.ceiling == 0;
      final first = beginning ? 1 : previous.nextUid;
      final ceiling = beginning ? selected.uidNext! - 1 : previous.ceiling;
      if (ceiling > selected.uidNext! - 1) {
        // UIDNEXT must not move backwards within one UIDVALIDITY generation.
        // A contradictory SELECT cannot authorize deletion of the old range.
        throw const _Failure(MailProblemCode.providerFailure);
      }
      var last = ceiling;
      final upserts = <MailHeaderRecord>[];
      MailImapSyncRange? range;
      if (first <= ceiling) {
        final discovered = await client.uidSearchRaw(
          firstUid: first,
          lastUid: ceiling,
          maxUids: limits.maxDiscoveredUids,
          responseTimeout: limits.operationTimeout,
        );
        operation.check();
        if (discovered.length > limit) last = discovered[limit - 1];
        final selectedUids = discovered.take(limit).toSet();
        if (selectedUids.isNotEmpty) {
          final fetched = await client.uidFetchRawMessages(
            firstUid: first,
            lastUid: last,
            headersOnly: true,
            maxMessages: limit,
            maxLiteralBytes: limits.maxHeaderBytes,
            responseTimeout: limits.operationTimeout,
          );
          operation.check();
          for (final source in fetched.messages) {
            if (!selectedUids.contains(source.uid)) {
              throw const _Failure(MailProblemCode.providerFailure);
            }
            upserts.add(_header(source, mailbox, validity, operation));
          }
        }
        range = MailImapSyncRange(
          mailbox: mailbox,
          uidValidity: validity,
          firstUid: first,
          lastUid: last,
        );
      }
      final more = last < ceiling;
      final next = ImapScanCursor(
        uidValidity: validity,
        nextUid: more ? last + 1 : 1,
        ceiling: more ? ceiling : 0,
        revision: revision + 1,
      );
      return MailSyncPage(
        mailbox: mailbox,
        upserts: upserts,
        tombstones: const [],
        imapRange: range,
        next: next.encode(mailbox),
        hasMore: more,
        resetRequired: reset,
      );
    });
  }

  @override
  Future<MailResult<MailHeaderPage>> fetchHeaders(
    MailMailboxId mailbox, {
    MailCursor? cursor,
    required int limit,
    required MailOperationLease lease,
  }) async {
    final result = await pullChanges(
      mailbox,
      cursor: cursor,
      limit: limit,
      lease: lease,
    );
    return switch (result) {
      MailFailure<MailSyncPage>(:final problem) => MailFailure(problem),
      MailSuccess<MailSyncPage>(:final value) => MailSuccess(
        MailHeaderPage(
          messages: value.upserts,
          next: value.hasMore ? value.next : null,
        ),
      ),
    };
  }

  @override
  Future<MailResult<MailHeaderPage>> fetchNewestHeaders(
    MailMailboxId mailbox, {
    required int uidValidity,
    MailCursor? cursor,
    required int limit,
    required MailOperationLease lease,
  }) async {
    if (!_mailboxValid(mailbox) ||
        limit < 1 ||
        limit > limits.maxPageSize ||
        uidValidity < 1 ||
        uidValidity > 0xffffffff) {
      return _failure(MailProblemCode.invalidInput);
    }
    ImapBrowseCursor? previous;
    try {
      previous = ImapBrowseCursor.decode(cursor, mailbox);
    } on FormatException {
      return _failure(MailProblemCode.invalidInput);
    }
    if (previous != null && previous.uidValidity != uidValidity) {
      return _failure(MailProblemCode.conflict);
    }
    return _run(lease, (client, operation) async {
      final selected = await _select(client, operation, mailbox);
      if (selected.uidValidity != uidValidity) {
        throw const _Failure(MailProblemCode.conflict);
      }
      final currentCeiling = selected.uidNext! - 1;
      final initialCeiling = previous?.initialCeiling ?? currentCeiling;
      if (currentCeiling < initialCeiling) {
        throw const _Failure(MailProblemCode.providerFailure);
      }
      final legacyCeiling = limits.maxUidScan;
      if (legacyCeiling != null && initialCeiling > legacyCeiling) {
        throw const _Failure(MailProblemCode.unsupported);
      }
      final ceiling = previous?.nextCeiling ?? initialCeiling;
      if (ceiling == 0) return MailHeaderPage(messages: const []);
      // Bound the widest possible dense SEARCH line before asking the server
      // for it. A token has at most this ceiling's digits plus one separator;
      // fixed slack covers SEARCH framing and its tagged completion response.
      // Use at most half the connection's aggregate byte budget for SEARCH to
      // retain headroom for authentication, SELECT and headers. The underlying
      // hard quota remains authoritative for unusually large control replies
      // or headers; this estimate never relaxes that connection-wide bound.
      final uidTokenBytes = ceiling.toString().length + 1;
      final windowSize = math.max(
        1,
        math.min(
          limits.maxDiscoveredUids,
          math.min(
            (limits.maxProtocolLineBytes - 32) ~/ uidTokenBytes,
            (limits.maxResponseBytes ~/ 2 - 64) ~/ uidTokenBytes,
          ),
        ),
      );
      // SELECT's count is only an optimization; the strict parser still
      // enforces every count and byte budget if that hint is inaccurate. The
      // library also uses zero for an unobserved count, so only a positive,
      // small count permits a whole-range search across large numeric gaps.
      final count = selected.messagesExists;
      final searchFirst = count > 0 && count <= windowSize
          ? 1
          : math.max(1, ceiling - windowSize + 1);
      final discovered = await client.uidSearchRaw(
        firstUid: searchFirst,
        lastUid: ceiling,
        maxUids: limits.maxDiscoveredUids,
        responseTimeout: limits.operationTimeout,
      );
      operation.check();
      final selectedUids = discovered.reversed.take(limit).toSet();
      final messages = <MailHeaderRecord>[];
      if (selectedUids.isNotEmpty) {
        final fetched = await client.uidFetchRawMessages(
          firstUid: selectedUids.last,
          lastUid: ceiling,
          headersOnly: true,
          maxMessages: limit,
          maxLiteralBytes: limits.maxHeaderBytes,
          responseTimeout: limits.operationTimeout,
        );
        operation.check();
        final observed = <int>{};
        for (final source in fetched.messages) {
          if (!selectedUids.contains(source.uid) || !observed.add(source.uid)) {
            throw const _Failure(MailProblemCode.providerFailure);
          }
          messages.add(_header(source, mailbox, uidValidity, operation));
        }
      }
      messages.sort(
        (left, right) => (right.remote as MailImapIdentity).uid.compareTo(
          (left.remote as MailImapIdentity).uid,
        ),
      );
      // One SEARCH and at most one FETCH per page: a sparse bounded window can
      // return an empty page with older ranges still available. Do not spin
      // through gaps or silently discard their continuation. Expunges between
      // SEARCH and FETCH advance the same already-observed range.
      final nextCeiling = discovered.length > limit
          ? selectedUids.last - 1
          : searchFirst - 1;
      return MailHeaderPage(
        messages: messages,
        next: nextCeiling > 0
            ? ImapBrowseCursor(
                uidValidity: uidValidity,
                initialCeiling: initialCeiling,
                nextCeiling: nextCeiling,
              ).encode(mailbox)
            : null,
      );
    });
  }

  @override
  Future<MailResult<MailMessage>> fetchMessage(
    MailRemoteIdentity identity, {
    required MailReadBudget budget,
    required MailOperationLease lease,
  }) async {
    if (identity is! MailImapIdentity || !_mailboxValid(identity.mailbox)) {
      return _failure(MailProblemCode.invalidInput);
    }
    try {
      budget.validate();
    } on ArgumentError {
      return _failure(MailProblemCode.invalidInput);
    }
    if (budget.maxRawBytes > 64 * 1024 * 1024) {
      return _failure(MailProblemCode.invalidInput);
    }
    return _run(
      lease,
      (client, operation) async {
        final selected = await _select(client, operation, identity.mailbox);
        if (selected.uidValidity != identity.uidValidity) {
          throw const _Failure(MailProblemCode.conflict);
        }
        final result = await client.uidFetchRawMessages(
          firstUid: identity.uid,
          lastUid: identity.uid,
          headersOnly: false,
          maxMessages: 1,
          maxLiteralBytes: budget.maxRawBytes,
          responseTimeout: limits.operationTimeout,
        );
        operation.check();
        if (result.messages.isEmpty) {
          throw const _Failure(MailProblemCode.unavailable);
        }
        final source = result.messages.single;
        final parsed = codec.parse(
          source.bytes,
          budget: budget,
          cancellation: lease.cancellation,
        );
        operation.check();
        final message = parsed.message;
        // MailProvider has no diagnostics field: do not hide a partial projection.
        if (message == null || parsed.status != MailParseStatus.complete) {
          throw _Failure(
            parsed.status == MailParseStatus.rejected
                ? MailProblemCode.quotaExceeded
                : parsed.status == MailParseStatus.unsupported
                ? MailProblemCode.unsupported
                : MailProblemCode.providerFailure,
          );
        }
        return MailMessage(
          raw: message.raw,
          envelope: message.envelope,
          body: message.body,
          attachments: message.attachments,
          localId: imapMessageId(identity),
          remoteIdentity: identity,
        );
      },
      literalBytes: budget.maxRawBytes,
      responseBytes: budget.maxRawBytes + limits.maxResponseBytes,
    );
  }

  Future<imap.RawImapMessage?> _readIdentity(
    imap.ImapClient client,
    _Operation operation,
    MailImapIdentity identity,
  ) async {
    final result = await client.uidFetchRawMessages(
      firstUid: identity.uid,
      lastUid: identity.uid,
      headersOnly: true,
      maxMessages: 1,
      maxLiteralBytes: limits.maxHeaderBytes,
      responseTimeout: limits.operationTimeout,
    );
    operation.check();
    return result.messages.isEmpty ? null : result.messages.single;
  }

  @override
  Future<MailResult<MailFlagObservation>> observeFlags(
    MailRemoteIdentity identity, {
    required MailOperationLease lease,
  }) async {
    if (identity is! MailImapIdentity || !_mailboxValid(identity.mailbox)) {
      return _failure(MailProblemCode.invalidInput);
    }
    return _run(lease, (client, operation) async {
      final selected = await _select(client, operation, identity.mailbox);
      if (selected.uidValidity != identity.uidValidity) {
        return MailFlagObservation.identityChanged(identity: identity);
      }
      // The bounded header FETCH uses BODY.PEEK and never changes Seen. An
      // empty exact-UID response is distinct from an absent cached list row.
      final source = await _readIdentity(client, operation, identity);
      if (source == null) {
        return MailFlagObservation.missing(identity: identity);
      }
      if (source.uid != identity.uid || source.flags == null) {
        throw const _Failure(MailProblemCode.providerFailure);
      }
      final flags = source.flags!.map((flag) => flag.toLowerCase()).toSet();
      return MailFlagObservation.present(
        identity: identity,
        flags: MailMessageFlags(
          isRead: flags.contains(r'\seen'),
          isFlagged: flags.contains(r'\flagged'),
          isAnswered: flags.contains(r'\answered'),
          isDraft: flags.contains(r'\draft'),
          isDeleted: flags.contains(r'\deleted'),
        ),
      );
    });
  }

  @override
  Future<MailResult<MailMembershipObservation>> observeMembership(
    MailRemoteIdentity identity, {
    required MailOperationLease lease,
  }) async {
    if (identity is! MailImapIdentity || !_mailboxValid(identity.mailbox)) {
      return _failure(MailProblemCode.invalidInput);
    }
    return _run(lease, (client, operation) async {
      final selected = await _select(client, operation, identity.mailbox);
      if (selected.uidValidity != identity.uidValidity) {
        return MailMembershipObservation.identityChanged(identity: identity);
      }
      // An exact source UID read can establish only its current presence and
      // deletion marker. Absence cannot recover a MOVE destination UID.
      final source = await _readIdentity(client, operation, identity);
      if (source == null) {
        return MailMembershipObservation.missing(identity: identity);
      }
      if (source.uid != identity.uid || source.flags == null) {
        throw const _Failure(MailProblemCode.providerFailure);
      }
      return MailMembershipObservation.imap(
        identity: identity,
        isDeleted: source.flags!.any(
          (flag) => flag.toLowerCase() == r'\deleted',
        ),
      );
    });
  }

  Future<void> _setFlag(
    imap.ImapClient client,
    _Operation operation,
    MailImapIdentity identity,
    String flag,
    bool enabled,
  ) async {
    operation.mutationStarted = true;
    await client.uidStore(
      imap.MessageSequence.fromId(identity.uid, isUid: true),
      <String>[flag],
      action: enabled ? imap.StoreAction.add : imap.StoreAction.remove,
    );
    operation.check();
    final confirmed = await _readIdentity(client, operation, identity);
    final flags = confirmed?.flags?.map((value) => value.toLowerCase()).toSet();
    if (flags == null || flags.contains(flag.toLowerCase()) != enabled) {
      throw const _Failure(MailProblemCode.conflict);
    }
  }

  @override
  Future<MailResult<MailUnit>> apply(
    MailOperation command,
    MailOperationLease lease,
  ) async => switch (await applyWithReceipt(command, lease)) {
    MailSuccess<MailMutationReceipt>() => const MailSuccess(MailUnit.value),
    MailFailure<MailMutationReceipt>(:final problem) => MailFailure(problem),
  };

  @override
  Future<MailResult<MailMutationReceipt>> applyWithReceipt(
    MailOperation command,
    MailOperationLease lease,
  ) async {
    final identity = command.message;
    if (identity is! MailImapIdentity ||
        !_mailboxValid(identity.mailbox) ||
        command.id.isEmpty ||
        command.id.length > 1024 ||
        command is MailMove &&
            (!_mailboxValid(command.destination) ||
                command.destination == identity.mailbox ||
                identity.mailbox.value.toUpperCase() == 'INBOX' &&
                    command.destination.value.toUpperCase() == 'INBOX')) {
      return _failure(MailProblemCode.invalidInput);
    }
    if (command is MailArchive) return _failure(MailProblemCode.unsupported);
    return _run(lease, (client, operation) async {
      final selected = await _select(client, operation, identity.mailbox);
      if (selected.uidValidity != identity.uidValidity) {
        throw const _Failure(MailProblemCode.conflict);
      }
      if (!selected.isReadWrite) {
        throw const _Failure(MailProblemCode.permissionDenied);
      }
      if (command is MailMove && !client.serverInfo.supportsMove) {
        throw const _Failure(MailProblemCode.unsupported);
      }
      if (await _readIdentity(client, operation, identity) == null) {
        throw const _Failure(MailProblemCode.unavailable);
      }
      final sequence = imap.MessageSequence.fromId(identity.uid, isUid: true);
      MailMoveIdentityTransition? transition;
      switch (command) {
        case MailSetRead(:final read):
          await _setFlag(
            client,
            operation,
            identity,
            imap.MessageFlags.seen,
            read,
          );
        case MailSetFlagged(:final flagged):
          await _setFlag(
            client,
            operation,
            identity,
            imap.MessageFlags.flagged,
            flagged,
          );
        case MailMove(:final destination):
          if (!client.serverInfo.supportsMove) {
            throw const _Failure(MailProblemCode.unsupported);
          }
          operation.mutationStarted = true;
          final moved = await client.uidMove(
            sequence,
            targetMailboxPath: destination.value,
          );
          operation.check();
          if (moved.malformedCopyUidResponse ||
              moved.copyUidResponseCodes.length > 1) {
            throw const _Failure(MailProblemCode.conflict);
          }
          final target = parseSingleCopyUid(
            moved.copyUidResponseCodes.singleOrNull,
            sourceUid: identity.uid,
          );
          if (await _readIdentity(client, operation, identity) != null) {
            throw const _Failure(MailProblemCode.conflict);
          }
          if (target != null) {
            final remote = MailImapIdentity(
              mailbox: destination,
              uidValidity: target.uidValidity,
              uid: target.uid,
            );
            transition = MailMoveIdentityTransition(
              operationId: command.id,
              source: identity,
              sourceMailbox: identity.mailbox,
              destination: remote,
              destinationMailbox: destination,
              destinationMessageId: imapMessageId(remote),
            );
          }
        case MailDelete():
          // Delete marks the specific UID. No mailbox-wide EXPUNGE or CLOSE.
          await _setFlag(
            client,
            operation,
            identity,
            imap.MessageFlags.deleted,
            true,
          );
        case MailArchive():
          throw const _Failure(MailProblemCode.unsupported);
      }
      operation.check();
      return MailMutationReceipt(identityTransition: transition);
    });
  }
}
