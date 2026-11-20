import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:quds_mail_core/quds_mail_core.dart';

import '../configuration.dart';
import '../cursor.dart';
import '../errors.dart';
import '../soap.dart';
import 'http_client.dart';

/// Internal transport seam; the public factory exposes no HTTP client/secret.
typedef EwsHttpClientFactory =
    EwsHttpClient Function({
      required MailEwsConfiguration configuration,
      required String secret,
      required MailEwsLimits limits,
    });

EwsHttpClient _client({
  required MailEwsConfiguration configuration,
  required String secret,
  required MailEwsLimits limits,
}) => NativeEwsHttpClient(
  configuration: configuration,
  secret: secret,
  limits: limits,
);

final class _Operation {
  _Operation(this.lease);
  final MailOperationLease lease;
  bool stopped = false;

  void check() {
    lease.checkCurrent();
    if (stopped) throw const EwsException(MailProblemCode.staleOperation);
  }

  Future<String> post(
    EwsHttpClient client,
    String action,
    String envelope, {
    bool mutation = false,
  }) async {
    check();
    final response = await client.post(action, envelope, mutation: mutation);
    check();
    return response;
  }
}

/// Native Exchange Server mail adapter. One active operation owns one HTTPS
/// client and a fresh vault read. No operation, including send, is retried here.
final class NativeMailEwsProvider implements MailEwsProvider {
  NativeMailEwsProvider({
    required this.configuration,
    required this.credentialStore,
    required this.codec,
    this.limits = const MailEwsLimits(),
    EwsHttpClientFactory? clientFactory,
  }) : _clientFactory = clientFactory ?? _client,
       _soap = EwsSoap(configuration: configuration, limits: limits) {
    limits.validate();
  }

  final MailEwsConfiguration configuration;
  final MailCredentialStore credentialStore;
  final MailCodec codec;
  final MailEwsLimits limits;
  final EwsHttpClientFactory _clientFactory;
  final EwsSoap _soap;
  bool _busy = false;

  @override
  MailAccountId get account => configuration.account;

  MailFailure<T> _failure<T>(
    MailProblemCode code, {
    Duration? retryAfter,
    bool mutationMayHaveOccurred = false,
  }) => MailFailure(
    MailProblem(
      code,
      mutationMayHaveOccurred: mutationMayHaveOccurred,
      retryAfter:
          code == MailProblemCode.unavailable ||
              code == MailProblemCode.providerFailure
          ? retryAfter ?? limits.retryAfter
          : null,
    ),
  );

  bool _validId(String value) =>
      value.isNotEmpty &&
      value.length <= 1024 &&
      !value.contains(RegExp(r'[\x00-\x1f\x7f]'));

  bool _mailboxValid(MailMailboxId mailbox) =>
      mailbox.account == account && _validId(mailbox.value);

  bool _identityValid(MailRemoteIdentity identity) =>
      identity is MailOpaqueIdentity &&
      identity.account == account &&
      identity.provider == MailProviderKind.ews &&
      _validId(identity.value);

  bool _limitValid(int limit) => limit > 0 && limit <= limits.maxPageSize;

  MailOpaqueIdentity _identity(String id) => MailOpaqueIdentity(
    account: account,
    provider: MailProviderKind.ews,
    value: id,
  );

  MailHeaderRecord _record(EwsItem item) {
    final identity = _identity(item.id);
    return MailHeaderRecord(
      id: ewsMessageId(identity),
      remote: identity,
      envelope: item.envelope,
      flags: item.flags,
    );
  }

