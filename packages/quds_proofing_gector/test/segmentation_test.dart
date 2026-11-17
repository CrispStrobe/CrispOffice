import 'package:quds_proofing_gector/quds_proofing_gector.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  late TestBundle fixtures;
  setUpAll(() async {
    fixtures = await TestBundle.load();
  });

  GectorSegmenter segmenter({
    int targetTokens = 64,
    int maximumTokens = 512,
    int maximumSegments = 32,
    int maximumTotalTokens = 4096,
    int maximumTextCodeUnits = 32768,
  }) => GectorSegmenter(
    configuration: fixtures.bundle.configuration,
    tokenizer: fixtures.bundle.tokenizer,
    options: GectorSegmentationOptions(
      targetTokens: targetTokens,
      maximumSegments: maximumSegments,
      maximumTotalTokens: maximumTotalTokens,
    ),
    maximumTokens: maximumTokens,
    maximumTextCodeUnits: maximumTextCodeUnits,
  );

  int tokens(String text) {
    final source = GectorSourceText(text, fixtures.bundle.configuration);
    return fixtures.bundle.tokenizer
        .encode(source.words(source.plain))
        .tokenCount;
  }

  void expectPartition(String original, List<GectorTextSegment> segments) {
    expect(segments, isNotEmpty);
    final boundaries = GectorSourceText(
      original,
      fixtures.bundle.configuration,
    ).graphemeBoundaries;
    var next = 0;
    for (final segment in segments) {
      expect(segment.start, next);
      expect(segment.end, lessThanOrEqualTo(original.length));
      expect(boundaries, contains(segment.start));
      expect(boundaries, contains(segment.end));
      expect(original.substring(segment.start, segment.end), segment.text);
      expect(segment.initialTokenCount, tokens(segment.text));
      next = segment.end;
    }
    expect(next, original.length);
    expect(segments.map((segment) => segment.text).join(), original);
  }

  test('the default short path retains the complete source as one slice', () {
    final text = '${List<String>.filled(15, 'Das ist gut.').join(' ')}  \r\n';
    expect(tokens(text), 61);
    final plan = segmenter().plan(text);
    expectPartition(text, plan);
    expect(plan, hasLength(1));
    expect(plan.single.text, text);
    expect(() => plan.clear(), throwsUnsupportedError);
  });

  test('packs whole sentences greedily up to the preferred token size', () {
    final text = List<String>.filled(16, 'Das ist gut.').join(' ');
    expect(tokens(text), 65);
    final plan = segmenter().plan(text);
    expectPartition(text, plan);
    expect(plan, hasLength(2));
    expect(
      plan.first.text,
      '${List<String>.filled(15, 'Das ist gut.').join(' ')} ',
    );
    expect(plan.map((segment) => segment.initialTokenCount), <int>[61, 5]);
  });

  test('counts real WordPieces instead of source words or code units', () {
    const first = 'Donaudampfschifffahrtsgesellschaften sind gut.';
    final firstTokens = tokens(first);
    final source = GectorSourceText(first, fixtures.bundle.configuration);
    expect(firstTokens, greaterThan(source.words(source.plain).length + 2));
    const text = '$first Das ist gut. Das ist gut.';
    final plan = segmenter(targetTokens: firstTokens + 3).plan(text);
    expectPartition(text, plan);
    expect(plan.first.text, '$first ');
    expect(plan.first.initialTokenCount, firstTokens);
    expect(plan.length, greaterThan(1));
  });

  test('an unsplittable medium sentence stays intact below the hard limit', () {
    final long = '${List<String>.filled(126, 'Wort').join(' ')}.';
    final text = '$long Das ist gut.';
    final plan = segmenter().plan(text);
    expectPartition(text, plan);
    expect(plan, hasLength(2));
    expect(plan.first.text, '$long ');
    expect(plan.first.initialTokenCount, 128);
  });

  test('admits exactly 512 tokens but never truncates a larger sentence', () {
    final exact = '${List<String>.filled(510, 'Wort').join(' ')}.';
    final plan = segmenter().plan(exact);
    expectPartition(exact, plan);
    expect(plan.single.initialTokenCount, 512);
    final tooLong = '${List<String>.filled(511, 'Wort').join(' ')}.';
    expect(
      () => segmenter().plan(tooLong),
      throwsA(
        isA<GectorCapacityException>().having(
          (error) => error.message,
          'message',
          contains('no text was truncated'),
        ),
      ),
    );
  });

  test('a late oversized sentence fails the complete plan', () {
    final planner = segmenter(targetTokens: 5);
    final tooLong = '${List<String>.filled(511, 'Wort').join(' ')}.';
    expect(
      () => planner.plan('Das ist gut. $tooLong'),
      throwsA(isA<GectorCapacityException>()),
    );
    // A failed plan does not leave a partial plan or consume later capacity.
    expect(planner.plan('Das ist gut.').single.text, 'Das ist gut.');
  });

  test('uses tighter hard token limits without splitting an entire clause', () {
    final text = '${List<String>.filled(15, 'Wort').join(' ')}.';
    expect(
      () => segmenter(targetTokens: 5, maximumTokens: 16).plan(text),
      throwsA(isA<GectorCapacityException>()),
    );
  });

  test(
    'segment count and total tokens include every planned special token',
    () {
      const text = 'Das ist gut. Das ist gut.';
      expect(tokens(text), 9);
      expect(
        () => segmenter(targetTokens: 5, maximumSegments: 1).plan(text),
        throwsA(isA<GectorCapacityException>()),
      );
      expect(
        () => segmenter(targetTokens: 5, maximumTotalTokens: 9).plan(text),
        throwsA(isA<GectorCapacityException>()),
      );
      final plan = segmenter(
        targetTokens: 5,
        maximumTotalTokens: 10,
      ).plan(text);
      expectPartition(text, plan);
      expect(plan, hasLength(2));
      expect(plan.map((segment) => segment.initialTokenCount), <int>[5, 5]);
      expect(
        () => segmenter(maximumTotalTokens: 4).plan('Das ist gut.'),
        throwsA(isA<GectorCapacityException>()),
      );
    },
  );

  test('the input ceiling counts original UTF-16 units before planning', () {
    const text = '😊😊😊😊😊😊';
    expect(text.length, 12);
    expect(
      () => segmenter(maximumTextCodeUnits: 11).plan(text),
      throwsA(isA<GectorCapacityException>()),
    );
    expectPartition(text, segmenter(maximumTextCodeUnits: 12).plan(text));
  });

  test(
    'preserves exact UTF-16 ranges, quotes, decomposed text and spacing',
    () {
      const first = '😊 Anna’s Buch ist gut.\r\n\t';
      const second = 'Mu\u0308de ist er nicht.\u00a0  ';
      const last = '„Wir ist zufrieden!“  \n';
      const text = '$first$second$last';
      final plan = segmenter(targetTokens: 2).plan(text);
      expectPartition(text, plan);
      expect(plan.map((segment) => segment.text), <String>[
        first,
        second,
        last,
      ]);
      expect(plan.map((segment) => segment.start), <int>[
        0,
        first.length,
        first.length + second.length,
      ]);
    },
  );

  test('a combining mark on punctuation is not a source boundary', () {
    const text = 'Das ist gut.\u0301 Danach ist es gut. Jetzt ist es gut.';
    final plan = segmenter(targetTokens: 2).plan(text);
    expectPartition(text, plan);
    expect(plan.map((segment) => segment.text), <String>[
      'Das ist gut.\u0301 Danach ist es gut. ',
      'Jetzt ist es gut.',
    ]);
  });

  final ambiguousPrefixes = <String>[
    'Wir treffen Dr. Müller.',
    'Wir treffen Prof. Müller.',
    'Herr A. Müller kommt.',
    'Herr A\u0308. Müller kommt.',
    'Es ist der 3. Oktober.',
    'Die Zahl 3.14 ist gut.',
    'Version 1.2.3 ist gut.',
    'Das gilt z. B. Heute bleibt es gut.',
    'Das gilt usw. Heute bleibt es gut.',
    'Das steht in Abschn. Zwei des Buches.',
    'Die Firma BASF. Bleibt im Text.',
    'Das ist gut... Vielleicht bleibt es gut.',
    'Das ist gut… Vielleicht bleibt es gut.',
    'Das ist gut. vielleicht bleibt es gut.',
    'Das ist gut; Vielleicht bleibt es gut.',
    'Das ist gut\nVielleicht bleibt es gut.',
  ];
  for (final prefix in ambiguousPrefixes) {
    test('keeps ambiguous punctuation together: $prefix', () {
      final text = '$prefix Danach ist es gut.';
      final plan = segmenter(targetTokens: 2).plan(text);
      expectPartition(text, plan);
      expect(plan.map((segment) => segment.text), <String>[
        '$prefix ',
        'Danach ist es gut.',
      ]);
    });
  }

  final closedContexts = <String>[
    '„Das ist gut. Es bleibt gut.“',
    '“Das ist gut. Es bleibt gut.”',
    '«Das ist gut. Es bleibt gut.»',
    '‹Das ist gut. Es bleibt gut.›',
    '‚Das ist gut. Es bleibt gut.‘',
    '‘Das ist gut. Es bleibt gut.’',
    '"Das ist gut. Es bleibt gut."',
    "'Das ist gut. Es bleibt gut.'",
    '(Das ist gut. Es bleibt gut.)',
    '[Das ist gut. Es bleibt gut.]',
    '{Das ist gut. Es bleibt gut.}',
    '„(Das ist gut. Es bleibt gut.)“',
  ];
  for (final prefix in closedContexts) {
    test('retains matched delimiters around whole context: $prefix', () {
      final text = '$prefix Danach ist es gut.';
      final plan = segmenter(targetTokens: 2).plan(text);
      expectPartition(text, plan);
      expect(plan.map((segment) => segment.text), <String>[
        '$prefix ',
        'Danach ist es gut.',
      ]);
    });
  }

  test('quoted punctuation followed by narration does not cut the clause', () {
    const first = '„Ist das gut?“, fragte sie. ';
    const text = '${first}Danach ist es gut.';
    final plan = segmenter(targetTokens: 2).plan(text);
    expectPartition(text, plan);
    expect(plan.map((segment) => segment.text), <String>[
      first,
      'Danach ist es gut.',
    ]);
  });

  test('unclosed delimiters keep an uncertain source context intact', () {
    for (final open in <String>['„', '"', '(', '[', '{']) {
      final text = '${open}Das ist gut. Es ist gut. Weiter ist es gut.';
      final plan = segmenter(targetTokens: 2).plan(text);
      expectPartition(text, plan);
      expect(plan, hasLength(1));
    }
  });

  test('question and exclamation runs retain their source punctuation', () {
    const text = 'Ist das gut?! Ja, das ist gut!! Danach geht es gut?  ';
    final plan = segmenter(targetTokens: 2).plan(text);
    expectPartition(text, plan);
    expect(plan.map((segment) => segment.text), <String>[
      'Ist das gut?! ',
      'Ja, das ist gut!! ',
      'Danach geht es gut?  ',
    ]);
  });

  final protectedPrefixes = <String>[
    '`Das ist gut. Es ist gut.` bleibt im Text.',
    '``Das ist gut. `Es ist gut.` `` bleibt im Text.',
    '```Das ist gut.\nEs ist gut.``` bleibt im Text.',
    '`(Das ist gut. Es ist gut.` bleibt im Text.',
    'https://beispiel.de/Dr.Meyer?Hallo=Welt bleibt im Text.',
    'max.mustermann@beispiel.de bleibt im Text.',
  ];
  for (final prefix in protectedPrefixes) {
    test(
      'does not divide protected source or borrow its delimiters: $prefix',
      () {
        final text = '$prefix Danach ist es gut.';
        final plan = segmenter(targetTokens: 2).plan(text);
        expectPartition(text, plan);
        expect(plan.map((segment) => segment.text), <String>[
          '$prefix ',
          'Danach ist es gut.',
        ]);
      },
    );
  }

  test(
    'empty and whitespace-only text remain complete exact source slices',
    () {
      for (final text in <String>['', ' \t\r\n\u00a0']) {
        final plan = segmenter().plan(text);
        expectPartition(text, plan);
        expect(plan, hasLength(1));
        expect(plan.single.initialTokenCount, 2);
      }
    },
  );

  test(
    'invalid source after an early sentence fails before any partial plan',
    () {
      expect(
        () => segmenter(targetTokens: 2).plan('Das ist gut. Wort \ud800'),
        throwsFormatException,
      );
      expect(
        () => segmenter(targetTokens: 2).plan('Das ist gut. \u200d'),
        throwsFormatException,
      );
    },
  );

  test('invalid planning limits fail explicitly', () {
    for (final factory in <GectorSegmentationOptions Function()>[
      () => GectorSegmentationOptions(targetTokens: 1),
      () => GectorSegmentationOptions(targetTokens: 513),
      () => GectorSegmentationOptions(maximumSegments: 0),
      () => GectorSegmentationOptions(maximumSegments: 129),
      () => GectorSegmentationOptions(maximumTotalTokens: 1),
      () => GectorSegmentationOptions(maximumTotalTokens: 32769),
    ]) {
      expect(factory, throwsArgumentError);
    }
    expect(() => segmenter(maximumTokens: 32), throwsArgumentError);
    expect(() => segmenter(maximumTokens: 513), throwsArgumentError);
    expect(() => segmenter(maximumTextCodeUnits: 0), throwsArgumentError);
    expect(() => segmenter(maximumTextCodeUnits: 32769), throwsArgumentError);
  });
}
