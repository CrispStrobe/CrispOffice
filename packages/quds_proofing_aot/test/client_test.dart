import 'dart:async';

import 'package:quds_proofing_aot/quds_proofing_aot.dart';
import 'package:test/test.dart';

import 'aot_fixture_data.dart';

void main() {
  test(
    'syntax request preserves source and canonical daemon language',
    () async {
      final _Transport transport = _Transport(syntaxFixture());
      final AotClient client = AotClient(transport: transport);
      addTearDown(client.dispose);
      final AotAnalysis analysis = await client.analyze(
        '  Ich gehe nach Hause.',
      );
      expect(transport.action, 'syntax');
      expect(transport.query, '  Ich gehe nach Hause.');
      expect(transport.language, AotLanguage.german);
      expect(analysis.text, transport.query);
      expect(analysis.tokens.first.start, 2);
      expect(analysis.fullyAligned, isTrue);
    },
  );

  test('English syntax is unsupported without sending text', () async {
    final _Transport transport = _Transport(<Object?>[]);
    final AotClient client = AotClient(transport: transport);
    addTearDown(client.dispose);
    await expectLater(
      client.analyze('Hello', language: AotLanguage.english),
      throwsA(
        isA<AotException>().having(
          (AotException e) => e.code,
          'code',
          AotErrorCode.unsupportedLanguage,
        ),
      ),
    );
    expect(transport.calls, 0);
  });

  test('English morphology and optional paradigms are supported', () async {
    final _Transport transport = _Transport(morphologyFixture());
    final AotClient client = AotClient(transport: transport);
    addTearDown(client.dispose);
    final AotMorphology result = await client.morphology(
      'goes',
      language: AotLanguage.english,
      withParadigms: true,
    );
    expect(result.word, 'goes');
    expect(result.language, AotLanguage.english);
    expect(transport.action, 'morph');
    expect(transport.withParadigms, isTrue);
  });

  test('Russian syntax is passed through explicitly', () async {
    final _Transport transport = _Transport(<Object?>[]);
    final AotClient client = AotClient(transport: transport);
    addTearDown(client.dispose);
    final AotAnalysis result = await client.analyze(
      'Привет.',
      language: AotLanguage.russian,
    );
    expect(result.language, AotLanguage.russian);
    expect(transport.language, AotLanguage.russian);
    expect(result.fullyAligned, isFalse);
  });

  test('empty input needs no daemon', () async {
    final _Transport transport = _Transport(null);
    final AotClient client = AotClient(transport: transport);
    addTearDown(client.dispose);
    expect((await client.analyze(' \n')).fullyAligned, isTrue);
    expect((await client.morphology('')).readings, isEmpty);
    expect(transport.calls, 0);
  });

  test('malformed schemas have a distinct operational error', () async {
    final _Transport transport = _Transport(<String, Object?>{'error': 'bad'});
    final AotClient client = AotClient(transport: transport);
    addTearDown(client.dispose);
    final Matcher malformed = throwsA(
      isA<AotException>().having(
        (AotException e) => e.code,
        'code',
        AotErrorCode.malformedResponse,
      ),
    );
    await expectLater(client.analyze('private input'), malformed);
    await expectLater(client.morphology('private'), malformed);
  });

  test('transport error status is not converted into a clean result', () async {
    const AotException error = AotException(
      AotErrorCode.http,
      'AOT returned HTTP 400.',
      statusCode: 400,
    );
    final _Transport transport = _Transport(null)..error = error;
    final AotClient client = AotClient(transport: transport);
    addTearDown(client.dispose);
    await expectLater(client.analyze('Ich geht.'), throwsA(same(error)));
  });

  test('disposal is idempotent and rejects late/incoming results', () async {
    final Completer<Object?> response = Completer<Object?>();
    final _Transport transport = _Transport(null)..delayed = response.future;
    final AotClient client = AotClient(transport: transport);
    final Future<AotAnalysis> analysis = client.analyze('Ich gehe nach Hause.');
    final Future<void> assertion = expectLater(
      analysis,
      throwsA(
        isA<AotException>().having(
          (AotException e) => e.code,
          'code',
          AotErrorCode.disposed,
        ),
      ),
    );
    await client.dispose();
    await client.dispose();
    response.complete(syntaxFixture());
    await assertion;
    expect(transport.disposals, 1);
    await expectLater(client.analyze('Hallo'), throwsA(isA<AotException>()));
    expect(transport.calls, 1);
  });
}

final class _Transport implements AotTransport {
  _Transport(this.response);
  final Object? response;
  Object? error;
  Future<Object?>? delayed;
  String? action;
  String? query;
  AotLanguage? language;
  bool? withParadigms;
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
    this.action = action;
    this.query = query;
    this.language = language;
    this.withParadigms = withParadigms;
    if (error case final Object failure) throw failure;
    return delayed ?? response;
  }

  @override
  Future<void> dispose() async {
    disposals++;
  }
}
