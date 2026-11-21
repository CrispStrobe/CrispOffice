import '../model/identity.dart';
import '../model/message.dart';
import '../model/parse.dart';
import '../model/result.dart';
import '../ports/provider.dart';
import 'cancellation.dart';

/// Owned storage for complete raw/body/attachment snapshots.
///
/// A non-null [load] result means the complete snapshot is locally retained,
/// not merely a header or a partially downloaded body. [save] must atomically
/// retain all three payloads under [MailHeaderRecord.id], check the supplied
/// lease inside the transaction, and preserve drafts, Outbox and sync cursors.
/// Only an acknowledged successful transaction may return success.
abstract interface class MailBodyDownloadCache {
  MailAccountId get account;

  Future<MailResult<MailMessage?>> load(MailHeaderRecord header);

  Future<MailResult<MailUnit>> save(
    MailHeaderRecord header,
    MailMessage message, {
    required MailOperationLease lease,
  });
}

enum MailBodyDownloadStatus {
  /// Every frozen input identity has a retained complete snapshot.
  completed,

  /// A run budget was reached. Another explicit run can skip saved snapshots.
  paused,

  /// Cancellation or a retired account/folder stopped further work.
  cancelled,

  /// Input, provider, storage or quota failure stopped further work.
  failed,
}

/// Content-free immutable progress for one explicit download request.
final class MailBodyDownloadProgress {
  const MailBodyDownloadProgress({
    required this.mailbox,
    required this.total,
    required this.downloaded,
    required this.alreadyCached,
    required this.retainedBytes,
  });

  final MailMailboxId mailbox;
  final int total;
  final int downloaded;
  final int alreadyCached;

  /// Payload bytes acknowledged as newly retained in this run: original raw
  /// bytes, selected plain/HTML UTF-8 text and decoded attachment contents.
  /// Existing cache hits and metadata/database overhead are excluded.
  final int retainedBytes;

  int get processed => downloaded + alreadyCached;
  int get remaining => total - processed;
}

/// A cancelled/failed receipt still retains every acknowledged successful save.
final class MailBodyDownloadReport {
  const MailBodyDownloadReport({
    required this.status,
    required this.progress,
    this.problem,
  });

  final MailBodyDownloadStatus status;
  final MailBodyDownloadProgress progress;
  final MailProblem? problem;

  MailMailboxId get mailbox => progress.mailbox;
  int get total => progress.total;
  int get downloaded => progress.downloaded;
  int get alreadyCached => progress.alreadyCached;
  int get retainedBytes => progress.retainedBytes;
  int get processed => progress.processed;
  int get remaining => progress.remaining;
}

/// Explicit, sequential and bounded retention of synchronized message bodies.
///
/// No automatic retry, mutation, submission or cursor advancement occurs.
/// One account lease spans the whole run. Provider identities are validated
/// before their local IDs are rebound to the frozen canonical header IDs.
/// Repeating an interrupted request skips complete snapshots already in cache.
final class MailBodyDownloadRunner {
  MailBodyDownloadRunner({
    required this.provider,
    required this.cache,
    required this.session,
    this.budget = const MailReadBudget(),
    this.maxMessages = 100,
    this.maxRetainedBytes = 64 * 1024 * 1024,
  });

  final MailProvider provider;
  final MailBodyDownloadCache cache;
  final MailAccountSession session;
  final MailReadBudget budget;

  /// Maximum newly fetched messages per run, in 1..100. Cache hits do not
  /// consume this allowance, so a later run can progress past saved messages.
  final int maxMessages;

  /// Maximum newly retained payload in 1..256 MiB. The default 64 MiB permits
  /// one maximum default raw+decoded message while keeping foreground work
  /// bounded. Storage metadata and database quota remain the cache's concern.
  final int maxRetainedBytes;
  bool _running = false;

