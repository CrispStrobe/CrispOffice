import 'dart:async';

import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:test/test.dart';

void main() {
  late MailAccountId account;
  late MailMailboxId inbox;
  late MailAccountSession session;
  late _Provider provider;
  late _Repository repository;
  const runner = MailSyncRunner();

  Future<MailSyncRunReport> run({
    int pageSize = 100,
    int maxPages = 10,
    MailCancellationToken? cancellation,
    void Function(MailSyncRunProgress)? onProgress,
  }) => runner.run(
    provider: provider,
    repository: repository,
    session: session,
    mailbox: inbox,
    pageSize: pageSize,
    maxPages: maxPages,
    cancellation: cancellation,
    onProgress: onProgress,
  );

  setUp(() {
    account = MailAccountId('a', profile: MailProfileId('p', hostId: 'office'));
    inbox = MailMailboxId('INBOX', account: account);
    session = MailAccountSession(account);
    provider = _Provider(account);
    repository = _Repository();
  });

  test(
    'commits multiple pages and immutable progress including resets',
    () async {
      provider.pages.addAll([
        MailSuccess(_page(inbox, 'one', uids: [1, 2], more: true)),
        MailSuccess(_page(inbox, 'two', uids: [3], deleted: [1], reset: true)),
      ]);
      final progress = <MailSyncRunProgress>[];
      final report = await run(pageSize: 3, onProgress: progress.add);

      expect(report.status, MailSyncRunStatus.completed);
      expect(report.problem, isNull);
      expect(report.mailbox, inbox);
      expect(report.committedPages, 2);
      expect(report.upsertCount, 3);
      expect(report.tombstoneCount, 1);
      expect(report.resetCount, 1);
      expect(report.lastCommittedCursor!.value, 'two');
      expect(report.hasMore, isFalse);
      expect(provider.seenCursors, [null, 'one']);
      expect(provider.limits, [3, 3]);
      expect(
        repository.records.keys.map((id) => (id as MailImapIdentity).uid),
        [3],
      );
      expect(progress, hasLength(2));
      expect(progress.first.committedPages, 1);
      expect(progress.first.upsertCount, 2);
      expect(progress.first.resetCount, 0);
      expect(progress.first.lastCommittedCursor!.value, 'one');
      expect(progress.first.hasMore, isTrue);
      expect(progress.last.committedPages, 2);
      expect(provider.otherCalls, 0);
    },
  );

  test(
    'page budget pauses and a later run resumes the persisted cursor',
    () async {
      provider.pages.addAll([
        MailSuccess(_page(inbox, 'one', uids: [1], more: true)),
        MailSuccess(_page(inbox, 'two', uids: [2], more: true)),
        MailSuccess(_page(inbox, 'three', uids: [3])),
      ]);
      final first = await run(maxPages: 1);
      expect(first.status, MailSyncRunStatus.paused);
      expect(first.committedPages, 1);
      expect(first.hasMore, isTrue);
      expect(first.lastCommittedCursor!.value, 'one');
      expect(provider.pages, hasLength(2));

      final resumed = await const MailSyncRunner().run(
        provider: provider,
        repository: repository,
        session: MailAccountSession(account),
        mailbox: inbox,
        maxPages: 2,
      );
      expect(resumed.status, MailSyncRunStatus.completed);
      expect(resumed.committedPages, 2);
      expect(resumed.upsertCount, 2);
      expect(resumed.lastCommittedCursor!.value, 'three');
      expect(provider.seenCursors, [null, 'one', 'two']);
      expect(repository.commits, 3);
      expect(repository.records, hasLength(3));
    },
  );

  test(
    'empty continuation pages still commit and consume the budget',
    () async {
      provider.pages.addAll([
        MailSuccess(_page(inbox, 'sparse-one', more: true)),
        MailSuccess(_page(inbox, 'sparse-two', more: true)),
        MailSuccess(_page(inbox, 'end')),
      ]);
      final report = await run(maxPages: 2);
      expect(report.status, MailSyncRunStatus.paused);
      expect(report.committedPages, 2);
      expect(report.upsertCount, 0);
      expect(report.tombstoneCount, 0);
      expect(report.lastCommittedCursor!.value, 'sparse-two');
      expect(provider.pages, hasLength(1));
    },
  );

  test(
    'second-page provider failure retains the first page without retry',
    () async {
      const problem = MailProblem(
        MailProblemCode.quotaExceeded,
        retryAfter: Duration(seconds: 30),
      );
      provider.pages.addAll([
        MailSuccess(_page(inbox, 'one', uids: [1], more: true)),
        const MailFailure(problem),
        MailSuccess(_page(inbox, 'two', uids: [2])),
      ]);
      final report = await run();
      expect(report.status, MailSyncRunStatus.failed);
      expect(report.problem, same(problem));
      expect(report.committedPages, 1);
      expect(report.upsertCount, 1);
      expect(report.lastCommittedCursor!.value, 'one');
      expect(report.hasMore, isTrue);
      expect(repository.records, hasLength(1));
      expect(provider.seenCursors, [null, 'one']);

      final resumed = await run();
      expect(resumed.status, MailSyncRunStatus.completed);
      expect(resumed.committedPages, 1);
      expect(provider.seenCursors, [null, 'one', 'one']);
    },
  );

  test(
    'second-page storage failure preserves data and cursor atomically',
    () async {
      provider.pages.addAll([
        MailSuccess(_page(inbox, 'one', uids: [1], more: true)),
        MailSuccess(_page(inbox, 'two', uids: [2], deleted: [1])),
      ]);
      repository.failCommitAt = 2;
      final report = await run();
      expect(report.status, MailSyncRunStatus.failed);
      expect(report.problem!.code, MailProblemCode.storageFailure);
      expect(report.committedPages, 1);
      expect(report.tombstoneCount, 0);
      expect(report.lastCommittedCursor!.value, 'one');
      expect(repository.cursor!.value, 'one');
      expect(repository.records.values.single.id.value, 'message-1');
    },
  );

  test(
    'cancelled before start never reads storage or calls the provider',
    () async {
      final source = MailCancellationSource()..cancel();
      final report = await run(cancellation: source.token);
      expect(report.status, MailSyncRunStatus.cancelled);
      expect(report.problem!.code, MailProblemCode.cancelled);
      expect(report.committedPages, 0);
      expect(report.hasMore, isNull);
      expect(repository.reads, 0);
      expect(provider.seenCursors, isEmpty);
    },
  );

  test(
    'cancellation while provider awaits prevents a late page commit',
    () async {
      final source = MailCancellationSource();
      provider.pending = Completer<MailResult<MailSyncPage>>();
      final pending = run(cancellation: source.token);
      await provider.started.future;
      source.cancel();
      provider.pending!.complete(MailSuccess(_page(inbox, 'late', uids: [1])));
      final report = await pending;
      expect(report.status, MailSyncRunStatus.cancelled);
      expect(report.problem!.code, MailProblemCode.cancelled);
      expect(report.committedPages, 0);
      expect(repository.commits, 0);
      expect(repository.cursor, isNull);
    },
  );

  test(
    'account invalidation while provider awaits prevents a late commit',
    () async {
      provider.pending = Completer<MailResult<MailSyncPage>>();
      final pending = run();
      await provider.started.future;
      session.invalidate();
      provider.pending!.complete(MailSuccess(_page(inbox, 'late', uids: [1])));
      final report = await pending;
      expect(report.status, MailSyncRunStatus.cancelled);
      expect(report.problem!.code, MailProblemCode.staleOperation);
      expect(repository.commits, 0);
    },
  );

  test(
    'cancelled raw provider failure is classified as cancellation',
    () async {
      final source = MailCancellationSource();
      provider.pending = Completer<MailResult<MailSyncPage>>();
      final pending = run(cancellation: source.token);
      await provider.started.future;
      source.cancel(MailCancellationReason.budgetExpired);
      provider.pending!.completeError(StateError('private provider details'));
      final report = await pending;
      expect(report.status, MailSyncRunStatus.cancelled);
      expect(report.problem!.code, MailProblemCode.cancelled);
      expect(repository.commits, 0);
    },
  );

  test(
    'session invalidation in progress does not start a fresh page lease',
    () async {
      provider.pages.addAll([
        MailSuccess(_page(inbox, 'one', uids: [1], more: true)),
        MailSuccess(_page(inbox, 'late', uids: [2])),
      ]);
      final report = await run(onProgress: (_) => session.invalidate());
      expect(report.status, MailSyncRunStatus.cancelled);
      expect(report.problem!.code, MailProblemCode.staleOperation);
      expect(report.committedPages, 1);
      expect(provider.seenCursors, [null]);
      expect(repository.cursor!.value, 'one');
    },
  );

  test('cancel during a storage transaction cannot commit the page', () async {
    final source = MailCancellationSource();
    provider.pages.add(MailSuccess(_page(inbox, 'late', uids: [1])));
    repository.beforeCommit = source.cancel;
    final report = await run(cancellation: source.token);
    expect(report.status, MailSyncRunStatus.cancelled);
    expect(report.committedPages, 0);
    expect(repository.commits, 0);
    expect(repository.records, isEmpty);
  });

  test(
    'cancellation after commit retains its receipt without stale progress',
    () async {
      final source = MailCancellationSource();
      provider.pages.add(MailSuccess(_page(inbox, 'end', uids: [1])));
      repository.afterCommit = source.cancel;
      final progress = <MailSyncRunProgress>[];
      final report = await run(
        cancellation: source.token,
        onProgress: progress.add,
      );
      expect(report.status, MailSyncRunStatus.cancelled);
      expect(report.problem!.code, MailProblemCode.cancelled);
      expect(report.committedPages, 1);
      expect(report.upsertCount, 1);
      expect(report.lastCommittedCursor!.value, 'end');
      expect(report.hasMore, isFalse);
      expect(repository.commits, 1);
      expect(progress, isEmpty);
    },
  );

  test('observer cancellation on the terminal page is not completed', () async {
    final source = MailCancellationSource();
    provider.pages.add(MailSuccess(_page(inbox, 'end')));
    final report = await run(
      cancellation: source.token,
      onProgress: (_) => source.cancel(),
    );
    expect(report.status, MailSyncRunStatus.cancelled);
    expect(report.committedPages, 1);
    expect(report.hasMore, isFalse);
  });

  test(
    'observer exceptions do not alter commits or stop later pages',
    () async {
      provider.pages.addAll([
        MailSuccess(_page(inbox, 'one', more: true)),
        MailSuccess(_page(inbox, 'two')),
      ]);
      var callbacks = 0;
      final report = await run(
        onProgress: (_) {
          callbacks++;
          throw StateError('private observer details');
        },
      );
      expect(report.status, MailSyncRunStatus.completed);
      expect(report.problem, isNull);
      expect(report.committedPages, 2);
      expect(callbacks, 2);
    },
  );

  test('mismatched account fails without storage or provider calls', () async {
    session = MailAccountSession(
      MailAccountId('other', profile: account.profile),
    );
    final report = await run();
    expect(report.status, MailSyncRunStatus.failed);
    expect(report.problem!.code, MailProblemCode.invalidInput);
    expect(repository.reads, 0);
    expect(provider.seenCursors, isEmpty);
  });

  test('mismatched mailbox account fails before storage access', () async {
    inbox = MailMailboxId(
      'INBOX',
      account: MailAccountId('other', profile: account.profile),
    );
    final report = await run();
    expect(report.problem!.code, MailProblemCode.invalidInput);
    expect(repository.reads, 0);
    expect(provider.seenCursors, isEmpty);
  });

  test(
    'disposed session returns stale operation before accessing storage',
    () async {
      session.dispose();
      final report = await run();
      expect(report.status, MailSyncRunStatus.cancelled);
      expect(report.problem!.code, MailProblemCode.staleOperation);
      expect(repository.reads, 0);
    },
  );

  for (final size in [-1, 0, 1001]) {
    test('invalid pageSize $size has no side effects', () async {
      final report = await run(pageSize: size);
      expect(report.status, MailSyncRunStatus.failed);
      expect(report.problem!.code, MailProblemCode.invalidInput);
      expect(repository.reads, 0);
      expect(provider.seenCursors, isEmpty);
    });
  }
  for (final pages in [-1, 0, 101]) {
    test('invalid maxPages $pages has no side effects', () async {
      final report = await run(maxPages: pages);
      expect(report.status, MailSyncRunStatus.failed);
      expect(report.problem!.code, MailProblemCode.invalidInput);
      expect(repository.reads, 0);
      expect(provider.seenCursors, isEmpty);
    });
  }

  test('maximum valid page and run bounds are accepted', () async {
    provider.pages.add(MailSuccess(_page(inbox, 'end')));
    final report = await run(pageSize: 1000, maxPages: 100);
    expect(report.status, MailSyncRunStatus.completed);
    expect(provider.limits, [1000]);
  });

  test('unchanged continuation cursor is rejected before commit', () async {
    repository.cursor = MailCursor(mailbox: inbox, value: 'initial');
    provider.pages.add(MailSuccess(_page(inbox, 'initial', more: true)));
    final report = await run();
    expect(report.status, MailSyncRunStatus.failed);
    expect(report.problem!.code, MailProblemCode.providerFailure);
    expect(report.committedPages, 0);
    expect(report.lastCommittedCursor!.value, 'initial');
    expect(report.hasMore, isNull);
    expect(repository.commitAttempts, 0);
  });

  test(
    'a cursor cycle is rejected without rolling back earlier pages',
    () async {
      repository.cursor = MailCursor(mailbox: inbox, value: 'initial');
      provider.pages.addAll([
        MailSuccess(_page(inbox, 'one', uids: [1], more: true)),
        MailSuccess(_page(inbox, 'two', uids: [2], more: true)),
        MailSuccess(_page(inbox, 'one', uids: [3], more: true)),
      ]);
      final report = await run();
      expect(report.problem!.code, MailProblemCode.providerFailure);
      expect(report.committedPages, 2);
      expect(report.lastCommittedCursor!.value, 'two');
      expect(repository.cursor!.value, 'two');
      expect(repository.records, hasLength(2));
      expect(repository.commitAttempts, 2);
    },
  );

  test('terminal page cannot rewind to an earlier cursor in the run', () async {
    repository.cursor = MailCursor(mailbox: inbox, value: 'initial');
    provider.pages.addAll([
      MailSuccess(_page(inbox, 'one', more: true)),
      MailSuccess(_page(inbox, 'initial')),
    ]);
    final report = await run();
    expect(report.status, MailSyncRunStatus.failed);
    expect(report.problem!.code, MailProblemCode.providerFailure);
    expect(report.committedPages, 1);
    expect(repository.cursor!.value, 'one');
  });

  test('unchanged terminal cursor permits a no-change poll', () async {
    repository.cursor = MailCursor(mailbox: inbox, value: 'initial');
    provider.pages.add(MailSuccess(_page(inbox, 'initial')));
    final report = await run();
    expect(report.status, MailSyncRunStatus.completed);
    expect(report.committedPages, 1);
    expect(report.upsertCount, 0);
    expect(report.hasMore, isFalse);
  });

  test(
    'a concurrently advanced cursor still fails atomic comparison',
    () async {
      repository.cursor = MailCursor(mailbox: inbox, value: 'initial');
      provider.pending = Completer<MailResult<MailSyncPage>>();
      final pending = run();
      await provider.started.future;
      repository.cursor = MailCursor(mailbox: inbox, value: 'concurrent');
      provider.pending!.complete(MailSuccess(_page(inbox, 'late', uids: [1])));
      final report = await pending;
      expect(report.status, MailSyncRunStatus.failed);
      expect(report.problem!.code, MailProblemCode.conflict);
      expect(report.committedPages, 0);
      expect(report.lastCommittedCursor!.value, 'initial');
      expect(repository.cursor!.value, 'concurrent');
      expect(repository.records, isEmpty);
    },
  );

  test(
    'cursor change between pages stops before another provider fetch',
    () async {
      provider.pages.addAll([
        MailSuccess(_page(inbox, 'one', more: true)),
        MailSuccess(_page(inbox, 'late')),
      ]);
      final report = await run(
        onProgress: (_) {
          repository.cursor = MailCursor(mailbox: inbox, value: 'concurrent');
        },
      );
      expect(report.status, MailSyncRunStatus.failed);
      expect(report.problem!.code, MailProblemCode.conflict);
      expect(report.committedPages, 1);
      expect(report.lastCommittedCursor!.value, 'one');
      expect(provider.seenCursors, [null]);
    },
  );

  test('foreign stored cursor is a typed storage failure', () async {
    repository.cursor = MailCursor(
      mailbox: MailMailboxId('OTHER', account: account),
      value: 'foreign',
    );
    final report = await run();
    expect(report.problem!.code, MailProblemCode.storageFailure);
    expect(report.lastCommittedCursor, isNull);
    expect(provider.seenCursors, isEmpty);
  });

  test('oversized provider page is rejected before persistence', () async {
    provider.pages.add(MailSuccess(_page(inbox, 'large', uids: [1, 2])));
    final report = await run(pageSize: 1);
    expect(report.problem!.code, MailProblemCode.providerFailure);
    expect(report.committedPages, 0);
    expect(repository.commitAttempts, 0);
  });

  test('wrong-mailbox provider page is rejected before persistence', () async {
    provider.pages.add(
      MailSuccess(_page(MailMailboxId('OTHER', account: account), 'wrong')),
    );
    final report = await run();
    expect(report.problem!.code, MailProblemCode.providerFailure);
    expect(report.committedPages, 0);
    expect(repository.commitAttempts, 0);
  });

  test(
    'raw provider exceptions become typed failures without raw detail',
    () async {
      provider.throwOnPull = StateError('private provider details');
      final report = await run();
      expect(report.status, MailSyncRunStatus.failed);
      expect(report.problem!.code, MailProblemCode.providerFailure);
      expect(report.problem.toString(), isNot(contains('private')));
      expect(repository.commits, 0);
    },
  );

  test('raw storage read exceptions become storage failure', () async {
    repository.throwOnRead = StateError('private storage details');
    final report = await run();
    expect(report.status, MailSyncRunStatus.failed);
    expect(report.problem!.code, MailProblemCode.storageFailure);
    expect(provider.seenCursors, isEmpty);
  });

  test('raw storage commit exceptions become storage failure', () async {
    provider.pages.add(MailSuccess(_page(inbox, 'uncommitted', uids: [1])));
    repository.throwOnCommit = StateError('private storage details');
    final report = await run();
    expect(report.status, MailSyncRunStatus.failed);
    expect(report.problem!.code, MailProblemCode.storageFailure);
    expect(report.committedPages, 0);
    expect(repository.cursor, isNull);
  });
}

