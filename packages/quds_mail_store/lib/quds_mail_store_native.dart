/// Native app-container storage. Import this entry only on Dart VM targets.
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import 'src/errors.dart';
import 'src/models.dart';
import 'src/owner_locked_executor.dart';
import 'src/platform_configuration.dart';
import 'src/repository.dart';

export 'quds_mail_store.dart';

/// Open one profile in the host's explicitly supplied application container.
///
/// The host resolves [appDirectory] using its platform application-support API.
/// This function never chooses a global path, stores credentials, or logs SQL.
/// A sibling SQLite transaction enforces a single live owner across connections,
/// isolates and processes. The operating system releases it after a crash.
Future<MailResult<SqliteMailRepository>> openNativeMailStore({
  required Directory appDirectory,
  required MailProfileId profile,
  MailStoreLimits limits = const MailStoreLimits(),
  DateTime Function()? clock,
  MailStoreFaultInjector? faultInjector,
}) async {
  sqlite.Database? owner;
  OwnerLockedMailExecutor? executor;
  try {
    if (!appDirectory.isAbsolute || !limits.isValid) {
      throw const MailStoreStorageException(MailProblemCode.invalidInput);
    }
    final namespace = mailStoreNamespace(profile);
    final directory = Directory(
      p.join(appDirectory.path, 'quds_mail', namespace),
    );
    await directory.create(recursive: true);
    owner = sqlite.sqlite3.open(p.join(directory.path, 'owner.sqlite3'));
    owner.execute('PRAGMA busy_timeout = 0');
    owner.execute('BEGIN EXCLUSIVE');
    final heldOwner = owner;
    executor = OwnerLockedMailExecutor(
      NativeDatabase.createInBackground(
        File(p.join(directory.path, 'mail.sqlite3')),
        setup: (database) {
          database.execute('PRAGMA journal_mode = WAL');
          database.execute('PRAGMA synchronous = FULL');
          database.execute('PRAGMA busy_timeout = 5000');
          database.execute('PRAGMA foreign_keys = ON');
        },
      ),
      () async => heldOwner.close(),
    );
    final result = await SqliteMailRepository.open(
      executor: executor,
      profile: profile,
      limits: limits,
      clock: clock,
      faultInjector: faultInjector,
    );
    if (result is MailFailure<SqliteMailRepository>) await executor.close();
    return result;
  } catch (error) {
    try {
      if (executor != null) {
        await executor.close();
      } else {
        owner?.close();
      }
    } catch (_) {
      // Preserve the sanitized failure that prevented opening.
    }
    if (error is sqlite.SqliteException &&
        (error.resultCode == 5 || error.resultCode == 6)) {
      return const MailFailure(MailProblem(MailProblemCode.conflict));
    }
    if (error is FileSystemException) {
      return MailFailure(
        MailProblem(switch (error.osError?.errorCode) {
          28 || 112 => MailProblemCode.quotaExceeded,
          13 || 5 => MailProblemCode.permissionDenied,
          _ => MailProblemCode.unavailable,
        }),
      );
    }
    return MailFailure(mailStoreProblem(error));
  }
}
