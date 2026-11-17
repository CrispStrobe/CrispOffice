import 'dart:async';
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

// Control a real worker isolate without timing guesses or model weights. Each
// forward waits for the test to release it; cancellation and queue commands can
// arrive while its result is outstanding.
final class _ControlledFactory implements GectorBackendFactory {
  const _ControlledFactory(this.configuration, this.events, this.exitOnRelease);
  final GectorConfiguration configuration;
  final SendPort events;
  final bool exitOnRelease;

  @override
  Future<GectorBackend> open(GectorModelArtifact artifact) async =>
      _ControlledBackend(
        ScriptedBackend(
          configuration,
          const <List<String>>[],
          artifactSha256: artifact.sha256,
        ),
        events,
        exitOnRelease,
      );
}

final class _ForwardStarted {
  const _ForwardStarted(this.call, this.inputIds, this.release);
  final int call;
  final List<int> inputIds;
  final SendPort release;
}

final class _BackendClosed {
  const _BackendClosed();
}

final class _ControlledBackend implements GectorBackend {
  _ControlledBackend(this.delegate, this.events, this.exitOnRelease);
  final ScriptedBackend delegate;
  final SendPort events;
  final bool exitOnRelease;
  int calls = 0;

  @override
  GectorBackendIdentity get identity => delegate.identity;

  @override
  Future<GectorLogits> forward(GectorPreparedInput input) async {
    final gate = ReceivePort();
    events.send(
      _ForwardStarted(++calls, input.inputIds.toList(), gate.sendPort),
    );
    try {
      await gate.first;
      if (exitOnRelease) Isolate.exit();
      return await delegate.forward(input);
    } finally {
      gate.close();
    }
  }

  @override
  Future<void> dispose() async {
    await delegate.dispose();
    events.send(const _BackendClosed());
  }
}

final class _WorkerProbe {
  _WorkerProbe() {
    _events = StreamIterator<Object?>(_notifications);
  }

  final ReceivePort _notifications = ReceivePort();
  late final StreamIterator<Object?> _events;
  final List<SendPort> _releases = <SendPort>[];
  GectorTransport? _transport;
  GectorTransport get transport => _transport!;

  static Future<_WorkerProbe> start(
    TestBundle fixtures, {
    int maximumPending = 1,
    int maximumTextCodeUnits = 32768,
    bool exitOnRelease = false,
  }) async {
    final probe = _WorkerProbe();
    try {
      probe._transport = await startGectorWorker(
        bundle: fixtures.bundle,
        backendFactory: _ControlledFactory(
          fixtures.bundle.configuration,
          probe._notifications.sendPort,
          exitOnRelease,
        ),
        lexiconFactory: GectorWordSetLexiconFactory(const <String>[
          'Das',
          'ist',
          'gut',
        ]),
        maximumPendingRequests: maximumPending,
        options: GectorDecodeOptions(
          maximumTextCodeUnits: maximumTextCodeUnits,
        ),
        startupTimeout: const Duration(seconds: 5),
      );
      return probe;
    } on Object {
      await probe.dispose();
      rethrow;
    }
  }

  Future<Object?> next() async {
    if (!await _events.moveNext().timeout(const Duration(seconds: 5))) {
      throw StateError('Worker probe stopped without the expected event.');
    }
    final event = _events.current;
    if (event is _ForwardStarted) _releases.add(event.release);
    return event;
  }

  Future<_ForwardStarted> nextForward() async {
    final event = await next();
    if (event is! _ForwardStarted) {
      throw StateError('Expected a forward, got $event.');
    }
    return event;
  }

  Future<void> dispose() async {
    for (final release in _releases) {
      release.send(null);
    }
    await _transport?.dispose();
    await _events.cancel();
    _notifications.close();
  }
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

  test('a replacement burst keeps only its latest snapshot live', () async {
    final probe = await _WorkerProbe.start(fixtures);
    addTearDown(probe.dispose);
    final assertions = <Future<void>>[
      expectLater(
        probe.transport.check(
          GectorCheckRequest(text: 'Das ist gut.', key: 'editing'),
        ),
        throwsA(isA<GectorCancelledException>()),
      ),
    ];
    final blocked = await probe.nextForward();
    for (var i = 0; i < 200; i++) {
      assertions.add(
        expectLater(
          probe.transport.check(
            GectorCheckRequest(text: 'Das ist gut $i.', key: 'editing'),
          ),
          throwsA(isA<GectorCancelledException>()),
        ),
      );
    }
    final latest = probe.transport.check(
      GectorCheckRequest(text: 'Das ist besser!', key: 'editing'),
    );
    latest.ignore();
    await Future.wait(assertions);
    await expectLater(
      probe.transport.check(
        GectorCheckRequest(text: 'Das ist gut?', key: 'another'),
      ),
      throwsA(isA<GectorCapacityException>()),
    );
    blocked.release.send(null);
    final admitted = await probe.nextForward();
    expect(admitted.call, 2);
    expect(
      admitted.inputIds,
      fixtures.bundle.tokenizer.encode(['Das', 'ist', 'besser']).inputIds,
    );
    admitted.release.send(null);
    expect((await latest).corrected, 'Das ist besser!');
    await probe.transport.dispose();
    expect(await probe.next(), isA<_BackendClosed>());
  });

