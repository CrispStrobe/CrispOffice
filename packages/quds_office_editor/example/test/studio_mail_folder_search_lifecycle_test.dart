import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:quds_office_studio/studio_mail_cached_search_dialog.dart';
import 'package:quds_office_studio/studio_mail_cached_search_strings.dart';
import 'package:quds_office_studio/studio_mail_draft.dart';
import 'package:quds_office_studio/studio_mail_draft_store.dart';
import 'package:quds_office_studio/studio_mail_mailbox_store.dart';
import 'package:quds_office_studio/studio_mail_saved_searches.dart';
import 'package:quds_office_studio/studio_mail_search_folder_strings.dart';
import 'package:quds_office_studio/studio_strings.dart';

import 'support/mail_local_accounts.dart';
import 'support/mail_outbox_store.dart';

const _strings = StudioStrings(StudioLanguage.en);
Finder _key(String suffix) => find.byKey(ValueKey('studio-mail-$suffix'));

final class _Control {
  int pages = 0;
  int bodies = 0;
  bool failSecondPage = false;
  bool removeFoldersAfterPage = false;
}

/// Every query runs through genuine SQLite. Only later-page failure and the
/// current local catalog observation are controlled at the optional host port.
final class _Mailbox
    implements
        StudioMailMailboxStore,
        StudioMailCachedHeaderSearchStore,
        StudioMailFolderScopedHeaderSearchStore {
  _Mailbox(this.delegate, this.control);

  final StudioMailMailboxStore delegate;
  final _Control control;

  @override
  MailAccountId get account => delegate.account;

  @override
  Future<List<MailMailbox>> listSearchFolders() async {
    final folders = await (delegate as StudioMailFolderScopedHeaderSearchStore)
        .listSearchFolders();
    return control.removeFoldersAfterPage && control.pages > 0
        ? const []
        : folders;
  }

  @override
  Future<MailCachedHeaderSearchPage> searchCachedHeadersInFolders(
    String query, {
    required List<MailMailboxId> mailboxIds,
    MailCachedHeaderSearchCursor? cursor,
    int limit = 100,
    int scanLimit = 500,
  }) async {
    control.pages++;
    if (control.failSecondPage && control.pages == 2) {
      throw const StudioMailMailboxStoreException(MailProblemCode.conflict);
    }
    return (delegate as StudioMailFolderScopedHeaderSearchStore)
        .searchCachedHeadersInFolders(
          query,
          mailboxIds: mailboxIds,
          cursor: cursor,
          limit: limit,
          scanLimit: scanLimit,
        );
  }

  @override
  Future<MailCachedHeaderSearchPage> searchCachedHeaders(
    String query, {
    MailCachedHeaderSearchCursor? cursor,
    int limit = 100,
    int scanLimit = 500,
  }) => throw StateError('Explicit folder search must never widen its scope');

  @override
  Future<MailMessage?> loadMessage(MailHeaderRecord header) {
    control.bodies++;
    throw StateError('These search paths must not load bodies');
  }

  @override
  Future<List<MailCachedMailboxSummary>> listViews() =>
      throw StateError('Use the explicit catalog port');
  @override
  Future<MailCachedMailboxView?> loadView(MailMailboxId mailbox) =>
      throw StateError('Search must not open mailbox views');
  @override
  Future<MailCachedMailboxView> saveView(
    MailMailbox mailbox,
    List<MailHeaderRecord> headers, {
    required bool hasMore,
    required MailOperationLease lease,
  }) => throw StateError('Search must not save mail');
  @override
  Future<void> cacheMessage(
    MailHeaderRecord header,
    MailMessage message, {
    required MailOperationLease lease,
  }) => throw StateError('Search must not cache bodies');
  @override
  Future<MailCacheCleanupReport> clearCache() =>
      throw StateError('Search must not clear mail');
}

