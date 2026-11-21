import 'dart:async';
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
import 'package:quds_office_studio/studio_mail_saved_searches.dart';
import 'package:quds_office_studio/studio_mail_saved_search_strings.dart';
import 'package:quds_office_studio/studio_strings.dart';

import 'support/mail_local_accounts.dart';
import 'support/mail_outbox_store.dart';

const _strings = StudioStrings(StudioLanguage.en);
Finder _key(String suffix) => find.byKey(ValueKey('studio-mail-$suffix'));

StudioMailDraftAccount _identity(String login) => StudioMailDraftAccount(
  provider: 'imap',
  endpoint: 'imaps://mail.example.test:993',
  login: '$login@example.test',
  sender: '$login@example.test',
);

/// Timing/failure injection wraps actual native saved-search persistence.
final class _SavedStore implements StudioMailSavedSearchStore {
  _SavedStore(this.native);
  final NativeStudioMailLocalAccountStore native;
  Completer<void>? saveGate;
  bool failSave = false;
  int saves = 0;

  @override
  Future<List<MailSavedHeaderSearch>> loadSavedSearches() =>
      native.loadSavedSearches();

  @override
  Future<MailSavedHeaderSearch> saveSavedSearch(
    MailSavedHeaderSearch search, {
    int? expectedRevision,
  }) async {
    saves++;
    await saveGate?.future;
    if (failSave) {
      throw const StudioMailDraftStoreException(MailProblemCode.storageFailure);
    }
    return native.saveSavedSearch(search, expectedRevision: expectedRevision);
  }

  @override
  Future<void> deleteSavedSearch(String id, {required int expectedRevision}) =>
      native.deleteSavedSearch(id, expectedRevision: expectedRevision);
}

final class _Fixture {
  _Fixture(this.directory, this.native, this.saved, this.mail, this.path);
  final MemoryMailLocalAccounts directory;
  final NativeStudioMailLocalAccountStore native;
  final _SavedStore saved;
  final SqliteOutboxFixture mail;
  final Directory path;
  final opened = <String>[];

  Future<StudioMailDraftStore> open(StudioMailDraftAccount account) {
    opened.add(account.account.value);
    return mail.open(account);
  }
}

Future<_Fixture> _fixture(WidgetTester tester) async {
  final identity = _identity('alice');
  final path = await awaitOutboxOperation(
    tester,
    Directory.systemTemp.createTemp('saved-search-dialog-'),
  );
  final native = NativeStudioMailLocalAccountStore(appDirectory: path);
  await awaitOutboxOperation(tester, native.remember(identity));
  final mail = await awaitOutboxOperation(
    tester,
    SqliteOutboxFixture.create(identity),
  );
  final fixture = _Fixture(
    MemoryMailLocalAccounts()..seed(identity),
    native,
    _SavedStore(native),
    mail,
    path,
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await awaitOutboxOperation(tester, mail.close());
    await awaitOutboxOperation(tester, path.delete(recursive: true));
  });
  await _seed(tester, fixture, 1);
  return fixture;
}

