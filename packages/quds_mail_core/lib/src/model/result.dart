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
  const MailProblem(this.code, {this.retryAfter});
  final MailProblemCode code;
  final Duration? retryAfter;
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
