import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:quds_office_studio/studio_mail_compose.dart';
import 'package:quds_office_studio/studio_mail_draft_store.dart';
import 'package:quds_office_studio/studio_mail_draft_store_native.dart';
import 'package:quds_office_studio/studio_mail_drafts_dialog.dart';
import 'package:quds_office_studio/studio_mail_drafts_strings.dart';
import 'package:quds_office_studio/studio_mail_local_drafts.dart';
import 'package:quds_office_studio/studio_mail_mailbox_store.dart';
import 'package:quds_office_studio/studio_mail_strings.dart';
import 'package:quds_office_studio/studio_strings.dart';

import 'support/mail_outbox_store.dart';

const _strings = StudioStrings(StudioLanguage.en);
const _sender = 'writer@example.test';

StudioMailDraftAccount _identity([String sender = _sender]) =>
    StudioMailDraftAccount(
      provider: 'imap',
      endpoint: 'imaps://imap.example.test:993',
      login: sender,
      sender: sender,
    );

StudioMailDraft _draft(String subject) => StudioMailDraft(
  to: 'reader@example.test',
  subject: subject,
  body: 'Saved body: $subject.',
);

Finder _field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

Finder get _catalogClose => find.descendant(
  of: find.byType(StudioMailDraftsDialog),
  matching: find.byWidgetPredicate(
    (widget) => widget is IconButton && widget.tooltip == _strings.close,
  ),
);

Finder get _send => find.descendant(
  of: find.byType(StudioMailComposeDialog),
  matching: find.byWidgetPredicate((widget) => widget is FilledButton),
);

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var turn = 0; turn < 200 && !ready(); turn++) {
    await tester.pump(const Duration(milliseconds: 10));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  }
  expect(ready(), isTrue, reason: 'The local draft operation must settle.');
  await pumpOutboxWidgets(tester);
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await pumpOutboxWidgets(tester);
}

Future<SqliteOutboxFixture> _fixture(WidgetTester tester) async {
  final fixture = await awaitOutboxOperation(
    tester,
    SqliteOutboxFixture.create(_identity()),
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await awaitOutboxOperation(tester, fixture.close());
  });
  return fixture;
}

Future<void> _show(
  WidgetTester tester, {
  required StudioMailDraftStoreFactory open,
  bool Function()? isCurrent,
  VoidCallback? onClosed,
  bool waitForCatalog = true,
}) async {
  await tester.binding.setSurfaceSize(const Size(1200, 950));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            child: const Text('Open local fixture'),
            onPressed: () async {
              await showDialog<void>(
                context: context,
                barrierDismissible: false,
                builder: (_) => StudioMailLocalDraftsDialog(
                  strings: _strings,
                  identity: _identity(),
                  sender: _sender,
                  isCurrent: isCurrent ?? () => true,
                  draftStoreFactory: open,
                ),
              );
              onClosed?.call();
            },
          ),
        ),
      ),
    ),
  );
  await _tap(tester, find.text('Open local fixture'));
  if (waitForCatalog) {
    await _until(
      tester,
      () => find.byType(StudioMailDraftsDialog).evaluate().isNotEmpty,
    );
    await _until(
      tester,
      () => tester.widget<IconButton>(_catalogClose).onPressed != null,
    );
  }
}

Future<void> _choose(WidgetTester tester, String subject) async {
  await _tap(tester, find.text(subject));
  await _until(
    tester,
    () => find.byType(StudioMailComposeDialog).evaluate().isNotEmpty,
  );
}

Future<void> _saveAndClose(WidgetTester tester) async {
  await _tap(tester, find.text(_strings.mailDraftSaveClose));
  await _until(
    tester,
    () => find.byType(StudioMailDraftsDialog).evaluate().isNotEmpty,
  );
  await _until(
    tester,
    () => tester.widget<IconButton>(_catalogClose).onPressed != null,
  );
}

