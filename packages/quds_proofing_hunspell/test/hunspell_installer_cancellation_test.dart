@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:quds_proofing_hunspell/installer_io.dart';
import 'package:quds_proofing_hunspell/quds_proofing_hunspell.dart';
import 'package:test/test.dart';

enum _ResponseMode { complete, stalledHeaders, stalledBody }

final _files = <String, List<int>>{
  'ar.aff': utf8.encode('SET UTF-8\n'),
  'ar.dic': utf8.encode('1\nword\n'),
  'NOTICE': utf8.encode('Locally authored cancellation fixture.\n'),
};

HunspellArtifact _artifact(String name) =>
    HunspellArtifact(name, sha256Hex(_files[name]!), _files[name]!.length);

final _bundle = HunspellBundleDownload(
  id: 'cancellation-fixture',
  displayName: 'Cancellation fixture',
  languages: const {'ar'},
  repository: 'test/fixture',
  revision: '0000000000000000000000000000000000000000',
  license: 'Test fixture',
  aff: _artifact('ar.aff'),
  dic: _artifact('ar.dic'),
  notices: [_artifact('NOTICE')],
);

final _cancelled = isA<HunspellInstallException>().having(
  (error) => error.message,
  'message',
  'Download cancelled.',
);

void main() {
  late Directory root;
  late _Server fixture;
  late HunspellInstaller installer;
  var clients = 0;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('hunspell-cancellation-');
    fixture = await _Server.start();
    clients = 0;
    installer = HunspellInstaller(
      root,
      httpClientFactory: () {
        clients++;
        return HttpClient();
      },
      resolveUrl: (_, artifact) => fixture.url(artifact.file),
    );
  });

  tearDown(() async {
    await fixture.close();
    root.deleteSync(recursive: true);
  });

  Future<void> expectAbsent() async {
    expect(await installer.installed(_bundle), isNull);
    final directory = Directory('${root.path}/hunspell');
    if (directory.existsSync()) expect(directory.listSync(), isEmpty);
  }

  Future<void> retry() async {
    fixture.mode = _ResponseMode.complete;
    final installed = await installer
        .install(_bundle)
        .timeout(const Duration(seconds: 3));
    expect(File(installed.affPath).readAsBytesSync(), _files['ar.aff']);
    expect(File(installed.dicPath).readAsBytesSync(), _files['ar.dic']);
    expect(await installer.installed(_bundle), isNotNull);
  }

  test(
    'already-cancelled install performs no network or staging work',
    () async {
      final cancellation = HunspellInstallCancellation()..cancel();
      await expectLater(
        installer.install(_bundle, cancellation: cancellation),
        throwsA(_cancelled),
      );
      expect(clients, 0);
      expect(fixture.requests, 0);
      await expectAbsent();
    },
  );

  for (final mode in [
    _ResponseMode.stalledHeaders,
    _ResponseMode.stalledBody,
  ]) {
    test(
      'cancelling ${mode.name} aborts and permits a fresh install',
      () async {
        fixture.mode = mode;
        final cancellation = HunspellInstallCancellation();
        addTearDown(cancellation.cancel);
        final received = Completer<void>();
        final outcome = expectLater(
          installer.install(
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
        cancellation.cancel();
        await outcome.timeout(const Duration(seconds: 3));
        expect(fixture.requests, 1);
        await expectAbsent();
        await retry();
      },
    );
  }

  test(
    'cancellation at the final progress callback prevents publication',
    () async {
      final cancellation = HunspellInstallCancellation();
      await expectLater(
        installer.install(
          _bundle,
          cancellation: cancellation,
          onProgress: (received, total) {
            if (received == total) cancellation.cancel();
          },
        ),
        throwsA(_cancelled),
      );
      await expectAbsent();
      await retry();
    },
  );
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
