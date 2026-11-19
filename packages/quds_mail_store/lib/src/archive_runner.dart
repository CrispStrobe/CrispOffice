import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:quds_mail_core/quds_mail_core.dart';

import 'archive_models.dart';
import 'archive_repository.dart';

enum MailArchiveRunStatus { completed, partial, cancelled, limited, failed }

enum MailArchiveRunStage { fetch, identity, store }

enum MailArchiveRunPhase { started, page, message, finished }

/// A content-free failure for a known item in this run, never a remote ID.
final class MailArchiveRunFailure {
  const MailArchiveRunFailure({
    required this.ordinal,
    required this.stage,
    required this.code,
  });

  final int ordinal;
  final MailArchiveRunStage stage;
  final MailProblemCode code;
}

/// Fixed phases, status and numeric metrics are safe for verbose diagnostics.
final class MailArchiveRunProgress {
  const MailArchiveRunProgress({
    required this.operationId,
    required this.phase,
    required this.pages,
    required this.processed,
    required this.saved,
    required this.duplicates,
    required this.failed,
    required this.bytes,
    required this.elapsedMicroseconds,
    required this.observerErrors,
    this.status,
    this.problem,
  });

  final int operationId;
  final MailArchiveRunPhase phase;
  final int pages;
  final int processed;
  final int saved;
  final int duplicates;
  final int failed;
  final int bytes;
  final int elapsedMicroseconds;
  final int observerErrors;
  final MailArchiveRunStatus? status;
  final MailProblemCode? problem;

  Map<String, Object> toJson() => {
    'operationId': operationId,
    'phase': phase.name,
    'pages': pages,
    'processed': processed,
    'saved': saved,
    'duplicates': duplicates,
    'failed': failed,
    'bytes': bytes,
    'elapsedMicroseconds': elapsedMicroseconds,
    'observerErrors': observerErrors,
    if (status != null) 'status': status!.name,
    if (problem != null) 'problem': problem!.name,
  };
}

typedef MailArchiveProgressSink =
    void Function(MailArchiveRunProgress progress);

/// A truthful local result; completed means the observed page sequence ended.
/// It does not assert that a changing remote mailbox was a consistent snapshot.
final class MailArchiveRunReport {
  MailArchiveRunReport({
    required this.status,
    required this.pages,
    required this.processed,
    required this.saved,
    required this.duplicates,
    required this.failed,
    required this.bytes,
    required this.elapsedMicroseconds,
    required this.observerErrors,
    required List<MailArchiveRunFailure> failures,
    required this.droppedFailures,
    this.problem,
  }) : failures = List.unmodifiable(failures);

  final MailArchiveRunStatus status;
  final int pages;

  /// Finished item attempts: always saved + duplicates + failed. A cancelled
  /// in-flight item is not counted as an unsuccessful committed operation.
  final int processed;
  final int saved;
  final int duplicates;
  final int failed;

  /// Exact original bytes of newly saved records; duplicates are excluded.
  final int bytes;
  final int elapsedMicroseconds;
  final int observerErrors;
  final List<MailArchiveRunFailure> failures;
  final int droppedFailures;

  /// Terminal reason. An individual failed item may instead be in failures.
  final MailProblem? problem;
}

/// Bounded, read-only collection from one connected mailbox into an archive.
///
/// Only fetchHeaders/fetchMessage are called. No provider mutation, deletion,
/// change cursor, account credential or network response is persisted here.
/// Each original is committed by the archive independently; rerunning starts at
/// the first page and deduplicates exact raw bytes. There is no durable cursor,
/// scheduler, retry, or promise of a remote point-in-time mailbox snapshot.
///
/// The supplied profile must explicitly select mailbox kind and disable
/// includeSubfolders. Its source/folder supply the archive provenance; the host
/// owns choosing and saving that profile. An opaque provenance fingerprint
/// includes the stable profile ID/source, mailbox and full provider identity.
/// Hosts reuse that profile across reconnects and give unrelated sources distinct
/// profile IDs. Ephemeral live-account IDs are checked for authorization, but
/// never create new provenance merely because a connection was recreated.
///
/// Runs sharing this provider object cannot overlap, including runs through
/// different runner instances. Provider and archive lifetimes remain host-owned.
final class MailArchiveRunner {
  MailArchiveRunner({
    required this.archive,
    required this.provider,
    required this.session,
  });

  final SqliteMailArchive archive;
  final MailProvider provider;
  final MailAccountSession session;
  static final Expando<Object> _owners = Expando('mail archive provider owner');
  int _sequence = 0;
  bool _running = false;
  bool get isRunning => _running;

