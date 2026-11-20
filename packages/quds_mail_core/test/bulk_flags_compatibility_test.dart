import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:test/test.dart';

final _profile = MailProfileId('profile', hostId: 'bulk-compatibility');
final _account = MailAccountId('account', profile: _profile);
final _mailbox = MailMailboxId('inbox', account: _account);

MailBulkFlagPlan _plan({MailProviderKind? provider}) => MailBulkFlagPlan(
  id: 'compatibility',
  mailbox: _mailbox,
  provider: provider,
  action: MailBulkFlagAction.markUnread,
  messages: [
    for (var index = 0; index < 3; index++)
      MailOpaqueIdentity(
        account: _account,
        provider: MailProviderKind.graph,
        value: '$index',
      ),
  ],
);

void main() {
  test('explicit provider checks rather than changes the frozen namespace', () {
    expect(_plan().provider, MailProviderKind.graph);
    expect(
      _plan(provider: MailProviderKind.graph).provider,
      MailProviderKind.graph,
    );
    expect(() => _plan(provider: MailProviderKind.gmail), throwsArgumentError);
    expect(() => _plan(provider: MailProviderKind.imap), throwsArgumentError);
  });

  for (final adapter in [false, true]) {
    group(adapter ? 'certified coordinator' : 'provider runner', () {
      Future<MailBulkFlagReport> run({
        required Future<MailBulkFlagAttempt> Function(MailOperation) apply,
        MailOperationLease? lease,
        bool Function()? isScopeCurrent,
        bool Function()? shouldStop,
        void Function(MailBulkFlagReport)? onProgress,
      }) {
        final actualLease = lease ?? MailAccountSession(_account).begin();
        if (adapter) {
          return MailBulkFlagCoordinator().run(
            plan: _plan(),
            lease: actualLease,
            isScopeCurrent: isScopeCurrent ?? () => true,
            shouldStop: shouldStop,
            onProgress: onProgress,
            apply: (operation, lease) => apply(operation),
          );
        }
        return const MailBulkFlagRunner().run(
          plan: _plan(),
          lease: actualLease,
          isScopeCurrent: isScopeCurrent ?? () => true,
          shouldStop: shouldStop,
          onProgress: onProgress,
          apply: (operation, lease) async {
            final attempt = await apply(operation);
            if (attempt.outcome == MailBulkFlagOutcome.confirmed) {
              return const MailSuccess(MailUnit.value);
            }
            return MailFailure(attempt.problem!);
          },
        );
      }

      test(
        'receipt retains exact dispatched operations and problem evidence',
        () async {
          final commands = <MailOperation>[];
          final progress = <MailBulkFlagReport>[];
          const denied = MailProblem(
            MailProblemCode.permissionDenied,
            mutationMayHaveOccurred: false,
          );
          final report = await run(
            apply: (operation) async {
              commands.add(operation);
              return commands.length == 2
                  ? const MailBulkFlagAttempt.failed(denied)
                  : const MailBulkFlagAttempt.confirmed();
            },
            onProgress: progress.add,
          );
          expect(commands.map((operation) => operation.id), [
            'compatibility:0',
            'compatibility:1',
            'compatibility:2',
          ]);
          expect(report.items, same(report.results));
          expect(() => report.items.clear(), throwsUnsupportedError);
          expect(report.confirmedCount, 2);
          expect(report.failedCount, 1);
          expect(report.items[1].problem, same(denied));
          expect(report.stopProblem, isNull);
          expect(report.stopReason, isNull);
          for (var index = 0; index < commands.length; index++) {
            expect(report.items[index].operation, same(commands[index]));
            expect(
              progress.first.items[index].operation,
              same(commands[index]),
            );
          }
          expect(progress.first.unattemptedCount, 3);
        },
      );

      test('uncertainty dominates simultaneous stop and stale scope', () async {
        const lostReply = MailProblem(
          MailProblemCode.unavailable,
          mutationMayHaveOccurred: true,
        );
        var current = true;
        var stopping = false;
        var calls = 0;
        final report = await run(
          apply: (operation) async {
            calls++;
            current = false;
            stopping = true;
            return const MailBulkFlagAttempt.uncertain(lostReply);
          },
          isScopeCurrent: () => current,
          shouldStop: () => stopping,
        );
        expect(calls, 1);
        expect(report.stopReason, MailBulkFlagStopReason.uncertain);
        expect(report.stopProblem, same(lostReply));
        expect(report.requiresRefresh, isTrue);
        expect(report.uncertainCount, 1);
        expect(report.unattemptedCount, 2);
      });

      test(
        'stop from progress retains confirmation even if display throws',
        () async {
          var stopping = false;
          var calls = 0;
          final lease = MailAccountSession(_account).begin();
          final report = await run(
            lease: lease,
            apply: (operation) async {
              calls++;
              return const MailBulkFlagAttempt.confirmed();
            },
            shouldStop: () => stopping,
            onProgress: (progress) {
              if (progress.confirmedCount == 1) {
                stopping = true;
                throw StateError('View was retired.');
              }
            },
          );
          expect(calls, 1);
          expect(lease.isCurrent, isTrue);
          expect(report.confirmedCount, 1);
          expect(report.unattemptedCount, 2);
          expect(report.stopReason, MailBulkFlagStopReason.cancelled);
          expect(report.requiresRefresh, isFalse);
        },
      );

      for (final code in [
        MailProblemCode.cancelled,
        MailProblemCode.staleOperation,
        MailProblemCode.quotaExceeded,
      ]) {
        test('certified $code failure still stops further dispatch', () async {
          var calls = 0;
          final problem = MailProblem(code, mutationMayHaveOccurred: false);
          final report = await run(
            apply: (operation) async {
              calls++;
              return MailBulkFlagAttempt.failed(problem);
            },
          );
          expect(calls, 1);
          expect(report.failedCount, 1);
          expect(report.unattemptedCount, 2);
          expect(report.stopProblem, same(problem));
          expect(
            report.requiresRefresh,
            code == MailProblemCode.staleOperation,
          );
          expect(report.stopReason, switch (code) {
            MailProblemCode.cancelled => MailBulkFlagStopReason.cancelled,
            MailProblemCode.staleOperation => MailBulkFlagStopReason.staleScope,
            _ => MailBulkFlagStopReason.rateLimited,
          });
        });
      }

      for (final inScopeCheck in [true, false]) {
        test(
          'reentrant lease retirement in guard cannot dispatch ($inScopeCheck)',
          () async {
            final session = MailAccountSession(_account);
            final report = await run(
              lease: session.begin(),
              isScopeCurrent: () {
                if (inScopeCheck) session.invalidate();
                return true;
              },
              shouldStop: () {
                if (!inScopeCheck) session.invalidate();
                return false;
              },
              apply: (operation) async => fail('Retired lease dispatched.'),
            );
            expect(report.unattemptedCount, 3);
            expect(report.stopReason, MailBulkFlagStopReason.staleScope);
            expect(report.requiresRefresh, isTrue);
          },
        );
      }
    });
  }

  test(
    'contradictory failed certificate never hides possible mutation',
    () async {
      const problem = MailProblem(
        MailProblemCode.permissionDenied,
        mutationMayHaveOccurred: true,
      );
      var calls = 0;
      final report = await MailBulkFlagCoordinator().run(
        plan: _plan(),
        lease: MailAccountSession(_account).begin(),
        isScopeCurrent: () => true,
        apply: (operation, lease) async {
          calls++;
          return const MailBulkFlagAttempt.failed(problem);
        },
      );
      expect(calls, 1);
      expect(report.failedCount, 0);
      expect(report.uncertainCount, 1);
      expect(report.unattemptedCount, 2);
      expect(report.stopReason, MailBulkFlagStopReason.uncertain);
      expect(report.stopProblem, same(problem));
    },
  );

  test(
    'a predispatch scope rejection consumes the single-use coordinator',
    () async {
      final coordinator = MailBulkFlagCoordinator();
      Future<MailBulkFlagReport> start() => coordinator.run(
        plan: _plan(),
        lease: MailAccountSession(_account).begin(),
        isScopeCurrent: () => false,
        apply: (operation, lease) async => fail('Retired scope dispatched.'),
      );
      final first = await start();
      expect(first.unattemptedCount, 3);
      expect(first.stopReason, MailBulkFlagStopReason.staleScope);
      await expectLater(start(), throwsStateError);
    },
  );
  for (final reason in [
    MailBulkFlagStopReason.staleScope,
    MailBulkFlagStopReason.invalidScope,
    MailBulkFlagStopReason.scopeCheckFailed,
  ]) {
    test(
      '$reason requires a fresh observation even without a dispatched write',
      () async {
        final account = reason == MailBulkFlagStopReason.invalidScope
            ? MailAccountId('foreign', profile: _profile)
            : _account;
        final report = await MailBulkFlagCoordinator().run(
          plan: _plan(),
          lease: MailAccountSession(account).begin(),
          isScopeCurrent: () {
            if (reason == MailBulkFlagStopReason.scopeCheckFailed) {
              throw StateError('Retired scope');
            }
            return false;
          },
          apply: (operation, lease) async => fail('Invalid scope dispatched.'),
        );
        expect(report.stopReason, reason);
        expect(report.requiresRefresh, isTrue);
        expect(report.unattemptedCount, 3);
        expect(report.uncertainCount, 0);
      },
    );
  }
}
