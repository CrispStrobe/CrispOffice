import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';

/// Optional mailbox access through the already-owned local draft repository.
/// The enclosing draft store retains sole responsibility for closing it.
abstract interface class StudioMailMailboxStoreOwner {
  StudioMailMailboxStore get mailboxStore;
}

abstract interface class StudioMailMailboxStore {
  MailAccountId get account;
  Future<List<MailCachedMailboxSummary>> listViews();
  Future<MailCachedMailboxView?> loadView(MailMailboxId mailbox);
  Future<MailCachedMailboxView> saveView(
    MailMailbox mailbox,
    List<MailHeaderRecord> headers, {
    required bool hasMore,
    required MailOperationLease lease,
  });
  Future<void> cacheMessage(
    MailHeaderRecord header,
    MailMessage message, {
    required MailOperationLease lease,
  });
  Future<MailMessage?> loadMessage(MailHeaderRecord header);
}

final class StudioMailMailboxStoreException implements Exception {
  const StudioMailMailboxStoreException(this.code);
  final MailProblemCode code;

  @override
  String toString() => 'StudioMailMailboxStoreException(${code.name})';
}

typedef StudioMailStorageQueue =
    Future<T> Function<T>(Future<T> Function() action);

/// Shares the draft owner's serialization and exclusive SQLite lease. A body
/// never gets persisted under a different remote identity or local account.
final class SqliteStudioMailMailboxStore implements StudioMailMailboxStore {
  SqliteStudioMailMailboxStore({
    required this._repository,
    required this.account,
    required this._serialize,
  });

  final SqliteMailRepository _repository;
  final StudioMailStorageQueue _serialize;
  @override
  final MailAccountId account;

  static T _value<T>(MailResult<T> result) => switch (result) {
    MailSuccess<T>(:final value) => value,
    MailFailure<T>(:final problem) => throw StudioMailMailboxStoreException(
      problem.code,
    ),
  };

  void _scope(MailAccountId value) {
    if (value != account) {
      throw const StudioMailMailboxStoreException(
        MailProblemCode.permissionDenied,
      );
    }
  }

  @override
  Future<List<MailCachedMailboxSummary>> listViews() => _serialize(
    () async => _value(await _repository.listMailboxViews(account)),
  );

  @override
  Future<MailCachedMailboxView?> loadView(MailMailboxId mailbox) =>
      _serialize(() async {
        _scope(mailbox.account);
        return _value(await _repository.loadMailboxView(mailbox));
      });

  @override
  Future<MailCachedMailboxView> saveView(
    MailMailbox mailbox,
    List<MailHeaderRecord> headers, {
    required bool hasMore,
    required MailOperationLease lease,
  }) {
    final snapshot = List<MailHeaderRecord>.unmodifiable(headers);
    return _serialize(() async {
      _scope(mailbox.id.account);
      _scope(lease.account);
      lease.checkCurrent();
      final previous = _value(await _repository.loadMailboxView(mailbox.id));
      lease.checkCurrent();
      return _value(
        await _repository.saveMailboxView(
          mailbox,
          snapshot,
          expectedRevision: previous?.revision,
          hasMore: hasMore,
          lease: lease,
        ),
      );
    });
  }

  @override
  Future<void> cacheMessage(
    MailHeaderRecord header,
    MailMessage message, {
    required MailOperationLease lease,
  }) => _serialize(() async {
    _scope(header.remote.account);
    _scope(lease.account);
    lease.checkCurrent();
    if (message.remoteIdentity != header.remote ||
        message.localId != header.id) {
      throw const StudioMailMailboxStoreException(MailProblemCode.conflict);
    }
    _value(
      await _repository.cacheMessage(account, header.id, message, lease: lease),
    );
  });

