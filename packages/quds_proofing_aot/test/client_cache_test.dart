import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quds_proofing_aot/quds_proofing_aot.dart';
import 'package:test/test.dart';

import 'aot_fixture_data.dart';

void main() {
  test(
    'reuses immutable successful morphology across repeated checks',
    () async {
      final _Transport transport = _Transport(morphologyFixture());
      final AotClient client = AotClient(transport: transport);
      addTearDown(client.dispose);
      final AotMorphology first = await client.morphology(
        'geht',
        withParadigms: true,
      );
      final AotMorphology second = await client.morphology(
        'geht',
        withParadigms: true,
      );
      expect(second, same(first));
      expect(transport.calls, 1);
      expect(() => first.readings.clear(), throwsUnsupportedError);
      expect(
        () => first.readings.first.paradigm.clear(),
        throwsUnsupportedError,
      );
    },
  );

  test('cache keys preserve exact case, language and paradigm mode', () async {
    final _Transport transport = _Transport(morphologyFixture());
    final AotClient client = AotClient(transport: transport);
    addTearDown(client.dispose);
    final AotMorphology lower = await client.morphology('geht');
    final AotMorphology upper = await client.morphology('Geht');
    final AotMorphology paradigms = await client.morphology(
      'geht',
      withParadigms: true,
    );
    final AotMorphology russian = await client.morphology(
      'geht',
      language: AotLanguage.russian,
    );
    final AotMorphology english = await client.morphology(
      'geht',
      language: AotLanguage.english,
    );
    final AotMorphology spaced = await client.morphology(' geht');
    expect(transport.calls, 6);
    expect(lower.word, 'geht');
    expect(upper.word, 'Geht');
    expect(paradigms, isNot(same(lower)));
    expect(russian.language, AotLanguage.russian);
    expect(english.language, AotLanguage.english);
    expect(spaced.word, ' geht');
    expect(await client.morphology('geht'), same(lower));
    expect(await client.morphology('Geht'), same(upper));
    expect(
      await client.morphology('geht', withParadigms: true),
      same(paradigms),
    );
    expect(
      await client.morphology('geht', language: AotLanguage.russian),
      same(russian),
    );
    expect(
      await client.morphology('geht', language: AotLanguage.english),
      same(english),
    );
    expect(await client.morphology(' geht'), same(spaced));
    expect(transport.calls, 6);
  });

  test(
    'coalesces identical pending lookups into one transport request',
    () async {
      final Completer<Object?> response = Completer<Object?>();
      final _Transport transport = _Transport(null)..pending = response.future;
      final AotClient client = AotClient(transport: transport);
      addTearDown(client.dispose);
      final Future<AotMorphology> first = client.morphology(
        'geht',
        withParadigms: true,
      );
      final Future<AotMorphology> second = client.morphology(
        'geht',
        withParadigms: true,
      );
      expect(transport.calls, 1);
      response.complete(morphologyFixture());
      final List<AotMorphology> results = await Future.wait(
        <Future<AotMorphology>>[first, second],
      );
      expect(results[0], same(results[1]));
      expect(
        await client.morphology('geht', withParadigms: true),
        same(results[0]),
      );
      expect(transport.calls, 1);
    },
  );

  test(
    'pending errors reach all callers and do not poison a later retry',
    () async {
      final Completer<Object?> response = Completer<Object?>();
      final _Transport transport = _Transport(null)..pending = response.future;
      final AotClient client = AotClient(transport: transport);
      addTearDown(client.dispose);
      final Future<void> first = expectLater(
        client.morphology('geht'),
        _throwsCode(AotErrorCode.unavailable),
      );
      final Future<void> second = expectLater(
        client.morphology('geht'),
        _throwsCode(AotErrorCode.unavailable),
      );
      expect(transport.calls, 1);
      response.completeError(
        const AotException(AotErrorCode.unavailable, 'Unavailable fixture.'),
      );
      await Future.wait(<Future<void>>[first, second]);
      transport
        ..pending = null
        ..response = morphologyFixture();
      expect((await client.morphology('geht')).readings, isNotEmpty);
      await client.morphology('geht');
      expect(transport.calls, 2);
    },
  );

  test('does not cache malformed responses or syntax document text', () async {
    final _Transport transport = _Transport(<String, Object?>{'bad': true});
    final AotClient client = AotClient(transport: transport);
    addTearDown(client.dispose);
    await expectLater(
      client.morphology('geht'),
      _throwsCode(AotErrorCode.malformedResponse),
    );
    await expectLater(
      client.morphology('geht'),
      _throwsCode(AotErrorCode.malformedResponse),
    );
    expect(transport.calls, 2);
    transport.response = syntaxFixture();
    await client.analyze('Ich gehe nach Hause.');
    await client.analyze('Ich gehe nach Hause.');
    expect(transport.calls, 4);
  });

  test(
    'entry bound evicts the least recently used successful lookup',
    () async {
      final _Transport transport = _Transport(morphologyFixture());
      final AotClient client = AotClient(
        transport: transport,
        maximumMorphologyCacheEntries: 2,
      );
      addTearDown(client.dispose);
      final AotMorphology firstA = await client.morphology('a');
      await client.morphology('b');
      expect(await client.morphology('a'), same(firstA));
      await client.morphology('c');
      expect(await client.morphology('a'), same(firstA));
      expect(transport.calls, 3);
      await client.morphology('b');
      expect(transport.calls, 4);
    },
  );

  test('raw UTF-16 budget evicts even when entry capacity remains', () async {
    final Object raw = morphologyFixture();
    final int entryCost = jsonEncode(raw).length + 1;
    final _Transport transport = _Transport(raw);
    final AotClient client = AotClient(
      transport: transport,
      maximumMorphologyCacheEntries: 64,
      maximumMorphologyCacheCodeUnits: entryCost * 2 - 1,
    );
    addTearDown(client.dispose);
    await client.morphology('a');
    await client.morphology('b');
    await client.morphology('a');
    expect(transport.calls, 3);
  });

  test(
    'returns oversized results without retaining or evicting small results',
    () async {
      final List<Object?> raw = morphologyFixture();
      final int entryCost = jsonEncode(raw).length + 1;
      final _Transport transport = _Transport(raw);
      final AotClient client = AotClient(
        transport: transport,
        maximumMorphologyCacheCodeUnits: entryCost,
      );
      addTearDown(client.dispose);
      final AotMorphology retained = await client.morphology('a');
      final List<Object?> large = morphologyFixture();
      (large.first! as Map<String, Object?>)['padding'] = '😀' * 1024;
      transport.response = large;
      expect((await client.morphology('b')).readings, isNotEmpty);
      expect((await client.morphology('b')).readings, isNotEmpty);
      expect(await client.morphology('a'), same(retained));
      expect(transport.calls, 3);
    },
  );

  test(
    'zero cache limits disable retention while still coalescing work',
    () async {
      for (final bool byEntries in <bool>[true, false]) {
        final Completer<Object?> response = Completer<Object?>();
        final _Transport transport = _Transport(null)
          ..pending = response.future;
        final AotClient client = AotClient(
          transport: transport,
          maximumMorphologyCacheEntries: byEntries ? 0 : 64,
          maximumMorphologyCacheCodeUnits: byEntries ? 512 * 1024 : 0,
        );
        addTearDown(client.dispose);
        final Future<AotMorphology> first = client.morphology('geht');
        final Future<AotMorphology> second = client.morphology('geht');
        response.complete(morphologyFixture());
        final List<AotMorphology> results = await Future.wait(
          <Future<AotMorphology>>[first, second],
        );
        expect(results.first, same(results.last));
        expect(transport.calls, 1);
        transport
          ..pending = null
          ..response = morphologyFixture();
        await client.morphology('geht');
        expect(transport.calls, 2);
      }
    },
  );

  test('disposal rejects cached and late coalesced results', () async {
    final _Transport transport = _Transport(morphologyFixture());
    final AotClient client = AotClient(transport: transport);
    await client.morphology('cached');
    final Completer<Object?> response = Completer<Object?>();
    transport.pending = response.future;
    final Future<void> first = expectLater(
      client.morphology('late'),
      _throwsCode(AotErrorCode.disposed),
    );
    final Future<void> second = expectLater(
      client.morphology('late'),
      _throwsCode(AotErrorCode.disposed),
    );
    await client.dispose();
    await expectLater(
      client.morphology('cached'),
      _throwsCode(AotErrorCode.disposed),
    );
    response.complete(morphologyFixture());
    await Future.wait(<Future<void>>[first, second]);
    await client.dispose();
    expect(transport.calls, 2);
    expect(transport.disposals, 1);
  });

  test(
    'cache bounds are validated and documented defaults are exposed',
    () async {
      expect(
        () => AotClient(maximumMorphologyCacheEntries: -1),
        throwsArgumentError,
      );
      expect(
        () => AotClient(maximumMorphologyCacheCodeUnits: -1),
        throwsArgumentError,
      );
      final AotClient client = AotClient();
      expect(client.maximumMorphologyCacheEntries, 64);
      expect(client.maximumMorphologyCacheCodeUnits, 512 * 1024);
      expect((await client.analyze('')).tokens, isEmpty);
      await client.dispose();
    },
  );

  test('explicit HTTP factory preserves legacy POST configuration', () async {
    final List<http.Request> requests = <http.Request>[];
    final AotClient client = AotClient.http(
      endpoint: Uri.parse('http://127.0.0.1:9999/analyze'),
      httpClient: MockClient((http.Request request) async {
        requests.add(request);
        return http.Response(jsonEncode(morphologyFixture()), 200);
      }),
    );
    addTearDown(client.dispose);
    expect(requests, isEmpty);
    await client.morphology('geht', withParadigms: true);
    expect(requests.single.url, Uri.parse('http://127.0.0.1:9999/analyze'));
    expect(requests.single.method, 'POST');
    expect(requests.single.bodyFields['query'], 'geht');
    expect(requests.single.bodyFields['withparadigms'], '1');
  });
}

Matcher _throwsCode(AotErrorCode code) => throwsA(
  isA<AotException>().having((AotException error) => error.code, 'code', code),
);

final class _Transport implements AotTransport {
  _Transport(this.response);
  Object? response;
  Future<Object?>? pending;
  int calls = 0;
  int disposals = 0;

  @override
  Future<Object?> request({
    required String action,
    required AotLanguage language,
    required String query,
    bool withParadigms = false,
  }) async {
    calls++;
    return pending ?? response;
  }

  @override
  Future<void> dispose() async {
    disposals++;
  }
}
