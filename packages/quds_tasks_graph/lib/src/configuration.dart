import 'package:quds_tasks_core/quds_tasks_core.dart';

/// A host supplies an account-bound Graph token, with delegated Tasks.ReadWrite.
/// Obtaining consent and storing/refreshing credentials belong to the host.
abstract interface class GraphTaskTokenSource {
  Future<String> accessToken({bool forceRefresh = false});
}

/// Lets a host preserve a typed authentication failure without exposing OAuth
/// response bodies or credentials to task diagnostics.
final class GraphTaskTokenException implements Exception {
  const GraphTaskTokenException(this.problem);

  final TaskProblem problem;

  @override
  String toString() => 'GraphTaskTokenException(${problem.code.name})';
}

/// Every call reads at most one page; pagination is controlled by the caller.
final class GraphTaskLimits {
  GraphTaskLimits({
    this.maxPageSize = 100,
    this.maxResponseItems = 1000,
    this.maxResponseBytes = 4 * 1024 * 1024,
    this.maxRequestBytes = 1024 * 1024,
    this.maxCursorBytes = 64 * 1024,
    this.maxUrlBytes = 24 * 1024,
    this.timeout = const Duration(seconds: 30),
  }) {
    if (maxPageSize < 1 ||
        maxPageSize > 1000 ||
        maxResponseItems < maxPageSize ||
        maxResponseItems > 10000 ||
        maxResponseBytes < 1024 ||
        maxResponseBytes > 32 * 1024 * 1024 ||
        maxRequestBytes < 128 ||
        maxRequestBytes > 4 * 1024 * 1024 ||
        maxCursorBytes < 128 ||
        maxCursorBytes > 128 * 1024 ||
        maxUrlBytes < 128 ||
        maxUrlBytes > 64 * 1024 ||
        timeout <= Duration.zero ||
        timeout > const Duration(minutes: 5)) {
      throw ArgumentError('Invalid Graph task limits.');
    }
  }

  final int maxPageSize;
  final int maxResponseItems;
  final int maxResponseBytes;
  final int maxRequestBytes;
  final int maxCursorBytes;
  final int maxUrlBytes;
  final Duration timeout;
}
