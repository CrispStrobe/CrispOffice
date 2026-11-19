@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:quds_proofing_hunspell/installer_io.dart';
import 'package:quds_proofing_hunspell/quds_proofing_hunspell.dart';
import 'package:test/test.dart';

void main() {
  final bytes = <String, List<int>>{
    'ar.aff': utf8.encode('SET UTF-8\n'),
    'ar.dic': utf8.encode('1\nمدرسة\n'),
    'LICENSE': utf8.encode('Synthetic cancellation fixture.\n'),
  };
  HunspellArtifact artifact(String name) =>
      HunspellArtifact(name, sha256Hex(bytes[name]!), bytes[name]!.length);
  final bundle = HunspellBundleDownload(
    id: 'cancellation-fixture',
    displayName: 'Cancellation fixture',
    languages: {'ar'},
    repository: 'unused/fixture',
    revision: '0000000000000000000000000000000000000000',
    license: 'Synthetic test data',
    aff: artifact('ar.aff'),
    dic: artifact('ar.dic'),
    notices: [artifact('LICENSE')],
  );
  late Directory root;
  late HttpServer server;
  late Completer<void> requested;
  var requests = 0;
  var stall = false;

  setUp(() async {
    root = Directory.systemTemp.createTempSync('hunspell-cancel-');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    requested = Completer<void>();
    requests = 0;
    stall = false;
    server.listen((request) {
      requests++;
      if (!requested.isCompleted) requested.complete();
      if (stall) return;
      request.response.add(bytes[request.uri.pathSegments.last]!);
      unawaited(request.response.close());
    });
  });

  tearDown(() async {
    await server.close(force: true);
    root.deleteSync(recursive: true);
  });

  HunspellInstaller installer() => HunspellInstaller(
    root,
    resolveUrl: (_, file) =>
        Uri.http('127.0.0.1:${server.port}', '/${file.file}'),
  );

  test(
    'an uncancelled small pinned bundle still installs and verifies',
    () async {
      final value = installer();
      await value.install(bundle);
      expect(requests, bundle.files.length);
      expect(await value.installed(bundle), isNotNull);
      await value.remove(bundle);
      expect(await value.installed(bundle), isNull);
    },
  );

  test(
    'pre-cancelled install makes no HTTP request or staging directory',
    () async {
      final cancellation = HunspellInstallCancellation()..cancel();
      await expectLater(
        installer().install(bundle, cancellation: cancellation),
        throwsA(isA<HunspellInstallException>()),
      );
      expect(requests, 0);
      expect(root.listSync(), isEmpty);
    },
  );

  test('cancellation at the final progress callback cannot publish', () async {
    final cancellation = HunspellInstallCancellation();
    final value = installer();
    var finalProgress = false;
    await expectLater(
      value.install(
        bundle,
        cancellation: cancellation,
        onProgress: (received, total) {
          if (received == total) {
            finalProgress = true;
            cancellation.cancel();
          }
        },
      ),
      throwsA(isA<HunspellInstallException>()),
    );
    expect(finalProgress, isTrue);
    expect(await value.installed(bundle), isNull);
    expect(Directory('${root.path}/hunspell').listSync(), isEmpty);
  });

  test(
    'cancellation aborts a stalled HTTP response and cleans staging',
    () async {
      stall = true;
      final cancellation = HunspellInstallCancellation();
      final value = installer();
      final pending = value.install(bundle, cancellation: cancellation);
      final completed = expectLater(
        pending.timeout(const Duration(seconds: 2)),
        throwsA(isA<HunspellInstallException>()),
      );
      await requested.future;
      cancellation.cancel();
      await completed;
      expect(await value.installed(bundle), isNull);
      expect(Directory('${root.path}/hunspell').listSync(), isEmpty);
    },
  );
}
