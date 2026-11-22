import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:test/test.dart';

final _profile = MailProfileId('profile', hostId: 'membership-tests');
final _account = MailAccountId('account', profile: _profile);
final _source = MailMailboxId('inbox', account: _account);
final _destination = MailMailboxId('archive', account: _account);
final _message = MailImapIdentity(mailbox: _source, uidValidity: 7, uid: 19);

MailBulkFlagPlan _plan(
  MailBulkFlagAction action, {
  MailMailboxId? destination,
}) => MailBulkFlagPlan(
  id: 'membership',
  mailbox: _source,
  action: action,
  destination: destination,
  messages: [_message],
);

final class _Journal implements MailBulkFlagJournal {
  _Journal(this.events, {this.failure});
  final List<String> events;
  final String? failure;
  MailBulkFlagPlan? intent;
  MailBulkFlagReport? receipt;

  Future<MailResult<MailUnit>> _write(String event) async {
    events.add(event);
    return event == failure
        ? const MailFailure(MailProblem(MailProblemCode.storageFailure))
        : const MailSuccess(MailUnit.value);
  }

  @override
  Future<MailResult<MailUnit>> prepare(MailBulkFlagPlan plan) {
    intent = plan;
    return _write('prepare');
  }

  @override
  Future<MailResult<MailUnit>> beginAttempt(int index) => _write('begin');

  @override
  Future<MailResult<MailUnit>> recordResult(
    int index,
    MailBulkFlagItemResult result,
  ) => _write('record');

  @override
  Future<MailResult<MailUnit>> finish(MailBulkFlagReport report) {
    receipt = report;
    return _write('finish');
  }
}

void main() {
  test(
    'move destination is required, account-owned and different from source',
    () {
      final foreign = MailAccountId(
        'account',
        profile: MailProfileId('profile', hostId: 'another-host'),
      );
      for (final destination in <MailMailboxId?>[
        null,
        _source,
        MailMailboxId('archive', account: foreign),
        MailMailboxId(
          'archive',
          account: MailAccountId('another', profile: _profile),
        ),
      ]) {
        expect(
          () => _plan(MailBulkFlagAction.move, destination: destination),
          throwsArgumentError,
        );
      }
      for (final action in MailBulkFlagAction.values.where(
        (action) => action != MailBulkFlagAction.move,
      )) {
        expect(
          () => _plan(action, destination: _destination),
          throwsArgumentError,
        );
      }
    },
  );

  test(
    'restored move evidence cannot substitute destination or operation kind',
    () {
      final plan = _plan(MailBulkFlagAction.move, destination: _destination);
      for (final operation in <MailOperation>[
        MailMove(
          id: 'membership:0',
          message: _message,
          destination: MailMailboxId('another', account: _account),
        ),
        MailDelete(id: 'membership:0', message: _message),
        MailSetRead(id: 'membership:0', message: _message, read: true),
      ]) {
        expect(
          () => MailBulkFlagReport.restore(
            plan: plan,
            results: [
              MailBulkFlagItemResult(
                operation: operation,
                outcome: MailBulkFlagOutcome.confirmed,
              ),
            ],
          ),
          throwsArgumentError,
        );
      }
    },
  );

  for (final action in [MailBulkFlagAction.move, MailBulkFlagAction.delete]) {
    for (final failure in <String?>[
      null,
      'prepare',
      'begin',
      'record',
      'finish',
    ]) {
      test(
        '${action.name} journal failure=$failure preserves dispatch ordering',
        () async {
          final events = <String>[];
          final journal = _Journal(events, failure: failure);
          final plan = _plan(
            action,
            destination: action == MailBulkFlagAction.move
                ? _destination
                : null,
          );
          final report = await MailBulkFlagCoordinator().run(
            plan: plan,
            journal: journal,
            lease: MailAccountSession(_account).begin(),
            isScopeCurrent: () => true,
            apply: (operation, lease) async {
              events.add('apply');
              expect(journal.intent, same(plan));
              expect(operation.message, _message);
              if (operation is MailMove) {
                expect(operation.destination, _destination);
              }
              return const MailBulkFlagAttempt.confirmed();
            },
          );
          final dispatched = failure != 'prepare' && failure != 'begin';
          expect(
            events.where((event) => event == 'apply').length,
            dispatched ? 1 : 0,
          );
          expect(report.confirmedCount, dispatched ? 1 : 0);
          expect(report.unattemptedCount, dispatched ? 0 : 1);
          expect(report.requiresRefresh, isTrue);
          expect(report.plan.destination, plan.destination);
          expect(action.isFlagAction, isFalse);
          if (dispatched) {
            expect(events.take(3), ['prepare', 'begin', 'apply']);
          }
          if (failure != null) {
            expect(
              report.persistenceProblem?.code,
              MailProblemCode.storageFailure,
            );
          }
        },
      );
    }

    test(
      '${action.name} known rejection does not imply a membership change',
      () {
        final plan = _plan(
          action,
          destination: action == MailBulkFlagAction.move ? _destination : null,
        );
        final report = MailBulkFlagReport.restore(
          plan: plan,
          results: [
            MailBulkFlagItemResult.restore(
              operation: plan.operationAt(0),
              outcome: MailBulkFlagOutcome.failed,
              problem: const MailProblem(
                MailProblemCode.unsupported,
                mutationMayHaveOccurred: false,
              ),
            ),
          ],
        );
        expect(report.requiresRefresh, isFalse);
      },
    );
  }
}
