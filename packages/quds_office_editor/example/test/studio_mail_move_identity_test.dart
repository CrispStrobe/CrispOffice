import 'dart:async';

import 'package:enough_mail/enough_mail.dart' as mail;
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:quds_office_studio/studio_mail_mailbox_store.dart';
import 'package:quds_office_studio/studio_mail_message_loader.dart';

import 'support/mail_flag_journal.dart';

MailMoveIdentityTransition _transition(
  MailMove command,
  MailMailboxId sourceMailbox,
) {
  final destination = command.message is MailImapIdentity
      ? MailImapIdentity(
          mailbox: command.destination,
          uidValidity: 291,
          uid: 907,
        )
      : MailOpaqueIdentity(
          account: command.message.account,
          provider: command.message.provider,
          value: 'new-exact-provider-id',
        );
  return MailMoveIdentityTransition(
    operationId: command.id,
    source: command.message,
    sourceMailbox: sourceMailbox,
    destination: destination,
    destinationMailbox: command.destination,
    destinationMessageId: MailMessageId('provider-local-id-is-not-studio-id'),
  );
}

MailBulkFlagPlan _plan(TestMailFlagJournal fixture, String id) {
  final selected = fixture.plan(id, count: 1);
  return MailBulkFlagPlan(
    id: id,
    mailbox: selected.mailbox,
    action: MailBulkFlagAction.move,
    messages: selected.messages,
    destination: MailMailboxId(
      'Archive/Projects 2026',
      account: selected.mailbox.account,
    ),
  );
}

final class _ReceiptProvider
    implements MailProvider, MailMutationReceiptProvider {
  _ReceiptProvider(this.account, this.answer);

  @override
  final MailAccountId account;
  final Future<MailResult<MailMutationReceipt>> Function(
    MailOperation,
    MailOperationLease,
  )
  answer;
  int calls = 0;

  @override
  Future<MailResult<MailMutationReceipt>> applyWithReceipt(
    MailOperation command,
    MailOperationLease lease,
  ) {
    calls++;
    return answer(command, lease);
  }

  @override
  Object? noSuchMethod(Invocation invocation) =>
      throw StateError('No unit mutation or read is expected.');
}

final class _LegacyProvider implements MailProvider {
  _LegacyProvider(this.account, this.result);
  @override
  final MailAccountId account;
  final MailResult<MailUnit> result;
  int calls = 0;

  @override
  Future<MailResult<MailUnit>> apply(
    MailOperation command,
    MailOperationLease lease,
  ) async {
    calls++;
    return result;
  }

  @override
  Object? noSuchMethod(Invocation invocation) =>
      throw StateError('Only a unit mutation is expected.');
}

final class _SnapshotProvider implements MailProvider {
  _SnapshotProvider(this.account, this.pull);
  @override
  final MailAccountId account;
  final Future<MailSyncPage> Function(MailMailboxId, MailCursor?) pull;
  @override
  Future<MailResult<MailSyncPage>> pullChanges(
    MailMailboxId mailbox, {
    MailCursor? cursor,
    required int limit,
    required MailOperationLease lease,
  }) async => MailSuccess(await pull(mailbox, cursor));
  @override
  Object? noSuchMethod(Invocation invocation) =>
      throw StateError('Only explicit synchronization is expected.');
}

mail.MailAccount _account() => mail.MailAccount.fromManualSettingsWithAuth(
  name: 'Move fixture',
  email: 'fixture@example.test',
  incomingHost: 'imap.example.test',
  outgoingHost: 'smtp.example.test',
  auth: mail.PlainAuthentication('fixture', 'fixture-only-password'),
  incomingType: mail.ServerType.imap,
  incomingPort: 993,
  incomingSocketType: mail.SocketType.ssl,
);

MailMove _command(NativeStudioMailMessageLoader loader) => MailMove(
  id: 'durable-move:0',
  message: MailImapIdentity(
    mailbox: MailMailboxId('INBOX', account: loader.account),
    uidValidity: 73,
    uid: 42,
  ),
  destination: MailMailboxId('Archive/2026', account: loader.account),
);

