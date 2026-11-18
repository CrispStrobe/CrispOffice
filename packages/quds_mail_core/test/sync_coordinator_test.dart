import 'dart:async';

import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:test/test.dart';

void main() {
  late MailAccountId account;
  late MailMailboxId inbox;
  late MailAccountSession session;
  late _FixtureProvider provider;
  late _MemorySyncRepository repository;
  const coordinator = MailSyncCoordinator();

  setUp(() {
    account = MailAccountId('a', profile: MailProfileId('p', hostId: 'office'));
    inbox = MailMailboxId('INBOX', account: account);
    session = MailAccountSession(account);
    provider = _FixtureProvider(account, inbox);
    repository = _MemorySyncRepository();
  });

  test(
    'fixture pages apply real upserts/tombstones and advance cursor atomically',
    () async {
      provider.pages.addAll([
        _page(inbox, 'page-1', uids: [1, 2], more: true),
        _page(inbox, 'page-2', uids: [3], deleted: [1]),
      ]);
      final first = await coordinator.pullPage(
        provider: provider,
        repository: repository,
        session: session,
        mailbox: inbox,
      );
      expect(first, isA<MailSuccess<MailSyncPage>>());
      expect(repository.records.values.map((r) => r.id.value), [
        'message-1',
        'message-2',
      ]);
      expect(repository.cursor!.value, 'page-1');
      final second = await coordinator.pullPage(
        provider: provider,
        repository: repository,
        session: session,
        mailbox: inbox,
      );
      expect(second, isA<MailSuccess<MailSyncPage>>());
      expect(repository.records.values.map((r) => r.id.value), [
        'message-2',
        'message-3',
      ]);
      expect(repository.cursor!.value, 'page-2');
      expect(provider.seenCursors, [null, 'page-1']);
    },
  );

  test(
    'transaction failure leaves both old content and cursor unchanged',
    () async {
      provider.pages.addAll([
        _page(inbox, 'initial', uids: [1]),
        _page(inbox, 'next', uids: [2]),
      ]);
      await coordinator.pullPage(
        provider: provider,
        repository: repository,
        session: session,
        mailbox: inbox,
      );
      repository.failCommit = true;
      final failure = await coordinator.pullPage(
        provider: provider,
        repository: repository,
        session: session,
        mailbox: inbox,
      );
      expect(
        (failure as MailFailure<MailSyncPage>).problem.code,
        MailProblemCode.storageFailure,
      );
      expect(repository.cursor!.value, 'initial');
      expect(repository.records.values.single.id.value, 'message-1');
    },
  );

  test('account disposal while provider awaits prevents any commit', () async {
    provider.delay = Completer<MailResult<MailSyncPage>>();
    final future = coordinator.pullPage(
      provider: provider,
      repository: repository,
      session: session,
      mailbox: inbox,
    );
    await provider.started.future;
    session.dispose();
    provider.delay!.complete(MailSuccess(_page(inbox, 'late', uids: [1])));
    final result = await future;
    expect(
      (result as MailFailure<MailSyncPage>).problem.code,
      MailProblemCode.staleOperation,
    );
    expect(repository.cursor, isNull);
    expect(repository.records, isEmpty);
    expect(repository.commits, 0);
  });

  test(
    'transaction rechecks the lease when disposal happens during persistence',
    () async {
      provider.pages.add(_page(inbox, 'late', uids: [1]));
      repository.beforeCommit = session.dispose;
      final result = await coordinator.pullPage(
        provider: provider,
        repository: repository,
        session: session,
        mailbox: inbox,
      );
      expect(
        (result as MailFailure<MailSyncPage>).problem.code,
        MailProblemCode.staleOperation,
      );
      expect(repository.cursor, isNull);
      expect(repository.records, isEmpty);
    },
  );

  test(
    'cooperative user cancellation differs from stale account work',
    () async {
      final cancellation = MailCancellationSource();
      cancellation.cancel();
      final result = await coordinator.pullPage(
        provider: provider,
        repository: repository,
        session: session,
        mailbox: inbox,
        cancellation: cancellation.token,
      );
      expect(
        (result as MailFailure<MailSyncPage>).problem.code,
        MailProblemCode.cancelled,
      );
      expect(provider.seenCursors, isEmpty);
    },
  );

  test(
    'wrong account and oversized provider page fail before persistence',
    () async {
      final other = MailAccountId('other', profile: account.profile);
      final wrong = await coordinator.pullPage(
        provider: provider,
        repository: repository,
        session: MailAccountSession(other),
        mailbox: inbox,
      );
      expect(
        (wrong as MailFailure<MailSyncPage>).problem.code,
        MailProblemCode.invalidInput,
      );
      provider.pages.add(_page(inbox, 'too-many', uids: [1, 2]));
      final large = await coordinator.pullPage(
        provider: provider,
        repository: repository,
        session: session,
        mailbox: inbox,
        limit: 1,
      );
      expect(
        (large as MailFailure<MailSyncPage>).problem.code,
        MailProblemCode.providerFailure,
      );
      expect(repository.commits, 0);
    },
  );

  test(
    'unsupported provider operations are failures rather than empty success',
    () async {
      final result = await provider.apply(
        MailSetRead(
          id: 'read',
          message: MailImapIdentity(mailbox: inbox, uidValidity: 1, uid: 1),
          read: true,
        ),
        session.begin(),
      );
      expect(
        (result as MailFailure<MailUnit>).problem.code,
        MailProblemCode.unsupported,
      );
    },
  );
}

