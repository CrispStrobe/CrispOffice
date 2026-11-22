import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:test/test.dart';

final _account = MailAccountId(
  'account',
  profile: MailProfileId('profile', hostId: 'archive-tests'),
);
final _inbox = MailMailboxId('INBOX', account: _account);

MailOpaqueIdentity _message(
  String id, {
  MailProviderKind provider = MailProviderKind.gmail,
  MailAccountId? account,
}) => MailOpaqueIdentity(
  account: account ?? _account,
  provider: provider,
  value: id,
);

MailBulkFlagPlan _plan({
  MailMailboxId? mailbox,
  MailMailboxId? destination,
  List<MailRemoteIdentity>? messages,
}) => MailBulkFlagPlan(
  id: 'archive',
  mailbox: mailbox ?? _inbox,
  action: MailBulkFlagAction.archive,
  destination: destination,
  messages: messages ?? [_message('one'), _message('two')],
);

void main() {
  test('Archive freezes Gmail identities without an invented folder', () {
    final messages = <MailRemoteIdentity>[_message('one'), _message('two')];
    final plan = _plan(messages: messages);
    messages.clear();
    expect(plan.provider, MailProviderKind.gmail);
    expect(plan.destination, isNull);
    expect(plan.action.isFlagAction, isFalse);
    expect(plan.operationAt(1), isA<MailArchive>());
    expect(plan.operationAt(1).id, 'archive:1');
    expect(plan.operationAt(1).message, _message('two'));
    expect(() => plan.messages.clear(), throwsUnsupportedError);
  });

  for (final folder in [
    'inbox',
    'All Mail',
    'ALL',
    'TRASH',
    'SPAM',
    'Label_1',
  ]) {
    test('Archive rejects the non-Inbox source $folder', () {
      expect(
        () => _plan(mailbox: MailMailboxId(folder, account: _account)),
        throwsArgumentError,
      );
    });
  }

  test('Archive rejects folder destinations and cross-account identities', () {
    expect(
      () => _plan(destination: MailMailboxId('Archive', account: _account)),
      throwsArgumentError,
    );
    final other = MailAccountId('other', profile: _account.profile);
    expect(
      () => _plan(messages: [_message('other', account: other)]),
      throwsArgumentError,
    );
  });

  for (final provider in [
    MailProviderKind.graph,
    MailProviderKind.ews,
    MailProviderKind.jmap,
  ]) {
    test('Archive does not reinterpret ${provider.name} as Gmail', () {
      expect(
        () => _plan(messages: [_message('one', provider: provider)]),
        throwsArgumentError,
      );
    });
  }

  test('IMAP Archive must use an exact Move plan', () {
    expect(
      () => _plan(
        messages: [MailImapIdentity(mailbox: _inbox, uidValidity: 7, uid: 1)],
      ),
      throwsArgumentError,
    );
  });

  test(
    'confirmed Archive requires refresh and keeps ordered receipts',
    () async {
      final commands = <MailOperation>[];
      final report = await const MailBulkFlagRunner().run(
        plan: _plan(),
        lease: MailAccountSession(_account).begin(),
        apply: (command, lease) async {
          commands.add(command);
          return const MailSuccess(MailUnit.value);
        },
        isScopeCurrent: () => true,
      );
      expect(commands, everyElement(isA<MailArchive>()));
      expect(commands.map((command) => command.id), ['archive:0', 'archive:1']);
      expect(report.confirmedCount, 2);
      expect(report.requiresRefresh, isTrue);
      expect(report.uncertainCount, 0);
    },
  );

  test('uncertain Archive stops later messages without replay', () async {
    var calls = 0;
    final report = await const MailBulkFlagRunner().run(
      plan: _plan(),
      lease: MailAccountSession(_account).begin(),
      apply: (command, lease) async {
        calls++;
        return const MailFailure<MailUnit>(
          MailProblem(
            MailProblemCode.unavailable,
            mutationMayHaveOccurred: true,
          ),
        );
      },
      isScopeCurrent: () => true,
    );
    expect(calls, 1);
    expect(report.uncertainCount, 1);
    expect(report.unattemptedCount, 1);
    expect(report.stopReason, MailBulkFlagStopReason.uncertain);
    expect(report.requiresRefresh, isTrue);
  });

  for (final outcome in MailBulkFlagOutcome.values) {
    test('restores ${outcome.name} Archive receipts without dispatch', () {
      final plan = _plan(messages: [_message('one')]);
      final problem = outcome == MailBulkFlagOutcome.failed
          ? const MailProblem(
              MailProblemCode.permissionDenied,
              mutationMayHaveOccurred: false,
            )
          : outcome == MailBulkFlagOutcome.uncertain
          ? const MailProblem(
              MailProblemCode.unavailable,
              mutationMayHaveOccurred: true,
            )
          : null;
      final restored = MailBulkFlagReport.restore(
        plan: plan,
        results: [
          MailBulkFlagItemResult.restore(
            operation: plan.operationAt(0),
            outcome: outcome,
            problem: problem,
          ),
        ],
      );
      expect(restored.results.single.operation, isA<MailArchive>());
      expect(restored.results.single.outcome, outcome);
    });
  }

  test('restored Archive cannot silently become Delete or a flag command', () {
    final plan = _plan(messages: [_message('one')]);
    for (final operation in <MailOperation>[
      MailDelete(id: 'archive:0', message: _message('one')),
      MailSetRead(id: 'archive:0', message: _message('one'), read: true),
      MailArchive(id: 'other:0', message: _message('one')),
      MailArchive(id: 'archive:0', message: _message('other')),
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
  });
}
