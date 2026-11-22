import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_office_studio/studio_mail_cached_search_dialog.dart';
import 'package:quds_office_studio/studio_mail_cached_search_strings.dart';
import 'package:quds_office_studio/studio_mail_draft_store.dart';
import 'package:quds_office_studio/studio_mail_local_accounts.dart';
import 'package:quds_office_studio/studio_mail_mailbox_store.dart';
import 'package:quds_office_studio/studio_mail_search_folder_strings.dart';
import 'package:quds_office_studio/studio_strings.dart';

import 'support/mail_local_accounts.dart';
import 'support/mail_outbox_store.dart';

const _strings = StudioStrings(StudioLanguage.en);
Finder _key(String suffix) => find.byKey(ValueKey('studio-mail-$suffix'));

StudioMailDraftAccount _identity() => StudioMailDraftAccount(
  provider: 'imap',
  endpoint: 'imaps://mail.example.test:993',
  login: 'alice@example.test',
  sender: 'alice@example.test',
);

final class _Fixture {
  _Fixture(this.path, this.native, this.directory, this.mail);
  final Directory path;
  final NativeStudioMailLocalAccountStore native;
  final MemoryMailLocalAccounts directory;
  final SqliteOutboxFixture mail;

  String get accountId => mail.identity.account.value;
  Finder folder(String id) => _key('folder-${jsonEncode([accountId, id])}');
}

Future<_Fixture> _fixture(WidgetTester tester) async {
  final identity = _identity();
  final path = await awaitOutboxOperation(
    tester,
    Directory.systemTemp.createTemp('folder-search-dialog-'),
  );
  final native = NativeStudioMailLocalAccountStore(appDirectory: path);
  await awaitOutboxOperation(tester, native.remember(identity));
  final mail = await awaitOutboxOperation(
    tester,
    SqliteOutboxFixture.create(identity),
  );
  final fixture = _Fixture(
    path,
    native,
    MemoryMailLocalAccounts()..seed(identity),
    mail,
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await awaitOutboxOperation(tester, mail.close());
    await awaitOutboxOperation(tester, path.delete(recursive: true));
  });
  await _seed(tester, fixture, 'Inbox');
  await _seed(tester, fixture, 'Projects');
  return fixture;
}

