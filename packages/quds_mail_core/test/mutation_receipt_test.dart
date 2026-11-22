import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:test/test.dart';

final _account = MailAccountId(
  'account',
  profile: MailProfileId('profile', hostId: 'move-receipts'),
);
final _source = MailMailboxId('Inbox', account: _account);
final _destination = MailMailboxId('Archive', account: _account);
final _remote = MailImapIdentity(mailbox: _source, uidValidity: 3, uid: 17);
final _moved = MailImapIdentity(mailbox: _destination, uidValidity: 5, uid: 29);

MailMoveIdentityTransition _transition({String operationId = 'move:0'}) =>
    MailMoveIdentityTransition(
      operationId: operationId,
      source: _remote,
      sourceMailbox: _source,
      destination: _moved,
      destinationMailbox: _destination,
      destinationMessageId: MailMessageId('destination-key'),
    );

MailBulkFlagPlan _plan({MailBulkFlagAction action = MailBulkFlagAction.move}) =>
    MailBulkFlagPlan(
      id: 'move',
      mailbox: _source,
      action: action,
      destination: action == MailBulkFlagAction.move ? _destination : null,
      messages: [_remote],
    );

void main() {
  test(
    'cursor repository revisions are optional and bounded without changing value',
    () {
      expect(
        MailCursor(mailbox: _source, value: 'opaque').repositoryRevision,
        isNull,
      );
      for (final revision in [0, 1, 0x1fffffffffffff]) {
        final cursor = MailCursor(
          mailbox: _source,
          value: 'opaque',
          repositoryRevision: revision,
        );
        expect(cursor.repositoryRevision, revision);
        expect(cursor.value, 'opaque');
      }
      for (final revision in [-1, 0x20000000000000]) {
        expect(
          () => MailCursor(
            mailbox: _source,
            value: 'opaque',
            repositoryRevision: revision,
          ),
          throwsA(isA<AssertionError>()),
        );
      }
    },
  );
  test(
    'exact transition is immutable, comparable and scoped to its command',
    () {
      final transition = _transition();
      expect(transition, _transition());
      expect(transition.hashCode, _transition().hashCode);
      expect(
        transition.matches(_plan().operationAt(0), sourceMailbox: _source),
        isTrue,
      );
      expect(
        transition.matches(_plan().operationAt(0), sourceMailbox: _destination),
        isFalse,
      );
      expect(
        transition.matches(
          MailMove(id: 'other', message: _remote, destination: _destination),
        ),
        isFalse,
      );
      expect(
        transition.matches(MailDelete(id: 'move:0', message: _remote)),
        isFalse,
      );
    },
  );

  test(
    'transition refuses cross-account, provider, folder and IMAP mismatch',
    () {
      final foreign = MailAccountId('other', profile: _account.profile);
      final foreignMailbox = MailMailboxId('Archive', account: foreign);
      final cases =
          <
            ({
              MailRemoteIdentity source,
              MailMailboxId sourceMailbox,
              MailRemoteIdentity destination,
              MailMailboxId destinationMailbox,
            })
          >[
            (
              source: _remote,
              sourceMailbox: _source,
              destination: MailImapIdentity(
                mailbox: foreignMailbox,
                uidValidity: 5,
                uid: 29,
              ),
              destinationMailbox: foreignMailbox,
            ),
            (
              source: _remote,
              sourceMailbox: _destination,
              destination: _moved,
              destinationMailbox: _source,
            ),
            (
              source: _remote,
              sourceMailbox: _source,
              destination: _remote,
              destinationMailbox: _source,
            ),
            (
              source: _remote,
              sourceMailbox: _source,
              destination: MailOpaqueIdentity(
                account: _account,
                provider: MailProviderKind.ews,
                value: 'new',
              ),
              destinationMailbox: _destination,
            ),
          ];
      for (final value in cases) {
        expect(
          () => MailMoveIdentityTransition(
            operationId: 'move:0',
            source: value.source,
            sourceMailbox: value.sourceMailbox,
            destination: value.destination,
            destinationMailbox: value.destinationMailbox,
            destinationMessageId: MailMessageId('key'),
          ),
          throwsArgumentError,
        );
      }
    },
  );

  for (final provider in [MailProviderKind.graph, MailProviderKind.ews]) {
    test(
      '${provider.name} identities may stay stable across different folders',
      () {
        final identity = MailOpaqueIdentity(
          account: _account,
          provider: provider,
          value: 'Opaque=Case',
        );
        final transition = MailMoveIdentityTransition(
          operationId: 'move:0',
          source: identity,
          sourceMailbox: _source,
          destination: identity,
          destinationMailbox: _destination,
          destinationMessageId: MailMessageId('canonical-key'),
        );
        expect(transition.source, transition.destination);
      },
    );
  }

  for (final provider in [MailProviderKind.gmail, MailProviderKind.jmap]) {
    test('${provider.name} does not acquire folder move evidence', () {
      expect(
        () => MailMoveIdentityTransition(
          operationId: 'move:0',
          source: MailOpaqueIdentity(
            account: _account,
            provider: provider,
            value: 'one',
          ),
          sourceMailbox: _source,
          destination: MailOpaqueIdentity(
            account: _account,
            provider: provider,
            value: 'two',
          ),
          destinationMailbox: _destination,
          destinationMessageId: MailMessageId('key'),
        ),
        throwsArgumentError,
      );
    });
  }

  test(
    'durable exact identifiers reject controls, malformed Unicode and excess',
    () {
      for (final id in ['', 'x\n', '\ud800', '\udc00', 'x' * 2049]) {
        expect(() => _transition(operationId: id), throwsArgumentError);
      }
      expect(_transition(operationId: 'move:😀').operationId, 'move:😀');
    },
  );

  test('receipt helper preserves success evidence and failure uncertainty', () {
    final transition = _transition();
    expect(
      MailBulkFlagAttempt.fromReceiptResult(
        MailSuccess(MailMutationReceipt(identityTransition: transition)),
      ).identityTransition,
      same(transition),
    );
    for (final definite in [true, false]) {
      final attempt = MailBulkFlagAttempt.fromReceiptResult(
        MailFailure(
          MailProblem(
            MailProblemCode.conflict,
            mutationMayHaveOccurred: !definite,
          ),
        ),
      );
      expect(
        attempt.outcome,
        definite ? MailBulkFlagOutcome.failed : MailBulkFlagOutcome.uncertain,
      );
      expect(attempt.identityTransition, isNull);
    }
  });

  test(
    'confirmed exact move evidence survives coordinator and report restore',
    () async {
      final transition = _transition();
      final report = await MailBulkFlagCoordinator().run(
        plan: _plan(),
        lease: MailAccountSession(_account).begin(),
        isScopeCurrent: () => true,
        apply: (_, _) async =>
            MailBulkFlagAttempt.confirmed(identityTransition: transition),
      );
      expect(report.confirmedCount, 1);
      expect(report.items.single.identityTransition, same(transition));
      final restored = MailBulkFlagReport.restore(
        plan: report.plan,
        results: report.items,
      );
      expect(restored.items.single.identityTransition, transition);
    },
  );

  for (final wrongAction in [true, false]) {
    test(
      'invalid ${wrongAction ? 'action' : 'operation'} evidence becomes uncertain without projection',
      () async {
        final report = await MailBulkFlagCoordinator().run(
          plan: _plan(
            action: wrongAction
                ? MailBulkFlagAction.delete
                : MailBulkFlagAction.move,
          ),
          lease: MailAccountSession(_account).begin(),
          isScopeCurrent: () => true,
          apply: (_, _) async => MailBulkFlagAttempt.confirmed(
            identityTransition: _transition(
              operationId: wrongAction ? 'move:0' : 'other',
            ),
          ),
        );
        expect(report.uncertainCount, 1);
        expect(report.items.single.identityTransition, isNull);
        expect(report.items.single.problem?.mutationMayHaveOccurred, isTrue);
        expect(report.stopReason, MailBulkFlagStopReason.uncertain);
      },
    );
  }

  test('restored nonconfirmed or mismatched evidence is refused', () {
    for (final outcome in MailBulkFlagOutcome.values.where(
      (value) => value != MailBulkFlagOutcome.confirmed,
    )) {
      expect(
        () => MailBulkFlagItemResult.restore(
          operation: _plan().operationAt(0),
          outcome: outcome,
          problem: outcome == MailBulkFlagOutcome.failed
              ? const MailProblem(
                  MailProblemCode.conflict,
                  mutationMayHaveOccurred: false,
                )
              : null,
          identityTransition: _transition(),
        ),
        throwsArgumentError,
      );
    }
    expect(
      () => MailBulkFlagItemResult.restore(
        operation: _plan().operationAt(0),
        outcome: MailBulkFlagOutcome.confirmed,
        identityTransition: _transition(operationId: 'other'),
      ),
      throwsArgumentError,
    );
  });

  test(
    'opaque transition cannot substitute a different frozen source folder',
    () async {
      final remote = MailOpaqueIdentity(
        account: _account,
        provider: MailProviderKind.ews,
        value: 'one',
      );
      final transition = MailMoveIdentityTransition(
        operationId: 'move:0',
        source: remote,
        sourceMailbox: MailMailboxId('Other', account: _account),
        destination: MailOpaqueIdentity(
          account: _account,
          provider: MailProviderKind.ews,
          value: 'two',
        ),
        destinationMailbox: _destination,
        destinationMessageId: MailMessageId('key'),
      );
      final plan = MailBulkFlagPlan(
        id: 'move',
        mailbox: _source,
        action: MailBulkFlagAction.move,
        destination: _destination,
        messages: [remote],
      );
      expect(
        () => MailBulkFlagReport.restore(
          plan: plan,
          results: [
            MailBulkFlagItemResult(
              operation: plan.operationAt(0),
              outcome: MailBulkFlagOutcome.confirmed,
              identityTransition: transition,
            ),
          ],
        ),
        throwsArgumentError,
      );
      final report = await MailBulkFlagCoordinator().run(
        plan: plan,
        lease: MailAccountSession(_account).begin(),
        isScopeCurrent: () => true,
        apply: (_, _) async =>
            MailBulkFlagAttempt.confirmed(identityTransition: transition),
      );
      expect(report.uncertainCount, 1);
      expect(report.items.single.identityTransition, isNull);
    },
  );
}