  /// [headers] contains at most 100 distinct local and remote identities from
  /// this mailbox. Its order and identities are frozen before any awaited work.
  /// An empty selection completes without contacting the provider or cache.
  ///
  /// [isCurrent] can additionally retire a host folder/view. False or a thrown
  /// exception cancels the run. It cannot restore an invalidated lease. Hosts
  /// must invalidate their session when retiring authority during a save.
  /// [onProgress] is an observer: exceptions are ignored; cancellation or
  /// session retirement from it still stops subsequent work. It is not called
  /// after cancellation, including after an acknowledged in-flight save.
  Future<MailBodyDownloadReport> run({
    required MailMailboxId mailbox,
    required List<MailHeaderRecord> headers,
    MailCancellationToken? cancellation,
    void Function(MailBodyDownloadProgress)? onProgress,
    bool Function()? isCurrent,
  }) async {
    final state = _DownloadState(mailbox, headers.length);
    if (_running) {
      return state.failure(const MailProblem(MailProblemCode.conflict));
    }
    if (headers.length > 100 ||
        maxMessages < 1 ||
        maxMessages > 100 ||
        maxRetainedBytes < 1 ||
        maxRetainedBytes > 256 * 1024 * 1024) {
      return state.failure(const MailProblem(MailProblemCode.invalidInput));
    }
    try {
      budget.validate();
    } on ArgumentError {
      return state.failure(const MailProblem(MailProblemCode.invalidInput));
    }
    final frozen = List<MailHeaderRecord>.unmodifiable(headers);
    final ids = <MailMessageId>{};
    final remotes = <MailRemoteIdentity>{};
    MailProviderKind? kind;
    int? uidValidity;
    for (final header in frozen) {
      final remote = header.remote;
      if (remote.account != mailbox.account ||
          !ids.add(header.id) ||
          !remotes.add(remote) ||
          (kind != null && remote.provider != kind)) {
        return state.failure(const MailProblem(MailProblemCode.invalidInput));
      }
      kind = remote.provider;
      if (remote is MailImapIdentity) {
        if (remote.mailbox != mailbox ||
            (uidValidity != null && remote.uidValidity != uidValidity)) {
          return state.failure(const MailProblem(MailProblemCode.invalidInput));
        }
        uidValidity = remote.uidValidity;
      }
    }

    _running = true;
    MailOperationLease? activeLease;
    try {
      if (provider.account != session.account ||
          cache.account != session.account ||
          mailbox.account != session.account) {
        return state.failure(const MailProblem(MailProblemCode.invalidInput));
      }
      final lease = session.begin(cancellation: cancellation);
      activeLease = lease;
      final scope = _DownloadScope(
        provider: provider,
        cache: cache,
        account: mailbox.account,
        lease: lease,
        isCurrent: isCurrent,
      );
      scope.check();
      for (final header in frozen) {
        scope.check();
        final cachedResult = await _load(header);
        scope.check();
        if (cachedResult case MailFailure<MailMessage?>(:final problem)) {
          return state.failure(problem);
        }
        final cached = (cachedResult as MailSuccess<MailMessage?>).value;
        if (cached != null) {
          if (cached.remoteIdentity != header.remote ||
              cached.localId != header.id ||
              cached.raw.length == 0) {
            return state.failure(
              const MailProblem(MailProblemCode.storageFailure),
            );
          }
          state.alreadyCached++;
        } else {
          if (state.downloaded >= maxMessages ||
              state.retainedBytes >= maxRetainedBytes) {
            return state.report(MailBodyDownloadStatus.paused);
          }
          scope.check();
          final fetchedResult = await provider.fetchMessage(
            header.remote,
            budget: budget,
            lease: lease,
          );
          scope.check();
          if (fetchedResult case MailFailure<MailMessage>(:final problem)) {
            return state.failure(problem);
          }
          final fetched = (fetchedResult as MailSuccess<MailMessage>).value;
          if (fetched.remoteIdentity != header.remote ||
              fetched.raw.length == 0) {
            return state.failure(
              const MailProblem(MailProblemCode.providerFailure),
            );
          }
          final bytes = _retainedPayloadBytes(fetched, budget);
          if (bytes == null || bytes > maxRetainedBytes) {
            return state.failure(
              const MailProblem(MailProblemCode.quotaExceeded),
            );
          }
          if (bytes > maxRetainedBytes - state.retainedBytes) {
            return state.report(MailBodyDownloadStatus.paused);
          }
          final canonical = MailMessage(
            raw: fetched.raw,
            envelope: fetched.envelope,
            body: fetched.body,
            attachments: fetched.attachments,
            localId: header.id,
            remoteIdentity: header.remote,
          );
          scope.check();
          final saved = await _save(header, canonical, lease);
          if (saved is MailSuccess<MailUnit>) {
            // A cancellation after the atomic commit cannot undo its receipt.
            state.downloaded++;
            state.retainedBytes += bytes;
          }
          scope.check();
          if (saved case MailFailure<MailUnit>(:final problem)) {
            return state.failure(problem);
          }
        }
        scope.check();
        try {
          onProgress?.call(state.snapshot());
        } on Object {
          // UI observers cannot change an acknowledged storage outcome.
        }
        scope.check();
      }
      return state.report(MailBodyDownloadStatus.completed);
    } on MailCancelled catch (cancelled) {
      return state.failure(_cancelledProblem(cancelled));
    } on Object {
      // Cache boundaries contain their own exceptions. No raw provider or
      // host exception (which might contain content) is retained in reports.
      try {
        activeLease?.checkCurrent();
      } on MailCancelled catch (cancelled) {
        return state.failure(_cancelledProblem(cancelled));
      }
      return state.failure(const MailProblem(MailProblemCode.providerFailure));
    } finally {
      _running = false;
    }
  }

