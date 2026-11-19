/// Native durable mail archive. Import only on Dart VM targets.
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import 'src/archive_models.dart';
import 'src/archive_repository.dart';
import 'src/errors.dart';
import 'src/owner_locked_executor.dart';
import 'src/platform_configuration.dart';

export 'quds_mail_store.dart';
export 'src/archive_directory_native.dart';
export 'src/archive_export_native.dart';

/// A separate archive database under an explicit application-support container.
/// SQLite FULL/WAL commits and a process-scoped exclusive owner protect writes.
/// No account cache cleanup can address this namespace.
Future<MailResult<SqliteMailArchive>> openNativeMailArchive({
  required Directory appDirectory,
  required MailProfileId profile,
  MailArchiveLimits limits = const MailArchiveLimits(),
  DateTime Function()? clock,
  MailArchiveDiagnostics? diagnostics,
  MailArchiveFaultInjector? faultInjector,
}) async {
  final watch = Stopwatch()..start();
  sqlite.Database? owner;
  OwnerLockedMailExecutor? executor;
  try {
    if (!appDirectory.isAbsolute || !limits.isValid) {
      throw const MailStoreStorageException(MailProblemCode.invalidInput);
    }
    final directory = Directory(
      p.join(
        appDirectory.path,
        'quds_mail_archive',
        mailStoreNamespace(profile),
      ),
    );
    await directory.create(recursive: true);
    owner = sqlite.sqlite3.open(p.join(directory.path, 'owner.sqlite3'));
    owner.execute('PRAGMA busy_timeout = 0');
    owner.execute('BEGIN EXCLUSIVE');
    final heldOwner = owner;
    executor = OwnerLockedMailExecutor(
      NativeDatabase.createInBackground(
        File(p.join(directory.path, 'archive.sqlite3')),
        setup: (database) {
          database.execute('PRAGMA journal_mode = WAL');
          database.execute('PRAGMA synchronous = FULL');
          database.execute('PRAGMA busy_timeout = 5000');
          database.execute('PRAGMA foreign_keys = ON');
        },
      ),
      () async => heldOwner.close(),
    );
    final result = await SqliteMailArchive.open(
      executor: executor,
      profile: profile,
      limits: limits,
      clock: clock,
      diagnostics: diagnostics,
      faultInjector: faultInjector,
    );
    if (result is MailFailure<SqliteMailArchive>) await executor.close();
    return result;
  } on Object catch (error) {
    try {
      if (executor != null) {
        await executor.close();
      } else {
        owner?.close();
      }
    } on Object {
      // Preserve the sanitized opening failure.
    }
    final MailProblem problem;
    if (error is sqlite.SqliteException &&
        (error.resultCode == 5 || error.resultCode == 6)) {
      problem = const MailProblem(MailProblemCode.conflict);
    } else if (error is FileSystemException) {
      problem = MailProblem(switch (error.osError?.errorCode) {
        28 || 112 => MailProblemCode.quotaExceeded,
        13 || 5 => MailProblemCode.permissionDenied,
        _ => MailProblemCode.unavailable,
      });
    } else {
      problem = mailStoreProblem(error);
    }
    try {
      diagnostics?.sink(
        MailArchiveDiagnostic(
          operationId: 0,
          operation: MailArchiveOperation.open,
          phase: MailArchivePhase.failed,
          elapsedMicroseconds: watch.elapsedMicroseconds,
          problem: problem.code,
        ),
      );
    } on Object {
      // Logging is observational even when ownership or filesystem setup fails.
    }
    return MailFailure(problem);
  }
}
