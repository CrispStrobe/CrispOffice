import 'dart:async';

import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:test/test.dart';

final _account = MailAccountId(
  'account',
  profile: MailProfileId('snapshot', hostId: 'sync-tests'),
);
final _inbox = MailMailboxId('INBOX', account: _account);
final _archive = MailMailboxId('Archive', account: _account);

MailSyncPage _page(String cursor, {bool more = false}) => MailSyncPage(
  mailbox: _inbox,
  upserts: const [],
  tombstones: const [],
  next: MailCursor(mailbox: _inbox, value: cursor),
  hasMore: more,
);

void main() {
  late _Provider provider;
  late _SnapshotRepository repository;
  late MailAccountSession session;

  Future<MailResult<MailSyncPage>> pull({
    MailSyncRepository? storage,
    MailCancellationToken? cancellation,
  }) => const MailSyncCoordinator().pullPage(
    provider: provider,
    repository: storage ?? repository,
    session: session,
    mailbox: _inbox,
    cancellation: cancellation,
  );

  Future<MailSyncRunReport> run({
    MailSyncRepository? storage,
    MailCancellationToken? cancellation,
    void Function(MailSyncRunProgress)? onProgress,
  }) => const MailSyncRunner().run(
    provider: provider,
    repository: storage ?? repository,
    session: session,
    mailbox: _inbox,
    cancellation: cancellation,
    onProgress: onProgress,
  );

  setUp(() {
    provider = _Provider();
    repository = _SnapshotRepository();
    session = MailAccountSession(_account);
  });

  test('snapshot scopes a null cursor and bounds its durable revision', () {
    for (final revision in [0, 7, 0x1fffffffffffff]) {
      final value = MailSyncRepositorySnapshot(
        mailbox: _inbox,
        cursor: null,
        revision: revision,
      );
      expect(value.mailbox, _inbox);
      expect(value.cursor, isNull);
      expect(value.revision, revision);
    }
    for (final revision in [-1, 0x20000000000000]) {
      expect(
        () => MailSyncRepositorySnapshot(
          mailbox: _inbox,
          cursor: null,
          revision: revision,
        ),
        throwsArgumentError,
      );
    }
  });

  test('snapshot refuses a cursor from another folder or account', () {
    final otherAccount = MailAccountId('other', profile: _account.profile);
    for (final mailbox in [
      _archive,
      MailMailboxId('INBOX', account: otherAccount),
    ]) {
      expect(
        () => MailSyncRepositorySnapshot(
          mailbox: _inbox,
          cursor: MailCursor(mailbox: mailbox, value: 'same-token'),
          revision: 0,
        ),
        throwsArgumentError,
      );
    }
  });

  test(
    'coordinator captures nonzero revision before first provider page',
    () async {
      repository.revision = 7;
      provider.pages.add(MailSuccess(_page('first')));
      expect(await pull(), isA<MailSuccess<MailSyncPage>>());
      expect(provider.seenCursors, [null]);
      expect(repository.reads, 0);
      expect(repository.legacyCommits, 0);
      expect(repository.snapshots.single.revision, 7);
      expect(repository.snapshots.single.cursor, isNull);
      expect(repository.expected.single, same(repository.snapshots.single));
      expect(repository.commits, 1);
    },
  );

  test(
    'coordinator forwards the original cursor and snapshot unchanged',
    () async {
      final cursor = MailCursor(
        mailbox: _inbox,
        value: 'opaque-provider-cursor',
        repositoryRevision: 11,
      );
      repository
        ..cursor = cursor
        ..revision = 11;
      provider.pages.add(MailSuccess(_page('next')));
      expect(await pull(), isA<MailSuccess<MailSyncPage>>());
      expect(provider.seenCursors.single, same(cursor));
      expect(repository.expected.single.cursor, same(cursor));
      expect(repository.expected.single.revision, 11);
    },
  );

  for (final useRunner in [false, true]) {
    test(
      '${useRunner ? 'runner' : 'coordinator'} retains legacy adapter path',
      () async {
        final legacy = _LegacyRepository();
        provider.pages.add(MailSuccess(_page('first')));
        if (useRunner) {
          expect(
            (await run(storage: legacy)).status,
            MailSyncRunStatus.completed,
          );
        } else {
          expect(await pull(storage: legacy), isA<MailSuccess<MailSyncPage>>());
        }
        expect(legacy.reads, 1);
        expect(legacy.legacyCommits, 1);
        expect(legacy.commits, 1);
      },
    );

    for (final initialCursor in [false, true]) {
      test(
        '${useRunner ? 'runner' : 'coordinator'} rejects stale local revision with ${initialCursor ? 'unchanged' : 'null'} cursor',
        () async {
          if (initialCursor) {
            repository.cursor = MailCursor(mailbox: _inbox, value: 'initial');
          }
          final original = repository.cursor;
          provider.pending = Completer<MailResult<MailSyncPage>>();
          final pending = useRunner ? run() : pull();
          await provider.started.future;
          // An acknowledged move changes local membership while the old
          // provider request remains in flight. Provider cursor bytes stay put.
          repository.revision++;
          provider.pending!.complete(MailSuccess(_page('stale-page')));
          final result = await pending;
          final problem = switch (result) {
            MailSyncRunReport(:final problem) => problem!,
            MailFailure<MailSyncPage>(:final problem) => problem,
            _ => throw StateError('Expected stale synchronization failure.'),
          };
          expect(problem.code, MailProblemCode.conflict);
          expect(repository.commits, 0);
          expect(repository.cursor, same(original));
          expect(repository.snapshots.single.revision, 0);
          expect(repository.expected.single, same(repository.snapshots.single));
          expect(repository.legacyCommits, 0);
        },
      );
    }

    test(
      '${useRunner ? 'runner' : 'coordinator'} refuses a foreign snapshot before dispatch',
      () async {
        repository.overrideSnapshot = MailSyncRepositorySnapshot(
          mailbox: _archive,
          cursor: null,
          revision: 0,
        );
        if (useRunner) {
          expect((await run()).problem!.code, MailProblemCode.storageFailure);
        } else {
          final result = await pull();
          expect(
            (result as MailFailure<MailSyncPage>).problem.code,
            MailProblemCode.storageFailure,
          );
        }
        expect(provider.seenCursors, isEmpty);
        expect(repository.commits, 0);
      },
    );

    test(
      '${useRunner ? 'runner' : 'coordinator'} propagates snapshot read failure',
      () async {
        const problem = MailProblem(MailProblemCode.quotaExceeded);
        repository.readProblem = problem;
        if (useRunner) {
          expect((await run()).problem, same(problem));
        } else {
          expect(
            (await pull() as MailFailure<MailSyncPage>).problem,
            same(problem),
          );
        }
        expect(provider.seenCursors, isEmpty);
        expect(repository.commits, 0);
      },
    );
  }

  test(
    'runner forwards fresh snapshots and preserves immutable page progress',
    () async {
      repository.revision = 5;
      provider.pages.addAll([
        MailSuccess(_page('one', more: true)),
        MailSuccess(_page('two')),
      ]);
      final progress = <MailSyncRunProgress>[];
      final report = await run(onProgress: progress.add);
      expect(report.status, MailSyncRunStatus.completed);
      expect(report.committedPages, 2);
      expect(repository.snapshots.map((value) => value.revision), [5, 5]);
      expect(repository.snapshots.map((value) => value.cursor?.value), [
        null,
        'one',
      ]);
      expect(repository.expected[0], same(repository.snapshots[0]));
      expect(repository.expected[1], same(repository.snapshots[1]));
      expect(repository.reads, 0);
      expect(repository.legacyCommits, 0);
      expect(progress.map((value) => value.committedPages), [1, 2]);
      expect(progress.first.lastCommittedCursor!.value, 'one');
      expect(progress.last.lastCommittedCursor!.value, 'two');
      expect(provider.otherCalls, 0);
    },
  );

  test(
    'snapshot wrapper still rejects repeated continuation cursors',
    () async {
      provider.pages.addAll([
        MailSuccess(_page('repeat', more: true)),
        MailSuccess(_page('repeat', more: true)),
      ]);
      final report = await run();
      expect(report.status, MailSyncRunStatus.failed);
      expect(report.problem!.code, MailProblemCode.providerFailure);
      expect(report.committedPages, 1);
      expect(repository.expected, hasLength(1));
      expect(repository.commits, 1);
    },
  );

  test('snapshot wrapper permits an unchanged terminal cursor', () async {
    repository.cursor = MailCursor(mailbox: _inbox, value: 'unchanged');
    provider.pages.add(MailSuccess(_page('unchanged')));
    final report = await run();
    expect(report.status, MailSyncRunStatus.completed);
    expect(report.committedPages, 1);
    expect(repository.expected.single.cursor!.value, 'unchanged');
  });

  test('runner rejects an external cursor change between snapshots', () async {
    provider.pages.addAll([
      MailSuccess(_page('one', more: true)),
      MailSuccess(_page('must-not-load')),
    ]);
    final report = await run(
      onProgress: (_) {
        repository.cursor = MailCursor(mailbox: _inbox, value: 'external');
      },
    );
    expect(report.status, MailSyncRunStatus.failed);
    expect(report.problem!.code, MailProblemCode.conflict);
    expect(report.committedPages, 1);
    expect(provider.seenCursors, hasLength(1));
    expect(repository.snapshots, hasLength(2));
  });

  for (final failRead in [true, false]) {
    test(
      'runner contains snapshot ${failRead ? 'read' : 'commit'} exceptions',
      () async {
        final error = StateError('private repository details');
        if (failRead) {
          repository.readError = error;
        } else {
          repository.commitError = error;
          provider.pages.add(MailSuccess(_page('first')));
        }
        final report = await run();
        expect(report.status, MailSyncRunStatus.failed);
        expect(report.problem!.code, MailProblemCode.storageFailure);
        expect(report.committedPages, 0);
        expect(repository.commits, 0);
      },
    );
  }

  test('snapshot commit failure remains typed and adds no progress', () async {
    const problem = MailProblem(MailProblemCode.quotaExceeded);
    repository.commitProblem = problem;
    provider.pages.add(MailSuccess(_page('first')));
    final report = await run();
    expect(report.problem, same(problem));
    expect(report.committedPages, 0);
    expect(repository.cursor, isNull);
  });

  test('snapshot read cancellation stops before provider dispatch', () async {
    final cancellation = MailCancellationSource();
    repository.afterRead = cancellation.cancel;
    final report = await run(cancellation: cancellation.token);
    expect(report.status, MailSyncRunStatus.cancelled);
    expect(report.problem!.code, MailProblemCode.cancelled);
    expect(provider.seenCursors, isEmpty);
    expect(report.committedPages, 0);
  });

  test('cancellation during snapshot commit prevents persistence', () async {
    final cancellation = MailCancellationSource();
    repository.beforeCommit = cancellation.cancel;
    provider.pages.add(MailSuccess(_page('first')));
    final report = await run(cancellation: cancellation.token);
    expect(report.status, MailSyncRunStatus.cancelled);
    expect(repository.commits, 0);
    expect(repository.cursor, isNull);
    expect(report.committedPages, 0);
  });

  test(
    'cancellation after snapshot commit retains acknowledged progress',
    () async {
      final cancellation = MailCancellationSource();
      repository.afterCommit = cancellation.cancel;
      provider.pages.add(MailSuccess(_page('first')));
      final progress = <MailSyncRunProgress>[];
      final report = await run(
        cancellation: cancellation.token,
        onProgress: progress.add,
      );
      expect(report.status, MailSyncRunStatus.cancelled);
      expect(report.committedPages, 1);
      expect(report.lastCommittedCursor!.value, 'first');
      expect(repository.commits, 1);
      expect(progress, isEmpty);
    },
  );

  test(
    'progress invalidation cannot acquire a new snapshot for a retired run',
    () async {
      provider.pages.addAll([
        MailSuccess(_page('one', more: true)),
        MailSuccess(_page('must-not-load')),
      ]);
      final report = await run(onProgress: (_) => session.invalidate());
      expect(report.status, MailSyncRunStatus.cancelled);
      expect(report.problem!.code, MailProblemCode.staleOperation);
      expect(report.committedPages, 1);
      expect(repository.snapshots, hasLength(1));
      expect(provider.seenCursors, hasLength(1));
    },
  );
}

