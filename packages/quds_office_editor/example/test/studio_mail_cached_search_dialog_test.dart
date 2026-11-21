import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_ui/quds_mail_ui.dart';
import 'package:quds_office_studio/studio_mail_cached_search_dialog.dart';
import 'package:quds_office_studio/studio_mail_cached_search_strings.dart';
import 'package:quds_office_studio/studio_mail_draft.dart';
import 'package:quds_office_studio/studio_mail_draft_store.dart';
import 'package:quds_office_studio/studio_mail_local_accounts_dialog.dart';
import 'package:quds_office_studio/studio_mail_mailbox_store.dart';
import 'package:quds_office_studio/studio_strings.dart';

import 'support/mail_local_accounts.dart';
import 'support/mail_outbox_store.dart';

const _strings = StudioStrings(StudioLanguage.en);
const _output = String.fromEnvironment('MAIL_CACHED_SEARCH_SCREENSHOT_DIR');
const _captureKey = ValueKey('saved-mail-search-capture');
final _query = find.byKey(const ValueKey('studio-mail-cached-search-query'));
final _start = find.byKey(const ValueKey('studio-mail-cached-search-start'));
final _more = find.byKey(const ValueKey('studio-mail-cached-search-more'));
final _close = find.byKey(const ValueKey('studio-mail-cached-search-close'));
final _results = find.byKey(
  const ValueKey('studio-mail-cached-search-results'),
);

StudioMailDraftAccount _identity(String name) => StudioMailDraftAccount(
  provider: 'imap',
  endpoint: 'imaps://mail.example.test:993',
  login: '$name@example.test',
  sender: '$name@example.test',
);

MailHeaderRecord _header(
  StudioMailDraftAccount identity,
  int number, {
  String subject = 'Quarterly report',
  String folder = 'Inbox',
  String authorName = 'Author',
}) => MailHeaderRecord(
  id: MailMessageId('$folder-${number.toString().padLeft(5, '0')}'),
  remote: MailImapIdentity(
    mailbox: MailMailboxId(folder, account: identity.account),
    uidValidity: 23,
    uid: number + 1,
  ),
  envelope: MailEnvelope(
    subject: subject,
    from: [MailAddress('author@example.test', displayName: authorName)],
    messageId: '<shared-rfc-id@example.test>',
    sentAt: DateTime.utc(2026, 11, 21, 9),
  ),
  flags: const MailMessageFlags(isRead: false, isFlagged: true),
);

/// Genuine SQLite and production adapters; only account-directory and timing
/// boundaries are controlled. No transport or successful-provider stub exists.
Future<SqliteOutboxFixture> _fixture(
  WidgetTester tester,
  StudioMailDraftAccount identity,
) async {
  final fixture = await awaitOutboxOperation(
    tester,
    SqliteOutboxFixture.create(identity),
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await awaitOutboxOperation(tester, fixture.close());
  });
  return fixture;
}

Future<void> _seed(
  WidgetTester tester,
  SqliteOutboxFixture fixture,
  List<MailHeaderRecord> headers, {
  String folder = 'Inbox',
  bool hasMore = true,
  bool body = false,
}) async {
  final owner = await awaitOutboxOperation(
    tester,
    fixture.open(fixture.identity),
  );
  final store = (owner as StudioMailMailboxStoreOwner).mailboxStore;
  final session = MailAccountSession(fixture.identity.account);
  final lease = session.begin();
  await awaitOutboxOperation(
    tester,
    store.saveView(
      MailMailbox(
        id: MailMailboxId(folder, account: fixture.identity.account),
        displayName: folder,
      ),
      headers,
      hasMore: hasMore,
      lease: lease,
    ),
  );
  if (body) {
    final header = headers.first;
    await awaitOutboxOperation(
      tester,
      store.cacheMessage(
        header,
        MailMessage(
          raw: MailBytes(
            utf8.encode(
              'Subject: ${header.envelope.subject}\r\n\r\nRetained body',
            ),
          ),
          envelope: header.envelope,
          body: const MailBody(
            plainText: 'Retained content available offline.',
          ),
          localId: header.id,
          remoteIdentity: header.remote,
        ),
        lease: lease,
      ),
    );
  }
  await awaitOutboxOperation(tester, owner.close());
  session.dispose();
}

