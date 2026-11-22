import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:test/test.dart';

void main() {
  late MailMailboxId mailbox;
  late MailAccountSession session;
  late _Snapshots repository;
  late _Provider provider;

  setUp(() {
    final account = MailAccountId(
      'account',
      profile: MailProfileId('profile', hostId: 'snapshot-test'),
    );
    mailbox = MailMailboxId('INBOX', account: account);
    session = MailAccountSession(account);
    repository = _Snapshots(mailbox);
    provider = _Provider(mailbox);
  });

  Future<MailResult<MailSyncPage>> pull() =>
      const MailSyncCoordinator().pullPage(
        provider: provider,
        repository: repository,
        session: session,
        mailbox: mailbox,
      );

  Future<MailSyncRunReport> run() => const MailSyncRunner().run(
    provider: provider,
    repository: repository,
    session: session,
    mailbox: mailbox,
  );

  test('a null provider cursor still retains a bounded local revision', () {
    for (final revision in [0, 1, 0x1fffffffffffff]) {
      final snapshot = MailSyncRepositorySnapshot(
        mailbox: mailbox,
        cursor: null,
        revision: revision,
      );
      expect(snapshot.mailbox, mailbox);
      expect(snapshot.cursor, isNull);
      expect(snapshot.revision, revision);
    }
    for (final revision in [-1, 0x20000000000000]) {
      expect(
        () => MailSyncRepositorySnapshot(
          mailbox: mailbox,
          cursor: null,
          revision: revision,
        ),
        throwsArgumentError,
      );
    }
  });

  test('snapshot cursor identity and optional stamp must agree', () {
    for (final cursor in [
      MailCursor(
        mailbox: MailMailboxId('Archive', account: mailbox.account),
        value: 'provider',
      ),
      MailCursor(mailbox: mailbox, value: 'provider', repositoryRevision: 2),
    ]) {
      expect(
        () => MailSyncRepositorySnapshot(
          mailbox: mailbox,
          cursor: cursor,
          revision: 1,
        ),
        throwsArgumentError,
      );
    }
    final cursor = MailCursor(mailbox: mailbox, value: 'opaque provider bytes');
    final snapshot = MailSyncRepositorySnapshot(
      mailbox: mailbox,
      cursor: cursor,
      revision: 4,
    );
    expect(snapshot.cursor, same(cursor));
    expect(snapshot.cursor!.value, 'opaque provider bytes');
  });

  test(
    'coordinator resumes first sync after local moves without a cursor',
    () async {
      repository.revision = 7;
      provider.pages.add(_page(mailbox, 'first'));
      expect(await pull(), isA<MailSuccess<MailSyncPage>>());
      expect(provider.seenCursors, [null]);
      expect(repository.snapshotReads, 1);
      expect(repository.commits, 1);
      expect(repository.expected.single.revision, 7);
      expect(repository.expected.single.cursor, isNull);
      expect(repository.expected.single, same(repository.observed.single));
      expect(repository.cursor!.value, 'first');
      expect(repository.legacyReads, 0);
      expect(repository.legacyCommits, 0);
    },
  );

  for (final existingCursor in [false, true]) {
    test(
      'move during pull rejects a stale ${existingCursor ? 'existing' : 'missing'} cursor snapshot',
      () async {
        repository.revision = 3;
        if (existingCursor) {
          repository.cursor = MailCursor(mailbox: mailbox, value: 'initial');
        }
        provider.pages.add(_page(mailbox, 'stale'));
        provider.onPull = () => repository.revision++;
        final result = await pull();
        expect(
          (result as MailFailure<MailSyncPage>).problem.code,
          MailProblemCode.conflict,
        );
        expect(repository.commits, 0);
        expect(repository.cursor?.value, existingCursor ? 'initial' : null);
        expect(repository.expected.single.revision, 3);
        expect(repository.revision, 4);

        provider.onPull = null;
        provider.pages.add(_page(mailbox, 'fresh'));
        expect(await pull(), isA<MailSuccess<MailSyncPage>>());
        expect(repository.commits, 1);
        expect(repository.expected.last.revision, 4);
        expect(repository.cursor!.value, 'fresh');
      },
    );
  }

  test('snapshot failure stops before contacting the provider', () async {
    repository.readProblem = const MailProblem(MailProblemCode.storageFailure);
    final result = await pull();
    expect(
      (result as MailFailure<MailSyncPage>).problem.code,
      MailProblemCode.storageFailure,
    );
    expect(provider.seenCursors, isEmpty);
    expect(repository.expected, isEmpty);
  });

  test('a self-consistent snapshot for another mailbox is refused', () async {
    repository.replacement = MailSyncRepositorySnapshot(
      mailbox: MailMailboxId('Other', account: mailbox.account),
      cursor: null,
      revision: 3,
    );
    final result = await pull();
    expect(
      (result as MailFailure<MailSyncPage>).problem.code,
      MailProblemCode.storageFailure,
    );
    expect(provider.seenCursors, isEmpty);
    expect(repository.expected, isEmpty);
  });

  test(
    'retiring the account during a snapshot read prevents provider work',
    () async {
      repository.onRead = session.dispose;
      final result = await pull();
      expect(
        (result as MailFailure<MailSyncPage>).problem.code,
        MailProblemCode.staleOperation,
      );
      expect(provider.seenCursors, isEmpty);
      expect(repository.expected, isEmpty);
    },
  );

  test('runner forwards exact snapshots across multiple pages', () async {
    repository.revision = 9;
    provider.pages.addAll([
      _page(mailbox, 'one', more: true),
      _page(mailbox, 'two'),
    ]);
    final report = await run();
    expect(report.status, MailSyncRunStatus.completed);
    expect(report.committedPages, 2);
    expect(report.lastCommittedCursor!.value, 'two');
    expect(provider.seenCursors, [null, 'one']);
    expect(repository.expected.map((item) => item.revision), [9, 9]);
    for (var index = 0; index < repository.expected.length; index++) {
      expect(repository.expected[index], same(repository.observed[index]));
    }
    expect(repository.legacyReads, 0);
    expect(repository.legacyCommits, 0);
  });

  test(
    'runner retains snapshot fencing when a move happens in flight',
    () async {
      repository.revision = 5;
      provider.onPull = () => repository.revision++;
      provider.pages.add(_page(mailbox, 'stale'));
      final report = await run();
      expect(report.status, MailSyncRunStatus.failed);
      expect(report.problem!.code, MailProblemCode.conflict);
      expect(report.committedPages, 0);
      expect(repository.cursor, isNull);
      expect(repository.commits, 0);
      expect(repository.expected.single.revision, 5);
    },
  );

  test(
    'runner still rejects repeated continuation cursors before commit',
    () async {
      provider.pages.addAll([
        _page(mailbox, 'same', more: true),
        _page(mailbox, 'same', more: true),
      ]);
      final report = await run();
      expect(report.status, MailSyncRunStatus.failed);
      expect(report.problem!.code, MailProblemCode.providerFailure);
      expect(report.committedPages, 1);
      expect(repository.commits, 1);
      expect(repository.expected, hasLength(1));
    },
  );

  test(
    'runner accepts an unchanged terminal cursor through the snapshot port',
    () async {
      repository.cursor = MailCursor(mailbox: mailbox, value: 'same');
      provider.pages.add(_page(mailbox, 'same'));
      final report = await run();
      expect(report.status, MailSyncRunStatus.completed);
      expect(report.committedPages, 1);
      expect(repository.commits, 1);
    },
  );

  test(
    'runner keeps a committed page when cancellation arrives afterward',
    () async {
      provider.pages.add(_page(mailbox, 'saved'));
      repository.afterCommit = session.dispose;
      final report = await run();
      expect(report.status, MailSyncRunStatus.cancelled);
      expect(report.problem!.code, MailProblemCode.staleOperation);
      expect(report.committedPages, 1);
      expect(report.lastCommittedCursor!.value, 'saved');
      expect(repository.commits, 1);
    },
  );

  for (final atRead in [true, false]) {
    test(
      'runner sanitizes a thrown snapshot ${atRead ? 'read' : 'commit'} error',
      () async {
        void fail() => throw StateError('private storage detail');
        if (atRead) {
          repository.onRead = fail;
        } else {
          repository.beforeCommit = fail;
        }
        provider.pages.add(_page(mailbox, 'saved'));
        final report = await run();
        expect(report.status, MailSyncRunStatus.failed);
        expect(report.problem!.code, MailProblemCode.storageFailure);
        expect(report.committedPages, 0);
        expect(repository.commits, 0);
      },
    );
  }
}