final class _Provider implements MailProvider {
  @override
  MailAccountId get account => _account;
  final List<MailResult<MailSyncPage>> pages = [];
  final List<MailCursor?> seenCursors = [];
  final Completer<void> started = Completer<void>();
  Completer<MailResult<MailSyncPage>>? pending;
  int otherCalls = 0;

  @override
  Future<MailResult<MailSyncPage>> pullChanges(
    MailMailboxId mailbox, {
    MailCursor? cursor,
    required int limit,
    required MailOperationLease lease,
  }) async {
    lease.checkCurrent();
    seenCursors.add(cursor);
    if (!started.isCompleted) started.complete();
    if (pending case final value?) return value.future;
    return pages.removeAt(0);
  }

  Future<MailResult<T>> _unsupported<T>() async {
    otherCalls++;
    return const MailFailure(MailProblem(MailProblemCode.unsupported));
  }

  @override
  Future<MailResult<MailCapabilities>> capabilities(MailOperationLease lease) =>
      _unsupported();
  @override
  Future<MailResult<List<MailMailbox>>> listMailboxes(
    MailOperationLease lease,
  ) => _unsupported();
  @override
  Future<MailResult<MailHeaderPage>> fetchHeaders(
    MailMailboxId mailbox, {
    MailCursor? cursor,
    required int limit,
    required MailOperationLease lease,
  }) => _unsupported();
  @override
  Future<MailResult<MailMessage>> fetchMessage(
    MailRemoteIdentity identity, {
    required MailReadBudget budget,
    required MailOperationLease lease,
  }) => _unsupported();
  @override
  Future<MailResult<MailUnit>> apply(
    MailOperation operation,
    MailOperationLease lease,
  ) => _unsupported();
}