  test('over-limit requests leave valid in-flight work intact', () async {
    final probe = await _WorkerProbe.start(fixtures, maximumTextCodeUnits: 16);
    addTearDown(probe.dispose);
    final valid = probe.transport.check(
      GectorCheckRequest(text: 'Das ist gut.', key: 'editing'),
    );
    valid.ignore();
    final blocked = await probe.nextForward();
    await expectLater(
      probe.transport
          .check(GectorCheckRequest(text: 'x' * 17, key: 'editing'))
          .timeout(const Duration(seconds: 2)),
      throwsA(
        isA<GectorCapacityException>().having(
          (error) => error.message,
          'message',
          contains('16 UTF-16 units'),
        ),
      ),
    );
    blocked.release.send(null);
    expect((await valid).corrected, 'Das ist gut.');
    await probe.transport.dispose();
    expect(await probe.next(), isA<_BackendClosed>());
  });

  test('replacements preserve another queued key and make progress', () async {
    final probe = await _WorkerProbe.start(fixtures, maximumPending: 2);
    addTearDown(probe.dispose);
    final assertions = <Future<void>>[
      expectLater(
        probe.transport.check(
          GectorCheckRequest(text: 'Das ist gut.', key: 'editing'),
        ),
        throwsA(isA<GectorCancelledException>()),
      ),
    ];
    final blocked = await probe.nextForward();
    final independent = probe.transport.check(
      GectorCheckRequest(text: 'Das ist kurz?', key: 'independent'),
    );
    independent.ignore();
    for (var i = 0; i < 100; i++) {
      assertions.add(
        expectLater(
          probe.transport.check(
            GectorCheckRequest(text: 'Das ist gut $i.', key: 'editing'),
          ),
          throwsA(isA<GectorCancelledException>()),
        ),
      );
    }
    final latest = probe.transport.check(
      GectorCheckRequest(text: 'Das ist besser!', key: 'editing'),
    );
    latest.ignore();
    await Future.wait(assertions);
    blocked.release.send(null);
    final next = await probe.nextForward();
    expect(next.call, 2);
    expect(
      next.inputIds,
      fixtures.bundle.tokenizer.encode(['Das', 'ist', 'kurz']).inputIds,
    );
    next.release.send(null);
    expect((await independent).corrected, 'Das ist kurz?');
    final last = await probe.nextForward();
    expect(last.call, 3);
    expect(
      last.inputIds,
      fixtures.bundle.tokenizer.encode(['Das', 'ist', 'besser']).inputIds,
    );
    last.release.send(null);
    expect((await latest).corrected, 'Das ist besser!');
  });

  test('disposal fails a waiting replacement without forwarding it', () async {
    final probe = await _WorkerProbe.start(fixtures);
    addTearDown(probe.dispose);
    final old = expectLater(
      probe.transport.check(
        GectorCheckRequest(text: 'Das ist gut.', key: 'editing'),
      ),
      throwsA(isA<GectorCancelledException>()),
    );
    final blocked = await probe.nextForward();
    final waiting = expectLater(
      probe.transport.check(
        GectorCheckRequest(text: 'Das ist gut!', key: 'editing'),
      ),
      throwsA(isA<GectorUnavailableException>()),
    );
    await old;
    final disposed = probe.transport.dispose();
    blocked.release.send(null);
    await waiting;
    await disposed;
    expect(await probe.next(), isA<_BackendClosed>());
    await expectLater(
      probe.transport.check(
        GectorCheckRequest(text: 'Das ist gut?', key: 'new'),
      ),
      throwsA(isA<GectorUnavailableException>()),
    );
  });

  test('unexpected worker exit fails a waiting replacement', () async {
    final probe = await _WorkerProbe.start(fixtures, exitOnRelease: true);
    addTearDown(probe.dispose);
    final old = expectLater(
      probe.transport.check(
        GectorCheckRequest(text: 'Das ist gut.', key: 'editing'),
      ),
      throwsA(isA<GectorCancelledException>()),
    );
    final blocked = await probe.nextForward();
    final waiting = expectLater(
      probe.transport.check(
        GectorCheckRequest(text: 'Das ist gut!', key: 'editing'),
      ),
      throwsA(isA<GectorUnavailableException>()),
    );
    await old;
    blocked.release.send(null);
    await waiting;
    await expectLater(
      probe.transport.check(
        GectorCheckRequest(text: 'Das ist gut?', key: 'new'),
      ),
      throwsA(isA<GectorUnavailableException>()),
    );
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
