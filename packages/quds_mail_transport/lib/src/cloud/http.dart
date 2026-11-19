import 'package:quds_mail_core/quds_mail_core.dart';

/// Internal injectable byte boundary. Authentication and interpretation belong
/// to the provider; native IO enforces deadlines, byte bounds and no redirects.
abstract interface class MailCloudHttpTransport {
  Future<MailCloudHttpResponse> send(
    MailCloudHttpRequest request, {
    required MailOperationLease lease,
    required Duration timeout,
    required int maxResponseBytes,
  });
  void close();
}

final class MailCloudHttpRequest {
  MailCloudHttpRequest({
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
  String toString() => 'MailCloudHttpRequest(redacted)';
}

final class MailCloudHttpResponse {
  MailCloudHttpResponse({
    required this.statusCode,
    Map<String, String> headers = const {},
    List<int> body = const [],
  }) : headers = Map.unmodifiable(headers),
       body = List.unmodifiable(body);

  final int statusCode;
  final Map<String, String> headers;
  final List<int> body;

  @override
  String toString() => 'MailCloudHttpResponse($statusCode, redacted)';
}

final class MailCloudException implements Exception {
  const MailCloudException(
    this.problem, {
    this.requestMayHaveReachedServer = false,
  });

  final MailProblem problem;
  final bool requestMayHaveReachedServer;

  @override
  String toString() => 'MailCloudException(${problem.code.name})';
}
