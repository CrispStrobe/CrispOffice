import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../http.dart';

/// Verified TLS to the global Graph To Do endpoint only. Redirects are disabled
/// and deadlines/byte bounds are enforced while reading, not after buffering.
final class NativeGraphTaskHttpTransport implements GraphTaskHttpTransport {
  NativeGraphTaskHttpTransport() {
    _client.connectionTimeout = const Duration(seconds: 30);
    _client.idleTimeout = const Duration(seconds: 10);
    _client.maxConnectionsPerHost = 4;
  }

  final HttpClient _client = HttpClient();
  final Set<void Function()> _activeStops = {};
  bool _closed = false;

  static bool allowedUri(Uri uri) {
    final segments = uri.pathSegments;
    return uri.scheme == 'https' &&
        uri.host == 'graph.microsoft.com' &&
        uri.port == 443 &&
        uri.userInfo.isEmpty &&
        !uri.hasFragment &&
        uri.toString().length <= 64 * 1024 &&
        segments.length >= 4 &&
        segments[0] == 'v1.0' &&
        segments[1] == 'me' &&
        segments[2] == 'todo' &&
        segments[3] == 'lists' &&
        !segments.any(
          (segment) =>
              segment == '.' ||
              segment == '..' ||
              segment.contains(RegExp(r'[\x00-\x1f\x7f\\]')),
        );
  }

  @override
  Future<GraphTaskHttpResponse> send(
    GraphTaskHttpRequest request, {
    required Duration timeout,
    required int maxResponseBytes,
  }) async {
    if (!allowedUri(request.uri) ||
        !const {'GET', 'POST', 'PATCH', 'DELETE'}.contains(request.method) ||
        timeout <= Duration.zero ||
        timeout > const Duration(minutes: 5) ||
        maxResponseBytes < 1 ||
        maxResponseBytes > 32 * 1024 * 1024 ||
        request.body.length > 4 * 1024 * 1024 ||
        request.headers.entries.any(
          (entry) =>
              !const {
                'authorization',
                'accept',
                'prefer',
                'content-type',
              }.contains(entry.key.toLowerCase()) ||
              entry.key.contains(RegExp(r'[\x00-\x20\x7f:]')) ||
              entry.value.contains(RegExp(r'[\x00-\x1f\x7f]')),
        )) {
      throw const GraphTaskTransportException(
        GraphTaskTransportProblem.invalidRequest,
        requestMayHaveReachedServer: false,
      );
    }
    if (_closed) {
      throw const GraphTaskTransportException(
        GraphTaskTransportProblem.cancelled,
        requestMayHaveReachedServer: false,
      );
    }
    final result = Completer<GraphTaskHttpResponse>();
    HttpClientRequest? active;
    StreamSubscription<List<int>>? subscription;
    var sent = false;

    void interrupt(GraphTaskTransportProblem problem) {
      if (result.isCompleted) return;
      result.completeError(
        GraphTaskTransportException(problem, requestMayHaveReachedServer: sent),
      );
      try {
        active?.abort();
      } on Object {
        // Cleanup must not replace the original typed failure.
      }
      if (subscription case final stream?) unawaited(_cancel(stream));
    }

    void stop() => interrupt(GraphTaskTransportProblem.cancelled);
    _activeStops.add(stop);
    final timer = Timer(
      timeout,
      () => interrupt(GraphTaskTransportProblem.unavailable),
    );

    Future<void> run() async {
      try {
        final outgoing = await _client.openUrl(request.method, request.uri);
        active = outgoing;
        if (result.isCompleted || _closed) {
          outgoing.abort();
          interrupt(GraphTaskTransportProblem.cancelled);
          return;
        }
        outgoing.followRedirects = false;
        outgoing.maxRedirects = 0;
        request.headers.forEach(outgoing.headers.set);
        outgoing.contentLength = request.body.length;
        // Conservative boundary: bytes might be flushed by add/close.
        sent = true;
        if (request.body.isNotEmpty) outgoing.add(request.body);
        final incoming = await outgoing.close();
        if (result.isCompleted || _closed) {
          await _cancel(incoming.listen((_) {}));
          interrupt(GraphTaskTransportProblem.cancelled);
          return;
        }
        final headers = <String, String>{};
        var headerBytes = 0;
        incoming.headers.forEach((name, values) {
          final value = values.join(', ');
          headerBytes += name.length + value.length;
          if (headerBytes <= 64 * 1024) headers[name] = value;
        });
        if (headerBytes > 64 * 1024 ||
            incoming.contentLength > maxResponseBytes) {
          await _cancel(incoming.listen((_) {}));
          interrupt(GraphTaskTransportProblem.responseTooLarge);
          return;
        }
        final body = BytesBuilder(copy: false);
        subscription = incoming.listen(
          (chunk) {
            if (result.isCompleted) return;
            if (body.length + chunk.length > maxResponseBytes) {
              interrupt(GraphTaskTransportProblem.responseTooLarge);
              return;
            }
            body.add(chunk);
          },
          onError: (Object error, StackTrace stack) {
            interrupt(GraphTaskTransportProblem.unavailable);
          },
          onDone: () {
            if (!result.isCompleted) {
              result.complete(
                GraphTaskHttpResponse(
                  statusCode: incoming.statusCode,
                  headers: headers,
                  body: body.takeBytes(),
                ),
              );
            }
          },
          cancelOnError: true,
        );
      } on Object {
        interrupt(GraphTaskTransportProblem.unavailable);
      }
    }

    unawaited(run());
    try {
      return await result.future;
    } finally {
      timer.cancel();
      _activeStops.remove(stop);
      try {
        await subscription?.cancel();
      } on Object {
        // Cleanup must not replace a terminal operation result.
      }
    }
  }

  /// Aborts in-flight calls. Writes interrupted after dispatch remain uncertain.
  void close() {
    if (_closed) return;
    _closed = true;
    for (final stop in _activeStops.toList()) {
      stop();
    }
    _client.close(force: true);
  }
}

Future<void> _cancel(StreamSubscription<List<int>> subscription) async {
  try {
    await subscription.cancel();
  } on Object {
    // Response cleanup is best effort after a terminal result.
  }
}
