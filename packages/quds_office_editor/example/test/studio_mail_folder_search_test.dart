import 'dart:async';
import 'dart:convert';
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

StudioMailDraftAccount _identity(String provider, String sender) =>
    StudioMailDraftAccount(
      provider: provider,
      endpoint: provider == 'imap'
          ? 'imaps://mail.example.test:993'
          : 'https://mail.example.test/$provider',
      login: sender,
      sender: sender,
    );

MailSavedHeaderSearchFolder _folder(
  StudioMailDraftAccount identity,
  String id, {
  String? name,
}) => MailSavedHeaderSearchFolder(
  accountId: identity.account.value,
  mailboxId: id,
  displayName: name,
);

MailHeaderRecord _header(
  StudioMailDraftAccount identity,
  int number, {
  String folder = 'inbox',
}) => MailHeaderRecord(
  id: MailMessageId('message-$number'),
  remote: identity.provider == MailProviderKind.imap
      ? MailImapIdentity(
          mailbox: MailMailboxId(folder, account: identity.account),
          uidValidity: 17,
          uid: number,
        )
      : MailOpaqueIdentity(
          account: identity.account,
          provider: identity.provider,
          value: 'message-$number',
        ),
  envelope: MailEnvelope(
    subject: 'Folder report',
    from: [MailAddress('team@example.test')],
    messageId: '<same-rfc-id@example.test>',
  ),
  flags: const MailMessageFlags(isRead: false),
);

Matcher _problem(MailProblemCode code) => isA<StudioMailMailboxStoreException>()
    .having((error) => error.code, 'code', code);

typedef _CatalogHook =
    Future<List<MailMailbox>> Function(List<MailMailbox> folders);
typedef _PageHook =
    Future<MailCachedHeaderSearchPage> Function(
      MailCachedHeaderSearchPage page,
      int call,
    );

/// The legacy adapter deliberately omits the optional folder capability.
/// All retained reads still execute against the real native SQLite profile.
class _LegacyMailbox
    implements StudioMailMailboxStore, StudioMailCachedHeaderSearchStore {
  _LegacyMailbox(this.delegate);

  final StudioMailMailboxStore delegate;
  int legacyCalls = 0;
  int bodyReads = 0;

  @override
  MailAccountId get account => delegate.account;

  @override
  Future<MailCachedHeaderSearchPage> searchCachedHeaders(
    String query, {
    MailCachedHeaderSearchCursor? cursor,
    int limit = 100,
    int scanLimit = 500,
  }) {
    legacyCalls++;
    return (delegate as StudioMailCachedHeaderSearchStore).searchCachedHeaders(
      query,
      cursor: cursor,
      limit: limit,
      scanLimit: scanLimit,
    );
  }

  @override
  Future<MailMessage?> loadMessage(MailHeaderRecord header) {
    bodyReads++;
    return delegate.loadMessage(header);
  }

  @override
  Future<List<MailCachedMailboxSummary>> listViews() =>
      throw StateError('Folder discovery uses the bounded catalog port');
  @override
  Future<MailCachedMailboxView?> loadView(MailMailboxId mailbox) =>
      throw StateError('Folder discovery does not load a mailbox page');
  @override
  Future<MailCachedMailboxView> saveView(
    MailMailbox mailbox,
    List<MailHeaderRecord> headers, {
    required bool hasMore,
    required MailOperationLease lease,
  }) => throw StateError('Discovery does not mutate messages');
  @override
  Future<void> cacheMessage(
    MailHeaderRecord header,
    MailMessage message, {
    required MailOperationLease lease,
  }) => throw StateError('Discovery does not download bodies');
  @override
  Future<MailCacheCleanupReport> clearCache() =>
      throw StateError('Discovery does not remove mail');
}

