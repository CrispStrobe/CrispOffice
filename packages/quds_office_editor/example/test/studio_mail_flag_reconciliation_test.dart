@TestOn('vm')
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:quds_office_studio/studio_mail_flag_journal.dart';

import 'support/mail_flag_journal.dart';

typedef _Observe =
    Future<MailResult<MailFlagObservation>> Function(
      MailRemoteIdentity identity,
      MailOperationLease lease,
    );

final class _Observer implements MailFlagObserver {
  _Observer(this.account, {this.respond});

  @override
  final MailAccountId account;
  final _Observe? respond;
  final identities = <MailRemoteIdentity>[];
  final leases = <MailOperationLease>[];

  @override
  Future<MailResult<MailFlagObservation>> observeFlags(
    MailRemoteIdentity identity, {
    required MailOperationLease lease,
  }) async {
    identities.add(identity);
    leases.add(lease);
    lease.checkCurrent();
    return respond == null
        ? MailSuccess(
            MailFlagObservation.present(
              identity: identity,
              flags: const MailMessageFlags(isRead: true, isFlagged: true),
            ),
          )
        : await respond!(identity, lease);
  }
}

Future<MailStoredFlagBatch> _uncertain(
  TestMailFlagJournal fixture, {
  String id = 'uncertain',
  MailBulkFlagAction action = MailBulkFlagAction.flag,
  int count = 3,
  bool firstConfirmed = false,
}) async {
  var attempts = 0;
  await fixture.run(
    id,
    count: count,
    action: action,
    apply: (_) async => firstConfirmed && attempts++ == 0
        ? const MailBulkFlagAttempt.confirmed()
        : const MailBulkFlagAttempt.uncertain(
            MailProblem(
              MailProblemCode.providerFailure,
              mutationMayHaveOccurred: true,
            ),
          ),
  );
  fixture.now = fixture.now.add(const Duration(minutes: 1));
  return (await fixture.store.load(id))!;
}

Future<MailStoredFlagBatch> _check(
  TestMailFlagJournal fixture,
  MailStoredFlagBatch batch,
  _Observer observer, {
  MailAccountId? sourceAccount,
  MailProviderKind? provider,
  int? revision,
  MailCancellationToken? cancellation,
  bool Function()? isCurrent,
}) => (fixture.store as StudioMailFlagReconciliationStore).reconcile(
  id: batch.summary.id,
  expectedRevision: revision ?? batch.summary.revision,
  sourceAccount: sourceAccount ?? observer.account,
  provider: provider ?? fixture.provider,
  observer: observer,
  isCurrent: isCurrent ?? () => fixture.current,
  cancellation: cancellation,
);

Matcher _problem(MailProblemCode code) => throwsA(
  isA<StudioMailFlagJournalException>().having(
    (error) => error.code,
    'typed problem',
    code,
  ),
);

Future<void> _stillUnresolved(
  TestMailFlagJournal fixture,
  MailStoredFlagBatch original,
) async {
  final stored = (await fixture.store.load(original.summary.id))!;
  expect(stored.summary.revision, original.summary.revision);
  expect(stored.summary.unresolvedCount, 1);
  expect(stored.resolutions, isEmpty);
  expect(stored.report.uncertainCount, 1);
  expect(stored.subjects, original.subjects);
}