final class _ObservedStore
    implements StudioMailDraftStore, StudioMailDraftCatalog {
  _ObservedStore(this.delegate, {MailAccountId? account})
    : account = account ?? delegate.account;

  final SqliteStudioMailDraftStore delegate;
  @override
  final MailAccountId account;
  Completer<void>? closeGate;
  bool failClose = false;
  int closes = 0;
  int loads = 0;

  @override
  int get selectionEpoch => delegate.selectionEpoch;
  @override
  String get selectedDraftId => delegate.selectedDraftId;
  @override
  Future<StudioMailDraftCatalogPage> listDrafts({String? afterId}) =>
      delegate.listDrafts(afterId: afterId);
  @override
  Future<StudioMailStoredDraft> selectDraft(StudioMailDraftSummary summary) =>
      delegate.selectDraft(summary);
  @override
  Future<StudioMailStoredDraft> createDraft(StudioMailDraft initial) =>
      delegate.createDraft(initial);
  @override
  Future<void> discardDraft(StudioMailDraftSummary summary) =>
      delegate.discardDraft(summary);
  @override
  Future<StudioMailStoredDraft?> load() {
    loads++;
    return delegate.load();
  }

  @override
  Future<void> save(
    StudioMailDraft draft, {
    required bool submissionUncertain,
  }) => delegate.save(draft, submissionUncertain: submissionUncertain);
  @override
  Future<void> saveRejectedDraft(
    StudioMailDraft draft, {
    required bool wasPreviouslyUncertain,
  }) => delegate.saveRejectedDraft(
    draft,
    wasPreviouslyUncertain: wasPreviouslyUncertain,
  );
  @override
  Future<void> clear() => delegate.clear();
  @override
  Future<void> close() async {
    closes++;
    await closeGate?.future;
    if (failClose) {
      failClose = false;
      throw const StudioMailDraftStoreException(MailProblemCode.storageFailure);
    }
    await delegate.close();
  }
}

final class _ForeignMailbox extends Fake implements StudioMailMailboxStore {
  _ForeignMailbox(this.account);
  @override
  final MailAccountId account;
  int clears = 0;
  @override
  Future<MailCacheCleanupReport> clearCache() async {
    clears++;
    throw StateError('A foreign mailbox must never be cleared.');
  }
}

final class _ObservedMailboxOwner extends _ObservedStore
    implements StudioMailMailboxStoreOwner {
  _ObservedMailboxOwner(super.delegate, this.mailboxStore);
  @override
  final StudioMailMailboxStore mailboxStore;
}