  Future<MailResult<T>> _run<T>(
    MailOperationLease lease,
    Future<T> Function(EwsHttpClient client, _Operation operation) action,
  ) async {
    if (lease.account != account) return _failure(MailProblemCode.invalidInput);
    if (_busy) return _failure(MailProblemCode.unavailable);
    _busy = true;
    final operation = _Operation(lease);
    EwsHttpClient? client;
    Timer? poll;
    try {
      operation.check();
      final cancelled = Completer<T>();
      poll = Timer.periodic(limits.cancellationPollInterval, (_) {
        try {
          operation.check();
        } on Object catch (error, stack) {
          if (!cancelled.isCompleted) cancelled.completeError(error, stack);
        }
      });
      final work = () async {
        final stored = await credentialStore.load(configuration.credential);
        operation.check();
        if (stored case MailFailure<MailCredentialRecord?>(:final problem)) {
          throw EwsException(problem.code, retryAfter: problem.retryAfter);
        }
        final record = (stored as MailSuccess<MailCredentialRecord?>).value;
        if (record == null) {
          throw const EwsException(MailProblemCode.authenticationRequired);
        }
        if (record.reference.account != account ||
            record.reference.key != configuration.credential.key ||
            record.opaqueData.length < 1 ||
            record.opaqueData.length > limits.maxCredentialBytes) {
          throw const EwsException(MailProblemCode.invalidInput);
        }
        String secret;
        try {
          secret = utf8.decode(record.opaqueData.bytes);
        } on FormatException {
          throw const EwsException(MailProblemCode.invalidInput);
        }
        if (secret.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
          throw const EwsException(MailProblemCode.invalidInput);
        }
        operation.check();
        final current = _clientFactory(
          configuration: configuration,
          secret: secret,
          limits: limits,
        );
        client = current;
        final value = await action(current, operation);
        operation.check();
        return value;
      }();
      final result = await Future.any(<Future<T>>[
        work,
        cancelled.future,
      ]).timeout(limits.operationTimeout);
      operation.check();
      return MailSuccess(result);
    } on MailCancelled catch (error) {
      if (client?.mutationStarted ?? false) {
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
    } on EwsException catch (error) {
      if (client?.mutationStarted ?? false) {
        return _failure(
          MailProblemCode.conflict,
          mutationMayHaveOccurred: true,
        );
      }
      return _failure(error.code, retryAfter: error.retryAfter);
    } on TimeoutException {
      return _failure(
        (client?.mutationStarted ?? false)
            ? MailProblemCode.conflict
            : MailProblemCode.unavailable,
        mutationMayHaveOccurred: client?.mutationStarted ?? false,
      );
    } on Object {
      return _failure(
        (client?.mutationStarted ?? false)
            ? MailProblemCode.conflict
            : MailProblemCode.providerFailure,
        mutationMayHaveOccurred: client?.mutationStarted ?? false,
      );
    } finally {
      operation.stopped = true;
      poll?.cancel();
      try {
        client?.abort();
      } on Object {
        // Cleanup cannot make a possibly accepted write safe to repeat.
      }
      _busy = false;
    }
  }

  @override
  Future<MailResult<MailCapabilities>> capabilities(MailOperationLease lease) =>
      _run(lease, (client, operation) async {
        final xml = await operation.post(
          client,
          'GetFolder',
          _soap.getFolder('inbox', distinguished: true),
        );
        if (_soap.folders(xml, 'GetFolder').folders.length != 1) {
          throw const EwsException(MailProblemCode.providerFailure);
        }
        return MailCapabilities(const [
          MailCapability.mail,
          MailCapability.folders,
          MailCapability.move,
          MailCapability.send,
        ]);
      });

  @override
  Future<MailResult<List<MailMailbox>>> listMailboxes(
    MailOperationLease lease,
  ) => _run(lease, (client, operation) async {
    final result = <MailMailbox>[];
    final seen = <String>{};
    var offset = 0;
    var pages = 0;
    while (true) {
      final count = math.min(limits.maxPageSize, limits.maxMailboxes);
      final xml = await operation.post(
        client,
        'FindFolder',
        _soap.findFolders(offset: offset, limit: count),
      );
      final page = _soap.folders(xml, 'FindFolder');
      if (page.folders.length > count || ++pages > limits.maxMailboxes) {
        throw const EwsException(MailProblemCode.quotaExceeded);
      }
      for (final folder in page.folders) {
        if (!seen.add(folder.id)) {
          throw const EwsException(MailProblemCode.providerFailure);
        }
        if (seen.length > limits.maxMailboxes) {
          throw const EwsException(MailProblemCode.quotaExceeded);
        }
        if (folder.isMailFolder) {
          result.add(
            MailMailbox(
              id: MailMailboxId(folder.id, account: account),
              displayName: folder.displayName,
            ),
          );
        }
      }
      if (page.lastPage) return List.unmodifiable(result);
      final next = page.nextOffset;
      if (next == null || next <= offset || next > 0x7fffffff) {
        throw const EwsException(MailProblemCode.providerFailure);
      }
      offset = next;
    }
  });

  Future<List<EwsItem?>> _items(
    EwsHttpClient client,
    _Operation operation,
    List<String> ids, {
    bool mime = false,
    int? maxMimeBytes,
    bool allowMissing = false,
  }) async {
    if (ids.isEmpty) return const [];
    final xml = await operation.post(
      client,
      'GetItem',
      _soap.getItems(ids, mime: mime),
    );
    final result = _soap.items(
      xml,
      mime: mime,
      maxMimeBytes: maxMimeBytes,
      allowMissing: allowMissing,
    );
    if (result.length != ids.length) {
      throw const EwsException(MailProblemCode.providerFailure);
    }
    for (var i = 0; i < ids.length; i++) {
      if (result[i] != null && result[i]!.id != ids[i]) {
        throw const EwsException(MailProblemCode.providerFailure);
      }
    }
    return result;
  }

  @override
  Future<MailResult<MailHeaderPage>> fetchHeaders(
    MailMailboxId mailbox, {
    MailCursor? cursor,
    required int limit,
    required MailOperationLease lease,
  }) async {
    if (!_mailboxValid(mailbox) || !_limitValid(limit)) {
      return _failure(MailProblemCode.invalidInput);
    }
    EwsHeaderCursor position;
    try {
      position = EwsHeaderCursor.decode(cursor, configuration, mailbox);
    } on EwsException catch (error) {
      return _failure(error.code);
    }
    return _run(lease, (client, operation) async {
      final xml = await operation.post(
        client,
        'FindItem',
        _soap.findItems(mailbox.value, offset: position.offset, limit: limit),
      );
      final page = _soap.itemIdsPage(xml);
      if (page.items.length > limit) {
        throw const EwsException(MailProblemCode.quotaExceeded);
      }
      if (!page.lastPage &&
          (page.nextOffset == null ||
              page.nextOffset! <= position.offset ||
              page.nextOffset! > 0x7fffffff)) {
        throw const EwsException(MailProblemCode.providerFailure);
      }
      final items = await _items(
        client,
        operation,
        page.items.map((item) => item.id).toList(),
        allowMissing: true,
      );
      return MailHeaderPage(
        messages: [
          for (final item in items)
            if (item != null) _record(item),
        ],
        next: page.lastPage
            ? null
            : EwsHeaderCursor(page.nextOffset!).encode(configuration, mailbox),
      );
    });
  }

  @override
  Future<MailResult<MailSyncPage>> pullChanges(
    MailMailboxId mailbox, {
    MailCursor? cursor,
    required int limit,
    required MailOperationLease lease,
  }) async {
    if (!_mailboxValid(mailbox) || !_limitValid(limit)) {
      return _failure(MailProblemCode.invalidInput);
    }
    EwsSyncCursor? position;
    try {
      position = EwsSyncCursor.decode(cursor, configuration, mailbox, limits);
    } on EwsException catch (error) {
      return _failure(error.code);
    }
    return _run(lease, (client, operation) async {
      var reset = position == null;
      Future<EwsSyncChanges> sync(String? state) async => _soap.sync(
        await operation.post(
          client,
          'SyncFolderItems',
          _soap.syncFolderItems(mailbox.value, syncState: state, limit: limit),
        ),
      );
      EwsSyncChanges page;
      try {
        page = await sync(position?.state);
      } on EwsException catch (error) {
        if (!error.invalidSyncState || position == null) rethrow;
        // Restart only an explicitly invalid server SyncState, once, committing
        // the reset with its page. Other conflicts must preserve cached data.
        reset = true;
        page = await sync(null);
      }
      if (page.changes.length > limit ||
          (!page.includesLast && page.syncState == position?.state)) {
        throw const EwsException(MailProblemCode.providerFailure);
      }
      final next = EwsSyncCursor(
        state: page.syncState,
        revision: (position?.revision ?? 0) + 1,
      ).encode(configuration, mailbox, limits);
      final changes = <String, EwsSyncChange>{};
      for (final change in page.changes) {
        changes[change.id] = change;
      }
      final deleted = <String>{
        for (final change in changes.values)
          if (change.kind == EwsChangeKind.delete) change.id,
      };
      final ids = [
        for (final change in changes.values)
          if (change.kind != EwsChangeKind.delete) change.id,
      ];
      final items = await _items(client, operation, ids, allowMissing: true);
      final upserts = <MailHeaderRecord>[];
      for (var i = 0; i < ids.length; i++) {
        final item = items[i];
        if (item == null) {
          // ItemNotFound is a confirmed concurrent removal, not an omitted or
          // malformed GetItem response. Never invent deletions from omissions.
          deleted.add(ids[i]);
        } else {
          upserts.add(_record(item));
        }
      }
      return MailSyncPage(
        mailbox: mailbox,
        upserts: upserts,
        tombstones: deleted.map(_identity).toList(),
        next: next,
        hasMore: !page.includesLast,
        resetRequired: reset,
      );
    });
  }

  @override
  Future<MailResult<MailMessage>> fetchMessage(
    MailRemoteIdentity identity, {
    required MailReadBudget budget,
    required MailOperationLease lease,
  }) async {
    if (!_identityValid(identity)) {
      return _failure(MailProblemCode.invalidInput);
    }
    try {
      budget.validate();
    } on ArgumentError {
      return _failure(MailProblemCode.invalidInput);
    }
    final remote = identity as MailOpaqueIdentity;
    return _run(lease, (client, operation) async {
      final item = (await _items(
        client,
        operation,
        [remote.value],
        mime: true,
        maxMimeBytes: budget.maxRawBytes,
      )).single!;
      final mime = item.mimeBytes;
      if (mime == null) {
        throw const EwsException(MailProblemCode.providerFailure);
      }
      operation.check();
      final parsed = codec.parse(
        mime,
        budget: budget,
        cancellation: lease.cancellation,
      );
      operation.check();
      final message = _completeMessage(parsed);
      return MailMessage(
        raw: message.raw,
        // Exchange's header properties supplement its generated MIME, which
        // can omit Bcc and other mailbox-only metadata.
        envelope: item.envelope,
        body: message.body,
        attachments: message.attachments,
        localId: ewsMessageId(remote),
        remoteIdentity: remote,
      );
    });
  }

  MailMessage _completeMessage(MailParseResult parsed) {
    if (parsed.status == MailParseStatus.complete && parsed.message != null) {
      return parsed.message!;
    }
    throw EwsException(switch (parsed.status) {
      MailParseStatus.rejected => MailProblemCode.quotaExceeded,
      MailParseStatus.unsupported => MailProblemCode.unsupported,
      MailParseStatus.cancelled => MailProblemCode.cancelled,
      _ => MailProblemCode.providerFailure,
    });
  }

  @override
  Future<MailResult<MailUnit>> apply(
    MailOperation command,
    MailOperationLease lease,
  ) async {
    if (!_identityValid(command.message) ||
        !_validId(command.id) ||
        (command is MailMove && !_mailboxValid(command.destination))) {
      return _failure(MailProblemCode.invalidInput);
    }
    final remote = command.message as MailOpaqueIdentity;
    return _run(lease, (client, operation) async {
      // ChangeKey is a concurrency token, not stable message identity. Always
      // get the current key, then use NeverOverwrite for a conditional update.
      final item = (await _items(client, operation, [remote.value])).single!;
      String action;
      String envelope;
      switch (command) {
        case MailSetRead(:final read):
          if (item.flags?.isRead == read) return MailUnit.value;
          action = 'UpdateItem';
          envelope = _soap.updateRead(item.id, item.changeKey, read);
        case MailSetFlagged(:final flagged):
          if (item.flags?.isFlagged == flagged) return MailUnit.value;
          action = 'UpdateItem';
          envelope = _soap.updateFlagged(item.id, item.changeKey, flagged);
        case MailMove(:final destination):
          action = 'MoveItem';
          envelope = _soap.moveItem(item.id, item.changeKey, destination.value);
        case MailDelete():
          action = 'DeleteItem';
          envelope = _soap.deleteItem(item.id, item.changeKey);
      }
      final xml = await operation.post(
        client,
        action,
        envelope,
        mutation: true,
      );
      final changed = _soap.mutation(xml, action);
      if (action == 'UpdateItem' &&
          (changed.length != 1 || changed.single.id != item.id)) {
        throw const EwsException(MailProblemCode.conflict);
      }
      final confirmed = (await _items(client, operation, [
        item.id,
      ], allowMissing: true)).single;
      final observed = confirmed?.flags;
      final correct = switch (command) {
        MailSetRead(:final read) => observed?.isRead == read,
        MailSetFlagged(:final flagged) => observed?.isFlagged == flagged,
        MailMove() || MailDelete() => confirmed == null,
      };
      if (!correct) throw const EwsException(MailProblemCode.conflict);
      return MailUnit.value;
    });
  }

  @override
  Future<MailSubmissionResult> submit(
    MailPreparedMessage message, {
    required String attemptId,
    required MailOperationLease lease,
  }) async {
    if (attemptId.isEmpty) {
      throw ArgumentError('Submission requires a persisted attempt identity.');
    }
    final result = await _submit(message, attemptId, lease);
    if (result is MailSuccess<MailUnit>) {
      // EWS supplies an aggregate submission acknowledgment, not per-recipient
      // SMTP responses or final delivery. Do not fabricate recipient outcomes.
      return MailSubmissionResult(
        attemptId: attemptId,
        outcome: MailSubmissionOutcome.accepted,
      );
    }
    final problem = (result as MailFailure<MailUnit>).problem;
    return MailSubmissionResult(
      attemptId: attemptId,
      outcome: switch (problem.code) {
        MailProblemCode.conflict => MailSubmissionOutcome.uncertain,
        MailProblemCode.unavailable ||
        MailProblemCode.providerFailure ||
        MailProblemCode.cancelled ||
        MailProblemCode.staleOperation =>
          MailSubmissionOutcome.retryableFailure,
        _ => MailSubmissionOutcome.rejected,
      },
      problem: problem,
    );
  }

  Future<MailResult<MailUnit>> _submit(
    MailPreparedMessage message,
    String attemptId,
    MailOperationLease lease,
  ) async {
    final addresses = message.envelope.recipients;
    if (message.account != account ||
        lease.account != account ||
        !_validId(attemptId) ||
        !validEwsAddress(message.envelope.sender) ||
        addresses.length > 1000 ||
        addresses.any((address) => !validEwsAddress(address))) {
      return _failure(MailProblemCode.invalidInput);
    }
    if (message.wire.length > const MailReadBudget().maxRawBytes ||
        (message.wire.length + 2) ~/ 3 * 4 > limits.maxRequestBytes) {
      return _failure(MailProblemCode.quotaExceeded);
    }
    MailEnvelope headers;
    try {
      lease.checkCurrent();
      headers = _completeMessage(
        codec.parse(message.wire.bytes, cancellation: lease.cancellation),
      ).envelope;
      lease.checkCurrent();
    } on EwsException catch (error) {
      return _failure(error.code);
    } on MailCancelled {
      return _failure(MailProblemCode.cancelled);
    } on Object {
      return _failure(MailProblemCode.invalidInput);
    }
    final intended = addresses.toSet();
    final visible = <String>{};
    if (headers.bcc.isNotEmpty ||
        headers.from.length != 1 ||
        headers.from.single.address != message.envelope.sender) {
      return _failure(MailProblemCode.invalidInput);
    }
    for (final address in [...headers.to, ...headers.cc]) {
      if (!validEwsAddress(address.address) ||
          !intended.contains(address.address) ||
          !visible.add(address.address)) {
        return _failure(MailProblemCode.invalidInput);
      }
    }
    final bcc = [
      for (final address in addresses)
        if (!visible.contains(address)) address,
    ];
    return _run(lease, (client, operation) async {
      final envelope = _soap.createMessage(
        mime: message.wire.bytes,
        sender: message.envelope.sender,
        to: headers.to,
        cc: headers.cc,
        bcc: bcc,
      );
      final xml = await operation.post(
        client,
        'CreateItem',
        envelope,
        mutation: true,
      );
      _soap.mutation(xml, 'CreateItem');
      return MailUnit.value;
    });
  }
}
