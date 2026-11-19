import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_office_studio/studio_hunspell_host.dart';
import 'package:quds_office_studio/studio_hunspell_host_web.dart';
import 'package:quds_proofing_hunspell/quds_proofing_hunspell.dart';

class _Client extends http.BaseClient {
  _Client(this.bytes, {this.stall = false});
  final Map<String, List<int>> bytes;
  final bool stall;
  final requested = Completer<void>();
  Completer<http.StreamedResponse>? pending;
  int requests = 0;
  int closes = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    requests++;
    if (!requested.isCompleted) requested.complete();
    if (stall) {
      pending = Completer<http.StreamedResponse>();
      return pending!.future;
    }
    return Future.value(
      http.StreamedResponse(
        Stream.value(bytes[request.url.pathSegments.last]!),
        200,
      ),
    );
  }

  @override
  void close() {
    closes++;
    final request = pending;
    if (request != null && !request.isCompleted) {
      request.completeError(http.ClientException('Client closed'));
    }
  }
}

void main() {
  final bytes = <String, List<int>>{
    'ar.aff': utf8.encode('SET UTF-8\n'),
    'ar.dic': utf8.encode('1\nمدرسة\n'),
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
    notices: [],
  );

  test(
    'web install publishes verified data and releases cancellation',
    () async {
      final client = _Client(bytes);
      final host = WebStudioHunspellHost(
        client: () => client,
        catalog: [bundle],
      );
      addTearDown(host.dispose);
      final cancellation = StudioHunspellCancellation();
      await host.install(bundle, cancellation: cancellation);
      expect(client.requests, 2);
      expect(host.status(bundle).installed, isTrue);
      final providers = host.createProviders(OfficeProofingVocabulary());
      expect(providers, hasLength(1));
      await providers.single.dispose();
      final closes = client.closes;
      cancellation.cancel();
      expect(client.closes, closes);
      expect(host.status(bundle).installed, isTrue);
      await host.remove(bundle);
      expect(host.createProviders(OfficeProofingVocabulary()), isEmpty);
    },
  );

  test('pre-cancelled web install does not start a request', () async {
    final client = _Client(bytes);
    final host = WebStudioHunspellHost(client: () => client, catalog: [bundle]);
    addTearDown(host.dispose);
    final cancellation = StudioHunspellCancellation()..cancel();
    await expectLater(
      host.install(bundle, cancellation: cancellation),
      throwsA(isA<StateError>()),
    );
    expect(client.requests, 0);
    expect(host.status(bundle).installed, isFalse);
  });

  test(
    'web cancellation at final progress cannot register a provider',
    () async {
      final client = _Client(bytes);
      final host = WebStudioHunspellHost(
        client: () => client,
        catalog: [bundle],
      );
      addTearDown(host.dispose);
      final cancellation = StudioHunspellCancellation();
      var finalProgress = false;
      await expectLater(
        host.install(
          bundle,
          cancellation: cancellation,
          onProgress: (received, total) {
            if (received == total) {
              finalProgress = true;
              cancellation.cancel();
            }
          },
        ),
        throwsA(isA<StateError>()),
      );
      expect(finalProgress, isTrue);
      expect(host.status(bundle).installed, isFalse);
      expect(host.createProviders(OfficeProofingVocabulary()), isEmpty);
      expect(client.closes, greaterThanOrEqualTo(1));
    },
  );

  test('web cancellation closes a client with a stalled response', () async {
    final client = _Client(bytes, stall: true);
    final host = WebStudioHunspellHost(client: () => client, catalog: [bundle]);
    addTearDown(host.dispose);
    final cancellation = StudioHunspellCancellation();
    final pending = host.install(bundle, cancellation: cancellation);
    final completed = expectLater(
      pending.timeout(const Duration(seconds: 2)),
      throwsA(isA<StateError>()),
    );
    await client.requested.future;
    cancellation.cancel();
    try {
      await completed;
      expect(client.closes, greaterThanOrEqualTo(1));
      expect(host.status(bundle).installed, isFalse);
    } finally {
      client.close();
      await pending.catchError((Object _) {});
    }
  });
}
