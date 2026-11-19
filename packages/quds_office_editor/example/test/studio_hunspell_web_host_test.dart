// Exercises the web host's HTTP contract on the VM using real loopback I/O.
// This does not claim browser, Worker, or WebAssembly execution.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:quds_office_studio/studio_hunspell_host.dart';
import 'package:quds_office_studio/studio_hunspell_host_web.dart';
import 'package:quds_proofing_hunspell/quds_proofing_hunspell.dart';

enum _ResponseMode { complete, stalledHeaders, stalledBody }

final _files = <String, List<int>>{
  'ar.aff': utf8.encode('SET UTF-8\n'),
  'ar.dic': utf8.encode('1\nword\n'),
};

HunspellArtifact _artifact(String name) =>
    HunspellArtifact(name, sha256Hex(_files[name]!), _files[name]!.length);

final _bundle = HunspellBundleDownload(
  id: 'web-cancellation-fixture',
  displayName: 'Web cancellation fixture',
  languages: const {'ar'},
  repository: 'test/fixture',
  revision: '0000000000000000000000000000000000000000',
  license: 'Test fixture',
  aff: _artifact('ar.aff'),
  dic: _artifact('ar.dic'),
  notices: const [],
);

final _cancelled = isA<StateError>().having(
  (error) => error.message,
  'message',
  'Download cancelled.',
);

void main() {
  late _Server fixture;
  late WebStudioHunspellHost host;
  final clients = <_RedirectingClient>[];

  setUp(() async {
    fixture = await _Server.start();
    clients.clear();
    host = WebStudioHunspellHost(
      catalog: [_bundle],
      client: () {
        final client = _RedirectingClient(fixture);
        clients.add(client);
        return client;
      },
    );
  });

  tearDown(() async {
    for (final client in clients) {
      client.close();
    }
    await fixture.close();
    host.dispose();
  });

  void expectAbsent() {
    expect(host.status(_bundle).installed, isFalse);
    expect(host.configurationKey, isEmpty);
  }

  Future<void> retry() async {
    fixture.mode = _ResponseMode.complete;
    await host.install(_bundle).timeout(const Duration(seconds: 3));
    expect(host.status(_bundle).installed, isTrue);
    expect(host.status(_bundle).problem, isNull);
    expect(host.configurationKey, '${_bundle.id}@${_bundle.revision}');
  }

  test('already-cancelled web install does not create a client', () async {
    final cancellation = StudioHunspellCancellation()..cancel();
    await expectLater(
      host.install(_bundle, cancellation: cancellation),
      throwsA(_cancelled),
    );
    expect(clients, isEmpty);
    expect(fixture.requests, 0);
    expectAbsent();
  });

  for (final mode in [
    _ResponseMode.stalledHeaders,
    _ResponseMode.stalledBody,
  ]) {
    test('web cancellation aborts ${mode.name} and permits a retry', () async {
      fixture.mode = mode;
      final cancellation = StudioHunspellCancellation();
      addTearDown(cancellation.cancel);
      final received = Completer<void>();
      final outcome = expectLater(
        host.install(
          _bundle,
          cancellation: cancellation,
          onProgress: (_, _) {
            if (!received.isCompleted) received.complete();
          },
        ),
        throwsA(_cancelled),
      );
      await (mode == _ResponseMode.stalledHeaders
              ? fixture.started.future
              : received.future)
          .timeout(const Duration(seconds: 3));
      final client = clients.single;
      expect(client.requests.single, isA<http.Abortable>());
      cancellation.cancel();
      await outcome.timeout(const Duration(seconds: 3));
      expect(client.closed, isTrue);
      expect(fixture.requests, 1);
      expectAbsent();
      expect(host.status(_bundle).problem, contains('Download cancelled.'));
      await retry();
    });
  }

  test(
    'web cancellation on final progress cannot publish verified bytes',
    () async {
      final cancellation = StudioHunspellCancellation();
      await expectLater(
        host.install(
          _bundle,
          cancellation: cancellation,
          onProgress: (received, total) {
            if (received == total) cancellation.cancel();
          },
        ),
        throwsA(_cancelled),
      );
      expectAbsent();
      await retry();
    },
  );
}

/// Preserves the host's abort trigger while redirecting only the transport URL.
final class _RedirectingClient extends http.BaseClient {
  _RedirectingClient(this.fixture);

  final _Server fixture;
  final _inner = IOClient();
  final requests = <http.BaseRequest>[];
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    requests.add(request);
    return _inner.send(
      http.AbortableRequest(
        request.method,
        fixture.url(request.url.pathSegments.last),
        abortTrigger: request is http.Abortable ? request.abortTrigger : null,
      ),
    );
  }

  @override
  void close() {
    closed = true;
    _inner.close();
  }
}

final class _Server {
  _Server(this.server) {
    server.listen((request) {
      unawaited(
        _respond(request).catchError((Object error, StackTrace stack) {
          if (error is! HttpException && error is! SocketException) {
            Error.throwWithStackTrace(error, stack);
          }
        }),
      );
    });
  }

  final HttpServer server;
  final started = Completer<void>();
  _ResponseMode mode = _ResponseMode.complete;
  int requests = 0;

  static Future<_Server> start() async =>
      _Server(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));

  Uri url(String file) => Uri.http('127.0.0.1:${server.port}', '/$file');

  Future<void> _respond(HttpRequest request) async {
    requests++;
    if (!started.isCompleted) started.complete();
    if (mode == _ResponseMode.stalledHeaders) return;
    final bytes = _files[request.uri.pathSegments.last]!;
    request.response.bufferOutput = false;
    request.response.contentLength = bytes.length;
    if (mode == _ResponseMode.stalledBody) {
      request.response.add(bytes.take(1).toList());
      await request.response.flush();
      return;
    }
    request.response.add(bytes);
    await request.response.close();
  }

  Future<void> close() async {
    await server.close(force: true);
  }
}
