part of '../studio_mail_journal_host_test.dart';

// The organization port does not require the optional legacy flag setters.
final class _MembershipOnlyBrowser
    implements
        StudioMailMessageLoader,
        StudioMailMailboxBrowser,
        StudioMailMailboxRecords,
        StudioMailMembershipActions {
  _MembershipOnlyBrowser(this.delegate);
  final _ImapBrowser delegate;
  @override
  MailAccountId get account => delegate.account;
  @override
  Future<StudioMailHeaderPage> fetchHeaders(
    mail.Mailbox mailbox, {
    MailCursor? cursor,
    int limit = 50,
  }) => delegate.fetchHeaders(mailbox, cursor: cursor, limit: limit);
  @override
  MailHeaderRecord observedHeader(
    mail.Mailbox mailbox,
    mail.MimeMessage header,
  ) => delegate.observedHeader(mailbox, header);
  @override
  Future<MailMessage> fetchMessage(
    mail.Mailbox mailbox,
    mail.MimeMessage header,
  ) => delegate.fetchMessage(mailbox, header);
  @override
  Future<Uint8List> fetch(mail.Mailbox mailbox, mail.MimeMessage header) =>
      delegate.fetch(mailbox, header);
  @override
  Future<void> markRead(mail.Mailbox mailbox, mail.MimeMessage header) =>
      delegate.markRead(mailbox, header);
  @override
  Future<MailCapabilities> membershipCapabilities() =>
      delegate.membershipCapabilities();
  @override
  Future<MailResult<MailUnit>> applyMembership(
    MailOperation operation,
    MailOperationLease lease,
  ) => delegate.applyMembership(operation, lease);
  @override
  void cancel() => delegate.cancel();
  @override
  void dispose() => delegate.dispose();
}

Future<void> _openFirst(WidgetTester tester) async {
  final list = _list(tester);
  list.onOpen(list.items.first.id);
  await _until(
    tester,
    () =>
        find.byType(MailMessageView).evaluate().isNotEmpty &&
        !_list(tester).busy,
  );
}

Future<void> _startMembership(
  WidgetTester tester,
  _Harness harness,
  MailBulkFlagAction action,
) async {
  if (action == MailBulkFlagAction.move) {
    if (harness.kind == MailProviderKind.imap) {
      await tester.tap(_key('studio-mail-move-message'));
      await _until(
        tester,
        () => _key('studio-mail-move-picker').evaluate().isNotEmpty,
      );
      await tester.tap(_key('studio-mail-move-destination-0'));
    } else {
      await tester.tap(find.byTooltip(_strings.ewsMove));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(
        find.widgetWithText(PopupMenuItem<MailMailbox>, 'Archive'),
      );
    }
  } else if (harness.kind == MailProviderKind.imap) {
    await tester.tap(_key('studio-mail-delete-message'));
    await _until(
      tester,
      () => _key('studio-mail-confirm-delete').evaluate().isNotEmpty,
    );
    expect(harness.commands, isEmpty);
    await tester.tap(_key('studio-mail-confirm-delete-apply'));
  } else {
    final label = harness.kind == MailProviderKind.ews
        ? _strings.ewsDelete
        : _strings.mailCloudDelete;
    await tester.tap(find.byTooltip(label));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(harness.commands, isEmpty);
    await tester.tap(find.widgetWithText(FilledButton, label));
  }
}

Future<MailStoredFlagBatch> _reopenMembershipReceipt(
  WidgetTester tester,
  _Harness harness,
) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await settleMailJournal(tester, harness.fixture.reopen);
  final page = (await tester.runAsync(() => harness.fixture.store.list()))!;
  expect(page.batches, hasLength(1));
  return (await tester.runAsync(
    () => harness.fixture.store.load(page.batches.single.id),
  ))!;
}

