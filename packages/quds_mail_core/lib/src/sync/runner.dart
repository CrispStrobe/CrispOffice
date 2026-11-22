import '../model/identity.dart';
import '../model/result.dart';
import '../ports/provider.dart';
import '../ports/repository.dart';
import 'cancellation.dart';
import 'coordinator.dart';

/// Why a bounded, foreground synchronization run stopped.
enum MailSyncRunStatus {
  /// The provider's terminal page was committed while the run remained current.
  completed,

  /// The page budget was exhausted; another explicit run may resume the cursor.
  paused,

  /// The caller cancelled or the account session was invalidated or disposed.
  cancelled,

  /// A provider, storage, input or concurrency problem stopped the run.
  failed,
}

/// An immutable receipt for the pages acknowledged by the repository.
///
/// Counts describe page payloads, not distinct messages or net changes. An IMAP
/// authoritative range may reconcile memberships without explicit tombstones.
final class MailSyncRunProgress {
  const MailSyncRunProgress({
    required this.mailbox,
    required this.committedPages,
    required this.upsertCount,
    required this.tombstoneCount,
    required this.resetCount,
    required this.lastCommittedCursor,
    required this.hasMore,
  });

  final MailMailboxId mailbox;
  final int committedPages;
  final int upsertCount;
  final int tombstoneCount;
  final int resetCount;

  /// Last cursor acknowledged in this run, or the initial persisted cursor.
  /// Null means no persisted cursor was successfully observed.
  final MailCursor? lastCommittedCursor;

  /// The last acknowledged page's continuation flag. Null means this run has
  /// not committed a page; the cursor alone does not establish completion.
  final bool? hasMore;
}

/// The outcome of one explicitly requested run, including partial progress.
///
/// A cancelled report can contain committed pages: cancellation after an atomic
/// commit does not undo it. [problem] distinguishes cancellation from stale
/// account work. Raw provider and storage exceptions are never retained.
final class MailSyncRunReport {
  const MailSyncRunReport({
    required this.status,
    required this.progress,
    this.problem,
  });

  final MailSyncRunStatus status;
  final MailSyncRunProgress progress;
  final MailProblem? problem;

  MailMailboxId get mailbox => progress.mailbox;
  int get committedPages => progress.committedPages;
  int get upsertCount => progress.upsertCount;
  int get tombstoneCount => progress.tombstoneCount;
  int get resetCount => progress.resetCount;
  MailCursor? get lastCommittedCursor => progress.lastCommittedCursor;
  bool? get hasMore => progress.hasMore;
}

/// Pulls and atomically commits a bounded sequence of provider pages.
///
/// Every page uses [MailSyncCoordinator] and its repository cursor comparison.
/// Each run reads the persisted cursor, so an explicit later run resumes after
/// all previously acknowledged pages. No retries, polling, sending or provider
/// mutations are performed. Empty continuation pages consume the page budget.
///
/// A single session lease spans the whole run. Repeated continuation cursors
/// are rejected before persistence; an unchanged terminal cursor is valid for
/// a no-change poll. The repository must honor its atomic commit and in-
/// transaction lease-check contract, including when cancellation occurs while
/// persistence is awaiting completion.
final class MailSyncRunner {
  const MailSyncRunner();