MailSyncPage _page(MailMailboxId mailbox, String cursor, {bool more = false}) =>
    MailSyncPage(
      mailbox: mailbox,
      upserts: const [],
      tombstones: const [],
      next: MailCursor(mailbox: mailbox, value: cursor),
      hasMore: more,
    );

final class _Snapshots implements MailSyncSnapshotRepository {
  _Snapshots(this.mailbox);
  final MailMailboxId mailbox;
  int revision = 0;
  MailCursor? cursor;
  int snapshotReads = 0;
  int legacyReads = 0;
  int legacyCommits = 0;
  int commits = 0;
  MailProblem? readProblem;
  MailSyncRepositorySnapshot? replacement;
  void Function()? onRead;
  void Function()? beforeCommit;
  void Function()? afterCommit;
  final List<MailSyncRepositorySnapshot> observed = [];
  final List<MailSyncRepositorySnapshot> expected = [];

  @override
  Future<MailResult<MailSyncRepositorySnapshot>> readSyncSnapshot(
    MailMailboxId requested,
  ) async {
    snapshotReads++;
    onRead?.call();
    if (readProblem case final problem?) return MailFailure(problem);
    final snapshot =
        replacement ??
        MailSyncRepositorySnapshot(
          mailbox: requested,
          cursor: cursor == null
              ? null
              : MailCursor(
                  mailbox: cursor!.mailbox,
                  value: cursor!.value,
                  repositoryRevision: revision,
                ),
          revision: revision,
        );
    observed.add(snapshot);
    return MailSuccess(snapshot);
  }

