import 'package:quds_proofing_gector/quds_proofing_gector.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  late TestBundle fixtures;
  setUpAll(() async {
    fixtures = await TestBundle.load();
  });

  GectorDecoder decoder(
    ScriptedBackend backend, {
    GectorSegmentationOptions? segmentation,
    int maximumTokens = 512,
    int maximumPasses = 5,
  }) => GectorDecoder.guarded(
    configuration: fixtures.bundle.configuration,
    tokenizer: fixtures.bundle.tokenizer,
    backend: backend,
    guards: GectorGermanGuards.fromJson(
      fixtures.bundle.guardsJson,
      configuration: fixtures.bundle.configuration,
      lexicon: GectorWordSetLexicon(const <String>[
        'Buch',
        'Haus',
        'haus',
        'sind',
        'zufrieden',
      ]),
    ),
    options: GectorDecodeOptions(
      maximumPasses: maximumPasses,
      maximumTokens: maximumTokens,
      segmentation: segmentation ?? GectorSegmentationOptions(),
    ),
  );

  List<String> keep(String text) {
    final source = GectorSourceText(text, fixtures.bundle.configuration);
    return List<String>.filled(source.words(source.plain).length + 1, r'$KEEP');
  }

  test(
    'short guarded input retains exact single-sequence IDs and edits',
    () async {
      const steps = <List<String>>[
        [r'$KEEP', r'$KEEP', r'$TRANSFORM_VERB_P3S_P3P', r'$KEEP'],
        [r'$KEEP', r'$KEEP', r'$KEEP', r'$KEEP'],
      ];
      final segmentedBackend = ScriptedBackend(
        fixtures.bundle.configuration,
        steps,
      );
      final originalBackend = ScriptedBackend(
        fixtures.bundle.configuration,
        steps,
      );
      final original = GectorDecoder.guarded(
        configuration: fixtures.bundle.configuration,
        tokenizer: fixtures.bundle.tokenizer,
        backend: originalBackend,
        guards: GectorGermanGuards.fromJson(
          fixtures.bundle.guardsJson,
          configuration: fixtures.bundle.configuration,
          lexicon: GectorWordSetLexicon(const <String>['sind']),
        ),
      );
      final before = await original.correct('Wir ist zufrieden.');
      final after = await decoder(
        segmentedBackend,
      ).correct('Wir ist zufrieden.');
      expect(after.corrected, before.corrected);
      expect(after.segmentCount, 1);
      expect(
        after.passes.map((pass) => pass.input.inputIds),
        before.passes.map((pass) => pass.input.inputIds),
      );
      expect(
        after.edits.map((edit) => (edit.start, edit.end, edit.replacement)),
        before.edits.map((edit) => (edit.start, edit.end, edit.replacement)),
      );
    },
  );

  test(
    'reference decoder rejects segmentation instead of changing its oracle',
    () {
      expect(
        () => GectorDecoder.reference(
          configuration: fixtures.bundle.configuration,
          tokenizer: fixtures.bundle.tokenizer,
          backend: ScriptedBackend(fixtures.bundle.configuration, const []),
          options: GectorDecodeOptions(
            segmentation: GectorSegmentationOptions(),
          ),
        ),
        throwsArgumentError,
      );
      expect(
        () => GectorDecodeOptions(
          maximumTokens: 32,
          segmentation: GectorSegmentationOptions(),
        ),
        throwsArgumentError,
      );
    },
  );

  test(
    'paragraph beyond 512 tokens is covered completely with bounded forwards',
    () async {
      final text = List<String>.filled(180, 'Das ist gut.').join(' ');
      final backend = ScriptedBackend(fixtures.bundle.configuration, const []);
      final result = await decoder(backend).correct(text);
      expect(result.complete, isTrue);
      expect(result.guarded, isTrue);
      expect(result.original, text);
      expect(result.corrected, text);
      expect(result.edits, isEmpty);
      expect(result.segmentCount, greaterThan(1));
      expect(result.passes.length, result.segmentCount);
      expect(
        result.passes.every((pass) => pass.input.tokenCount <= 64),
        isTrue,
      );
      expect(
        result.forwardTokens,
        result.passes.fold<int>(0, (sum, pass) => sum + pass.input.tokenCount),
      );
      expect(result.passes.first.sourceStart, 0);
      expect(result.passes.last.sourceStart, greaterThan(0));
    },
  );

  test(
    'late correction rebases UTF-16 after emoji, CRLF and original spaces',
    () async {
      const first = '  😊 Gut.\r\n';
      const text = '${first}Wir ist zufrieden.';
      final backend = ScriptedBackend(fixtures.bundle.configuration, [
        keep(first),
        const [r'$KEEP', r'$KEEP', r'$TRANSFORM_VERB_P3S_P3P', r'$KEEP'],
        const [r'$KEEP', r'$KEEP', r'$KEEP', r'$KEEP'],
      ]);
      final result = await decoder(
        backend,
        segmentation: GectorSegmentationOptions(targetTokens: 5),
      ).correct(text);
      expect(result.complete, isTrue);
      expect(result.segmentCount, 2);
      expect(result.corrected, '${first}Wir sind zufrieden.');
      expect(result.edits.single.start, first.length + 4);
      expect(result.edits.single.end, first.length + 7);
      expect(result.edits.single.original, 'ist');
      expect(result.passes.map((pass) => pass.sourceStart), [
        0,
        first.length,
        first.length,
      ]);
      expect(
        GectorSourceText(
          text,
          fixtures.bundle.configuration,
        ).apply(result.edits),
        result.corrected,
      );
    },
  );

  test(
    'repeated phrases cannot move a correction to a different occurrence',
    () async {
      const text = 'Buch. Buch. Buch.';
      final backend = ScriptedBackend(fixtures.bundle.configuration, const [
        [r'$KEEP', r'$KEEP'],
        [r'$KEEP', r'$REPLACE_Haus'],
        [r'$KEEP', r'$KEEP'],
        [r'$KEEP', r'$KEEP'],
      ]);
      final result = await decoder(
        backend,
        segmentation: GectorSegmentationOptions(targetTokens: 3),
      ).correct(text);
      expect(result.corrected, 'Buch. Haus. Buch.');
      expect(result.edits.single.start, 6);
      expect(result.edits.single.end, 10);
      expect(result.edits.single.original, 'Buch');
      expect(result.segmentCount, 3);
    },
  );

  test(
    'later START tags cannot introduce new paragraph-start insertions',
    () async {
      final backend = ScriptedBackend(fixtures.bundle.configuration, const [
        [r'$KEEP', r'$KEEP'],
        [r'$APPEND_sind', r'$KEEP'],
      ]);
      final result = await decoder(
        backend,
        segmentation: GectorSegmentationOptions(targetTokens: 3),
      ).correct('Buch. Buch.');
      expect(result.complete, isTrue);
      expect(result.corrected, 'Buch. Buch.');
      expect(result.edits, isEmpty);
      expect(backend.calls, 2);
      final atStart = ScriptedBackend(fixtures.bundle.configuration, const [
        [r'$APPEND_sind', r'$KEEP'],
        [r'$KEEP', r'$KEEP', r'$KEEP'],
      ]);
      expect((await decoder(atStart).correct('Buch.')).corrected, 'sind Buch.');
    },
  );

  test(
    'later case-differing duplicates do not inherit the initial exception',
    () async {
      final backend = ScriptedBackend(fixtures.bundle.configuration, const [
        [r'$KEEP', r'$KEEP'],
        [r'$KEEP', r'$DELETE', r'$KEEP'],
      ]);
      final result = await decoder(
        backend,
        segmentation: GectorSegmentationOptions(targetTokens: 4),
      ).correct('Buch. Haus haus.');
      expect(result.complete, isTrue);
      expect(result.corrected, 'Buch. Haus haus.');
      expect(result.edits, isEmpty);
      final atStart = ScriptedBackend(fixtures.bundle.configuration, const [
        [r'$KEEP', r'$DELETE', r'$KEEP'],
        [r'$KEEP', r'$KEEP'],
      ]);
      expect((await decoder(atStart).correct('Haus haus.')).corrected, 'haus.');
    },
  );

  test(
    'a late cycle discards an earlier completed correction atomically',
    () async {
      const text = 'Buch. Haus.';
      final backend = ScriptedBackend(fixtures.bundle.configuration, const [
        [r'$KEEP', r'$REPLACE_Haus'],
        [r'$KEEP', r'$KEEP'],
        [r'$KEEP', r'$REPLACE_Buch'],
        [r'$KEEP', r'$REPLACE_Haus'],
      ]);
      final result = await decoder(
        backend,
        segmentation: GectorSegmentationOptions(targetTokens: 3),
      ).correct(text);
      expect(result.stopReason, GectorStopReason.cycle);
      expect(result.complete, isFalse);
      expect(result.corrected, text);
      expect(result.edits, isEmpty);
      expect(result.passes, hasLength(4));
    },
  );

  test('a late pass limit reports no earlier edits as complete', () async {
    const text = 'Buch. Haus.';
    final backend = ScriptedBackend(fixtures.bundle.configuration, const [
      [r'$KEEP', r'$KEEP'],
      [r'$KEEP', r'$REPLACE_Buch'],
    ]);
    final result = await decoder(
      backend,
      maximumPasses: 1,
      segmentation: GectorSegmentationOptions(targetTokens: 3),
    ).correct(text);
    expect(result.stopReason, GectorStopReason.passLimit);
    expect(result.complete, isFalse);
    expect(result.corrected, text);
    expect(result.edits, isEmpty);
  });

  test(
    'a late backend failure cannot return earlier speculative edits',
    () async {
      final backend = ScriptedBackend(fixtures.bundle.configuration, const [
        [r'$KEEP', r'$REPLACE_Haus'],
        [r'$KEEP', r'$KEEP'],
      ], failOnCall: 3);
      await expectLater(
        decoder(
          backend,
          segmentation: GectorSegmentationOptions(targetTokens: 3),
        ).correct('Buch. Haus.'),
        throwsStateError,
      );
      expect(backend.calls, 3);
    },
  );

  test(
    'cancellation after a segment prevents another native forward',
    () async {
      final backend = ScriptedBackend(fixtures.bundle.configuration, const []);
      await expectLater(
        decoder(
          backend,
          segmentation: GectorSegmentationOptions(targetTokens: 3),
        ).correct('Buch. Haus.', isCancelled: () => backend.calls >= 1),
        throwsA(isA<GectorCancelledException>()),
      );
      expect(backend.calls, 1);
    },
  );

  test(
    'late invalid or oversized source is rejected before any inference',
    () async {
      for (final text in <String>[
        'Das ist gut. ${List<String>.filled(520, 'Wort').join(' ')}.',
        'Das ist gut. \ud800',
      ]) {
        final backend = ScriptedBackend(
          fixtures.bundle.configuration,
          const [],
        );
        await expectLater(
          decoder(backend).correct(text),
          throwsA(isA<Exception>()),
        );
        expect(backend.calls, 0);
      }
    },
  );

  test(
    'segment and total-token admission budgets fail before any inference',
    () async {
      for (final segmentation in <GectorSegmentationOptions>[
        GectorSegmentationOptions(targetTokens: 3, maximumSegments: 1),
        GectorSegmentationOptions(targetTokens: 3, maximumTotalTokens: 5),
      ]) {
        final backend = ScriptedBackend(
          fixtures.bundle.configuration,
          const [],
        );
        await expectLater(
          decoder(backend, segmentation: segmentation).correct('Buch. Haus.'),
          throwsA(isA<GectorCapacityException>()),
        );
        expect(backend.calls, 0);
      }
    },
  );

  test(
    'expansion consumes one request-wide actual forward-token budget',
    () async {
      final backend = ScriptedBackend(fixtures.bundle.configuration, const [
        [r'$KEEP', r'$APPEND_sind'],
        [r'$KEEP', r'$KEEP', r'$KEEP'],
        [r'$KEEP', r'$APPEND_sind'],
        [r'$KEEP', r'$KEEP', r'$KEEP'],
      ]);
      await expectLater(
        decoder(
          backend,
          maximumPasses: 2,
          segmentation: GectorSegmentationOptions(
            targetTokens: 3,
            maximumTotalTokens: 6,
          ),
        ).correct('Buch. Buch.'),
        throwsA(
          isA<GectorCapacityException>().having(
            (error) => error.message,
            'message',
            contains('request-wide'),
          ),
        ),
      );
      expect(backend.calls, 3);
    },
  );

  test('expansion never escapes a segment hard token limit', () async {
    final backend = ScriptedBackend(fixtures.bundle.configuration, const [
      [r'$KEEP', r'$APPEND_sind'],
    ]);
    await expectLater(
      decoder(
        backend,
        maximumTokens: 3,
        segmentation: GectorSegmentationOptions(targetTokens: 3),
      ).correct('Buch. Buch.'),
      throwsA(isA<GectorCapacityException>()),
    );
    expect(backend.calls, 1);
  });
}
