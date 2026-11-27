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

/// Optional bounded discovery over all retained headers in this account.
/// The existing draft owner serializes reads and retains its exclusive lease.
abstract interface class StudioMailCachedHeaderSearchStore {
  MailAccountId get account;
  Future<MailCachedHeaderSearchPage> searchCachedHeaders(
    String query, {
    MailCachedHeaderSearchCursor? cursor,
    int limit = 100,
    int scanLimit = 500,
  });
}

/// Optional local tag/category assignment for retained messages. This is local
/// metadata only; it never writes provider keywords or changes membership.
abstract interface class StudioMailTagStore {
  MailAccountId get account;
  Future<List<MailTag>> loadMessageTags(MailMessageId message);
  Future<List<MailTag>> listMessageTags();
  Future<void> setMessageTags(
    MailMessageId message,
    Iterable<String> tags, {
    MailOperationLease? lease,
  });
}

/// Ordered local rules over retained headers. Rules only change local tags and
/// never contact a provider.
abstract interface class StudioMailRuleStore {
  MailAccountId get account;
  Future<List<MailRule>> listMailRules();
  Future<void> replaceMailRules(
    Iterable<MailRule> rules, {
    MailOperationLease? lease,
  });
  Future<void> setMessageTagsBatch(
    Map<MailMessageId, Iterable<String>> updates, {
    MailOperationLease? lease,
  });
}

/// Published string-ID capability retained for existing hosts. Missing folders
/// fail the legacy query instead of returning partial folder coverage. New
/// hosts can implement [StudioMailFolderScopedHeaderSearchStore] to expose the
/// bounded local catalog and account-bound IDs through the same query engine.
abstract interface class StudioMailScopedHeaderSearchStore
    implements StudioMailCachedHeaderSearchStore {
  Future<MailCachedHeaderSearchPage> searchCachedHeadersInFolders(
    String query, {
    required List<String> folderIds,
    MailCachedHeaderSearchCursor? cursor,
    int limit = 100,
    int scanLimit = 500,
  });
}

/// Optional exact-folder discovery. Older hosts retain account-wide search;
/// callers must never emulate an unsupported explicit scope by broadening it.
abstract interface class StudioMailFolderScopedHeaderSearchStore {
  MailAccountId get account;

  /// Known local folders, including catalog rows without retained headers.
  /// This neither contacts a provider nor reads message bodies or credentials.
  Future<List<MailMailbox>> listSearchFolders();

  Future<MailCachedHeaderSearchPage> searchCachedHeadersInFolders(
    String query, {
    required List<MailMailboxId> mailboxIds,
    MailCachedHeaderSearchCursor? cursor,
    int limit = 100,
    int scanLimit = 500,
  });
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
  return MailHeaderRecord(
    id: studioMailCachedMessageId(source.remote),
    remote: source.remote,
    envelope: source.envelope,
    flags: source.flags,
    conversationId: source.conversationId,
    tags: source.tags,
  );
}

