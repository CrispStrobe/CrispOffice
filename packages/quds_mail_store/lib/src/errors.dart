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
