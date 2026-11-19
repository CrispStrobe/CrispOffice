import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_mime/quds_mail_mime.dart';
import 'package:quds_mail_store/quds_mail_archive_native.dart';

import 'studio_mail_archive_host.dart';

/// Numeric, content-free progress for a foreground directory import.
final class StudioMailDirectoryImportProgress {
  const StudioMailDirectoryImportProgress({
    required this.files,
    required this.saved,
    required this.duplicates,
    required this.failed,
    required this.skipped,
    required this.scanErrors,
    required this.limited,
    required this.warnings,
    required this.observerErrors,
  });
  final int files;
  final int saved;
  final int duplicates;
  final int failed;
  final int skipped;
  final int scanErrors;
  final int limited;
  final int warnings;
  final int observerErrors;
  int get processed => saved + duplicates + failed;
  Map<String, int> toJson() => {
    'files': files,
    'saved': saved,
    'duplicates': duplicates,
    'failed': failed,
    'skipped': skipped,
    'scanErrors': scanErrors,
    'limited': limited,
    'warnings': warnings,
    'observerErrors': observerErrors,
  };
}

final class StudioMailDirectoryImportReport {
  const StudioMailDirectoryImportReport({
    required this.status,
    required this.progress,
    this.problem,
  });
  final MailArchiveRunStatus status;
  final StudioMailDirectoryImportProgress progress;
  final MailProblem? problem;
}

/// Stream a selected directory into the archive, committing each original
/// independently. Relative subfolders become provenance under [folder].
/// Source IDs hash full relative file paths plus record ordinals, so duplicate
/// basenames in different directories cannot collapse their provenance.
///
/// A changing directory is not a snapshot. The native reader revalidates each
/// admitted file and bounds MBOX reads to its observed size. Rerunning starts
/// from the beginning and deduplicates original bytes; this is not a saved
/// import cursor. Neither this importer nor the walker modifies source files.
Future<StudioMailDirectoryImportReport> importStudioMailDirectory({
  required StudioMailArchiveStore store,
  required StudioMailArchiveFiles files,
  required String directory,
  required String source,
  required String folder,
  required MailCancellationToken cancellation,
  bool recursive = true,
  bool indexAttachmentText = false,
  MailMboxDialect dialect = MailMboxDialect.mboxrd,
  MailArchiveDirectoryLimits directoryLimits =
      const MailArchiveDirectoryLimits(),
  int maxMessageBytes = 32 * 1024 * 1024,
  int maxMessages = 100000,
  void Function(StudioMailDirectoryImportProgress progress)? onProgress,
}) async {
  final run = _DirectoryImportRun(onProgress);
  var baseFolder = folder;
  try {
    cancellation.throwIfCancelled();
    if (!directoryLimits.isValid ||
        maxMessageBytes < 1 ||
        maxMessageBytes > 256 * 1024 * 1024 ||
        maxMessages < 1 ||
        maxMessages > 1000000 ||
        source.trim().isEmpty ||
        source.length > 1024 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(source)) {
      return run.finish(
        MailArchiveRunStatus.failed,
        MailProblemCode.invalidInput,
      );
    }
    baseFolder = _folder(folder);
    var terminal = false;
    await for (final entry in files.enumerateDirectory(
      directory,
      cancellation: cancellation,
      limits: directoryLimits,
      recursive: recursive,
    )) {
      cancellation.throwIfCancelled();
      run.files = entry.progress.filesAccepted;
      run.skipped = entry.progress.skippedEntries;
      run.scanErrors = entry.progress.errorEntries;
      run.limited = entry.progress.limitedEntries;
      run.emit();
      cancellation.throwIfCancelled();
      if (entry.terminal) {
        terminal = true;
        if (entry.outcome == MailArchiveDirectoryOutcome.cancelled) {
          return run.finish(
            MailArchiveRunStatus.cancelled,
            MailProblemCode.cancelled,
          );
        }
        if (entry.outcome == MailArchiveDirectoryOutcome.limited) {
          return run.finish(
            MailArchiveRunStatus.limited,
            MailProblemCode.quotaExceeded,
          );
        }
        if (entry.outcome == MailArchiveDirectoryOutcome.error) {
          return run.finish(run.failureStatus, MailProblemCode.unavailable);
        }
        break;
      }
      if (entry.outcome != MailArchiveDirectoryOutcome.file) continue;
      if (run.processed >= maxMessages) {
        return run.finish(
          MailArchiveRunStatus.limited,
          MailProblemCode.quotaExceeded,
        );
      }
      final relative = entry.relativePath;
      final relativeFolder = entry.relativeFolder;
      final path = entry.absolutePath;
      if (relative == null ||
          relativeFolder == null ||
          path == null ||
          entry.byteLength == null ||
          relative.isEmpty ||
          relative.length > directoryLimits.maxPathCodeUnits ||
          relative.startsWith('/') ||
          relative.contains('\\') ||
          RegExp(r'[\x00-\x1f\x7f]').hasMatch(relative) ||
          relative
              .split('/')
              .any((part) => part.isEmpty || part == '.' || part == '..') ||
          relative.split('/').take(relative.split('/').length - 1).join('/') !=
              relativeFolder) {
        run.failed++;
        run.emit();
        continue;
      }
      final destinationFolder = _folder('$baseFolder/$relativeFolder');
      final identity = crypto.sha256.convert(utf8.encode(relative)).toString();
      var ordinal = 0;
      try {
        await for (final record in files.readMessages(
          StudioMailArchiveInput(
            name: relative.split('/').last,
            path: path,
            directoryRoot: directory,
            expectedSize: entry.byteLength,
          ),
          maxMessageBytes: maxMessageBytes,
          cancellation: cancellation,
          dialect: dialect,
        )) {
          cancellation.throwIfCancelled();
          if (run.processed >= maxMessages) {
            return run.finish(
              MailArchiveRunStatus.limited,
              MailProblemCode.quotaExceeded,
            );
          }
          ordinal++;
          if (record case MailFailure(:final problem)) {
            if (_cancelled(problem.code)) {
              return run.finish(MailArchiveRunStatus.cancelled, problem.code);
            }
            run.failed++;
            run.emit();
            continue;
          }
          final bytes = (record as MailSuccess<Uint8List>).value;
          if (bytes.isEmpty || bytes.length > maxMessageBytes) {
            run.failed++;
            run.emit();
            continue;
          }
          final parsed = const QudsMimeCodec().parse(
            bytes,
            budget: MailReadBudget(maxRawBytes: maxMessageBytes),
            cancellation: cancellation,
          );
          cancellation.throwIfCancelled();
          final message = parsed.message;
          if (message == null || parsed.status == MailParseStatus.cancelled) {
            run.failed++;
            run.emit();
            continue;
          }
          final MailResult<MailArchiveImportResult> result;
          try {
            result = await store.archiveMessage(
              message,
              origin: MailArchiveOrigin(
                source: source,
                folder: destinationFolder,
                sourceMessageId: 'file:$identity:$ordinal',
              ),
              indexAttachmentText: indexAttachmentText,
              cancellation: cancellation,
            );
          } on MailCancelled {
            rethrow;
          } on Object {
            run.failed++;
            return run.finish(
              run.failureStatus,
              MailProblemCode.storageFailure,
            );
          }
          // Account for confirmed committed originals before late cancellation.
          if (result case MailSuccess(:final value)) {
            if (value.duplicate) {
              run.duplicates++;
            } else {
              run.saved++;
            }
            if (parsed.status != MailParseStatus.complete ||
                value.entry.indexTruncated ||
                value.entry.attachmentTextSkipped > 0) {
              run.warnings++;
            }
          } else {
            final problem =
                (result as MailFailure<MailArchiveImportResult>).problem;
            if (_cancelled(problem.code)) {
              return run.finish(MailArchiveRunStatus.cancelled, problem.code);
            }
            run.failed++;
            run.emit();
            if (problem.code == MailProblemCode.quotaExceeded) {
              return run.finish(MailArchiveRunStatus.limited, problem.code);
            }
            if (problem.code == MailProblemCode.storageFailure ||
                problem.code == MailProblemCode.unavailable ||
                problem.code == MailProblemCode.permissionDenied) {
              return run.finish(run.failureStatus, problem.code);
            }
          }
          run.emit();
          cancellation.throwIfCancelled();
          await Future<void>.delayed(Duration.zero);
        }
      } on MailCancelled {
        rethrow;
      } on Object {
        run.failed++;
        run.emit();
      }
    }
    cancellation.throwIfCancelled();
    if (!terminal) {
      return run.finish(run.failureStatus, MailProblemCode.unavailable);
    }
    return run.finish(
      run.limited > 0
          ? MailArchiveRunStatus.limited
          : run.failed + run.skipped + run.scanErrors > 0
          ? MailArchiveRunStatus.partial
          : MailArchiveRunStatus.completed,
    );
  } on MailCancelled {
    return run.finish(
      MailArchiveRunStatus.cancelled,
      MailProblemCode.cancelled,
    );
  } on FormatException {
    return run.finish(run.failureStatus, MailProblemCode.invalidInput);
  } on Object {
    return run.finish(run.failureStatus, MailProblemCode.unavailable);
  }
}