/// Deterministic transaction fixture. Native durable storage is qualified by
/// its package; this fixture checks which fences the coordinator forwards.
class _LegacyRepository implements MailSyncRepository {
  MailCursor? cursor;
  int reads = 0;
  int legacyCommits = 0;
  int commits = 0;
  void Function()? beforeCommit;
  void Function()? afterCommit;

  @override
  Future<MailResult<MailCursor?>> readCursor(MailMailboxId mailbox) async {
    reads++;
    return MailSuccess(cursor);
  }

  @override
  Future<MailResult<MailUnit>> commitSyncPage(
    MailSyncPage page, {
    required MailCursor? expectedCursor,
    required MailOperationLease lease,
  }) async {
    legacyCommits++;
    beforeCommit?.call();
    lease.checkCurrent();
    if (!_cursorMatches(expectedCursor)) {
      return const MailFailure(MailProblem(MailProblemCode.conflict));
    }
    return _commit(page);
  }

  bool _cursorMatches(MailCursor? expected) =>
      expected?.mailbox == cursor?.mailbox && expected?.value == cursor?.value;

  MailResult<MailUnit> _commit(MailSyncPage page) {
    cursor = page.next;
    commits++;
    afterCommit?.call();
    return const MailSuccess(MailUnit.value);
  }
}

