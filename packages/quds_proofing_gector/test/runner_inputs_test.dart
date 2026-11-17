import 'package:quds_proofing_gector/quds_proofing_gector.dart';
import 'package:test/test.dart';

import '../../../tools/proofing/german_model/run_gector_dart.dart' as runner;
import 'support.dart';

void main() {
  late TestBundle fixtures;
  setUpAll(() async {
    fixtures = await TestBundle.load();
  });

  const requiredArguments = <String>[
    '--bundle-dir',
    'bundle',
    '--model',
    'model',
    '--model-sha256',
    'model-hash',
    '--library',
    'library',
    '--library-sha256',
    'library-hash',
    '--reference',
    'reference',
    '--output',
    'output',
  ];

  test('native thread CLI preserves two threads by default', () {
    expect(
      runner.gectorRunnerArguments(requiredArguments)['native-threads'],
      '2',
    );
  });

  test('native thread CLI admits explicit bounded decimal counts', () {
    for (final threads in <String>['1', '2', '4', '8', '64']) {
      expect(
        runner.gectorRunnerArguments(<String>[
          ...requiredArguments,
          '--native-threads',
          threads,
        ])['native-threads'],
        threads,
      );
    }
  });

  test('native thread CLI rejects invalid counts before opening assets', () {
    for (final invalid in <String>[
      '0',
      '65',
      '-1',
      '2.5',
      '1e0',
      '',
      'many',
      ' 2 ',
      '0x2',
      '+2',
    ]) {
      expect(
        () => runner.gectorRunnerArguments(<String>[
          ...requiredArguments,
          '--native-threads',
          invalid,
        ]),
        throwsArgumentError,
        reason: invalid,
      );
    }
  });

  test('thread CLI rejects missing, duplicate and unknown options', () {
    for (final extra in <List<String>>[
      ['--native-threads'],
      ['--native-threads', '2', '--native-threads', '4'],
      ['--thread-count', '2'],
    ]) {
      expect(
        () => runner.gectorRunnerArguments(<String>[
          ...requiredArguments,
          ...extra,
        ]),
        throwsArgumentError,
      );
    }
  });

  test('reuse CLI requires an explicit segmented mode and boolean value', () {
    expect(
      runner
          .gectorRunnerArguments(requiredArguments)
          .containsKey('reuse-identical-inputs'),
      isFalse,
    );
    expect(
      () => runner.gectorRunnerArguments(<String>[
        ...requiredArguments,
        '--reuse-identical-inputs',
        'true',
      ]),
      throwsArgumentError,
    );
    for (final invalid in <String>['1', 'yes', 'TRUE', '']) {
      expect(
        () => runner.gectorRunnerArguments(<String>[
          ...requiredArguments,
          '--segment-target-tokens',
          '64',
          '--reuse-identical-inputs',
          invalid,
        ]),
        throwsArgumentError,
      );
    }
    for (final enabled in <String>['true', 'false']) {
      final parsed = runner.gectorRunnerArguments(<String>[
        ...requiredArguments,
        '--segment-target-tokens',
        '64',
        '--reuse-identical-inputs',
        enabled,
      ]);
      expect(parsed['reuse-identical-inputs'], enabled);
      expect(parsed['segment-target-tokens'], '64');
    }
    expect(
      () => runner.gectorRunnerArguments(<String>[
        ...requiredArguments,
        '--segment-target-tokens',
        '64',
        '--reuse-identical-inputs',
        'true',
        '--reuse-identical-inputs',
        'false',
      ]),
      throwsArgumentError,
    );
  });

  for (final budget in <int>[640, 1280]) {
    test('varied $budget-token probe covers distinct full source segments', () {
      final text = runner.gectorVariedSentences(budget, fixtures.bundle);
      final evidence = runner.gectorInputEvidence(
        text,
        fixtures.bundle,
        GectorDecodeOptions(segmentation: GectorSegmentationOptions()),
      );
      expect(
        evidence['tokens_first_pass'],
        allOf(greaterThan(512), lessThanOrEqualTo(budget)),
      );
      expect(evidence['source_coverage_complete'], isTrue);
      expect(evidence['source_code_units'], text.length);
      expect(evidence['initial_segment_count'], greaterThan(1));
      expect(
        evidence['initial_distinct_model_inputs'],
        evidence['initial_segment_count'],
      );
      final segments = GectorSegmenter(
        configuration: fixtures.bundle.configuration,
        tokenizer: fixtures.bundle.tokenizer,
        options: GectorSegmentationOptions(),
      ).plan(text);
      expect(segments.map((segment) => segment.text).join(), text);
      expect(
        segments.every((segment) => segment.initialTokenCount <= 64),
        isTrue,
      );
      expect(segments.last.end, text.length);
      final sentences = text
          .split('. ')
          .map((s) => s.replaceFirst(RegExp(r'\.$'), ''));
      expect(sentences.toSet().length, sentences.length);
    });
  }

  test('repeated probe evidence identifies genuine duplicate model inputs', () {
    const text = 'Das Haus ist schön. Das Haus ist schön. Das Haus ist schön.';
    final evidence = runner.gectorInputEvidence(
      text,
      fixtures.bundle,
      GectorDecodeOptions(
        segmentation: GectorSegmentationOptions(targetTokens: 6),
      ),
    );
    expect(evidence['initial_segment_count'], 3);
    expect(evidence['initial_distinct_model_inputs'], 1);
    expect(evidence['source_coverage_complete'], isTrue);
  });
}
