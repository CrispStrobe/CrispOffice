import 'dart:async';

import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:test/test.dart';

final _profile = MailProfileId('profile', hostId: 'bulk-test');
final _account = MailAccountId('account', profile: _profile);
final _mailbox = MailMailboxId('inbox', account: _account);

List<MailRemoteIdentity> _messages(
  int count, {
  MailAccountId? account,
  MailProviderKind provider = MailProviderKind.graph,
}) => List<MailRemoteIdentity>.generate(
  count,
  (index) => MailOpaqueIdentity(
    account: account ?? _account,
    provider: provider,
    value: 'message-$index',
  ),
);

MailBulkFlagPlan _plan({
  String id = 'batch',
  MailMailboxId? mailbox,
  MailProviderKind provider = MailProviderKind.graph,
  List<MailRemoteIdentity>? messages,
  MailBulkFlagAction action = MailBulkFlagAction.markRead,
}) => MailBulkFlagPlan(
  id: id,
  mailbox: mailbox ?? _mailbox,
  provider: provider,
  messages: messages ?? _messages(3, provider: provider),
  action: action,
);

Future<MailBulkFlagReport> _run({
  required MailBulkFlagApply apply,
  MailBulkFlagPlan? plan,
  MailOperationLease? lease,
  bool Function()? isScopeCurrent,
  MailCancellationToken? cancellation,
}) => MailBulkFlagCoordinator().run(
  plan: plan ?? _plan(),
  lease: lease ?? MailAccountSession(_account).begin(),
  isScopeCurrent: isScopeCurrent ?? () => true,
  apply: apply,
  cancellation: cancellation,
);

const _confirmed = MailBulkFlagAttempt.confirmed();
const _denied = MailProblem(MailProblemCode.permissionDenied);
const _lostReply = MailProblem(MailProblemCode.unavailable);

