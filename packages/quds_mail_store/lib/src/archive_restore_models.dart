import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:quds_mail_core/quds_mail_core.dart';

import 'archive_export_models.dart';
import 'archive_restore_checkpoint_models.dart';

/// A validated preview of an exported selection. Provenance is untrusted
/// display metadata. Its unsigned digest detects changes, not authenticity.
/// Restoring copies messages into the destination's existing profile; it never
/// changes archive ownership or restores settings, credentials or saved searches.
final class MailArchiveRestorePlan {
  MailArchiveRestorePlan._({
    required this.directoryPath,
    required this.manifestSha256,
    required this.exportPlan,
    this.checkpoint,
  });

  factory MailArchiveRestorePlan.fromManifest({
    required String directoryPath,
    required String manifest,
    MailArchiveExportLimits limits = const MailArchiveExportLimits(),
  }) {
    final plan = decodeMailArchiveExportManifest(manifest, limits);
    return MailArchiveRestorePlan._(
      directoryPath: directoryPath,
      manifestSha256: crypto.sha256.convert(utf8.encode(manifest)).toString(),
      exportPlan: plan,
    );
  }

  /// Explicit user-facing source path, omitted from progress diagnostics.
  final String directoryPath;
  final String manifestSha256;
  final MailArchiveExportPlan exportPlan;

  /// Recorded progress in the destination at inspection time. This is a
  /// preview, not permission to skip work: resume validates each retained
  /// original and its complete provenance again before confirming a receipt.
  final MailArchiveRestoreCheckpoint? checkpoint;

  MailArchiveRestorePlan withCheckpoint(
    MailArchiveRestoreCheckpoint? checkpoint,
  ) => MailArchiveRestorePlan._(
    directoryPath: directoryPath,
    manifestSha256: manifestSha256,
    exportPlan: exportPlan,
    checkpoint: checkpoint,
  );

  MailProfileId get sourceProfile => exportPlan.profile;
  DateTime get createdAt => exportPlan.createdAt;
  int get messageCount => exportPlan.items.length;
  int get totalBytes => exportPlan.totalBytes;
  int get originCount =>
      exportPlan.items.fold(0, (total, item) => total + item.origins.length);
}

enum MailArchiveRestoreStatus { completed, partial, cancelled, failed }

enum MailArchiveRestorePhase { started, message, finished }

final class MailArchiveRestoreFailure {
  const MailArchiveRestoreFailure({required this.ordinal, required this.code});
  final int ordinal;
  final MailProblemCode code;
}

/// Numeric, content-free progress. A message is accounted only after its
/// original, index and all origins are confirmed in one archive transaction.
final class MailArchiveRestoreProgress {
  const MailArchiveRestoreProgress({
    required this.phase,
    required this.planned,
    required this.saved,
    required this.duplicates,
    required this.failed,
    required this.originsAdded,
    required this.bytes,
    required this.indexWarnings,
    required this.elapsedMicroseconds,
    required this.observerErrors,
    this.resumed = 0,
    this.resumedBytes = 0,
    this.resumedIndexWarnings = 0,
    this.status,
    this.problem,
  });

  final MailArchiveRestorePhase phase;
  final int planned;
  final int saved;
  final int duplicates;
  final int failed;
  final int originsAdded;

  /// Verified committed original bytes this run, including duplicate originals.
  final int bytes;

  /// Previously committed messages verified in the destination this run.
  /// Their source files are not read or parsed in resume mode.
  final int resumed;
  final int resumedBytes;
  final int resumedIndexWarnings;

  /// Successful messages whose parsing or retained index projection is partial.
  final int indexWarnings;
  final int elapsedMicroseconds;
  final int observerErrors;
  final MailArchiveRestoreStatus? status;
  final MailProblemCode? problem;

  int get processed => saved + duplicates + failed + resumed;

  Map<String, Object> toJson() => {
    'phase': phase.name,
    'planned': planned,
    'saved': saved,
    'duplicates': duplicates,
    'failed': failed,
    'originsAdded': originsAdded,
    'bytes': bytes,
    'resumed': resumed,
    'resumedBytes': resumedBytes,
    'resumedIndexWarnings': resumedIndexWarnings,
    'indexWarnings': indexWarnings,
    'elapsedMicroseconds': elapsedMicroseconds,
    'observerErrors': observerErrors,
    if (status != null) 'status': status!.name,
    if (problem != null) 'problem': problem!.name,
  };
}

typedef MailArchiveRestoreProgressSink =
    void Function(MailArchiveRestoreProgress progress);

final class MailArchiveRestoreReport {
  MailArchiveRestoreReport({
    required this.status,
    required this.planned,
    required this.saved,
    required this.duplicates,
    required this.failed,
    required this.originsAdded,
    required this.bytes,
    required this.indexWarnings,
    required this.elapsedMicroseconds,
    required this.observerErrors,
    required List<MailArchiveRestoreFailure> failures,
    required this.droppedFailures,
    this.resumed = 0,
    this.resumedBytes = 0,
    this.resumedIndexWarnings = 0,
    this.problem,
  }) : failures = List.unmodifiable(failures);

  final MailArchiveRestoreStatus status;
  final int planned;
  final int saved;
  final int duplicates;
  final int failed;
  final int originsAdded;
  final int bytes;
  final int resumed;
  final int resumedBytes;
  final int resumedIndexWarnings;
  final int indexWarnings;
  final int elapsedMicroseconds;
  final int observerErrors;
  final List<MailArchiveRestoreFailure> failures;
  final int droppedFailures;
  final MailProblem? problem;

  int get processed => saved + duplicates + failed + resumed;
}