final class _FolderMailbox extends _LegacyMailbox
    implements StudioMailFolderScopedHeaderSearchStore {
  _FolderMailbox(super.delegate, {this.catalogHook, this.pageHook});

  final _CatalogHook? catalogHook;
  final _PageHook? pageHook;
  int scopedCalls = 0;
  int catalogCalls = 0;

  @override
  Future<List<MailMailbox>> listSearchFolders() async {
    catalogCalls++;
    final folders = await (delegate as StudioMailFolderScopedHeaderSearchStore)
        .listSearchFolders();
    return catalogHook == null ? folders : await catalogHook!(folders);
  }

  @override
  Future<MailCachedHeaderSearchPage> searchCachedHeadersInFolders(
    String query, {
    required List<MailMailboxId> mailboxIds,
    MailCachedHeaderSearchCursor? cursor,
    int limit = 100,
    int scanLimit = 500,
  }) async {
    scopedCalls++;
    final page = await (delegate as StudioMailFolderScopedHeaderSearchStore)
        .searchCachedHeadersInFolders(
          query,
          mailboxIds: mailboxIds,
          cursor: cursor,
          limit: limit,
          scanLimit: scanLimit,
        );
    return pageHook == null ? page : await pageHook!(page, scopedCalls);
  }
}

/// The already-published scoped port has string IDs and no catalog method.
/// Its old account-wide checkpoint metadata must be checked before filtering.
final class _PublishedMailbox extends _LegacyMailbox
    implements StudioMailScopedHeaderSearchStore {
  _PublishedMailbox(super.delegate, {this.pageHook});

  final _PageHook? pageHook;
  int scopedCalls = 0;

  @override
  Future<MailCachedHeaderSearchPage> searchCachedHeadersInFolders(
    String query, {
    required List<String> folderIds,
    MailCachedHeaderSearchCursor? cursor,
    int limit = 100,
    int scanLimit = 500,
  }) async {
    scopedCalls++;
    final result = await (delegate as StudioMailScopedHeaderSearchStore)
        .searchCachedHeadersInFolders(
          query,
          folderIds: folderIds,
          cursor: cursor,
          limit: limit,
          scanLimit: scanLimit,
        );
    final page = MailCachedHeaderSearchPage(
      hits: result.hits,
      scannedCount: result.scannedCount,
      totalCount: result.totalCount,
      nextCursor: result.nextCursor,
      browsed: await delegate.listViews(),
      synchronized: result.synchronized,
    );
    return pageHook == null ? page : await pageHook!(page, scopedCalls);
  }
}

final class _Owner
    implements StudioMailDraftStore, StudioMailMailboxStoreOwner {
  _Owner(
    this.delegate, {
    bool legacy = false,
    bool published = false,
    _CatalogHook? catalogHook,
    _PageHook? pageHook,
  }) : mailboxStore = legacy
           ? _LegacyMailbox(
               (delegate as StudioMailMailboxStoreOwner).mailboxStore,
             )
           : published
           ? _PublishedMailbox(
               (delegate as StudioMailMailboxStoreOwner).mailboxStore,
               pageHook: pageHook,
             )
           : _FolderMailbox(
               (delegate as StudioMailMailboxStoreOwner).mailboxStore,
               catalogHook: catalogHook,
               pageHook: pageHook,
             );

  final StudioMailDraftStore delegate;
  @override
  final _LegacyMailbox mailboxStore;
  int closeCalls = 0;
  bool failClose = false;

  @override
  Future<void> close() async {
    closeCalls++;
    if (failClose) {
      throw const StudioMailDraftStoreException(MailProblemCode.storageFailure);
    }
    await delegate.close();
  }

  @override
  Future<StudioMailStoredDraft?> load() =>
      throw StateError('Discovery must not load drafts');
  @override
  Future<void> save(
    StudioMailDraft draft, {
    required bool submissionUncertain,
  }) => throw StateError('Discovery must not save drafts');
  @override
  Future<void> saveRejectedDraft(
    StudioMailDraft draft, {
    required bool wasPreviouslyUncertain,
  }) => throw StateError('Discovery must not submit mail');
  @override
  Future<void> clear() => throw StateError('Discovery must not clear drafts');
}