  /// [pageSize] is 1..1000 and [maxPages] is 1..100. Invalid bounds fail without
  /// contacting the provider or repository.
  ///
  /// [onProgress] is a synchronous observer called after an acknowledged page,
  /// while the account is still current. Exceptions from it are ignored so an
  /// observer cannot change a committed page's outcome. Cancellation or session
  /// invalidation performed by the observer stops further work. Snapshots stay
  /// unchanged as the run advances. Hosts must also scope their own UI updates.
  Future<MailSyncRunReport> run({
    required MailProvider provider,
    required MailSyncRepository repository,
    required MailAccountSession session,
    required MailMailboxId mailbox,
    int pageSize = 100,
    int maxPages = 10,
    MailCancellationToken? cancellation,
    void Function(MailSyncRunProgress)? onProgress,
  }) async {
    final state = _SyncRunState(mailbox);
    if (pageSize < 1 || pageSize > 1000 || maxPages < 1 || maxPages > 100) {
      return state.failure(const MailProblem(MailProblemCode.invalidInput));
    }
    MailOperationLease? activeLease;
    try {
      if (provider.account != session.account ||
          mailbox.account != session.account) {
        return state.failure(const MailProblem(MailProblemCode.invalidInput));
      }
      final runLease = session.begin(cancellation: cancellation);
      activeLease = runLease;
      final guardedRepository = _RunRepository(repository, runLease, state);
      const coordinator = MailSyncCoordinator();
      for (var pageIndex = 0; pageIndex < maxPages; pageIndex++) {
        runLease.checkCurrent();
        final result = await coordinator.pullPage(
          provider: provider,
          repository: guardedRepository,
          session: session,
          mailbox: mailbox,
          limit: pageSize,
          cancellation: cancellation,
        );
        runLease.checkCurrent();
        if (result case MailFailure<MailSyncPage>(:final problem)) {
          return state.failure(problem);
        }
        final page = (result as MailSuccess<MailSyncPage>).value;
        if (onProgress != null) {
          try {
            onProgress(state.snapshot());
          } on Object {
            // Observer failures do not turn an acknowledged commit into failure.
          }
        }
        runLease.checkCurrent();
        if (!page.hasMore) return state.report(MailSyncRunStatus.completed);
      }
      return state.report(MailSyncRunStatus.paused);
    } on MailCancelled catch (cancelled) {
      return state.failure(_cancellationProblem(cancelled));
    } on Object {
      // Storage exceptions are contained by _RunRepository. The remaining
      // external boundary is the provider, including its account getter.
      try {
        activeLease?.checkCurrent();
      } on MailCancelled catch (cancelled) {
        return state.failure(_cancellationProblem(cancelled));
      }
      return state.failure(const MailProblem(MailProblemCode.providerFailure));
    }
  }
}

MailProblem _cancellationProblem(MailCancelled cancelled) => MailProblem(
  cancelled.reason == MailCancellationReason.user ||
          cancelled.reason == MailCancellationReason.budgetExpired
      ? MailProblemCode.cancelled
      : MailProblemCode.staleOperation,
);

final class _SyncRunState {
  _SyncRunState(this.mailbox);

  final MailMailboxId mailbox;
  int committedPages = 0;
  int upsertCount = 0;
  int tombstoneCount = 0;
  int resetCount = 0;
  MailCursor? cursor;
  bool? hasMore;
  bool cursorWasRead = false;
  final Set<String> seenCursors = {};

  MailSyncRunProgress snapshot() => MailSyncRunProgress(
    mailbox: mailbox,
    committedPages: committedPages,
    upsertCount: upsertCount,
    tombstoneCount: tombstoneCount,
    resetCount: resetCount,
    lastCommittedCursor: cursor,
    hasMore: hasMore,
  );

  MailSyncRunReport report(MailSyncRunStatus status, {MailProblem? problem}) =>
      MailSyncRunReport(status: status, progress: snapshot(), problem: problem);

  MailSyncRunReport failure(MailProblem problem) => report(
    problem.code == MailProblemCode.cancelled ||
            problem.code == MailProblemCode.staleOperation
        ? MailSyncRunStatus.cancelled
        : MailSyncRunStatus.failed,
    problem: problem,
  );

  void acknowledge(MailSyncPage page) {
    committedPages++;
    upsertCount += page.upserts.length;
    tombstoneCount += page.tombstones.length;
    if (page.resetRequired) resetCount++;
    cursor = page.next;
    hasMore = page.hasMore;
    seenCursors.add(page.next.value);
  }
}

/// Adds run-wide scope and cursor guards without replacing the coordinator's
/// per-page compare-and-swap or the repository's own atomic transaction.
final class _RunRepository implements MailSyncSnapshotRepository {
  _RunRepository(this.delegate, this.runLease, this.state);

  final MailSyncRepository delegate;
  final MailOperationLease runLease;
  final _SyncRunState state;

  MailProblem? _observeCursor(MailMailboxId mailbox, MailCursor? value) {
    if (value != null && value.mailbox != mailbox) {
      return const MailProblem(MailProblemCode.storageFailure);
    }
    if (state.cursorWasRead &&
        (value?.mailbox != state.cursor?.mailbox ||
            value?.value != state.cursor?.value)) {
      return const MailProblem(MailProblemCode.conflict);
    }
    state.cursorWasRead = true;
    state.cursor = value;
    if (value != null) state.seenCursors.add(value.value);
    return null;
  }

