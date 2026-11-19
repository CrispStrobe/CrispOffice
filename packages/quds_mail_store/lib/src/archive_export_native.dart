import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as p;
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import 'archive_export_models.dart';
import 'errors.dart';

typedef MailArchiveOriginalLoader =
    Future<MailResult<MailBytes?>> Function(String id);

/// Native, resumable bulk original-message export into a dedicated directory.
///
/// The immutable manifest is flushed before any EML is published. Resume uses
/// its fixed selection and verifies every existing EML's length and SHA-256;
/// it does not trust a progress counter. Temporary files are never interpreted
/// as completed originals. Source mail and existing conflicting files are not
/// modified. SQLite ownership excludes cooperating simultaneous exporters,
/// including separate connections in the same process and other processes.
///
/// Use a private destination under the user's control. Dart's portable file API
/// does not expose directory-relative no-follow operations or a portable atomic
/// no-replace rename. Checks reject observed links and substitutions; they do
/// not defend against a hostile process changing paths between system calls.
/// File flush plus rename is process-crash recovery, not a guarantee against
/// every filesystem, device or power-loss failure. A manifest digest is not a
/// signature, and an export is not a database backup or a mailbox restore.
final class NativeMailArchiveExporter {
  NativeMailArchiveExporter({
    required this.profile,
    required this.loadOriginal,
    this.limits = const MailArchiveExportLimits(),
  });

  final MailProfileId profile;
  final MailArchiveOriginalLoader loadOriginal;
  final MailArchiveExportLimits limits;
  static final Set<String> _active = {};

  Future<MailArchiveExportReport> exportPlan(
    MailArchiveExportPlan plan, {
    required Directory parent,
    MailCancellationToken? cancellation,
    MailArchiveExportProgressSink? onProgress,
  }) async {
    final run = _ExportRun(limits.maxFailures, onProgress);
    _ExportOwner? owner;
    try {
      cancellation?.throwIfCancelled();
      final manifest = encodeMailArchiveExportManifest(plan, limits);
      if (plan.profile != profile) _fail(MailProblemCode.permissionDenied);
      final canonicalParent = await _canonicalDirectory(parent);
      cancellation?.throwIfCancelled();
      final directory = await Directory(
        canonicalParent,
      ).createTemp('crispoffice-mail-export-');
      run.planned = plan.items.length;
      owner = await _claim(directory);
      // Once a directory is allocated, finish its small durable plan even if
      // cancellation arrives. No original is exported until cancellation has
      // been checked again. Returned paths always contain a resumable manifest.
      await _writeManifest(owner, manifest);
      run.directoryPath = directory.path;
      await _export(plan, owner, manifest, run, cancellation);
      return run.finish(
        run.failed == 0
            ? MailArchiveExportStatus.completed
            : run.written + run.existing > 0
            ? MailArchiveExportStatus.partial
            : MailArchiveExportStatus.failed,
      );
    } on Object catch (error) {
      return run.failedResult(_problem(error));
    } finally {
      owner?.close();
    }
  }

  Future<MailArchiveExportReport> resume(
    Directory directory, {
    MailCancellationToken? cancellation,
    MailArchiveExportProgressSink? onProgress,
  }) async {
    final run = _ExportRun(limits.maxFailures, onProgress);
    _ExportOwner? owner;
    try {
      cancellation?.throwIfCancelled();
      if (!limits.isValid) _fail(MailProblemCode.invalidInput);
      // Read and validate before creating an owner file in a user-selected
      // directory. A random folder is never turned into an export implicitly.
      final canonical = await _canonicalDirectory(directory);
      final initial = await _readManifest(canonical, cancellation);
      final plan = decodeMailArchiveExportManifest(initial, limits);
      if (plan.profile != profile) _fail(MailProblemCode.permissionDenied);
      run.directoryPath = canonical;
      run.planned = plan.items.length;
      owner = await _claim(Directory(canonical));
      if (await _readManifest(canonical, cancellation) != initial) {
        _fail(MailProblemCode.conflict);
      }
      await _export(plan, owner, initial, run, cancellation);
      return run.finish(
        run.failed == 0
            ? MailArchiveExportStatus.completed
            : run.written + run.existing > 0
            ? MailArchiveExportStatus.partial
            : MailArchiveExportStatus.failed,
      );
    } on Object catch (error) {
      return run.failedResult(_problem(error));
    } finally {
      owner?.close();
    }
  }

