import 'dart:async';
import 'dart:collection';

import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:test/test.dart';

final _profile = MailProfileId('profile', hostId: 'bulk-tests');
final _account = MailAccountId('account', profile: _profile);
final _mailbox = MailMailboxId('INBOX', account: _account);

MailImapIdentity _imap(int uid, {MailMailboxId? mailbox, int validity = 7}) =>
    MailImapIdentity(
      mailbox: mailbox ?? _mailbox,
      uidValidity: validity,
      uid: uid,
    );

MailBulkFlagPlan _plan({
  MailBulkFlagAction action = MailBulkFlagAction.markRead,
  List<MailRemoteIdentity>? messages,
}) => MailBulkFlagPlan(
  id: 'batch',
  mailbox: _mailbox,
  action: action,
  messages: messages ?? [_imap(1), _imap(2), _imap(3)],
);

const _success = MailSuccess<MailUnit>(MailUnit.value);

final class _OversizedSelection extends ListBase<MailRemoteIdentity> {
  @override
  int get length => MailBulkFlagPlan.maxMessages + 1;
  @override
  set length(int value) => throw UnsupportedError('Immutable test input');
  @override
  MailRemoteIdentity operator [](int index) =>
      throw StateError('An oversized selection must not be traversed.');
  @override
  void operator []=(int index, MailRemoteIdentity value) =>
      throw UnsupportedError('Immutable test input');
}

Future<MailBulkFlagReport> _run(
  Future<MailResult<MailUnit>> Function(MailOperation, MailOperationLease)
  apply, {
  MailBulkFlagPlan? plan,
  MailOperationLease? lease,
  bool Function()? isScopeCurrent,
  bool Function()? shouldStop,
  void Function(MailBulkFlagReport)? onProgress,
}) => const MailBulkFlagRunner().run(
  plan: plan ?? _plan(),
  lease: lease ?? MailAccountSession(_account).begin(),
  apply: apply,
  isScopeCurrent: isScopeCurrent ?? () => true,
  shouldStop: shouldStop,
  onProgress: onProgress,
);

