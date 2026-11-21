import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:quds_mail_ui/quds_mail_ui.dart';
import 'package:quds_office_studio/studio_mail_cached_search_dialog.dart';
import 'package:quds_office_studio/studio_mail_cached_search_strings.dart';
import 'package:quds_office_studio/studio_mail_draft.dart';
import 'package:quds_office_studio/studio_mail_draft_store.dart';
import 'package:quds_office_studio/studio_mail_mailbox_store.dart';
import 'package:quds_office_studio/studio_strings.dart';

import 'support/mail_local_accounts.dart';
import 'support/mail_outbox_store.dart';

const _strings = StudioStrings(StudioLanguage.en);
final _query = find.byKey(const ValueKey('studio-mail-cached-search-query'));
final _start = find.byKey(const ValueKey('studio-mail-cached-search-start'));
final _more = find.byKey(const ValueKey('studio-mail-cached-search-more'));
final _refresh = find.byKey(
  const ValueKey('studio-mail-cached-search-refresh'),
);
final _auto = find.byKey(
  const ValueKey('studio-mail-cached-search-auto-refresh'),
);
final _close = find.byKey(const ValueKey('studio-mail-cached-search-close'));

StudioMailDraftAccount _identity(String name) => StudioMailDraftAccount(
  provider: 'imap',
  endpoint: 'imaps://mail.example.test:993',
  login: '$name@example.test',
  sender: '$name@example.test',
);

MailHeaderRecord _header(
  StudioMailDraftAccount identity,
  int number, {
  required String subject,
  bool read = false,
  bool flagged = false,
  String folder = 'Inbox',
}) => MailHeaderRecord(
  id: MailMessageId('$folder-${number.toString().padLeft(5, '0')}'),
  remote: MailImapIdentity(
    mailbox: MailMailboxId(folder, account: identity.account),
    uidValidity: 23,
    uid: number + 1,
  ),
  envelope: MailEnvelope(
    subject: subject,
    from: [MailAddress('author@example.test')],
    messageId: '<shared-rfc-id@example.test>',
    sentAt: DateTime.utc(2026, 11, 21, 9),
  ),
  flags: MailMessageFlags(isRead: read, isFlagged: flagged),
);

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

/// Replace the real saved browse membership, preserving retained body bytes.
Future<void> _seed(
  WidgetTester tester,
  SqliteOutboxFixture fixture,
  List<MailHeaderRecord> headers, {
  String folder = 'Inbox',
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
      hasMore: false,
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
              'Subject: ${header.envelope.subject}\r\n\r\nSaved body',
            ),
          ),
          envelope: header.envelope,
          body: const MailBody(plainText: 'Retained content stays selected.'),
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
  final elapsed = Stopwatch()..start();
  while (!done() && elapsed.elapsed < const Duration(seconds: 15)) {
    await tester.pump(const Duration(milliseconds: 1));
    if (!done()) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1)),
      );
    }
  }
  expect(done(), isTrue, reason: 'The local operation did not complete.');
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

Future<void> _show(WidgetTester tester, _Probe probe) async {
  await tester.binding.setSurfaceSize(const Size(1100, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  final directory = MemoryMailLocalAccounts();
  for (final fixture in probe.fixtures.values) {
    directory.seed(fixture.identity);
  }
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
                store: directory,
                isCurrent: () => true,
                draftStoreFactory: probe.open,
              ),
            ),
            child: const Text('Open saved mail'),
          ),
        ),
      ),
    ),
  );
  await _press(tester, find.text('Open saved mail'));
  await _idle(tester);
  addTearDown(
    () => tester.binding.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    ),
  );
}

Future<void> _search(WidgetTester tester, {String query = ''}) async {
  await tester.enterText(_query, query);
  await _press(tester, _start);
  await _idle(tester);
}

