import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:quds_mail_core/quds_mail_core.dart';

import '../http.dart';

/// Verified TLS only. The transport never follows redirects, including OAuth
/// token redirects, and cannot be configured with an arbitrary credential host.
final class NativeMailCloudHttpTransport implements MailCloudHttpTransport {
  NativeMailCloudHttpTransport({HttpClient? client})
    : _client = client ?? HttpClient() {
    _client.connectionTimeout = const Duration(seconds: 30);
    _client.idleTimeout = const Duration(seconds: 10);
    _client.maxConnectionsPerHost = 4;
  }

  final HttpClient _client;
  final Set<HttpClientRequest> _active = {};
  final Set<StreamSubscription<List<int>>> _responses = {};
  bool _closed = false;

  static bool allowedUri(Uri uri) {
    if (uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment ||
        uri.port != 443 ||
        uri.toString().length > 64 * 1024 ||
        uri.pathSegments.any(
          (part) =>
              part == '.' ||
              part == '..' ||
              part.contains(RegExp(r'[\x00-\x1f\x7f\\]')),
        )) {
      return false;
    }
    return switch (uri.host) {
      'gmail.googleapis.com' =>
        uri.path == '/gmail/v1/users/me/profile' ||
            uri.path.startsWith('/gmail/v1/users/me/labels') ||
            uri.path.startsWith('/gmail/v1/users/me/messages') ||
            uri.path == '/gmail/v1/users/me/history',
      'graph.microsoft.com' =>
        uri.path == '/v1.0/me' ||
            uri.path.startsWith('/v1.0/me/') ||
            uri.path.startsWith('/v1.0/users/') ||
            uri.path.startsWith('/v1.0/users('),
      'tasks.googleapis.com' =>
        uri.path == '/tasks/v1/users/@me/lists' ||
            ([5, 6].contains(uri.pathSegments.length) &&
                uri.pathSegments[0] == 'tasks' &&
                uri.pathSegments[1] == 'v1' &&
                uri.pathSegments[2] == 'lists' &&
                uri.pathSegments[4] == 'tasks' &&
                _googleIdSegment(uri.pathSegments[3]) &&
                (uri.pathSegments.length == 5 ||
                    _googleIdSegment(uri.pathSegments[5]))),
      'oauth2.googleapis.com' => uri.path == '/token' && !uri.hasQuery,
      'login.microsoftonline.com' =>
        RegExp(
              r'^/[A-Za-z0-9][A-Za-z0-9.-]{0,253}/oauth2/v2\.0/token$',
            ).hasMatch(uri.path) &&
            !uri.hasQuery,
      _ => false,
    };
  }

  static bool _googleIdSegment(String value) =>
      value.isNotEmpty && !value.contains('/');

  static bool _allowedTaskMethod(Uri uri, String method) =>
      switch (uri.pathSegments.length) {
        5 when uri.pathSegments[2] == 'lists' => const {
          'GET',
          'POST',
        }.contains(method),
        6 => const {'GET', 'PATCH', 'DELETE'}.contains(method),
        _ => method == 'GET',
      };

