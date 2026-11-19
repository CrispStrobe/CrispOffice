import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as p;
import 'package:quds_mail_core/quds_mail_core.dart';

import 'archive_export_models.dart';
import 'archive_models.dart';
import 'archive_repository.dart';
import 'archive_restore_checkpoint_models.dart';
import 'archive_restore_models.dart';
import 'errors.dart';

/// Restore a bounded exported selection into an existing native archive.
///
/// Inspection reads only the manifest. Restoration verifies every named EML
/// against its exact length and SHA-256 before parsing, then commits the
/// original, index, all exported provenance and a durable receipt atomically
/// per message. Full reruns verify input again and merge missing origins.
/// Explicit resume verifies recorded messages in the destination and reads
/// source EML only for unfinished items. Receipts survive process termination.
/// Source files, ownership files and staging directories are never changed.
/// The export profile is informative and may differ from [archive.profile].
///
/// Unsigned manifests do not authenticate provenance. A host should show the
/// selection and its source profile before accepting it. This is message
/// restoration, not a database backup or a restore into a provider mailbox.
///
/// Observed links (including ancestor components), non-regular files, changed
/// metadata and changed manifests are rejected. Portable Dart file APIs cannot
/// atomically prevent a hostile process replacing paths between system calls;
/// use a source directory under the user's control. No filesystem snapshot is
/// implied. Resume is bound to decoded manifest text and the destination archive,
/// not the source directory's location or the preview's recorded counts.
final class NativeMailArchiveRestorer {
  NativeMailArchiveRestorer({
    required this.archive,
    required this.codec,
    this.limits = const MailArchiveExportLimits(),
  });

  final SqliteMailArchive archive;
  final MailCodec codec;
  final MailArchiveExportLimits limits;
  static final Expando<Object> _owners = Expando('mail archive restore owner');

  Future<MailResult<MailArchiveRestorePlan>> inspect(
    Directory directory, {
    MailCancellationToken? cancellation,
  }) async {
    try {
      cancellation?.throwIfCancelled();
      if (!limits.isValid) _fail(MailProblemCode.invalidInput);
      final root = await _directory(directory.path, cancellation);
      final manifest = await _readManifest(root, cancellation);
      final plan = MailArchiveRestorePlan.fromManifest(
        directoryPath: root,
        manifest: manifest.text,
        limits: limits,
      );
      final checkpoint = await archive.restoreCheckpoint(
        plan,
        cancellation: cancellation,
      );
      cancellation?.throwIfCancelled();
      return switch (checkpoint) {
        MailSuccess(:final value) => MailSuccess(plan.withCheckpoint(value)),
        MailFailure(:final problem) => MailFailure(problem),
      };
    } on Object catch (error) {
      return MailFailure(_problem(error));
    }
  }

