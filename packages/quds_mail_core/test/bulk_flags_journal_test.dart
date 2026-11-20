import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:test/test.dart';

final _account = MailAccountId(
  'account',
  profile: MailProfileId('journal', hostId: 'test'),
);
final _mailbox = MailMailboxId('inbox', account: _account);

MailBulkFlagPlan _plan() => MailBulkFlagPlan(
  id: 'batch',
  mailbox: _mailbox,
  action: MailBulkFlagAction.markRead,
  messages: [
    for (var uid = 1; uid <= 3; uid++)
      MailImapIdentity(mailbox: _mailbox, uidValidity: 7, uid: uid),
  ],
);

final class _Journal implements MailBulkFlagJournal {
  _Journal(this.events, {this.failAt, this.onWrite, this.throwAt});
  final List<String> events;
  final String? failAt;
  final String? throwAt;
  final void Function(String)? onWrite;
  final List<MailBulkFlagItemResult> recorded = [];
  MailBulkFlagReport? finished;

  Future<MailResult<MailUnit>> _write(String event) async {
    events.add(event);
    await Future<void>.value();
    onWrite?.call(event);
    if (event == throwAt) throw StateError('private database text');
    return event == failAt
        ? const MailFailure(MailProblem(MailProblemCode.storageFailure))
        : const MailSuccess(MailUnit.value);
  }

  @override
  Future<MailResult<MailUnit>> prepare(MailBulkFlagPlan plan) =>
      _write('prepare');
  @override
  Future<MailResult<MailUnit>> beginAttempt(int index) =>
      _write('begin:$index');
  @override
  Future<MailResult<MailUnit>> recordResult(
    int index,
    MailBulkFlagItemResult result,
  ) async {
    final saved = await _write('record:$index');
    if (saved is MailSuccess<MailUnit>) recorded.add(result);
    return saved;
  }

  @override
  Future<MailResult<MailUnit>> finish(MailBulkFlagReport report) async {
    final saved = await _write('finish');
    if (saved is MailSuccess<MailUnit>) finished = report;
    return saved;
  }
}

