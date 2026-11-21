import 'dart:async';
import 'dart:convert';

import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';

import 'studio_mail_draft_store.dart';
import 'studio_mail_local_accounts.dart';
import 'studio_mail_mailbox_store.dart';

/// A result retains its account and exact local/remote identities. RFC
/// Message-ID is deliberately not used for cross-account deduplication.
final class StudioMailCachedSearchHit {
  const StudioMailCachedSearchHit._(this.account, this.result, this._owner);

  final MailLocalAccountRecord account;
  final MailCachedHeaderSearchHit result;
  final Object _owner;

  String get key => jsonEncode([account.id, result.header.id.value]);
}

/// Coverage of saved headers only. Completion never certifies server state,
/// body availability, or unvisited folders. A failed account stays visible.
final class StudioMailCachedSearchCoverage {
  StudioMailCachedSearchCoverage({
    required this.account,
    required this.scannedCount,
    required this.totalCount,
    required this.complete,
    this.problem,
    List<MailCachedMailboxSummary> browsed = const [],
    List<MailMailboxSyncSummary> synchronized = const [],
  }) : browsed = List.unmodifiable(browsed),
       synchronized = List.unmodifiable(synchronized);

  final MailLocalAccountRecord account;
  final int scannedCount;
  final int totalCount;
  final bool complete;
  final MailProblemCode? problem;
  final List<MailCachedMailboxSummary> browsed;
  final List<MailMailboxSyncSummary> synchronized;
}

/// Bounded, sequential discovery across the host's separate account profiles.
///
/// Only one search owner stays open between pages. A message from another
/// account uses one temporary owner, closed before the read completes. Search
/// never loads a draft, requests credentials, contacts a provider, or reads a
/// body. [loadMessage] is a separate explicit local read.
///
/// The caller creates a new session when query/scope changes and immediately
/// invalidates [isCurrent]. [close] fences and drains pending work before
/// releasing ownership. A close failure retains the owner for an explicit
/// retry; it is never silently ignored while opening the next account.
final class StudioMailCachedSearchSession {
  StudioMailCachedSearchSession({
    required this.query,
    required List<MailLocalAccountRecord> accounts,
    required this.directory,
    required this.openStore,
    required this.isCurrent,
  }) : _accounts = List.of(accounts) {
    MailHeaderSearchQuery.parse(query);
    if (_accounts.length > MailLocalAccountDirectory.maxAccounts) {
      _fail(MailProblemCode.quotaExceeded);
    }
    final ids = <String>{};
    for (final record in _accounts) {
      studioMailLocalAccountIdentity(record);
      if (!ids.add(record.id)) _fail(MailProblemCode.conflict);
    }
    _accounts.sort((left, right) => left.id.compareTo(right.id));
  }

  final String query;
  final StudioMailLocalAccountStore directory;
  final StudioMailDraftStoreFactory openStore;
  final bool Function() isCurrent;
  final List<MailLocalAccountRecord> _accounts;
  final Object _identity = Object();
  final Map<String, StudioMailCachedSearchCoverage> _coverage = {};
  int _index = 0;
  MailCachedHeaderSearchCursor? _cursor;
  StudioMailDraftStore? _owner;
  StudioMailMailboxStore? _mailbox;
  StudioMailCachedHeaderSearchStore? _search;
  StudioMailDraftStore? _temporaryOwner;
  Future<void>? _pending;
  Future<void>? _closing;
  bool _closed = false;

  bool get hasMore => !_closed && _index < _accounts.length;

  List<StudioMailCachedSearchCoverage> get coverage => List.unmodifiable([
    for (final record in _accounts) ?_coverage[record.id],
  ]);

  static Never _fail(MailProblemCode code) =>
      throw StudioMailMailboxStoreException(code);

  bool get _current => !_closed && isCurrent();

  void _check() {
    if (!_current) _fail(MailProblemCode.staleOperation);
  }

  Future<T> _work<T>(Future<T> Function() action) async {
    _check();
    if (_pending != null) _fail(MailProblemCode.conflict);
    final operation = Future<T>.sync(action);
    final drained = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    _pending = drained;
    try {
      return await operation;
    } finally {
      if (identical(_pending, drained)) _pending = null;
    }
  }