  Future<MailArchiveRestoreReport> restore(
    MailArchiveRestorePlan preview, {
    bool indexAttachmentText = false,
    bool resume = false,
    MailCancellationToken? cancellation,
    MailArchiveRestoreProgressSink? onProgress,
  }) async {
    final run = _RestoreRun(limits.maxFailures, onProgress);
    final owner = Object();
    var owned = false;
    try {
      cancellation?.throwIfCancelled();
      if (!limits.isValid) _fail(MailProblemCode.invalidInput);
      if (_owners[archive] != null) _fail(MailProblemCode.conflict);
      _owners[archive] = owner;
      owned = true;
      final root = await _directory(preview.directoryPath, cancellation);
      final manifest = await _readManifest(root, cancellation);
      if (_digest(manifest.text) != preview.manifestSha256) {
        _fail(MailProblemCode.conflict);
      }
      // Decode afresh under this restorer's limits, not the limits used by the
      // preview's creator. Do not silently truncate an over-budget selection.
      final selection = MailArchiveRestorePlan.fromManifest(
        directoryPath: root,
        manifest: manifest.text,
        limits: limits,
      );
      final plan = selection.exportPlan;
      run.planned = plan.items.length;
      run.emit(MailArchiveRestorePhase.started);
      for (var index = 0; index < plan.items.length; index++) {
        cancellation?.throwIfCancelled();
        await _unchanged(manifest.file, manifest.stat, cancellation);
        final item = plan.items[index];
        MailParseResult parsed;
        try {
          if (item.byteLength > archive.limits.maxMessageBytes) {
            _fail(MailProblemCode.quotaExceeded);
          }
          if (resume) {
            final restored = await archive.loadRestoreReceipt(
              selection,
              index + 1,
              cancellation: cancellation,
            );
            if (restored case MailFailure(:final problem)) {
              _fail(problem.code);
            }
            final receipt =
                (restored as MailSuccess<MailArchiveRestoreReceipt?>).value;
            if (receipt != null) {
              await _unchanged(manifest.file, manifest.stat, cancellation);
              run.resumed++;
              run.resumedBytes += receipt.byteLength;
              if (receipt.indexWarning) run.resumedIndexWarnings++;
              run.emit(MailArchiveRestorePhase.message);
              cancellation?.throwIfCancelled();
              await Future<void>.delayed(Duration.zero);
              continue;
            }
          }
          final file = File(p.join(root, '${item.id}.eml'));
          final original = await _readFile(
            file,
            maximum: limits.maxMessageBytes,
            expectedLength: item.byteLength,
            cancellation: cancellation,
          );
          if (crypto.sha256.convert(original.bytes).toString() != item.id) {
            _fail(MailProblemCode.conflict);
          }
          parsed = codec.parse(
            original.bytes,
            budget: MailReadBudget(maxRawBytes: limits.maxMessageBytes),
            cancellation: cancellation,
          );
          cancellation?.throwIfCancelled();
          if (parsed.status == MailParseStatus.cancelled) {
            _fail(MailProblemCode.cancelled);
          }
          final message = parsed.message;
          if (message == null ||
              (parsed.status != MailParseStatus.complete &&
                  parsed.status != MailParseStatus.partial)) {
            _fail(
              parsed.status == MailParseStatus.unsupported
                  ? MailProblemCode.unsupported
                  : MailProblemCode.invalidInput,
            );
          }
          // A codec supplies a projection, never permission to replace the
          // verified original with rebuilt MIME or another byte sequence.
          if (message.raw.length != item.byteLength ||
              message.raw.sha256 != item.id) {
            _fail(MailProblemCode.conflict);
          }
          await _unchanged(file, original.stat, cancellation);
        } on Object catch (error) {
          final problem = _problem(error);
          if (_cancelled(problem.code)) rethrow;
          run.fail(index + 1, problem);
          run.emit(MailArchiveRestorePhase.message);
          if (problem.code == MailProblemCode.quotaExceeded ||
              problem.code == MailProblemCode.storageFailure ||
              problem.code == MailProblemCode.permissionDenied) {
            rethrow;
          }
          cancellation?.throwIfCancelled();
          await Future<void>.delayed(Duration.zero);
          continue;
        }
        // Check the manifest and its ancestors again after an injected codec
        // has returned, immediately before accepting any database mutation.
        await _unchanged(manifest.file, manifest.stat, cancellation);
        cancellation?.throwIfCancelled();
        final stored = await archive.archiveRestoreMessage(
          parsed.message!,
          plan: selection,
          ordinal: index + 1,
          indexAttachmentText: indexAttachmentText,
          indexWarning: parsed.status != MailParseStatus.complete,
          cancellation: cancellation,
        );
        if (stored case MailSuccess<MailArchiveImportResult>(:final value)) {
          // A late cancellation/observer failure cannot erase confirmed work.
          if (value.duplicate) {
            run.duplicates++;
          } else {
            run.saved++;
          }
          run.originsAdded += value.originsAdded;
          run.bytes += item.byteLength;
          if (parsed.status != MailParseStatus.complete ||
              value.entry.indexTruncated ||
              value.entry.attachmentTextSkipped > 0) {
            run.indexWarnings++;
          }
        } else {
          final problem =
              (stored as MailFailure<MailArchiveImportResult>).problem;
          if (_cancelled(problem.code)) _fail(problem.code);
          run.fail(index + 1, problem);
          run.emit(MailArchiveRestorePhase.message);
          if (problem.code == MailProblemCode.quotaExceeded ||
              problem.code == MailProblemCode.storageFailure ||
              problem.code == MailProblemCode.unavailable ||
              problem.code == MailProblemCode.permissionDenied) {
            _fail(problem.code);
          }
          cancellation?.throwIfCancelled();
          await Future<void>.delayed(Duration.zero);
          continue;
        }
        run.emit(MailArchiveRestorePhase.message);
        cancellation?.throwIfCancelled();
        await Future<void>.delayed(Duration.zero);
      }
      final finalManifest = await _readManifest(root, cancellation);
      if (_digest(finalManifest.text) != preview.manifestSha256) {
        _fail(MailProblemCode.conflict);
      }
      return run.finish(
        run.failed == 0
            ? MailArchiveRestoreStatus.completed
            : run.saved + run.duplicates + run.resumed > 0
            ? MailArchiveRestoreStatus.partial
            : MailArchiveRestoreStatus.failed,
      );
    } on Object catch (error) {
      return run.failedResult(_problem(error));
    } finally {
      if (owned && identical(_owners[archive], owner)) _owners[archive] = null;
    }
  }

