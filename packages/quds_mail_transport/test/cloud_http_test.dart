import 'dart:async';
import 'dart:io';

import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_transport/src/cloud/configuration.dart';
import 'package:quds_mail_transport/src/cloud/http.dart';
import 'package:quds_mail_transport/src/cloud/native/http.dart';
import 'package:test/test.dart';

final _account = MailAccountId(
  'cloud-http',
  profile: MailProfileId('tests', hostId: 'crisp-office.test'),
);
final _uri = Uri.https('gmail.googleapis.com', '/gmail/v1/users/me/profile');
const _secret = 'bearer-secret-never-in-diagnostics';

final class _Headers implements HttpHeaders {
  final values = <String, String>{};

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    values[name.toLowerCase()] = value.toString();
  }

  @override
  String? value(String name) => values[name.toLowerCase()];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected HTTP headers fixture operation');
}

final class _Response extends Stream<List<int>> implements HttpClientResponse {
  _Response({
    this.statusCode = 200,
    this.contentLength = -1,
    Stream<List<int>>? stream,
    Map<String, String> headers = const {},
  }) : _stream = stream ?? Stream.value([1, 2, 3]) {
    headers.forEach(this.headers.set);
  }

  final Stream<List<int>> _stream;
  int subscriptions = 0;
  @override
  final int statusCode;
  @override
  final int contentLength;
  @override
  final _Headers headers = _Headers();

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    subscriptions++;
    return _stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected HTTP response fixture operation');
}

final class _Request implements HttpClientRequest {
  _Request({Future<HttpClientResponse> Function()? onClose})
    : _onClose = onClose ?? (() async => _Response());

  final Future<HttpClientResponse> Function() _onClose;
  final bytes = <int>[];
  int closeCalls = 0;
  int abortCalls = 0;
  @override
  final _Headers headers = _Headers();
  @override
  bool followRedirects = true;
  @override
  int maxRedirects = 5;
  @override
  bool persistentConnection = false;
  @override
  int contentLength = -1;

  @override
  void add(List<int> data) => bytes.addAll(data);

  @override
  Future<HttpClientResponse> close() {
    closeCalls++;
    return _onClose();
  }

  @override
  void abort([Object? exception, StackTrace? stackTrace]) => abortCalls++;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected HTTP request fixture operation');
}

final class _Client implements HttpClient {
  _Client(this.onOpen);
  final Future<HttpClientRequest> Function(String, Uri) onOpen;
  final opened = <(String, Uri)>[];
  int closeCalls = 0;
  bool? lastForce;
  @override
  Duration? connectionTimeout;
  @override
  Duration idleTimeout = Duration.zero;
  @override
  int? maxConnectionsPerHost;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) {
    opened.add((method, url));
    return onOpen(method, url);
  }

  @override
  void close({bool force = false}) {
    closeCalls++;
    lastForce = force;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected HTTP client fixture operation');
}

Matcher _problem(MailProblemCode code, {bool? reached}) =>
    isA<MailCloudException>()
        .having((e) => e.problem.code, 'problem', code)
        .having(
          (e) => e.requestMayHaveReachedServer,
          'requestMayHaveReachedServer',
          reached ?? anything,
        );