  Future<MailResult<MailMessage?>> _load(MailHeaderRecord header) async {
    try {
      return await cache.load(header);
    } on MailCancelled {
      rethrow;
    } on Object {
      return const MailFailure(MailProblem(MailProblemCode.storageFailure));
    }
  }

  Future<MailResult<MailUnit>> _save(
    MailHeaderRecord header,
    MailMessage message,
    MailOperationLease lease,
  ) async {
    try {
      return await cache.save(header, message, lease: lease);
    } on MailCancelled {
      rethrow;
    } on Object {
      return const MailFailure(MailProblem(MailProblemCode.storageFailure));
    }
  }
}

MailProblem _cancelledProblem(MailCancelled cancelled) => MailProblem(
  cancelled.reason == MailCancellationReason.user ||
          cancelled.reason == MailCancellationReason.budgetExpired
      ? MailProblemCode.cancelled
      : MailProblemCode.staleOperation,
);

final class _DownloadScope {
  const _DownloadScope({
    required this.provider,
    required this.cache,
    required this.account,
    required this.lease,
    required this.isCurrent,
  });

  final MailProvider provider;
  final MailBodyDownloadCache cache;
  final MailAccountId account;
  final MailOperationLease lease;
  final bool Function()? isCurrent;

  void check() {
    lease.checkCurrent();
    var current = false;
    try {
      current = isCurrent?.call() ?? true;
    } on Object {
      throw const MailCancelled(MailCancellationReason.accountChanged);
    }
    if (!current || provider.account != account || cache.account != account) {
      throw const MailCancelled(MailCancellationReason.accountChanged);
    }
    // A host callback returning true must not revive a lease it just retired.
    lease.checkCurrent();
  }
}

final class _DownloadState {
  _DownloadState(this.mailbox, this.total);

  final MailMailboxId mailbox;
  final int total;
  int downloaded = 0;
  int alreadyCached = 0;
  int retainedBytes = 0;

  MailBodyDownloadProgress snapshot() => MailBodyDownloadProgress(
    mailbox: mailbox,
    total: total,
    downloaded: downloaded,
    alreadyCached: alreadyCached,
    retainedBytes: retainedBytes,
  );

  MailBodyDownloadReport report(
    MailBodyDownloadStatus status, {
    MailProblem? problem,
  }) => MailBodyDownloadReport(
    status: status,
    progress: snapshot(),
    problem: problem,
  );

  MailBodyDownloadReport failure(MailProblem problem) => report(
    problem.code == MailProblemCode.cancelled ||
            problem.code == MailProblemCode.staleOperation
        ? MailBodyDownloadStatus.cancelled
        : MailBodyDownloadStatus.failed,
    problem: problem,
  );
}

/// Measure actual retained bytes without allocating another encoded body.
/// MIME part/header/nesting limits still belong to the provider's codec.
int? _retainedPayloadBytes(MailMessage message, MailReadBudget budget) {
  if (message.raw.length > budget.maxRawBytes ||
      message.attachments.length > budget.maxAttachments) {
    return null;
  }
  final bodyLimit = budget.maxBodyBytes < budget.maxRenderTextBytes
      ? budget.maxBodyBytes
      : budget.maxRenderTextBytes;
  var bodyBytes = 0;
  for (final text in [message.body.plainText, message.body.html]) {
    if (text == null) continue;
    for (final rune in text.runes) {
      bodyBytes += rune < 0x80
          ? 1
          : rune < 0x800
          ? 2
          : rune < 0x10000
          ? 3
          : 4;
      if (bodyBytes > bodyLimit || bodyBytes > budget.maxDecodedBytes) {
        return null;
      }
    }
  }
  var decodedBytes = bodyBytes;
  for (final attachment in message.attachments) {
    if (attachment.observedSize > budget.maxAttachmentBytes) return null;
    decodedBytes += attachment.observedSize;
    if (decodedBytes > budget.maxDecodedBytes) return null;
  }
  return message.raw.length + decodedBytes;
}