  static Never _fail(MailProblemCode code) =>
      throw MailStoreStorageException(code);

  static String _digest(String text) =>
      crypto.sha256.convert(utf8.encode(text)).toString();

  static bool _cancelled(MailProblemCode code) =>
      code == MailProblemCode.cancelled ||
      code == MailProblemCode.staleOperation;

  Future<String> _directory(
    String path,
    MailCancellationToken? cancellation,
  ) async {
    _validatePath(path, maxComponents: 128);
    final normalized = p.normalize(path);
    await _checkPath(normalized, FileSystemEntityType.directory, cancellation);
    return normalized;
  }

  void _validatePath(String path, {int maxComponents = 129}) {
    if (!p.isAbsolute(path) ||
        p.split(path).contains('..') ||
        (!Platform.isWindows && path.contains(r'\')) ||
        RegExp(
          r'[\x00-\x1f\x7f-\x9f\u202a-\u202e\u2066-\u2069]',
        ).hasMatch(path)) {
      _fail(MailProblemCode.invalidInput);
    }
    if (path.length > 4096 || p.split(path).length > maxComponents) {
      _fail(MailProblemCode.quotaExceeded);
    }
  }

  Future<void> _checkPath(
    String path,
    FileSystemEntityType expected,
    MailCancellationToken? cancellation,
  ) async {
    _validatePath(path);
    final components = p.split(path);
    var current = components.first;
    for (var index = 0; index < components.length; index++) {
      cancellation?.throwIfCancelled();
      if (index > 0) current = p.join(current, components[index]);
      // ignore: avoid_slow_async_io
      final type = await FileSystemEntity.type(current, followLinks: false);
      if (type == FileSystemEntityType.notFound) {
        _fail(MailProblemCode.unavailable);
      }
      if (type !=
          (index == components.length - 1
              ? expected
              : FileSystemEntityType.directory)) {
        _fail(MailProblemCode.conflict);
      }
    }
    cancellation?.throwIfCancelled();
  }

  Future<_RestoreManifest> _readManifest(
    String root,
    MailCancellationToken? cancellation,
  ) async {
    final file = File(p.join(root, 'manifest.json'));
    final data = await _readFile(
      file,
      maximum: limits.maxManifestBytes,
      cancellation: cancellation,
    );
    return _RestoreManifest(file, data.stat, utf8.decode(data.bytes));
  }

  Future<_RestoreBytes> _readFile(
    File file, {
    required int maximum,
    int? expectedLength,
    MailCancellationToken? cancellation,
  }) async {
    await _checkPath(file.path, FileSystemEntityType.file, cancellation);
    // Keep bounded filesystem work responsive to host cancellation.
    // ignore: avoid_slow_async_io
    final before = await file.stat();
    if (before.type != FileSystemEntityType.file) {
      _fail(MailProblemCode.conflict);
    }
    if (before.size > maximum) _fail(MailProblemCode.quotaExceeded);
    if (before.size <= 0 ||
        (expectedLength != null && before.size != expectedLength)) {
      _fail(MailProblemCode.conflict);
    }
    RandomAccessFile? handle;
    try {
      handle = await file.open();
      if (await handle.length() != before.size) _fail(MailProblemCode.conflict);
      await _unchanged(file, before, cancellation);
      final bytes = Uint8List(before.size);
      var offset = 0;
      while (offset < bytes.length) {
        cancellation?.throwIfCancelled();
        final end = (offset + 65536).clamp(0, bytes.length);
        final count = await handle.readInto(bytes, offset, end);
        if (count == 0) _fail(MailProblemCode.conflict);
        offset += count;
      }
      if (await handle.length() != before.size) _fail(MailProblemCode.conflict);
      await _unchanged(file, before, cancellation);
      return _RestoreBytes(bytes, before);
    } finally {
      await handle?.close();
    }
  }

  Future<void> _unchanged(
    File file,
    FileStat before,
    MailCancellationToken? cancellation,
  ) async {
    await _checkPath(file.path, FileSystemEntityType.file, cancellation);
    // ignore: avoid_slow_async_io
    final after = await file.stat();
    if (after.type != FileSystemEntityType.file ||
        after.size != before.size ||
        after.modified != before.modified ||
        after.changed != before.changed) {
      _fail(MailProblemCode.conflict);
    }
    cancellation?.throwIfCancelled();
  }

  MailProblem _problem(Object error) {
    if (error is FormatException || error is ArgumentError) {
      return const MailProblem(MailProblemCode.invalidInput);
    }
    if (error is FileSystemException) {
      return MailProblem(switch (error.osError?.errorCode) {
        13 || 5 => MailProblemCode.permissionDenied,
        28 || 112 => MailProblemCode.quotaExceeded,
        _ => MailProblemCode.unavailable,
      });
    }
    return mailStoreProblem(error);
  }
}

final class _RestoreManifest {
  const _RestoreManifest(this.file, this.stat, this.text);
  final File file;
  final FileStat stat;
  final String text;
}

final class _RestoreBytes {
  const _RestoreBytes(this.bytes, this.stat);
  final Uint8List bytes;
  final FileStat stat;
}

final class _RestoreRun {
  _RestoreRun(this.maxFailures, this.sink);
  final int maxFailures;
  final MailArchiveRestoreProgressSink? sink;
  final Stopwatch clock = Stopwatch()..start();
  int planned = 0;
  int saved = 0;
  int duplicates = 0;
  int failed = 0;
  int originsAdded = 0;
  int bytes = 0;
  int resumed = 0;
  int resumedBytes = 0;
  int resumedIndexWarnings = 0;
  int indexWarnings = 0;
  int observerErrors = 0;
  int droppedFailures = 0;
  MailProblem? firstProblem;
  final List<MailArchiveRestoreFailure> failures = [];

  void fail(int ordinal, MailProblem problem) {
    failed++;
    firstProblem ??= problem;
    if (failures.length < maxFailures) {
      failures.add(
        MailArchiveRestoreFailure(ordinal: ordinal, code: problem.code),
      );
    } else {
      droppedFailures++;
    }
  }

  void emit(
    MailArchiveRestorePhase phase, {
    MailArchiveRestoreStatus? status,
    MailProblem? problem,
  }) {
    try {
      sink?.call(
        MailArchiveRestoreProgress(
          phase: phase,
          planned: planned,
          saved: saved,
          duplicates: duplicates,
          failed: failed,
          originsAdded: originsAdded,
          bytes: bytes,
          resumed: resumed,
          resumedBytes: resumedBytes,
          resumedIndexWarnings: resumedIndexWarnings,
          indexWarnings: indexWarnings,
          elapsedMicroseconds: clock.elapsedMicroseconds,
          observerErrors: observerErrors,
          status: status,
          problem: problem?.code,
        ),
      );
    } on Object {
      observerErrors++;
    }
  }

  MailArchiveRestoreReport failedResult(MailProblem problem) => finish(
    NativeMailArchiveRestorer._cancelled(problem.code)
        ? MailArchiveRestoreStatus.cancelled
        : saved + duplicates + resumed > 0
        ? MailArchiveRestoreStatus.partial
        : MailArchiveRestoreStatus.failed,
    problem: problem,
  );

  MailArchiveRestoreReport finish(
    MailArchiveRestoreStatus status, {
    MailProblem? problem,
  }) {
    final terminalProblem = problem ?? firstProblem;
    emit(
      MailArchiveRestorePhase.finished,
      status: status,
      problem: terminalProblem,
    );
    clock.stop();
    return MailArchiveRestoreReport(
      status: status,
      planned: planned,
      saved: saved,
      duplicates: duplicates,
      failed: failed,
      originsAdded: originsAdded,
      bytes: bytes,
      resumed: resumed,
      resumedBytes: resumedBytes,
      resumedIndexWarnings: resumedIndexWarnings,
      indexWarnings: indexWarnings,
      elapsedMicroseconds: clock.elapsedMicroseconds,
      observerErrors: observerErrors,
      failures: failures,
      droppedFailures: droppedFailures,
      problem: terminalProblem,
    );
  }
}
