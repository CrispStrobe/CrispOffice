@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:quds_proofing_aot/quds_proofing_aot.dart';
import 'package:test/test.dart';

void main() {
  late String fixture;
  late Directory temporary;

  setUpAll(() async {
    final Uri? library = await Isolate.resolvePackageUri(
      Uri.parse('package:quds_proofing_aot/quds_proofing_aot.dart'),
    );
    fixture = library!
        .resolve('../test/fixtures/process_worker.dart')
        .toFilePath();
  });
  setUp(() {
    temporary = Directory.systemTemp.createTempSync('quds-aot-process-');
  });
  tearDown(() {
    temporary.deleteSync(recursive: true);
  });

  AotProcessTransport transport({
    String mode = 'echo',
    String? rmlDirectory,
    Map<String, String> environment = const <String, String>{},
    Duration timeout = const Duration(seconds: 10),
    int maximumResponseBytes = 4 * 1024 * 1024,
    int maximumStderrBytes = 256 * 1024,
    int maximumPendingRequests = 4,
  }) {
    final AotProcessTransport result = AotProcessTransport(
      executable: Platform.resolvedExecutable,
      arguments: <String>[fixture, '--literal-argument'],
      rmlDirectory: rmlDirectory,
      environment: <String, String>{
        ...environment,
        'QUDS_TEST_MODE': mode,
        'QUDS_TEST_MARKER': '${temporary.path}/worker.pid',
      },
      timeout: timeout,
      maximumResponseBytes: maximumResponseBytes,
      maximumStderrBytes: maximumStderrBytes,
      maximumPendingRequests: maximumPendingRequests,
    );
    addTearDown(result.dispose);
    return result;
  }

  test(
    'starts lazily and reuses a private process without shell expansion',
    () async {
      expect(AotProcessTransport.isSupported, isTrue);
      final AotProcessTransport worker = transport();
      expect(File('${temporary.path}/worker.pid').existsSync(), isFalse);
      const String secret = '  Für 😀 & + = ?\n`echo no` \$(touch no)';
      final Map<String, Object?> first =
          await _request(worker, secret) as Map<String, Object?>;
      final Map<String, Object?> second =
          await worker.request(
                action: 'morph',
                language: AotLanguage.english,
                query: 'goes',
                withParadigms: true,
              )
              as Map<String, Object?>;
      expect(first['pid'], second['pid']);
      expect(first['arguments'], <String>['--literal-argument']);
      expect(first['request'], <String, Object?>{
        'id': 1,
        'action': 'syntax',
        'langua': 'German',
        'query': secret,
        'withparadigms': false,
      });
      expect(second['request'], <String, Object?>{
        'id': 2,
        'action': 'morph',
        'langua': 'English',
        'query': 'goes',
        'withparadigms': true,
      });
    },
  );

  test(
    'passes an explicit resource directory and immutable environment',
    () async {
      final Map<String, String> environment = <String, String>{
        'RML': 'other-resource-directory',
        'QUDS_TEST_EXTRA': 'original',
      };
      final AotProcessTransport worker = transport(
        rmlDirectory: '${temporary.path}/resources with spaces',
        environment: environment,
      );
      environment['QUDS_TEST_EXTRA'] = 'changed';
      final Map<String, Object?> result =
          await _request(worker) as Map<String, Object?>;
      expect(result['rml'], '${temporary.path}/resources with spaces');
      expect(result['extra'], 'original');
    },
  );

  test('decodes Unicode split across pipe chunks', () async {
    final AotProcessTransport worker = transport(mode: 'split-bytes');
    final Map<String, Object?> result =
        await _request(worker, '😀 ÄÖÜ русский') as Map<String, Object?>;
    expect(
      (result['request'] as Map<String, Object?>)['query'],
      '😀 ÄÖÜ русский',
    );
  });

  test('serializes bounded requests and rejects queue overflow', () async {
    final AotProcessTransport worker = transport(maximumPendingRequests: 2);
    final Future<Object?> first = _request(worker, 'first');
    final Future<Object?> second = _request(worker, 'second');
    await expectLater(
      _request(worker, 'third'),
      _throwsCode(AotErrorCode.limit),
    );
    final List<Object?> results = await Future.wait(<Future<Object?>>[
      first,
      second,
    ]);
    final Map<String, Object?> firstResult = results[0] as Map<String, Object?>;
    final Map<String, Object?> secondResult =
        results[1] as Map<String, Object?>;
    expect(firstResult['pid'], secondResult['pid']);
    expect((firstResult['request'] as Map<String, Object?>)['query'], 'first');
    expect(
      (secondResult['request'] as Map<String, Object?>)['query'],
      'second',
    );
  });

  for (final (String, AotErrorCode) scenario in <(String, AotErrorCode)>[
    ('wrong-id', AotErrorCode.malformedResponse),
    ('float-id', AotErrorCode.malformedResponse),
    ('double-payload', AotErrorCode.malformedResponse),
    ('missing-payload', AotErrorCode.malformedResponse),
    ('unknown-field', AotErrorCode.malformedResponse),
    ('non-object', AotErrorCode.malformedResponse),
    ('invalid-json', AotErrorCode.malformedResponse),
    ('invalid-utf8', AotErrorCode.malformedResponse),
    ('truncated', AotErrorCode.malformedResponse),
    ('unsolicited', AotErrorCode.malformedResponse),
    ('crash', AotErrorCode.unavailable),
    ('engine-error', AotErrorCode.unavailable),
    ('engine-limit', AotErrorCode.limit),
    ('unsupported', AotErrorCode.unsupportedLanguage),
  ]) {
    test(
      '${scenario.$1} fails explicitly without exposing text or retrying',
      () async {
        final AotProcessTransport worker = transport(mode: scenario.$1);
        await expectLater(
          _request(worker, 'private document'),
          _throwsCode(scenario.$2),
        );
        await expectLater(
          _request(worker, 'private retry'),
          _throwsCode(scenario.$2),
        );
        await worker.dispose();
        await _expectWorkerStopped(temporary);
      },
    );
  }

  test('bounds streamed output before JSON parsing', () async {
    final AotProcessTransport worker = transport(
      mode: 'flood',
      maximumResponseBytes: 128,
    );
    await expectLater(_request(worker), _throwsCode(AotErrorCode.limit));
    await worker.dispose();
    await _expectWorkerStopped(temporary);
  });

  test(
    'drains and caps stderr without retaining private diagnostics',
    () async {
      final AotProcessTransport worker = transport(
        mode: 'stderr-flood',
        maximumStderrBytes: 128,
      );
      await expectLater(_request(worker), _throwsCode(AotErrorCode.limit));
      await worker.dispose();
      await _expectWorkerStopped(temporary);
    },
  );

  test(
    'active deadline kills worker and fails queued work without retries',
    () async {
      final AotProcessTransport worker = transport(
        mode: 'hang',
        timeout: const Duration(seconds: 2),
      );
      final Future<void> first = expectLater(
        _request(worker, 'first'),
        _throwsCode(AotErrorCode.timeout),
      );
      final Future<void> second = expectLater(
        _request(worker, 'second'),
        _throwsCode(AotErrorCode.timeout),
      );
      await Future.wait(<Future<void>>[first, second]);
      await worker.dispose();
      await _expectWorkerStopped(temporary);
    },
  );

  test(
    'deadline includes time spent waiting behind a previous request',
    () async {
      final AotProcessTransport worker = transport(
        mode: 'delay',
        timeout: const Duration(milliseconds: 1700),
      );
      final Future<Object?> first = _request(worker, 'first');
      final Future<void> second = expectLater(
        _request(worker, 'second'),
        _throwsCode(AotErrorCode.timeout),
      );
      expect(await first, isA<Map<String, Object?>>());
      await second;
      await worker.dispose();
      await _expectWorkerStopped(temporary);
    },
  );

  test('disposal cancels active and queued work and is idempotent', () async {
    final AotProcessTransport worker = transport(mode: 'hang');
    final Future<void> first = expectLater(
      _request(worker, 'first'),
      _throwsCode(AotErrorCode.disposed),
    );
    final Future<void> second = expectLater(
      _request(worker, 'second'),
      _throwsCode(AotErrorCode.disposed),
    );
    await _awaitWorkerMarker(temporary);
    await worker.dispose();
    await worker.dispose();
    await Future.wait(<Future<void>>[first, second]);
    await expectLater(_request(worker), _throwsCode(AotErrorCode.disposed));
    await _expectWorkerStopped(temporary);
  });

  test(
    'disposal during process startup still terminates the late process',
    () async {
      final AotProcessTransport worker = transport(mode: 'hang');
      final Future<void> response = expectLater(
        _request(worker),
        _throwsCode(AotErrorCode.disposed),
      );
      await worker.dispose();
      await response;
      await _expectWorkerStopped(temporary);
    },
  );

  test('missing executable remains a redacted unavailable result', () async {
    final AotProcessTransport worker = AotProcessTransport(
      executable: '${temporary.path}/private-nonexistent-worker',
    );
    addTearDown(worker.dispose);
    await expectLater(
      _request(worker, 'private text'),
      _throwsCode(AotErrorCode.unavailable),
    );
  });

  test(
    'validates action, language and input before starting anything',
    () async {
      final AotProcessTransport worker = AotProcessTransport(
        executable: '${temporary.path}/not-installed',
        maximumQueryCodeUnits: 4,
        maximumRequestBytes: 200,
      );
      addTearDown(worker.dispose);
      await expectLater(
        _request(worker, '12345'),
        _throwsCode(AotErrorCode.limit),
      );
      await expectLater(_request(worker, '  '), throwsArgumentError);
      await expectLater(
        worker.request(
          action: 'wrong',
          language: AotLanguage.german,
          query: 'a',
        ),
        throwsArgumentError,
      );
      await expectLater(
        worker.request(
          action: 'syntax',
          language: AotLanguage.english,
          query: 'a',
        ),
        _throwsCode(AotErrorCode.unsupportedLanguage),
      );
      final AotProcessTransport encodedLimit = AotProcessTransport(
        executable: '${temporary.path}/not-installed',
        maximumRequestBytes: 1,
      );
      addTearDown(encodedLimit.dispose);
      await expectLater(
        _request(encodedLimit, 'a'),
        _throwsCode(AotErrorCode.limit),
      );
    },
  );
}

Future<Object?> _request(
  AotProcessTransport transport, [
  String query = 'Hund',
]) => transport.request(
  action: 'syntax',
  language: AotLanguage.german,
  query: query,
);

Matcher _throwsCode(AotErrorCode code) => throwsA(
  isA<AotException>()
      .having((AotException error) => error.code, 'code', code)
      .having(
        (AotException error) => error.toString(),
        'redacted message',
        isNot(contains('private')),
      ),
);

Future<void> _awaitWorkerMarker(Directory directory) async {
  final File marker = File('${directory.path}/worker.pid');
  final Stopwatch timer = Stopwatch()..start();
  while (!marker.existsSync() && timer.elapsed < const Duration(seconds: 5)) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(
    marker.existsSync(),
    isTrue,
    reason: 'The fixture worker did not start.',
  );
}

Future<void> _expectWorkerStopped(Directory directory) async {
  final File marker = File('${directory.path}/worker.pid');
  if (!marker.existsSync() || Platform.isWindows) return;
  final int workerPid = int.parse(marker.readAsStringSync());
  expect(
    Process.killPid(workerPid, ProcessSignal.sigcont),
    isFalse,
    reason: 'The managed worker must not survive cancellation/disposal.',
  );
}