Future<void> _until(WidgetTester tester, bool Function() done) async {
  final timer = Stopwatch()..start();
  while (!done() && timer.elapsed < const Duration(seconds: 15)) {
    await tester.pump(const Duration(milliseconds: 10));
    if (!done()) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1)),
      );
    }
  }
  expect(
    done(),
    isTrue,
    reason: 'The requested local UI operation did not settle.',
  );
  await tester.pump();
}

Future<void> _idle(WidgetTester tester) => _until(
  tester,
  () => find.byType(LinearProgressIndicator).evaluate().isEmpty,
);

Future<void> _press(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pump();
  await tester.tap(target);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

Future<void> _atEnd(WidgetTester tester, Finder target) async {
  for (var count = 0; target.evaluate().isEmpty && count < 40; count++) {
    final scrollable = tester.state<ScrollableState>(
      find.descendant(of: _results, matching: find.byType(Scrollable)).first,
    );
    scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
    await tester.pump();
  }
  expect(target, findsOneWidget);
  await tester.ensureVisible(target);
}

Future<void> _show(
  WidgetTester tester,
  MemoryMailLocalAccounts directory,
  StudioMailDraftStoreFactory open, {
  bool entry = false,
  bool Function()? isCurrent,
  StudioStrings strings = _strings,
  Size size = const Size(1000, 850),
  double scale = 1,
  MailProviderKind? provider,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final direction = strings.language == StudioLanguage.ar
      ? TextDirection.rtl
      : TextDirection.ltr;
  await tester.pumpWidget(
    RepaintBoundary(
      key: _captureKey,
      child: MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff3457a0)),
          fontFamily: strings.language == StudioLanguage.ar
              ? 'SavedSearchArabic'
              : 'SavedSearchLatin',
          fontFamilyFallback: const ['SavedSearchArabic', 'SavedSearchLatin'],
        ),
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
                  textDirection: direction,
                  child: entry
                      ? StudioMailLocalAccountsDialog(
                          strings: strings,
                          store: directory,
                          isCurrent: isCurrent ?? () => true,
                          provider: provider,
                          draftStoreFactory: open,
                        )
                      : StudioMailCachedSearchDialog(
                          strings: strings,
                          store: directory,
                          isCurrent: isCurrent ?? () => true,
                          provider: provider,
                          draftStoreFactory: open,
                        ),
                ),
              ),
              child: const Text('Open saved search'),
            ),
          ),
        ),
      ),
    ),
  );
  await _press(tester, find.text('Open saved search'));
  await _idle(tester);
}