bool _cancelled(MailProblemCode code) =>
    code == MailProblemCode.cancelled || code == MailProblemCode.staleOperation;

String _folder(String value) {
  if (value.trim().isEmpty ||
      value.length > 4096 ||
      RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)) {
    throw const FormatException('Invalid archive folder.');
  }
  final parts = value.replaceAll('\\', '/').split('/');
  if (parts.any((part) => part == '.' || part == '..')) {
    throw const FormatException('Invalid archive folder.');
  }
  return '/${parts.where((part) => part.isNotEmpty).join('/')}';
}

final class _DirectoryImportRun {
  _DirectoryImportRun(this.onProgress);
  final void Function(StudioMailDirectoryImportProgress)? onProgress;
  int files = 0, saved = 0, duplicates = 0, failed = 0;
  int skipped = 0,
      scanErrors = 0,
      limited = 0,
      warnings = 0,
      observerErrors = 0;
  int get processed => saved + duplicates + failed;
  MailArchiveRunStatus get failureStatus => saved + duplicates > 0
      ? MailArchiveRunStatus.partial
      : MailArchiveRunStatus.failed;
  StudioMailDirectoryImportProgress get progress =>
      StudioMailDirectoryImportProgress(
        files: files,
        saved: saved,
        duplicates: duplicates,
        failed: failed,
        skipped: skipped,
        scanErrors: scanErrors,
        limited: limited,
        warnings: warnings,
        observerErrors: observerErrors,
      );
  void emit() {
    try {
      onProgress?.call(progress);
    } on Object {
      observerErrors++;
    }
  }

  StudioMailDirectoryImportReport finish(
    MailArchiveRunStatus status, [
    MailProblemCode? code,
  ]) {
    emit();
    return StudioMailDirectoryImportReport(
      status: status,
      progress: progress,
      problem: code == null ? null : MailProblem(code),
    );
  }
}
