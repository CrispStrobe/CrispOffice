import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:quds_proofing_gector/quds_proofing_gector.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  late TestBundle fixtures;
  setUpAll(() async {
    fixtures = await TestBundle.load();
  });
  final Object? raw = jsonDecode(
    File('test/fixtures/decoder_oracle.json').readAsStringSync(),
  );
  final oracle = raw! as Map<String, Object?>;
  for (final value in oracle['cases']! as List<Object?>) {
    final row = value! as Map<String, Object?>;
    test(
      'frozen reference ${row['id']}: words, IDs, tags, passes and UTF-16 edits',
      () async {
        final rawPasses = (row['passes']! as List<Object?>)
            .cast<Map<String, Object?>>();
        final backend = ScriptedBackend(
          fixtures.bundle.configuration,
          <List<String>>[
            for (final p in rawPasses)
              (p['labels']! as List<Object?>).cast<String>(),
          ],
        );
        final decoder = GectorDecoder.reference(
          configuration: fixtures.bundle.configuration,
          tokenizer: fixtures.bundle.tokenizer,
          backend: backend,
        );
        final result = await decoder.correct(row['input']! as String);
        expect(result.corrected, row['corrected']);
        expect(result.passes.length, rawPasses.length);
        for (var i = 0; i < result.passes.length; i++) {
          expect(result.passes[i].words, rawPasses[i]['words']);
          expect(result.passes[i].input.inputIds, rawPasses[i]['input_ids']);
          expect(
            result.passes[i].input.firstSubwordIndices,
            rawPasses[i]['first_subword_indices'],
          );
          expect(
            result.passes[i].tags.map((tag) => tag.label),
            rawPasses[i]['labels'],
          );
        }
        expect(<Map<String, Object>>[
          for (final e in result.edits)
            <String, Object>{
              'start': e.start,
              'end': e.end,
              'original': e.original,
              'replacement': e.replacement,
            },
        ], row['suggestions_utf16']);
      },
    );
  }

  test(
    'guarded decoding retains the frozen wir correction and source span',
    () async {
      final row = (oracle['cases']! as List<Object?>)
          .cast<Map<String, Object?>>()
          .singleWhere((row) => row['id'] == 'verb-wir');
      final rawPasses = (row['passes']! as List<Object?>)
          .cast<Map<String, Object?>>();
      final backend =
          ScriptedBackend(fixtures.bundle.configuration, <List<String>>[
            for (final pass in rawPasses)
              (pass['labels']! as List<Object?>).cast<String>(),
          ]);
      final decoder = GectorDecoder.guarded(
        configuration: fixtures.bundle.configuration,
        tokenizer: fixtures.bundle.tokenizer,
        backend: backend,
        guards: GectorGermanGuards.fromJson(
          fixtures.bundle.guardsJson,
          configuration: fixtures.bundle.configuration,
          lexicon: GectorWordSetLexicon(const <String>['sind']),
        ),
      );
      final result = await decoder.correct(row['input']! as String);
      expect(result.guarded, isTrue);
      expect(result.complete, isTrue);
      expect(result.corrected, row['corrected']);
      expect(result.passes.length, rawPasses.length);
      expect(<Map<String, Object>>[
        for (final edit in result.edits)
          <String, Object>{
            'start': edit.start,
            'end': edit.end,
            'original': edit.original,
            'replacement': edit.replacement,
          },
      ], row['suggestions_utf16']);
    },
  );

  test('explicit capacity failure never truncates a long input', () async {
    final backend = ScriptedBackend(fixtures.bundle.configuration, const []);
    final decoder = GectorDecoder.reference(
      configuration: fixtures.bundle.configuration,
      tokenizer: fixtures.bundle.tokenizer,
      backend: backend,
      options: GectorDecodeOptions(maximumTokens: 8),
    );
    await expectLater(
      decoder.correct('Das ist ein sehr langer deutscher Satz mit Wörtern.'),
      throwsA(isA<GectorCapacityException>()),
    );
    expect(backend.calls, 0);
  });

  test('pass limit and a cycle are visible incomplete results', () async {
    final config = fixtures.bundle.configuration;
    final decoder = GectorDecoder.reference(
      configuration: config,
      tokenizer: fixtures.bundle.tokenizer,
      backend: ScriptedBackend(config, const [
        [r'$KEEP', r'$REPLACE_Haus'],
      ]),
      options: GectorDecodeOptions(maximumPasses: 1),
    );
    final capped = await decoder.correct('Buch.');
    expect(capped.stopReason, GectorStopReason.passLimit);
    expect(capped.complete, isFalse);
    final cycling = GectorDecoder.reference(
      configuration: config,
      tokenizer: fixtures.bundle.tokenizer,
      backend: ScriptedBackend(config, const [
        [r'$KEEP', r'$REPLACE_Haus'],
        [r'$KEEP', r'$REPLACE_Buch'],
      ]),
    );
    final cycle = await cycling.correct('Buch.');
    expect(cycle.stopReason, GectorStopReason.cycle);
    expect(cycle.complete, isFalse);
    expect(cycle.passes.length, 2);
  });

  test(
    'cancellation after a forward stops before edits/another pass',
    () async {
      var cancelled = false;
      final backend = ScriptedBackend(
        fixtures.bundle.configuration,
        const [],
        delay: const Duration(milliseconds: 30),
      );
      final decoder = GectorDecoder.reference(
        configuration: fixtures.bundle.configuration,
        tokenizer: fixtures.bundle.tokenizer,
        backend: backend,
      );
      final future = decoder.correct(
        'Das ist gut.',
        isCancelled: () => cancelled,
      );
      final assertion = expectLater(
        future,
        throwsA(isA<GectorCancelledException>()),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      cancelled = true;
      await assertion;
      expect(backend.calls, 1);
    },
  );

  test('head shapes and non-finite values fail before any tag is accepted', () {
    final input = fixtures.bundle.tokenizer.encode(<String>['gut']);
    final wrong = GectorLogits(
      tokenCount: 3,
      labels: Float32List(1),
      detection: Float32List(6),
    );
    expect(() => wrong.validate(input, 5000), throwsFormatException);
    final invalid = GectorLogits(
      tokenCount: 3,
      labels: Float32List(15000)..[5] = double.nan,
      detection: Float32List(6),
    );
    expect(() => invalid.validate(input, 5000), throwsFormatException);
  });

  test(
    'Unicode case expansion and suffix/verb transforms follow source semantics',
    () {
      final decoder = GectorDecoder.reference(
        configuration: fixtures.bundle.configuration,
        tokenizer: fixtures.bundle.tokenizer,
        backend: ScriptedBackend(fixtures.bundle.configuration, const []),
      );
      expect(decoder.edit('straße', r'$TRANSFORM_CASE_UPPER'), 'STRASSE');
      expect(decoder.edit('ßA', r'$TRANSFORM_CASE_CAPITAL'), 'SSa');
      expect(decoder.edit('İ', r'$TRANSFORM_CASE_LOWER'), 'i\u0307');
      expect(decoder.edit('ΟΣ', r'$TRANSFORM_CASE_LOWER'), 'ος');
      expect(decoder.edit('Hunde', r'$TRANSFORM_SUF_e_'), 'Hund');
      expect(decoder.edit('Tag', r'$TRANSFORM_SUF__e'), 'Tage');
      expect(decoder.edit('gehen', r'$TRANSFORM_VERB_P1P_P2S'), 'gehst');
      expect(
        decoder.edit('unbekannt', r'$TRANSFORM_VERB_P1P_P2S'),
        'unbekannt',
      );
      expect(
        () => decoder.edit('Tag', r'$TRANSFORM_SOMETHING_NEW'),
        throwsFormatException,
      );
    },
  );

  test('WordPiece rejects vanished words and preserves cased Unicode', () {
    final tokenizer = fixtures.bundle.tokenizer;
    expect(
      tokenizer.encode(<String>['Mädchen']).inputIds.length,
      greaterThan(2),
    );
    expect(() => tokenizer.encode(<String>['\u200d']), throwsFormatException);
    expect(
      () => GectorSourceText('\ud800x', fixtures.bundle.configuration),
      throwsFormatException,
    );
    final empty = GectorSourceText(' \t\n', fixtures.bundle.configuration);
    expect(empty.words(empty.plain), isEmpty);
  });
}