  Future<MailArchiveRunReport> archiveMailbox(
    MailMailbox mailbox, {
    required MailArchiveProfile profile,
    int pageSize = 100,
    int maxPages = 1000,
    int maxMessages = 100000,
    int maxFailures = 50,
    int maxConsecutiveProviderFailures = 3,
    MailReadBudget budget = const MailReadBudget(),
    MailCancellationToken? cancellation,
    MailArchiveProgressSink? onProgress,
  }) async {
    final run = _ArchiveRun(++_sequence, maxFailures, onProgress);
    if (_running || _owners[provider] != null) {
      return run.finish(
        MailArchiveRunStatus.failed,
        const MailProblem(MailProblemCode.conflict),
      );
    }
    final owner = Object();
    _owners[provider] = owner;
    _running = true;
    try {
      if (pageSize < 1 ||
          pageSize > 1000 ||
          maxPages < 1 ||
          maxPages > 100000 ||
          maxMessages < 1 ||
          maxMessages > 1000000 ||
          maxFailures < 0 ||
          maxFailures > 1000 ||
          maxConsecutiveProviderFailures < 1 ||
          maxConsecutiveProviderFailures > 1000 ||
          provider.account != session.account ||
          mailbox.id.account != session.account ||
          !_identifier(mailbox.id.value) ||
          !_identifier(session.account.value) ||
          !_identifier(session.account.profile.value) ||
          !_identifier(session.account.profile.hostId) ||
          !_identifier(profile.id, max: 1024) ||
          !_identifier(profile.name, max: 1024) ||
          !_identifier(profile.source, max: 1024) ||
          !_folder(profile.folder)) {
        return run.finish(
          MailArchiveRunStatus.failed,
          const MailProblem(MailProblemCode.invalidInput),
        );
      }
      if (profile.kind != MailArchiveProfileKind.mailbox ||
          profile.includeSubfolders) {
        return run.finish(
          MailArchiveRunStatus.failed,
          const MailProblem(MailProblemCode.unsupported),
        );
      }
      try {
        budget.validate();
      } on Object {
        return run.finish(
          MailArchiveRunStatus.failed,
          const MailProblem(MailProblemCode.invalidInput),
        );
      }
      final lease = session.begin(cancellation: cancellation);
      run.emit(MailArchiveRunPhase.started);
      lease.checkCurrent();
      final conclusion = await _collect(
        mailbox,
        profile,
        run,
        lease,
        pageSize,
        maxPages,
        maxMessages,
        maxConsecutiveProviderFailures,
        _budget(budget),
      );
      return run.finish(conclusion.$1, conclusion.$2);
    } on MailCancelled catch (error) {
      return run.finish(MailArchiveRunStatus.cancelled, _cancelled(error));
    } on Object {
      return run.finish(
        run.failureStatus,
        const MailProblem(MailProblemCode.providerFailure),
      );
    } finally {
      if (identical(_owners[provider], owner)) _owners[provider] = null;
      _running = false;
    }
  }

