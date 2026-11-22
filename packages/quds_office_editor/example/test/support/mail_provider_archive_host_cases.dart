part of '../studio_mail_journal_host_test.dart';

Future<void> _startProviderArchive(
  WidgetTester tester,
  _Harness harness, {
  int count = 2,
  bool single = false,
  bool confirm = true,
}) async {
  if (single) {
    await _openFirst(tester);
    await tester.tap(_key('studio-mail-archive-message'));
  } else {
    final list = _list(tester);
    expect(list.supportedBulkActions, contains(MailBulkFlagAction.archive));
    list.onBulkAction!(
      MailBulkFlagAction.archive,
      list.items.take(count).map((row) => row.id).toList(),
    );
  }
  await _until(
    tester,
    () => _key('studio-mail-archive-selection-dialog').evaluate().isNotEmpty,
  );
  expect(harness.commands, isEmpty);
  if (!confirm) return;
  await _confirmProviderArchive(tester);
}

Future<void> _confirmProviderArchive(WidgetTester tester) async {
  if (_key('studio-mail-archive-destination-0').evaluate().isNotEmpty) {
    await tester.tap(_key('studio-mail-archive-destination-0'));
    await tester.pump();
  }
  await tester.tap(_key('studio-mail-archive-apply'));
}

void providerArchiveHostTests() {
  for (final kind in [
    MailProviderKind.imap,
    MailProviderKind.ews,
    MailProviderKind.gmail,
    MailProviderKind.graph,
  ]) {
    for (final single in [false, true]) {
      testWidgets(
        '${kind.name} ${single ? 'single' : 'bulk'} provider Archive persists exact reviewed intent',
        (tester) async {
          final harness = _Harness(kind)..archiveEnabled = true;
          await _show(tester, harness);
          await _startProviderArchive(tester, harness, single: single);
          final count = single ? 1 : 2;
          await _until(
            tester,
            () => harness.commands.length == count && !_list(tester).busy,
          );
          expect(
            harness.commands,
            everyElement(
              kind == MailProviderKind.gmail
                  ? isA<MailArchive>()
                  : isA<MailMove>(),
            ),
          );
          final action = kind == MailProviderKind.gmail
              ? MailBulkFlagAction.archive
              : MailBulkFlagAction.move;
          expect(
            harness.atDispatch.map((receipt) => receipt.summary.action),
            everyElement(action),
          );
          if (kind == MailProviderKind.gmail) {
            expect(harness.atDispatch.first.summary.mailbox.value, 'INBOX');
            expect(harness.atDispatch.first.summary.destination, isNull);
            expect(harness.archiveResolutionReads, 0);
          } else {
            final destination = kind == MailProviderKind.imap
                ? 'Archive'
                : 'archive';
            expect(
              harness.commands.cast<MailMove>().map(
                (command) => command.destination.value,
              ),
              everyElement(destination),
            );
            expect(
              harness.atDispatch.first.summary.destination?.value,
              destination,
            );
          }
          expect(_list(tester).items, hasLength(3 - count));
          expect(_list(tester).bulkActionsEnabled, isFalse);
          final receipt = await _reopenMembershipReceipt(tester, harness);
          expect(receipt.report.confirmedCount, count);
          expect(receipt.summary.action, action);
          expect(receipt.summary.canCheckFlags, isFalse);
          expect(
            harness.commands,
            hasLength(count),
            reason: 'Reopening cannot replay Archive',
          );
          expect(harness.sends, 0);
        },
      );
    }

    testWidgets(
      '${kind.name} stale single Archive button cannot act on another reader',
      (tester) async {
        final harness = _Harness(kind)..archiveEnabled = true;
        await _show(tester, harness);
        await _openFirst(tester);
        final oldAction = tester
            .widget<IconButton>(_key('studio-mail-archive-message'))
            .onPressed!;
        final otherId = _list(tester).items[1].id;
        _list(tester).onOpen(otherId);
        await _until(
          tester,
          () => _list(tester).selectedId == otherId && !_list(tester).busy,
        );
        oldAction();
        await tester.pump(const Duration(milliseconds: 350));
        expect(_key('studio-mail-archive-selection-dialog'), findsNothing);
        expect(harness.commands, isEmpty);
      },
    );

    testWidgets('${kind.name} cancelled provider Archive saves no command', (
      tester,
    ) async {
      final harness = _Harness(kind)..archiveEnabled = true;
      await _show(tester, harness);
      final commits = harness.fixture.commits;
      await _startProviderArchive(tester, harness, confirm: false);
      expect(find.text(_strings.mailOrganizationCount(2)), findsOneWidget);
      await tester.tap(_key('studio-mail-organization-cancel'));
      await _until(tester, () => !_list(tester).busy);
      expect(harness.commands, isEmpty);
      expect(harness.fixture.commits, commits);
      expect(_list(tester).items, hasLength(3));
    });

    testWidgets(
      '${kind.name} uncertain Archive saves evidence and stops remaining messages',
      (tester) async {
        final harness = _Harness(kind)..archiveEnabled = true;
        harness.respond = (_) async => const MailFailure(
          MailProblem(
            MailProblemCode.unavailable,
            mutationMayHaveOccurred: true,
          ),
        );
        await _show(tester, harness);
        await _startProviderArchive(tester, harness);
        await _until(
          tester,
          () => harness.commands.length == 1 && !_list(tester).busy,
        );
        expect(_status(tester).report.uncertainCount, 1);
        expect(_status(tester).report.unattemptedCount, 1);
        expect(_list(tester).items, hasLength(3));
        final receipt = await _reopenMembershipReceipt(tester, harness);
        expect(receipt.summary.canCheckMembership, isTrue);
        expect(receipt.summary.unresolvedCount, 1);
        expect(receipt.report.unattemptedCount, 1);
        expect(harness.commands, hasLength(1));
      },
    );
  }

  testWidgets(
    'Gmail Archive is absent outside exact Inbox despite advertised capability',
    (tester) async {
      final harness = _Harness(MailProviderKind.gmail)..archiveEnabled = true;
      await _show(tester, harness);
      expect(
        _list(tester).supportedBulkActions,
        contains(MailBulkFlagAction.archive),
      );
      await tester.tap(find.text('Archive'));
      await _until(
        tester,
        () => harness.headerReads == 2 && !_list(tester).busy,
      );
      final list = _list(tester);
      expect(
        list.supportedBulkActions,
        isNot(contains(MailBulkFlagAction.archive)),
      );
      list.onBulkAction!(MailBulkFlagAction.archive, [list.items.first.id]);
      await tester.pump();
      expect(_key('studio-mail-archive-selection-dialog'), findsNothing);
      expect(harness.commands, isEmpty);
    },
  );

  for (final kind in [MailProviderKind.imap, MailProviderKind.graph]) {
    testWidgets(
      '${kind.name} Archive reviews a newly resolved folder outside the earlier catalog',
      (tester) async {
        final harness = _Harness(kind)..archiveEnabled = true;
        harness.archiveResolution = (lease) async => MailSuccess(
          MailMailbox(
            id: MailMailboxId('newly-resolved-archive', account: lease.account),
            displayName: 'Server filing folder',
          ),
        );
        await _show(tester, harness);
        await _startProviderArchive(tester, harness, confirm: false);
        expect(find.text('newly-resolved-archive'), findsOneWidget);
        expect(_key('studio-mail-archive-destination-0'), findsNothing);
        await _confirmProviderArchive(tester);
        await _until(
          tester,
          () => harness.commands.length == 2 && !_list(tester).busy,
        );
        expect(
          harness.commands.cast<MailMove>().map(
            (command) => command.destination.value,
          ),
          everyElement('newly-resolved-archive'),
        );
        final receipt = await _reopenMembershipReceipt(tester, harness);
        expect(receipt.summary.destination?.value, 'newly-resolved-archive');
      },
    );

    testWidgets(
      '${kind.name} Archive resolution failure never opens manual fallback',
      (tester) async {
        final harness = _Harness(kind)..archiveEnabled = true;
        harness.archiveResolution = (_) async =>
            const MailFailure(MailProblem(MailProblemCode.unavailable));
        await _show(tester, harness);
        final list = _list(tester);
        list.onBulkAction!(MailBulkFlagAction.archive, [list.items.first.id]);
        await _until(
          tester,
          () => harness.archiveResolutionReads == 1 && !_list(tester).busy,
        );
        expect(find.text(_strings.mailMutationCheckFailed), findsOneWidget);
        expect(_key('studio-mail-archive-selection-dialog'), findsNothing);
        expect(harness.commands, isEmpty);
      },
    );

    testWidgets(
      '${kind.name} Archive requires explicit choice when server reports unsupported',
      (tester) async {
        final harness = _Harness(kind)..archiveEnabled = true;
        harness.archiveResolution = (_) async =>
            const MailFailure(MailProblem(MailProblemCode.unsupported));
        await _show(tester, harness);
        await _startProviderArchive(tester, harness, confirm: false);
        expect(
          find.text(_strings.mailArchiveChooseExplanation),
          findsOneWidget,
        );
        expect(
          tester
              .widget<FilledButton>(_key('studio-mail-archive-apply'))
              .onPressed,
          isNull,
        );
        await _confirmProviderArchive(tester);
        await _until(
          tester,
          () => harness.commands.length == 2 && !_list(tester).busy,
        );
        expect(harness.commands, everyElement(isA<MailMove>()));
      },
    );

    testWidgets(
      '${kind.name} late Archive resolution cannot enter a replaced account',
      (tester) async {
        final gate = Completer<MailResult<MailMailbox>>();
        final harness = _Harness(kind)..archiveEnabled = true;
        harness.archiveResolution = (_) => gate.future;
        await _show(tester, harness);
        final list = _list(tester);
        list.onBulkAction!(MailBulkFlagAction.archive, [list.items.first.id]);
        await _until(tester, () => harness.archiveResolutionReads == 1);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        gate.complete(
          MailSuccess(
            MailMailbox(
              id: MailMailboxId('late-archive', account: harness.liveAccount!),
              displayName: 'Archive',
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 350));
        expect(harness.commands, isEmpty);
        expect(_key('studio-mail-archive-selection-dialog'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('IMAP Archive confirmation rejects a changed UID generation', (
    tester,
  ) async {
    final harness = _Harness(MailProviderKind.imap)..archiveEnabled = true;
    await _show(tester, harness);
    await _startProviderArchive(tester, harness, confirm: false);
    final browser = harness.imapBrowser!;
    final message = browser.observations.keys.first;
    final old = browser.observations[message]!;
    final identity = old.remote as MailImapIdentity;
    browser.observations[message] = MailHeaderRecord(
      id: old.id,
      remote: MailImapIdentity(
        mailbox: identity.mailbox,
        uidValidity: identity.uidValidity + 1,
        uid: identity.uid,
      ),
      envelope: old.envelope,
      flags: old.flags,
    );
    await _confirmProviderArchive(tester);
    await _until(tester, () => !_list(tester).busy);
    expect(harness.commands, isEmpty);
  });
}