Future<void> _seed(WidgetTester tester, _Fixture fixture, String folder) async {
  final identity = fixture.mail.identity;
  final owner = await awaitOutboxOperation(tester, fixture.mail.open(identity));
  final mailbox = (owner as StudioMailMailboxStoreOwner).mailboxStore;
  final folderId = MailMailboxId(folder, account: identity.account);
  final session = MailAccountSession(identity.account);
  await awaitOutboxOperation(
    tester,
    mailbox.saveView(
      MailMailbox(id: folderId, displayName: folder),
      [
        MailHeaderRecord(
          id: MailMessageId('$folder-message'),
          remote: MailImapIdentity(mailbox: folderId, uidValidity: 23, uid: 1),
          envelope: MailEnvelope(
            subject: '$folder report',
            from: const [MailAddress('author@example.test')],
          ),
          flags: const MailMessageFlags(isRead: false, isFlagged: true),
        ),
      ],
      hasMore: false,
      lease: session.begin(),
    ),
  );
  await awaitOutboxOperation(tester, owner.close());
  session.dispose();
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

Future<void> _press(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

Future<void> _show(WidgetTester tester, _Fixture fixture) async {
  await tester.binding.setSurfaceSize(const Size(1100, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: (_) => StudioMailCachedSearchDialog(
                strings: _strings,
                store: fixture.directory,
                savedSearchStore: fixture.native,
                draftStoreFactory: fixture.mail.open,
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
}

Future<void> _openFolders(WidgetTester tester) async {
  await _press(tester, _key('cached-search-choose-folders'));
  await _idle(tester);
  expect(_key('folder-picker'), findsOneWidget);
}

Future<void> _chooseInbox(WidgetTester tester, _Fixture fixture) async {
  await _openFolders(tester);
  if (tester.widget<SwitchListTile>(_key('folder-all')).value) {
    await _press(tester, _key('folder-all'));
  }
  await _press(tester, fixture.folder('Inbox'));
  await _press(tester, _key('folder-apply'));
  await _idle(tester);
}

Future<void> _save(
  WidgetTester tester,
  String name, {
  bool update = false,
}) async {
  await _press(
    tester,
    _key(update ? 'saved-search-update' : 'saved-search-save'),
  );
  await tester.enterText(_key('saved-search-name'), name);
  await _press(tester, _key('saved-search-confirm'));
  await _idle(tester);
}

Future<void> _chooseSaved(WidgetTester tester, String name) async {
  await _press(tester, _key('saved-search-picker'));
  await _press(tester, find.text(name).last);
  await _idle(tester);
}

Future<void> _search(WidgetTester tester) async {
  await _press(tester, _key('cached-search-start'));
  await _idle(tester);
}

Future<void> _revealResult(WidgetTester tester, String subject) async {
  final results = _key('cached-search-results');
  final scrollable = find.descendant(
    of: results,
    matching: find.byType(Scrollable),
  );
  await tester.scrollUntilVisible(
    find.text(subject),
    250,
    scrollable: scrollable.first,
    maxScrolls: 15,
  );
  await tester.pump();
}

void main() {
  setUp(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  testWidgets('choose save and reopen keeps exact folders as new ones appear', (
    tester,
  ) async {
    final fixture = await _fixture(tester);
    await _show(tester, fixture);
    await tester.enterText(_key('cached-search-query'), 'subject:report');
    await _chooseInbox(tester, fixture);
    await _search(tester);
    expect(find.text('Inbox report'), findsOneWidget);
    expect(find.text('Projects report'), findsNothing);
    expect(find.text(_strings.mailCachedSearchMatches(1)), findsOneWidget);
    await _save(tester, 'Inbox reports');
    final reopenedStore = NativeStudioMailLocalAccountStore(
      appDirectory: fixture.path,
    );
    final saved = (await awaitOutboxOperation(
      tester,
      reopenedStore.loadSavedSearches(),
    )).single;
    expect(saved.query, 'subject:report');
    expect(saved.accountIds, [fixture.accountId]);
    expect(saved.folders, [
      MailSavedHeaderSearchFolder(
        accountId: fixture.accountId,
        mailboxId: 'Inbox',
      ),
    ]);
    expect(saved.folders!.single.displayName, 'Inbox');
    await _press(tester, _key('cached-search-close'));
    await _seed(tester, fixture, 'Later');
    await _press(tester, find.text('Open search'));
    await _idle(tester);
    await _chooseSaved(tester, 'Inbox reports');
    await _revealResult(tester, 'Inbox report');
    expect(find.text('Inbox report'), findsOneWidget);
    expect(find.text('Projects report'), findsNothing);
    expect(find.text('Later report'), findsNothing);
    expect(find.text(_strings.mailCachedSearchMatches(1)), findsOneWidget);
    expect(
      tester.widget<Text>(_key('cached-search-folder-scope')).data,
      _strings.mailSearchFolderCount(1),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing saved folder never widens and can be repaired durably', (
    tester,
  ) async {
    final fixture = await _fixture(tester);
    final initial = await awaitOutboxOperation(
      tester,
      fixture.native.saveSavedSearch(
        MailSavedHeaderSearch(
          id: 'missing-projects',
          name: 'Missing projects',
          query: 'subject:report',
          accountIds: [fixture.accountId],
          folders: [
            MailSavedHeaderSearchFolder(
              accountId: fixture.accountId,
              mailboxId: 'Gone',
              displayName: 'Projects before migration',
            ),
          ],
        ),
      ),
    );
    await _show(tester, fixture);
    await _chooseSaved(tester, 'Missing projects');
    expect(find.text('Inbox report'), findsNothing);
    expect(find.text('Projects report'), findsNothing);
    expect(find.text(_strings.mailCachedSearchMatches(0)), findsOneWidget);
    expect(
      _key('cached-search-missing-folders-${fixture.accountId}'),
      findsOneWidget,
    );
    await _openFolders(tester);
    expect(
      tester.widget<CheckboxListTile>(fixture.folder('Gone')).value,
      isTrue,
    );
    expect(find.text(_strings.mailSearchFolderUnavailable), findsOneWidget);
    await _press(tester, fixture.folder('Gone'));
    expect(tester.widget<FilledButton>(_key('folder-apply')).onPressed, isNull);
    await _press(tester, fixture.folder('Inbox'));
    await _press(tester, _key('folder-apply'));
    await _idle(tester);
    await _search(tester);
    await _revealResult(tester, 'Inbox report');
    expect(find.text('Inbox report'), findsOneWidget);
    expect(find.text('Projects report'), findsNothing);
    expect(
      _key('cached-search-missing-folders-${fixture.accountId}'),
      findsNothing,
    );
    await _save(tester, 'Repaired projects', update: true);
    final saved = (await awaitOutboxOperation(
      tester,
      fixture.native.loadSavedSearches(),
    )).single;
    expect(saved.id, initial.id);
    expect(saved.revision, greaterThan(initial.revision));
    expect(saved.folders!.single.mailboxId, 'Inbox');
    await _press(tester, _key('cached-search-close'));
    await _press(tester, find.text('Open search'));
    await _idle(tester);
    await _chooseSaved(tester, 'Repaired projects');
    await _revealResult(tester, 'Inbox report');
    expect(find.text('Inbox report'), findsOneWidget);
    expect(find.text('Projects report'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'cancelling a changed chooser preserves the query and folder set',
    (tester) async {
      final fixture = await _fixture(tester);
      await _show(tester, fixture);
      await tester.enterText(_key('cached-search-query'), 'subject:report');
      await _chooseInbox(tester, fixture);
      await _search(tester);
      await _openFolders(tester);
      await _press(tester, fixture.folder('Inbox'));
      await _press(tester, fixture.folder('Projects'));
      await _press(tester, _key('folder-cancel'));
      await _idle(tester);
      expect(
        tester.widget<TextField>(_key('cached-search-query')).controller!.text,
        'subject:report',
      );
      expect(
        tester.widget<Text>(_key('cached-search-folder-scope')).data,
        _strings.mailSearchFolderCount(1),
      );
      await _search(tester);
      expect(find.text('Inbox report'), findsOneWidget);
      expect(find.text('Projects report'), findsNothing);
      await _save(tester, 'Cancelled replacement');
      expect(
        (await awaitOutboxOperation(
          tester,
          fixture.native.loadSavedSearches(),
        )).single.folders!.single.mailboxId,
        'Inbox',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('explicit all-folders update restores legacy scope durably', (
    tester,
  ) async {
    final fixture = await _fixture(tester);
    await _show(tester, fixture);
    await tester.enterText(_key('cached-search-query'), 'subject:report');
    await _chooseInbox(tester, fixture);
    await _save(tester, 'Reports');
    await _openFolders(tester);
    await _press(tester, _key('folder-all'));
    await _press(tester, _key('folder-apply'));
    await _idle(tester);
    await _save(tester, 'Reports', update: true);
    final saved = (await awaitOutboxOperation(
      tester,
      fixture.native.loadSavedSearches(),
    )).single;
    expect(saved.folders, isNull);
    expect(saved.accountIds, [fixture.accountId]);
    await _search(tester);
    await _revealResult(tester, 'Projects report');
    expect(find.text('Inbox report'), findsOneWidget);
    expect(find.text('Projects report'), findsOneWidget);
    expect(find.text(_strings.mailCachedSearchMatches(2)), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
