import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:quds_tasks_core/quds_tasks_core.dart';

import 'dav_uri.dart';
import 'server_profile.dart';

final class DavFailure implements Exception {
  const DavFailure(this.code, {this.retryAfter, this.mutationMayHaveOccurred});

  final TaskProblemCode code;
  final Duration? retryAfter;
  final bool? mutationMayHaveOccurred;

  TaskProblem get problem => TaskProblem(
    code,
    retryAfter: retryAfter,
    mutationMayHaveOccurred: mutationMayHaveOccurred,
  );
}

final class DavHttp {
  DavHttp(this.settings, this.client, this.appPassword);

  static const _timeout = Duration(seconds: 30);
  static const _maxBytes = 16 * 1024 * 1024;
  final CalDavConnectionSettings settings;
  final http.Client client;
  final Future<String?> Function() appPassword;

  Future<http.Response> send(
    String method,
    Uri uri, {
    String? body,
    Map<String, String> headers = const {},
    bool mutation = false,
    bool allowDiscoveryRedirect = false,
  }) async {
    for (var hop = 0; ; hop++) {
      if (!safeDavUri(uri, settings.discoveryUrl)) {
        throw const DavFailure(TaskProblemCode.invalidResponse);
      }
      final response = await _send(
        method,
        uri,
        body: body,
        headers: headers,
        mutation: mutation,
      );
      if (!allowDiscoveryRedirect ||
          !const {301, 302, 307, 308}.contains(response.statusCode)) {
        return response;
      }
      final target = davHref(uri, response.headers['location'] ?? '');
      if (target == null || hop >= 2) {
        throw const DavFailure(TaskProblemCode.invalidResponse);
      }
      uri = target;
    }
  }

  Future<http.Response> _send(
    String method,
    Uri uri, {
    required String? body,
    required Map<String, String> headers,
    required bool mutation,
  }) async {
    String? password;
    try {
      password = await appPassword().timeout(_timeout);
    } on Exception {
      throw const DavFailure(TaskProblemCode.authenticationRequired);
    }
    if (password == null ||
        password.isEmpty ||
        password.length > 8192 ||
        settings.username.length > 4096 ||
        settings.username.contains(':') ||
        password.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
      throw const DavFailure(TaskProblemCode.authenticationRequired);
    }
    final abort = Completer<void>();
    final authorization = base64.encode(
      utf8.encode('${settings.username}:$password'),
    );
    final outgoing =
        http.AbortableRequest(method, uri, abortTrigger: abort.future)
          ..followRedirects = false
          ..maxRedirects = 0
          ..headers.addAll({
            ...headers,
            'authorization': 'Basic $authorization',
          });
    if (body != null) outgoing.bodyBytes = utf8.encode(body);

    Future<http.Response> exchange() async {
      final response = await client.send(outgoing);
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.stream) {
        if ((response.contentLength ?? 0) > _maxBytes ||
            bytes.length + chunk.length > _maxBytes) {
          throw DavFailure(
            TaskProblemCode.invalidResponse,
            mutationMayHaveOccurred: mutation,
          );
        }
        bytes.add(chunk);
      }
      return http.Response.bytes(
        bytes.takeBytes(),
        response.statusCode,
        headers: response.headers,
        request: outgoing,
      );
    }

    try {
      return await exchange().timeout(_timeout);
    } on DavFailure {
      rethrow;
    } on Exception {
      throw DavFailure(
        TaskProblemCode.unavailable,
        mutationMayHaveOccurred: mutation,
      );
    } finally {
      abort.complete();
    }
  }
}

Never davStatus(http.Response response, {bool mutation = false}) =>
    davStatusCode(
      response.statusCode,
      mutation: mutation,
      headers: response.headers,
    );

Never davStatusCode(
  int status, {
  bool mutation = false,
  Map<String, String> headers = const {},
}) {
  final code = switch (status) {
    401 => TaskProblemCode.authenticationRequired,
    403 => TaskProblemCode.permissionDenied,
    404 || 409 || 410 || 412 => TaskProblemCode.conflict,
    405 || 501 => TaskProblemCode.unsupported,
    429 => TaskProblemCode.throttled,
    507 => TaskProblemCode.quotaExceeded,
    >= 300 && < 400 => TaskProblemCode.invalidResponse,
    >= 500 => TaskProblemCode.unavailable,
    _ => TaskProblemCode.providerFailure,
  };
  const rejected = {400, 401, 403, 404, 405, 409, 410, 412, 415, 422, 429, 507};
  throw DavFailure(
    code,
    retryAfter: _retryAfter(headers['retry-after']),
    mutationMayHaveOccurred: mutation ? !rejected.contains(status) : null,
  );
}

Duration? _retryAfter(String? value) {
  if (value == null || value.length > 128) return null;
  final header = value.trim();
  final seconds = int.tryParse(header);
  if (seconds != null) {
    return seconds >= 0 && seconds <= 31536000
        ? Duration(seconds: seconds)
        : null;
  }
  try {
    final duration = parseHttpDate(header).difference(DateTime.now().toUtc());
    return duration.isNegative ? Duration.zero : duration;
  } on FormatException {
    return null;
  }
}