  @override
  Future<MailResult<MailUnit>> commitSyncPageWithSnapshot(
    MailSyncPage page, {
    required MailSyncRepositorySnapshot expectedSnapshot,
    required MailOperationLease lease,
  }) async {
    expected.add(expectedSnapshot);
    beforeCommit?.call();
    lease.checkCurrent();
    if (page.mailbox != mailbox ||
        expectedSnapshot.mailbox != mailbox ||
        expectedSnapshot.revision != revision ||
        expectedSnapshot.cursor?.value != cursor?.value) {
      return const MailFailure(MailProblem(MailProblemCode.conflict));
    }
    cursor = page.next;
    commits++;
    afterCommit?.call();
    return const MailSuccess(MailUnit.value);
  }

  @override
  Future<MailResult<MailCursor?>> readCursor(MailMailboxId mailbox) async {
    legacyReads++;
    return const MailFailure(MailProblem(MailProblemCode.unsupported));
  }

  @override
  Future<MailResult<MailUnit>> commitSyncPage(
    MailSyncPage page, {
    required MailCursor? expectedCursor,
    required MailOperationLease lease,
  }) async {
    legacyCommits++;
    return const MailFailure(MailProblem(MailProblemCode.unsupported));
  }
}

final class _Provider implements MailProvider {
  _Provider(this.mailbox);
  final MailMailboxId mailbox;
  @override
  MailAccountId get account => mailbox.account;
  final List<MailSyncPage> pages = [];
  final List<String?> seenCursors = [];
  void Function()? onPull;

  @override
  Future<MailResult<MailSyncPage>> pullChanges(
    MailMailboxId mailbox, {
    MailCursor? cursor,
    required int limit,
    required MailOperationLease lease,
  }) async {
    lease.checkCurrent();
    seenCursors.add(cursor?.value);
    onPull?.call();
    return MailSuccess(pages.removeAt(0));
  }

  @override
  Future<MailResult<MailCapabilities>> capabilities(
    MailOperationLease lease,
  ) async => const MailFailure(MailProblem(MailProblemCode.unsupported));
  @override
  Future<MailResult<List<MailMailbox>>> listMailboxes(
    MailOperationLease lease,
  ) async => const MailFailure(MailProblem(MailProblemCode.unsupported));
  @override
  Future<MailResult<MailHeaderPage>> fetchHeaders(
    MailMailboxId mailbox, {
    MailCursor? cursor,
    required int limit,
    required MailOperationLease lease,
  }) async => const MailFailure(MailProblem(MailProblemCode.unsupported));
  @override
  Future<MailResult<MailMessage>> fetchMessage(
    MailRemoteIdentity identity, {
    required MailReadBudget budget,
    required MailOperationLease lease,
  }) async => const MailFailure(MailProblem(MailProblemCode.unsupported));
  @override
  Future<MailResult<MailUnit>> apply(
    MailOperation operation,
    MailOperationLease lease,
  ) async => const MailFailure(MailProblem(MailProblemCode.unsupported));
}