MailSyncPage _page(
  MailMailboxId mailbox,
  String cursor, {
  List<int> uids = const [],
  List<int> deleted = const [],
  bool more = false,
  bool reset = false,
}) => MailSyncPage(
  mailbox: mailbox,
  upserts: [
    for (final uid in uids)
      MailHeaderRecord(
        id: MailMessageId('message-$uid'),
        remote: MailImapIdentity(mailbox: mailbox, uidValidity: 1, uid: uid),
        envelope: MailEnvelope(subject: 'Fixture $uid'),
      ),
  ],
  tombstones: [
    for (final uid in deleted)
      MailImapIdentity(mailbox: mailbox, uidValidity: 1, uid: uid),
  ],
  next: MailCursor(mailbox: mailbox, value: cursor),
  hasMore: more,
  resetRequired: reset,
);

final class _Provider implements MailProvider {
  _Provider(this.account);
  @override
  final MailAccountId account;
  final List<MailResult<MailSyncPage>> pages = [];
  final List<String?> seenCursors = [];
  final List<int> limits = [];
  final Completer<void> started = Completer<void>();
  Completer<MailResult<MailSyncPage>>? pending;
  Object? throwOnPull;
  int otherCalls = 0;

  @override
  Future<MailResult<MailSyncPage>> pullChanges(
    MailMailboxId mailbox, {
    MailCursor? cursor,
    required int limit,
    required MailOperationLease lease,
  }) async {
    lease.checkCurrent();
    seenCursors.add(cursor?.value);
    limits.add(limit);
    if (!started.isCompleted) started.complete();
    if (throwOnPull case final exception?) throw exception;
    if (pending case final response?) return response.future;
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

/// An atomic deterministic repository fixture; durable reopen is tested by the
/// storage package rather than claimed by this in-memory implementation.
final class _Repository implements MailSyncRepository {
  MailCursor? cursor;
  final Map<MailRemoteIdentity, MailHeaderRecord> records = {};
  int reads = 0;
  int commits = 0;
  int commitAttempts = 0;
  int? failCommitAt;
  Object? throwOnRead;
  Object? throwOnCommit;
  void Function()? beforeCommit;
  void Function()? afterCommit;

  @override
  Future<MailResult<MailCursor?>> readCursor(MailMailboxId mailbox) async {
    reads++;
    if (throwOnRead case final exception?) throw exception;
    return MailSuccess(cursor);
  }

  @override
  Future<MailResult<MailUnit>> commitSyncPage(
    MailSyncPage page, {
    required MailCursor? expectedCursor,
    required MailOperationLease lease,
  }) async {
    commitAttempts++;
    if (throwOnCommit case final exception?) throw exception;
    if (expectedCursor?.mailbox != cursor?.mailbox ||
        expectedCursor?.value != cursor?.value) {
      return const MailFailure(MailProblem(MailProblemCode.conflict));
    }
    final transaction = page.resetRequired
        ? <MailRemoteIdentity, MailHeaderRecord>{}
        : Map<MailRemoteIdentity, MailHeaderRecord>.of(records);
    for (final identity in page.tombstones) {
      transaction.remove(identity);
    }
    for (final record in page.upserts) {
      transaction[record.remote] = record;
    }
    beforeCommit?.call();
    lease.checkCurrent();
    if (commitAttempts == failCommitAt) {
      return const MailFailure(MailProblem(MailProblemCode.storageFailure));
    }
    records
      ..clear()
      ..addAll(transaction);
    cursor = page.next;
    commits++;
    afterCommit?.call();
    return const MailSuccess(MailUnit.value);
  }
}