final class _Owner
    implements StudioMailDraftStore, StudioMailMailboxStoreOwner {
  _Owner(this.delegate, _Control control)
    : mailboxStore = _Mailbox(
        (delegate as StudioMailMailboxStoreOwner).mailboxStore,
        control,
      );

  final StudioMailDraftStore delegate;
  @override
  final _Mailbox mailboxStore;
  @override
  Future<void> close() => delegate.close();
  @override
  Future<StudioMailStoredDraft?> load() =>
      throw StateError('Search must not load drafts');
  @override
  Future<void> save(
    StudioMailDraft draft, {
    required bool submissionUncertain,
  }) => throw StateError('Search must not save drafts');
  @override
  Future<void> saveRejectedDraft(
    StudioMailDraft draft, {
    required bool wasPreviouslyUncertain,
  }) => throw StateError('Search must not submit mail');
  @override
  Future<void> clear() => throw StateError('Search must not clear drafts');
}

/// A fixed saved-definition catalog; tests exercise reads, never persistence.
final class _SavedSearches implements StudioMailSavedSearchStore {
  _SavedSearches(this.search);
  final MailSavedHeaderSearch search;
  @override
  Future<List<MailSavedHeaderSearch>> loadSavedSearches() async => [search];
  @override
  Future<MailSavedHeaderSearch> saveSavedSearch(
    MailSavedHeaderSearch search, {
    int? expectedRevision,
  }) => throw StateError('This test must not save search definitions');
  @override
  Future<void> deleteSavedSearch(String id, {required int expectedRevision}) =>
      throw StateError('This test must not delete search definitions');
}

Future<void> _idle(WidgetTester tester) async {
  final elapsed = Stopwatch()..start();
  while (find.byType(LinearProgressIndicator).evaluate().isNotEmpty &&
      elapsed.elapsed < const Duration(seconds: 15)) {
    await tester.pump(const Duration(milliseconds: 10));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1)),
    );
  }
  expect(find.byType(LinearProgressIndicator), findsNothing);
  await tester.pump();
}

Future<void> _press(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pump();
  await tester.tap(target);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

Future<SqliteOutboxFixture> _show(
  WidgetTester tester,
  _Control control, {
  int messages = 1,
  bool missingFolder = false,
}) async {
  final identity = StudioMailDraftAccount(
    provider: 'imap',
    endpoint: 'imaps://mail.example.test:993',
    login: 'reader@example.test',
    sender: 'reader@example.test',
  );
  final fixture = await awaitOutboxOperation(
    tester,
    SqliteOutboxFixture.create(identity),
  );
  await tester.binding.setSurfaceSize(const Size(1100, 1000));
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await awaitOutboxOperation(tester, fixture.close());
    await tester.binding.setSurfaceSize(null);
  });
  final seed = await awaitOutboxOperation(tester, fixture.open(identity));
  final mailbox = (seed as StudioMailMailboxStoreOwner).mailboxStore;
  for (final folder in ['Inbox', 'Other']) {
    final id = MailMailboxId(folder, account: identity.account);
    await awaitOutboxOperation(
      tester,
      mailbox.saveView(
        MailMailbox(id: id, displayName: folder),
        [
          for (
            var index = 1;
            index <= (folder == 'Inbox' ? messages : 1);
            index++
          )
            MailHeaderRecord(
              id: MailMessageId('$folder-$index'),
              remote: MailImapIdentity(
                mailbox: id,
                uidValidity: 23,
                uid: index,
              ),
              envelope: MailEnvelope(
                subject: folder == 'Inbox'
                    ? 'Surviving message'
                    : 'Unselected message',
                from: const [MailAddress('author@example.test')],
              ),
              flags: const MailMessageFlags(isRead: false),
            ),
        ],
        hasMore: false,
        lease: MailAccountSession(identity.account).begin(),
      ),
    );
  }
  await awaitOutboxOperation(tester, seed.close());
  final saved = MailSavedHeaderSearch(
    id: 'scoped',
    name: 'Scoped search',
    query: '',
    accountIds: [identity.account.value],
    folders: [
      MailSavedHeaderSearchFolder(
        accountId: identity.account.value,
        mailboxId: 'Inbox',
      ),
      if (missingFolder)
        MailSavedHeaderSearchFolder(
          accountId: identity.account.value,
          mailboxId: 'Gone',
        ),
    ],
    revision: 1,
  );
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => StudioMailCachedSearchDialog(
                strings: _strings,
                store: MemoryMailLocalAccounts()..seed(identity),
                savedSearchStore: _SavedSearches(saved),
                draftStoreFactory: (identity) async =>
                    _Owner(await fixture.open(identity), control),
                isCurrent: () => true,
              ),
            ),
            child: const Text('Open search'),
          ),
        ),
      ),
    ),
  );
  await _press(tester, find.text('Open search'));
  await _idle(tester);
  await _press(tester, _key('saved-search-picker'));
  await _press(tester, find.text('Scoped search').last);
  await _idle(tester);
  return fixture;
}