void main() {
  testWidgets(
    'foreign optional cache owner is closed before any local draft load or clear',
    (tester) async {
      final fixture = await _fixture(tester);
      final adapter = await awaitOutboxOperation(tester, fixture.openLoaded());
      final foreign = _ForeignMailbox(
        MailAccountId('foreign-cache', profile: adapter.account.profile),
      );
      final observed = _ObservedMailboxOwner(adapter, foreign);
      await _show(tester, open: (_) async => observed, waitForCatalog: false);
      await _until(tester, () => observed.closes == 1);
      expect(observed.loads, 0);
      expect(foreign.clears, 0);
      expect(find.byType(StudioMailDraftsDialog), findsNothing);
      expect(find.byType(StudioMailComposeDialog), findsNothing);
      expect(find.text(_strings.mailDraftStorageFailed), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'offline editing retains separate drafts, attachments and uncertainty on reopen',
    (tester) async {
      final fixture = await _fixture(tester);
      final seed = await awaitOutboxOperation(tester, fixture.openLoaded());
      final attachment = Uint8List.fromList([0, 13, 10, 255]);
      await awaitOutboxOperation(
        tester,
        seed.save(
          StudioMailDraft(
            to: 'reader@example.test',
            bcc: 'private@example.test',
            subject: 'Existing uncertain',
            body: 'Retained body.',
            attachments: StudioMailAttachments.from([
              StudioMailAttachment(name: 'saved.bin', bytes: attachment),
            ]),
          ),
          submissionUncertain: true,
        ),
      );
      await awaitOutboxOperation(tester, seed.close());
      var returned = false;
      await _show(tester, open: fixture.open, onClosed: () => returned = true);
      expect(find.text(_strings.mailDraftUncertain), findsOneWidget);
      await _choose(tester, 'Existing uncertain');
      final composer = tester.widget<StudioMailComposeDialog>(
        find.byType(StudioMailComposeDialog),
      );
      expect(composer.canSend, isFalse);
      expect(composer.onQueueDraft, isNull);
      expect(composer.previousSubmissionUncertain, isTrue);
      expect(tester.widget<FilledButton>(_send).onPressed, isNull);
      expect(find.text(_strings.mailDraftConnectToSend), findsOneWidget);
      await tester.enterText(_field(_strings.subject), 'Edited offline');
      await _saveAndClose(tester);
      expect(find.text('Edited offline'), findsOneWidget);
      await _tap(tester, find.byKey(const ValueKey('studio-mail-new-draft')));
      await _until(
        tester,
        () => find.byType(StudioMailComposeDialog).evaluate().isNotEmpty,
      );
      await tester.enterText(_field(_strings.to), 'unfinished@');
      await tester.enterText(_field(_strings.subject), 'Second unfinished');
      await _saveAndClose(tester);
      expect(find.text('Edited offline'), findsOneWidget);
      expect(find.text('Second unfinished'), findsOneWidget);
      expect(
        await awaitOutboxOperation(tester, fixture.adapters.last.loadOutbox()),
        isEmpty,
      );
      await _tap(tester, _catalogClose);
      await _until(tester, () => returned);
      expect(find.byType(StudioMailLocalDraftsDialog), findsNothing);

      final reopened = await awaitOutboxOperation(tester, fixture.openLoaded());
      final rows = await awaitOutboxOperation(tester, reopened.listDrafts());
      expect(
        rows.drafts.map((draft) => draft.subject),
        containsAll(['Edited offline', 'Second unfinished']),
      );
      final original = await awaitOutboxOperation(
        tester,
        reopened.selectDraft(
          rows.drafts.singleWhere((draft) => draft.subject == 'Edited offline'),
        ),
      );
      expect(original.submissionUncertain, isTrue);
      expect(original.draft.bcc, 'private@example.test');
      expect(original.draft.attachments.items.single.content.bytes, attachment);
      final second = await awaitOutboxOperation(
        tester,
        reopened.selectDraft(
          rows.drafts.singleWhere(
            (draft) => draft.subject == 'Second unfinished',
          ),
        ),
      );
      expect(second.draft.to, 'unfinished@');
      expect(second.submissionUncertain, isFalse);
      expect(second.draft.attachments.items, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a mismatched catalog is closed before any draft is loaded', (
    tester,
  ) async {
    final fixture = await _fixture(tester);
    final adapter = await awaitOutboxOperation(tester, fixture.openLoaded());
    final observed = _ObservedStore(
      adapter,
      account: _identity('someone-else@example.test').account,
    );
    await _show(tester, open: (_) async => observed, waitForCatalog: false);
    await _until(tester, () => observed.closes == 1);
    expect(observed.loads, 0);
    expect(find.byType(StudioMailDraftsDialog), findsNothing);
    expect(find.text(_strings.mailDraftStorageFailed), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disposal releases an owner returned by a delayed opener', (
    tester,
  ) async {
    final fixture = await _fixture(tester);
    final adapter = await awaitOutboxOperation(tester, fixture.openLoaded());
    final observed = _ObservedStore(adapter);
    final gate = Completer<StudioMailDraftStore>();
    await _show(tester, open: (_) => gate.future, waitForCatalog: false);
    await tester.pumpWidget(const SizedBox.shrink());
    gate.complete(observed);
    await _until(tester, () => observed.closes == 1);
    expect(observed.loads, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a changed account lifetime rejects a delayed opener', (
    tester,
  ) async {
    final fixture = await _fixture(tester);
    final adapter = await awaitOutboxOperation(tester, fixture.openLoaded());
    final observed = _ObservedStore(adapter);
    final gate = Completer<StudioMailDraftStore>();
    var current = true;
    await _show(
      tester,
      open: (_) => gate.future,
      isCurrent: () => current,
      waitForCatalog: false,
    );
    current = false;
    gate.complete(observed);
    await _until(tester, () => observed.closes == 1);
    expect(observed.loads, 0);
    expect(find.byType(StudioMailDraftsDialog), findsNothing);
    expect(find.text(_strings.mailDraftStorageFailed), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the parent does not return before its store lease closes', (
    tester,
  ) async {
    final fixture = await _fixture(tester);
    final adapter = await awaitOutboxOperation(tester, fixture.openLoaded());
    final observed = _ObservedStore(adapter)..closeGate = Completer<void>();
    var returned = false;
    await _show(
      tester,
      open: (_) async => observed,
      onClosed: () => returned = true,
    );
    await _tap(tester, _catalogClose);
    expect(observed.closes, 1);
    expect(returned, isFalse);
    expect(find.byType(StudioMailLocalDraftsDialog), findsOneWidget);
    observed.closeGate!.complete();
    await _until(tester, () => returned);
    expect(observed.closes, 1);
    expect(find.byType(StudioMailLocalDraftsDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'failed close retains the surface until explicit retry succeeds',
    (tester) async {
      final fixture = await _fixture(tester);
      final adapter = await awaitOutboxOperation(tester, fixture.openLoaded());
      final observed = _ObservedStore(adapter)..failClose = true;
      var returned = false;
      await _show(
        tester,
        open: (_) async => observed,
        onClosed: () => returned = true,
      );
      await _tap(tester, _catalogClose);
      await _until(
        tester,
        () => find.text(_strings.mailDraftCloseFailed).evaluate().isNotEmpty,
      );
      expect(returned, isFalse);
      await _tap(
        tester,
        find.byKey(const ValueKey('studio-mail-local-drafts-close')),
      );
      await _until(tester, () => returned);
      expect(observed.closes, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'returning from the native workspace releases the profile lease',
    (tester) async {
      final directory = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('mail-local-drafts-widget-'),
      ))!;
      final owners = <StudioMailDraftStore>[];
      Future<StudioMailDraftStore> open(StudioMailDraftAccount identity) async {
        final owner = await openStudioMailDraftStore(
          identity,
          appDirectory: directory,
        );
        owners.add(owner);
        return owner;
      }

      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        for (final owner in owners.reversed) {
          await awaitOutboxOperation(tester, owner.close());
        }
        await tester.runAsync(() => directory.delete(recursive: true));
      });
      var returned = false;
      await _show(tester, open: open, onClosed: () => returned = true);
      Object? denied;
      try {
        await awaitOutboxOperation(tester, open(_identity()));
      } on Object catch (error) {
        denied = error;
      }
      expect(
        denied,
        isA<StudioMailDraftStoreException>().having(
          (error) => error.code,
          'code',
          MailProblemCode.conflict,
        ),
      );
      await _tap(tester, _catalogClose);
      await _until(tester, () => returned);
      final reopened = await awaitOutboxOperation(tester, open(_identity()));
      expect(await awaitOutboxOperation(tester, reopened.load()), isNull);
      expect(owners, hasLength(2));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a failed SQLite save keeps edits open and permits explicit retry',
    (tester) async {
      final fixture = await _fixture(tester);
      final seed = await awaitOutboxOperation(tester, fixture.openLoaded());
      await awaitOutboxOperation(
        tester,
        seed.save(_draft('Before failure'), submissionUncertain: false),
      );
      await awaitOutboxOperation(tester, seed.close());
      await _show(tester, open: fixture.open);
      await _choose(tester, 'Before failure');
      await tester.enterText(_field(_strings.subject), 'Retained failed edit');
      fixture.failNextCheckpoint = MailStoreCheckpoint.beforeCommit;
      await _tap(tester, find.text(_strings.mailDraftSaveClose));
      await _until(
        tester,
        () => find.text(_strings.mailDraftSaveFailed).evaluate().isNotEmpty,
      );
      expect(find.byType(StudioMailComposeDialog), findsOneWidget);
      expect(
        tester.widget<TextField>(_field(_strings.subject)).controller!.text,
        'Retained failed edit',
      );
      expect(
        (await awaitOutboxOperation(
          tester,
          fixture.adapters.last.load(),
        ))!.draft.subject,
        'Before failure',
      );
      await _saveAndClose(tester);
      expect(find.text('Retained failed edit'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final changeSelection in [false, true]) {
    testWidgets(
      'retained save callback rejects ${changeSelection ? 'A to B to A selection' : 'account lifetime'} changes',
      (tester) async {
        final fixture = await _fixture(tester);
        final seed = await awaitOutboxOperation(tester, fixture.openLoaded());
        await awaitOutboxOperation(
          tester,
          seed.save(_draft('Original A'), submissionUncertain: true),
        );
        await awaitOutboxOperation(tester, seed.close());
        var current = true;
        await _show(tester, open: fixture.open, isCurrent: () => current);
        await _choose(tester, 'Original A');
        final callback = tester
            .widget<StudioMailComposeDialog>(
              find.byType(StudioMailComposeDialog),
            )
            .onSaveDraft!;
        final store = fixture.adapters.last;
        if (changeSelection) {
          await awaitOutboxOperation(tester, store.createDraft(_draft('B')));
          final page = await awaitOutboxOperation(tester, store.listDrafts());
          await awaitOutboxOperation(
            tester,
            store.selectDraft(
              page.drafts.singleWhere((draft) => draft.subject == 'Original A'),
            ),
          );
        } else {
          current = false;
        }
        await expectLater(
          callback(_draft('Stale overwrite')),
          throwsA(
            isA<StudioMailDraftStoreException>().having(
              (error) => error.code,
              'code',
              MailProblemCode.unavailable,
            ),
          ),
        );
        final unchanged = await awaitOutboxOperation(tester, store.load());
        expect(unchanged!.draft.subject, 'Original A');
        expect(unchanged.submissionUncertain, isTrue);
        expect(await awaitOutboxOperation(tester, store.loadOutbox()), isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'canSend blocks retained send callbacks and keyboard activation',
    (tester) async {
      var canSend = true;
      var returned = false;
      late StateSetter update;
      await tester.binding.setSurfaceSize(const Size(1200, 950));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                await showDialog<StudioMailDraft>(
                  context: context,
                  builder: (_) => StatefulBuilder(
                    builder: (context, setState) {
                      update = setState;
                      return StudioMailComposeDialog(
                        strings: _strings,
                        from: _sender,
                        initialDraft: _draft('No transport'),
                        canSend: canSend,
                      );
                    },
                  ),
                );
                returned = true;
              },
              child: const Text('Open composer'),
            ),
          ),
        ),
      );
      await _tap(tester, find.text('Open composer'));
      final retained = tester.widget<FilledButton>(_send).onPressed!;
      update(() => canSend = false);
      await tester.pump();
      expect(tester.widget<FilledButton>(_send).onPressed, isNull);
      retained();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await pumpOutboxWidgets(tester);
      expect(returned, isFalse);
      expect(find.byType(StudioMailComposeDialog), findsOneWidget);
      expect(find.text(_strings.mailDraftConnectToSend), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'disabling send during its awaited save prevents returning a send',
    (tester) async {
      var canSend = true;
      var returned = false;
      var saves = 0;
      late StateSetter update;
      final gate = Completer<void>();
      await tester.binding.setSurfaceSize(const Size(1200, 950));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                await showDialog<StudioMailDraft>(
                  context: context,
                  builder: (_) => StatefulBuilder(
                    builder: (context, setState) {
                      update = setState;
                      return StudioMailComposeDialog(
                        strings: _strings,
                        from: _sender,
                        initialDraft: _draft('Save before send'),
                        canSend: canSend,
                        onSaveDraft: (_) {
                          saves++;
                          return gate.future;
                        },
                      );
                    },
                  ),
                );
                returned = true;
              },
              child: const Text('Open composer'),
            ),
          ),
        ),
      );
      await _tap(tester, find.text('Open composer'));
      tester.widget<FilledButton>(_send).onPressed!();
      await tester.pump();
      expect(saves, 1);
      update(() => canSend = false);
      await tester.pump();
      gate.complete();
      await pumpOutboxWidgets(tester);
      expect(returned, isFalse);
      expect(find.byType(StudioMailComposeDialog), findsOneWidget);
      expect(tester.widget<FilledButton>(_send).onPressed, isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );
}