void main() {
  late Directory files;
  late NativeStudioMailLocalAccountStore directory;
  final owners = <_Owner>[];
  final sessions = <StudioMailCachedSearchSession>[];
  var current = true;

  setUp(() async {
    files = await Directory.systemTemp.createTemp('studio-mail-folder-search-');
    directory = NativeStudioMailLocalAccountStore(appDirectory: files);
    current = true;
  });

  tearDown(() async {
    for (final owner in owners) {
      owner.failClose = false;
    }
    for (final session in sessions) {
      await session.close();
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
    String folder,
    List<MailHeaderRecord> headers, {
    String? name,
    bool catalogOnly = false,
    bool cacheBody = false,
  }) async {
    final owner = await openStudioMailDraftStore(identity, appDirectory: files);
    try {
      final mailbox = (owner as StudioMailMailboxStoreOwner).mailboxStore;
      final value = MailMailbox(
        id: MailMailboxId(folder, account: identity.account),
        displayName: name ?? folder,
      );
      if (catalogOnly) {
        expect(
          await (mailbox as StudioMailSyncStore).saveSyncMailbox(value),
          isA<MailSuccess<MailUnit>>(),
        );
      } else {
        final lease = MailAccountSession(identity.account).begin();
        await mailbox.saveView(value, headers, hasMore: false, lease: lease);
        if (cacheBody) {
          for (final header in headers) {
            await mailbox.cacheMessage(
              header,
              MailMessage(
                raw: MailBytes(utf8.encode('Subject: Saved\r\n\r\nSaved body')),
                envelope: header.envelope,
                body: MailBody(plainText: 'Saved body'),
                localId: header.id,
                remoteIdentity: header.remote,
              ),
              lease: lease,
            );
          }
        }
      }
    } finally {
      await owner.close();
    }
    await directory.remember(identity);
  }

  Future<_Owner> open(
    StudioMailDraftAccount identity, {
    bool legacy = false,
    bool published = false,
    _CatalogHook? catalogHook,
    _PageHook? pageHook,
  }) async {
    final owner = _Owner(
      await openStudioMailDraftStore(identity, appDirectory: files),
      legacy: legacy,
      published: published,
      catalogHook: catalogHook,
      pageHook: pageHook,
    );
    owners.add(owner);
    return owner;
  }

  Future<StudioMailCachedSearchSession> session({
    List<MailSavedHeaderSearchFolder>? folders,
    List<MailSavedHeaderSearchFolder>? folderScopes,
    List<MailLocalAccountRecord>? accounts,
    StudioMailDraftStoreFactory? factory,
  }) async {
    final search = StudioMailCachedSearchSession(
      query: '',
      accounts: accounts ?? await directory.load(),
      folders: folders,
      folderScopes: folderScopes,
      directory: directory,
      openStore: factory ?? open,
      isCurrent: () => current,
    );
    sessions.add(search);
    return search;
  }

  for (final provider in ['imap', 'ews', 'gmail', 'graph']) {
    test(
      '$provider exact-folder paging excludes other retained mail',
      () async {
        final identity = _identity(provider, '$provider@example.test');
        await seed(identity, 'inbox', [
          _header(identity, 1),
          _header(identity, 2),
        ]);
        await seed(identity, 'archive', [
          _header(identity, 3, folder: 'archive'),
        ]);
        final selected = [_folder(identity, 'inbox', name: 'Inbox')];
        final search = await session(folders: selected);
        selected.clear();
        final first = await search.nextPage(limit: 1, scanLimit: 1);
        expect(first, hasLength(1));
        expect(search.coverage.single.totalCount, 2);
        expect(search.hasMore, isTrue);
        expect(owners.single.closeCalls, 0);
        final second = await search.nextPage(limit: 1, scanLimit: 1);
        expect(second, hasLength(1));
        expect(search.hasMore, isFalse);
        expect(search.coverage.single.complete, isTrue);
        expect(search.coverage.single.missingMailboxIds, isEmpty);
        expect(
          search.coverage.single.selectedFolders!.single.mailboxId,
          'inbox',
        );
        expect(
          [
            ...first,
            ...second,
          ].expand((hit) => hit.result.folders).map((f) => f.id.value),
          everyElement('inbox'),
        );
        expect(owners.single.mailboxStore.legacyCalls, 0);
        expect(owners.single.mailboxStore.bodyReads, 0);
        expect(owners.single.closeCalls, 1);
      },
    );
  }

  test(
    'selected labels deduplicate locally without merging account identities',
    () async {
      final one = _identity('gmail', 'one@example.test');
      final two = _identity('gmail', 'two@example.test');
      await seed(one, 'inbox', [_header(one, 1)]);
      await seed(one, 'priority', [_header(one, 1)]);
      await seed(two, 'inbox', [_header(two, 1)]);
      final batch = await refreshStudioMailCachedSearch(
        await session(
          folders: [
            _folder(one, 'inbox'),
            _folder(one, 'priority'),
            _folder(two, 'inbox'),
          ],
        ),
      );
      expect(batch.complete, isTrue);
      expect(batch.hits, hasLength(2));
      expect(batch.hits.map((hit) => hit.key).toSet(), hasLength(2));
      expect(
        batch.hits
            .singleWhere((hit) => hit.account.id == one.account.value)
            .result
            .folders,
        hasLength(2),
      );
    },
  );

  test(
    'partial missing scope keeps surviving hits and pauses complete refresh',
    () async {
      final identity = _identity('gmail', 'missing@example.test');
      await seed(identity, 'inbox', [_header(identity, 1)]);
      await seed(identity, 'archive', [_header(identity, 2)]);
      final batch = await refreshStudioMailCachedSearch(
        await session(
          folders: [
            _folder(identity, 'inbox'),
            _folder(identity, 'removed', name: 'Retained display name'),
          ],
        ),
      );
      expect(batch.hits, hasLength(1));
      expect(batch.hits.single.result.folders.single.id.value, 'inbox');
      expect(batch.complete, isFalse);
      expect(batch.hasMore, isFalse);
      expect(batch.hasCoverageProblems, isTrue);
      expect(batch.coverage.single.problem, isNull);
      expect(batch.coverage.single.missingMailboxIds.single.value, 'removed');
      expect(
        batch.coverage.single.selectedFolders!.last.displayName,
        'Retained display name',
      );
    },
  );

  test('entirely missing scope returns no unrelated account mail', () async {
    final identity = _identity('ews', 'missing-all@example.test');
    await seed(identity, 'inbox', [_header(identity, 1)]);
    final search = await session(folders: [_folder(identity, 'absent')]);
    expect(await search.nextPage(), isEmpty);
    expect(search.coverage.single.totalCount, 0);
    expect(search.coverage.single.complete, isFalse);
    expect(search.coverage.single.missingMailboxIds.single.value, 'absent');
  });

  test(
    'catalog includes empty folders and exact whitespace IDs per account',
    () async {
      final one = _identity('gmail', 'one-catalog@example.test');
      final two = _identity('ews', 'two-catalog@example.test');
      await seed(
        one,
        ' inbox ',
        const [],
        name: 'Same name',
        catalogOnly: true,
      );
      await seed(one, 'inbox', [_header(one, 1)], name: 'Same name');
      await seed(two, 'inbox', const [], name: 'Same name', catalogOnly: true);
      final search = await session();
      final catalogs = await search.loadFolderCatalog();
      expect(catalogs, hasLength(2));
      final first = catalogs.singleWhere(
        (item) => item.account.id == one.account.value,
      );
      expect(
        first.folders.map((folder) => folder.id.value),
        unorderedEquals([' inbox ', 'inbox']),
      );
      expect(catalogs.every((item) => item.problem == null), isTrue);
      expect(owners.every((owner) => owner.closeCalls == 1), isTrue);
      expect(
        owners.every((owner) => owner.mailboxStore.legacyCalls == 0),
        isTrue,
      );
      expect(() => first.folders.clear(), throwsUnsupportedError);
      expect(() => catalogs.clear(), throwsUnsupportedError);
      final exact = await session(
        accounts: [first.account],
        folders: [_folder(one, ' inbox ')],
      );
      expect(await exact.nextPage(), isEmpty);
      expect(exact.coverage.single.complete, isTrue);
      expect(exact.coverage.single.missingMailboxIds, isEmpty);
    },
  );

  test(
    'legacy adapters retain all-folder search and refuse explicit scope',
    () async {
      final identity = _identity('imap', 'legacy@example.test');
      await seed(identity, 'inbox', [_header(identity, 1)]);
      final unscoped = await session(
        factory: (identity) => open(identity, legacy: true),
      );
      expect(await unscoped.nextPage(), hasLength(1));
      expect(owners.first.mailboxStore.legacyCalls, 1);
      final scoped = await session(
        folders: [_folder(identity, 'inbox')],
        factory: (identity) => open(identity, legacy: true),
      );
      expect(await scoped.nextPage(), isEmpty);
      expect(scoped.coverage.single.problem, MailProblemCode.unsupported);
      expect(owners.last.mailboxStore.legacyCalls, 0);
      final catalog = await session(
        factory: (identity) => open(identity, legacy: true),
      );
      expect(
        (await catalog.loadFolderCatalog()).single.problem,
        MailProblemCode.unsupported,
      );
    },
  );

  test('invalid exact scopes fail before acquiring any profile', () async {
    final one = _identity('gmail', 'scope-one@example.test');
    final two = _identity('ews', 'scope-two@example.test');
    await seed(one, 'inbox', [_header(one, 1)]);
    await seed(two, 'inbox', [_header(two, 1)]);
    final cases = <List<MailSavedHeaderSearchFolder>>[
      [],
      [_folder(one, 'inbox')],
      [_folder(one, 'inbox'), _folder(one, 'inbox'), _folder(two, 'inbox')],
      [
        _folder(one, 'inbox'),
        const MailSavedHeaderSearchFolder(
          accountId: 'foreign',
          mailboxId: 'inbox',
        ),
      ],
    ];
    for (final folders in cases) {
      await expectLater(
        session(folders: folders),
        throwsA(_problem(MailProblemCode.invalidInput)),
      );
    }
    expect(owners, isEmpty);
  });

  test(
    'catalog failures preserve account provenance and healthy choices',
    () async {
      final one = _identity('gmail', 'bad-catalog@example.test');
      final two = _identity('ews', 'good-catalog@example.test');
      await seed(one, 'inbox', [_header(one, 1)]);
      await seed(two, 'inbox', [_header(two, 1)]);
      final search = await session(
        factory: (identity) =>
            open(identity, legacy: identity.account == one.account),
      );
      final catalogs = await search.loadFolderCatalog();
      final bad = catalogs.singleWhere(
        (item) => item.account.id == one.account.value,
      );
      final good = catalogs.singleWhere(
        (item) => item.account.id == two.account.value,
      );
      expect(bad.problem, MailProblemCode.unsupported);
      expect(bad.folders, isEmpty);
      expect(good.problem, isNull);
      expect(good.folders, hasLength(1));
    },
  );

  test(
    'late account retirement invalidates its earlier folder catalog',
    () async {
      final one = _identity('gmail', 'catalog-first@example.test');
      final two = _identity('ews', 'catalog-second@example.test');
      await seed(one, 'inbox', [_header(one, 1)]);
      await seed(two, 'inbox', [_header(two, 1)]);
      final records = (await directory.load()).toList()
        ..sort((a, b) => a.id.compareTo(b.id));
      final first = records.first;
      final search = await session(
        factory: (identity) => open(
          identity,
          catalogHook: (folders) async {
            if (identity.account.value != first.id) {
              await directory.forget(first);
            }
            return folders;
          },
        ),
      );
      final catalogs = await search.loadFolderCatalog();
      expect(catalogs.first.account.id, first.id);
      expect(catalogs.first.problem, MailProblemCode.conflict);
      expect(catalogs.first.folders, isEmpty);
      expect(catalogs.last.problem, isNull);
    },
  );

  test(
    'catalog close failure retains owner and prevents opening another account',
    () async {
      final one = _identity('gmail', 'close-one@example.test');
      final two = _identity('ews', 'close-two@example.test');
      await seed(one, 'inbox', [_header(one, 1)]);
      await seed(two, 'inbox', [_header(two, 1)]);
      final search = await session(
        factory: (identity) async {
          final owner = await open(identity);
          owner.failClose = true;
          return owner;
        },
      );
      await expectLater(
        search.loadFolderCatalog(),
        throwsA(isA<StudioMailDraftStoreException>()),
      );
      expect(owners, hasLength(1));
      owners.single.failClose = false;
      await search.close();
      expect(owners.single.closeCalls, 2);
    },
  );

  test('close fences an in-flight catalog and drains its sole owner', () async {
    final identity = _identity('gmail', 'late-catalog@example.test');
    await seed(identity, 'inbox', [_header(identity, 1)]);
    final entered = Completer<void>();
    final proceed = Completer<void>();
    final search = await session(
      factory: (identity) => open(
        identity,
        catalogHook: (folders) async {
          entered.complete();
          await proceed.future;
          return folders;
        },
      ),
    );
    final loading = search.loadFolderCatalog();
    final rejected = expectLater(
      loading,
      throwsA(_problem(MailProblemCode.staleOperation)),
    );
    await entered.future;
    var closed = false;
    final closing = search.close().then((_) => closed = true);
    expect(closed, isFalse);
    proceed.complete();
    await rejected;
    await closing;
    expect(owners.single.closeCalls, 1);
    expect(closed, isTrue);
  });

  test('optional adapter cannot inject unselected folder provenance', () async {
    final identity = _identity('gmail', 'wrong-folder@example.test');
    await seed(identity, 'inbox', [_header(identity, 1)]);
    final search = await session(
      folders: [_folder(identity, 'inbox')],
      factory: (identity) => open(
        identity,
        pageHook: (page, _) async => MailCachedHeaderSearchPage(
          hits: [
            MailCachedHeaderSearchHit(
              header: page.hits.single.header,
              folders: [
                MailMailbox(
                  id: MailMailboxId('archive', account: identity.account),
                  displayName: 'Archive',
                ),
              ],
              hasCachedBody: false,
            ),
          ],
          scannedCount: page.scannedCount,
          totalCount: page.totalCount,
          nextCursor: page.nextCursor,
          browsed: page.browsed,
          synchronized: page.synchronized,
        ),
      ),
    );
    expect(await search.nextPage(), isEmpty);
    expect(search.coverage.single.problem, MailProblemCode.permissionDenied);
  });

  test(
    'changed folder availability before final refresh discards stale account hits',
    () async {
      final identity = _identity('gmail', 'refresh-folder-loss@example.test');
      await seed(identity, 'inbox', [_header(identity, 1)]);
      final batch = await refreshStudioMailCachedSearch(
        await session(
          folders: [_folder(identity, 'inbox')],
          factory: (identity) =>
              open(identity, catalogHook: (_) async => const []),
        ),
      );
      expect(batch.hits, isEmpty);
      expect(batch.coverage.single.problem, MailProblemCode.conflict);
      expect(batch.coverage.single.missingMailboxIds.single.value, 'inbox');
      expect(batch.complete, isFalse);
    },
  );

  test('missing result folders prevent opening an old retained body', () async {
    final identity = _identity('gmail', 'reader-folder-loss@example.test');
    await seed(identity, 'inbox', [_header(identity, 1)], cacheBody: true);
    final search = await session(
      folders: [_folder(identity, 'inbox')],
      factory: (identity) => open(identity, catalogHook: (_) async => const []),
    );
    final hit = (await search.nextPage()).single;
    await expectLater(
      search.loadMessage(hit),
      throwsA(_problem(MailProblemCode.conflict)),
    );
    expect(owners.every((owner) => owner.mailboxStore.bodyReads == 0), isTrue);
  });

  test('catalog cannot interrupt an active scoped continuation', () async {
    final identity = _identity('gmail', 'catalog-during-page@example.test');
    await seed(identity, 'inbox', [_header(identity, 1), _header(identity, 2)]);
    final search = await session(folders: [_folder(identity, 'inbox')]);
    expect(await search.nextPage(limit: 1), hasLength(1));
    await expectLater(
      search.loadFolderCatalog(),
      throwsA(_problem(MailProblemCode.conflict)),
    );
    expect(owners, hasLength(1));
    expect(owners.single.closeCalls, 0);
    expect(await search.nextPage(limit: 1), hasLength(1));
  });

  test(
    'native saved-search directory retains missing folders through reopen',
    () async {
      final identity = _identity('gmail', 'saved-folder@example.test');
      await seed(identity, 'inbox', [_header(identity, 1)]);
      final saved = await directory.saveSavedSearch(
        MailSavedHeaderSearch(
          id: 'folder-scope',
          name: 'Project mail',
          query: '',
          accountIds: [identity.account.value],
          folders: [
            _folder(identity, 'inbox'),
            _folder(identity, 'missing', name: 'Old name'),
          ],
        ),
      );
      final reopened = NativeStudioMailLocalAccountStore(appDirectory: files);
      final restored = (await reopened.loadSavedSearches()).single;
      expect(restored.revision, saved.revision);
      expect(restored.folders, saved.folders);
      expect(restored.folders!.last.displayName, 'Old name');
      await reopened.deleteSavedSearch(
        restored.id,
        expectedRevision: restored.revision,
      );
      final search = await session(folders: [_folder(identity, 'inbox')]);
      expect(await search.nextPage(), hasLength(1));
    },
  );

  test(
    'published scoped adapters keep exact queries without a catalog port',
    () async {
      final identity = _identity('gmail', 'published-port@example.test');
      await seed(identity, 'inbox', [_header(identity, 1)]);
      await seed(identity, 'archive', [_header(identity, 2)]);
      final search = await session(
        folderScopes: [_folder(identity, 'inbox')],
        factory: (identity) => open(identity, published: true),
      );
      final batch = await refreshStudioMailCachedSearch(search);
      expect(batch.complete, isTrue);
      expect(batch.hits, hasLength(1));
      expect(batch.coverage.single.browsed.single.mailbox.id.value, 'inbox');
      expect(
        owners.every((owner) => owner.mailboxStore.legacyCalls == 0),
        isTrue,
      );
      expect(await search.loadMessage(batch.hits.single), isNull);
      final missing = await session(
        folderScopes: [_folder(identity, 'gone')],
        factory: (identity) => open(identity, published: true),
      );
      expect(await missing.nextPage(), isEmpty);
      expect(missing.coverage.single.problem, MailProblemCode.unavailable);
    },
  );

  test(
    'new folder path requires its declared missing-aware capability',
    () async {
      final identity = _identity('ews', 'published-only@example.test');
      await seed(identity, 'inbox', [_header(identity, 1)]);
      final search = await session(
        folders: [_folder(identity, 'inbox')],
        factory: (identity) => open(identity, published: true),
      );
      expect(await search.nextPage(), isEmpty);
      expect(search.coverage.single.problem, MailProblemCode.unsupported);
      expect((owners.single.mailboxStore as _PublishedMailbox).scopedCalls, 0);
    },
  );

  test(
    'foreign legacy coverage cannot disappear behind selected-folder filtering',
    () async {
      final identity = _identity('gmail', 'foreign-legacy@example.test');
      final foreign = _identity('gmail', 'foreign-other@example.test');
      await seed(identity, 'inbox', [_header(identity, 1)]);
      final search = await session(
        folderScopes: [_folder(identity, 'inbox')],
        factory: (identity) => open(
          identity,
          published: true,
          pageHook: (page, _) async => MailCachedHeaderSearchPage(
            hits: page.hits,
            scannedCount: page.scannedCount,
            totalCount: page.totalCount,
            nextCursor: page.nextCursor,
            browsed: [
              ...page.browsed,
              MailCachedMailboxSummary(
                mailbox: MailMailbox(
                  id: MailMailboxId('unselected', account: foreign.account),
                  displayName: 'Foreign metadata',
                ),
                revision: 1,
                capturedAt: DateTime.utc(2026, 11, 22),
                headerCount: 1,
                hasMore: false,
              ),
            ],
            synchronized: page.synchronized,
          ),
        ),
      );
      expect(await search.nextPage(), isEmpty);
      expect(search.coverage.single.problem, MailProblemCode.permissionDenied);
    },
  );

  test(
    'ambiguous scope aliases fail before reads or queued native work',
    () async {
      final identity = _identity('imap', 'ambiguous-scope@example.test');
      await seed(identity, 'inbox', [_header(identity, 1)]);
      final folders = [_folder(identity, 'inbox')];
      await expectLater(
        session(folders: folders, folderScopes: folders),
        throwsA(_problem(MailProblemCode.invalidInput)),
      );
      expect(owners, isEmpty);
      final raw = await openStudioMailDraftStore(identity, appDirectory: files);
      try {
        final mailbox =
            (raw as StudioMailMailboxStoreOwner).mailboxStore
                as SqliteStudioMailMailboxStore;
        expect(
          () => mailbox.searchCachedHeadersInFolders(''),
          throwsA(_problem(MailProblemCode.invalidInput)),
        );
        expect(
          () => mailbox.searchCachedHeadersInFolders(
            '',
            folderIds: ['inbox'],
            mailboxIds: [MailMailboxId('inbox', account: identity.account)],
          ),
          throwsA(_problem(MailProblemCode.invalidInput)),
        );
      } finally {
        await raw.close();
      }
    },
  );
}