final class _SnapshotRepository extends _LegacyRepository
    implements MailSyncSnapshotRepository {
  int revision = 0;
  final List<MailSyncRepositorySnapshot> snapshots = [];
  final List<MailSyncRepositorySnapshot> expected = [];
  MailSyncRepositorySnapshot? overrideSnapshot;
  MailProblem? readProblem;
  MailProblem? commitProblem;
  Object? readError;
  Object? commitError;
  void Function()? afterRead;

  @override
  Future<MailResult<MailSyncRepositorySnapshot>> readSyncSnapshot(
    MailMailboxId mailbox,
  ) async {
    if (readError case final error?) throw error;
    if (readProblem case final problem?) return MailFailure(problem);
    final snapshot =
        overrideSnapshot ??
        MailSyncRepositorySnapshot(
          mailbox: mailbox,
          cursor: cursor,
          revision: revision,
        );
    snapshots.add(snapshot);
    afterRead?.call();
    return MailSuccess(snapshot);
  }

  @override
  Future<MailResult<MailUnit>> commitSyncPageWithSnapshot(
    MailSyncPage page, {
    required MailSyncRepositorySnapshot expectedSnapshot,
    required MailOperationLease lease,
  }) async {
    expected.add(expectedSnapshot);
    if (commitError case final error?) throw error;
    beforeCommit?.call();
    lease.checkCurrent();
    if (expectedSnapshot.mailbox != page.mailbox ||
        expectedSnapshot.revision != revision ||
        !_cursorMatches(expectedSnapshot.cursor)) {
      return const MailFailure(MailProblem(MailProblemCode.conflict));
    }
    if (commitProblem case final problem?) return MailFailure(problem);
    return _commit(page);
  }
}