void membershipHostTests() {
  for (final kind in [
    MailProviderKind.imap,
    MailProviderKind.ews,
    MailProviderKind.gmail,
    MailProviderKind.graph,
  ]) {
    testWidgets(
      '${kind.name} connected history checks membership without replay and requires refresh',
      (tester) async {
        final harness = _Harness(kind);
        await _show(tester, harness);
        final historical = await _historicalUncertainty(
          tester,
          harness,
          action: kind == MailProviderKind.gmail
              ? MailBulkFlagAction.delete
              : MailBulkFlagAction.move,
        );
        final headerReads = harness.headerReads;
        await _openActivity(tester, historical);
        expect(harness.membershipObservations, isEmpty);
        await tester.ensureVisible(_key('studio-mail-activity-check-location'));
        await tester.tap(_key('studio-mail-activity-check-location'));
        await _until(
          tester,
          () =>
              _key('studio-mail-activity-location-0').evaluate().isNotEmpty &&
              find.byType(LinearProgressIndicator).evaluate().isEmpty,
        );
        expect(harness.membershipObservations, hasLength(1));
        final observed = harness.membershipObservations.single.$1;
        expect(observed.account, harness.liveAccount);
        expect(observed.provider, kind);
        if (observed is MailImapIdentity) {
          expect(
            (observed.mailbox.value, observed.uidValidity, observed.uid),
            ('Archive/2025', 191, 501),
          );
        } else {
          expect((observed as MailOpaqueIdentity).value, 'historical-item-501');
        }
        expect(harness.flagObservations, isEmpty);
        expect(harness.commands, isEmpty);
        expect(harness.bodyReads, 0);
        expect(harness.sends, 0);
        expect(harness.headerReads, headerReads);
        await tester.tap(_key('studio-mail-activity-close'));
        await _until(
          tester,
          () => _key('studio-mail-activity-dialog').evaluate().isEmpty,
        );
        expect(
          find.text(_strings.mailWorkspaceRefreshRequired),
          findsOneWidget,
        );
        expect(_list(tester).bulkActionsEnabled, isFalse);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await settleMailJournal(tester, harness.fixture.reopen);
        final saved = (await tester.runAsync(
          () => harness.fixture.store.load(historical.summary.id),
        ))!;
        expect(saved!.membershipObservations, hasLength(1));
        expect(
          saved.membershipObservations.single.observation.identity,
          saved.report.items.first.message,
        );
        expect(saved.summary.unresolvedCount, 1);
        expect(saved.summary.uncertainCount, 1);
        expect(saved.summary.reconciledCount, 0);
        expect(
          saved.report.plan.destination,
          historical.report.plan.destination,
        );
        expect(saved.resolutions, isEmpty);
        expect(harness.commands, isEmpty);
      },
    );
  }

  testWidgets('IMAP organization works without legacy flag setters', (
    tester,
  ) async {
    final harness = _Harness(MailProviderKind.imap)..membershipOnly = true;
    await _show(tester, harness);
    await _openFirst(tester);
    await _startMembership(tester, harness, MailBulkFlagAction.move);
    await _until(
      tester,
      () => harness.commands.isNotEmpty && !_list(tester).busy,
    );
    expect(harness.commands.single, isA<MailMove>());
    expect(_status(tester).report.confirmedCount, 1);
    expect(_list(tester).items, hasLength(2));
  });

  testWidgets('IMAP Mark deleted preserves unknown read and flag state', (
    tester,
  ) async {
    final harness = _Harness(MailProviderKind.imap)
      ..nativeFlagsKnown = false
      ..nativeObservedFlags = null;
    await _show(tester, harness);
    await _openFirst(tester);
    expect(_list(tester).items.first.isRead, isNull);
    expect(_list(tester).items.first.isFlagged, isNull);
    await _startMembership(tester, harness, MailBulkFlagAction.delete);
    await _until(
      tester,
      () => harness.commands.isNotEmpty && !_list(tester).busy,
    );
    expect(_status(tester).report.confirmedCount, 1);
    expect(_list(tester).items.first.isRead, isNull);
    expect(_list(tester).items.first.isFlagged, isNull);
  });

  for (final confirmed in [true, false]) {
    testWidgets(
      'IMAP ${confirmed ? 'confirmed' : 'failed'} Move retains other rows observed flags',
      (tester) async {
        final harness = _Harness(MailProviderKind.imap)
          ..nativeObservedFlags = const MailMessageFlags(isFlagged: true)
          ..respond = (_) async => confirmed
              ? _success
              : const MailFailure(
                  MailProblem(
                    MailProblemCode.permissionDenied,
                    mutationMayHaveOccurred: false,
                  ),
                );
        await _show(tester, harness);
        await _openFirst(tester);
        final survivorId = _list(tester).items[1].id;
        expect(_list(tester).items[1].isRead, isFalse);
        expect(_list(tester).items[1].isFlagged, isTrue);
        await _startMembership(tester, harness, MailBulkFlagAction.move);
        await _until(
          tester,
          () => harness.commands.isNotEmpty && !_list(tester).busy,
        );
        final survivor = _list(
          tester,
        ).items.singleWhere((item) => item.id == survivorId);
        expect(survivor.isRead, isFalse);
        expect(survivor.isFlagged, isTrue);
        expect(_status(tester).report.confirmedCount, confirmed ? 1 : 0);
        expect(_status(tester).report.failedCount, confirmed ? 0 : 1);
      },
    );
  }

  for (final kind in [
    MailProviderKind.imap,
    MailProviderKind.ews,
    MailProviderKind.gmail,
    MailProviderKind.graph,
  ]) {
    for (final action in [
      if (kind != MailProviderKind.gmail) MailBulkFlagAction.move,
      MailBulkFlagAction.delete,
    ]) {
      testWidgets(
        '${kind.name} ${action.name} controls save intent and dispatch marker before provider work',
        (tester) async {
          final harness = _Harness(kind);
          await _show(tester, harness);
          await _openFirst(tester);
          final bodyReads = harness.bodyReads;
          await _startMembership(tester, harness, action);
          await _until(
            tester,
            () => harness.commands.isNotEmpty && !_list(tester).busy,
          );
          expect(harness.commands, hasLength(1));
          final applying = harness.atDispatch.single;
          expect(applying.summary.complete, isFalse);
          expect(applying.report.uncertainCount, 1);
          expect(applying.report.plan.action, action);
          expect(applying.report.plan.mailbox.account, harness.fixture.account);
          expect(
            applying.report.plan.messages.single.account,
            harness.fixture.account,
          );
          if (action == MailBulkFlagAction.move) {
            final dispatched = harness.commands.single as MailMove;
            expect(dispatched.destination.account, harness.liveAccount);
            expect(
              applying.report.plan.destination!.account,
              harness.fixture.account,
            );
            expect(
              applying.report.plan.destination!.value,
              kind == MailProviderKind.imap ? 'Archive' : 'archive',
            );
          } else {
            expect(harness.commands.single, isA<MailDelete>());
            expect(applying.report.plan.destination, isNull);
          }
          expect(_status(tester).report.confirmedCount, 1);
          expect(_status(tester).report.persistenceProblem, isNull);
          expect(_list(tester).bulkActionsEnabled, isFalse);
          expect(harness.bodyReads, bodyReads);
          expect(harness.sends, 0);
          if (kind == MailProviderKind.imap &&
              action == MailBulkFlagAction.delete) {
            expect(
              _list(tester).items,
              hasLength(3),
              reason: 'IMAP Deleted is not an expunge',
            );
          } else {
            expect(_list(tester).items, hasLength(2));
            expect(find.byType(MailMessageView), findsNothing);
          }
          final receipt = await _reopenMembershipReceipt(tester, harness);
          expect(receipt.report.confirmedCount, 1);
          expect(receipt.summary.complete, isTrue);
          expect(receipt.report.plan.action, action);
          expect(
            receipt.report.plan.destination,
            applying.report.plan.destination,
          );
          expect(receipt.subjects, ['Frozen subject 1']);
          expect(
            harness.commands,
            hasLength(1),
            reason: 'Reopen must never replay',
          );
        },
      );
    }

    final action = kind == MailProviderKind.gmail
        ? MailBulkFlagAction.delete
        : MailBulkFlagAction.move;
    for (final failedWrite in [1, 2]) {
      testWidgets(
        '${kind.name} membership write $failedWrite failure blocks provider dispatch',
        (tester) async {
          final harness = _Harness(kind);
          await _show(tester, harness);
          await _openFirst(tester);
          harness.fixture.failCommit = harness.fixture.commits + failedWrite;
          await _startMembership(tester, harness, action);
          await _until(
            tester,
            () =>
                find.byType(StudioMailBulkStatus).evaluate().isNotEmpty &&
                !_list(tester).busy,
          );
          expect(harness.commands, isEmpty);
          expect(harness.atDispatch, isEmpty);
          expect(_status(tester).report.unattemptedCount, 1);
          expect(
            _status(tester).report.persistenceProblem?.code,
            MailProblemCode.storageFailure,
          );
          expect(_list(tester).items, hasLength(3));
          expect(harness.sends, 0);
          harness.fixture.failCommit = null;
        },
      );
    }

    testWidgets(
      '${kind.name} unconfirmed organization stays uncertain through reopening without replay',
      (tester) async {
        final harness = _Harness(kind)
          ..respond = (_) async => const MailFailure(
            MailProblem(
              MailProblemCode.providerFailure,
              mutationMayHaveOccurred: true,
            ),
          );
        await _show(tester, harness);
        await _openFirst(tester);
        await _startMembership(tester, harness, action);
        await _until(
          tester,
          () => harness.commands.isNotEmpty && !_list(tester).busy,
        );
        expect(_status(tester).report.uncertainCount, 1);
        expect(_list(tester).items, hasLength(3));
        expect(_list(tester).bulkActionsEnabled, isFalse);
        final receipt = await _reopenMembershipReceipt(tester, harness);
        expect(receipt.summary.unresolvedCount, 1);
        expect(receipt.report.uncertainCount, 1);
        expect(receipt.summary.canCheckFlags, isFalse);
        expect(receipt.resolutions, isEmpty);
        expect(harness.commands, hasLength(1));
        expect(harness.flagObservations, isEmpty);
        expect(harness.sends, 0);
      },
    );

    testWidgets(
      '${kind.name} closing an applying membership command retains the late receipt',
      (tester) async {
        final gate = Completer<MailResult<MailUnit>>();
        final harness = _Harness(kind)..respond = (_) => gate.future;
        await _show(tester, harness);
        await _openFirst(tester);
        await _startMembership(tester, harness, action);
        await _until(tester, () => harness.commands.isNotEmpty);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        gate.complete(_success);
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 20));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)),
          );
        }
        final receipt = await _reopenMembershipReceipt(tester, harness);
        expect(receipt.report.confirmedCount, 1);
        expect(receipt.report.uncertainCount, 0);
        expect(harness.commands, hasLength(1));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'IMAP denied membership capability performs no command or body fetch',
    (tester) async {
      final harness = _Harness(MailProviderKind.imap)..allowMembership = false;
      await _show(tester, harness);
      await _openFirst(tester);
      final bodyReads = harness.bodyReads;
      await tester.tap(_key('studio-mail-move-message'));
      await _until(
        tester,
        () => !_list(tester).busy && harness.capabilityReads == 1,
      );
      expect(find.text(_strings.mailMutationUnavailable), findsOneWidget);
      expect(harness.commands, isEmpty);
      expect(harness.bodyReads, bodyReads);
      expect(_key('studio-mail-move-picker'), findsNothing);
    },
  );

  testWidgets(
    'IMAP delete cancellation preserves mail and creates no journal',
    (tester) async {
      final harness = _Harness(MailProviderKind.imap);
      await _show(tester, harness);
      await _openFirst(tester);
      await tester.tap(_key('studio-mail-delete-message'));
      await _until(
        tester,
        () => _key('studio-mail-confirm-delete').evaluate().isNotEmpty,
      );
      expect(find.text(_strings.mailMarkDeletedExplanation), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, _strings.cancel));
      await _until(
        tester,
        () =>
            !_list(tester).busy &&
            _key('studio-mail-confirm-delete').evaluate().isEmpty,
      );
      expect(harness.commands, isEmpty);
      final page = (await tester.runAsync(() => harness.fixture.store.list()))!;
      expect(page.batches, isEmpty);
      expect(_list(tester).items, hasLength(3));
    },
  );

  testWidgets('Gmail cannot choose a folder move without provider support', (
    tester,
  ) async {
    final harness = _Harness(MailProviderKind.gmail);
    await _show(tester, harness);
    await _openFirst(tester);
    expect(
      tester
          .widget<PopupMenuButton<MailMailbox>>(
            find.byType(PopupMenuButton<MailMailbox>),
          )
          .enabled,
      isFalse,
    );
    expect(harness.commands, isEmpty);
  });
}