  Future<StudioMailDraftAccount> _verify(
    MailLocalAccountRecord expected,
  ) async {
    _check();
    final records = await directory.load();
    _check();
    if (records.length > MailLocalAccountDirectory.maxAccounts) {
      _fail(MailProblemCode.quotaExceeded);
    }
    final ids = <String>{};
    for (final record in records) {
      studioMailLocalAccountIdentity(record);
      if (!ids.add(record.id)) _fail(MailProblemCode.conflict);
    }
    final matches = records.where((record) => record.id == expected.id);
    if (matches.length != 1 ||
        !matches.single.hasSameIdentity(expected) ||
        matches.single.revision != expected.revision) {
      _fail(MailProblemCode.conflict);
    }
    return studioMailLocalAccountIdentity(matches.single);
  }

  StudioMailMailboxStore _mailboxFor(
    StudioMailDraftStore owner,
    StudioMailDraftAccount identity,
  ) {
    final mailbox = switch (owner) {
      StudioMailMailboxStoreOwner value => value.mailboxStore,
      _ => null,
    };
    if (mailbox == null) _fail(MailProblemCode.unsupported);
    if (mailbox.account != identity.account) {
      _fail(MailProblemCode.permissionDenied);
    }
    return mailbox;
  }

  Future<void> _releaseOwner() async {
    final owner = _owner;
    if (owner == null) return;
    await owner.close();
    if (identical(owner, _owner)) {
      _owner = null;
      _mailbox = null;
      _search = null;
      _cursor = null;
    }
  }

  Future<void> _releaseTemporary() async {
    final owner = _temporaryOwner;
    if (owner == null) return;
    await owner.close();
    if (identical(owner, _temporaryOwner)) _temporaryOwner = null;
  }

  static MailProblemCode _problem(Object error) => switch (error) {
    StudioMailMailboxStoreException(:final code) => code,
    StudioMailDraftStoreException(:final code) => code,
    _ => MailProblemCode.storageFailure,
  };

  /// Inspects at most [scanLimit] headers from one account and emits at most
  /// [limit] matches. An empty result with [hasMore] is not a completed search.
  /// Account failures are retained in [coverage] and allow the next account.
  Future<List<StudioMailCachedSearchHit>> nextPage({
    int limit = 100,
    int scanLimit = 500,
  }) => _work(() async {
    if (limit < 1 || limit > 100 || scanLimit < 1 || scanLimit > 1000) {
      _fail(MailProblemCode.invalidInput);
    }
    if (_temporaryOwner != null) _fail(MailProblemCode.conflict);
    if (!hasMore) return const [];
    final record = _accounts[_index];
    MailCachedHeaderSearchPage page;
    final int scanned;
    try {
      final identity = await _verify(record);
      if (_owner == null) {
        _owner = await openStore(identity);
        _check();
        final mailbox = _mailboxFor(_owner!, identity);
        if (mailbox is! StudioMailCachedHeaderSearchStore) {
          _fail(MailProblemCode.unsupported);
        }
        _mailbox = mailbox;
        _search = mailbox as StudioMailCachedHeaderSearchStore;
      }
      page = await _search!.searchCachedHeaders(
        query,
        cursor: _cursor,
        limit: limit,
        scanLimit: scanLimit,
      );
      _check();
      await _verify(record);
      _validatePage(page, identity, limit, scanLimit);
      final previous = _coverage[record.id];
      scanned = (previous?.scannedCount ?? 0) + page.scannedCount;
      // A continuation is one unchanged local scan. A malformed optional
      // host adapter must not turn missing candidates into completed coverage
      // or publish hits from a page whose population changed mid-search.
      if ((previous != null && previous.totalCount != page.totalCount) ||
          scanned > page.totalCount ||
          (page.nextCursor == null && scanned != page.totalCount) ||
          (page.nextCursor != null && scanned >= page.totalCount)) {
        _fail(MailProblemCode.conflict);
      }
    } on Object catch (error) {
      // A failed close prevents advancing to another profile. Keep ownership
      // so Close can be retried without acquiring a competing lease.
      await _releaseOwner();
      _check();
      final previous = _coverage[record.id];
      _coverage[record.id] = StudioMailCachedSearchCoverage(
        account: record,
        scannedCount: previous?.scannedCount ?? 0,
        totalCount: previous?.totalCount ?? 0,
        complete: false,
        problem: _problem(error),
        browsed: previous?.browsed ?? const [],
        synchronized: previous?.synchronized ?? const [],
      );
      _index++;
      _cursor = null;
      return const [];
    }
    if (page.nextCursor == null) {
      await _releaseOwner();
      _check();
      _index++;
    } else {
      _cursor = page.nextCursor;
    }
    _coverage[record.id] = StudioMailCachedSearchCoverage(
      account: record,
      scannedCount: scanned,
      totalCount: page.totalCount,
      complete: page.nextCursor == null,
      browsed: page.browsed,
      synchronized: page.synchronized,
    );
    return List.unmodifiable([
      for (final hit in page.hits)
        StudioMailCachedSearchHit._(record, hit, _identity),
    ]);
  });