  @override
  Future<MailResult<MailCursor?>> readCursor(MailMailboxId mailbox) async {
    try {
      runLease.checkCurrent();
      final result = await delegate.readCursor(mailbox);
      runLease.checkCurrent();
      if (result case MailSuccess<MailCursor?>(:final value)) {
        final problem = _observeCursor(mailbox, value);
        if (problem != null) return MailFailure(problem);
      }
      return result;
    } on MailCancelled {
      rethrow;
    } on Object {
      return const MailFailure(MailProblem(MailProblemCode.storageFailure));
    }
  }

  @override
  Future<MailResult<MailSyncRepositorySnapshot>> readSyncSnapshot(
    MailMailboxId mailbox,
  ) async {
    try {
      runLease.checkCurrent();
      final repository = delegate;
      if (repository is! MailSyncSnapshotRepository) {
        return switch (await readCursor(mailbox)) {
          MailFailure<MailCursor?>(:final problem) => MailFailure(problem),
          MailSuccess<MailCursor?>(:final value) => MailSuccess(
            MailSyncRepositorySnapshot(
              mailbox: mailbox,
              cursor: value,
              revision: value?.repositoryRevision ?? 0,
            ),
          ),
        };
      }
      final result = await repository.readSyncSnapshot(mailbox);
      runLease.checkCurrent();
      if (result case MailSuccess<MailSyncRepositorySnapshot>(:final value)) {
        if (value.mailbox != mailbox) {
          return const MailFailure(MailProblem(MailProblemCode.storageFailure));
        }
        final problem = _observeCursor(mailbox, value.cursor);
        if (problem != null) return MailFailure(problem);
      }
      return result;
    } on MailCancelled {
      rethrow;
    } on Object {
      return const MailFailure(MailProblem(MailProblemCode.storageFailure));
    }
  }

  @override
  Future<MailResult<MailUnit>> commitSyncPage(
    MailSyncPage page, {
    required MailCursor? expectedCursor,
    required MailOperationLease lease,
  }) => _commitPage(
    page,
    expectedCursor: expectedCursor,
    lease: lease,
    commit: () => delegate.commitSyncPage(
      page,
      expectedCursor: expectedCursor,
      lease: lease,
    ),
  );

  @override
  Future<MailResult<MailUnit>> commitSyncPageWithSnapshot(
    MailSyncPage page, {
    required MailSyncRepositorySnapshot expectedSnapshot,
    required MailOperationLease lease,
  }) {
    if (expectedSnapshot.mailbox != page.mailbox) {
      return Future.value(
        const MailFailure(MailProblem(MailProblemCode.invalidInput)),
      );
    }
    final repository = delegate;
    return _commitPage(
      page,
      expectedCursor: expectedSnapshot.cursor,
      lease: lease,
      commit: () => repository is MailSyncSnapshotRepository
          ? repository.commitSyncPageWithSnapshot(
              page,
              expectedSnapshot: expectedSnapshot,
              lease: lease,
            )
          : repository.commitSyncPage(
              page,
              expectedCursor: expectedSnapshot.cursor,
              lease: lease,
            ),
    );
  }

  Future<MailResult<MailUnit>> _commitPage(
    MailSyncPage page, {
    required MailCursor? expectedCursor,
    required MailOperationLease lease,
    required Future<MailResult<MailUnit>> Function() commit,
  }) async {
    try {
      runLease.checkCurrent();
      lease.checkCurrent();
      final repeatsCursor = state.seenCursors.contains(page.next.value);
      final unchangedTerminal =
          !page.hasMore && page.next.value == expectedCursor?.value;
      if (repeatsCursor && !unchangedTerminal) {
        return const MailFailure(MailProblem(MailProblemCode.providerFailure));
      }
      final result = await commit();
      if (result is MailSuccess<MailUnit>) {
        // Keep the acknowledged receipt even if cancellation arrived after the
        // repository's atomic commit but before this continuation resumed.
        state.acknowledge(page);
      }
      return result;
    } on MailCancelled {
      rethrow;
    } on Object {
      return const MailFailure(MailProblem(MailProblemCode.storageFailure));
    }
  }
}
