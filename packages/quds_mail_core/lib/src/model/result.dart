/// The only successful value for commands without a payload.
enum MailUnit { value }

enum MailProblemCode {
  unsupported,
  cancelled,
  staleOperation,
  authenticationRequired,
  permissionDenied,
  unavailable,
  quotaExceeded,
  invalidInput,
  conflict,
  providerFailure,
  storageFailure,
}

/// No raw server text, mail content, endpoint credentials or tokens are retained.
final class MailProblem {
  const MailProblem(this.code, {this.retryAfter, this.mutationMayHaveOccurred});
  final MailProblemCode code;
  final Duration? retryAfter;

  /// Evidence from the provider's mutation boundary for this failed operation.
  ///
  /// False certifies that the operation did not mutate remote state. True means
  /// a write may have reached the server without confirmation. Null means the
  /// provider supplied no such evidence and must be treated conservatively.
  /// A problem code alone cannot establish whether a write was dispatched.
  final bool? mutationMayHaveOccurred;
}

sealed class MailResult<T> {
  const MailResult();
}

final class MailSuccess<T> extends MailResult<T> {
  const MailSuccess(this.value);
  final T value;
}

final class MailFailure<T> extends MailResult<T> {
  const MailFailure(this.problem);
  final MailProblem problem;
}
