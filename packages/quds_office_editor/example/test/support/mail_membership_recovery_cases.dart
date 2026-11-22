part of '../studio_mail_flag_recovery_dialog_test.dart';

final class _MembershipObserver implements MailMembershipObserver {
  _MembershipObserver(this.account);
  @override
  final MailAccountId account;
  final requests = <MailRemoteIdentity>[];
  Future<MailResult<MailMembershipObservation>> Function(MailRemoteIdentity)?
  respond;
  @override
  Future<MailResult<MailMembershipObservation>> observeMembership(
    MailRemoteIdentity identity, {
    required MailOperationLease lease,
  }) async {
    requests.add(identity);
    lease.checkCurrent();
    if (respond != null) return respond!(identity);
    return MailSuccess(switch (identity) {
      final MailImapIdentity imap => MailMembershipObservation.imap(
        identity: imap,
        isDeleted: true,
      ),
      final MailOpaqueIdentity opaque => MailMembershipObservation.folders(
        identity: opaque,
        mailboxes: [MailMailboxId('Archive/Projects 2026', account: account)],
        deletionMailbox: MailMailboxId(
          identity.provider == MailProviderKind.gmail
              ? 'TRASH'
              : 'Deleted Items',
          account: account,
        ),
      ),
    });
  }
}

Future<TestMailFlagJournal> _membershipFixture(
  WidgetTester tester, {
  MailProviderKind provider = MailProviderKind.imap,
}) async {
  final fixture = (await tester.runAsync(() async {
    final fixture = await TestMailFlagJournal.create(provider: provider);
    final source = fixture.plan(_id, count: 1);
    final plan = MailBulkFlagPlan(
      id: _id,
      mailbox: source.mailbox,
      action: provider == MailProviderKind.gmail
          ? MailBulkFlagAction.delete
          : MailBulkFlagAction.move,
      destination: provider == MailProviderKind.gmail
          ? null
          : MailMailboxId(
              'Archive/Projects 2026',
              account: source.mailbox.account,
            ),
      messages: source.messages,
    );
    final session = MailAccountSession(source.mailbox.account);
    try {
      await MailBulkFlagCoordinator().run(
        plan: plan,
        lease: session.begin(),
        isScopeCurrent: () => fixture.current,
        journal: fixture.bind(plan, subjects: ['Quarterly review']),
        apply: (operation, _) async {
          fixture.dispatched.add(operation);
          return const MailBulkFlagAttempt.uncertain(
            MailProblem(
              MailProblemCode.providerFailure,
              mutationMayHaveOccurred: true,
            ),
          );
        },
      );
    } finally {
      session.dispose();
    }
    fixture.now = fixture.now.add(const Duration(minutes: 2));
    return fixture;
  }))!;
  addTearDown(() => settleMailJournal(tester, fixture.dispose));
  return fixture;
}

StudioMailReconcileMembershipBatch _membershipRecovery(
  TestMailFlagJournal fixture,
  _MembershipObserver observer,
) => studioMailMembershipRecovery(
  store: fixture.store,
  observer: observer,
  provider: fixture.provider,
  isCurrent: () => fixture.current,
)!;

Future<void> _membershipStarted(
  WidgetTester tester,
  _MembershipObserver observer,
) async {
  for (var i = 0; i < 100 && observer.requests.isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 5));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
  }
  expect(observer.requests, hasLength(1));
}

