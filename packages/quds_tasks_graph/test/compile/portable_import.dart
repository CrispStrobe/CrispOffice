import 'package:quds_tasks_core/quds_tasks_core.dart';
import 'package:quds_tasks_graph/quds_tasks_graph.dart';

void main() {
  final provider = GraphTaskProvider(
    account: TaskAccountId('portable', provider: 'microsoftGraph'),
    transport: _Transport(),
    tokens: _Tokens(),
  );
  if (provider.capabilities.supports(TaskCapability.conditionalWrites)) {
    throw StateError('Unverified conditional writes must stay disabled.');
  }
  print('Portable Graph task adapter loaded.');
}

final class _Tokens implements GraphTaskTokenSource {
  @override
  Future<String> accessToken({bool forceRefresh = false}) async => 'unused';
}

final class _Transport implements GraphTaskHttpTransport {
  @override
  Future<GraphTaskHttpResponse> send(
    GraphTaskHttpRequest request, {
    required Duration timeout,
    required int maxResponseBytes,
  }) async => GraphTaskHttpResponse(statusCode: 401);
}