  @override
  Future<MailMessage?> loadMessage(MailHeaderRecord header) =>
      _serialize(() async {
        _scope(header.remote.account);
        final message = _value(
          await _repository.loadCachedMessage(account, header.id),
        );
        if (message != null &&
            (message.remoteIdentity != header.remote ||
                message.localId != header.id)) {
          throw const StudioMailMailboxStoreException(MailProblemCode.conflict);
        }
        return message;
      });
}

/// One live connection's write authority into a stable account namespace.
/// Provider cursors are deliberately not persisted or rewritten. Every remote
/// identity is checked in its original session before it is rebound for local
/// storage. Reconnects get a new lease even when their stable account is equal.
final class StudioMailMailboxCapture {
  StudioMailMailboxCapture({
    required this.store,
    required this.sourceAccount,
    required this.provider,
    required this._isCurrent,
  }) : _session = MailAccountSession(store.account);

  final StudioMailMailboxStore store;
  final MailAccountId sourceAccount;
  final MailProviderKind provider;
  final bool Function() _isCurrent;
  final MailAccountSession _session;

  void dispose() => _session.dispose();

  void _check() {
    if (!_isCurrent()) _session.dispose();
    _session.begin().checkCurrent();
  }

  MailRemoteIdentity _remote(MailRemoteIdentity source) {
    if (source.account != sourceAccount || source.provider != provider) {
      throw const StudioMailMailboxStoreException(
        MailProblemCode.permissionDenied,
      );
    }
    return switch (source) {
      MailImapIdentity(:final mailbox, :final uidValidity, :final uid) =>
        MailImapIdentity(
          mailbox: MailMailboxId(mailbox.value, account: store.account),
          uidValidity: uidValidity,
          uid: uid,
        ),
      MailOpaqueIdentity(:final value) => MailOpaqueIdentity(
        account: store.account,
        provider: provider,
        value: value,
      ),
    };
  }

  MailHeaderRecord _header(MailHeaderRecord source) {
    final remote = _remote(source.remote);
    // Structured, account-independent remote parameters plus the enclosing
    // stable account row identify cached content across reconnects. Message-ID
    // headers, mutable provider projections and numeric UID alone never do.
    final key = jsonEncode([
      'studio-mail-cache-v1',
      provider.name,
      switch (remote) {
        MailImapIdentity(:final mailbox, :final uidValidity, :final uid) => [
          mailbox.value,
          uidValidity,
          uid,
        ],
        MailOpaqueIdentity(:final value) => [value],
      },
    ]);
    return MailHeaderRecord(
      id: MailMessageId(sha256.convert(utf8.encode(key)).toString()),
      remote: remote,
      envelope: source.envelope,
      flags: source.flags,
    );
  }

  Future<void> saveView(
    MailMailbox mailbox,
    List<MailHeaderRecord> headers, {
    required bool hasMore,
  }) async {
    _check();
    if (mailbox.id.account != sourceAccount) {
      throw const StudioMailMailboxStoreException(
        MailProblemCode.permissionDenied,
      );
    }
    final local = MailMailbox(
      id: MailMailboxId(mailbox.id.value, account: store.account),
      displayName: mailbox.displayName,
      isLabel: mailbox.isLabel,
    );
    final mapped = [for (final header in headers) _header(header)];
    await store.saveView(
      local,
      mapped,
      hasMore: hasMore,
      lease: _session.begin(),
    );
    _check();
  }

  Future<void> cacheMessage(
    MailHeaderRecord header,
    MailMessage message,
  ) async {
    _check();
    if (message.remoteIdentity != header.remote ||
        message.localId != null && message.localId != header.id) {
      throw const StudioMailMailboxStoreException(MailProblemCode.conflict);
    }
    final local = _header(header);
    await store.cacheMessage(
      local,
      MailMessage(
        raw: message.raw,
        envelope: message.envelope,
        body: message.body,
        attachments: message.attachments,
        localId: local.id,
        remoteIdentity: local.remote,
      ),
      lease: _session.begin(),
    );
    _check();
  }
}