  void _validatePage(
    MailCachedHeaderSearchPage page,
    StudioMailDraftAccount identity,
    int limit,
    int scanLimit,
  ) {
    if (page.hits.length > limit ||
        page.scannedCount < page.hits.length ||
        page.scannedCount > scanLimit ||
        page.totalCount < page.scannedCount ||
        (page.nextCursor != null && page.scannedCount == 0) ||
        page.browsed.length > 1000 ||
        page.synchronized.length > 1000) {
      _fail(MailProblemCode.conflict);
    }
    final ids = <MailMessageId>{};
    for (final hit in page.hits) {
      if (hit.header.remote.account != identity.account ||
          hit.header.remote.provider != identity.provider ||
          !ids.add(hit.header.id) ||
          hit.folders.isEmpty ||
          hit.folders.any((folder) => folder.id.account != identity.account)) {
        _fail(MailProblemCode.permissionDenied);
      }
    }
    if (page.browsed.any(
          (folder) => folder.mailbox.id.account != identity.account,
        ) ||
        page.synchronized.any(
          (folder) => folder.mailbox.id.account != identity.account,
        )) {
      _fail(MailProblemCode.permissionDenied);
    }
  }

  /// Opens retained bytes only after explicit selection. Revalidates the local
  /// directory before opening a completed account again and rejects a hit from
  /// another query/session. Missing bytes remain a truthful null result.
  Future<MailMessage?> loadMessage(StudioMailCachedSearchHit hit) =>
      _work(() async {
        if (!identical(hit._owner, _identity) || _temporaryOwner != null) {
          _fail(MailProblemCode.conflict);
        }
        final identity = await _verify(hit.account);
        if (hit.result.header.remote.account != identity.account) {
          _fail(MailProblemCode.permissionDenied);
        }
        var mailbox = _mailbox;
        var temporary = false;
        try {
          if (mailbox == null || mailbox.account != identity.account) {
            _temporaryOwner = await openStore(identity);
            temporary = true;
            _check();
            mailbox = _mailboxFor(_temporaryOwner!, identity);
          }
          final message = await mailbox.loadMessage(hit.result.header);
          _check();
          await _verify(hit.account);
          if (message != null &&
              (message.localId != hit.result.header.id ||
                  message.remoteIdentity != hit.result.header.remote)) {
            _fail(MailProblemCode.conflict);
          }
          return message;
        } finally {
          if (temporary) await _releaseTemporary();
        }
      });

  Future<void> close() {
    _closed = true;
    return _closing ??= _drain().whenComplete(() => _closing = null);
  }

  Future<void> _drain() async {
    await _pending;
    // Attempt both independent releases even when one owner reports failure.
    Object? failure;
    StackTrace? failureStack;
    try {
      await _releaseTemporary();
    } on Object catch (error, stack) {
      failure = error;
      failureStack = stack;
    }
    try {
      await _releaseOwner();
    } on Object catch (error, stack) {
      failure ??= error;
      failureStack ??= stack;
    }
    if (failure != null) Error.throwWithStackTrace(failure, failureStack!);
  }
}
