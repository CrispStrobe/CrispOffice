@TestOn('vm')
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:quds_office_studio/studio_mail_flag_journal.dart';

import 'support/mail_flag_journal.dart';

typedef _Respond =
    Future<MailResult<MailMembershipObservation>> Function(
      MailRemoteIdentity identity,
      MailOperationLease lease,
    );

final class _Observer implements MailMembershipObserver {
  _Observer(this.account, {this.respond});
  @override
  final MailAccountId account;
  final _Respond? respond;
  final requests = <MailRemoteIdentity>[];
  final leases = <MailOperationLease>[];
  @override
  Future<MailResult<MailMembershipObservation>> observeMembership(
    MailRemoteIdentity identity, {
    required MailOperationLease lease,
  }) async {
    requests.add(identity);
    leases.add(lease);
    lease.checkCurrent();
    if (respond != null) return respond!(identity, lease);
    return MailSuccess(switch (identity) {
      final MailImapIdentity imap => MailMembershipObservation.imap(
        identity: imap,
        isDeleted: true,
      ),
      final MailOpaqueIdentity opaque => MailMembershipObservation.folders(
        identity: opaque,
        mailboxes: [MailMailboxId('Archive', account: account)],
        deletionMailbox: MailMailboxId(
          identity.provider == MailProviderKind.gmail ? 'TRASH' : 'Deleted',
          account: account,
        ),
      ),
    });
  }
}