void main() {
  for (final provider in [MailProviderKind.imap, MailProviderKind.ews]) {
    test(
      '${provider.name} move evidence survives host rebinding and restart',
      () async {
        final fixture = await TestMailFlagJournal.create(provider: provider);
        addTearDown(fixture.dispose);
        final plan = _plan(fixture, 'mapped-move');
        final command = plan.operationAt(0) as MailMove;
        final transition = _transition(command, plan.mailbox);
        final session = MailAccountSession(plan.mailbox.account);
        addTearDown(session.dispose);
        final report = await MailBulkFlagCoordinator().run(
          plan: plan,
          lease: session.begin(),
          isScopeCurrent: () => fixture.current,
          journal: fixture.bind(plan),
          apply: (_, _) async =>
              MailBulkFlagAttempt.confirmed(identityTransition: transition),
        );
        expect(report.items.single.identityTransition, same(transition));
        await fixture.reopen();
        final saved = (await fixture.store.load(plan.id))!;
        final local = saved.report.items.single.identityTransition!;
        expect(local.source.account, fixture.account);
        expect(local.destination.account, fixture.account);
        expect(local.sourceMailbox.account, fixture.account);
        expect(local.destinationMailbox.account, fixture.account);
        expect(
          local.destinationMessageId,
          studioMailCachedMessageId(local.destination),
        );
        expect(
          local.destinationMessageId,
          isNot(transition.destinationMessageId),
        );
        expect(
          local.matches(
            saved.report.items.single.operation,
            sourceMailbox: saved.summary.mailbox,
          ),
          isTrue,
        );
        expect(saved.identityTransitions.single.transition, local);
        expect(saved.identityTransitions.single.cacheProjected, isFalse);
        expect(saved.summary.uncertainCount, 0);
        expect(saved.summary.confirmedCount, 1);
      },
    );
  }

  test(
    'Studio snapshot forwarding rejects an old first-sync page after a move',
    () async {
      final fixture = await TestMailFlagJournal.create();
      addTearDown(fixture.dispose);
      final plan = _plan(fixture, 'move-during-first-sync');
      final source = MailMailboxId(
        plan.mailbox.value,
        account: fixture.account,
      );
      final target = MailMailboxId(
        plan.destination!.value,
        account: fixture.account,
      );
      final original = MailHeaderRecord(
        id: MailMessageId('provider-header-id'),
        remote: MailImapIdentity(mailbox: source, uidValidity: 71, uid: 1),
        envelope: MailEnvelope(subject: 'Saved move subject'),
      );
      final localSession = MailAccountSession(fixture.account);
      final transportSession = MailAccountSession(plan.mailbox.account);
      addTearDown(localSession.dispose);
      addTearDown(transportSession.dispose);
      TestMailFlagJournal.success(
        await fixture.repository.saveMailboxView(
          MailMailbox(id: source, displayName: 'Inbox'),
          [studioMailCachedHeader(original)],
          expectedRevision: null,
          hasMore: false,
          lease: localSession.begin(),
        ),
      );
      TestMailFlagJournal.success(
        await fixture.repository.saveMailboxView(
          MailMailbox(id: target, displayName: 'Archive'),
          [],
          expectedRevision: null,
          hasMore: false,
          lease: localSession.begin(),
        ),
      );
      final hostStore = fixture.owner.mailboxStore;
      expect(hostStore, isA<MailSyncSnapshotRepository>());
      final repository = hostStore as MailSyncSnapshotRepository;
      var moveDuringRead = true;
      final provider = _SnapshotProvider(fixture.account, (
        mailbox,
        cursor,
      ) async {
        expect(cursor, isNull);
        if (moveDuringRead) {
          final moved = await MailBulkFlagCoordinator().run(
            plan: plan,
            lease: transportSession.begin(),
            isScopeCurrent: () => true,
            journal: fixture.bind(plan),
            apply: (command, _) async => MailBulkFlagAttempt.confirmed(
              identityTransition: _transition(
                command as MailMove,
                plan.mailbox,
              ),
            ),
          );
          expect(moved.confirmedCount, 1);
          expect(moved.persistenceProblem, isNull);
        }
        return MailSyncPage(
          mailbox: mailbox,
          upserts: moveDuringRead ? [original] : [],
          tombstones: [],
          next: MailCursor(mailbox: mailbox, value: 'provider-cursor-1'),
          hasMore: false,
        );
      });
      final failed = await const MailSyncRunner().run(
        provider: provider,
        repository: repository,
        session: localSession,
        mailbox: source,
      );
      expect(failed.status, MailSyncRunStatus.failed);
      expect(failed.problem!.code, MailProblemCode.conflict);
      expect(failed.committedPages, 0);
      expect(
        TestMailFlagJournal.success(
          await fixture.repository.loadMailboxView(source),
        )!.headers,
        isEmpty,
      );
      final snapshot = TestMailFlagJournal.success(
        await repository.readSyncSnapshot(source),
      );
      expect(snapshot.cursor, isNull);
      expect(snapshot.revision, 1);
      moveDuringRead = false;
      final fresh = await const MailSyncRunner().run(
        provider: provider,
        repository: repository,
        session: localSession,
        mailbox: source,
      );
      expect(fresh.status, MailSyncRunStatus.completed);
      expect(fresh.committedPages, 1);
      expect(
        TestMailFlagJournal.success(
          await fixture.repository.loadSyncMailbox(source),
        )!.headers,
        isEmpty,
      );
      final cachedTarget = TestMailFlagJournal.success(
        await fixture.repository.loadMailboxView(target),
      )!.headers.single;
      expect(cachedTarget.id, studioMailCachedMessageId(cachedTarget.remote));
      expect(
        (await fixture.store.load(
          plan.id,
        ))!.identityTransitions.single.cacheProjected,
        isTrue,
      );
    },
  );

  test(
    'late acknowledgement remains durable after the host leaves its view',
    () async {
      final fixture = await TestMailFlagJournal.create();
      addTearDown(fixture.dispose);
      final plan = _plan(fixture, 'late-move');
      final session = MailAccountSession(plan.mailbox.account);
      addTearDown(session.dispose);
      final report = await MailBulkFlagCoordinator().run(
        plan: plan,
        lease: session.begin(),
        isScopeCurrent: () => fixture.current,
        journal: fixture.bind(plan),
        apply: (command, _) async {
          fixture.current = false;
          return MailBulkFlagAttempt.confirmed(
            identityTransition: _transition(command as MailMove, plan.mailbox),
          );
        },
      );
      expect(report.confirmedCount, 1);
      await fixture.reopen();
      final saved = (await fixture.store.load(plan.id))!;
      expect(saved.report.items.single.identityTransition, isNotNull);
      expect(saved.summary.confirmedCount, 1);
      expect(saved.summary.stopReason, MailBulkFlagStopReason.staleScope);
    },
  );

  test(
    'lost receipt never manufactures a mapping when the store reopens',
    () async {
      final fixture = await TestMailFlagJournal.create();
      addTearDown(fixture.dispose);
      final plan = _plan(fixture, 'lost-move');
      final session = MailAccountSession(plan.mailbox.account);
      addTearDown(session.dispose);
      var dispatches = 0;
      final report = await MailBulkFlagCoordinator().run(
        plan: plan,
        lease: session.begin(),
        isScopeCurrent: () => fixture.current,
        journal: fixture.bind(plan),
        apply: (command, _) async {
          dispatches++;
          fixture.failWrites = true;
          return MailBulkFlagAttempt.confirmed(
            identityTransition: _transition(command as MailMove, plan.mailbox),
          );
        },
      );
      expect(report.confirmedCount, 1);
      expect(report.items.single.identityTransition, isNotNull);
      expect(report.persistenceProblem, isNotNull);
      await fixture.reopen();
      final saved = (await fixture.store.load(plan.id))!;
      expect(saved.summary.uncertainCount, 1);
      expect(saved.report.items.single.identityTransition, isNull);
      expect(saved.identityTransitions, isEmpty);
      expect(await fixture.store.clearCompleted(), 0);
      expect(dispatches, 1);
    },
  );

  test(
    'opaque evidence from another source folder cannot enter the journal',
    () async {
      final fixture = await TestMailFlagJournal.create(
        provider: MailProviderKind.ews,
      );
      addTearDown(fixture.dispose);
      final plan = _plan(fixture, 'wrong-source');
      final journal = fixture.bind(plan);
      TestMailFlagJournal.success(await journal.prepare(plan));
      TestMailFlagJournal.success(await journal.beginAttempt(0));
      final command = plan.operationAt(0) as MailMove;
      final result = await journal.recordResult(
        0,
        MailBulkFlagItemResult(
          operation: command,
          outcome: MailBulkFlagOutcome.confirmed,
          identityTransition: _transition(
            command,
            MailMailboxId('Another folder', account: plan.mailbox.account),
          ),
        ),
      );
      expect(result, isA<MailFailure<MailUnit>>());
      await fixture.reopen();
      final saved = (await fixture.store.load(plan.id))!;
      expect(saved.identityTransitions, isEmpty);
      expect(saved.summary.uncertainCount, 1);
    },
  );

  test(
    'native loader selects receipt capability and retains a late reply',
    () async {
      final response = Completer<MailResult<MailMutationReceipt>>();
      late _ReceiptProvider provider;
      late MailMove sent;
      final loader = NativeStudioMailMessageLoader(
        _account(),
        providerFactory:
            ({
              required configuration,
              required credentialStore,
              required limits,
            }) => provider = _ReceiptProvider(configuration.account, (
              command,
              lease,
            ) {
              sent = command as MailMove;
              return response.future;
            }),
      );
      final session = MailAccountSession(loader.account);
      addTearDown(session.dispose);
      final requested = _command(loader);
      final pending = loader.applyMembershipWithReceipt(
        requested,
        session.begin(),
      );
      loader.dispose();
      final transition = _transition(
        sent,
        (sent.message as MailImapIdentity).mailbox,
      );
      final result = MailSuccess(
        MailMutationReceipt(identityTransition: transition),
      );
      response.complete(result);
      expect(await pending, same(result));
      expect(provider.calls, 1);
      expect(sent, same(requested));
      final later = await loader.applyMembershipWithReceipt(
        requested,
        session.begin(),
      );
      expect(later, isA<MailFailure<MailMutationReceipt>>());
      expect(provider.calls, 1);
    },
  );

  test(
    'legacy provider unit success does not invent a destination identity',
    () async {
      late _LegacyProvider provider;
      final loader = NativeStudioMailMessageLoader(
        _account(),
        providerFactory:
            ({
              required configuration,
              required credentialStore,
              required limits,
            }) => provider = _LegacyProvider(
              configuration.account,
              const MailSuccess(MailUnit.value),
            ),
      );
      addTearDown(loader.dispose);
      final session = MailAccountSession(loader.account);
      addTearDown(session.dispose);
      final result = await loader.applyMembershipWithReceipt(
        _command(loader),
        session.begin(),
      );
      expect(result, isA<MailSuccess<MailMutationReceipt>>());
      expect(
        (result as MailSuccess<MailMutationReceipt>).value.identityTransition,
        isNull,
      );
      expect(provider.calls, 1);
    },
  );

  for (final evidence in <bool?>[false, true, null]) {
    test(
      'receipt adapter preserves provider failure evidence $evidence',
      () async {
        final problem = MailProblem(
          MailProblemCode.conflict,
          mutationMayHaveOccurred: evidence,
        );
        late _ReceiptProvider provider;
        final loader = NativeStudioMailMessageLoader(
          _account(),
          providerFactory:
              ({
                required configuration,
                required credentialStore,
                required limits,
              }) => provider = _ReceiptProvider(
                configuration.account,
                (_, _) async => MailFailure(problem),
              ),
        );
        addTearDown(loader.dispose);
        final session = MailAccountSession(loader.account);
        addTearDown(session.dispose);
        final result = await loader.applyMembershipWithReceipt(
          _command(loader),
          session.begin(),
        );
        expect(
          (result as MailFailure<MailMutationReceipt>).problem,
          same(problem),
        );
        expect(provider.calls, 1);
      },
    );
  }
}
