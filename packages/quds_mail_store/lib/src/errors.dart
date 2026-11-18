import 'package:drift/drift.dart' show DriftWrappedException;
// The worker protocol is versioned; this public error type is tested against
// exact-pinned Drift 2.35.4 and the matching host/worker build.
// ignore: experimental_member_use
import 'package:drift/remote.dart' show DriftRemoteException;
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:sqlite3/common.dart';

/// Content-free failure passed by a platform storage adapter.
final class MailStoreStorageException implements Exception {
  const MailStoreStorageException(this.code);
  final MailProblemCode code;

  @override
  String toString() => 'Mail storage failed (${code.name}).';
}

/// Never stringify a database exception: it may contain SQL and message bytes.
MailProblem mailStoreProblem(Object error) {
  // Native workers preserve typed causes inside protocol wrappers. Keep the
  // traversal bounded and never parse exception messages or stack traces.
  for (var depth = 0; depth < 8; depth++) {
    if (error is DriftRemoteException) {
      error = error.remoteCause;
    } else if (error is DriftWrappedException && error.cause != null) {
      error = error.cause!;
    } else {
      break;
    }
  }
  if (error is MailStoreStorageException) return MailProblem(error.code);
  if (error is MailCancelled) {
    return MailProblem(
      error.reason == MailCancellationReason.user ||
              error.reason == MailCancellationReason.budgetExpired
          ? MailProblemCode.cancelled
          : MailProblemCode.staleOperation,
    );
  }
  if (error is SqliteException) {
    return MailProblem(switch (error.extendedResultCode & 0xff) {
      7 || 13 => MailProblemCode.quotaExceeded,
      5 || 6 || 8 || 10 || 14 => MailProblemCode.unavailable,
      19 => MailProblemCode.conflict,
      4 || 9 => MailProblemCode.cancelled,
      _ => MailProblemCode.storageFailure,
    });
  }
  return const MailProblem(MailProblemCode.storageFailure);
}
