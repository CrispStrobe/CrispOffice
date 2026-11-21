import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';

/// Optional mailbox access through the already-owned local draft repository.
/// The enclosing draft store retains sole responsibility for closing it.
abstract interface class StudioMailMailboxStoreOwner {
  StudioMailMailboxStore get mailboxStore;
}

/// Optional live repository views. Hosts that supply an in-memory store can
/// continue to expose one-shot reads through [StudioMailMailboxStore].
abstract interface class StudioMailMailboxWatchStore {
  Stream<MailResult<List<MailCachedMailboxSummary>>> watchViews();
  Stream<MailResult<MailCachedMailboxView?>> watchView(MailMailboxId mailbox);
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

  /// Explicit local recovery, bounded to one step. No provider is contacted.
  Future<MailCacheCleanupReport> clearCache();
}

/// Durable synchronization is separate from a saved foreground browse window.
/// The draft owner keeps the same exclusive repository lease for both ports.
abstract interface class StudioMailSyncStore implements MailSyncRepository {
  MailAccountId get account;
  Future<MailResult<MailUnit>> saveSyncMailbox(MailMailbox mailbox);
  Future<MailResult<MailMailboxSyncSnapshot?>> loadSyncMailbox(
    MailMailboxId mailbox, {
    int limit = 100,
    int offset = 0,
  });
  Future<MailResult<List<MailMailboxSyncSummary>>> listSyncMailboxes();
  Stream<MailResult<MailMailboxSyncSnapshot?>> watchSyncMailbox(
    MailMailboxId mailbox, {
    int limit = 100,
    int offset = 0,
  });
  Stream<MailResult<List<MailMailboxSyncSummary>>> watchSyncMailboxes();
}