void main() {
  group('cloud request boundaries', () {
    test('whitelists public-cloud endpoints with verified HTTPS', () {
      for (final value in [
        'https://gmail.googleapis.com/gmail/v1/users/me/profile',
        'https://gmail.googleapis.com/gmail/v1/users/me/labels',
        'https://gmail.googleapis.com/gmail/v1/users/me/messages/abc?format=raw',
        'https://gmail.googleapis.com/gmail/v1/users/me/history?startHistoryId=8',
        'https://graph.microsoft.com/v1.0/me',
        'https://graph.microsoft.com/v1.0/me/mailFolders/inbox/messages',
        'https://graph.microsoft.com/v1.0/users/bound-identity/messages',
        'https://oauth2.googleapis.com/token',
        'https://tasks.googleapis.com/tasks/v1/users/@me/lists',
        'https://tasks.googleapis.com/tasks/v1/lists/id/tasks?pageToken=opaque',
        'https://tasks.googleapis.com/tasks/v1/lists/id/tasks/task-id',
        'https://login.microsoftonline.com/common/oauth2/v2.0/token',
      ]) {
        expect(
          NativeMailCloudHttpTransport.allowedUri(Uri.parse(value)),
          isTrue,
          reason: value,
        );
      }
      for (final value in [
        'http://gmail.googleapis.com/gmail/v1/users/me/profile',
        'https://gmail.googleapis.com:444/gmail/v1/users/me/profile',
        'https://gmail.googleapis.com.evil.test/gmail/v1/users/me/profile',
        'https://secret@gmail.googleapis.com/gmail/v1/users/me/profile',
        'https://gmail.googleapis.com/gmail/v1/users/someone/profile',
        'https://graph.microsoft.com/beta/me/messages',
        'https://graph.microsoft.com/v1.0/me/messages#secret',
        'https://graph.microsoft.com/v1.0/me/%5csecrets',
        'https://oauth2.googleapis.com/token?forward=secret',
        'https://tasks.googleapis.com/tasks/v1/lists/id/tasks/other/move',
        'https://tasks.googleapis.com/tasks/v1/lists/id%2Fother/tasks',
        'https://tasks.googleapis.com.evil.test/tasks/v1/users/@me/lists',
        'https://login.microsoftonline.com/common/oauth2/v2.0/token?x=1',
        'https://example.test/token',
      ]) {
        expect(
          NativeMailCloudHttpTransport.allowedUri(Uri.parse(value)),
          isFalse,
          reason: value,
        );
      }
    });

    test('request and response freeze caller-owned collections', () {
      final headers = {'authorization': _secret};
      final bytes = [1, 2, 3];
      final request = MailCloudHttpRequest(
        method: 'POST',
        uri: _uri,
        headers: headers,
        body: bytes,
      );
      final response = MailCloudHttpResponse(
        statusCode: 200,
        headers: headers,
        body: bytes,
      );
      headers.clear();
      bytes.clear();
      expect(request.headers['authorization'], _secret);
      expect(response.headers['authorization'], _secret);
      expect(request.body, [1, 2, 3]);
      expect(response.body, [1, 2, 3]);
      expect(() => request.body.add(4), throwsUnsupportedError);
      expect(() => response.headers.clear(), throwsUnsupportedError);
      expect(request.toString(), isNot(contains(_secret)));
      expect(response.toString(), isNot(contains(_secret)));
    });

    test('debug diagnostics expose only structured non-secret fields', () {
      final event = MailCloudLogEvent(
        service: MailCloudService.gmail,
        operation: MailCloudOperation.refreshToken,
        stage: MailCloudLogStage.failed,
        statusCode: 401,
        elapsedMilliseconds: 25,
        requestBytes: 30,
        responseBytes: 40,
        itemCount: 0,
        attempt: 1,
        problemCode: MailProblemCode.authenticationRequired,
        retryAfterSeconds: 5,
      );
      expect(event.toJson(), {
        'service': 'gmail',
        'operation': 'refreshToken',
        'stage': 'failed',
        'statusCode': 401,
        'elapsedMilliseconds': 25,
        'requestBytes': 30,
        'responseBytes': 40,
        'itemCount': 0,
        'attempt': 1,
        'problemCode': 'authenticationRequired',
        'retryAfterSeconds': 5,
      });
      expect(
        () => emitMailCloudLog((_) => throw StateError(_secret), event),
        returnsNormally,
      );
      expect(event.toString(), isNot(contains(_secret)));
      expect(
        MailCloudAccessToken(
          value: _secret,
          expiresAt: DateTime(2030),
        ).toString(),
        isNot(contains(_secret)),
      );
    });
  });

  group('native cloud HTTP', () {
    late MailAccountSession session;
    late MailOperationLease lease;
    late _Request outgoing;
    late _Client client;
    late NativeMailCloudHttpTransport transport;

    setUp(() {
      session = MailAccountSession(_account);
      lease = session.begin();
      outgoing = _Request();
      client = _Client((_, _) async => outgoing);
      transport = NativeMailCloudHttpTransport(client: client);
    });
    tearDown(() {
      transport.close();
      session.dispose();
    });

    Future<MailCloudHttpResponse> send({
      MailCloudHttpRequest? request,
      Duration timeout = const Duration(seconds: 1),
      int limit = 1024,
      MailOperationLease? operation,
    }) => transport.send(
      request ?? MailCloudHttpRequest(method: 'GET', uri: _uri),
      lease: operation ?? lease,
      timeout: timeout,
      maxResponseBytes: limit,
    );

    test(
      'disables redirects and forwards auth only to the permitted URL',
      () async {
        outgoing = _Request(
          onClose: () async => _Response(
            statusCode: 302,
            headers: {
              'location': 'https://evil.test/steal',
              'set-cookie': _secret,
            },
          ),
        );
        final result = await send(
          request: MailCloudHttpRequest(
            method: 'POST',
            uri: _uri,
            headers: {'authorization': 'Bearer $_secret'},
            body: [4, 5],
          ),
        );
        expect(result.statusCode, 302);
        expect(result.headers, isEmpty);
        expect(client.opened, [('POST', _uri)]);
        expect(outgoing.followRedirects, isFalse);
        expect(outgoing.maxRedirects, 0);
        expect(outgoing.headers.values['authorization'], 'Bearer $_secret');
        expect(outgoing.contentLength, 2);
        expect(outgoing.bytes, [4, 5]);
        expect(outgoing.abortCalls, 0);
      },
    );

    test('rejects off-host credentials before opening a socket', () async {
      await expectLater(
        send(
          request: MailCloudHttpRequest(
            method: 'GET',
            uri: Uri.https('evil.test', '/'),
            headers: {'authorization': _secret},
          ),
        ),
        throwsA(_problem(MailProblemCode.invalidInput, reached: false)),
      );
      expect(client.opened, isEmpty);
    });

    test('rejects invalid timeout, limits and method before IO', () async {
      for (final future in [
        send(timeout: Duration.zero),
        send(timeout: const Duration(minutes: 6)),
        send(limit: 0),
        send(limit: 128 * 1024 * 1024 + 1),
        send(
          request: MailCloudHttpRequest(method: 'CONNECT', uri: _uri),
        ),
      ]) {
        await expectLater(
          future,
          throwsA(_problem(MailProblemCode.invalidInput)),
        );
      }
      expect(client.opened, isEmpty);
    });

    test('stale lease is rejected before connection', () async {
      session.invalidate();
      await expectLater(
        send(),
        throwsA(_problem(MailProblemCode.staleOperation, reached: false)),
      );
      expect(client.opened, isEmpty);
    });

    test(
      'returns exact streamed bytes and only the response-header allowlist',
      () async {
        outgoing = _Request(
          onClose: () async => _Response(
            stream: Stream.fromIterable([
              [0, 127],
              [128, 255],
            ]),
            headers: {
              'retry-after': '7',
              'content-type': 'application/json',
              'authorization': _secret,
              'x-private': _secret,
            },
          ),
        );
        final result = await send(limit: 4);
        expect(result.body, [0, 127, 128, 255]);
        expect(result.headers, {
          'retry-after': '7',
          'content-type': 'application/json',
        });
      },
    );

    test(
      'declared oversize response retires the unread response stream',
      () async {
        var cancelled = false;
        final body = StreamController<List<int>>(
          onCancel: () => cancelled = true,
        );
        final response = _Response(contentLength: 1025, stream: body.stream);
        outgoing = _Request(onClose: () async => response);
        await expectLater(
          send(),
          throwsA(_problem(MailProblemCode.quotaExceeded, reached: true)),
        );
        expect(cancelled, isTrue);
        expect(outgoing.abortCalls, 1);
        await body.close();
      },
    );

    test(
      'streaming response overflow cancels subscription and aborts request',
      () async {
        var cancelled = false;
        final body = StreamController<List<int>>(
          onCancel: () => cancelled = true,
        );
        outgoing = _Request(
          onClose: () async => _Response(stream: body.stream),
        );
        final result = send(limit: 3);
        body.add([1, 2]);
        body.add([3, 4]);
        await expectLater(
          result,
          throwsA(_problem(MailProblemCode.quotaExceeded, reached: true)),
        );
        expect(cancelled, isTrue);
        expect(outgoing.abortCalls, 1);
        await body.close();
      },
    );

    test(
      'deadline before open completes aborts a late request without auth',
      () async {
        final opened = Completer<HttpClientRequest>();
        client = _Client((_, _) => opened.future);
        transport.close();
        transport = NativeMailCloudHttpTransport(client: client);
        final result = send(
          timeout: const Duration(milliseconds: 20),
          request: MailCloudHttpRequest(
            method: 'GET',
            uri: _uri,
            headers: {'authorization': _secret},
          ),
        );
        await expectLater(
          result,
          throwsA(_problem(MailProblemCode.unavailable, reached: false)),
        );
        opened.complete(outgoing);
        await Future<void>.delayed(Duration.zero);
        expect(outgoing.abortCalls, 1);
        expect(outgoing.headers.values, isEmpty);
        expect(outgoing.closeCalls, 0);
      },
    );

    test(
      'deadline after close discards and cancels a late response stream',
      () async {
        final closed = Completer<HttpClientResponse>();
        outgoing = _Request(onClose: () => closed.future);
        final result = send(timeout: const Duration(milliseconds: 20));
        await expectLater(
          result,
          throwsA(_problem(MailProblemCode.unavailable, reached: true)),
        );
        var cancelled = false;
        final body = StreamController<List<int>>(
          onCancel: () => cancelled = true,
        );
        closed.complete(_Response(stream: body.stream));
        await Future<void>.delayed(Duration.zero);
        expect(cancelled, isTrue);
        expect(outgoing.closeCalls, 1);
        await body.close();
      },
    );

    test(
      'deadline cancels a response body even when request abort cannot',
      () async {
        var cancelled = false;
        final body = StreamController<List<int>>(
          onCancel: () => cancelled = true,
        );
        outgoing = _Request(
          onClose: () async => _Response(stream: body.stream),
        );
        await expectLater(
          send(timeout: const Duration(milliseconds: 20)),
          throwsA(_problem(MailProblemCode.unavailable, reached: true)),
        );
        expect(cancelled, isTrue);
        await body.close();
      },
    );

    test('cancellation aborts a request stalled awaiting a response', () async {
      final source = MailCancellationSource();
      final closed = Completer<HttpClientResponse>();
      outgoing = _Request(onClose: () => closed.future);
      final result = send(operation: session.begin(cancellation: source.token));
      await Future<void>.delayed(Duration.zero);
      source.cancel();
      await expectLater(
        result,
        throwsA(_problem(MailProblemCode.cancelled, reached: true)),
      );
      var cancelled = false;
      final body = StreamController<List<int>>(
        onCancel: () => cancelled = true,
      );
      closed.complete(_Response(stream: body.stream));
      await Future<void>.delayed(Duration.zero);
      expect(cancelled, isTrue);
      await body.close();
    });

    test('invalidating session during IO rejects the stale result', () async {
      final closed = Completer<HttpClientResponse>();
      outgoing = _Request(onClose: () => closed.future);
      final result = send();
      await Future<void>.delayed(Duration.zero);
      session.invalidate();
      closed.complete(_Response());
      await expectLater(
        result,
        throwsA(_problem(MailProblemCode.staleOperation, reached: true)),
      );
    });

    test(
      'close aborts active work and future sends; close is idempotent',
      () async {
        final closed = Completer<HttpClientResponse>();
        outgoing = _Request(onClose: () => closed.future);
        final result = send();
        await Future<void>.delayed(Duration.zero);
        transport.close();
        await expectLater(
          result,
          throwsA(_problem(MailProblemCode.cancelled, reached: true)),
        );
        await expectLater(
          send(),
          throwsA(_problem(MailProblemCode.cancelled, reached: false)),
        );
        transport.close();
        expect(client.closeCalls, 1);
        expect(client.lastForce, isTrue);
        expect(outgoing.abortCalls, greaterThanOrEqualTo(1));
        closed.complete(_Response());
        await Future<void>.delayed(Duration.zero);
      },
    );

    test(
      'unexpected open failure is caught and does not retain raw secrets',
      () async {
        client = _Client((_, _) async => throw StateError(_secret));
        transport.close();
        transport = NativeMailCloudHttpTransport(client: client);
        try {
          await send();
          fail('Expected a redacted transport failure');
        } on MailCloudException catch (error) {
          expect(error.problem.code, MailProblemCode.unavailable);
          expect(error.requestMayHaveReachedServer, isFalse);
          expect(error.toString(), isNot(contains(_secret)));
        }
      },
    );

    test(
      'TLS and body stream failures are caught after request dispatch',
      () async {
        for (final error in [
          const HandshakeException(_secret),
          StateError(_secret),
        ]) {
          outgoing = _Request(
            onClose: () async =>
                _Response(stream: Stream<List<int>>.error(error)),
          );
          await expectLater(
            send(),
            throwsA(_problem(MailProblemCode.unavailable, reached: true)),
          );
          expect(outgoing.abortCalls, 1);
        }
      },
    );
  });
}