void main() {
  group('frozen bulk flag plan', () {
    test('copies selection and rejects subsequent caller mutation', () {
      final messages = _messages(3);
      final identities = List<MailRemoteIdentity>.of(messages);
      final plan = _plan(messages: messages);
      messages.clear();
      expect(plan.messages, identities);
      expect(() => plan.messages.clear(), throwsUnsupportedError);
      expect(plan.operationAt(0).message, same(identities.first));
      expect(plan.operationAt(0).id, 'batch:0');
      expect(plan.operationAt(2).id, 'batch:2');
    });

    test(
      'accepts the exact selection bound and refuses empty/oversized input',
      () {
        expect(_plan(messages: _messages(1000)).messages.length, 1000);
        expect(() => _plan(messages: []), throwsArgumentError);
        expect(() => _plan(messages: _messages(1001)), throwsArgumentError);
      },
    );

    test('rejects invalid batch IDs without exposing the supplied ID', () {
      for (final id in ['', ' ', '\nsecret', 'secret\x00', 'x' * 257]) {
        expect(() => _plan(id: id), throwsArgumentError);
      }
      expect(_plan(id: 'x' * 256).id.length, 256);
      try {
        _plan(id: 'sensitive-recipient@example.test\x00');
        fail('A control character must be rejected.');
      } on ArgumentError catch (error) {
        expect(error.toString(), isNot(contains('sensitive-recipient')));
      }
    });

    test('rejects structurally equal duplicate remote identities', () {
      final first = _messages(1).single;
      final equalCopy = _messages(1).single;
      expect(identical(first, equalCopy), isFalse);
      expect(() => _plan(messages: [first, equalCopy]), throwsArgumentError);
    });

    test('does not merge account IDs belonging to different host profiles', () {
      final other = MailAccountId(
        'account',
        profile: MailProfileId('profile', hostId: 'other-host'),
      );
      expect(
        () => _plan(messages: _messages(1, account: other)),
        throwsArgumentError,
      );
    });

    test('rejects mixed providers and a local provider plan', () {
      expect(
        () => _plan(
          messages: [
            ..._messages(1),
            ..._messages(1, provider: MailProviderKind.gmail),
          ],
        ),
        throwsArgumentError,
      );
      expect(
        () => _plan(provider: MailProviderKind.local, messages: _messages(1)),
        throwsArgumentError,
      );
    });

    test('IMAP freezes UIDVALIDITY and never accepts another folder', () {
      MailImapIdentity imap(MailMailboxId mailbox, int validity, int uid) =>
          MailImapIdentity(mailbox: mailbox, uidValidity: validity, uid: uid);
      final messages = [imap(_mailbox, 9, 1), imap(_mailbox, 9, 2)];
      final plan = _plan(provider: MailProviderKind.imap, messages: messages);
      expect(plan.messages, messages);
      expect(
        () => _plan(
          provider: MailProviderKind.imap,
          messages: [imap(_mailbox, 9, 1), imap(_mailbox, 10, 2)],
        ),
        throwsArgumentError,
      );
      expect(
        () => _plan(
          provider: MailProviderKind.imap,
          messages: [
            imap(_mailbox, 9, 1),
            imap(MailMailboxId('archive', account: _account), 9, 2),
          ],
        ),
        throwsArgumentError,
      );
    });

    for (final provider in [
      MailProviderKind.graph,
      MailProviderKind.gmail,
      MailProviderKind.ews,
      MailProviderKind.jmap,
    ]) {
      test('${provider.name} keeps its opaque identity namespace', () {
        final plan = _plan(provider: provider);
        expect(
          plan.messages.every((message) => message.provider == provider),
          isTrue,
        );
        expect(plan.operationAt(0).message, same(plan.messages.first));
      });
    }

    test('each action assigns exactly one flag without reading old flags', () {
      for (final action in MailBulkFlagAction.values) {
        final operation = _plan(action: action).operationAt(1);
        expect(operation.id, 'batch:1');
        switch (action) {
          case MailBulkFlagAction.markRead:
            expect(operation, isA<MailSetRead>());
            expect((operation as MailSetRead).read, isTrue);
          case MailBulkFlagAction.markUnread:
            expect(operation, isA<MailSetRead>());
            expect((operation as MailSetRead).read, isFalse);
          case MailBulkFlagAction.flag:
            expect(operation, isA<MailSetFlagged>());
            expect((operation as MailSetFlagged).flagged, isTrue);
          case MailBulkFlagAction.unflag:
            expect(operation, isA<MailSetFlagged>());
            expect((operation as MailSetFlagged).flagged, isFalse);
        }
      }
    });
  });

  group('foreground outcome accounting', () {
    test(
      'dispatches sequentially in frozen order and retains the exact lease',
      () async {
        final gate = Completer<MailBulkFlagAttempt>();
        final started = Completer<void>();
        final calls = <String>[];
        final lease = MailAccountSession(_account).begin();
        final future = _run(
          lease: lease,
          apply: (operation, actualLease) async {
            expect(actualLease, same(lease));
            calls.add(operation.id);
            if (calls.length == 1) {
              started.complete();
              return gate.future;
            }
            return _confirmed;
          },
        );
        await started.future;
        expect(calls, ['batch:0']);
        gate.complete(_confirmed);
        final report = await future;
        expect(calls, ['batch:0', 'batch:1', 'batch:2']);
        expect(report.items.map((item) => item.operation.id), calls);
        expect(report.confirmedCount, 3);
        expect(report.failedCount, 0);
        expect(report.uncertainCount, 0);
        expect(report.unattemptedCount, 0);
        expect(report.stopReason, isNull);
        expect(() => report.items.clear(), throwsUnsupportedError);
      },
    );

    test(
      'definite rejection is retained and does not stop other messages',
      () async {
        var calls = 0;
        final report = await _run(
          apply: (operation, lease) async => ++calls == 2
              ? const MailBulkFlagAttempt.failed(_denied)
              : _confirmed,
        );
        expect(calls, 3);
        expect(report.confirmedCount, 2);
        expect(report.failedCount, 1);
        expect(report.uncertainCount, 0);
        expect(report.unattemptedCount, 0);
        expect(report.items[1].problem, same(_denied));
        expect(report.stopReason, isNull);
      },
    );

    test(
      'uncertainty stops immediately and accounts for the remaining selection',
      () async {
        var calls = 0;
        final report = await _run(
          apply: (operation, lease) async => ++calls == 2
              ? const MailBulkFlagAttempt.uncertain(_lostReply)
              : _confirmed,
        );
        expect(calls, 2);
        expect(report.confirmedCount, 1);
        expect(report.failedCount, 0);
        expect(report.uncertainCount, 1);
        expect(report.unattemptedCount, 1);
        expect(report.items[1].problem, same(_lostReply));
        expect(report.items[2].problem, isNull);
        expect(report.stopReason, MailBulkFlagStopReason.uncertain);
        expect(report.items.map((item) => item.message), report.plan.messages);
      },
    );

    test(
      'an uncertain last reply is never reported as a completed batch',
      () async {
        final report = await _run(
          plan: _plan(messages: _messages(1)),
          apply: (operation, lease) async =>
              const MailBulkFlagAttempt.uncertain(_lostReply),
        );
        expect(report.uncertainCount, 1);
        expect(report.unattemptedCount, 0);
        expect(report.stopReason, MailBulkFlagStopReason.uncertain);
      },
    );

    test(
      'synchronous adapter exceptions are uncertain and omit raw error text',
      () async {
        final report = await _run(
          apply: (operation, lease) =>
              throw StateError('secret server response'),
        );
        expect(report.uncertainCount, 1);
        expect(report.unattemptedCount, 2);
        expect(
          report.items.first.problem!.code,
          MailProblemCode.providerFailure,
        );
        expect(
          report.items.first.problem.toString(),
          isNot(contains('secret')),
        );
      },
    );

    test(
      'asynchronous failure after dispatch is uncertain without retry',
      () async {
        var calls = 0;
        final report = await _run(
          apply: (operation, lease) async {
            calls++;
            await Future<void>.value();
            throw StateError('lost response');
          },
        );
        expect(calls, 1);
        expect(report.uncertainCount, 1);
        expect(report.unattemptedCount, 2);
      },
    );

    test(
      'MailCancelled from an invoked adapter cannot prove non-delivery',
      () async {
        final report = await _run(
          apply: (operation, lease) async =>
              throw const MailCancelled(MailCancellationReason.user),
        );
        expect(report.uncertainCount, 1);
        expect(report.unattemptedCount, 2);
        expect(report.stopReason, MailBulkFlagStopReason.uncertain);
      },
    );

    test('a coordinator rejects overlap and later replay', () async {
      final coordinator = MailBulkFlagCoordinator();
      final gate = Completer<MailBulkFlagAttempt>();
      final entered = Completer<void>();
      var calls = 0;
      Future<MailBulkFlagReport> start() => coordinator.run(
        plan: _plan(messages: _messages(1)),
        lease: MailAccountSession(_account).begin(),
        isScopeCurrent: () => true,
        apply: (operation, lease) {
          calls++;
          entered.complete();
          return gate.future;
        },
      );
      final first = start();
      await entered.future;
      await expectLater(start(), throwsStateError);
      gate.complete(_confirmed);
      await first;
      await expectLater(start(), throwsStateError);
      expect(calls, 1);
    });
  });

  group('scope and cancellation boundaries', () {
    test('a foreign account lease dispatches nothing', () async {
      var calls = 0;
      final report = await _run(
        lease: MailAccountSession(
          MailAccountId('other', profile: _profile),
        ).begin(),
        apply: (operation, lease) async {
          calls++;
          return _confirmed;
        },
      );
      expect(calls, 0);
      expect(report.unattemptedCount, 3);
      expect(report.stopReason, MailBulkFlagStopReason.invalidScope);
    });

    test(
      'a stale folder before dispatch leaves every identity unattempted',
      () async {
        final report = await _run(
          isScopeCurrent: () => false,
          apply: (operation, lease) async => fail('Must not dispatch.'),
        );
        expect(report.unattemptedCount, 3);
        expect(report.stopReason, MailBulkFlagStopReason.staleScope);
      },
    );

    test('a failing scope check before dispatch fails closed', () async {
      final report = await _run(
        isScopeCurrent: () => throw StateError('private scope data'),
        apply: (operation, lease) async => fail('Must not dispatch.'),
      );
      expect(report.unattemptedCount, 3);
      expect(report.stopReason, MailBulkFlagStopReason.scopeCheckFailed);
    });

    test(
      'invalidation and disposal make a previously captured lease stale',
      () async {
        for (final dispose in [false, true]) {
          final session = MailAccountSession(_account);
          final lease = session.begin();
          if (dispose) {
            session.dispose();
          } else {
            session.invalidate();
          }
          final report = await _run(
            lease: lease,
            apply: (operation, lease) async => fail('Must not dispatch.'),
          );
          expect(report.unattemptedCount, 3);
          expect(report.stopReason, MailBulkFlagStopReason.staleScope);
        }
      },
    );

    test(
      'a cancelled separate token prevents dispatch without invalidating lease',
      () async {
        final cancellation = MailCancellationSource()..cancel();
        final lease = MailAccountSession(_account).begin();
        final report = await _run(
          lease: lease,
          cancellation: cancellation.token,
          apply: (operation, lease) async => fail('Must not dispatch.'),
        );
        expect(lease.isCurrent, isTrue);
        expect(report.unattemptedCount, 3);
        expect(report.stopReason, MailBulkFlagStopReason.cancelled);
      },
    );

    test(
      'lease cancellation reasons preserve user versus obsolete scope',
      () async {
        for (final reason in MailCancellationReason.values) {
          final cancellation = MailCancellationSource();
          final lease = MailAccountSession(
            _account,
          ).begin(cancellation: cancellation.token);
          cancellation.cancel(reason);
          final report = await _run(
            lease: lease,
            apply: (operation, lease) async => fail('Must not dispatch.'),
          );
          expect(report.unattemptedCount, 3);
          expect(
            report.stopReason,
            reason == MailCancellationReason.user ||
                    reason == MailCancellationReason.budgetExpired
                ? MailBulkFlagStopReason.cancelled
                : MailBulkFlagStopReason.staleScope,
          );
        }
      },
    );

    test(
      'stop waits for the current reply and retains its confirmation',
      () async {
        final cancellation = MailCancellationSource();
        final gate = Completer<MailBulkFlagAttempt>();
        final entered = Completer<void>();
        var calls = 0;
        var completed = false;
        final future =
            _run(
              cancellation: cancellation.token,
              apply: (operation, lease) {
                calls++;
                entered.complete();
                return gate.future;
              },
            ).then((report) {
              completed = true;
              return report;
            });
        await entered.future;
        cancellation.cancel();
        await Future<void>.value();
        expect(completed, isFalse);
        gate.complete(_confirmed);
        final report = await future;
        expect(calls, 1);
        expect(report.confirmedCount, 1);
        expect(report.unattemptedCount, 2);
        expect(report.stopReason, MailBulkFlagStopReason.cancelled);
      },
    );

    test(
      'uncertainty after user stop still requires uncertainty disclosure',
      () async {
        final cancellation = MailCancellationSource();
        final report = await _run(
          cancellation: cancellation.token,
          apply: (operation, lease) async {
            cancellation.cancel();
            return const MailBulkFlagAttempt.uncertain(_lostReply);
          },
        );
        expect(report.uncertainCount, 1);
        expect(report.unattemptedCount, 2);
        expect(report.stopReason, MailBulkFlagStopReason.uncertain);
      },
    );

    test('folder A to B to A cannot reuse an earlier generation', () async {
      var generation = 0;
      var folder = 'A';
      final capturedGeneration = generation;
      final report = await _run(
        isScopeCurrent: () => folder == 'A' && generation == capturedGeneration,
        apply: (operation, lease) async {
          folder = 'B';
          generation++;
          folder = 'A';
          generation++;
          return _confirmed;
        },
      );
      expect(folder, 'A');
      expect(report.confirmedCount, 1);
      expect(report.unattemptedCount, 2);
      expect(report.stopReason, MailBulkFlagStopReason.staleScope);
    });

    test(
      'an account change after dispatch retains the known remote result',
      () async {
        final session = MailAccountSession(_account);
        final report = await _run(
          lease: session.begin(),
          apply: (operation, lease) async {
            session.invalidate();
            return const MailBulkFlagAttempt.failed(_denied);
          },
        );
        expect(report.failedCount, 1);
        expect(report.unattemptedCount, 2);
        expect(report.items.first.problem, same(_denied));
        expect(report.stopReason, MailBulkFlagStopReason.staleScope);
      },
    );

    test(
      'scope check failure after confirmation does not erase that receipt',
      () async {
        var applied = false;
        final report = await _run(
          isScopeCurrent: () {
            if (applied) throw StateError('scope unavailable');
            return true;
          },
          apply: (operation, lease) async {
            applied = true;
            return _confirmed;
          },
        );
        expect(report.confirmedCount, 1);
        expect(report.unattemptedCount, 2);
        expect(report.stopReason, MailBulkFlagStopReason.scopeCheckFailed);
      },
    );
  });
}