void _membershipRecoveryTests() {
  for (final provider in [
    MailProviderKind.imap,
    MailProviderKind.ews,
    MailProviderKind.gmail,
    MailProviderKind.graph,
  ]) {
    testWidgets(
      '${provider.name} membership uses its distinct read-only check and keeps the original uncertainty',
      (tester) async {
        final fixture = await _membershipFixture(tester, provider: provider);
        final observer = _MembershipObserver(fixture.source());
        var flagChecks = 0;
        await _show(
          tester,
          fixture.store,
          membershipRecovery: _membershipRecovery(fixture, observer),
          recovery: (batch, _, _) async {
            flagChecks++;
            return batch;
          },
        );
        await _tap(tester, 'studio-mail-activity-$_id');
        expect(observer.requests, isEmpty);
        expect(_key('studio-mail-activity-check'), findsNothing);
        expect(_key('studio-mail-activity-check-location'), findsOneWidget);
        await _tap(tester, 'studio-mail-activity-check-location');
        expect(observer.requests, hasLength(1));
        expect(flagChecks, 0);
        expect(_key('studio-mail-activity-location-0'), findsOneWidget);
        expect(find.textContaining('1 of 1 uncertain actions'), findsOneWidget);
        expect(
          tester
              .widget<StudioMailBulkStatus>(find.byType(StudioMailBulkStatus))
              .report
              .uncertainCount,
          1,
        );
        expect(fixture.dispatched, hasLength(1));
        final before = (await tester.runAsync(() => fixture.store.load(_id)))!;
        expect(before!.summary.unresolvedCount, 1);
        observer.respond = (identity) async =>
            MailSuccess(MailMembershipObservation.missing(identity: identity));
        fixture.now = fixture.now.add(const Duration(minutes: 1));
        await _tap(tester, 'studio-mail-activity-check-location');
        expect(observer.requests, hasLength(2));
        expect(
          find.textContaining(
            'Its destination and the result of the earlier action are not verified',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('Moved successfully'), findsNothing);
        final after = (await tester.runAsync(() => fixture.store.load(_id)))!;
        expect(after!.membershipObservations, hasLength(1));
        expect(after.summary.unresolvedCount, 1);
        expect(fixture.dispatched, hasLength(1));
      },
    );
  }

  testWidgets(
    'cached membership history reads saved location without a provider and retains cleanup protection',
    (tester) async {
      final fixture = await _membershipFixture(tester);
      final observer = _MembershipObserver(fixture.source());
      await tester.runAsync(() async {
        final before = (await fixture.store.load(_id))!;
        await _membershipRecovery(fixture, observer)(
          before,
          MailCancellationSource().token,
          () => true,
        );
        await fixture.reopen();
      });
      final store = _RecordingStore(fixture.store);
      await _show(tester, store);
      await _tap(tester, 'studio-mail-activity-$_id');
      expect(_key('studio-mail-activity-location-0'), findsOneWidget);
      expect(_key('studio-mail-activity-location-reconnect'), findsOneWidget);
      expect(_key('studio-mail-activity-check-location'), findsNothing);
      expect(store.binds, 0);
      expect(observer.requests, hasLength(1));
      expect(await tester.runAsync(() => fixture.store.clearCompleted()), 0);
    },
  );

  testWidgets('a flag recovery callback cannot authorize a membership check', (
    tester,
  ) async {
    final fixture = await _membershipFixture(tester);
    var checks = 0;
    await _show(
      tester,
      fixture.store,
      recovery: (batch, _, _) async {
        checks++;
        return batch;
      },
    );
    await _tap(tester, 'studio-mail-activity-$_id');
    expect(_key('studio-mail-activity-check-location'), findsNothing);
    expect(_key('studio-mail-activity-check'), findsNothing);
    expect(checks, 0);
    expect(fixture.dispatched, hasLength(1));
  });

  for (final close in [false, true]) {
    testWidgets(
      '${close ? 'closing' : 'stopping'} a membership check prevents a late observation',
      (tester) async {
        final fixture = await _membershipFixture(tester);
        final response = Completer<MailResult<MailMembershipObservation>>();
        final observer = _MembershipObserver(fixture.source())
          ..respond = (_) => response.future;
        await _show(
          tester,
          fixture.store,
          membershipRecovery: _membershipRecovery(fixture, observer),
        );
        await _tap(tester, 'studio-mail-activity-$_id');
        await _tap(
          tester,
          'studio-mail-activity-check-location',
          settle: false,
        );
        await _membershipStarted(tester, observer);
        await _tap(
          tester,
          close
              ? 'studio-mail-activity-close'
              : 'studio-mail-activity-stop-check',
        );
        response.complete(
          MailSuccess(
            MailMembershipObservation.missing(
              identity: observer.requests.single,
            ),
          ),
        );
        await _settle(tester);
        final saved = (await tester.runAsync(() => fixture.store.load(_id)))!;
        expect(saved!.membershipObservations, isEmpty);
        expect(saved.summary.unresolvedCount, 1);
        expect(fixture.dispatched, hasLength(1));
      },
    );
  }

  for (final language in StudioLanguage.values) {
    testWidgets(
      '${language.name} membership status fits compact enlarged text and keeps repeat-check controls',
      (tester) async {
        final fixture = await _membershipFixture(tester);
        final observer = _MembershipObserver(fixture.source());
        await _show(
          tester,
          fixture.store,
          language: language,
          size: const Size(390, 844),
          scale: 1.6,
          membershipRecovery: _membershipRecovery(fixture, observer),
        );
        await _tap(tester, 'studio-mail-activity-$_id');
        await tester.ensureVisible(_key('studio-mail-activity-check-location'));
        await tester.pumpAndSettle();
        await _capture(tester, '${language.name}-membership-check');
        await _tap(tester, 'studio-mail-activity-check-location');
        await tester.ensureVisible(_key('studio-mail-activity-location-0'));
        await tester.pumpAndSettle();
        await _capture(tester, '${language.name}-membership-observed');
        await tester.ensureVisible(_key('studio-mail-activity-check-location'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(_key('studio-mail-activity-check-location'), findsOneWidget);
        expect(fixture.dispatched, hasLength(1));
      },
    );
  }
}
