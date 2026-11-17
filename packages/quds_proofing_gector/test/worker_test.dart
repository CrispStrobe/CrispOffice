import 'dart:isolate';

import 'package:quds_proofing_gector/quds_proofing_gector.dart';
import 'package:test/test.dart';

import 'support.dart';

final class _UnsendableFactory implements GectorBackendFactory {
  _UnsendableFactory(this.port);
  final ReceivePort port;
  @override
  Future<GectorBackend> open(GectorModelArtifact artifact) async =>
      throw StateError('An unsendable factory cannot reach the worker.');
}

void main() {
  late TestBundle fixtures;
  setUpAll(() async {
    fixtures = await TestBundle.load();
  });
  Future<GectorTransport> worker({
    int delayMillis = 0,
    int? failOnCall,
    int maximumPending = 3,
    bool wrongIdentity = false,
  }) => startGectorWorker(
    bundle: fixtures.bundle,
    backendFactory: TestBackendFactory(
      fixtures.bundle.configuration,
      delayMillis: delayMillis,
      failOnCall: failOnCall,
      wrongIdentity: wrongIdentity,
    ),
    lexiconFactory: GectorWordSetLexiconFactory(const <String>[
      'Das',
      'ist',
      'gut',
    ]),
    maximumPendingRequests: maximumPending,
    startupTimeout: const Duration(seconds: 5),
  );

  test(
    'one preloaded backend persists across requests and failures propagate',
    () async {
      final transport = await worker(failOnCall: 2);
      addTearDown(transport.dispose);
      final first = await transport.check(
        GectorCheckRequest(text: 'Das ist gut.', key: 'a'),
      );
      expect(first.guarded, isTrue);
      expect(first.complete, isTrue);
      expect(first.corrected, 'Das ist gut.');
      await expectLater(
        transport.check(GectorCheckRequest(text: 'Das ist gut.', key: 'a')),
        throwsA(
          isA<StateError>().having(
            (e) => e.toString(),
            'failure',
            contains('Injected'),
          ),
        ),
      );
      final third = await transport.check(
        GectorCheckRequest(text: 'Das ist gut.', key: 'a'),
      );
      expect(third.corrected, 'Das ist gut.');
    },
  );

  test(
    'new snapshot supersedes in-flight work, including with a one-request queue',
    () async {
      final transport = await worker(delayMillis: 60, maximumPending: 1);
      addTearDown(transport.dispose);
      final old = transport.check(
        GectorCheckRequest(text: 'Das ist gut.', key: 'same'),
      );
      final oldAssertion = expectLater(
        old,
        throwsA(isA<GectorCancelledException>()),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final fresh = transport.check(
        GectorCheckRequest(text: 'Das ist gut!', key: 'same'),
      );
      await oldAssertion;
      expect((await fresh).corrected, 'Das ist gut!');
    },
  );

  test('different requests cannot grow an unbounded queue', () async {
    final transport = await worker(delayMillis: 60, maximumPending: 1);
    addTearDown(transport.dispose);
    final first = transport.check(
      GectorCheckRequest(text: 'Das ist gut.', key: 'one'),
    );
    await expectLater(
      transport.check(GectorCheckRequest(text: 'Das ist gut.', key: 'two')),
      throwsA(isA<GectorCapacityException>()),
    );
    expect((await first).complete, isTrue);
  });

  test('loaded identity mismatch prevents worker readiness', () async {
    await expectLater(
      worker(wrongIdentity: true),
      throwsA(isA<GectorUnavailableException>()),
    );
  });

  test(
    'spawn failure reports once without an unhandled readiness error',
    () async {
      final port = ReceivePort();
      addTearDown(port.close);
      await expectLater(
        startGectorWorker(
          bundle: fixtures.bundle,
          backendFactory: _UnsendableFactory(port),
          lexiconFactory: GectorWordSetLexiconFactory(const <String>[]),
        ),
        throwsArgumentError,
      );
      await Future<void>.delayed(Duration.zero);
    },
  );

  test(
    'dispose completes outstanding work and future requests report unavailable',
    () async {
      final transport = await worker(delayMillis: 60);
      final request = transport.check(
        GectorCheckRequest(text: 'Das ist gut.', key: 'one'),
      );
      final assertion = expectLater(
        request,
        throwsA(isA<GectorUnavailableException>()),
      );
      await transport.dispose();
      await assertion;
      await expectLater(
        transport.check(GectorCheckRequest(text: 'Das ist gut.', key: 'two')),
        throwsA(isA<GectorUnavailableException>()),
      );
      await transport.dispose();
    },
  );
}
