import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:quds_office_studio/studio_mail_cached_search.dart';
import 'package:quds_office_studio/studio_mail_cached_search_refresh.dart';
import 'package:quds_office_studio/studio_mail_draft.dart';
import 'package:quds_office_studio/studio_mail_draft_store.dart';
import 'package:quds_office_studio/studio_mail_draft_store_native.dart';
import 'package:quds_office_studio/studio_mail_local_accounts.dart';
import 'package:quds_office_studio/studio_mail_mailbox_store.dart';

StudioMailDraftAccount _identity(String sender) => StudioMailDraftAccount(
  provider: 'gmail',
  endpoint: 'https://mail.example.test/gmail',
  login: sender,
  sender: sender,
);

MailHeaderRecord _header(
  StudioMailDraftAccount identity,
  int number, {
  String subject = 'Report',
  bool read = false,
  bool flagged = true,
}) => MailHeaderRecord(
  id: MailMessageId('message-${number.toString().padLeft(4, '0')}'),
  remote: MailOpaqueIdentity(
    account: identity.account,
    provider: identity.provider,
    value: 'message-$number',
  ),
  envelope: MailEnvelope(
    subject: subject,
    from: const [MailAddress('team@example.test')],
    to: [MailAddress(identity.sender)],
    messageId: '<same-rfc-id@example.test>',
  ),
  flags: MailMessageFlags(isRead: read, isFlagged: flagged),
);

Matcher _problem(MailProblemCode code) => isA<StudioMailMailboxStoreException>()
    .having((error) => error.code, 'code', code);

typedef _AfterPage =
    Future<MailCachedHeaderSearchPage> Function(
      MailCachedHeaderSearchPage page,
      int call,
    );

/// Every search reads the actual native SQLite profile. Other ports throw to
/// prove that collecting a refresh cannot read a body or mutate the mailbox.
final class _Mailbox
    implements StudioMailMailboxStore, StudioMailCachedHeaderSearchStore {
  _Mailbox(this.delegate, this.afterPage);

  final StudioMailMailboxStore delegate;
  final _AfterPage? afterPage;
  int calls = 0;
  final limits = <({int limit, int scanLimit})>[];

  @override
  MailAccountId get account => delegate.account;

  @override
  Future<MailCachedHeaderSearchPage> searchCachedHeaders(
    String query, {
    MailCachedHeaderSearchCursor? cursor,
    int limit = 100,
    int scanLimit = 500,
  }) async {
    calls++;
    limits.add((limit: limit, scanLimit: scanLimit));
    final page = await (delegate as StudioMailCachedHeaderSearchStore)
        .searchCachedHeaders(
          query,
          cursor: cursor,
          limit: limit,
          scanLimit: scanLimit,
        );
    return afterPage == null ? page : await afterPage!(page, calls);
  }

  @override
  Future<List<MailCachedMailboxSummary>> listViews() =>
      throw StateError('Refresh must only search headers');

  @override
  Future<MailCachedMailboxView?> loadView(MailMailboxId mailbox) =>
      throw StateError('Refresh must only search headers');

  @override
  Future<MailCachedMailboxView> saveView(
    MailMailbox mailbox,
    List<MailHeaderRecord> headers, {
    required bool hasMore,
    required MailOperationLease lease,
  }) => throw StateError('Refresh must never save mail');

  @override
  Future<void> cacheMessage(
    MailHeaderRecord header,
    MailMessage message, {
    required MailOperationLease lease,
  }) => throw StateError('Refresh must never cache bodies');

  @override
  Future<MailMessage?> loadMessage(MailHeaderRecord header) =>
      throw StateError('Refresh must never load bodies');

  @override
  Future<MailCacheCleanupReport> clearCache() =>
      throw StateError('Refresh must never clear mail');
}

