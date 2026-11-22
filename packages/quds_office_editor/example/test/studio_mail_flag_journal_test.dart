import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_office_studio/studio_mail_flag_journal.dart';

import 'support/mail_flag_journal.dart';

MailBulkFlagPlan _membershipPlan(
  TestMailFlagJournal fixture,
  String id,
  MailBulkFlagAction action, {
  String destination = 'Archive/Projects 2026',
}) {
  final selected = fixture.plan(id, count: 2);
  return MailBulkFlagPlan(
    id: selected.id,
    mailbox: selected.mailbox,
    provider: selected.provider,
    action: action,
    messages: selected.messages,
    destination: action == MailBulkFlagAction.move
        ? MailMailboxId(destination, account: selected.mailbox.account)
        : null,
  );
}

Future<MailBulkFlagReport> _runMembership(
  TestMailFlagJournal fixture,
  MailBulkFlagPlan plan, {
  List<String> subjects = const [
    'Frozen first subject',
    'Frozen second subject',
  ],
  MailBulkFlagAttempt outcome = const MailBulkFlagAttempt.confirmed(),
}) async {
  final session = MailAccountSession(plan.mailbox.account);
  try {
    return await MailBulkFlagCoordinator().run(
      plan: plan,
      lease: session.begin(),
      isScopeCurrent: () => fixture.current,
      journal: fixture.bind(plan, subjects: subjects),
      apply: (operation, lease) async {
        fixture.dispatched.add(operation);
        return outcome;
      },
    );
  } finally {
    session.dispose();
  }
}

final class _MembershipObserver implements MailFlagObserver {
  _MembershipObserver(this.account);

  @override
  final MailAccountId account;
  int calls = 0;

  @override
  Future<MailResult<MailFlagObservation>> observeFlags(
    MailRemoteIdentity identity, {
    required MailOperationLease lease,
  }) async {
    calls++;
    return MailSuccess(
      MailFlagObservation.present(
        identity: identity,
        flags: const MailMessageFlags(isRead: true, isFlagged: true),
      ),
    );
  }
}