Future<void> _more(WidgetTester tester) async {
  final target = _key('cached-search-more');
  final scroller = find
      .descendant(
        of: _key('cached-search-results'),
        matching: find.byType(Scrollable),
      )
      .first;
  for (var attempt = 0; target.evaluate().isEmpty && attempt < 40; attempt++) {
    final state = tester.state<ScrollableState>(scroller);
    state.position.jumpTo(state.position.maxScrollExtent);
    await tester.pump();
  }
  expect(target, findsOneWidget);
  await _press(tester, target);
  await _idle(tester);
  tester.state<ScrollableState>(scroller).position.jumpTo(0);
  await tester.pump();
}

void main() {
  setUp(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  testWidgets(
    'later scoped-page failure removes earlier displayed account hits',
    (tester) async {
      final control = _Control()..failSecondPage = true;
      await _show(tester, control, messages: 101);
      expect(find.text(_strings.mailCachedSearchMatches(100)), findsOneWidget);
      expect(control.pages, 1);
      await _more(tester);
      expect(control.pages, 2);
      expect(find.text(_strings.mailCachedSearchMatches(0)), findsOneWidget);
      expect(find.text('Surviving message'), findsNothing);
      expect(
        find.textContaining(_strings.mailCachedSearchAccountFailed),
        findsWidgets,
      );
      expect(control.bodies, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'scoped manual completion rechecks folder availability before publication',
    (tester) async {
      final control = _Control()..removeFoldersAfterPage = true;
      final fixture = await _show(tester, control);
      expect(control.pages, 1);
      expect(find.text(_strings.mailCachedSearchMatches(0)), findsOneWidget);
      expect(find.text('Surviving message'), findsNothing);
      expect(
        _key('cached-search-missing-folders-${fixture.identity.account.value}'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<SwitchListTile>(_key('cached-search-auto-refresh'))
            .onChanged,
        isNull,
      );
      expect(control.bodies, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'missing-only scope preserves healthy selected results and stays incomplete',
    (tester) async {
      final control = _Control();
      final fixture = await _show(tester, control, missingFolder: true);
      expect(find.text(_strings.mailCachedSearchMatches(1)), findsOneWidget);
      expect(find.text('Unselected message'), findsNothing);
      expect(
        _key('cached-search-missing-folders-${fixture.identity.account.value}'),
        findsOneWidget,
      );
      expect(
        find.textContaining(_strings.mailCachedSearchAccountFailed),
        findsNothing,
      );
      expect(
        find.textContaining(_strings.mailSearchFolderMissing),
        findsOneWidget,
      );
      expect(
        tester
            .widget<SwitchListTile>(_key('cached-search-auto-refresh'))
            .onChanged,
        isNull,
      );
      await tester.scrollUntilVisible(
        find.text('Surviving message'),
        250,
        scrollable: find
            .descendant(
              of: _key('cached-search-results'),
              matching: find.byType(Scrollable),
            )
            .first,
        maxScrolls: 10,
      );
      expect(find.text('Surviving message'), findsOneWidget);
      expect(control.bodies, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