final class _Owner
    implements StudioMailDraftStore, StudioMailMailboxStoreOwner {
  _Owner(this.delegate, _AfterPage? afterPage)
    : mailboxStore = _Mailbox(
        (delegate as StudioMailMailboxStoreOwner).mailboxStore,
        afterPage,
      );

  final StudioMailDraftStore delegate;
  @override
  final _Mailbox mailboxStore;
  int closeCalls = 0;

  @override
  Future<void> close() async {
    closeCalls++;
    await delegate.close();
  }

  @override
  Future<StudioMailStoredDraft?> load() =>
      throw StateError('Refresh must never read drafts');

  @override
  Future<void> save(
    StudioMailDraft draft, {
    required bool submissionUncertain,
  }) => throw StateError('Refresh must never save drafts');

  @override
  Future<void> saveRejectedDraft(
    StudioMailDraft draft, {
    required bool wasPreviouslyUncertain,
  }) => throw StateError('Refresh must never submit mail');

  @override
  Future<void> clear() => throw StateError('Refresh must never clear drafts');
}

void main() {
  late Directory files;
  late NativeStudioMailLocalAccountStore directory;
  final owners = <_Owner>[];
  final sessions = <StudioMailCachedSearchSession>[];
  var sessionCurrent = true;

  setUp(() async {
    files = await Directory.systemTemp.createTemp('mail-search-refresh-');
    directory = NativeStudioMailLocalAccountStore(appDirectory: files);
    sessionCurrent = true;
  });

  tearDown(() async {
    for (final search in sessions) {
      await search.close();
    }
    for (final owner in owners) {
      await owner.delegate.close();
    }
    sessions.clear();
    owners.clear();
    await files.delete(recursive: true);
  });

  Future<void> seed(
    StudioMailDraftAccount identity,
    List<MailHeaderRecord> headers, {
    String folder = 'inbox',
    bool partial = false,
  }) async {
    final owner = await openStudioMailDraftStore(identity, appDirectory: files);
    try {
      final mailbox = (owner as StudioMailMailboxStoreOwner).mailboxStore;
      await mailbox.saveView(
        MailMailbox(
          id: MailMailboxId(folder, account: identity.account),
          displayName: folder,
        ),
        headers,
        hasMore: partial,
        lease: MailAccountSession(identity.account).begin(),
      );
    } finally {
      await owner.close();
    }
    await directory.remember(identity);
  }

  Future<StudioMailDraftStore> open(
    StudioMailDraftAccount identity, {
    _AfterPage? afterPage,
  }) async {
    final owner = _Owner(
      await openStudioMailDraftStore(identity, appDirectory: files),
      afterPage,
    );
    owners.add(owner);
    return owner;
  }

  Future<StudioMailCachedSearchSession> session({
    String query = '',
    StudioMailDraftStoreFactory? factory,
  }) async {
    final search = StudioMailCachedSearchSession(
      query: query,
      accounts: await directory.load(),
      directory: directory,
      openStore: factory ?? open,
      isCurrent: () => sessionCurrent,
    );
    sessions.add(search);
    return search;
  }

  test(
    'fresh refresh replaces changed flags, membership and messages',
    () async {
      final one = _identity('one@example.test');
      final two = _identity('two@example.test');
      await seed(one, [for (var i = 1; i <= 4; i++) _header(one, i)]);
      await seed(two, [_header(two, 1)]);
      final firstSession = await session(query: 'is:unread AND is:flagged');
      final first = await refreshStudioMailCachedSearch(firstSession);
      expect(first.hits, hasLength(5));
      expect(first.hits.map((hit) => hit.key).toSet(), hasLength(5));
      expect(first.complete, isTrue);
      await firstSession.close();

      await seed(one, [
        _header(one, 1, read: true),
        _header(one, 3, flagged: false),
        _header(one, 5),
      ]);
      await seed(one, [_header(one, 4)], folder: 'archive');
      final refreshed = await refreshStudioMailCachedSearch(
        await session(query: 'is:unread AND is:flagged'),
      );
      expect(refreshed.hits, hasLength(3));
      final accountHits = refreshed.hits.where(
        (hit) => hit.account.id == one.account.value,
      );
      expect(
        accountHits.map(
          (hit) => (hit.result.header.remote as MailOpaqueIdentity).value,
        ),
        unorderedEquals(['message-4', 'message-5']),
      );
      final moved = accountHits.singleWhere(
        (hit) =>
            (hit.result.header.remote as MailOpaqueIdentity).value ==
            'message-4',
      );
      expect(moved.result.folders.single.id.value, 'archive');
      expect(refreshed.coverage, hasLength(2));
      expect(refreshed.complete, isTrue);
      expect(refreshed.hasMore, isFalse);
      expect(refreshed.limited, isFalse);
      expect(first.hits, hasLength(5));
      expect(() => refreshed.hits.clear(), throwsUnsupportedError);
      expect(() => refreshed.coverage.clear(), throwsUnsupportedError);
    },
  );

  test(
    'empty matching page continues through the native scan budget',
    () async {
      final identity = _identity('zero-page@example.test');
      await seed(identity, [
        for (var i = 1; i <= 500; i++) _header(identity, i, subject: 'Other'),
        _header(identity, 501, subject: 'Target'),
      ]);
      final batch = await refreshStudioMailCachedSearch(
        await session(query: 'subject:Target'),
      );
      expect(batch.hits.single.result.header.envelope.subject, 'Target');
      expect(batch.pagesRead, 2);
      expect(batch.coverage.single.scannedCount, 501);
      expect(batch.complete, isTrue);
      expect(owners.single.mailboxStore.limits, [
        (limit: 100, scanLimit: 500),
        (limit: 100, scanLimit: 500),
      ]);
    },
  );

  test(
    'page cap reports incomplete scan with no matches, not empty completion',
    () async {
      final identity = _identity('page-cap@example.test');
      await seed(identity, [
        for (var i = 1; i <= 501; i++) _header(identity, i, subject: 'Other'),
      ]);
      final search = await session(query: 'subject:Missing');
      final batch = await refreshStudioMailCachedSearch(search, maxPages: 1);
      expect(batch.hits, isEmpty);
      expect(batch.pagesRead, 1);
      expect(batch.hasMore, isTrue);
      expect(batch.pageLimitReached, isTrue);
      expect(batch.resultLimitReached, isFalse);
      expect(batch.limited, isTrue);
      expect(batch.complete, isFalse);
      expect(batch.hasCoverageProblems, isTrue);
      expect(batch.coverage.single.scannedCount, 500);
      expect(owners.single.closeCalls, 0);
      await search.close();
      expect(owners.single.closeCalls, 1);
    },
  );

  test(
    'result cap never overreads and leaves the supplied session owned',
    () async {
      final identity = _identity('result-cap@example.test');
      await seed(identity, [
        for (var i = 1; i <= 120; i++) _header(identity, i),
      ]);
      final search = await session();
      final batch = await refreshStudioMailCachedSearch(
        search,
        maxResults: 105,
      );
      expect(batch.hits, hasLength(105));
      expect(batch.pagesRead, 2);
      expect(batch.resultLimitReached, isTrue);
      expect(batch.pageLimitReached, isFalse);
      expect(batch.complete, isFalse);
      expect(owners.single.mailboxStore.limits, [
        (limit: 100, scanLimit: 500),
        (limit: 5, scanLimit: 500),
      ]);
      expect(owners.single.closeCalls, 0);
      expect(await search.nextPage(limit: 1), hasLength(1));
      expect(batch.hits, hasLength(105));
      expect(batch.coverage.single.scannedCount, 105);
      await search.close();
      expect(owners.single.closeCalls, 1);
    },
  );

  test('exact completion at both limits remains a complete batch', () async {
    final identity = _identity('exact-cap@example.test');
    await seed(identity, [_header(identity, 1)], partial: true);
    final batch = await refreshStudioMailCachedSearch(
      await session(),
      maxResults: 1,
      maxPages: 1,
    );
    expect(batch.hits, hasLength(1));
    expect(batch.complete, isTrue);
    expect(batch.limited, isFalse);
    // Completion covers retained headers, not the provider's remaining mail.
    expect(batch.coverage.single.browsed.single.hasMore, isTrue);
  });

  test(
    'failed account keeps coverage while a healthy profile completes',
    () async {
      final one = _identity('failed@example.test');
      final two = _identity('healthy@example.test');
      await seed(one, [_header(one, 1)]);
      await seed(two, [_header(two, 1)]);
      final search = await session(
        factory: (identity) async {
          if (identity.account == one.account) {
            throw const StudioMailDraftStoreException(
              MailProblemCode.permissionDenied,
            );
          }
          return open(identity);
        },
      );
      final batch = await refreshStudioMailCachedSearch(search);
      expect(batch.hits.single.account.id, two.account.value);
      expect(batch.coverage, hasLength(2));
      expect(
        batch.coverage
            .singleWhere((row) => row.account.id == one.account.value)
            .problem,
        MailProblemCode.permissionDenied,
      );
      expect(batch.hasMore, isFalse);
      expect(batch.limited, isFalse);
      expect(batch.hasCoverageProblems, isTrue);
      expect(batch.complete, isFalse);
    },
  );

  test(
    'authority loss on a later page removes all earlier account hits',
    () async {
      final one = _identity('first@example.test');
      final two = _identity('second@example.test');
      await seed(one, [for (var i = 1; i <= 101; i++) _header(one, i)]);
      await seed(two, [for (var i = 1; i <= 101; i++) _header(two, i)]);
      final records = await directory.load();
      final ids = records.map((row) => row.id).toList()..sort();
      final failedId = ids.first;
      final removed = records.singleWhere((row) => row.id == failedId);
      final batch = await refreshStudioMailCachedSearch(
        await session(
          factory: (identity) => open(
            identity,
            afterPage: (page, call) async {
              if (identity.account.value == failedId && call == 2) {
                await directory.forget(removed);
              }
              return page;
            },
          ),
        ),
        maxResults: 150,
      );
      expect(batch.hits, hasLength(101));
      expect(batch.hits.every((hit) => hit.account.id != failedId), isTrue);
      expect(batch.pagesRead, 4);
      expect(batch.hasMore, isFalse);
      final failedCoverage = batch.coverage.singleWhere(
        (row) => row.account.id == failedId,
      );
      expect(failedCoverage.scannedCount, 100);
      expect(failedCoverage.problem, MailProblemCode.conflict);
      expect(batch.complete, isFalse);
    },
  );

  test('repeated adapter hit is deduplicated across native pages', () async {
    final identity = _identity('duplicate@example.test');
    await seed(identity, [for (var i = 1; i <= 101; i++) _header(identity, i)]);
    MailCachedHeaderSearchHit? repeated;
    final batch = await refreshStudioMailCachedSearch(
      await session(
        factory: (identity) => open(
          identity,
          afterPage: (page, call) async {
            if (call == 1) {
              repeated = page.hits.first;
              return page;
            }
            return MailCachedHeaderSearchPage(
              hits: [repeated!],
              scannedCount: page.scannedCount,
              totalCount: page.totalCount,
              nextCursor: page.nextCursor,
              browsed: page.browsed,
              synchronized: page.synchronized,
            );
          },
        ),
      ),
    );
    expect(batch.hits, hasLength(100));
    expect(batch.hits.map((hit) => hit.key).toSet(), hasLength(100));
    expect(batch.coverage.single.scannedCount, 101);
    expect(batch.complete, isTrue);
  });

  for (final limits in [
    (pages: 0, results: 1000),
    (pages: -1, results: 1000),
    (pages: 101, results: 1000),
    (pages: 100, results: 0),
    (pages: 100, results: -1),
    (pages: 100, results: 1001),
  ]) {
    test('invalid limits $limits fail before opening profiles', () async {
      final identity = _identity('limits@example.test');
      await seed(identity, [_header(identity, 1)]);
      final search = await session();
      await expectLater(
        refreshStudioMailCachedSearch(
          search,
          maxPages: limits.pages,
          maxResults: limits.results,
        ),
        throwsA(_problem(MailProblemCode.invalidInput)),
      );
      expect(owners, isEmpty);
    });
  }

  test(
    'stale host and session predicates reject before profile reads',
    () async {
      final identity = _identity('stale@example.test');
      await seed(identity, [_header(identity, 1)]);
      final search = await session();
      await expectLater(
        refreshStudioMailCachedSearch(search, isCurrent: () => false),
        throwsA(_problem(MailProblemCode.staleOperation)),
      );
      sessionCurrent = false;
      await expectLater(
        refreshStudioMailCachedSearch(search),
        throwsA(_problem(MailProblemCode.staleOperation)),
      );
      expect(owners, isEmpty);
    },
  );

  test(
    'late cancellation publishes no batch and leaves draining to caller',
    () async {
      final identity = _identity('late@example.test');
      await seed(identity, [
        for (var i = 1; i <= 101; i++) _header(identity, i),
      ]);
      final entered = Completer<void>();
      final proceed = Completer<void>();
      var hostCurrent = true;
      final search = await session(
        factory: (identity) => open(
          identity,
          afterPage: (page, _) async {
            entered.complete();
            await proceed.future;
            return page;
          },
        ),
      );
      final refreshing = refreshStudioMailCachedSearch(
        search,
        isCurrent: () => hostCurrent,
      );
      final rejected = expectLater(
        refreshing,
        throwsA(_problem(MailProblemCode.staleOperation)),
      );
      await entered.future;
      hostCurrent = false;
      proceed.complete();
      await rejected;
      expect(owners.single.mailboxStore.calls, 1);
      expect(owners.single.closeCalls, 0);
      await search.close();
      expect(owners.single.closeCalls, 1);
    },
  );

  test(
    'closed session rejects even when the host scope remains current',
    () async {
      final search = await session();
      expect(search.isActive, isTrue);
      await search.close();
      expect(search.isActive, isFalse);
      expect(sessionCurrent, isTrue);
      await expectLater(
        refreshStudioMailCachedSearch(search),
        throwsA(_problem(MailProblemCode.staleOperation)),
      );
      expect(owners, isEmpty);
    },
  );

  test(
    'closing an in-flight session suppresses its late refresh batch',
    () async {
      final identity = _identity('close-in-flight@example.test');
      await seed(identity, [_header(identity, 1)]);
      final entered = Completer<void>();
      final proceed = Completer<void>();
      final search = await session(
        factory: (identity) => open(
          identity,
          afterPage: (page, _) async {
            entered.complete();
            await proceed.future;
            return page;
          },
        ),
      );
      final refreshing = refreshStudioMailCachedSearch(search);
      final rejected = expectLater(
        refreshing,
        throwsA(_problem(MailProblemCode.staleOperation)),
      );
      await entered.future;
      var drained = false;
      final closing = search.close().then((_) => drained = true);
      expect(search.isActive, isFalse);
      expect(drained, isFalse);
      proceed.complete();
      await rejected;
      await closing;
      expect(drained, isTrue);
      expect(owners.single.mailboxStore.calls, 1);
      expect(owners.single.closeCalls, 1);
    },
  );

  test('empty account scope completes without opening a profile', () async {
    final batch = await refreshStudioMailCachedSearch(await session());
    expect(batch.hits, isEmpty);
    expect(batch.coverage, isEmpty);
    expect(batch.pagesRead, 0);
    expect(batch.complete, isTrue);
    expect(owners, isEmpty);
  });
}