void main() {
  for (final provider in [
    MailProviderKind.imap,
    MailProviderKind.ews,
    MailProviderKind.gmail,
    MailProviderKind.graph,
  ]) {
    for (final action in [MailBulkFlagAction.move, MailBulkFlagAction.delete]) {
      test(
        '${provider.name} ${action.name} receipts preserve commands in the stable account after restart',
        () async {
          final fixture = await TestMailFlagJournal.create(provider: provider);
          addTearDown(fixture.dispose);
          final plan = _membershipPlan(fixture, 'membership', action);
          final originalDestination = plan.destination;
          final subjects = ['Original subject', 'النص المحفوظ'];
          final report = await _runMembership(
            fixture,
            plan,
            subjects: subjects,
          );
          subjects[0] = 'Changed after dispatch';

          expect(report.confirmedCount, 2);
          expect(fixture.dispatched, hasLength(2));
          expect(
            fixture.dispatched.map((operation) => operation.message.account),
            everyElement(plan.mailbox.account),
          );
          if (action == MailBulkFlagAction.move) {
            expect(
              fixture.dispatched.cast<MailMove>().map(
                (operation) => operation.destination,
              ),
              everyElement(originalDestination),
            );
          } else {
            expect(fixture.dispatched, everyElement(isA<MailDelete>()));
          }

          await fixture.reopen();
          final saved = (await fixture.store.load(plan.id))!;
          final destination = action == MailBulkFlagAction.move
              ? MailMailboxId('Archive/Projects 2026', account: fixture.account)
              : null;
          expect(saved.summary.action, action);
          expect(saved.summary.provider, provider);
          expect(saved.summary.mailbox.account, fixture.account);
          expect(saved.summary.destination, destination);
          expect(saved.report.plan.destination, destination);
          expect(saved.summary.canCheckFlags, isFalse);
          expect(saved.report.confirmedCount, 2);
          expect(saved.subjects, ['Original subject', 'النص المحفوظ']);
          expect(
            saved.report.items.map((item) => item.message.account),
            everyElement(fixture.account),
          );
          if (action == MailBulkFlagAction.move) {
            expect(
              saved.report.items.map(
                (item) => (item.operation as MailMove).destination,
              ),
              everyElement(destination),
            );
          } else {
            expect(
              saved.report.items.map((item) => item.operation),
              everyElement(isA<MailDelete>()),
            );
          }
          if (provider == MailProviderKind.imap) {
            final message =
                saved.report.items.first.message as MailImapIdentity;
            expect(
              (message.mailbox.value, message.uidValidity, message.uid),
              ('INBOX', 71, 1),
            );
          } else {
            expect(
              (saved.report.items.first.message as MailOpaqueIdentity).value,
              'remote-1',
            );
          }
          expect(
            (await fixture.store.list()).batches.single.destination,
            destination,
          );
          expect(plan.destination, originalDestination);
          expect(fixture.dispatched, hasLength(2));
        },
      );
    }
  }

  test(
    'a move receipt rejects a different exact destination before saving',
    () async {
      final fixture = await TestMailFlagJournal.create();
      addTearDown(fixture.dispose);
      final plan = _membershipPlan(
        fixture,
        'frozen-destination',
        MailBulkFlagAction.move,
      );
      final journal = fixture.bind(plan);
      TestMailFlagJournal.success(await journal.prepare(plan));
      TestMailFlagJournal.success(await journal.beginAttempt(0));
      final original = plan.operationAt(0) as MailMove;

      for (final destination in ['archive/Projects 2026', 'Archive/Other']) {
        final result = await journal.recordResult(
          0,
          MailBulkFlagItemResult.restore(
            operation: MailMove(
              id: original.id,
              message: original.message,
              destination: MailMailboxId(
                destination,
                account: original.message.account,
              ),
            ),
            outcome: MailBulkFlagOutcome.confirmed,
          ),
        );
        expect(result, isA<MailFailure<MailUnit>>());
        final saved = (await fixture.store.load(plan.id))!;
        expect(saved.report.confirmedCount, 0);
        expect(saved.summary.destination?.value, 'Archive/Projects 2026');
      }

      TestMailFlagJournal.success(
        await journal.recordResult(
          0,
          MailBulkFlagItemResult.restore(
            operation: original,
            outcome: MailBulkFlagOutcome.confirmed,
          ),
        ),
      );
      final saved = (await fixture.store.load(plan.id))!;
      expect(saved.report.confirmedCount, 1);
      expect(
        (saved.report.items.first.operation as MailMove).destination,
        MailMailboxId('Archive/Projects 2026', account: fixture.account),
      );
      expect(fixture.dispatched, isEmpty);
    },
  );

  for (final provider in [MailProviderKind.imap, MailProviderKind.graph]) {
    for (final action in [MailBulkFlagAction.move, MailBulkFlagAction.delete]) {
      test(
        '${provider.name} uncertain ${action.name} never invokes flag observation recovery',
        () async {
          final fixture = await TestMailFlagJournal.create(provider: provider);
          addTearDown(fixture.dispose);
          final plan = _membershipPlan(fixture, 'uncertain-membership', action);
          await _runMembership(
            fixture,
            plan,
            outcome: const MailBulkFlagAttempt.uncertain(
              MailProblem(
                MailProblemCode.providerFailure,
                mutationMayHaveOccurred: true,
              ),
            ),
          );
          await fixture.reopen();
          final original = (await fixture.store.load(plan.id))!;
          final observer = _MembershipObserver(
            fixture.source('new-connection'),
          );
          final cancellation = MailCancellationSource();
          var checked = 0;
          final recovery = studioMailFlagRecovery(
            store: fixture.store,
            observer: observer,
            provider: provider,
            isCurrent: () => true,
            onChecked: () => checked++,
          )!;
          final unsupported = throwsA(
            isA<StudioMailFlagJournalException>().having(
              (error) => error.code,
              'typed unsupported recovery',
              MailProblemCode.unsupported,
            ),
          );
          await expectLater(
            recovery(original, cancellation.token, () => true),
            unsupported,
          );
          await expectLater(
            (fixture.store as StudioMailFlagReconciliationStore).reconcile(
              id: plan.id,
              expectedRevision: original.summary.revision,
              sourceAccount: observer.account,
              provider: provider,
              observer: observer,
              isCurrent: () => true,
            ),
            unsupported,
          );

          final unchanged = (await fixture.store.load(plan.id))!;
          expect(observer.calls, 0);
          expect(checked, 0);
          expect(unchanged.summary.revision, original.summary.revision);
          expect(unchanged.summary.unresolvedCount, 1);
          expect(unchanged.resolutions, isEmpty);
          expect(unchanged.report.unattemptedCount, 1);
          expect(
            unchanged.report.plan.destination,
            original.report.plan.destination,
          );
          expect(fixture.dispatched, hasLength(1));
        },
      );
    }
  }

  for (final provider in [
    MailProviderKind.imap,
    MailProviderKind.ews,
    MailProviderKind.gmail,
    MailProviderKind.graph,
  ]) {
    test(
      '${provider.name} receipts rebind connection IDs into the stable local account',
      () async {
        final fixture = await TestMailFlagJournal.create(provider: provider);
        addTearDown(fixture.dispose);
        final subjects = ['Quarterly report', 'Bericht', 'تقرير'];
        final source = fixture.source('first-connection');
        final report = await fixture.run(
          'before-restart',
          sourceAccount: source,
          subjects: subjects,
        );
        subjects.clear();
        expect(report.confirmedCount, 3);
        expect(
          fixture.dispatched.every(
            (operation) => operation.message.account == source,
          ),
          isTrue,
        );
        await fixture.reopen();
        final stored = (await fixture.store.load('before-restart'))!;
        expect(stored.summary.mailbox.account, fixture.account);
        expect(
          stored.report.plan.messages.every(
            (message) => message.account == fixture.account,
          ),
          isTrue,
        );
        expect(stored.subjects, ['Quarterly report', 'Bericht', 'تقرير']);
        expect(stored.report.plan.provider, provider);
        if (provider == MailProviderKind.imap) {
          final message = stored.report.plan.messages.first as MailImapIdentity;
          expect(
            (message.mailbox.value, message.uidValidity, message.uid),
            ('INBOX', 71, 1),
          );
        } else {
          expect(
            (stored.report.plan.messages.first as MailOpaqueIdentity).value,
            'remote-1',
          );
        }
        await fixture.run(
          'after-restart',
          sourceAccount: fixture.source('second-connection'),
        );
        expect((await fixture.store.list()).batches.map((batch) => batch.id), [
          'after-restart',
          'before-restart',
        ]);
        expect(fixture.dispatched, hasLength(6));
      },
    );
  }

  test(
    'closed or unavailable production storage prevents every provider dispatch',
    () async {
      final fixture = await TestMailFlagJournal.create();
      addTearDown(fixture.dispose);
      await fixture.owner.close();
      final selected = fixture.plan('closed');
      final session = MailAccountSession(selected.mailbox.account);
      addTearDown(session.dispose);
      var commands = 0;
      for (final journal in [
        fixture.bind(selected),
        studioMailFlagJournal(
          owner: null,
          requireDurable: false,
          sourceAccount: selected.mailbox.account,
          provider: selected.provider,
          subjects: const ['One', 'Two', 'Three'],
          isCurrent: () => true,
        )!,
      ]) {
        final report = await MailBulkFlagCoordinator().run(
          plan: selected,
          lease: session.begin(),
          isScopeCurrent: () => true,
          journal: journal,
          apply: (_, lease) async {
            commands++;
            return const MailBulkFlagAttempt.confirmed();
          },
        );
        expect(report.stopReason, MailBulkFlagStopReason.persistenceFailure);
        expect(report.persistenceProblem?.code, MailProblemCode.storageFailure);
        expect(report.unattemptedCount, 3);
      }
      expect(commands, 0);
    },
  );

  test(
    'only explicitly injected foreground-only owners can omit persistence',
    () {
      final source = MailAccountId(
        'ephemeral',
        profile: MailProfileId('profile', hostId: 'test'),
      );
      final owner = Object();
      expect(
        studioMailFlagJournal(
          owner: owner,
          requireDurable: false,
          sourceAccount: source,
          provider: MailProviderKind.imap,
          subjects: const ['One'],
          isCurrent: () => true,
        ),
        isNull,
      );
      expect(
        studioMailFlagJournal(
          owner: owner,
          requireDurable: true,
          sourceAccount: source,
          provider: MailProviderKind.imap,
          subjects: const ['One'],
          isCurrent: () => true,
        ),
        isA<UnavailableStudioMailFlagJournal>(),
      );
    },
  );

  for (final failingCommit in [1, 2]) {
    test(
      'local commit $failingCommit failure causes zero provider calls and survives reopen',
      () async {
        final fixture = await TestMailFlagJournal.create();
        addTearDown(fixture.dispose);
        fixture.failCommit = failingCommit;
        final report = await fixture.run('not-dispatched');
        expect(report.persistenceProblem?.code, MailProblemCode.storageFailure);
        expect(report.unattemptedCount, 3);
        expect(fixture.dispatched, isEmpty);
        await fixture.reopen();
        final stored = await fixture.store.load('not-dispatched');
        if (failingCommit == 1) {
          expect(stored, isNull);
        } else {
          expect(stored!.report.unattemptedCount, 3);
          expect(stored.report.uncertainCount, 0);
        }
        expect(fixture.dispatched, isEmpty);
      },
    );
  }

  test(
    'a retired view retains the in-flight acknowledgement without dispatching its tail',
    () async {
      final fixture = await TestMailFlagJournal.create();
      addTearDown(fixture.dispose);
      final started = Completer<void>();
      final response = Completer<MailBulkFlagAttempt>();
      final running = fixture.run(
        'retired-view',
        apply: (_) {
          started.complete();
          return response.future;
        },
      );
      await started.future;
      fixture.current = false;
      response.complete(const MailBulkFlagAttempt.confirmed());
      final report = await running;
      expect(report.confirmedCount, 1);
      expect(report.unattemptedCount, 2);
      expect(report.stopReason, MailBulkFlagStopReason.staleScope);
      await fixture.reopen();
      final stored = (await fixture.store.load('retired-view'))!;
      expect(stored.report.confirmedCount, 1);
      expect(stored.report.unattemptedCount, 2);
      expect(stored.report.plan.mailbox.account, fixture.account);
      expect(fixture.dispatched, hasLength(1));
    },
  );

  test(
    'stop after current persists the known reply and never replays the remainder',
    () async {
      final fixture = await TestMailFlagJournal.create();
      addTearDown(fixture.dispose);
      final cancellation = MailCancellationSource();
      final started = Completer<void>();
      final response = Completer<MailBulkFlagAttempt>();
      final running = fixture.run(
        'stopped',
        cancellation: cancellation.token,
        apply: (_) {
          started.complete();
          return response.future;
        },
      );
      await started.future;
      cancellation.cancel();
      response.complete(const MailBulkFlagAttempt.confirmed());
      final report = await running;
      expect(report.stopReason, MailBulkFlagStopReason.cancelled);
      await fixture.reopen();
      final stored = (await fixture.store.load('stopped'))!;
      expect(stored.report.results.map((result) => result.outcome), [
        MailBulkFlagOutcome.confirmed,
        MailBulkFlagOutcome.unattempted,
        MailBulkFlagOutcome.unattempted,
      ]);
      await fixture.store.list();
      await fixture.store.load('stopped');
      expect(fixture.dispatched, hasLength(1));
    },
  );

  test(
    'lost persistence after acknowledgement remains visibly uncertain on reopen',
    () async {
      final fixture = await TestMailFlagJournal.create();
      addTearDown(fixture.dispose);
      final report = await fixture.run(
        'lost-receipt',
        apply: (_) async {
          fixture.failWrites = true;
          return const MailBulkFlagAttempt.confirmed();
        },
      );
      expect(report.confirmedCount, 1);
      expect(report.persistenceProblem, isNotNull);
      expect(fixture.dispatched, hasLength(1));
      await fixture.reopen();
      final stored = (await fixture.store.load('lost-receipt'))!;
      expect(stored.summary.interrupted, isTrue);
      expect(stored.report.results.map((result) => result.outcome), [
        MailBulkFlagOutcome.uncertain,
        MailBulkFlagOutcome.unattempted,
        MailBulkFlagOutcome.unattempted,
      ]);
      expect(fixture.dispatched, hasLength(1));
    },
  );

  test(
    'intent-only and applying markers recover separately with no retry authority',
    () async {
      final fixture = await TestMailFlagJournal.create();
      addTearDown(fixture.dispose);
      final prepared = await fixture.prepare('prepared');
      final applying = await fixture.prepare('applying', begin: true);
      await fixture.reopen();
      expect(
        (await fixture.store.load('prepared'))!.report.unattemptedCount,
        3,
      );
      expect((await fixture.store.load('applying'))!.report.uncertainCount, 1);
      expect(await prepared.beginAttempt(0), isA<MailFailure<MailUnit>>());
      expect(await applying.beginAttempt(1), isA<MailFailure<MailUnit>>());
      expect(fixture.dispatched, isEmpty);
    },
  );

  test(
    'another source namespace and changed desired value cannot alter a frozen receipt',
    () async {
      final fixture = await TestMailFlagJournal.create();
      addTearDown(fixture.dispose);
      final plan = fixture.plan('pinned');
      final journal = fixture.bind(plan);
      TestMailFlagJournal.success(await journal.prepare(plan));
      TestMailFlagJournal.success(await journal.beginAttempt(0));
      final wrongAccount = fixture.plan(
        'pinned',
        sourceAccount: fixture.source('other'),
      );
      expect(
        await journal.recordResult(
          0,
          MailBulkFlagItemResult.restore(
            operation: wrongAccount.operationAt(0),
            outcome: MailBulkFlagOutcome.confirmed,
          ),
        ),
        isA<MailFailure<MailUnit>>(),
      );
      final opposite = fixture.plan(
        'pinned',
        action: MailBulkFlagAction.unflag,
      );
      expect(
        await journal.recordResult(
          0,
          MailBulkFlagItemResult.restore(
            operation: opposite.operationAt(0),
            outcome: MailBulkFlagOutcome.confirmed,
          ),
        ),
        isA<MailFailure<MailUnit>>(),
      );
      expect((await fixture.store.load('pinned'))!.report.confirmedCount, 0);
      TestMailFlagJournal.success(
        await journal.recordResult(
          0,
          MailBulkFlagItemResult.restore(
            operation: plan.operationAt(0),
            outcome: MailBulkFlagOutcome.confirmed,
          ),
        ),
      );
      expect((await fixture.store.load('pinned'))!.report.confirmedCount, 1);
    },
  );

  test('bind freezes subjects before the serialized prepare runs', () async {
    final fixture = await TestMailFlagJournal.create();
    addTearDown(fixture.dispose);
    final subjects = ['First', 'Second', 'Third'];
    final plan = fixture.plan('frozen-subjects');
    final journal = fixture.bind(plan, subjects: subjects);
    subjects[0] = 'Edited after selection';
    TestMailFlagJournal.success(await journal.prepare(plan));
    expect((await fixture.store.load(plan.id))!.subjects, [
      'First',
      'Second',
      'Third',
    ]);
  });

  test(
    'operation IDs remain distinct and contain no account or message data',
    () {
      final ids = {
        for (var i = 0; i < 100; i++) newStudioMailFlagOperationId(),
      };
      expect(ids, hasLength(100));
      expect(
        ids.every((id) => RegExp(r'^flags-[0-9]+-[0-9a-f]{32}$').hasMatch(id)),
        isTrue,
      );
    },
  );
}