void main() {
  test('plan freezes stable identities and rejects list mutation', () {
    final input = <MailRemoteIdentity>[_imap(1), _imap(2)];
    final plan = _plan(messages: input);
    input.clear();
    expect(plan.messages, [_imap(1), _imap(2)]);
    expect(() => plan.messages.clear(), throwsUnsupportedError);
  });

  test('plan bounds the selection and operation IDs before work', () {
    for (final id in ['', 'bad\nkey', 'x' * 1001]) {
      expect(
        () => MailBulkFlagPlan(
          id: id,
          mailbox: _mailbox,
          action: MailBulkFlagAction.flag,
          messages: [_imap(1)],
        ),
        throwsArgumentError,
      );
    }
    expect(() => _plan(messages: []), throwsArgumentError);
    expect(() => _plan(messages: _OversizedSelection()), throwsArgumentError);
    expect(
      () => _plan(messages: List.generate(1001, (index) => _imap(index + 1))),
      throwsArgumentError,
    );
    expect(
      _plan(
        messages: List.generate(1000, (index) => _imap(index + 1)),
      ).messages.length,
      1000,
    );
  });

  test('duplicate value identities are rejected even in different objects', () {
    expect(() => _plan(messages: [_imap(1), _imap(1)]), throwsArgumentError);
  });

  test('wrong account, folder and mixed IMAP generations are rejected', () {
    final otherAccount = MailAccountId('other', profile: _profile);
    final otherFolder = MailMailboxId('Archive', account: _account);
    final otherInbox = MailMailboxId('INBOX', account: otherAccount);
    for (final identity in [
      _imap(2, mailbox: otherFolder),
      _imap(2, mailbox: otherInbox),
      _imap(2, validity: 8),
    ]) {
      expect(() => _plan(messages: [_imap(1), identity]), throwsArgumentError);
    }
  });

  test('opaque provider namespaces cannot mix in one selected mailbox', () {
    final gmail = MailOpaqueIdentity(
      account: _account,
      provider: MailProviderKind.gmail,
      value: 'one',
    );
    final graph = MailOpaqueIdentity(
      account: _account,
      provider: MailProviderKind.graph,
      value: 'two',
    );
    expect(() => _plan(messages: [gmail, graph]), throwsArgumentError);
    expect(() => _plan(messages: [_imap(1), gmail]), throwsArgumentError);
    expect(_plan(messages: [gmail]).messages.single, same(gmail));
  });

  for (final action in MailBulkFlagAction.values) {
    test(
      'explicit ${action.name} freezes desired state and ordered IDs',
      () async {
        final commands = <MailOperation>[];
        final report = await _run((command, lease) async {
          commands.add(command);
          return _success;
        }, plan: _plan(action: action));
        expect(commands.map((command) => command.id), [
          'batch-0',
          'batch-1',
          'batch-2',
        ]);
        expect(commands.map((command) => command.message), [
          _imap(1),
          _imap(2),
          _imap(3),
        ]);
        if (action == MailBulkFlagAction.markRead ||
            action == MailBulkFlagAction.markUnread) {
          expect(
            commands.cast<MailSetRead>().every(
              (command) =>
                  command.read == (action == MailBulkFlagAction.markRead),
            ),
            isTrue,
          );
        } else {
          expect(
            commands.cast<MailSetFlagged>().every(
              (command) =>
                  command.flagged == (action == MailBulkFlagAction.flag),
            ),
            isTrue,
          );
        }
        expect(report.confirmedCount, 3);
        expect(report.failedCount, 0);
        expect(report.uncertainCount, 0);
        expect(report.unattemptedCount, 0);
        expect(report.stopProblem, isNull);
        expect(report.requiresRefresh, isFalse);
      },
    );
  }

  test(
    'dispatch is sequential and progress snapshots remain immutable',
    () async {
      final pending = <Completer<MailResult<MailUnit>>>[];
      final progress = <MailBulkFlagReport>[];
      final future = _run((command, lease) {
        final completer = Completer<MailResult<MailUnit>>();
        pending.add(completer);
        return completer.future;
      }, onProgress: progress.add);
      expect(pending, hasLength(1));
      expect(progress.single.unattemptedCount, 3);
      pending[0].complete(_success);
      await Future<void>.delayed(Duration.zero);
      expect(pending, hasLength(2));
      pending[1].complete(_success);
      await Future<void>.delayed(Duration.zero);
      expect(pending, hasLength(3));
      pending[2].complete(_success);
      final report = await future;
      expect(progress.map((snapshot) => snapshot.confirmedCount), [0, 1, 2, 3]);
      expect(progress.first.unattemptedCount, 3);
      expect(report.results.map((result) => result.message), _plan().messages);
      expect(() => report.results.clear(), throwsUnsupportedError);
    },
  );

  test(
    'certified no-write failure permits independent later commands',
    () async {
      var count = 0;
      final report = await _run((command, lease) async {
        if (count++ == 1) {
          return const MailFailure(
            MailProblem(
              MailProblemCode.permissionDenied,
              mutationMayHaveOccurred: false,
            ),
          );
        }
        return _success;
      });
      expect(count, 3);
      expect(report.results.map((result) => result.outcome), [
        MailBulkFlagOutcome.confirmed,
        MailBulkFlagOutcome.failed,
        MailBulkFlagOutcome.confirmed,
      ]);
      expect(report.failedCount, 1);
      expect(report.requiresRefresh, isFalse);
    },
  );

  for (final evidence in <bool?>[true, null]) {
    test(
      'mutation evidence $evidence stops at uncertainty without replay',
      () async {
        var count = 0;
        final report = await _run((command, lease) async {
          if (count++ == 1) {
            return MailFailure(
              MailProblem(
                MailProblemCode.permissionDenied,
                mutationMayHaveOccurred: evidence,
              ),
            );
          }
          return _success;
        });
        expect(count, 2);
        expect(report.results.map((result) => result.outcome), [
          MailBulkFlagOutcome.confirmed,
          MailBulkFlagOutcome.uncertain,
          MailBulkFlagOutcome.unattempted,
        ]);
        expect(report.uncertainCount, 1);
        expect(report.unattemptedCount, 1);
        expect(report.requiresRefresh, isTrue);
        expect(report.stopProblem?.code, MailProblemCode.permissionDenied);
      },
    );
  }

  test('conflict code with certified no-write evidence is definite', () async {
    final report = await _run((command, lease) async {
      return const MailFailure(
        MailProblem(MailProblemCode.conflict, mutationMayHaveOccurred: false),
      );
    });
    expect(report.failedCount, 3);
    expect(report.uncertainCount, 0);
    expect(report.requiresRefresh, isFalse);
  });

  for (final code in [
    MailProblemCode.cancelled,
    MailProblemCode.staleOperation,
  ]) {
    test('provider $code stops even when no mutation occurred', () async {
      var count = 0;
      final report = await _run((command, lease) async {
        count++;
        return MailFailure(MailProblem(code, mutationMayHaveOccurred: false));
      });
      expect(count, 1);
      expect(report.failedCount, 1);
      expect(report.unattemptedCount, 2);
      expect(report.stopProblem?.code, code);
    });
  }

  test('callback exception after possible dispatch is uncertain', () async {
    var count = 0;
    final report = await _run((command, lease) async {
      count++;
      throw StateError('raw provider content must not become report text');
    });
    expect(count, 1);
    expect(report.uncertainCount, 1);
    expect(report.unattemptedCount, 2);
    expect(report.stopProblem?.code, MailProblemCode.providerFailure);
    expect(report.stopProblem?.mutationMayHaveOccurred, isNull);
  });

  test('wrong-account lease cannot dispatch', () async {
    var count = 0;
    final report = await _run(
      (command, lease) async {
        count++;
        return _success;
      },
      lease: MailAccountSession(
        MailAccountId('other', profile: _profile),
      ).begin(),
    );
    expect(count, 0);
    expect(report.unattemptedCount, 3);
    expect(report.stopProblem?.code, MailProblemCode.invalidInput);
  });

  test(
    'cancellation before dispatch leaves all identities unattempted',
    () async {
      final cancellation = MailCancellationSource();
      final lease = MailAccountSession(
        _account,
      ).begin(cancellation: cancellation.token);
      cancellation.cancel();
      var count = 0;
      final report = await _run((command, lease) async {
        count++;
        return _success;
      }, lease: lease);
      expect(count, 0);
      expect(report.unattemptedCount, 3);
      expect(report.stopProblem?.code, MailProblemCode.cancelled);
    },
  );

  test('stale account lease cannot dispatch', () async {
    final session = MailAccountSession(_account);
    final lease = session.begin();
    session.invalidate();
    var count = 0;
    final report = await _run((command, lease) async {
      count++;
      return _success;
    }, lease: lease);
    expect(count, 0);
    expect(report.unattemptedCount, 3);
    expect(report.stopProblem?.code, MailProblemCode.staleOperation);
  });

  test('disposed account session cannot dispatch', () async {
    final session = MailAccountSession(_account);
    final lease = session.begin();
    session.dispose();
    final report = await _run((command, lease) async {
      fail('Disposed session dispatched a command.');
    }, lease: lease);
    expect(report.unattemptedCount, 3);
    expect(report.stopProblem?.code, MailProblemCode.staleOperation);
  });

  for (final throws in [false, true]) {
    test('stale folder predicate (throws=$throws) rejects selection', () async {
      final report = await _run(
        (command, lease) async {
          fail('Stale folder dispatched a command.');
        },
        isScopeCurrent: () {
          if (throws) throw StateError('stale view');
          return false;
        },
      );
      expect(report.unattemptedCount, 3);
      expect(report.stopProblem?.code, MailProblemCode.staleOperation);
    });
  }

  test(
    'successful in-flight result survives scope change but stops next write',
    () async {
      final pending = Completer<MailResult<MailUnit>>();
      var current = true;
      var count = 0;
      final future = _run((command, lease) {
        count++;
        return pending.future;
      }, isScopeCurrent: () => current);
      current = false;
      pending.complete(_success);
      final report = await future;
      expect(count, 1);
      expect(report.confirmedCount, 1);
      expect(report.unattemptedCount, 2);
      expect(report.stopProblem?.code, MailProblemCode.staleOperation);
    },
  );

  test(
    'in-flight cancellation cannot erase confirmed acknowledgement',
    () async {
      final pending = Completer<MailResult<MailUnit>>();
      final cancellation = MailCancellationSource();
      final future = _run(
        (command, lease) => pending.future,
        lease: MailAccountSession(
          _account,
        ).begin(cancellation: cancellation.token),
      );
      cancellation.cancel();
      pending.complete(_success);
      final report = await future;
      expect(report.confirmedCount, 1);
      expect(report.unattemptedCount, 2);
      expect(report.stopProblem?.code, MailProblemCode.cancelled);
    },
  );

  test('scope retirement in progress callback prevents next command', () async {
    var count = 0;
    var current = true;
    final report = await _run(
      (command, lease) async {
        count++;
        return _success;
      },
      isScopeCurrent: () => current,
      onProgress: (progress) {
        if (progress.confirmedCount == 1) current = false;
      },
    );
    expect(count, 1);
    expect(report.confirmedCount, 1);
    expect(report.unattemptedCount, 2);
    expect(report.stopProblem?.code, MailProblemCode.staleOperation);
  });

  test('display observer exceptions cannot change command outcomes', () async {
    var count = 0;
    final report = await _run((command, lease) async {
      count++;
      return _success;
    }, onProgress: (_) => throw StateError('display failure'));
    expect(count, 3);
    expect(report.confirmedCount, 3);
    expect(report.stopProblem, isNull);
  });

  test(
    'Stop after current preserves acknowledgement without cancelling lease',
    () async {
      final pending = Completer<MailResult<MailUnit>>();
      var stopping = false;
      var calls = 0;
      final lease = MailAccountSession(_account).begin();
      final future = _run(
        (command, operationLease) {
          calls++;
          return pending.future;
        },
        lease: lease,
        shouldStop: () => stopping,
      );
      stopping = true;
      expect(lease.isCurrent, isTrue);
      pending.complete(_success);
      final report = await future;
      expect(calls, 1);
      expect(report.confirmedCount, 1);
      expect(report.unattemptedCount, 2);
      expect(report.stopProblem?.code, MailProblemCode.cancelled);
      expect(report.requiresRefresh, isFalse);
      expect(lease.isCurrent, isTrue);
    },
  );

  for (final throws in [false, true]) {
    test(
      'Stop before dispatch (throws=$throws) leaves all unattempted',
      () async {
        final report = await _run(
          (command, lease) async {
            fail('Stop request dispatched a command.');
          },
          shouldStop: () {
            if (throws) throw StateError('stop source retired');
            return true;
          },
        );
        expect(report.unattemptedCount, 3);
        expect(report.stopProblem?.code, MailProblemCode.cancelled);
      },
    );
  }
}