Future<void> _completeSearch(WidgetTester tester, {String query = ''}) async {
  await _search(tester, query: query);
  for (var pages = 0; pages < 20; pages++) {
    // The continuation lives after the lazily built hit rows. Bring it into
    // the viewport before deciding that a multiaccount scan has completed.
    final scrollable = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byKey(const ValueKey('studio-mail-cached-search-results')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    for (var settle = 0; settle < 2; settle++) {
      scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
      await tester.pump();
    }
    if (_more.evaluate().isEmpty) return;
    await _press(tester, _more);
    await _idle(tester);
  }
  fail('The fixture exceeded its expected initial search page count.');
}

Future<void> _setAuto(WidgetTester tester, bool value) async {
  final control = tester.widget<SwitchListTile>(_auto);
  expect(control.onChanged, isNotNull);
  control.onChanged!(value);
  // No elapsed fake time here: subsequent 29 s / 1 s pumps test the deadline.
  await tester.pump();
  expect(tester.widget<SwitchListTile>(_auto).value, value);
}

bool _autoEnabled(WidgetTester tester) =>
    _auto.evaluate().isNotEmpty && tester.widget<SwitchListTile>(_auto).value;

Completer<void> _gate() {
  final gate = Completer<void>();
  addTearDown(() {
    if (!gate.isCompleted) gate.complete();
  });
  return gate;
}

/// The real production SQLite adapters do all search/body work. This boundary
/// only counts reads and delays a selected page to exercise cancellation races.
final class _Probe {
  _Probe(Iterable<SqliteOutboxFixture> fixtures)
    : fixtures = {
        for (final fixture in fixtures) fixture.identity.account: fixture,
      };

  final Map<MailAccountId, SqliteOutboxFixture> fixtures;
  final owners = <_Owner>[];
  Completer<void>? searchGate;
  MailAccountId? gateAccount;
  MailAccountId? failedAccount;
  int opens = 0;
  int searchCalls = 0;
  int bodyLoads = 0;
  int activeSearches = 0;
  int maxActiveSearches = 0;
  int readsAfterClose = 0;
  final searchedAccounts = <MailAccountId>[];

  Future<StudioMailDraftStore> open(StudioMailDraftAccount identity) async {
    opens++;
    final owner = _Owner(
      await fixtures[identity.account]!.open(identity),
      this,
    );
    owners.add(owner);
    return owner;
  }
}

final class _Owner
    implements StudioMailDraftStore, StudioMailMailboxStoreOwner {
  _Owner(this.delegate, this.probe) {
    mailboxStore = _Mailbox(
      (delegate as StudioMailMailboxStoreOwner).mailboxStore,
      this,
    );
  }

  final StudioMailDraftStore delegate;
  final _Probe probe;
  bool closed = false;
  @override
  late final _Mailbox mailboxStore;

  @override
  Future<void> close() async {
    if (closed) return;
    await delegate.close();
    closed = true;
  }

  @override
  Future<StudioMailStoredDraft?> load() =>
      throw StateError('Unexpected draft read');
  @override
  Future<void> save(
    StudioMailDraft draft, {
    required bool submissionUncertain,
  }) => throw StateError('Unexpected draft write');
  @override
  Future<void> saveRejectedDraft(
    StudioMailDraft draft, {
    required bool wasPreviouslyUncertain,
  }) => throw StateError('Unexpected draft submission');
  @override
  Future<void> clear() => throw StateError('Unexpected draft deletion');
}

final class _Mailbox
    implements StudioMailMailboxStore, StudioMailCachedHeaderSearchStore {
  _Mailbox(this.delegate, this.owner);
  final StudioMailMailboxStore delegate;
  final _Owner owner;
  _Probe get probe => owner.probe;

  void _read() {
    if (owner.closed) {
      probe.readsAfterClose++;
      throw StateError('Read after owner close');
    }
  }

  @override
  MailAccountId get account => delegate.account;

  @override
  Future<MailCachedHeaderSearchPage> searchCachedHeaders(
    String query, {
    MailCachedHeaderSearchCursor? cursor,
    int limit = 100,
    int scanLimit = 500,
  }) async {
    _read();
    probe.searchCalls++;
    probe.searchedAccounts.add(account);
    probe.activeSearches++;
    if (probe.activeSearches > probe.maxActiveSearches) {
      probe.maxActiveSearches = probe.activeSearches;
    }
    try {
      if (probe.gateAccount == null || probe.gateAccount == account) {
        await probe.searchGate?.future;
      }
      if (probe.failedAccount == account) {
        throw StateError('private-refresh-storage-detail');
      }
      return await (delegate as StudioMailCachedHeaderSearchStore)
          .searchCachedHeaders(
            query,
            cursor: cursor,
            limit: limit,
            scanLimit: scanLimit,
          );
    } finally {
      probe.activeSearches--;
    }
  }

  @override
  Future<MailMessage?> loadMessage(MailHeaderRecord header) {
    _read();
    probe.bodyLoads++;
    return delegate.loadMessage(header);
  }

  @override
  Future<List<MailCachedMailboxSummary>> listViews() => delegate.listViews();
  @override
  Future<MailCachedMailboxView?> loadView(MailMailboxId mailbox) =>
      delegate.loadView(mailbox);
  @override
  Future<MailCachedMailboxView> saveView(
    MailMailbox mailbox,
    List<MailHeaderRecord> headers, {
    required bool hasMore,
    required MailOperationLease lease,
  }) => delegate.saveView(mailbox, headers, hasMore: hasMore, lease: lease);
  @override
  Future<void> cacheMessage(
    MailHeaderRecord header,
    MailMessage message, {
    required MailOperationLease lease,
  }) => delegate.cacheMessage(header, message, lease: lease);
  @override
  Future<MailCacheCleanupReport> clearCache() => delegate.clearCache();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final previousWarnings = driftRuntimeOptions.dontWarnAboutMultipleDatabases;
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  tearDownAll(
    () => driftRuntimeOptions.dontWarnAboutMultipleDatabases = previousWarnings,
  );

  testWidgets('manual refresh replaces removed and changed-flag matches', (
    tester,
  ) async {
    final identity = _identity('flags');
    final fixture = await _fixture(tester, identity);
    await _seed(tester, fixture, [
      _header(identity, 0, subject: 'Removed unread'),
      _header(identity, 1, subject: 'Changed unread'),
      _header(identity, 2, subject: 'Still read', read: true),
    ]);
    final probe = _Probe([fixture]);
    await _show(tester, probe);
    await _completeSearch(tester, query: 'is:unread');
    expect(find.text('Removed unread'), findsOneWidget);
    expect(find.text('Changed unread'), findsOneWidget);
    expect(find.text('Still read'), findsNothing);
    await _seed(tester, fixture, [
      _header(identity, 1, subject: 'Changed unread', read: true),
      _header(identity, 2, subject: 'Still read', read: true),
      _header(identity, 3, subject: 'New unread'),
    ]);
    await _press(tester, _refresh);
    await _idle(tester);
    expect(find.text('New unread'), findsOneWidget);
    expect(find.text('Removed unread'), findsNothing);
    expect(find.text('Changed unread'), findsNothing);
    expect(find.text('Still read'), findsNothing);
    expect(probe.bodyLoads, 0);
    expect(probe.readsAfterClose, 0);
  });

  testWidgets('multiaccount refresh publishes one complete replacement', (
    tester,
  ) async {
    final identities = [_identity('first'), _identity('second')]
      ..sort((a, b) => a.account.value.compareTo(b.account.value));
    final first = await _fixture(tester, identities.first);
    final second = await _fixture(tester, identities.last);
    await _seed(tester, first, [
      _header(first.identity, 0, subject: 'Before one'),
    ]);
    await _seed(tester, second, [
      _header(second.identity, 0, subject: 'Before two'),
    ]);
    final probe = _Probe([first, second]);
    await _show(tester, probe);
    await _completeSearch(tester);
    await _seed(tester, first, [
      _header(first.identity, 1, subject: 'After one'),
    ]);
    await _seed(tester, second, [
      _header(second.identity, 1, subject: 'After two'),
    ]);
    final gate = _gate();
    probe.searchGate = gate;
    probe.gateAccount = second.identity.account;
    await _press(tester, _refresh);
    await _until(
      tester,
      () => probe.searchedAccounts.length == 4 && probe.activeSearches == 1,
    );
    expect(find.text('Before one'), findsOneWidget);
    expect(find.text('Before two'), findsOneWidget);
    expect(find.text('After one'), findsNothing);
    expect(find.text('After two'), findsNothing);
    gate.complete();
    probe.searchGate = null;
    await _idle(tester);
    expect(find.text('After one'), findsOneWidget);
    expect(find.text('After two'), findsOneWidget);
    expect(find.text('Before one'), findsNothing);
    expect(find.text('Before two'), findsNothing);
    expect(probe.maxActiveSearches, 1);
    expect(probe.bodyLoads, 0);
  });

  testWidgets(
    'refresh preserves the selected reader without rereading its body',
    (tester) async {
      final identity = _identity('reader');
      final fixture = await _fixture(tester, identity);
      final selected = _header(identity, 0, subject: 'Selected message');
      await _seed(tester, fixture, [selected], body: true);
      final probe = _Probe([fixture]);
      await _show(tester, probe);
      await _completeSearch(tester);
      await _press(tester, find.text('Selected message'));
      await _idle(tester);
      final controller = tester
          .widget<MailMessageView>(find.byType(MailMessageView))
          .controller;
      expect(controller.decodedText, contains('Retained content'));
      expect(probe.bodyLoads, 1);
      await _seed(tester, fixture, [
        selected,
        _header(identity, 1, subject: 'Added message'),
      ]);
      await _press(tester, _refresh);
      await _idle(tester);
      expect(
        tester.widget<MailMessageView>(find.byType(MailMessageView)).controller,
        same(controller),
      );
      expect(probe.bodyLoads, 1);
      await _seed(tester, fixture, [
        _header(identity, 1, subject: 'Added message'),
      ]);
      await _press(tester, _refresh);
      await _idle(tester);
      expect(find.byType(MailMessageView), findsNothing);
      expect(find.text('Added message'), findsOneWidget);
      expect(find.text('Selected message'), findsNothing);
      expect(probe.bodyLoads, 1);
    },
  );

  testWidgets(
    'refresh is explicit until auto is opted in after full local coverage',
    (tester) async {
      final identity = _identity('opt-in');
      final fixture = await _fixture(tester, identity);
      await _seed(tester, fixture, [
        for (var index = 0; index < 101; index++)
          _header(identity, index, subject: 'Saved $index'),
      ]);
      final probe = _Probe([fixture]);
      await _show(tester, probe);
      await _search(tester);
      expect(_autoEnabled(tester), isFalse);
      expect(tester.widget<SwitchListTile>(_auto).onChanged, isNull);
      final reads = probe.searchCalls;
      await tester.pump(const Duration(minutes: 1));
      expect(probe.searchCalls, reads);
      await _press(tester, _refresh);
      await _idle(tester);
      expect(probe.searchCalls, reads + 2);
      expect(_autoEnabled(tester), isFalse);
      await _setAuto(tester, true);
      final refreshed = probe.searchCalls;
      await tester.pump(const Duration(seconds: 29));
      expect(probe.searchCalls, refreshed);
      await tester.pump(const Duration(seconds: 1));
      await _idle(tester);
      expect(probe.searchCalls, refreshed + 2);
      expect(probe.bodyLoads, 0);
      await _setAuto(tester, false);
    },
  );

  testWidgets('slow automatic refresh never overlaps or catches up in bursts', (
    tester,
  ) async {
    final identity = _identity('slow');
    final fixture = await _fixture(tester, identity);
    await _seed(tester, fixture, [_header(identity, 0, subject: 'Original')]);
    final probe = _Probe([fixture]);
    await _show(tester, probe);
    await _completeSearch(tester);
    final gate = _gate();
    probe.searchGate = gate;
    await _setAuto(tester, true);
    await tester.pump(const Duration(seconds: 30));
    await _until(tester, () => probe.activeSearches == 1);
    expect(probe.searchCalls, 2);
    await tester.pump(const Duration(minutes: 2));
    expect(probe.searchCalls, 2);
    expect(probe.maxActiveSearches, 1);
    gate.complete();
    probe.searchGate = null;
    await _idle(tester);
    expect(probe.searchCalls, 2);
    await tester.pump(const Duration(seconds: 29));
    expect(probe.searchCalls, 2);
    await tester.pump(const Duration(seconds: 1));
    await _idle(tester);
    expect(probe.searchCalls, 3);
    await _press(tester, _close);
    await _until(
      tester,
      () => find.byType(StudioMailCachedSearchDialog).evaluate().isEmpty,
    );
    final closedReads = probe.searchCalls;
    final closedOpens = probe.opens;
    await tester.pump(const Duration(minutes: 2));
    expect(probe.searchCalls, closedReads);
    expect(probe.opens, closedOpens);
    expect(probe.owners.every((owner) => owner.closed), isTrue);
    expect(probe.readsAfterClose, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('suspension cancels the timer and resume waits a full interval', (
    tester,
  ) async {
    final identity = _identity('lifecycle');
    final fixture = await _fixture(tester, identity);
    await _seed(tester, fixture, [
      _header(identity, 0, subject: 'Offline result'),
    ]);
    final probe = _Probe([fixture]);
    await _show(tester, probe);
    await _completeSearch(tester);
    await _setAuto(tester, true);
    await tester.pump(const Duration(seconds: 29));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(minutes: 3));
    expect(probe.searchCalls, 1);
    expect(find.text('Offline result'), findsOneWidget);
    expect(_autoEnabled(tester), isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(seconds: 29));
    expect(probe.searchCalls, 1);
    await tester.pump(const Duration(seconds: 1));
    await _idle(tester);
    expect(probe.searchCalls, 2);
    await _setAuto(tester, false);
  });

  testWidgets(
    'suspending a staged refresh retains completed results and stops future pages',
    (tester) async {
      final identities = [
        _identity('one'),
        _identity('two'),
        _identity('three'),
      ]..sort((a, b) => a.account.value.compareTo(b.account.value));
      final fixtures = <SqliteOutboxFixture>[];
      for (final identity in identities) {
        final fixture = await _fixture(tester, identity);
        fixtures.add(fixture);
        await _seed(tester, fixture, [
          _header(identity, 0, subject: 'Before ${fixtures.length}'),
        ]);
      }
      final probe = _Probe(fixtures);
      await _show(tester, probe);
      await _completeSearch(tester);
      for (var i = 0; i < fixtures.length; i++) {
        await _seed(tester, fixtures[i], [
          _header(fixtures[i].identity, 1, subject: 'After ${i + 1}'),
        ]);
      }
      final gate = _gate();
      probe.searchGate = gate;
      probe.gateAccount = fixtures[1].identity.account;
      await _setAuto(tester, true);
      await tester.pump(const Duration(seconds: 30));
      await _until(
        tester,
        () => probe.searchCalls == 5 && probe.activeSearches == 1,
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      gate.complete();
      probe.searchGate = null;
      await _idle(tester);
      expect(probe.searchCalls, 5);
      expect(find.text('After 1'), findsNothing);
      expect(find.text('Before 1'), findsOneWidget);
      expect(_autoEnabled(tester), isTrue);
      await tester.pump(const Duration(minutes: 2));
      expect(probe.searchCalls, 5);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(seconds: 29));
      expect(probe.searchCalls, 5);
      await tester.pump(const Duration(seconds: 1));
      await _idle(tester);
      expect(probe.searchCalls, 8);
      expect(find.text('After 1'), findsOneWidget);
      expect(find.text('Before 1'), findsNothing);
      await _setAuto(tester, false);
      expect(probe.bodyLoads, 0);
    },
  );

  testWidgets(
    'query edits invalidate staged work and stale refresh callbacks',
    (tester) async {
      final identity = _identity('edit');
      final fixture = await _fixture(tester, identity);
      await _seed(tester, fixture, [
        _header(identity, 0, subject: 'Old query match'),
      ]);
      final probe = _Probe([fixture]);
      await _show(tester, probe);
      await _completeSearch(tester);
      await _setAuto(tester, true);
      final staleRefresh = tester
          .widget<ButtonStyleButton>(_refresh)
          .onPressed!;
      final gate = _gate();
      probe.searchGate = gate;
      staleRefresh();
      await tester.pump();
      await _until(tester, () => probe.activeSearches == 1);
      await tester.enterText(_query, 'subject:different');
      await tester.pump();
      expect(_autoEnabled(tester), isFalse);
      expect(find.text('Old query match'), findsNothing);
      gate.complete();
      probe.searchGate = null;
      await _idle(tester);
      final opens = probe.opens;
      staleRefresh();
      await tester.pump(const Duration(minutes: 2));
      expect(probe.opens, opens);
      expect(find.text('Old query match'), findsNothing);
      expect(find.byType(MailMessageView), findsNothing);
      expect(probe.owners.every((owner) => owner.closed), isTrue);
    },
  );

  testWidgets(
    'scope edits clear the previous search and disable auto immediately',
    (tester) async {
      final first = await _fixture(tester, _identity('scope-first'));
      final second = await _fixture(tester, _identity('scope-second'));
      await _seed(tester, first, [
        _header(first.identity, 0, subject: 'First account'),
      ]);
      await _seed(tester, second, [
        _header(second.identity, 0, subject: 'Second account'),
      ]);
      final probe = _Probe([first, second]);
      await _show(tester, probe);
      await _completeSearch(tester);
      await _setAuto(tester, true);
      final staleRefresh = tester
          .widget<ButtonStyleButton>(_refresh)
          .onPressed!;
      tester
          .widget<DropdownButtonFormField<String>>(
            find.byKey(const ValueKey('studio-mail-cached-search-scope')),
          )
          .onChanged!(second.identity.account.value);
      await tester.pump();
      expect(_autoEnabled(tester), isFalse);
      expect(find.text('First account'), findsNothing);
      expect(find.text('Second account'), findsNothing);
      final opens = probe.opens;
      staleRefresh();
      await tester.pump(const Duration(minutes: 2));
      expect(probe.opens, opens);
      await _completeSearch(tester);
      expect(find.text('First account'), findsNothing);
      expect(find.text('Second account'), findsOneWidget);
      expect(probe.searchedAccounts.last, second.identity.account);
      expect(_autoEnabled(tester), isFalse);
    },
  );

  testWidgets(
    'a refresh capped at one thousand matches pauses automatic work',
    (tester) async {
      final identity = _identity('limit');
      final fixture = await _fixture(tester, identity);
      await _seed(tester, fixture, [
        _header(identity, 0, subject: 'Initial result'),
      ]);
      final probe = _Probe([fixture]);
      await _show(tester, probe);
      await _completeSearch(tester);
      await _seed(tester, fixture, [
        for (var index = 0; index < 1000; index++)
          _header(identity, index, subject: 'Inbox $index'),
      ]);
      await _seed(tester, fixture, [
        _header(identity, 1001, subject: 'Beyond the cap', folder: 'Archive'),
      ], folder: 'Archive');
      await _setAuto(tester, true);
      final before = probe.searchCalls;
      await tester.pump(const Duration(seconds: 30));
      await _idle(tester);
      expect(probe.searchCalls, before + 10);
      expect(find.text(_strings.mailCachedSearchMatches(1000)), findsOneWidget);
      expect(_autoEnabled(tester), isFalse);
      expect(tester.widget<SwitchListTile>(_auto).onChanged, isNull);
      final capped = probe.searchCalls;
      await tester.pump(const Duration(minutes: 2));
      expect(probe.searchCalls, capped);
      expect(probe.bodyLoads, 0);
    },
  );

  testWidgets('failed refresh pauses auto without exposing storage details', (
    tester,
  ) async {
    final identity = _identity('failure');
    final fixture = await _fixture(tester, identity);
    await _seed(tester, fixture, [
      _header(identity, 0, subject: 'Previously cached'),
    ]);
    final probe = _Probe([fixture]);
    await _show(tester, probe);
    await _completeSearch(tester);
    await _setAuto(tester, true);
    probe.failedAccount = identity.account;
    await tester.pump(const Duration(seconds: 30));
    await _idle(tester);
    expect(_autoEnabled(tester), isFalse);
    expect(tester.widget<SwitchListTile>(_auto).onChanged, isNull);
    expect(find.textContaining('private-refresh-storage-detail'), findsNothing);
    final attempts = probe.searchCalls;
    await tester.pump(const Duration(minutes: 2));
    expect(probe.searchCalls, attempts);
    expect(probe.bodyLoads, 0);
  });

  testWidgets(
    'Close drains an in-flight automatic refresh and rejects its late result',
    (tester) async {
      final identity = _identity('close');
      final fixture = await _fixture(tester, identity);
      await _seed(tester, fixture, [
        _header(identity, 0, subject: 'Kept until close'),
      ]);
      final probe = _Probe([fixture]);
      await _show(tester, probe);
      await _completeSearch(tester);
      final gate = _gate();
      probe.searchGate = gate;
      await _setAuto(tester, true);
      await tester.pump(const Duration(seconds: 30));
      await _until(tester, () => probe.activeSearches == 1);
      await _press(tester, _close);
      expect(find.byType(StudioMailCachedSearchDialog), findsOneWidget);
      gate.complete();
      probe.searchGate = null;
      await _until(
        tester,
        () => find.byType(StudioMailCachedSearchDialog).evaluate().isEmpty,
      );
      final calls = probe.searchCalls;
      await tester.pump(const Duration(minutes: 2));
      expect(probe.searchCalls, calls);
      expect(probe.owners.every((owner) => owner.closed), isTrue);
      expect(probe.readsAfterClose, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
