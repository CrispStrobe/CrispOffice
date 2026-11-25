/// Byte transport. Implementations MUST enforce the deadline and response byte
/// limit while receiving data, use verified HTTPS, and never follow redirects.
/// They MUST NOT retry mutations. The provider also checks returned bounds.
abstract interface class GraphTaskHttpTransport {
  Future<GraphTaskHttpResponse> send(
    GraphTaskHttpRequest request, {
    required Duration timeout,
    required int maxResponseBytes,
  });
}

final class GraphTaskHttpRequest {
  GraphTaskHttpRequest({
    required this.method,
    required this.uri,
    Map<String, String> headers = const {},
    List<int> body = const [],
  }) : headers = Map.unmodifiable(headers),
       body = List.unmodifiable(body);

  final String method;
  final Uri uri;
  final Map<String, String> headers;
  final List<int> body;

  @override
  String toString() => 'GraphTaskHttpRequest($method, redacted)';
}

final class GraphTaskHttpResponse {
  GraphTaskHttpResponse({
    required this.statusCode,
    Map<String, String> headers = const {},
    List<int> body = const [],
  }) : headers = Map.unmodifiable(headers),
       body = List.unmodifiable(body);

  final int statusCode;
  final Map<String, String> headers;
  final List<int> body;

  @override
  String toString() => 'GraphTaskHttpResponse($statusCode, redacted)';
}

enum GraphTaskTransportProblem {
  unavailable,
  cancelled,
  invalidRequest,
  responseTooLarge,
}

/// A failed transport cannot generally determine whether a write was accepted.
/// False is allowed only when no authenticated request bytes could be sent.
final class GraphTaskTransportException implements Exception {
  const GraphTaskTransportException(
    this.problem, {
    required this.requestMayHaveReachedServer,
  });

  final GraphTaskTransportProblem problem;
  final bool requestMayHaveReachedServer;

  @override
  String toString() => 'GraphTaskTransportException(${problem.name})';
}