MailSyncPage _page(
  MailMailboxId mailbox,
  String cursor, {
  List<int> uids = const [],
  List<int> deleted = const [],
  bool more = false,
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
);

final class _FixtureProvider implements MailProvider {
  _FixtureProvider(this.account, this.mailbox);
  @override
  final MailAccountId account;
  final MailMailboxId mailbox;
  final List<MailSyncPage> pages = [];
  final List<String?> seenCursors = [];
  final Completer<void> started = Completer<void>();
  Completer<MailResult<MailSyncPage>>? delay;

  @override
  Future<MailResult<MailSyncPage>> pullChanges(
    MailMailboxId mailbox, {
    MailCursor? cursor,
    required int limit,
    required MailOperationLease lease,
  }) async {
    lease.checkCurrent();
    seenCursors.add(cursor?.value);
    if (!started.isCompleted) started.complete();
    final pending = delay;
    if (pending != null) return pending.future;
    if (pages.isEmpty) {
      return const MailFailure(MailProblem(MailProblemCode.unavailable));
    }
    return MailSuccess(pages.removeAt(0));
  }

  @override
  Future<MailResult<MailCapabilities>> capabilities(
    MailOperationLease lease,
  ) async => MailSuccess(
    MailCapabilities([MailCapability.mail, MailCapability.folders]),
  );
  @override
  Future<MailResult<List<MailMailbox>>> listMailboxes(
    MailOperationLease lease,
  ) async => MailSuccess([MailMailbox(id: mailbox, displayName: 'Inbox')]);
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

/// A deterministic transaction fixture, not a production durable repository.
final class _MemorySyncRepository implements MailSyncRepository {
  MailCursor? cursor;
  final Map<MailRemoteIdentity, MailHeaderRecord> records = {};
  bool failCommit = false;
  int commits = 0;
  void Function()? beforeCommit;

  @override
  Future<MailResult<MailCursor?>> readCursor(MailMailboxId mailbox) async =>
      MailSuccess(cursor);
  @override
  Future<MailResult<MailUnit>> commitSyncPage(
    MailSyncPage page, {
    required MailOperationLease lease,
  }) async {
    final transaction = Map<MailRemoteIdentity, MailHeaderRecord>.of(records);
    for (final tombstone in page.tombstones) {
      transaction.remove(tombstone);
    }
    for (final record in page.upserts) {
      transaction[record.remote] = record;
    }
    beforeCommit?.call();
    lease.checkCurrent();
    if (failCommit) {
      return const MailFailure(MailProblem(MailProblemCode.storageFailure));
    }
    records
      ..clear()
      ..addAll(transaction);
    cursor = page.next;
    commits++;
    return const MailSuccess(MailUnit.value);
  }
}