Future<void> _loadFonts() async {
  await (FontLoader('SavedSearchLatin')
        ..addFont(
          rootBundle.load(
            'packages/quds_office_editor/fonts/LiberationSans-Regular.ttf',
          ),
        )
        ..addFont(
          rootBundle.load(
            'packages/quds_office_editor/fonts/LiberationSans-Bold.ttf',
          ),
        ))
      .load();
  await (FontLoader('SavedSearchArabic')
        ..addFont(rootBundle.load('fonts/Tajawal-Regular.ttf'))
        ..addFont(rootBundle.load('fonts/Tajawal-Bold.ttf')))
      .load();
  await (FontLoader(
    'MaterialIcons',
  )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
}

Future<void> _capture(WidgetTester tester, String name) async {
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  if (_output.isEmpty) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureKey),
  );
  await tester.runAsync(() async {
    final directory = await Directory(_output).create(recursive: true);
    final image = await boundary.toImage(pixelRatio: 1.5);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(
        '${directory.path}/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

final class _Owner
    implements StudioMailDraftStore, StudioMailMailboxStoreOwner {
  _Owner(this.delegate);
  final StudioMailDraftStore delegate;
  Completer<void>? closeGate;
  bool failClose = false;
  int closeCalls = 0;

  @override
  StudioMailMailboxStore get mailboxStore =>
      (delegate as StudioMailMailboxStoreOwner).mailboxStore;
  @override
  Future<void> close() async {
    closeCalls++;
    await closeGate?.future;
    if (failClose) throw StateError('private-owner-close-detail');
    await delegate.close();
  }

  @override
  Future<StudioMailStoredDraft?> load() =>
      throw StateError('Search must not read drafts');
  @override
  Future<void> save(
    StudioMailDraft draft, {
    required bool submissionUncertain,
  }) => throw StateError('Search must not write drafts');
  @override
  Future<void> saveRejectedDraft(
    StudioMailDraft draft, {
    required bool wasPreviouslyUncertain,
  }) => throw StateError('Search must not submit mail');
  @override
  Future<void> clear() => throw StateError('Search must not clear drafts');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final warnAboutDatabases = driftRuntimeOptions.dontWarnAboutMultipleDatabases;
  setUpAll(() async {
    // Each fixture creates its own NativeDatabase.memory() executor. Separate
    // account databases are intentional and never share an executor.
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    await _loadFonts();
  });
  tearDownAll(
    () =>
        driftRuntimeOptions.dontWarnAboutMultipleDatabases = warnAboutDatabases,
  );
  testWidgets(
    'saved-account entry and query typing never open an account store',
    (tester) async {
      final identity = _identity('writer');
      final directory = MemoryMailLocalAccounts()..seed(identity);
      var opens = 0;
      await _show(tester, directory, (_) async {
        opens++;
        throw StateError('No implicit open');
      }, entry: true);
      await _press(
        tester,
        find.byKey(const ValueKey('studio-mail-search-saved')),
      );
      await _idle(tester);
      expect(find.byType(StudioMailCachedSearchDialog), findsOneWidget);
      await tester.enterText(_query, 'from:author OR subject:report');
      await tester.pump();
      expect(opens, 0);
      expect(directory.remembered, isEmpty);
      await _press(tester, _close);
      await _until(
        tester,
        () => find.byType(StudioMailCachedSearchDialog).evaluate().isEmpty,
      );
      expect(find.byType(StudioMailLocalAccountsDialog), findsOneWidget);
    },
  );

  testWidgets(
    'open search rejects replaced parent directory, provider, factory and freshness',
    (tester) async {
      for (final replacement in [
        'directory',
        'provider',
        'factory',
        'freshness',
      ]) {
        final originalDirectory = MemoryMailLocalAccounts()
          ..seed(_identity('original'));
        final nextDirectory = MemoryMailLocalAccounts()
          ..seed(_identity('replacement'));
        var directory = originalDirectory;
        MailProviderKind? provider;
        var originalCurrent = true;
        bool isOriginallyCurrent() => originalCurrent;
        bool Function() isCurrent = isOriginallyCurrent;
        var originalOpens = 0;
        var replacementOpens = 0;
        Future<StudioMailDraftStore> openOriginal(
          StudioMailDraftAccount _,
        ) async {
          originalOpens++;
          throw StateError('No stale account open');
        }

        Future<StudioMailDraftStore> openReplacement(
          StudioMailDraftAccount _,
        ) async {
          replacementOpens++;
          throw StateError('No implicit replacement account open');
        }

        StudioMailDraftStoreFactory open = openOriginal;
        final revision = ValueNotifier(0);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => ValueListenableBuilder<int>(
                      valueListenable: revision,
                      builder: (_, _, _) => StudioMailLocalAccountsDialog(
                        strings: _strings,
                        store: directory,
                        provider: provider,
                        isCurrent: isCurrent,
                        draftStoreFactory: open,
                      ),
                    ),
                  ),
                  child: const Text('Open changing accounts'),
                ),
              ),
            ),
          ),
        );
        await _press(tester, find.text('Open changing accounts'));
        await _idle(tester);
        await _press(
          tester,
          find.byKey(const ValueKey('studio-mail-search-saved')),
        );
        await _idle(tester);
        final child = tester.widget<StudioMailCachedSearchDialog>(
          find.byType(StudioMailCachedSearchDialog),
        );
        final staleSearch = tester.widget<FilledButton>(_start).onPressed!;
        final oldLoads = originalDirectory.loads;
        expect(child.isCurrent(), isTrue);
        switch (replacement) {
          case 'directory':
            directory = nextDirectory;
          case 'provider':
            provider = MailProviderKind.imap;
          case 'factory':
            open = openReplacement;
          case 'freshness':
            originalCurrent = false;
            isCurrent = () => true;
        }
        revision.value++;
        await tester.pump();
        // The child route was not rebuilt. Its captured parent context still
        // rejects the stale callback before any directory or account access.
        expect(child.isCurrent(), isFalse, reason: replacement);
        staleSearch();
        await tester.pump();
        expect(originalDirectory.loads, oldLoads, reason: replacement);
        expect(nextDirectory.loads, 0, reason: replacement);
        expect(originalOpens, 0, reason: replacement);
        expect(replacementOpens, 0, reason: replacement);
        await _press(tester, _close);
        await _until(
          tester,
          () => find.byType(StudioMailCachedSearchDialog).evaluate().isEmpty,
        );
        await tester.pumpWidget(const SizedBox.shrink());
        revision.dispose();
      }
    },
  );

  testWidgets(
    'all accounts keep same local IDs distinct and open saved body locally',
    (tester) async {
      final one = _identity('one');
      final two = _identity('two');
      final a = await _fixture(tester, one);
      final b = await _fixture(tester, two);
      await _seed(tester, a, [
        _header(one, 0, subject: 'Report one'),
      ], body: true);
      await _seed(tester, b, [_header(two, 0, subject: 'Report two')]);
      final directory = MemoryMailLocalAccounts()
        ..seed(one)
        ..seed(two);
      final owners = <_Owner>[];
      await _show(tester, directory, (identity) async {
        final owner = _Owner(
          await (identity.account == one.account ? a : b).open(identity),
        );
        owners.add(owner);
        return owner;
      });
      await tester.enterText(_query, 'subject:report');
      await _press(tester, _start);
      await _idle(tester);
      await _atEnd(tester, _more);
      await _press(tester, _more);
      await _idle(tester);
      expect(find.text('Report one'), findsOneWidget);
      expect(find.text('Report two'), findsOneWidget);
      expect(find.textContaining('one@example.test'), findsWidgets);
      expect(find.textContaining('two@example.test'), findsWidgets);
      expect(find.textContaining('Header only'), findsWidgets);
      final stale = tester
          .widget<ListTile>(
            find.ancestor(
              of: find.text('Report one'),
              matching: find.byType(ListTile),
            ),
          )
          .onTap!;
      await _press(tester, find.text('Report one'));
      await _idle(tester);
      final view = tester.widget<MailMessageView>(find.byType(MailMessageView));
      expect(view.controller.decodedText, contains('Retained content'));
      await _press(
        tester,
        find.byKey(const ValueKey('studio-mail-cached-search-back')),
      );
      await tester.enterText(_query, 'different');
      await tester.pump();
      final openCount = owners.length;
      stale();
      await tester.pump();
      expect(owners.length, openCount);
      expect(find.byType(MailMessageView), findsNothing);
      expect(find.text('Report one'), findsNothing);
    },
  );

  testWidgets('invalid Boolean query fails before store acquisition', (
    tester,
  ) async {
    final directory = MemoryMailLocalAccounts()..seed(_identity('writer'));
    var opens = 0;
    await _show(tester, directory, (_) async {
      opens++;
      throw StateError('must not open');
    });
    await tester.enterText(_query, 'from:secret@example.test OR (');
    await _press(tester, _start);
    expect(find.text(_strings.mailCachedSearchInvalid), findsOneWidget);
    expect(opens, 0);
    final error = tester.widget<Text>(
      find.byKey(const ValueKey('studio-mail-cached-search-error')),
    );
    expect(error.data, isNot(contains('secret@example.test')));
  });

  for (final cancel in [false, true]) {
    testWidgets(
      '${cancel ? 'cancel' : 'query edit'} rejects a pending account-open result',
      (tester) async {
        final identity = _identity('delayed');
        final fixture = await _fixture(tester, identity);
        await _seed(tester, fixture, [
          _header(identity, 0, subject: 'Late report'),
        ]);
        final directory = MemoryMailLocalAccounts()..seed(identity);
        final gate = Completer<void>();
        final owners = <_Owner>[];
        await _show(tester, directory, (account) async {
          final owner = _Owner(await fixture.open(account));
          owners.add(owner);
          await gate.future;
          return owner;
        });
        await _press(tester, _start);
        await _until(tester, () => owners.isNotEmpty);
        if (cancel) {
          await _press(
            tester,
            find.byKey(const ValueKey('studio-mail-cached-search-cancel')),
          );
        } else {
          await tester.enterText(_query, 'different');
        }
        gate.complete();
        await _idle(tester);
        expect(find.text('Late report'), findsNothing);
        expect(owners.single.closeCalls, greaterThanOrEqualTo(1));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'single-account scope excludes other accounts and changing it clears results',
    (tester) async {
      final first = _identity('first');
      final second = _identity('second');
      final fixture = await _fixture(tester, second);
      await _seed(tester, fixture, [
        _header(second, 0, subject: 'Scoped report'),
      ]);
      final directory = MemoryMailLocalAccounts()
        ..seed(first)
        ..seed(second);
      final opened = <String>[];
      await _show(tester, directory, (account) async {
        opened.add(account.sender);
        return fixture.open(account);
      });
      final scope = tester.widget<DropdownButtonFormField<String>>(
        find.byKey(const ValueKey('studio-mail-cached-search-scope')),
      );
      scope.onChanged!(second.account.value);
      await tester.pump();
      await _press(tester, _start);
      await _idle(tester);
      expect(opened, [second.sender]);
      expect(find.text('Scoped report'), findsOneWidget);
      tester
          .widget<DropdownButtonFormField<String>>(
            find.byKey(const ValueKey('studio-mail-cached-search-scope')),
          )
          .onChanged!('');
      await tester.pump();
      expect(find.text('Scoped report'), findsNothing);
      expect(opened, [second.sender]);
    },
  );

  testWidgets(
    'zero-hit scan still offers continuation to later saved headers',
    (tester) async {
      final identity = _identity('many');
      final fixture = await _fixture(tester, identity);
      await _seed(tester, fixture, [
        for (var i = 0; i < 501; i++)
          _header(
            identity,
            i,
            subject: i == 500 ? 'Target report' : 'Other mail',
          ),
      ]);
      final directory = MemoryMailLocalAccounts()..seed(identity);
      await _show(tester, directory, fixture.open);
      await tester.enterText(_query, 'subject:Target');
      await _press(tester, _start);
      await _idle(tester);
      expect(find.text(_strings.mailCachedSearchEmptyMore), findsOneWidget);
      expect(find.text('Target report'), findsNothing);
      await _press(tester, _more);
      await _idle(tester);
      expect(find.text('Target report'), findsOneWidget);
      expect(_more, findsNothing);
      await _press(tester, find.text('Target report'));
      await _idle(tester);
      expect(find.text(_strings.mailCachedSearchMissingBody), findsOneWidget);
      expect(find.byType(MailMessageView), findsNothing);
    },
  );

  testWidgets(
    'failed account stays visible while a later account remains searchable',
    (tester) async {
      final ids = [_identity('first'), _identity('second')]
        ..sort((a, b) => a.account.value.compareTo(b.account.value));
      final fixture = await _fixture(tester, ids.last);
      await _seed(tester, fixture, [
        _header(ids.last, 0, subject: 'Available report'),
      ]);
      final directory = MemoryMailLocalAccounts()
        ..seed(ids.first)
        ..seed(ids.last);
      await _show(tester, directory, (account) async {
        if (account.account == ids.first.account) {
          throw StateError('sensitive-account-detail');
        }
        return fixture.open(account);
      });
      await _press(tester, _start);
      await _idle(tester);
      expect(
        find.text(
          '${ids.first.sender}: ${_strings.mailCachedSearchAccountFailed}',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('sensitive-account-detail'), findsNothing);
      await _press(tester, _more);
      await _idle(tester);
      expect(find.text('Available report'), findsOneWidget);
      await _atEnd(
        tester,
        find.byKey(const ValueKey('studio-mail-cached-search-coverage')),
      );
      await _press(
        tester,
        find.byKey(const ValueKey('studio-mail-cached-search-coverage')),
      );
      expect(
        find.text(_strings.mailCachedSearchPartialFolders),
        findsOneWidget,
      );
      expect(find.text(_strings.mailCachedSearchLocalFinished), findsOneWidget);
    },
  );

  testWidgets(
    'Close waits for pending store open and owner release before popping',
    (tester) async {
      final identity = _identity('closing');
      final fixture = await _fixture(tester, identity);
      await _seed(tester, fixture, [_header(identity, 0)]);
      final directory = MemoryMailLocalAccounts()..seed(identity);
      final openGate = Completer<void>();
      final closeGate = Completer<void>();
      _Owner? owner;
      await _show(tester, directory, (account) async {
        owner = _Owner(await fixture.open(account))..closeGate = closeGate;
        await openGate.future;
        return owner!;
      });
      await _press(tester, _start);
      await _until(tester, () => owner != null);
      await _press(tester, _close);
      expect(find.byType(StudioMailCachedSearchDialog), findsOneWidget);
      openGate.complete();
      await _until(tester, () => owner!.closeCalls > 0);
      expect(find.byType(StudioMailCachedSearchDialog), findsOneWidget);
      closeGate.complete();
      await _until(
        tester,
        () => find.byType(StudioMailCachedSearchDialog).evaluate().isEmpty,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('failed Close retains route and allows an explicit retry', (
    tester,
  ) async {
    final identity = _identity('close-retry');
    final fixture = await _fixture(tester, identity);
    await _seed(tester, fixture, [
      for (var i = 0; i < 101; i++) _header(identity, i),
    ]);
    final directory = MemoryMailLocalAccounts()..seed(identity);
    late _Owner owner;
    await _show(
      tester,
      directory,
      (account) async => owner = _Owner(await fixture.open(account)),
    );
    await _press(tester, _start);
    await _idle(tester);
    owner.failClose = true;
    await _press(tester, _close);
    await _idle(tester);
    expect(find.byType(StudioMailCachedSearchDialog), findsOneWidget);
    expect(find.text(_strings.mailCachedSearchCloseFailed), findsOneWidget);
    expect(find.textContaining('private-owner-close-detail'), findsNothing);
    owner.failClose = false;
    await _press(tester, _close);
    await _until(
      tester,
      () => find.byType(StudioMailCachedSearchDialog).evaluate().isEmpty,
    );
    expect(owner.closeCalls, 2);
  });

  testWidgets(
    '1,000-result cap asks for refinement instead of reporting completion',
    (tester) async {
      final identity = _identity('limit');
      final fixture = await _fixture(tester, identity);
      await _seed(tester, fixture, [
        for (var i = 0; i < 700; i++) _header(identity, i),
      ]);
      await _seed(tester, fixture, [
        for (var i = 0; i < 400; i++) _header(identity, i, folder: 'Archive'),
      ], folder: 'Archive');
      final directory = MemoryMailLocalAccounts()..seed(identity);
      await _show(tester, directory, fixture.open);
      await _press(tester, _start);
      await _idle(tester);
      for (var page = 1; page < 10; page++) {
        await _atEnd(tester, _more);
        await _press(tester, _more);
        await _idle(tester);
      }
      final limit = find.byKey(
        const ValueKey('studio-mail-cached-search-limit'),
      );
      await _atEnd(tester, limit);
      expect(find.text(_strings.mailCachedSearchLimit), findsOneWidget);
      expect(_more, findsNothing);
      expect(find.text(_strings.mailCachedSearchLocalFinished), findsNothing);
    },
  );

  testWidgets('directory failure is redacted and never opens account storage', (
    tester,
  ) async {
    final directory = MemoryMailLocalAccounts()..failLoad = true;
    var opens = 0;
    await _show(tester, directory, (_) async {
      opens++;
      throw StateError('must not open');
    });
    expect(find.text(_strings.mailCachedSearchAccountsFailed), findsOneWidget);
    expect(tester.widget<FilledButton>(_start).onPressed, isNull);
    expect(opens, 0);
  });

  for (final loading in [true, false]) {
    testWidgets(
      'directory replacement ${loading ? 'during load' : 'after scope selection'} expires context without stale rows',
      (tester) async {
        final original = _identity('original');
        final replacement = _identity('replacement');
        final oldDirectory = MemoryMailLocalAccounts()..seed(original);
        final newDirectory = MemoryMailLocalAccounts()..seed(replacement);
        final gate = Completer<void>();
        if (loading) oldDirectory.loadGate = gate;
        final directory = ValueNotifier(oldDirectory);
        addTearDown(directory.dispose);
        var opens = 0;
        Future<StudioMailDraftStore> open(StudioMailDraftAccount _) async {
          opens++;
          throw StateError('No implicit account open');
        }

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ValueListenableBuilder<MemoryMailLocalAccounts>(
                valueListenable: directory,
                builder: (_, value, _) => StudioMailCachedSearchDialog(
                  strings: _strings,
                  store: value,
                  isCurrent: () => true,
                  draftStoreFactory: open,
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        if (!loading) {
          await _idle(tester);
          tester
              .widget<DropdownButtonFormField<String>>(
                find.byKey(const ValueKey('studio-mail-cached-search-scope')),
              )
              .onChanged!(original.account.value);
          await tester.pump();
        }
        directory.value = newDirectory;
        await tester.pump();
        if (loading) gate.complete();
        await _idle(tester);
        expect(find.text(_strings.mailCachedSearchExpired), findsOneWidget);
        expect(find.byType(DropdownButtonFormField<String>), findsNothing);
        expect(find.textContaining(original.sender), findsNothing);
        expect(find.textContaining(replacement.sender), findsNothing);
        expect(newDirectory.loads, 0);
        expect(opens, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final language in StudioLanguage.values) {
    testWidgets(
      'compact ${language.name} search help keeps grammar LTR at enlarged text',
      (tester) async {
        final strings = StudioStrings(language);
        final directory = MemoryMailLocalAccounts()..seed(_identity('reader'));
        await _show(
          tester,
          directory,
          (_) async => throw StateError('no explicit search'),
          strings: strings,
          size: const Size(360, 600),
          scale: 1.4,
        );
        await _press(
          tester,
          find.byKey(const ValueKey('studio-mail-cached-search-help')),
        );
        await tester.pump(const Duration(milliseconds: 400));
        final example = find.text('NOT(subject:alerts OR from:newsletter)');
        await tester.ensureVisible(example);
        expect(Directionality.of(tester.element(example)), TextDirection.ltr);
        expect(
          tester.widget<TextField>(_query).textDirection,
          TextDirection.ltr,
        );
        expect(tester.takeException(), isNull);
        await _press(tester, _close);
        await _until(
          tester,
          () => find.byType(StudioMailCachedSearchDialog).evaluate().isEmpty,
        );
      },
    );
  }

  for (final spec in [
    (StudioLanguage.en, false),
    (StudioLanguage.de, false),
    (StudioLanguage.ar, false),
    (StudioLanguage.de, true),
    (StudioLanguage.ar, true),
  ]) {
    final (language, compact) = spec;
    testWidgets(
      'saved-search ${language.name} ${compact ? 'compact' : 'wide'} results render',
      (tester) async {
        final strings = StudioStrings(language);
        final identity = _identity('research');
        final fixture = await _fixture(tester, identity);
        final subject = switch (language) {
          StudioLanguage.en => 'Research notes for the quarterly review',
          StudioLanguage.de => 'Forschungsnotizen für die Quartalsbesprechung',
          StudioLanguage.ar => 'ملاحظات البحث للاجتماع الفصلي',
        };
        final authorName = language == StudioLanguage.ar
            ? 'مؤلف البحث'
            : 'Author';
        await _seed(tester, fixture, [
          _header(identity, 0, subject: subject, authorName: authorName),
          _header(
            identity,
            1,
            subject: switch (language) {
              StudioLanguage.en => 'Updated project schedule',
              StudioLanguage.de => 'Aktualisierter Projektzeitplan',
              StudioLanguage.ar => 'الجدول الزمني المحدّث للمشروع',
            },
          ),
        ], body: true);
        final directory = MemoryMailLocalAccounts()..seed(identity);
        await _show(
          tester,
          directory,
          fixture.open,
          strings: strings,
          size: compact ? const Size(360, 600) : const Size(1000, 850),
          scale: compact ? 1.4 : 1,
        );
        if (compact) {
          await _capture(tester, '${language.name}-compact-form');
        }
        await tester.enterText(_query, 'is:unread');
        await _press(tester, _start);
        await _idle(tester);
        final firstResult = find.ancestor(
          of: find.text(subject),
          matching: find.byType(ListTile),
        );
        // Enlarged compact controls can leave this lazy row unbuilt. Navigate
        // the results as a user would before asserting its sender layout.
        await tester.scrollUntilVisible(
          firstResult,
          150,
          scrollable: find
              .descendant(of: _results, matching: find.byType(Scrollable))
              .first,
        );
        await tester.pump();
        final sender = find.descendant(
          of: firstResult,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Text &&
                widget.data ==
                    '\u2068$authorName\u2069 '
                        '\u2066<author@example.test>\u2069',
          ),
        );
        expect(sender, findsOneWidget);
        final senderText = tester.widget<Text>(sender);
        expect(senderText.textDirection, TextDirection.ltr);
        final paragraph = tester.renderObject<RenderParagraph>(sender);
        final openingBracket = senderText.data!.indexOf('<');
        final closingBracket = senderText.data!.indexOf('>');
        final openingBox = paragraph.getBoxesForSelection(
          TextSelection(
            baseOffset: openingBracket,
            extentOffset: openingBracket + 1,
          ),
        );
        final closingBox = paragraph.getBoxesForSelection(
          TextSelection(
            baseOffset: closingBracket,
            extentOffset: closingBracket + 1,
          ),
        );
        expect(openingBox, hasLength(1));
        expect(closingBox, hasLength(1));
        expect(openingBox.single.direction, TextDirection.ltr);
        expect(closingBox.single.direction, TextDirection.ltr);
        expect(openingBox.single.left, lessThan(closingBox.single.left));
        if (language == StudioLanguage.ar) {
          final nameBoxes = paragraph.getBoxesForSelection(
            TextSelection(baseOffset: 1, extentOffset: 1 + authorName.length),
          );
          expect(
            nameBoxes.any((box) => box.direction == TextDirection.rtl),
            isTrue,
          );
        }
        for (final text in ['Inbox', strings.mailCachedSearchSavedBody]) {
          final field = find.descendant(
            of: firstResult,
            matching: find.text(text),
          );
          expect(field, findsOneWidget);
          expect(
            tester.renderObject<RenderParagraph>(field).didExceedMaxLines,
            isFalse,
          );
          expect(
            tester.getRect(field).bottom,
            lessThanOrEqualTo(tester.getRect(firstResult).bottom),
          );
        }
        await _capture(
          tester,
          '${language.name}-${compact ? 'compact' : 'wide'}-results',
        );
        expect(find.text(subject).hitTestable(), findsOneWidget);
        if (language == StudioLanguage.en && !compact) {
          await _press(tester, find.text(subject));
          await _idle(tester);
          await _capture(tester, 'en-wide-reader');
        }
      },
    );
  }
}