/// One local ID for a remote message, shared by browse captures and sync pages.
/// The account is the enclosing repository namespace; RFC Message-ID is not an
/// identity. Keeping this encoding unchanged preserves previously cached bodies.
MailHeaderRecord studioMailCachedHeader(MailHeaderRecord source) {
  final remote = source.remote;
  final key = jsonEncode([
    'studio-mail-cache-v1',
    remote.provider.name,
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
final class SqliteStudioMailMailboxStore
    implements
        StudioMailMailboxStore,
        StudioMailMailboxWatchStore,
        StudioMailSyncStore {
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

  Future<MailResult<T>> _sync<T>(
    MailAccountId account,
    Future<MailResult<T>> Function() action,
  ) async {
    try {
      _scope(account);
      return await _serialize(action);
    } on StudioMailMailboxStoreException catch (error) {
      return MailFailure(MailProblem(error.code));
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
      return const MailFailure(MailProblem(MailProblemCode.storageFailure));
    }
  }

  @override
  Future<MailResult<MailUnit>> saveSyncMailbox(MailMailbox mailbox) =>
      _sync(mailbox.id.account, () => _repository.saveMailbox(mailbox));

  @override
  Future<MailResult<MailCursor?>> readCursor(MailMailboxId mailbox) =>
      _sync(mailbox.account, () => _repository.readCursor(mailbox));

  @override
  Future<MailResult<MailUnit>> commitSyncPage(
    MailSyncPage page, {
    required MailCursor? expectedCursor,
    required MailOperationLease lease,
  }) => _sync(page.mailbox.account, () async {
    _scope(lease.account);
    lease.checkCurrent();
    final ids = <MailMessageId>{};
    if (page.upserts.any((header) => !ids.add(header.id))) {
      return const MailFailure(MailProblem(MailProblemCode.invalidInput));
    }
    return _repository.commitSyncPage(
      MailSyncPage(
        mailbox: page.mailbox,
        upserts: [
          for (final header in page.upserts) studioMailCachedHeader(header),
        ],
        tombstones: page.tombstones,
        next: page.next,
        hasMore: page.hasMore,
        resetRequired: page.resetRequired,
        imapRange: page.imapRange,
      ),
      expectedCursor: expectedCursor,
      lease: lease,
    );
  });

  @override
  Future<MailResult<MailMailboxSyncSnapshot?>> loadSyncMailbox(
    MailMailboxId mailbox, {
    int limit = 100,
    int offset = 0,
  }) => _sync(
    mailbox.account,
    () => _repository.loadSyncMailbox(mailbox, limit: limit, offset: offset),
  );

  @override
  Future<MailResult<List<MailMailboxSyncSummary>>> listSyncMailboxes() =>
      _sync(account, () => _repository.listSyncMailboxes(account));

  @override
  Stream<MailResult<MailMailboxSyncSnapshot?>> watchSyncMailbox(
    MailMailboxId mailbox, {
    int limit = 100,
    int offset = 0,
  }) {
    if (mailbox.account != account) {
      return Stream.value(
        const MailFailure(MailProblem(MailProblemCode.permissionDenied)),
      );
    }
    return _repository.watchSyncMailbox(mailbox, limit: limit, offset: offset);
  }

  @override
  Stream<MailResult<List<MailMailboxSyncSummary>>> watchSyncMailboxes() =>
      _repository.watchSyncMailboxes(account);

  @override
  Future<List<MailCachedMailboxSummary>> listViews() => _serialize(
    () async => _value(await _repository.listMailboxViews(account)),
  );

  @override
  Stream<MailResult<List<MailCachedMailboxSummary>>> watchViews() =>
      _repository.watchMailboxViews(account);

  @override
  Stream<MailResult<MailCachedMailboxView?>> watchView(MailMailboxId mailbox) {
    if (mailbox.account != account) {
      return Stream.value(
        const MailFailure(MailProblem(MailProblemCode.permissionDenied)),
      );
    }
    return _repository.watchMailboxView(mailbox);
  }

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

  @override
  Future<MailCacheCleanupReport> clearCache() => _serialize(
    () async => _value(
      await _repository.clearMailboxCache(
        account,
        limit: _repository.limits.maxPageSize < 1000
            ? _repository.limits.maxPageSize
            : 1000,
      ),
    ),
  );
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
  int _windowGeneration = 0;
  MailCachedMailboxView? _savedWindow;
  Map<MailMessageId, MailHeaderRecord> _sources = const {};
  int _projectedRevision = 0;

  void dispose() {
    invalidateView();
    _session.dispose();
  }

  /// Retires this window before a refresh, folder change or subscription close.
  /// Cached rows cannot become remote command identities by themselves.
  void invalidateView() {
    _windowGeneration++;
    _savedWindow = null;
    _sources = const {};
    _projectedRevision = 0;
  }

  MailMailboxId cachedMailboxId(MailMailboxId source) {
    _check();
    if (source.account != sourceAccount) {
      throw const StudioMailMailboxStoreException(
        MailProblemCode.permissionDenied,
      );
    }
    return MailMailboxId(source.value, account: store.account);
  }

  /// Projects persisted metadata only onto this successfully saved window's
  /// original provider identities. A cache from an earlier connection, a
  /// partial membership or a changed IMAP generation cannot authorize actions.
  List<MailHeaderRecord> projectView(MailCachedMailboxView view) {
    _check();
    final saved = _savedWindow;
    if (saved == null ||
        view.mailbox.id != saved.mailbox.id ||
        view.revision < saved.revision ||
        view.revision < _projectedRevision ||
        view.revision > 9007199254740991 ||
        view.headers.length != _sources.length) {
      throw const StudioMailMailboxStoreException(MailProblemCode.conflict);
    }
    final seen = <MailMessageId>{};
    final projected = <MailHeaderRecord>[];
    for (final cached in view.headers) {
      final source = _sources[cached.id];
      if (source == null ||
          !seen.add(cached.id) ||
          cached.remote != _remote(source.remote)) {
        throw const StudioMailMailboxStoreException(MailProblemCode.conflict);
      }
      projected.add(
        MailHeaderRecord(
          id: source.id,
          remote: source.remote,
          envelope: source.envelope,
          flags: cached.flags,
        ),
      );
    }
    _projectedRevision = view.revision;
    return List.unmodifiable(projected);
  }

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
    return studioMailCachedHeader(
      MailHeaderRecord(
        id: source.id,
        remote: remote,
        envelope: source.envelope,
        flags: source.flags,
      ),
    );
  }

  Future<MailCachedMailboxView> saveView(
    MailMailbox mailbox,
    List<MailHeaderRecord> headers, {
    required bool hasMore,
  }) async {
    _check();
    invalidateView();
    final generation = _windowGeneration;
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
    final sourceIds = <MailMessageId>{};
    final sources = <MailMessageId, MailHeaderRecord>{};
    int? uidValidity;
    for (var i = 0; i < mapped.length; i++) {
      if (!sourceIds.add(headers[i].id) || sources.containsKey(mapped[i].id)) {
        throw const StudioMailMailboxStoreException(MailProblemCode.conflict);
      }
      if (headers[i].remote case MailImapIdentity(
        mailbox: final sourceBox,
        uidValidity: final validity,
      )) {
        if (sourceBox != mailbox.id ||
            uidValidity != null && uidValidity != validity) {
          throw const StudioMailMailboxStoreException(MailProblemCode.conflict);
        }
        uidValidity = validity;
      }
      sources[mapped[i].id] = headers[i];
    }
    final saved = await store.saveView(
      local,
      mapped,
      hasMore: hasMore,
      lease: _session.begin(),
    );
    _check();
    if (generation != _windowGeneration ||
        saved.mailbox.id != local.id ||
        saved.revision < 1 ||
        saved.revision > 9007199254740991) {
      throw const StudioMailMailboxStoreException(MailProblemCode.conflict);
    }
    _sources = Map.unmodifiable(sources);
    _savedWindow = saved;
    try {
      projectView(saved);
    } on Object {
      invalidateView();
      rethrow;
    }
    return saved;
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
