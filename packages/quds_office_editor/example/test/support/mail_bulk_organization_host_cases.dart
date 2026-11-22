part of '../studio_mail_journal_host_test.dart';

Future<void> _startBulkOrganization(
  WidgetTester tester,
  MailBulkFlagAction action, {
  int count = 3,
  bool confirm = true,
}) async {
  final list = _list(tester);
  expect(list.supportedBulkActions, contains(action));
  list.onBulkAction!(action, [
    for (final row in list.items.take(count)) row.id,
  ]);
  final dialogKey = action == MailBulkFlagAction.move
      ? 'studio-mail-move-selection-dialog'
      : 'studio-mail-delete-selection-dialog';
  await _until(tester, () => _key(dialogKey).evaluate().isNotEmpty);
  if (!confirm) return;
  if (action == MailBulkFlagAction.move) {
    await tester.tap(_key('studio-mail-move-destination-0'));
    await tester.pump();
  }
  await tester.tap(
    _key(
      action == MailBulkFlagAction.move
          ? 'studio-mail-move-apply'
          : 'studio-mail-delete-apply',
    ),
  );
}

void membershipBulkHostTests() {
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
        '${kind.name} bulk ${action.name} confirms exact selection and persists each dispatch before provider work',
        (tester) async {
          final harness = _Harness(kind);
          await _show(tester, harness);
          final untouched = _list(tester).items.last.id;
          final before = harness.fixture.commits;
          await _startBulkOrganization(
            tester,
            action,
            count: 2,
            confirm: false,
          );
          expect(harness.commands, isEmpty);
          expect(harness.fixture.commits, before);
          expect(_key('studio-mail-organization-count'), findsOneWidget);
          expect(_key('studio-mail-organization-account'), findsOneWidget);
          expect(_key('studio-mail-organization-source'), findsOneWidget);
          if (action == MailBulkFlagAction.move) {
            await tester.tap(_key('studio-mail-move-destination-0'));
            await tester.pump();
            expect(harness.commands, isEmpty);
            expect(harness.fixture.commits, before);
          }
          await tester.tap(
            _key(
              action == MailBulkFlagAction.move
                  ? 'studio-mail-move-apply'
                  : 'studio-mail-delete-apply',
            ),
          );
          await _until(
            tester,
            () => harness.commands.length == 2 && !_list(tester).busy,
          );
          expect(harness.atDispatch, hasLength(2));
          for (var i = 0; i < 2; i++) {
            final saved = harness.atDispatch[i];
            expect(saved.summary.complete, isFalse);
            expect(saved.report.plan.action, action);
            expect(saved.report.plan.messages, hasLength(2));
            expect(saved.report.confirmedCount, i);
            expect(saved.report.uncertainCount, 1);
            expect(saved.report.unattemptedCount, 1 - i);
            expect(saved.report.plan.mailbox.account, harness.fixture.account);
            expect(harness.commands[i].message.account, harness.liveAccount);
            if (action == MailBulkFlagAction.move) {
              expect(
                (harness.commands[i] as MailMove).destination.value,
                kind == MailProviderKind.imap ? 'Archive' : 'archive',
              );
            }
          }
          expect(_status(tester).report.confirmedCount, 2);
          expect(_status(tester).report.persistenceProblem, isNull);
          expect(_list(tester).bulkActionsEnabled, isFalse);
          expect(_list(tester).items.map((row) => row.id), contains(untouched));
          expect(
            _list(tester).items,
            hasLength(
              kind == MailProviderKind.imap &&
                      action == MailBulkFlagAction.delete
                  ? 3
                  : 1,
            ),
          );
          expect(harness.bodyReads, 0);
          expect(harness.sends, 0);
          final receipt = await _reopenMembershipReceipt(tester, harness);
          expect(receipt.summary.complete, isTrue);
          expect(receipt.report.confirmedCount, 2);
          expect(receipt.subjects, ['Frozen subject 1', 'Frozen subject 2']);
          expect(
            harness.commands,
            hasLength(2),
            reason: 'Reopen never replays',
          );
        },
      );
    }

    final action = kind == MailProviderKind.gmail
        ? MailBulkFlagAction.delete
        : MailBulkFlagAction.move;
    testWidgets(
      '${kind.name} bulk organization retains an uncertain middle result and never dispatches the tail',
      (tester) async {
        final harness = _Harness(kind);
        harness.respond = (_) async => harness.commands.length == 2
            ? const MailFailure(
                MailProblem(
                  MailProblemCode.unavailable,
                  mutationMayHaveOccurred: true,
                ),
              )
            : _success;
        await _show(tester, harness);
        await _startBulkOrganization(tester, action);
        await _until(
          tester,
          () => harness.commands.length == 2 && !_list(tester).busy,
        );
        final report = _status(tester).report;
        expect(report.confirmedCount, 1);
        expect(report.uncertainCount, 1);
        expect(report.unattemptedCount, 1);
        expect(report.stopReason, MailBulkFlagStopReason.uncertain);
        expect(_list(tester).items, hasLength(2));
        final receipt = await _reopenMembershipReceipt(tester, harness);
        expect(receipt.report.confirmedCount, 1);
        expect(receipt.report.uncertainCount, 1);
        expect(receipt.report.unattemptedCount, 1);
        expect(receipt.summary.unresolvedCount, 1);
        expect(harness.commands, hasLength(2));
      },
    );

    testWidgets(
      '${kind.name} stopped bulk organization saves the current acknowledgement and unattempted tail',
      (tester) async {
        final gate = Completer<MailResult<MailUnit>>();
        final harness = _Harness(kind)..respond = (_) => gate.future;
        await _show(tester, harness);
        await _startBulkOrganization(tester, action);
        await _until(tester, () => harness.commands.length == 1);
        final stop = _list(tester).onCancelBulk;
        expect(stop, isNotNull);
        stop!();
        gate.complete(_success);
        await _until(tester, () => !_list(tester).busy);
        expect(_status(tester).report.confirmedCount, 1);
        expect(_status(tester).report.unattemptedCount, 2);
        expect(
          _status(tester).report.stopReason,
          MailBulkFlagStopReason.cancelled,
        );
        final receipt = await _reopenMembershipReceipt(tester, harness);
        expect(receipt.report.confirmedCount, 1);
        expect(receipt.report.unattemptedCount, 2);
        expect(harness.commands, hasLength(1));
      },
    );

    testWidgets(
      '${kind.name} bulk receipt write failure retains remote success and blocks later dispatch',
      (tester) async {
        final harness = _Harness(kind);
        harness.respond = (_) async {
          harness.fixture.failCommit = harness.fixture.commits + 1;
          return _success;
        };
        await _show(tester, harness);
        await _startBulkOrganization(tester, action);
        await _until(
          tester,
          () => harness.commands.length == 1 && !_list(tester).busy,
        );
        final report = _status(tester).report;
        expect(report.confirmedCount, 1);
        expect(report.unattemptedCount, 2);
        expect(report.persistenceProblem?.code, MailProblemCode.storageFailure);
        expect(report.stopReason, MailBulkFlagStopReason.persistenceFailure);
        harness.fixture.failCommit = null;
        final receipt = await _reopenMembershipReceipt(tester, harness);
        expect(receipt.report.uncertainCount, 1);
        expect(receipt.report.unattemptedCount, 2);
        expect(harness.commands, hasLength(1));
      },
    );
  }

  testWidgets('IMAP cancelled bulk organization creates no durable intent', (
    tester,
  ) async {
    final harness = _Harness(MailProviderKind.imap);
    await _show(tester, harness);
    final commits = harness.fixture.commits;
    await _startBulkOrganization(
      tester,
      MailBulkFlagAction.delete,
      confirm: false,
    );
    await tester.tap(_key('studio-mail-organization-cancel'));
    await _until(tester, () => !_list(tester).busy);
    expect(harness.commands, isEmpty);
    expect(harness.fixture.commits, commits);
    expect(_list(tester).items, hasLength(3));
    expect(harness.bodyReads, 0);
  });

  testWidgets('IMAP bulk confirmation rejects changed UID identity', (
    tester,
  ) async {
    final harness = _Harness(MailProviderKind.imap);
    await _show(tester, harness);
    await _startBulkOrganization(
      tester,
      MailBulkFlagAction.move,
      confirm: false,
    );
    final browser = harness.imapBrowser!;
    final message = browser.observations.keys.first;
    final before = browser.observations[message]!;
    final remote = before.remote as MailImapIdentity;
    browser.observations[message] = MailHeaderRecord(
      id: before.id,
      remote: MailImapIdentity(
        mailbox: remote.mailbox,
        uidValidity: remote.uidValidity + 1,
        uid: remote.uid,
      ),
      envelope: before.envelope,
      flags: before.flags,
    );
    final commits = harness.fixture.commits;
    await tester.tap(_key('studio-mail-move-destination-0'));
    await tester.pump();
    await tester.tap(_key('studio-mail-move-apply'));
    await _until(tester, () => !_list(tester).busy);
    expect(harness.commands, isEmpty);
    expect(harness.fixture.commits, commits);
    expect(_list(tester).items, hasLength(3));
  });

  testWidgets('IMAP bulk action rechecks revoked organization capability', (
    tester,
  ) async {
    final harness = _Harness(MailProviderKind.imap);
    await _show(tester, harness);
    final list = _list(tester);
    expect(list.supportedBulkActions, contains(MailBulkFlagAction.move));
    harness.allowMembership = false;
    list.onBulkAction!(MailBulkFlagAction.move, [
      for (final row in list.items) row.id,
    ]);
    await _until(
      tester,
      () => !_list(tester).busy && harness.capabilityReads == 2,
    );
    expect(harness.commands, isEmpty);
    expect(_key('studio-mail-move-selection-dialog'), findsNothing);
    expect(find.text(_strings.mailMutationUnavailable), findsOneWidget);
    expect(
      _list(tester).supportedBulkActions,
      isNot(contains(MailBulkFlagAction.move)),
    );
  });

  testWidgets('IMAP membership-only adapter exposes and executes bulk Move', (
    tester,
  ) async {
    final harness = _Harness(MailProviderKind.imap)..membershipOnly = true;
    await _show(tester, harness);
    expect(_list(tester).supportedBulkActions, {
      MailBulkFlagAction.move,
      MailBulkFlagAction.delete,
    });
    await _startBulkOrganization(tester, MailBulkFlagAction.move, count: 2);
    await _until(
      tester,
      () => harness.commands.length == 2 && !_list(tester).busy,
    );
    expect(_status(tester).report.confirmedCount, 2);
    expect(harness.commands, everyElement(isA<MailMove>()));
  });
}