  Future<(MailArchiveRunStatus, MailProblem?)> _collect(
    MailMailbox mailbox,
    MailArchiveProfile profile,
    _ArchiveRun run,
    MailOperationLease lease,
    int pageSize,
    int maxPages,
    int maxMessages,
    int maxConsecutiveProviderFailures,
    MailReadBudget budget,
  ) async {
    MailCursor? cursor;
    MailProviderKind? kind;
    final cursors = <String>{};
    var consecutiveFailures = 0;
    while (true) {
      lease.checkCurrent();
      if (run.pages >= maxPages || run.processed >= maxMessages) {
        return (
          MailArchiveRunStatus.limited,
          const MailProblem(MailProblemCode.quotaExceeded),
        );
      }
      final remaining = maxMessages - run.processed;
      final requested = remaining < pageSize ? remaining : pageSize;
      final pageResult = await provider.fetchHeaders(
        mailbox.id,
        cursor: cursor,
        limit: requested,
        lease: lease,
      );
      lease.checkCurrent();
      if (pageResult case MailFailure<MailHeaderPage>(:final problem)) {
        return (_terminalStatus(run, problem), problem);
      }
      final page = (pageResult as MailSuccess<MailHeaderPage>).value;
      if (!_validPage(page, mailbox.id, requested, cursors, kind)) {
        return (
          run.failureStatus,
          const MailProblem(MailProblemCode.providerFailure),
        );
      }
      if (page.messages.isNotEmpty) {
        kind ??= page.messages.first.remote.provider;
      }
      if (page.next case final next?) cursors.add(_digest(next.value));
      run.pages++;
      run.emit(MailArchiveRunPhase.page);
      lease.checkCurrent();
      for (final header in page.messages) {
        lease.checkCurrent();
        MailResult<MailMessage> fetched;
        try {
          fetched = await provider.fetchMessage(
            header.remote,
            budget: budget,
            lease: lease,
          );
        } on MailCancelled {
          rethrow;
        } on Object {
          fetched = const MailFailure(
            MailProblem(MailProblemCode.providerFailure),
          );
        }
        lease.checkCurrent();
        if (fetched case MailFailure<MailMessage>(:final problem)) {
          if (_isCancellation(problem)) {
            return (MailArchiveRunStatus.cancelled, problem);
          }
          run.fail(MailArchiveRunStage.fetch, problem.code);
          consecutiveFailures++;
          run.emit(MailArchiveRunPhase.message);
          lease.checkCurrent();
          if (consecutiveFailures >= maxConsecutiveProviderFailures ||
              problem.code == MailProblemCode.authenticationRequired ||
              problem.code == MailProblemCode.permissionDenied ||
              problem.retryAfter != null) {
            return (run.failureStatus, problem);
          }
          continue;
        }
        final message = (fetched as MailSuccess<MailMessage>).value;
        final problem =
            message.remoteIdentity != header.remote ||
                (message.localId != null && message.localId != header.id) ||
                message.raw.length == 0
            ? MailProblemCode.providerFailure
            : message.raw.length > budget.maxRawBytes
            ? MailProblemCode.quotaExceeded
            : null;
        if (problem != null) {
          run.fail(MailArchiveRunStage.identity, problem);
          consecutiveFailures++;
          run.emit(MailArchiveRunPhase.message);
          lease.checkCurrent();
          if (consecutiveFailures >= maxConsecutiveProviderFailures) {
            return (run.failureStatus, MailProblem(problem));
          }
          continue;
        }
        consecutiveFailures = 0;
        MailResult<MailArchiveImportResult> stored;
        try {
          stored = await archive.archiveMessage(
            message,
            origin: MailArchiveOrigin(
              source: profile.source,
              folder: profile.folder,
              sourceMessageId: _originKey(profile, mailbox.id, header.remote),
            ),
            indexAttachmentText: profile.indexAttachmentText,
            cancellation: lease.cancellation,
            lease: lease,
          );
        } on MailCancelled {
          rethrow;
        } on Object {
          stored = const MailFailure(
            MailProblem(MailProblemCode.storageFailure),
          );
        }
        // Account for confirmed committed bytes before observing a cancellation
        // that may have happened just after that commit. Never hide durable work.
        if (stored case MailSuccess<MailArchiveImportResult>(:final value)) {
          run.savedItem(duplicate: value.duplicate, length: message.raw.length);
          run.emit(MailArchiveRunPhase.message);
          lease.checkCurrent();
        } else {
          lease.checkCurrent();
          final problem =
              (stored as MailFailure<MailArchiveImportResult>).problem;
          if (_isCancellation(problem)) {
            return (MailArchiveRunStatus.cancelled, problem);
          }
          run.fail(MailArchiveRunStage.store, problem.code);
          run.emit(MailArchiveRunPhase.message);
          lease.checkCurrent();
          if (problem.code == MailProblemCode.quotaExceeded) {
            return (MailArchiveRunStatus.limited, problem);
          }
          if (problem.code == MailProblemCode.unavailable ||
              problem.code == MailProblemCode.storageFailure ||
              problem.code == MailProblemCode.permissionDenied) {
            return (run.failureStatus, problem);
          }
        }
      }
      cursor = page.next;
      if (cursor == null) {
        return (
          run.failed == 0
              ? MailArchiveRunStatus.completed
              : MailArchiveRunStatus.partial,
          null,
        );
      }
    }
  }

  MailReadBudget _budget(MailReadBudget requested) => MailReadBudget(
    maxRawBytes: requested.maxRawBytes < archive.limits.maxMessageBytes
        ? requested.maxRawBytes
        : archive.limits.maxMessageBytes,
    maxDecodedBytes: requested.maxDecodedBytes,
    maxBodyBytes: requested.maxBodyBytes,
    maxAttachmentBytes: requested.maxAttachmentBytes,
    maxAttachments: requested.maxAttachments,
    maxParts: requested.maxParts,
    maxNestingDepth: requested.maxNestingDepth,
    maxHeaderBytes: requested.maxHeaderBytes,
    maxHeaderFieldBytes: requested.maxHeaderFieldBytes,
    maxHtmlNodes: requested.maxHtmlNodes,
    maxHtmlDepth: requested.maxHtmlDepth,
    maxRenderTextBytes: requested.maxRenderTextBytes,
    maxImagePixels: requested.maxImagePixels,
  );
}

bool _identifier(String value, {int max = 4096}) =>
    value.trim().isNotEmpty &&
    value.length <= max &&
    !RegExp(r'[\x00-\x1f\x7f]').hasMatch(value);