  static Never _fail(MailProblemCode code) =>
      throw MailStoreStorageException(code);

  Future<String> _canonicalDirectory(Directory directory) async {
    if (!directory.isAbsolute) _fail(MailProblemCode.invalidInput);
    if (FileSystemEntity.typeSync(directory.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      _fail(MailProblemCode.conflict);
    }
    return directory.resolveSymbolicLinks();
  }

  Future<_ExportOwner> _claim(Directory directory) async {
    final canonical = await _canonicalDirectory(directory);
    if (!_active.add(canonical)) _fail(MailProblemCode.conflict);
    sqlite.Database? database;
    try {
      final file = File(p.join(canonical, '.export-owner.sqlite3'));
      for (final suffix in ['', '-journal', '-wal', '-shm']) {
        final candidate = File('${file.path}$suffix');
        final type = FileSystemEntity.typeSync(
          candidate.path,
          followLinks: false,
        );
        if (type != FileSystemEntityType.notFound &&
            type != FileSystemEntityType.file) {
          _fail(MailProblemCode.conflict);
        }
        if (type == FileSystemEntityType.file &&
            await candidate.length() > 1024 * 1024) {
          _fail(MailProblemCode.quotaExceeded);
        }
      }
      final type = FileSystemEntity.typeSync(file.path, followLinks: false);
      if (type == FileSystemEntityType.notFound) {
        await file.create(exclusive: true);
      } else if (type != FileSystemEntityType.file) {
        _fail(MailProblemCode.conflict);
      }
      database = sqlite.sqlite3.open(file.path);
      database.execute('PRAGMA busy_timeout = 0');
      database.execute('BEGIN EXCLUSIVE');
      final owner = _ExportOwner(canonical, database, file.statSync());
      await owner.check();
      return owner;
    } on Object {
      try {
        database?.close();
      } on Object {
        // The acquisition error is authoritative, never a raw cleanup error.
      }
      _active.remove(canonical);
      rethrow;
    }
  }

  Future<void> _writeManifest(_ExportOwner owner, String manifest) async {
    await owner.check();
    final destination = File(p.join(owner.path, 'manifest.json'));
    final staging = File(p.join(owner.path, '.manifest.pending'));
    await staging.create(exclusive: true);
    await staging.writeAsString(manifest, encoding: utf8, flush: true);
    await owner.check();
    if (FileSystemEntity.typeSync(destination.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      _fail(MailProblemCode.conflict);
    }
    await staging.rename(destination.path);
    // Do not observe cancellation between publication and recording this
    // recoverable manifest. A directory with a manifest is always resumable.
  }

  Future<String> _readManifest(
    String directory,
    MailCancellationToken? cancellation,
  ) async {
    cancellation?.throwIfCancelled();
    final file = File(p.join(directory, 'manifest.json'));
    if (FileSystemEntity.typeSync(file.path, followLinks: false) !=
        FileSystemEntityType.file) {
      _fail(MailProblemCode.conflict);
    }
    RandomAccessFile? handle;
    try {
      handle = await file.open();
      final length = await handle.length();
      if (length <= 0) _fail(MailProblemCode.invalidInput);
      if (length > limits.maxManifestBytes) {
        _fail(MailProblemCode.quotaExceeded);
      }
      cancellation?.throwIfCancelled();
      final bytes = await handle.read(length);
      cancellation?.throwIfCancelled();
      if (bytes.length != length || await handle.length() != length) {
        _fail(MailProblemCode.conflict);
      }
      try {
        return utf8.decode(bytes);
      } on FormatException {
        _fail(MailProblemCode.invalidInput);
      }
    } finally {
      await handle?.close();
    }
  }

  Future<void> _export(
    MailArchiveExportPlan plan,
    _ExportOwner owner,
    String manifest,
    _ExportRun run,
    MailCancellationToken? cancellation,
  ) async {
    run.emit(MailArchiveExportPhase.started);
    for (var index = 0; index < plan.items.length; index++) {
      cancellation?.throwIfCancelled();
      await owner.check();
      final item = plan.items[index];
      try {
        final destination = File(p.join(owner.path, '${item.id}.eml'));
        final type = FileSystemEntity.typeSync(
          destination.path,
          followLinks: false,
        );
        if (type == FileSystemEntityType.file) {
          await _verifyFile(destination, item, cancellation);
          run.existing++;
          run.bytes += item.byteLength;
        } else if (type != FileSystemEntityType.notFound) {
          _fail(MailProblemCode.conflict);
        } else {
          final result = await loadOriginal(item.id);
          cancellation?.throwIfCancelled();
          final MailBytes original;
          switch (result) {
            case MailFailure(:final problem):
              _fail(problem.code);
            case MailSuccess(value: final bytes?):
              original = bytes;
            case MailSuccess():
              _fail(MailProblemCode.unavailable);
          }
          if (original.length != item.byteLength ||
              original.sha256 != item.id) {
            _fail(MailProblemCode.conflict);
          }
          await _publish(owner, destination, original, cancellation);
          // Publication is the accounting point. A later cancellation must not
          // erase the record of an original that is already durably exported.
          run.written++;
          run.bytes += item.byteLength;
        }
      } on Object catch (error) {
        final problem = _problem(error);
        if (problem.code == MailProblemCode.cancelled ||
            problem.code == MailProblemCode.staleOperation) {
          rethrow;
        }
        run.fail(index + 1, problem);
        if (problem.code == MailProblemCode.quotaExceeded ||
            problem.code == MailProblemCode.permissionDenied) {
          rethrow;
        }
      }
      run.emit(MailArchiveExportPhase.message);
      cancellation?.throwIfCancelled();
      // Yield to the event loop between originals, including already present
      // files, so cancellation and progress remain responsive on large jobs.
      await Future<void>.delayed(Duration.zero);
    }
    await owner.check();
    if (await _readManifest(owner.path, cancellation) != manifest) {
      _fail(MailProblemCode.conflict);
    }
  }

  Future<void> _verifyFile(
    File file,
    MailArchiveExportItem item,
    MailCancellationToken? cancellation,
  ) async {
    RandomAccessFile? handle;
    try {
      handle = await file.open();
      if (await handle.length() != item.byteLength) {
        _fail(MailProblemCode.conflict);
      }
      final result = _DigestSink();
      final digest = crypto.sha256.startChunkedConversion(result);
      try {
        var read = 0;
        while (read < item.byteLength) {
          cancellation?.throwIfCancelled();
          final remaining = item.byteLength - read;
          final bytes = await handle.read(
            remaining < 65536 ? remaining : 65536,
          );
          if (bytes.isEmpty) _fail(MailProblemCode.conflict);
          read += bytes.length;
          digest.add(bytes);
        }
        if (await handle.length() != item.byteLength) {
          _fail(MailProblemCode.conflict);
        }
      } finally {
        digest.close();
      }
      if (result.value?.toString() != item.id) _fail(MailProblemCode.conflict);
      cancellation?.throwIfCancelled();
    } finally {
      await handle?.close();
    }
  }

  Future<void> _publish(
    _ExportOwner owner,
    File destination,
    MailBytes bytes,
    MailCancellationToken? cancellation,
  ) async {
    await owner.check();
    cancellation?.throwIfCancelled();
    final temporary = await Directory(owner.path).createTemp('.pending-');
    final staged = File(p.join(temporary.path, 'original.eml'));
    try {
      await staged.writeAsBytes(bytes.bytes, flush: true);
      cancellation?.throwIfCancelled();
      await owner.check();
      if (FileSystemEntity.typeSync(destination.path, followLinks: false) !=
          FileSystemEntityType.notFound) {
        _fail(MailProblemCode.conflict);
      }
      await staged.rename(destination.path);
    } finally {
      // Only remove our own now-empty staging directory. Incomplete staging
      // files are left for diagnosis/recovery; resume ignores them entirely.
      try {
        await temporary.delete();
      } on Object {
        // Never turn an already published original into an apparent failure.
      }
    }
  }

  MailProblem _problem(Object error) {
    if (error is FileSystemException) {
      return MailProblem(switch (error.osError?.errorCode) {
        13 || 5 => MailProblemCode.permissionDenied,
        28 || 112 => MailProblemCode.quotaExceeded,
        17 || 80 || 183 => MailProblemCode.conflict,
        _ => MailProblemCode.unavailable,
      });
    }
    if (error is sqlite.SqliteException &&
        (error.resultCode == 5 || error.resultCode == 6)) {
      return const MailProblem(MailProblemCode.conflict);
    }
    return mailStoreProblem(error);
  }
}

final class _ExportOwner {
  _ExportOwner(this.path, this.database, this.ownerStat);
  final String path;
  final sqlite.Database database;
  final FileStat ownerStat;

  Future<void> check() async {
    final directory = Directory(path);
    if (FileSystemEntity.typeSync(path, followLinks: false) !=
            FileSystemEntityType.directory ||
        await directory.resolveSymbolicLinks() != path) {
      throw const MailStoreStorageException(MailProblemCode.conflict);
    }
    final ownerFile = File(p.join(path, '.export-owner.sqlite3'));
    if (FileSystemEntity.typeSync(ownerFile.path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw const MailStoreStorageException(MailProblemCode.conflict);
    }
    final current = ownerFile.statSync();
    if (current.size != ownerStat.size ||
        current.modified != ownerStat.modified ||
        current.changed != ownerStat.changed) {
      throw const MailStoreStorageException(MailProblemCode.conflict);
    }
    for (final name in [
      '.export-owner.sqlite3',
      '.export-owner.sqlite3-journal',
      '.export-owner.sqlite3-wal',
      '.export-owner.sqlite3-shm',
    ]) {
      final type = FileSystemEntity.typeSync(
        p.join(path, name),
        followLinks: false,
      );
      if (type != FileSystemEntityType.notFound &&
          type != FileSystemEntityType.file) {
        throw const MailStoreStorageException(MailProblemCode.conflict);
      }
    }
  }

  void close() {
    try {
      database.close();
    } on Object {
      // Keep the confirmed report. SQLite closes its process-owned file locks.
    } finally {
      NativeMailArchiveExporter._active.remove(path);
    }
  }
}

final class _DigestSink implements Sink<crypto.Digest> {
  crypto.Digest? value;
  @override
  void add(crypto.Digest data) => value = data;
  @override
  void close() {}
}

final class _ExportRun {
  _ExportRun(this.maxFailures, this.sink);
  final int maxFailures;
  final MailArchiveExportProgressSink? sink;
  final Stopwatch clock = Stopwatch()..start();
  int planned = 0;
  int written = 0;
  int existing = 0;
  int failed = 0;
  int bytes = 0;
  int observerErrors = 0;
  int droppedFailures = 0;
  String? directoryPath;
  MailProblem? firstProblem;
  final List<MailArchiveExportFailure> failures = [];

  void fail(int ordinal, MailProblem problem) {
    failed++;
    firstProblem ??= problem;
    if (failures.length < maxFailures) {
      failures.add(
        MailArchiveExportFailure(ordinal: ordinal, code: problem.code),
      );
    } else {
      droppedFailures++;
    }
  }

  void emit(
    MailArchiveExportPhase phase, {
    MailArchiveExportStatus? status,
    MailProblem? problem,
  }) {
    try {
      sink?.call(
        MailArchiveExportProgress(
          phase: phase,
          planned: planned,
          written: written,
          existing: existing,
          failed: failed,
          bytes: bytes,
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

  MailArchiveExportReport failedResult(MailProblem problem) => finish(
    problem.code == MailProblemCode.cancelled ||
            problem.code == MailProblemCode.staleOperation
        ? MailArchiveExportStatus.cancelled
        : written + existing > 0
        ? MailArchiveExportStatus.partial
        : MailArchiveExportStatus.failed,
    problem: problem,
  );

  MailArchiveExportReport finish(
    MailArchiveExportStatus status, {
    MailProblem? problem,
  }) {
    final terminalProblem = problem ?? firstProblem;
    emit(
      MailArchiveExportPhase.finished,
      status: status,
      problem: terminalProblem,
    );
    clock.stop();
    return MailArchiveExportReport(
      status: status,
      planned: planned,
      written: written,
      existing: existing,
      failed: failed,
      bytes: bytes,
      elapsedMicroseconds: clock.elapsedMicroseconds,
      observerErrors: observerErrors,
      failures: failures,
      droppedFailures: droppedFailures,
      directoryPath: directoryPath,
      problem: terminalProblem,
    );
  }
}