Future<void> _seed(WidgetTester tester, _Fixture fixture, int count) async {
  final identity = fixture.mail.identity;
  final owner = await awaitOutboxOperation(tester, fixture.mail.open(identity));
  final mailbox = (owner as StudioMailMailboxStoreOwner).mailboxStore;
  final folder = MailMailboxId('Inbox', account: identity.account);
  final session = MailAccountSession(identity.account);
  await awaitOutboxOperation(
    tester,
    mailbox.saveView(
      MailMailbox(id: folder, displayName: 'Inbox'),
      [
        for (var index = 1; index <= count; index++)
          MailHeaderRecord(
            id: MailMessageId('message-$index'),
            remote: MailImapIdentity(
              mailbox: folder,
              uidValidity: 23,
              uid: index,
            ),
            envelope: MailEnvelope(
              subject: 'Report $index',
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
  for (
    var i = 0;
    i < 500 && find.byType(LinearProgressIndicator).evaluate().isNotEmpty;
    i++
  ) {
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

Future<void> _show(
  WidgetTester tester,
  _Fixture fixture, {
  StudioStrings strings = _strings,
  Size size = const Size(1000, 900),
  double scale = 1,
  MailProviderKind? provider,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: (_) => Directionality(
                textDirection: strings.language == StudioLanguage.ar
                    ? TextDirection.rtl
                    : TextDirection.ltr,
                child: StudioMailCachedSearchDialog(
                  strings: strings,
                  store: fixture.directory,
                  savedSearchStore: fixture.saved,
                  draftStoreFactory: fixture.open,
                  provider: provider,
                  isCurrent: () => true,
                ),
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

Future<void> _name(
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
}

Future<void> _choose(WidgetTester tester, String name) async {
  await _press(tester, _key('saved-search-picker'));
  await _press(tester, find.text(name).last);
  await _idle(tester);
}

Future<MailSavedHeaderSearch> _saveDirect(
  WidgetTester tester,
  _Fixture fixture, {
  String name = 'Reports',
}) => awaitOutboxOperation(
  tester,
  fixture.native.saveSavedSearch(
    MailSavedHeaderSearch(
      id: 'reports',
      name: name,
      query: 'subject:Report is:unread',
      accountIds: [fixture.mail.identity.account.value],
    ),
  ),
);

void main() {
  setUp(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);

  testWidgets(
    'save and reopen runs current headers without adding new accounts',
    (tester) async {
      final fixture = await _fixture(tester);
      await _show(tester, fixture);
      await tester.enterText(
        _key('cached-search-query'),
        'subject:Report is:unread',
      );
      await _name(tester, 'Reports');
      await _idle(tester);
      expect(find.text(_strings.mailSavedSearchSaved), findsOneWidget);
      final saved = (await awaitOutboxOperation(
        tester,
        fixture.native.loadSavedSearches(),
      )).single;
      expect(saved.accountIds, [fixture.mail.identity.account.value]);
      await _press(tester, _key('cached-search-close'));
      await _seed(tester, fixture, 2);
      final added = _identity('new-account');
      fixture.directory.seed(added);
      await awaitOutboxOperation(tester, fixture.native.remember(added));
      await _press(tester, find.text('Open search'));
      await _idle(tester);
      fixture.opened.clear();
      await _choose(tester, 'Reports');
      expect(find.text(_strings.mailCachedSearchMatches(2)), findsOneWidget);
      expect(fixture.opened, [fixture.mail.identity.account.value]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('update renames criteria and delete leaves retained messages', (
    tester,
  ) async {
    final fixture = await _fixture(tester);
    final old = await _saveDirect(tester, fixture);
    await _show(tester, fixture);
    await _choose(tester, 'Reports');
    await tester.enterText(_key('cached-search-query'), 'subject:Report');
    await _name(tester, 'All reports', update: true);
    await _idle(tester);
    final updated = (await awaitOutboxOperation(
      tester,
      fixture.native.loadSavedSearches(),
    )).single;
    expect(updated.id, old.id);
    expect(updated.name, 'All reports');
    expect(updated.query, 'subject:Report');
    expect(updated.revision, greaterThan(old.revision));
    await _press(tester, _key('saved-search-delete'));
    await _press(
      tester,
      find.widgetWithText(FilledButton, _strings.mailSavedSearchDelete),
    );
    await _idle(tester);
    expect(
      await awaitOutboxOperation(tester, fixture.native.loadSavedSearches()),
      isEmpty,
    );
    await _press(tester, _key('cached-search-start'));
    await _idle(tester);
    expect(find.text(_strings.mailCachedSearchMatches(1)), findsOneWidget);
    expect(fixture.directory.records, hasLength(1));
  });

  testWidgets('missing saved account never widens to an available account', (
    tester,
  ) async {
    final fixture = await _fixture(tester);
    await _saveDirect(tester, fixture);
    await _show(tester, fixture);
    fixture.directory.records.clear();
    fixture.directory.seed(_identity('different'));
    await _choose(tester, 'Reports');
    expect(find.text(_strings.mailSavedSearchMissingAccounts), findsOneWidget);
    expect(fixture.opened, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed second directory load stops saved-search acquisition', (
    tester,
  ) async {
    final fixture = await _fixture(tester);
    await _saveDirect(tester, fixture);
    await _show(tester, fixture);
    fixture.directory.failLoad = true;
    await _choose(tester, 'Reports');
    expect(find.text(_strings.mailCachedSearchAccountsFailed), findsOneWidget);
    expect(fixture.opened, isEmpty);
    expect(fixture.directory.loads, 2);
  });

  testWidgets('provider-filtered route refuses an unavailable saved scope', (
    tester,
  ) async {
    final fixture = await _fixture(tester);
    await _saveDirect(tester, fixture);
    await _show(tester, fixture, provider: MailProviderKind.ews);
    await _choose(tester, 'Reports');
    expect(find.text(_strings.mailSavedSearchMissingAccounts), findsOneWidget);
    expect(fixture.opened, isEmpty);
  });

  testWidgets('editing while saved accounts refresh fences the old choice', (
    tester,
  ) async {
    final fixture = await _fixture(tester);
    await _saveDirect(tester, fixture);
    await _show(tester, fixture);
    fixture.directory.loadGate = Completer<void>();
    await _press(tester, _key('saved-search-picker'));
    await _press(tester, find.text('Reports').last);
    await tester.enterText(_key('cached-search-query'), 'subject:Different');
    fixture.directory.loadGate!.complete();
    await _idle(tester);
    expect(fixture.opened, isEmpty);
    expect(
      tester.widget<TextField>(_key('cached-search-query')).controller!.text,
      'subject:Different',
    );
  });

  testWidgets('invalid query cannot be saved and does not open a profile', (
    tester,
  ) async {
    final fixture = await _fixture(tester);
    await _show(tester, fixture);
    await tester.enterText(_key('cached-search-query'), 'subject:');
    await _press(tester, _key('saved-search-save'));
    expect(find.text(_strings.mailCachedSearchInvalid), findsOneWidget);
    expect(_key('saved-search-name'), findsNothing);
    expect(fixture.saved.saves, 0);
    expect(fixture.opened, isEmpty);
  });

  testWidgets('failed save announces no success and can be retried', (
    tester,
  ) async {
    final fixture = await _fixture(tester);
    fixture.saved.failSave = true;
    await _show(tester, fixture);
    await _name(tester, 'Reports');
    await _idle(tester);
    expect(find.text(_strings.mailSavedSearchWriteFailed), findsOneWidget);
    expect(find.text(_strings.mailSavedSearchSaved), findsNothing);
    expect(
      await awaitOutboxOperation(tester, fixture.native.loadSavedSearches()),
      isEmpty,
    );
    fixture.saved.failSave = false;
    await _name(tester, 'Reports');
    await _idle(tester);
    expect(
      (await awaitOutboxOperation(
        tester,
        fixture.native.loadSavedSearches(),
      )).single.name,
      'Reports',
    );
  });

  testWidgets(
    'stale update refuses overwrite until refreshed definition selected',
    (tester) async {
      final fixture = await _fixture(tester);
      final first = await _saveDirect(tester, fixture);
      await _show(tester, fixture);
      await _choose(tester, 'Reports');
      await awaitOutboxOperation(
        tester,
        fixture.native.saveSavedSearch(
          first.copyWith(name: 'Newer reports'),
          expectedRevision: first.revision,
        ),
      );
      await _name(tester, 'Stale overwrite', update: true);
      await _idle(tester);
      expect(find.text(_strings.mailSavedSearchConflict), findsOneWidget);
      expect(
        (await awaitOutboxOperation(
          tester,
          fixture.native.loadSavedSearches(),
        )).single.name,
        'Newer reports',
      );
      await _press(tester, _key('saved-search-reload'));
      await _idle(tester);
      expect(_key('saved-search-update'), findsNothing);
      await _choose(tester, 'Newer reports');
      await _name(tester, 'Reviewed reports', update: true);
      await _idle(tester);
      expect(
        (await awaitOutboxOperation(
          tester,
          fixture.native.loadSavedSearches(),
        )).single.name,
        'Reviewed reports',
      );
    },
  );

  testWidgets('close drains pending persistence before leaving the route', (
    tester,
  ) async {
    final fixture = await _fixture(tester);
    fixture.saved.saveGate = Completer<void>();
    await _show(tester, fixture);
    await _name(tester, 'Reports');
    expect(fixture.saved.saves, 1);
    await _press(tester, _key('cached-search-close'));
    expect(find.byType(StudioMailCachedSearchDialog), findsOneWidget);
    fixture.saved.saveGate!.complete();
    await _idle(tester);
    await tester.pumpAndSettle();
    expect(find.byType(StudioMailCachedSearchDialog), findsNothing);
    expect(
      (await awaitOutboxOperation(
        tester,
        fixture.native.loadSavedSearches(),
      )).single.name,
      'Reports',
    );
    expect(tester.takeException(), isNull);
  });

  for (final language in StudioLanguage.values) {
    testWidgets(
      'saved controls remain usable with enlarged ${language.name} chrome',
      (tester) async {
        final fixture = await _fixture(tester);
        final strings = StudioStrings(language);
        await _show(
          tester,
          fixture,
          strings: strings,
          size: const Size(440, 850),
          scale: 1.5,
        );
        await _name(
          tester,
          language == StudioLanguage.ar ? 'تقارير العمل' : 'Reports',
        );
        await _idle(tester);
        expect(find.text(strings.mailSavedSearchSaved), findsOneWidget);
        await _press(tester, _key('cached-search-start'));
        await _idle(tester);
        expect(find.text(strings.mailCachedSearchMatches(1)), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