bool _folder(String value) =>
    _identifier(value) &&
    !value
        .replaceAll('\\', '/')
        .split('/')
        .any((part) => part == '.' || part == '..');

bool _validPage(
  MailHeaderPage page,
  MailMailboxId mailbox,
  int requested,
  Set<String> cursors,
  MailProviderKind? expectedKind,
) {
  if (page.messages.length > requested) return false;
  if (page.next case final next?) {
    if (next.mailbox != mailbox ||
        !_identifier(next.value, max: 65536) ||
        cursors.contains(_digest(next.value))) {
      return false;
    }
  }
  final ids = <MailMessageId>{};
  final remotes = <MailRemoteIdentity>{};
  var kind = expectedKind;
  for (final header in page.messages) {
    final remote = header.remote;
    kind ??= remote.provider;
    if (remote.account != mailbox.account ||
        remote.provider != kind ||
        !_identifier(header.id.value) ||
        !ids.add(header.id) ||
        !remotes.add(remote)) {
      return false;
    }
    switch (remote) {
      case MailImapIdentity():
        if (remote.mailbox != mailbox) return false;
      case MailOpaqueIdentity():
        if (!_identifier(remote.value, max: 16384)) return false;
    }
  }
  return true;
}

String _digest(String value) =>
    crypto.sha256.convert(utf8.encode(value)).toString();

String _originKey(
  MailArchiveProfile profile,
  MailMailboxId mailbox,
  MailRemoteIdentity identity,
) => _digest(
  jsonEncode([
    2,
    profile.id,
    profile.source,
    mailbox.value,
    identity.provider.name,
    switch (identity) {
      MailImapIdentity() => [
        identity.mailbox.value,
        identity.uidValidity,
        identity.uid,
      ],
      MailOpaqueIdentity() => identity.value,
    },
  ]),
);

MailProblem _cancelled(MailCancelled error) => MailProblem(
  error.reason == MailCancellationReason.user ||
          error.reason == MailCancellationReason.budgetExpired
      ? MailProblemCode.cancelled
      : MailProblemCode.staleOperation,
);

bool _isCancellation(MailProblem problem) =>
    problem.code == MailProblemCode.cancelled ||
    problem.code == MailProblemCode.staleOperation;

MailArchiveRunStatus _terminalStatus(_ArchiveRun run, MailProblem problem) =>
    _isCancellation(problem)
    ? MailArchiveRunStatus.cancelled
    : run.failureStatus;

final class _ArchiveRun {
  _ArchiveRun(this.operationId, this.maxFailures, this.sink);
  final int operationId;
  final int maxFailures;
  final MailArchiveProgressSink? sink;
  final Stopwatch clock = Stopwatch()..start();
  int pages = 0;
  int processed = 0;
  int saved = 0;
  int duplicates = 0;
  int failed = 0;
  int bytes = 0;
  int observerErrors = 0;
  int droppedFailures = 0;
  final List<MailArchiveRunFailure> failures = [];
  MailArchiveRunStatus get failureStatus => saved + duplicates > 0
      ? MailArchiveRunStatus.partial
      : MailArchiveRunStatus.failed;

  void fail(MailArchiveRunStage stage, MailProblemCode code) {
    processed++;
    failed++;
    if (failures.length < maxFailures) {
      failures.add(
        MailArchiveRunFailure(ordinal: processed, stage: stage, code: code),
      );
    } else {
      droppedFailures++;
    }
  }

  void savedItem({required bool duplicate, required int length}) {
    processed++;
    if (duplicate) {
      duplicates++;
    } else {
      saved++;
      bytes += length;
    }
  }

  void emit(
    MailArchiveRunPhase phase, {
    MailArchiveRunStatus? status,
    MailProblemCode? problem,
  }) {
    try {
      sink?.call(
        MailArchiveRunProgress(
          operationId: operationId,
          phase: phase,
          pages: pages,
          processed: processed,
          saved: saved,
          duplicates: duplicates,
          failed: failed,
          bytes: bytes,
          elapsedMicroseconds: clock.elapsedMicroseconds,
          observerErrors: observerErrors,
          status: status,
          problem: problem,
        ),
      );
    } on Object {
      observerErrors++;
    }
  }

  MailArchiveRunReport finish(
    MailArchiveRunStatus status,
    MailProblem? problem,
  ) {
    emit(MailArchiveRunPhase.finished, status: status, problem: problem?.code);
    clock.stop();
    return MailArchiveRunReport(
      status: status,
      pages: pages,
      processed: processed,
      saved: saved,
      duplicates: duplicates,
      failed: failed,
      bytes: bytes,
      elapsedMicroseconds: clock.elapsedMicroseconds,
      observerErrors: observerErrors,
      failures: failures,
      droppedFailures: droppedFailures,
      problem: problem,
    );
  }
}
