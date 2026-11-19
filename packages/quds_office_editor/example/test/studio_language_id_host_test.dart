import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_language_id/quds_language_id.dart';
import 'package:quds_office_studio/studio_language_id_host.dart';

final class _Transport implements LanguageIdTransport {
  final opened = Completer<void>();
  Completer<void>? openGate;
  Object? openFailure;
  Object? disposeFailure;
  int opens = 0;
  int disposals = 0;

  @override
  Future<void> open(Uint8List model) async {
    opens++;
    if (!opened.isCompleted) opened.complete();
    await openGate?.future;
    final failure = openFailure;
    if (failure != null) throw failure;
  }

  @override
  Future<List<List<(String, double)>>> detect(
    List<String> texts,
    int k,
  ) async => [for (final _ in texts) const []];

  @override
  Future<void> dispose() async {
    disposals++;
    final failure = disposeFailure;
    if (failure != null) throw failure;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Uint8List model;

  setUpAll(() async {
    final data = await rootBundle.load(Cld3Model.assetKey);
    model = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    expect(Cld3Model.verify(model), isTrue);
  });

  test(
    'concurrent loads publish one owned detector and dispose it once',
    () async {
      final transport = _Transport();
      var modelLoads = 0;
      var creations = 0;
      final host = BundledStudioLanguageIdHost(
        loadModel: () async {
          modelLoads++;
          return model;
        },
        createIdentifier: (bytes) {
          creations++;
          return Cld3LanguageIdentifier(model: bytes, transport: transport);
        },
      );
      var notifications = 0;
      host.addListener(() => notifications++);
      final first = host.load();
      expect(host.load(), same(first));
      await first;
      expect(modelLoads, 1);
      expect(creations, 1);
      expect(transport.opens, 1);
      expect(host.detector, isNotNull);
      expect(host.problem, isNull);
      expect(notifications, 1);
      host.dispose();
      host.dispose();
      expect(transport.disposals, 1);
      expect(host.detector, isNull);
    },
  );

  test(
    'dispose before asset completion never creates or publishes an identifier',
    () async {
      final pending = Completer<Uint8List>();
      var creations = 0;
      var modelLoads = 0;
      final host = BundledStudioLanguageIdHost(
        loadModel: () {
          modelLoads++;
          return pending.future;
        },
        createIdentifier: (bytes) {
          creations++;
          return Cld3LanguageIdentifier(model: bytes, transport: _Transport());
        },
      );
      var notifications = 0;
      host.addListener(() => notifications++);
      final loading = host.load();
      host.dispose();
      pending.complete(model);
      await expectLater(loading, completes);
      await host.load();
      expect(modelLoads, 1);
      expect(creations, 0);
      expect(host.detector, isNull);
      expect(host.problem, isNull);
      expect(notifications, 0);
    },
  );

  test('asset failure after disposal cannot publish a problem', () async {
    final pending = Completer<Uint8List>();
    final host = BundledStudioLanguageIdHost(
      loadModel: () => pending.future,
      createIdentifier: (_) => throw StateError('unexpected creation'),
    );
    var notifications = 0;
    host.addListener(() => notifications++);
    final loading = host.load();
    host.dispose();
    pending.completeError(StateError('private asset path and token'));
    await expectLater(loading, completes);
    expect(host.detector, isNull);
    expect(host.problem, isNull);
    expect(notifications, 0);
  });

  for (final fails in [false, true]) {
    test(
      'dispose during identifier load suppresses late ${fails ? 'failure' : 'success'}',
      () async {
        final transport = _Transport()
          ..openGate = Completer<void>()
          ..openFailure = fails
              ? StateError('private native library path')
              : null;
        final host = BundledStudioLanguageIdHost(
          loadModel: () async => model,
          createIdentifier: (bytes) =>
              Cld3LanguageIdentifier(model: bytes, transport: transport),
        );
        var notifications = 0;
        host.addListener(() => notifications++);
        final loading = host.load();
        await transport.opened.future;
        host.dispose();
        expect(transport.disposals, 1);
        transport.openGate!.complete();
        await expectLater(loading, completes);
        expect(host.detector, isNull);
        expect(host.problem, isNull);
        expect(notifications, 0);
        expect(transport.disposals, 1);
      },
    );
  }

  test(
    'factory disposal retires its late candidate before loading it',
    () async {
      final transport = _Transport();
      late BundledStudioLanguageIdHost host;
      host = BundledStudioLanguageIdHost(
        loadModel: () async => model,
        createIdentifier: (bytes) {
          host.dispose();
          return Cld3LanguageIdentifier(model: bytes, transport: transport);
        },
      );
      await expectLater(host.load(), completes);
      expect(transport.opens, 0);
      expect(transport.disposals, 1);
      expect(host.detector, isNull);
      expect(host.problem, isNull);
    },
  );

  for (final stage in ['asset', 'factory', 'identifier']) {
    test(
      '$stage failure publishes fixed feedback and retires an owned candidate',
      () async {
        final transport = _Transport()
          ..openFailure = stage == 'identifier'
              ? StateError('private worker diagnostics')
              : null;
        final host = BundledStudioLanguageIdHost(
          loadModel: () async {
            if (stage == 'asset') throw StateError('private asset path');
            return model;
          },
          createIdentifier: (bytes) {
            if (stage == 'factory') throw StateError('private library path');
            return Cld3LanguageIdentifier(model: bytes, transport: transport);
          },
        );
        var notifications = 0;
        host.addListener(() => notifications++);
        await expectLater(host.load(), completes);
        expect(host.detector, isNull);
        expect(host.problem, 'Automatic language detection is unavailable.');
        expect(notifications, 1);
        expect(transport.disposals, stage == 'identifier' ? 1 : 0);
        host.dispose();
      },
    );
  }

  test('asynchronous teardown failure cannot escape a disposed host', () async {
    final transport = _Transport()
      ..disposeFailure = StateError('private cleanup details');
    final host = BundledStudioLanguageIdHost(
      loadModel: () async => model,
      createIdentifier: (bytes) =>
          Cld3LanguageIdentifier(model: bytes, transport: transport),
    );
    await host.load();
    host.dispose();
    await Future<void>.delayed(Duration.zero);
    expect(transport.disposals, 1);
    expect(host.detector, isNull);
    expect(host.problem, isNull);
  });
}
