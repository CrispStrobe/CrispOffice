enum TaskUnit { value }

enum TaskProblemCode {
  unsupported,
  cancelled,
  staleOperation,
  authenticationRequired,
  permissionDenied,
  unavailable,
  throttled,
  quotaExceeded,
  invalidInput,
  invalidResponse,
  cursorExpired,
  conflict,
  providerFailure,
  storageFailure,
}

/// Deliberately excludes raw server text, task content and credentials.
final class TaskProblem {
  const TaskProblem(this.code, {this.retryAfter, this.mutationMayHaveOccurred});
  final TaskProblemCode code;
  final Duration? retryAfter;

  /// True or unknown requires reconciliation before retrying a write; an error
  /// code alone cannot establish that the server did not apply the operation.
  final bool? mutationMayHaveOccurred;
}

sealed class TaskResult<T> {
  const TaskResult();
}

final class TaskSuccess<T> extends TaskResult<T> {
  const TaskSuccess(this.value);
  final T value;
}

final class TaskFailure<T> extends TaskResult<T> {
  const TaskFailure(this.problem);
  final TaskProblem problem;
}