Future<MailStoredFlagBatch> _uncertain(
  TestMailFlagJournal fixture, {
  MailBulkFlagAction action = MailBulkFlagAction.move,
}) async {
  final source = fixture.plan('membership', count: 1);
  final plan = MailBulkFlagPlan(
    id: source.id,
    mailbox: source.mailbox,
    action: action,
    messages: source.messages,
    destination: action == MailBulkFlagAction.move
        ? MailMailboxId('Archive', account: source.mailbox.account)
        : null,
  );
  final session = MailAccountSession(source.mailbox.account);
  try {
    await MailBulkFlagCoordinator().run(
      plan: plan,
      lease: session.begin(),
      isScopeCurrent: () => fixture.current,
      journal: fixture.bind(plan, subjects: ['Uncertain organization']),
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
  fixture.now = fixture.now.add(const Duration(minutes: 1));
  return (await fixture.store.load(plan.id))!;
}

Future<MailStoredFlagBatch> _check(
  TestMailFlagJournal fixture,
  MailStoredFlagBatch batch,
  _Observer observer, {
  MailAccountId? sourceAccount,
  MailProviderKind? provider,
  MailCancellationToken? cancellation,
  bool Function()? isCurrent,
}) => (fixture.store as StudioMailMembershipReconciliationStore)
    .reconcileMembership(
      id: batch.summary.id,
      expectedRevision: batch.summary.revision,
      sourceAccount: sourceAccount ?? observer.account,
      provider: provider ?? fixture.provider,
      observer: observer,
      isCurrent: isCurrent ?? () => fixture.current,
      cancellation: cancellation,
    );

Matcher _problem(MailProblemCode code) => throwsA(
  isA<StudioMailFlagJournalException>().having(
    (error) => error.code,
    'code',
    code,
  ),
);

void main() {
  for (final provider in [
    MailProviderKind.imap,
    MailProviderKind.ews,
    MailProviderKind.gmail,
    MailProviderKind.graph,
  ]) {
    test(
      '${provider.name} reconnect maps exact membership evidence and retains uncertainty',
      () async {
        final fixture = await TestMailFlagJournal.create(provider: provider);
        addTearDown(fixture.dispose);
        final before = await _uncertain(
          fixture,
          action: provider == MailProviderKind.gmail
              ? MailBulkFlagAction.delete
              : MailBulkFlagAction.move,
        );
        await fixture.reopen();
        final observer = _Observer(fixture.source('new-connection'));
        final checked = await _check(fixture, before, observer);
        expect(observer.requests, hasLength(1));
        expect(observer.requests.single.account, observer.account);
        expect(observer.leases.single.account, observer.account);
        final evidence = checked.membershipObservations.single;
        expect(evidence.index, 0);
        expect(
          evidence.observation.identity,
          checked.report.items.single.message,
        );
        expect(
          evidence.observation.mailboxes.every(
            (box) => box.account == fixture.account,
          ),
          isTrue,
        );
        expect(
          evidence.observation.deletionMailbox?.account,
          provider == MailProviderKind.imap ? null : fixture.account,
        );
        expect(evidence.checkedAt, fixture.now);
        expect(checked.summary.uncertainCount, 1);
        expect(checked.summary.unresolvedCount, 1);
        expect(checked.summary.reconciledCount, 0);
        expect(checked.summary.destination, before.summary.destination);
        expect(checked.subjects, before.subjects);
        expect(
          checked.report.items.single.problem?.mutationMayHaveOccurred,
          isTrue,
        );
        expect(fixture.dispatched, hasLength(1));
        expect(await fixture.store.clearCompleted(), 0);
        await fixture.reopen();
        final reopened = (await fixture.store.load(before.summary.id))!;
        expect(reopened.membershipObservations.single.checkedAt, fixture.now);
        expect(reopened.summary.unresolvedCount, 1);
        expect(fixture.dispatched, hasLength(1));
      },
    );
  }

  test(
    'a repeated explicit check replaces evidence without resolving or replaying',
    () async {
      final fixture = await TestMailFlagJournal.create();
      addTearDown(fixture.dispose);
      final original = await _uncertain(fixture);
      final first = await _check(
        fixture,
        original,
        _Observer(fixture.source()),
      );
      fixture.now = fixture.now.add(const Duration(minutes: 2));
      final second = await _check(
        fixture,
        first,
        _Observer(
          fixture.source(),
          respond: (identity, _) async => MailSuccess(
            MailMembershipObservation.missing(identity: identity),
          ),
        ),
      );
      expect(second.membershipObservations, hasLength(1));
      expect(
        second.membershipObservations.single.observation.kind,
        MailMembershipObservationKind.missing,
      );
      expect(second.membershipObservations.single.checkedAt, fixture.now);
      expect(second.summary.revision, greaterThan(first.summary.revision));
      expect(second.summary.unresolvedCount, 1);
      expect(second.report.uncertainCount, 1);
      expect(fixture.dispatched, hasLength(1));
    },
  );

  test(
    'folder replacement evidence preserves the original IMAP generation',
    () async {
      final fixture = await TestMailFlagJournal.create();
      addTearDown(fixture.dispose);
      final original = await _uncertain(
        fixture,
        action: MailBulkFlagAction.delete,
      );
      final checked = await _check(
        fixture,
        original,
        _Observer(
          fixture.source(),
          respond: (identity, _) async => MailSuccess(
            MailMembershipObservation.identityChanged(
              identity: identity as MailImapIdentity,
            ),
          ),
        ),
      );
      final evidence = checked.membershipObservations.single.observation;
      expect(evidence.kind, MailMembershipObservationKind.identityChanged);
      expect((evidence.identity as MailImapIdentity).uidValidity, 71);
      expect(evidence.mailboxes, isEmpty);
      expect(checked.summary.unresolvedCount, 1);
    },
  );

  test(
    'wrong provider, observer account and stale revision fail before a read',
    () async {
      final fixture = await TestMailFlagJournal.create();
      addTearDown(fixture.dispose);
      final original = await _uncertain(fixture);
      final observer = _Observer(fixture.source());
      await expectLater(
        _check(fixture, original, observer, provider: MailProviderKind.graph),
        _problem(MailProblemCode.conflict),
      );
      await expectLater(
        _check(
          fixture,
          original,
          observer,
          sourceAccount: fixture.source('other'),
        ),
        _problem(MailProblemCode.permissionDenied),
      );
      expect(observer.requests, isEmpty);
      await _check(fixture, original, observer);
      final stale = _Observer(fixture.source());
      await expectLater(
        _check(fixture, original, stale),
        _problem(MailProblemCode.conflict),
      );
      expect(stale.requests, isEmpty);
    },
  );

  test('flag commands cannot use membership recovery', () async {
    final fixture = await TestMailFlagJournal.create();
    addTearDown(fixture.dispose);
    final original = await _uncertain(fixture, action: MailBulkFlagAction.flag);
    final observer = _Observer(fixture.source());
    await expectLater(
      _check(fixture, original, observer),
      _problem(MailProblemCode.unsupported),
    );
    expect(observer.requests, isEmpty);
  });

  test(
    'mismatched returned identity cannot be rebound into local evidence',
    () async {
      final fixture = await TestMailFlagJournal.create();
      addTearDown(fixture.dispose);
      final original = await _uncertain(fixture);
      final observer = _Observer(
        fixture.source(),
        respond: (identity, _) async => MailSuccess(
          MailMembershipObservation.missing(
            identity: MailImapIdentity(
              mailbox: (identity as MailImapIdentity).mailbox,
              uidValidity: 71,
              uid: 999,
            ),
          ),
        ),
      );
      await expectLater(
        _check(fixture, original, observer),
        _problem(MailProblemCode.conflict),
      );
      expect(
        (await fixture.store.load(original.summary.id))!.membershipObservations,
        isEmpty,
      );
    },
  );

  for (final retire in [false, true]) {
    test(
      '${retire ? 'retired view' : 'cancellation'} releases an uncooperative read without publishing late evidence',
      () async {
        final fixture = await TestMailFlagJournal.create();
        addTearDown(fixture.dispose);
        final original = await _uncertain(fixture);
        final response = Completer<MailResult<MailMembershipObservation>>();
        final started = Completer<MailRemoteIdentity>();
        final observer = _Observer(
          fixture.source(),
          respond: (identity, _) {
            started.complete(identity);
            return response.future;
          },
        );
        final cancellation = MailCancellationSource();
        final pending = _check(
          fixture,
          original,
          observer,
          cancellation: cancellation.token,
        );
        final expected = expectLater(
          pending,
          _problem(
            retire ? MailProblemCode.staleOperation : MailProblemCode.cancelled,
          ),
        );
        final identity = await started.future;
        if (retire) {
          fixture.current = false;
        } else {
          cancellation.cancel();
        }
        await expected;
        response.complete(
          MailSuccess(MailMembershipObservation.missing(identity: identity)),
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));
        final saved = (await fixture.store.load(original.summary.id))!;
        expect(saved.membershipObservations, isEmpty);
        expect(saved.summary.revision, original.summary.revision);
        expect(fixture.dispatched, hasLength(1));
      },
    );
  }

  test(
    'storage failure leaves previous evidence and uncertainty intact',
    () async {
      final fixture = await TestMailFlagJournal.create();
      addTearDown(fixture.dispose);
      final original = await _uncertain(fixture);
      final first = await _check(
        fixture,
        original,
        _Observer(fixture.source()),
      );
      fixture.now = fixture.now.add(const Duration(minutes: 1));
      fixture.failWrites = true;
      await expectLater(
        _check(
          fixture,
          first,
          _Observer(
            fixture.source(),
            respond: (identity, _) async => MailSuccess(
              MailMembershipObservation.missing(identity: identity),
            ),
          ),
        ),
        _problem(MailProblemCode.storageFailure),
      );
      fixture.failWrites = false;
      final saved = (await fixture.store.load(original.summary.id))!;
      expect(saved.summary.revision, first.summary.revision);
      expect(
        saved.membershipObservations.single.observation.kind,
        MailMembershipObservationKind.present,
      );
      expect(saved.summary.unresolvedCount, 1);
      expect(fixture.dispatched, hasLength(1));
    },
  );

  test(
    'optional recovery factory requires membership support and never dispatches on creation',
    () async {
      final fixture = await TestMailFlagJournal.create();
      addTearDown(fixture.dispose);
      final original = await _uncertain(fixture);
      final observer = _Observer(fixture.source());
      expect(
        studioMailMembershipRecovery(
          store: fixture.store,
          observer: Object(),
          provider: fixture.provider,
          isCurrent: () => true,
        ),
        isNull,
      );
      var checked = 0;
      final callback = studioMailMembershipRecovery(
        store: fixture.store,
        observer: observer,
        provider: fixture.provider,
        isCurrent: () => fixture.current,
        onChecked: () => checked++,
      );
      expect(callback, isNotNull);
      expect(observer.requests, isEmpty);
      await callback!(original, MailCancellationSource().token, () => true);
      expect(checked, 1);
      expect(observer.requests, hasLength(1));
      expect(fixture.dispatched, hasLength(1));
    },
  );
}