void main() {
  late List<String> events;
  late MailAccountSession session;
  late bool current;
  late MailCancellationSource cancellation;

  Future<MailBulkFlagReport> run(
    _Journal journal, {
    Future<MailBulkFlagAttempt> Function(MailOperation)? apply,
  }) => MailBulkFlagCoordinator().run(
    plan: _plan(),
    lease: session.begin(),
    journal: journal,
    isScopeCurrent: () => current,
    cancellation: cancellation.token,
    apply: (operation, lease) async {
      events.add('apply:${operation.id}');
      return apply == null
          ? const MailBulkFlagAttempt.confirmed()
          : apply(operation);
    },
  );

  setUp(() {
    events = [];
    session = MailAccountSession(_account);
    current = true;
    cancellation = MailCancellationSource();
  });

  test(
    'intent and every applying marker commit before the matching provider call',
    () async {
      final journal = _Journal(events);
      final report = await run(journal);
      expect(events, [
        'prepare',
        'begin:0',
        'apply:batch:0',
        'record:0',
        'begin:1',
        'apply:batch:1',
        'record:1',
        'begin:2',
        'apply:batch:2',
        'record:2',
        'finish',
      ]);
      expect(report.confirmedCount, 3);
      expect(journal.finished!.confirmedCount, 3);
      expect(report.persistenceProblem, isNull);
    },
  );

  for (final step in ['prepare', 'begin:0']) {
    test('$step failure prevents every provider dispatch', () async {
      final journal = _Journal(events, failAt: step);
      final report = await run(journal);
      expect(events.where((event) => event.startsWith('apply:')), isEmpty);
      expect(report.unattemptedCount, 3);
      expect(report.stopReason, MailBulkFlagStopReason.persistenceFailure);
      expect(report.persistenceProblem!.code, MailProblemCode.storageFailure);
      expect(report.requiresRefresh, isTrue);
      expect(events.contains('finish'), step != 'prepare');
    });
  }

  for (final step in ['prepare', 'begin:0']) {
    test(
      'cancellation during $step prevents dispatch and retains an unattempted receipt',
      () async {
        final journal = _Journal(
          events,
          onWrite: (event) {
            if (event == step) cancellation.cancel();
          },
        );
        final report = await run(journal);
        expect(events.where((event) => event.startsWith('apply:')), isEmpty);
        expect(report.stopReason, MailBulkFlagStopReason.cancelled);
        expect(journal.finished!.unattemptedCount, 3);
        expect(journal.finished!.uncertainCount, 0);
      },
    );
  }

  for (final step in ['prepare', 'begin:0']) {
    test('scope retirement during $step prevents dispatch', () async {
      final report = await run(
        _Journal(
          events,
          onWrite: (event) {
            if (event == step) current = false;
          },
        ),
      );
      expect(events.where((event) => event.startsWith('apply:')), isEmpty);
      expect(report.stopReason, MailBulkFlagStopReason.staleScope);
    });
  }

  test(
    'receipt write failure retains confirmed knowledge and stops later dispatch',
    () async {
      final journal = _Journal(events, failAt: 'record:0');
      final report = await run(journal);
      expect(events.where((event) => event.startsWith('apply:')), [
        'apply:batch:0',
      ]);
      expect(report.confirmedCount, 1);
      expect(report.uncertainCount, 0);
      expect(report.unattemptedCount, 2);
      expect(report.stopReason, MailBulkFlagStopReason.persistenceFailure);
      expect(journal.finished!.confirmedCount, 1);
    },
  );

  test(
    'a thrown persistence exception is sanitized and cannot authorize dispatch',
    () async {
      final report = await run(_Journal(events, throwAt: 'begin:0'));
      expect(report.persistenceProblem!.code, MailProblemCode.storageFailure);
      expect(report.unattemptedCount, 3);
      expect(events.where((event) => event.startsWith('apply:')), isEmpty);
    },
  );

  test('finish failure never discards settled acknowledgements', () async {
    final report = await run(_Journal(events, failAt: 'finish'));
    expect(report.confirmedCount, 3);
    expect(report.stopReason, MailBulkFlagStopReason.persistenceFailure);
    expect(report.persistenceProblem, isNotNull);
  });

  test(
    'a late acknowledgement is persisted even after its view and lease retire',
    () async {
      final journal = _Journal(events);
      final report = await run(
        journal,
        apply: (_) async {
          current = false;
          session.invalidate();
          return const MailBulkFlagAttempt.confirmed();
        },
      );
      expect(report.confirmedCount, 1);
      expect(report.unattemptedCount, 2);
      expect(journal.recorded.single.outcome, MailBulkFlagOutcome.confirmed);
      expect(journal.finished!.confirmedCount, 1);
    },
  );

  test(
    'uncertainty retains precedence and still exposes failed persistence',
    () async {
      final journal = _Journal(events, failAt: 'record:0');
      final report = await run(
        journal,
        apply: (_) async => const MailBulkFlagAttempt.uncertain(
          MailProblem(
            MailProblemCode.providerFailure,
            mutationMayHaveOccurred: true,
          ),
        ),
      );
      expect(report.stopReason, MailBulkFlagStopReason.uncertain);
      expect(report.uncertainCount, 1);
      expect(report.persistenceProblem, isNotNull);
      expect(journal.finished!.unattemptedCount, 2);
    },
  );

  test(
    'a contradictory failed certificate is normalized before persistence',
    () async {
      final journal = _Journal(events);
      final report = await run(
        journal,
        apply: (_) async => const MailBulkFlagAttempt.failed(
          MailProblem(
            MailProblemCode.permissionDenied,
            mutationMayHaveOccurred: true,
          ),
        ),
      );
      expect(report.uncertainCount, 1);
      expect(journal.recorded.single.outcome, MailBulkFlagOutcome.uncertain);
    },
  );

  test('provider-result runner uses the same durable lifecycle', () async {
    final journal = _Journal(events);
    final report = await const MailBulkFlagRunner().run(
      plan: _plan(),
      lease: session.begin(),
      journal: journal,
      isScopeCurrent: () => true,
      apply: (operation, lease) async {
        events.add('apply:${operation.id}');
        return const MailSuccess(MailUnit.value);
      },
    );
    expect(report.confirmedCount, 3);
    expect(events.first, 'prepare');
    expect(events.last, 'finish');
  });

  test(
    'restoring receipt cannot change identity, order, desired state or count',
    () {
      final plan = _plan();
      List<MailBulkFlagItemResult> results() => [
        for (var i = 0; i < 3; i++)
          MailBulkFlagItemResult(
            operation: plan.operationAt(i),
            outcome: MailBulkFlagOutcome.confirmed,
          ),
      ];
      final valid = MailBulkFlagReport.restore(plan: plan, results: results());
      expect(() => valid.results.clear(), throwsUnsupportedError);
      expect(
        () => MailBulkFlagReport.restore(
          plan: plan,
          results: results().reversed.toList(),
        ),
        throwsArgumentError,
      );
      expect(
        () => MailBulkFlagReport.restore(
          plan: plan,
          results: results().take(2).toList(),
        ),
        throwsArgumentError,
      );
      final changed = results();
      changed[0] = MailBulkFlagItemResult(
        operation: MailSetRead(
          id: 'batch:0',
          message: plan.messages[0],
          read: false,
        ),
        outcome: MailBulkFlagOutcome.confirmed,
      );
      expect(
        () => MailBulkFlagReport.restore(plan: plan, results: changed),
        throwsArgumentError,
      );
    },
  );

  test(
    'restoration rejects contradictory failure evidence and keeps storage refresh requirement',
    () {
      final plan = _plan();
      final contradictory = [
        for (var i = 0; i < 3; i++)
          MailBulkFlagItemResult(
            operation: plan.operationAt(i),
            outcome: MailBulkFlagOutcome.failed,
            problem: const MailProblem(
              MailProblemCode.permissionDenied,
              mutationMayHaveOccurred: true,
            ),
          ),
      ];
      expect(
        () => MailBulkFlagReport.restore(plan: plan, results: contradictory),
        throwsArgumentError,
      );
      final restored = MailBulkFlagReport.restore(
        plan: plan,
        results: [
          for (var i = 0; i < 3; i++)
            MailBulkFlagItemResult(
              operation: plan.operationAt(i),
              outcome: MailBulkFlagOutcome.unattempted,
            ),
        ],
        stopReason: MailBulkFlagStopReason.persistenceFailure,
      );
      expect(restored.requiresRefresh, isTrue);
    },
  );
}