void main() {
  for (final provider in [
    MailProviderKind.imap,
    MailProviderKind.ews,
    MailProviderKind.gmail,
    MailProviderKind.graph,
  ]) {
    test(
      '${provider.name} recovery maps exact identities into the new connection and retains historical uncertainty',
      () async {
        final fixture = await TestMailFlagJournal.create(provider: provider);
        addTearDown(fixture.dispose);
        final before = await _uncertain(fixture, firstConfirmed: true);
        final originalDispatches = fixture.dispatched.length;
        await fixture.reopen();
        final observer = _Observer(fixture.source('after-reconnect'));
        final checked = await _check(fixture, before, observer);

        expect(observer.identities, hasLength(1));
        final requested = observer.identities.single;
        expect(requested.account, observer.account);
        expect(requested.provider, provider);
        expect(observer.leases.single.account, observer.account);
        if (requested is MailImapIdentity) {
          expect(
            (requested.mailbox.value, requested.uidValidity, requested.uid),
            ('INBOX', 71, 2),
          );
        } else {
          expect((requested as MailOpaqueIdentity).value, 'remote-2');
        }
        expect(checked.summary.mailbox.account, fixture.account);
        expect(checked.report.plan.messages[1].account, fixture.account);
        expect(checked.resolutions.single.index, 1);
        expect(checked.resolutions.single.kind, MailFlagResolutionKind.matches);
        expect(checked.resolutions.single.checkedAt, fixture.now);
        expect(checked.summary.unresolvedCount, 0);
        expect(checked.summary.reconciledCount, 1);
        expect(checked.summary.uncertainCount, 1);
        expect(checked.report.items.map((item) => item.outcome), [
          MailBulkFlagOutcome.confirmed,
          MailBulkFlagOutcome.uncertain,
          MailBulkFlagOutcome.unattempted,
        ]);
        expect(
          checked.report.items[1].problem?.mutationMayHaveOccurred,
          isTrue,
        );
        expect(checked.subjects, before.subjects);
        expect(fixture.dispatched, hasLength(originalDispatches));
        await fixture.reopen();
        final reopened = (await fixture.store.load(before.summary.id))!;
        expect(
          reopened.resolutions.single.kind,
          MailFlagResolutionKind.matches,
        );
        expect(reopened.summary.uncertainCount, 1);
        expect(reopened.summary.unresolvedCount, 0);
        expect(fixture.dispatched, hasLength(originalDispatches));
      },
    );
  }

  for (final (action, observed, expected) in [
    (MailBulkFlagAction.markRead, true, MailFlagResolutionKind.matches),
    (MailBulkFlagAction.markUnread, true, MailFlagResolutionKind.differs),
    (MailBulkFlagAction.flag, false, MailFlagResolutionKind.differs),
    (MailBulkFlagAction.unflag, false, MailFlagResolutionKind.matches),
  ]) {
    test(
      '${action.name} records the observed desired-state comparison',
      () async {
        final fixture = await TestMailFlagJournal.create();
        addTearDown(fixture.dispose);
        final before = await _uncertain(fixture, action: action);
        final observer = _Observer(
          fixture.source(),
          respond: (identity, _) async => MailSuccess(
            MailFlagObservation.present(
              identity: identity,
              flags: MailMessageFlags(isRead: observed, isFlagged: observed),
            ),
          ),
        );
        final checked = await _check(fixture, before, observer);
        expect(checked.resolutions.single.kind, expected);
        expect(
          checked.report.items.first.outcome,
          MailBulkFlagOutcome.uncertain,
        );
        expect(fixture.dispatched, hasLength(1));
      },
    );
  }

  for (final kind in [
    MailFlagResolutionKind.missing,
    MailFlagResolutionKind.identityChanged,
  ]) {
    test(
      '${kind.name} closes uncertainty without certifying the old command',
      () async {
        final fixture = await TestMailFlagJournal.create();
        addTearDown(fixture.dispose);
        final before = await _uncertain(fixture);
        final observer = _Observer(
          fixture.source(),
          respond: (identity, _) async => MailSuccess(
            kind == MailFlagResolutionKind.missing
                ? MailFlagObservation.missing(identity: identity)
                : MailFlagObservation.identityChanged(
                    identity: identity as MailImapIdentity,
                  ),
          ),
        );
        final checked = await _check(fixture, before, observer);
        expect(checked.resolutions.single.kind, kind);
        expect(checked.summary.unresolvedCount, 0);
        expect(checked.report.confirmedCount, 0);
        expect(checked.report.uncertainCount, 1);
        expect(fixture.dispatched, hasLength(1));
      },
    );
  }

  test(
    'wrong observer account or provider never requests remote flags',
    () async {
      final fixture = await TestMailFlagJournal.create();
      addTearDown(fixture.dispose);
      final before = await _uncertain(fixture);
      final observer = _Observer(fixture.source('current'));
      await expectLater(
        _check(
          fixture,
          before,
          observer,
          sourceAccount: fixture.source('other'),
        ),
        _problem(MailProblemCode.permissionDenied),
      );
      await expectLater(
        _check(fixture, before, observer, provider: MailProviderKind.graph),
        _problem(MailProblemCode.conflict),
      );
      expect(observer.identities, isEmpty);
      await _stillUnresolved(fixture, before);
    },
  );

  test('a stale selected revision does not request remote flags', () async {
    final fixture = await TestMailFlagJournal.create();
    addTearDown(fixture.dispose);
    final before = await _uncertain(fixture);
    final observer = _Observer(fixture.source());
    await expectLater(
      _check(fixture, before, observer, revision: before.summary.revision - 1),
      _problem(MailProblemCode.conflict),
    );
    expect(observer.identities, isEmpty);
    await _stillUnresolved(fixture, before);
  });

  test(
    'running and already settled receipts cannot start a remote check',
    () async {
      final fixture = await TestMailFlagJournal.create();
      addTearDown(fixture.dispose);
      await fixture.prepare('running', begin: true);
      await fixture.run('confirmed', count: 1);
      final observer = _Observer(fixture.source());
      for (final id in ['running', 'confirmed']) {
        final batch = (await fixture.store.load(id))!;
        await expectLater(
          _check(fixture, batch, observer),
          _problem(MailProblemCode.conflict),
        );
      }
      expect(observer.identities, isEmpty);
    },
  );

  test('retired and cancelled views cannot start a remote check', () async {
    final fixture = await TestMailFlagJournal.create();
    addTearDown(fixture.dispose);
    final before = await _uncertain(fixture);
    final observer = _Observer(fixture.source());
    await expectLater(
      _check(fixture, before, observer, isCurrent: () => false),
      _problem(MailProblemCode.staleOperation),
    );
    final cancellation = MailCancellationSource()..cancel();
    await expectLater(
      _check(fixture, before, observer, cancellation: cancellation.token),
      _problem(MailProblemCode.cancelled),
    );
    expect(observer.identities, isEmpty);
    await _stillUnresolved(fixture, before);
  });

  test(
    'another local account cannot load or observe the selected receipt',
    () async {
      final fixture = await TestMailFlagJournal.create();
      final other = await TestMailFlagJournal.create(accountName: 'another');
      addTearDown(fixture.dispose);
      addTearDown(other.dispose);
      final before = await _uncertain(fixture);
      final observer = _Observer(other.source());
      await expectLater(
        _check(other, before, observer),
        _problem(MailProblemCode.conflict),
      );
      expect(observer.identities, isEmpty);
      await _stillUnresolved(fixture, before);
    },
  );

  test(
    'provider failure keeps uncertainty and permits a later explicit check',
    () async {
      final fixture = await TestMailFlagJournal.create(
        provider: MailProviderKind.gmail,
      );
      addTearDown(fixture.dispose);
      final before = await _uncertain(fixture);
      final failed = _Observer(
        fixture.source(),
        respond: (_, _) async =>
            const MailFailure(MailProblem(MailProblemCode.unavailable)),
      );
      await expectLater(
        _check(fixture, before, failed),
        _problem(MailProblemCode.unavailable),
      );
      await _stillUnresolved(fixture, before);
      final succeeding = _Observer(fixture.source());
      final checked = await _check(fixture, before, succeeding);
      expect(checked.summary.unresolvedCount, 0);
      expect(failed.identities, hasLength(1));
      expect(succeeding.identities, hasLength(1));
      expect(fixture.dispatched, hasLength(1));
    },
  );

  for (final changed in ['account', 'uidValidity', 'uid']) {
    test(
      'a response for a different $changed cannot resolve the receipt',
      () async {
        final fixture = await TestMailFlagJournal.create();
        addTearDown(fixture.dispose);
        final before = await _uncertain(fixture);
        final observer = _Observer(
          fixture.source(),
          respond: (identity, _) async {
            final original = identity as MailImapIdentity;
            final returned = MailImapIdentity(
              mailbox: MailMailboxId(
                original.mailbox.value,
                account: changed == 'account'
                    ? fixture.source('foreign')
                    : original.account,
              ),
              uidValidity:
                  original.uidValidity + (changed == 'uidValidity' ? 1 : 0),
              uid: original.uid + (changed == 'uid' ? 1 : 0),
            );
            return MailSuccess(MailFlagObservation.missing(identity: returned));
          },
        );
        await expectLater(
          _check(fixture, before, observer),
          _problem(MailProblemCode.conflict),
        );
        await _stillUnresolved(fixture, before);
        expect(observer.identities, hasLength(1));
      },
    );
  }

  for (final retire in [false, true]) {
    test(
      '${retire ? 'account retirement' : 'cancellation'} during observation discards the late response',
      () async {
        final fixture = await TestMailFlagJournal.create();
        addTearDown(fixture.dispose);
        final before = await _uncertain(fixture);
        final cancellation = MailCancellationSource();
        final started = Completer<MailRemoteIdentity>();
        final response = Completer<MailResult<MailFlagObservation>>();
        final observer = _Observer(
          fixture.source(),
          respond: (identity, _) {
            started.complete(identity);
            return response.future;
          },
        );
        final result = _check(
          fixture,
          before,
          observer,
          cancellation: cancellation.token,
        );
        final identity = await started.future;
        if (retire) {
          fixture.current = false;
        } else {
          cancellation.cancel();
        }
        final assertion = expectLater(
          result,
          _problem(
            retire ? MailProblemCode.staleOperation : MailProblemCode.cancelled,
          ),
        );
        response.complete(
          MailSuccess(MailFlagObservation.missing(identity: identity)),
        );
        await assertion;
        fixture.current = true;
        await _stillUnresolved(fixture, before);
        expect(observer.leases.single.isCurrent, isFalse);
        expect(fixture.dispatched, hasLength(1));
      },
    );
  }

  test(
    'a failed observation commit retains the original receipt after reopen',
    () async {
      final fixture = await TestMailFlagJournal.create();
      addTearDown(fixture.dispose);
      final before = await _uncertain(fixture);
      final observer = _Observer(
        fixture.source(),
        respond: (identity, _) async {
          fixture.failWrites = true;
          return MailSuccess(MailFlagObservation.missing(identity: identity));
        },
      );
      await expectLater(
        _check(fixture, before, observer),
        _problem(MailProblemCode.storageFailure),
      );
      fixture.failWrites = false;
      await fixture.reopen();
      await _stillUnresolved(fixture, before);
      expect(observer.identities, hasLength(1));
      expect(fixture.dispatched, hasLength(1));
    },
  );

  test(
    'concurrent checks cannot overwrite the first committed observation',
    () async {
      final fixture = await TestMailFlagJournal.create();
      addTearDown(fixture.dispose);
      final before = await _uncertain(fixture);
      final started = Completer<MailRemoteIdentity>();
      final response = Completer<MailResult<MailFlagObservation>>();
      final late = _Observer(
        fixture.source(),
        respond: (identity, _) {
          started.complete(identity);
          return response.future;
        },
      );
      final pending = _check(fixture, before, late);
      final identity = await started.future;
      final first = await _check(fixture, before, _Observer(fixture.source()));
      final assertion = expectLater(
        pending,
        _problem(MailProblemCode.conflict),
      );
      response.complete(
        MailSuccess(MailFlagObservation.missing(identity: identity)),
      );
      await assertion;
      final stored = (await fixture.store.load(before.summary.id))!;
      expect(stored.summary.revision, first.summary.revision);
      expect(stored.resolutions.single.kind, MailFlagResolutionKind.matches);
      expect(stored.report.uncertainCount, 1);
    },
  );

  test(
    'the recovery binder is optional and combines host and dialog lifetime',
    () async {
      final fixture = await TestMailFlagJournal.create();
      addTearDown(fixture.dispose);
      final before = await _uncertain(fixture);
      expect(
        studioMailFlagRecovery(
          store: fixture.store,
          observer: Object(),
          provider: fixture.provider,
          isCurrent: () => true,
        ),
        isNull,
      );
      final observer = _Observer(fixture.source());
      var refreshes = 0;
      final recovery = studioMailFlagRecovery(
        store: fixture.store,
        observer: observer,
        provider: fixture.provider,
        isCurrent: () => fixture.current,
        onChecked: () => refreshes++,
      )!;
      final cancellation = MailCancellationSource();
      await expectLater(
        recovery(before, cancellation.token, () => false),
        _problem(MailProblemCode.staleOperation),
      );
      expect(observer.identities, isEmpty);
      fixture.current = false;
      await expectLater(
        recovery(before, cancellation.token, () => true),
        _problem(MailProblemCode.staleOperation),
      );
      expect(refreshes, 1);
      fixture.current = true;
      final checked = await recovery(before, cancellation.token, () => true);
      expect(checked.summary.unresolvedCount, 0);
      expect(refreshes, 2);
      expect(observer.identities, hasLength(1));
    },
  );
}