  @override
  Future<MailCloudHttpResponse> send(
    MailCloudHttpRequest request, {
    required MailOperationLease lease,
    required Duration timeout,
    required int maxResponseBytes,
  }) async {
    if (!allowedUri(request.uri) ||
        (request.uri.host == 'tasks.googleapis.com' &&
            !_allowedTaskMethod(request.uri, request.method)) ||
        !const {'GET', 'POST', 'PATCH', 'DELETE'}.contains(request.method) ||
        timeout <= Duration.zero ||
        timeout > const Duration(minutes: 5) ||
        maxResponseBytes < 1 ||
        maxResponseBytes > 128 * 1024 * 1024 ||
        request.body.length > 128 * 1024 * 1024) {
      throw const MailCloudException(MailProblem(MailProblemCode.invalidInput));
    }
    if (_closed) {
      throw const MailCloudException(MailProblem(MailProblemCode.cancelled));
    }
    HttpClientRequest? active;
    StreamSubscription<List<int>>? responseSubscription;
    Completer<void>? responseDone;
    var interrupted = false;
    var reachedServer = false;
    var completed = false;
    final interruption = Completer<MailCloudHttpResponse>();

    void cancelBody() {
      final subscription = responseSubscription;
      if (subscription == null) return;
      responseSubscription = null;
      _responses.remove(subscription);
      unawaited(_cancelResponse(subscription));
    }

    void interrupt(MailProblem problem) {
      if (interrupted) return;
      interrupted = true;
      try {
        active?.abort();
      } on Object {
        // Cleanup cannot replace the typed interruption.
      }
      cancelBody();
      final failure = MailCloudException(
        problem,
        requestMayHaveReachedServer: reachedServer,
      );
      if (responseDone case final done? when !done.isCompleted) {
        done.completeError(failure);
      }
      if (!interruption.isCompleted) {
        interruption.completeError(failure);
      }
    }

    final deadline = Timer(
      timeout,
      () => interrupt(const MailProblem(MailProblemCode.unavailable)),
    );
    final cancellation = Timer.periodic(const Duration(milliseconds: 25), (_) {
      if (!lease.isCurrent || _closed) {
        interrupt(
          MailProblem(
            lease.cancellation?.isCancelled == true || _closed
                ? MailProblemCode.cancelled
                : MailProblemCode.staleOperation,
          ),
        );
      }
    });

    Future<MailCloudHttpResponse> run() async {
      lease.checkCurrent();
      final outgoing = await _client.openUrl(request.method, request.uri);
      active = outgoing;
      if (interrupted || _closed) {
        outgoing.abort();
        throw const MailCloudException(MailProblem(MailProblemCode.cancelled));
      }
      _active.add(outgoing);
      lease.checkCurrent();
      outgoing.followRedirects = false;
      outgoing.maxRedirects = 0;
      outgoing.persistentConnection = true;
      request.headers.forEach(outgoing.headers.set);
      outgoing.contentLength = request.body.length;
      // Set this BEFORE any body write or close can flush authenticated bytes.
      reachedServer = true;
      if (request.body.isNotEmpty) outgoing.add(request.body);
      final incoming = await outgoing.close();
      if (interrupted || _closed || !lease.isCurrent) {
        // abort() no longer destroys a request after close() has completed.
        // Cancel even a late response explicitly instead of leaving its body
        // unread on a pooled authenticated connection.
        await _cancelResponse(incoming.listen((_) {}));
        lease.checkCurrent();
        throw const MailCloudException(
          MailProblem(MailProblemCode.cancelled),
          requestMayHaveReachedServer: true,
        );
      }
      if (incoming.contentLength > maxResponseBytes) {
        await _cancelResponse(incoming.listen((_) {}));
        throw const MailCloudException(
          MailProblem(MailProblemCode.quotaExceeded),
          requestMayHaveReachedServer: true,
        );
      }
      final bytes = BytesBuilder(copy: false);
      final done = Completer<void>();
      responseDone = done;
      responseSubscription = incoming.listen(
        (chunk) {
          if (done.isCompleted) return;
          try {
            lease.checkCurrent();
            if (interrupted || _closed) {
              throw const MailCloudException(
                MailProblem(MailProblemCode.cancelled),
                requestMayHaveReachedServer: true,
              );
            }
            if (bytes.length + chunk.length > maxResponseBytes) {
              throw const MailCloudException(
                MailProblem(MailProblemCode.quotaExceeded),
                requestMayHaveReachedServer: true,
              );
            }
            bytes.add(chunk);
          } on Object catch (error, stack) {
            done.completeError(error, stack);
            cancelBody();
          }
        },
        onError: (Object error, StackTrace stack) {
          if (!done.isCompleted) done.completeError(error, stack);
        },
        onDone: () {
          if (!done.isCompleted) done.complete();
        },
        cancelOnError: true,
      );
      _responses.add(responseSubscription!);
      await done.future;
      lease.checkCurrent();
      if (interrupted || _closed) {
        throw const MailCloudException(
          MailProblem(MailProblemCode.cancelled),
          requestMayHaveReachedServer: true,
        );
      }
      return MailCloudHttpResponse(
        statusCode: incoming.statusCode,
        headers: {
          // No provider-supplied arbitrary headers escape the IO boundary.
          'retry-after': ?incoming.headers.value(HttpHeaders.retryAfterHeader),
          'content-type': ?incoming.headers.value(
            HttpHeaders.contentTypeHeader,
          ),
        },
        body: bytes.takeBytes(),
      );
    }

    try {
      final response = await Future.any([run(), interruption.future]);
      completed = true;
      return response;
    } on MailCloudException {
      rethrow;
    } on MailCancelled {
      throw MailCloudException(
        MailProblem(
          lease.cancellation?.isCancelled == true || _closed
              ? MailProblemCode.cancelled
              : MailProblemCode.staleOperation,
        ),
        requestMayHaveReachedServer: reachedServer,
      );
    } on Object {
      throw MailCloudException(
        const MailProblem(MailProblemCode.unavailable),
        requestMayHaveReachedServer: reachedServer,
      );
    } finally {
      interrupted = true;
      deadline.cancel();
      cancellation.cancel();
      cancelBody();
      final outgoing = active;
      if (outgoing != null) {
        _active.remove(outgoing);
        if (!completed) {
          try {
            outgoing.abort();
          } on Object {
            // Preserve the original, redacted failure.
          }
        }
      }
    }
  }

  static Future<void> _cancelResponse(
    StreamSubscription<List<int>> subscription,
  ) async {
    try {
      await subscription.cancel();
    } on Object {
      // Cancellation failures are private; retain the original typed result.
    }
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    for (final request in _active) {
      try {
        request.abort();
      } on Object {
        // Continue releasing the remaining requests.
      }
    }
    _active.clear();
    for (final subscription in _responses.toList()) {
      unawaited(_cancelResponse(subscription));
    }
    _responses.clear();
    try {
      _client.close(force: true);
    } on Object {
      // Disposal remains idempotent even for a failing embedding transport.
    }
  }
}