/// Uses the same stable identity for browsed, synchronized and moved headers.
/// Provider-local IDs must be translated before writing into Studio's cache.
MailMessageId studioMailCachedMessageId(MailRemoteIdentity remote) {
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
  return MailMessageId(sha256.convert(utf8.encode(key)).toString());
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
        StudioMailCachedHeaderSearchStore,
        StudioMailScopedHeaderSearchStore,
        StudioMailFolderScopedHeaderSearchStore,
        StudioMailTagStore,
        StudioMailRuleStore,
        StudioMailSyncStore,
        MailSyncSnapshotRepository {
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
  Future<MailCachedHeaderSearchPage> searchCachedHeaders(
    String query, {
    MailCachedHeaderSearchCursor? cursor,
    int limit = 100,
    int scanLimit = 500,
  }) => _serialize(
    () async => _value(
      await _repository.searchCachedHeaders(
        account,
        query,
        cursor: cursor,
        limit: limit,
        scanLimit: scanLimit,
      ),
    ),
  );

  @override
  Future<List<MailTag>> loadMessageTags(MailMessageId message) => _serialize(
    () async => _value(await _repository.loadMessageTags(account, message)),
  );

  @override
  Future<List<MailTag>> listMessageTags() => _serialize(
    () async => _value(await _repository.listMessageTags(account)),
  );

  @override
  Future<void> setMessageTags(
    MailMessageId message,
    Iterable<String> tags, {
    MailOperationLease? lease,
  }) => _serialize(() async {
    _value(
      await _repository.setMessageTags(account, message, tags, lease: lease),
    );
  });

  @override
  Future<List<MailRule>> listMailRules() =>
      _serialize(() async => _value(await _repository.listMailRules(account)));

  @override
  Future<void> replaceMailRules(
    Iterable<MailRule> rules, {
    MailOperationLease? lease,
  }) => _serialize(() async {
    _value(await _repository.replaceMailRules(account, rules, lease: lease));
  });

  @override
  Future<void> setMessageTagsBatch(
    Map<MailMessageId, Iterable<String>> updates, {
    MailOperationLease? lease,
  }) => _serialize(() async {
    _value(
      await _repository.setMessageTagsBatch(account, updates, lease: lease),
    );
  });

  @override
  Future<List<MailMailbox>> listSearchFolders() => _serialize(
    () async => _value(await _repository.listCachedSearchMailboxes(account)),
  );

  @override
  Future<MailCachedHeaderSearchPage> searchCachedHeadersInFolders(
    String query, {
    List<MailMailboxId>? mailboxIds,
    List<String>? folderIds,
    MailCachedHeaderSearchCursor? cursor,
    int limit = 100,
    int scanLimit = 500,
  }) {
    if ((mailboxIds == null) == (folderIds == null)) {
      throw const StudioMailMailboxStoreException(MailProblemCode.invalidInput);
    }
    // Capture the caller's selection before the owner's queue can yield.
    final selected = mailboxIds == null
        ? null
        : List<MailMailboxId>.unmodifiable(mailboxIds);
    final legacy = folderIds == null
        ? null
        : List<String>.unmodifiable(folderIds);
    for (final mailbox in selected ?? const <MailMailboxId>[]) {
      _scope(mailbox.account);
    }
    return _serialize(
      () async => _value(
        await _repository.searchCachedHeaders(
          account,
          query,
          mailboxIds: selected,
          folderIds: legacy,
          cursor: cursor,
          limit: limit,
          scanLimit: scanLimit,
        ),
      ),
    );
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
  Future<MailResult<MailSyncRepositorySnapshot>> readSyncSnapshot(
    MailMailboxId mailbox,
  ) => _sync(mailbox.account, () => _repository.readSyncSnapshot(mailbox));

  @override
  Future<MailResult<MailUnit>> commitSyncPage(
    MailSyncPage page, {
    required MailCursor? expectedCursor,
    required MailOperationLease lease,
  }) => _commitSyncPage(
    page,
    lease,
    (cached) => _repository.commitSyncPage(
      cached,
      expectedCursor: expectedCursor,
      lease: lease,
    ),
  );

  @override
  Future<MailResult<MailUnit>> commitSyncPageWithSnapshot(
    MailSyncPage page, {
    required MailSyncRepositorySnapshot expectedSnapshot,
    required MailOperationLease lease,
  }) => _commitSyncPage(
    page,
    lease,
    (cached) => _repository.commitSyncPageWithSnapshot(
      cached,
      expectedSnapshot: expectedSnapshot,
      lease: lease,
    ),
  );

  Future<MailResult<MailUnit>> _commitSyncPage(
    MailSyncPage page,
    MailOperationLease lease,
    Future<MailResult<MailUnit>> Function(MailSyncPage) write,
  ) => _sync(page.mailbox.account, () async {
    _scope(lease.account);
    lease.checkCurrent();
    final ids = <MailMessageId>{};
    if (page.upserts.any((header) => !ids.add(header.id))) {
      return const MailFailure(MailProblem(MailProblemCode.invalidInput));
    }
    return write(
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

  Future<int> expireMailboxViews(DateTime capturedBefore) => _serialize(
    () async => _value(
      await _repository.expireMailboxViews(
        account,
        capturedBefore: capturedBefore,
        limit: _repository.limits.maxPageSize.clamp(1, 100),
      ),
    ),
  );

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
  MailCancellationSource? _prefetch;
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
    cancelBodyPrefetch();
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
          conversationId: cached.conversationId ?? source.conversationId,
          tags: cached.tags,
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

  Future<MailMessage?> loadMessage(MailHeaderRecord header) async {
    _check();
    final message = await store.loadMessage(_header(header));
    _check();
    if (message == null) return null;
    return MailMessage(
      raw: message.raw,
      envelope: header.envelope,
      body: message.body,
      attachments: message.attachments,
      localId: header.id,
      remoteIdentity: header.remote,
    );
  }

  void cancelBodyPrefetch() {
    _prefetch?.cancel(MailCancellationReason.accountChanged);
    _prefetch = null;
  }

  // Warm the most recent rows without blocking the foreground reader. The
  // smaller per-message limit keeps large attachments out of automatic fetches.
  Future<void> prefetchBodies(
    List<MailHeaderRecord> headers,
    Future<MailResult<MailMessage>> Function(
      MailRemoteIdentity,
      MailReadBudget,
      MailOperationLease,
    )
    fetch,
  ) async {
    if (!_isCurrent() || _session.isDisposed) return;
    cancelBodyPrefetch();
    final cancellation = MailCancellationSource();
    _prefetch = cancellation;
    final session = MailAccountSession(sourceAccount);
    final lease = session.begin(cancellation: cancellation.token);
    const budget = MailReadBudget(
      maxRawBytes: 512 * 1024,
      maxDecodedBytes: 512 * 1024,
      maxBodyBytes: 512 * 1024,
      maxAttachmentBytes: 512 * 1024,
    );
    try {
      for (final header
          in headers.where((entry) => entry.flags?.isDraft != true).take(12)) {
        lease.checkCurrent();
        if (await loadMessage(header) != null) continue;
        lease.checkCurrent();
        final result = await fetch(header.remote, budget, lease);
        lease.checkCurrent();
        switch (result) {
          case MailSuccess(:final value):
            if (value.raw.length <= budget.maxRawBytes) {
              await cacheMessage(
                header,
                value,
                cancellation: cancellation.token,
              );
            }
          case MailFailure(:final problem):
            if (problem.code != MailProblemCode.quotaExceeded) {
              return;
            }
        }
      }
    } on MailCancelled {
      // The view or session was retired while an operation was in flight.
    } on Object {
      // A failed prefetch leaves foreground and explicit downloads available.
    } finally {
      session.dispose();
      if (identical(_prefetch, cancellation)) _prefetch = null;
    }
  }

  Future<void> cacheMessage(
    MailHeaderRecord header,
    MailMessage message, {
    MailCancellationToken? cancellation,
  }) async {
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
      lease: _session.begin(cancellation: cancellation),
    );
    _check();
  }
}
