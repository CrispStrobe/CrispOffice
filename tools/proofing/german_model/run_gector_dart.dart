// Workspace-level qualification uses the resolved workspace package config.
// It is not a separately published package.
// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_proofing_gector/quds_proofing_gector.dart';
import 'package:quds_proofing_gector/quds_proofing_gector_native.dart';

/// Measures the actual persistent worker, native backend, German guards,
/// read-only Quds dictionary and OfficeProofingService validation together.
/// Assets are explicit local inputs; this tool downloads or installs nothing.
Future<void> main(List<String> arguments) async {
  final options = _arguments(arguments);
  final output = File(options['output']!);
  if (output.existsSync()) {
    throw StateError('Refusing to overwrite an existing qualification report.');
  }
  final partial = <String, Object?>{
    'schema_version': 1,
    'kind': 'quds-gector-native-dart-complete-check',
    'timestamp_utc': DateTime.now().toUtc().toIso8601String(),
    'completed': false,
    'operational_passed': false,
  };
  try {
    await _run(options, output, partial);
  } on Object catch (error) {
    partial['error'] = error.toString();
    partial['peak_process_rss_bytes'] = ProcessInfo.maxRss;
    await output.parent.create(recursive: true);
    await output.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(partial)}\n',
    );
    stderr.writeln('Qualification failed; partial receipt preserved: $error');
    exitCode = 1;
  }
}

Future<void> _run(
  Map<String, String> options,
  File output,
  Map<String, Object?> partial,
) async {
  final root = options['source-root'] == null
      ? Directory.fromUri(Platform.script.resolve('../../../'))
      : Directory(options['source-root']!).absolute;
  final segmentationTarget = options['segment-target-tokens'];
  final decodeOptions = GectorDecodeOptions(
    segmentation: segmentationTarget == null
        ? null
        : GectorSegmentationOptions(
            targetTokens: int.parse(segmentationTarget),
          ),
  );
  final segmentation = decodeOptions.segmentation;
  final decodeConfiguration = <String, Object?>{
    'mode': segmentation == null ? 'single-sequence' : 'sentence-segments',
    'maximum_passes': decodeOptions.maximumPasses,
    'maximum_tokens_per_sequence': decodeOptions.maximumTokens,
    'maximum_text_code_units': decodeOptions.maximumTextCodeUnits,
    'keep_confidence': decodeOptions.keepConfidence,
    'minimum_error_probability': decodeOptions.minimumErrorProbability,
    'segmentation': segmentation == null
        ? null
        : {
            'target_tokens': segmentation.targetTokens,
            'maximum_segments': segmentation.maximumSegments,
            'maximum_total_initial_tokens': segmentation.maximumTotalTokens,
            'maximum_total_forward_tokens':
                segmentation.maximumTotalTokens * decodeOptions.maximumPasses,
          },
    'token_accounting': {
      'tokens_first_pass':
          'Logical original-source encoding with one CLS/SEP pair, retained '
          'for the frozen comparison. Counts above the native limit are summed '
          'from individual word encodings without encoding an oversized sequence.',
      'initial_model_tokens_total':
          'Sum of the actual planned initial sequence lengths. Each segment '
          'has its own CLS/SEP and source-terminal normalization.',
      'initial_segments':
          'Complete original-source UTF-16 partition planned outside the '
          'measurement. Full worker planning remains inside each timed check.',
    },
  };
  partial['decode_configuration'] = decodeConfiguration;
  partial['stage'] = 'source-and-reference-admission';
  final sourcesBefore = await _sources(root);
  partial['source_files'] = sourcesBefore;
  final model = File(options['model']!);
  final reference = File(options['reference']!);
  final referenceBytes = await reference.readAsBytes();
  final referenceData = _map(jsonDecode(utf8.decode(referenceBytes)));
  final frozenBytes = await File.fromUri(
    root.uri.resolve('tools/proofing/german_model/cases.json'),
  ).readAsBytes();
  const frozenCasesSha =
      'ec3309ebf99a3b1be9bb065fc91cd2afce2e362ebaa81f2d64d39a231c6defb9';
  final inference = _map(referenceData['inference_model']);
  if (referenceData['kind'] != 'quds-gector-reference' ||
      referenceData['model'] != 'proofbird/gector-bert-de' ||
      referenceData['revision'] != gectorModelRevision ||
      referenceData['cases_sha256'] != frozenCasesSha ||
      sha256.convert(frozenBytes).toString() != frozenCasesSha ||
      inference['variant'] != 'float32' ||
      inference['sha256'] != gectorSourceModelSha256 ||
      inference['source_model_sha256'] != gectorSourceModelSha256) {
    throw const FormatException('Reference identity or frozen panel mismatch.');
  }
  final cases = (referenceData['cases']! as List<Object?>).map(_map).toList();
  final frozen = (jsonDecode(utf8.decode(frozenBytes)) as List<Object?>)
      .map(_map)
      .toList();
  if (cases.length != 30 ||
      frozen.length != 30 ||
      cases.map((c) => c['id']).toSet().length != 30) {
    throw const FormatException(
      'The frozen panel must contain 30 unique cases.',
    );
  }
  for (var i = 0; i < cases.length; i++) {
    for (final key in ['id', 'kind', 'input', 'expected']) {
      if (cases[i][key] != frozen[i][key]) {
        throw FormatException('Frozen case ${frozen[i]['id']} differs: $key');
      }
    }
    if (cases[i].containsKey('locale') &&
        cases[i]['locale'] != frozen[i]['locale']) {
      throw const FormatException('Reference changed a frozen locale.');
    }
    cases[i]['locale'] = frozen[i]['locale'] ?? 'de-DE';
  }
  partial['reference_sha256'] = sha256.convert(referenceBytes).toString();
  partial['cases_sha256'] = frozenCasesSha;
  final artifact = GectorModelArtifact(
    file: model.uri.pathSegments.last,
    sha256: options['model-sha256']!,
    bytes: model.lengthSync(),
  );
  partial['stage'] = 'verified-model-and-worker-startup';
  partial['model_sha256'] = artifact.sha256;
  partial['native_library_sha256'] = options['library-sha256'];
  final setup = Stopwatch()..start();
  final bundle = await GectorVerifiedBundle.load(
    read: (name) => name == artifact.file
        ? model.openRead()
        : File('${options['bundle-dir']}/$name').openRead(),
    artifact: artifact,
  );
  final vocabulary = OfficeProofingVocabulary();
  final provider = await GectorProofingProvider.load(
    bundle: bundle,
    backendFactory: GectorNativeBackendFactory(
      modelDirectory: model.parent.path,
      libraryPath: options['library']!,
      librarySha256: options['library-sha256']!,
      threads: 2,
    ),
    lexiconFactory: const GectorGermanLexiconFactory(),
    vocabulary: vocabulary,
    options: decodeOptions,
  );
  final service = OfficeProofingService(providers: [provider]);
  setup.stop();
  final results = <Map<String, Object?>>[];
  final probes = <Map<String, Object?>>[];
  final controls = <Map<String, Object?>>[];
  final segmentedProbes = <Map<String, Object?>>[];
  final segmentationControls = <Map<String, Object?>>[];
  final shortSamples = <double>[];
  partial.addAll({
    'stage': 'complete-checks',
    'cases': results,
    'long_complete_check_probes': probes,
    'controls': controls,
    if (segmentation != null) ...{
      'segmented_long_complete_check_probes': segmentedProbes,
      'segmentation_controls': segmentationControls,
    },
  });
  var revision = 0;
  Future<Map<String, Object?>> check(
    String id,
    String text, {
    String language = 'de-DE',
    Set<String> ignored = const {},
    int startOffset = 7,
  }) async {
    final request = OfficeProofingRequest(
      documentId: 'native-dart-qualification',
      blockId: id,
      revision: revision++,
      text: text,
      language: language,
      startOffset: startOffset,
      ignoredRuleIds: ignored,
    );
    final timer = Stopwatch()..start();
    final report = await service.check(request);
    timer.stop();
    if (report.results.length != 1) {
      throw StateError('Expected one source-bound provider result.');
    }
    final result = report.results.single;
    var corrected = text;
    final findings = result.findings.toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    for (final finding in findings.reversed) {
      corrected = corrected.replaceRange(
        finding.start - request.startOffset,
        finding.end - request.startOffset,
        finding.replacements.single,
      );
    }
    return {
      'id': id,
      'input': text,
      'language': language,
      'start_offset': request.startOffset,
      'status': result.status.name,
      'message': result.message,
      'corrected': corrected,
      'elapsed_ms': timer.elapsedMicroseconds / 1000,
      'findings': [
        for (final finding in findings)
          {
            'start': finding.start,
            'end': finding.end,
            'original': finding.originalText,
            'replacement': finding.replacements.single,
            'rule_id': finding.ruleId,
          },
      ],
    };
  }

  Future<Map<String, Object?>> measured(
    String id,
    String text, {
    String language = 'de-DE',
  }) async {
    final warmup = await check('$id-warmup', text, language: language);
    final runs = <Map<String, Object?>>[];
    for (var repeat = 0; repeat < 3; repeat++) {
      runs.add(await check(id, text, language: language));
    }
    final stable = <Map<String, Object?>>[warmup, ...runs].every(
      (run) =>
          run['corrected'] == runs.first['corrected'] &&
          run['status'] == runs.first['status'] &&
          jsonEncode(run['findings']) == jsonEncode(runs.first['findings']),
    );
    final inputEvidence = _inputEvidence(text, bundle, decodeOptions);
    final samples = runs.map((r) => r['elapsed_ms']! as double).toList();
    return {
      ...runs.first,
      ...inputEvidence,
      'expected_status': language == 'de-DE' ? 'success' : 'unsupported',
      'warmup': warmup,
      'stable_repeats': stable,
      'timing': _timing(samples),
    };
  }

  try {
    for (final entry in cases) {
      final text = entry['input']! as String;
      final result = await measured(
        entry['id']! as String,
        text,
        language: entry['locale']! as String,
      );
      final expectedText = entry['expected'] ?? text;
      result.addAll({
        'kind': entry['kind'],
        'expected': expectedText,
        'source_locale': entry['locale'],
        'evaluation_locale': entry['locale'],
        'reference_unguarded': entry['corrected'],
        'matches_expected': result['corrected'] == expectedText,
        'matches_unguarded_reference':
            result['corrected'] == entry['corrected'],
      });
      if (result['status'] == 'success' &&
          (result['tokens_first_pass']! as int) <= 64) {
        shortSamples.addAll(
          (_map(result['timing'])['samples_ms']! as List<double>),
        );
      }
      results.add(result);
    }
    // Repeated grammatical sentences probe complete-check scaling. They are
    // structural controls, not a representative long-document quality corpus.
    for (final target in [64, 128, 256]) {
      var text = 'Das Haus ist schön.';
      while (true) {
        final next = '$text Das Haus ist schön.';
        final source = GectorSourceText(next, bundle.configuration);
        if (bundle.tokenizer.encode(source.words(source.plain)).tokenCount >
            target) {
          break;
        }
        text = next;
      }
      final probe = await measured('repeated-sentences-up-to-$target', text);
      probe['token_budget'] = target;
      probes.add(probe);
      if (target == 64) {
        shortSamples.addAll(
          (_map(probe['timing'])['samples_ms']! as List<double>),
        );
      }
    }
    Future<void> control(
      String id,
      String text, {
      String language = 'de-DE',
      Set<String> ignored = const {},
      required String expectedStatus,
      String? expectedText,
    }) async {
      final result = await check(
        id,
        text,
        language: language,
        ignored: ignored,
      );
      result['passed'] =
          result['status'] == expectedStatus &&
          (expectedText == null || result['corrected'] == expectedText);
      controls.add(result);
    }

    const sentence = 'Du geht heute nach Hause.';
    for (final language in ['de-AT', 'de-CH']) {
      await control(
        'unsupported-$language',
        sentence,
        language: language,
        expectedStatus: 'unsupported',
        expectedText: sentence,
      );
    }
    await control(
      'ignored-rule',
      sentence,
      ignored: {'gector.de.grammar'},
      expectedStatus: 'success',
      expectedText: sentence,
    );
    vocabulary.addWord('geht');
    await control(
      'personal-vocabulary',
      sentence,
      expectedStatus: 'success',
      expectedText: sentence,
    );
    vocabulary.removeWord('geht');
    await control(
      'personal-vocabulary-removed',
      sentence,
      expectedStatus: 'success',
      expectedText: 'Du gehst heute nach Hause.',
    );
    await control(
      'protected-code',
      '`$sentence`',
      expectedStatus: 'success',
      expectedText: '`$sentence`',
    );
    await control(
      'emoji-source-offset',
      '😀 $sentence',
      expectedStatus: 'success',
      expectedText: '😀 Du gehst heute nach Hause.',
    );
    await control(
      'capacity-fails-explicitly',
      List.filled(600, 'Haus').join(' '),
      expectedStatus: 'failed',
    );
    if (segmentation != null) {
      // These are separately retained additions. The frozen 30 cases, eight
      // controls and three original length probes keep their original inputs
      // and result keys so the strict historical comparator remains usable.
      for (final target in [640, 1280]) {
        final text = _repeatedSentences(target, bundle);
        final probe = await measured(
          'segmented-repeated-sentences-up-to-$target',
          text,
        );
        probe.addAll({
          'logical_token_budget': target,
          'expected': text,
          'matches_expected': probe['corrected'] == text,
          'exceeds_single_sequence_capacity':
              (probe['tokens_first_pass']! as int) >
              decodeOptions.maximumTokens,
        });
        segmentedProbes.add(probe);
      }

      Future<void> segmentedControl(
        String id,
        String text, {
        required String expectedStatus,
        required String expectedText,
        int startOffset = 137,
        List<Map<String, Object?>>? expectedFindings,
      }) async {
        final result = await check(id, text, startOffset: startOffset);
        Map<String, Object?>? inputEvidence;
        try {
          inputEvidence = _inputEvidence(text, bundle, decodeOptions);
          result.addAll(inputEvidence);
          result['planning_admitted'] = true;
        } on GectorCapacityException catch (error) {
          result['planning_admitted'] = false;
          result['planning_rejection'] = error.toString();
        }
        result.addAll({
          'expected_status': expectedStatus,
          'expected': expectedText,
          'expected_findings': ?expectedFindings,
          'passed':
              result['status'] == expectedStatus &&
              result['corrected'] == expectedText &&
              (expectedFindings == null ||
                  jsonEncode(result['findings']) ==
                      jsonEncode(expectedFindings)) &&
              (expectedStatus != 'success' ||
                  inputEvidence?['source_coverage_complete'] == true) &&
              (expectedStatus == 'success' ||
                  ((result['findings']! as List<Object?>).isEmpty &&
                      result['planning_admitted'] == false &&
                      (result['message'] as String? ?? '').contains(
                        result['planning_rejection']! as String,
                      ))),
        });
        segmentationControls.add(result);
      }

      // A known frozen correction occurs after more than one native sequence
      // worth of clean source. The initial emoji and nondefault request offset
      // distinguish original UTF-16 coordinates from segment-relative offsets.
      final prefix = '😀 ${List.filled(120, 'Das Haus ist schön.').join(' ')} ';
      final late = '$prefix$sentence';
      final expectedStart = 137 + late.lastIndexOf('geht');
      await segmentedControl(
        'segmented-late-correction-utf16-offset',
        late,
        expectedStatus: 'success',
        expectedText: '${prefix}Du gehst heute nach Hause.',
        expectedFindings: [
          {
            'start': expectedStart,
            'end': expectedStart + 'geht'.length,
            'original': 'geht',
            'replacement': 'gehst',
            'rule_id': 'gector.de.grammar',
          },
        ],
      );
      final protectedText = '$prefix`$sentence` Das Haus ist schön.';
      await segmentedControl(
        'segmented-protected-code',
        protectedText,
        expectedStatus: 'success',
        expectedText: protectedText,
        expectedFindings: const [],
      );
      final lateOversize = '$sentence ${List.filled(600, 'Haus').join(' ')}';
      await segmentedControl(
        'segmented-late-capacity-fails-whole-request',
        lateOversize,
        expectedStatus: 'failed',
        expectedText: lateOversize,
        expectedFindings: const [],
      );
      // Independently exceed total initial tokens using intact sentences that
      // each fit the native hard limit, rather than one oversized sentence.
      final longSentence = '${List.filled(256, 'Haus').join(' ')}.';
      final longSentenceTokens = _logicalTokens(longSentence, bundle);
      final overTotal = List.filled(
        segmentation.maximumTotalTokens ~/ longSentenceTokens + 1,
        longSentence,
      ).join(' ');
      await segmentedControl(
        'segmented-total-token-cap-fails-whole-request',
        overTotal,
        expectedStatus: 'failed',
        expectedText: overTotal,
        expectedFindings: const [],
      );
      // At target=64 this reaches the segment-count bound before the total
      // token or source-length bound. Other explicit targets may encounter an
      // earlier request-wide bound; the actual admission rejection is retained.
      final nearTarget = _repeatedSentences(
        math.max(segmentation.targetTokens, 6),
        bundle,
      );
      final overSegments = List.filled(
        segmentation.maximumSegments + 1,
        nearTarget,
      ).join(' ');
      await segmentedControl(
        'segmented-segment-cap-fails-whole-request',
        overSegments,
        expectedStatus: 'failed',
        expectedText: overSegments,
        expectedFindings: const [],
      );
      final overText = List.filled(
        decodeOptions.maximumTextCodeUnits + 1,
        'x',
      ).join();
      await segmentedControl(
        'segmented-text-cap-fails-whole-request',
        overText,
        expectedStatus: 'failed',
        expectedText: overText,
        expectedFindings: const [],
      );
    }
  } finally {
    await service.dispose();
  }
  final sourcesAfter = await _sources(root);
  final sourceStable = jsonEncode(sourcesBefore) == jsonEncode(sourcesAfter);
  final shortTiming = _timing(shortSamples);
  final operationalPass =
      sourceStable &&
      results.length == 30 &&
      probes.length == 3 &&
      controls.length == 8 &&
      results.every(
        (r) =>
            r['status'] == r['expected_status'] && r['stable_repeats'] == true,
      ) &&
      probes.every(
        (r) => r['status'] == 'success' && r['stable_repeats'] == true,
      ) &&
      controls.every((r) => r['passed'] == true);
  final segmentationPass = segmentation == null
      ? null
      : segmentedProbes.length == 2 &&
            segmentationControls.length == 6 &&
            segmentedProbes.every(
              (r) =>
                  r['status'] == 'success' &&
                  r['stable_repeats'] == true &&
                  r['matches_expected'] == true &&
                  r['exceeds_single_sequence_capacity'] == true &&
                  (r['initial_segment_count']! as int) > 1 &&
                  r['source_coverage_complete'] == true,
            ) &&
            segmentationControls.every((r) => r['passed'] == true);
  final allRequestedChecksPass = operationalPass && segmentationPass != false;
  final report = <String, Object?>{
    'schema_version': 1,
    'kind': 'quds-gector-native-dart-complete-check',
    'timestamp_utc': DateTime.now().toUtc().toIso8601String(),
    'completed': true,
    'operational_passed': operationalPass,
    'decode_configuration': decodeConfiguration,
    'segmentation_operational_passed': segmentationPass,
    'all_requested_checks_passed': allRequestedChecksPass,
    'operational_passed_scope':
        'The original frozen corpus, eight controls and three structural probes. '
        'Opt-in segmentation additions are evaluated separately and also gate '
        'all_requested_checks_passed and the process exit status.',
    'interpretation':
        'Guarded provider and service, including persistent-isolate '
        'IPC, tokenization, all model passes, dictionary checks and source-bound '
        'result validation. Guarded outputs may differ from the unguarded oracle. '
        'This small panel is not target-device or representative quality qualification.',
    'runtime': {
      'dart': Platform.version,
      'product_mode': const bool.fromEnvironment('dart.vm.product'),
      'executable': await _filePin(File(Platform.resolvedExecutable)),
      'entrypoint': await _filePin(File.fromUri(Platform.script)),
      'os': Platform.operatingSystem,
      'os_version': Platform.operatingSystemVersion,
      'processors': Platform.numberOfProcessors,
      'native_threads': 2,
      'warmups_per_input': 1,
      'repeats_per_input': 3,
    },
    'model': {
      'file': artifact.file,
      'sha256': artifact.sha256,
      'bytes': artifact.bytes,
      'source_model_sha256': artifact.sourceModelSha256,
      'revision': artifact.revision,
    },
    'native_library_sha256': options['library-sha256'],
    'reference_sha256': sha256.convert(referenceBytes).toString(),
    'cases_sha256': frozenCasesSha,
    'bundle_assets': bundle.assetDigests,
    'source_files': sourcesBefore,
    'source_stable': sourceStable,
    'setup_ms': setup.elapsedMicroseconds / 1000,
    'peak_process_rss_bytes': ProcessInfo.maxRss,
    'warm_checks_up_to_64_wordpieces': shortTiming,
    'engineering_budgets': {
      'p95_at_most_500_ms': (shortTiming['p95_ms']! as double) <= 500,
      'peak_rss_at_most_768_mib': ProcessInfo.maxRss <= 768 * 1024 * 1024,
      'gguf_at_most_160_mib': artifact.bytes <= 160 * 1024 * 1024,
      'note':
          'GGUF size excludes sidecars; target hardware remains unqualified.',
    },
    'cases': results,
    'long_complete_check_probes': probes,
    'controls': controls,
    if (segmentation != null) ...{
      'segmented_long_complete_check_probes': segmentedProbes,
      'segmentation_controls': segmentationControls,
    },
  };
  await output.parent.create(recursive: true);
  await output.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );
  stdout.writeln(
    jsonEncode({
      'operational_passed': operationalPass,
      'segmentation_operational_passed': segmentationPass,
      'all_requested_checks_passed': allRequestedChecksPass,
      'cases': results.length,
      'controls': controls.length,
      'setup_ms': report['setup_ms'],
      'peak_process_rss_bytes': report['peak_process_rss_bytes'],
      'short_check_timing': shortTiming,
      'engineering_budgets': report['engineering_budgets'],
    }),
  );
  if (!allRequestedChecksPass) exitCode = 1;
}

/// The old single-source token count is additive per source word. Counting
/// oversized inputs this way does not ask the model tokenizer to admit a
/// sequence beyond its hard limit, or mistake per-segment terminal stripping
/// for the original-source normalization used by the frozen comparator.
int _logicalTokens(String text, GectorVerifiedBundle bundle) {
  final source = GectorSourceText(text, bundle.configuration);
  final words = source.words(source.plain);
  try {
    return bundle.tokenizer.encode(words).tokenCount;
  } on GectorCapacityException {
    return 2 +
        words.fold<int>(
          0,
          (total, word) =>
              total + bundle.tokenizer.encode([word]).tokenCount - 2,
        );
  }
}

Map<String, Object?> _inputEvidence(
  String text,
  GectorVerifiedBundle bundle,
  GectorDecodeOptions options,
) {
  final logicalTokens = _logicalTokens(text, bundle);
  final segmentation = options.segmentation;
  if (segmentation == null) {
    return {
      'tokens_first_pass': logicalTokens,
      'initial_model_tokens_total': logicalTokens,
      'initial_segment_count': 1,
      'initial_segments': [
        {'start': 0, 'end': text.length, 'tokens': logicalTokens},
      ],
      'source_code_units': text.length,
      'source_coverage_complete': true,
    };
  }
  final segments = GectorSegmenter(
    configuration: bundle.configuration,
    tokenizer: bundle.tokenizer,
    options: segmentation,
    maximumTokens: options.maximumTokens,
    maximumTextCodeUnits: options.maximumTextCodeUnits,
  ).plan(text);
  var cursor = 0;
  var complete = true;
  var actualTokens = 0;
  for (final segment in segments) {
    complete =
        complete &&
        segment.start == cursor &&
        text.substring(segment.start, segment.end) == segment.text;
    cursor = segment.end;
    actualTokens += segment.initialTokenCount;
  }
  complete = complete && cursor == text.length;
  if (!complete) throw StateError('Planned segments do not cover the source.');
  return {
    'tokens_first_pass': logicalTokens,
    'initial_model_tokens_total': actualTokens,
    'initial_segment_count': segments.length,
    'initial_segments': [
      for (final segment in segments)
        {
          'start': segment.start,
          'end': segment.end,
          'tokens': segment.initialTokenCount,
        },
    ],
    'source_code_units': text.length,
    'source_coverage_complete': complete,
  };
}

String _repeatedSentences(int logicalBudget, GectorVerifiedBundle bundle) {
  const sentence = 'Das Haus ist schön.';
  final first = _logicalTokens(sentence, bundle);
  final step = _logicalTokens('$sentence $sentence', bundle) - first;
  if (logicalBudget < first || step <= 0) {
    throw ArgumentError('The structural probe budget must fit one sentence.');
  }
  final repeats = 1 + (logicalBudget - first) ~/ step;
  final text = List.filled(repeats, sentence).join(' ');
  if (_logicalTokens(text, bundle) > logicalBudget ||
      _logicalTokens('$text $sentence', bundle) <= logicalBudget) {
    throw StateError('Structural probe token accounting is inconsistent.');
  }
  return text;
}

Map<String, Object?> _map(Object? value) => value! as Map<String, Object?>;

Future<Map<String, Object?>> _filePin(File file) async => {
  'file': file.uri.pathSegments.last,
  'bytes': file.lengthSync(),
  'sha256': (await sha256.bind(file.openRead()).first).toString(),
};

Map<String, Object?> _timing(List<double> samples) {
  final sorted = samples.toList()..sort();
  if (sorted.isEmpty) throw StateError('Timing samples are required.');
  return {
    'samples_ms': samples,
    'median_ms': sorted.length.isOdd
        ? sorted[sorted.length ~/ 2]
        : (sorted[sorted.length ~/ 2 - 1] + sorted[sorted.length ~/ 2]) / 2,
    'p95_ms': sorted[math.max(0, (sorted.length * 0.95).ceil() - 1)],
    'maximum_ms': sorted.last,
  };
}

Future<Map<String, String>> _sources(Directory root) async {
  final paths = <String>[
    'pubspec.yaml',
    'pubspec.lock',
    'packages/quds_proofing_gector/pubspec.yaml',
    'packages/quds_office_engine/lib/src/proofing/german_spelling.dart',
    'packages/quds_office_engine/lib/src/proofing/office_proofing.dart',
    'packages/quds_office_engine/lib/src/proofing/proofing_text_ranges.dart',
    'tools/proofing/german_model/run_gector_dart.dart',
    'tools/proofing/german_model/cases.json',
    'tools/proofing/german_model/artifacts.json',
  ];
  for (final directory in [
    'packages/quds_proofing_gector/lib/',
    'packages/quds_office_engine/lib/src/proofing/data/',
    'packages/quds_office_engine/lib/src/opc/zip/',
  ]) {
    for (final entry in Directory.fromUri(
      root.uri.resolve(directory),
    ).listSync(recursive: true)) {
      if (entry is File && entry.path.endsWith('.dart')) {
        paths.add(entry.uri.path.substring(root.uri.path.length));
      }
    }
  }
  paths.sort();
  return {
    for (final path in paths)
      path:
          (await sha256
                  .bind(File.fromUri(root.uri.resolve(path)).openRead())
                  .first)
              .toString(),
  };
}

Map<String, String> _arguments(List<String> arguments) {
  const required = {
    'bundle-dir',
    'model',
    'model-sha256',
    'library',
    'library-sha256',
    'reference',
    'output',
  };
  final result = <String, String>{};
  for (var index = 0; index < arguments.length; index += 2) {
    if (index + 1 >= arguments.length || !arguments[index].startsWith('--')) {
      throw ArgumentError(
        'Expected --name value pairs: ${required.join(', ')}',
      );
    }
    final key = arguments[index].substring(2);
    if ((!required.contains(key) &&
            !const {'source-root', 'segment-target-tokens'}.contains(key)) ||
        result.containsKey(key)) {
      throw ArgumentError('Unknown or duplicated option: $key');
    }
    result[key] = arguments[index + 1];
  }
  if (!required.every(result.containsKey)) {
    throw ArgumentError('Required options: ${required.join(', ')}');
  }
  if (result['segment-target-tokens'] case final target?) {
    final parsed = int.tryParse(target);
    if (parsed == null || parsed < 2 || parsed > 512) {
      throw ArgumentError('--segment-target-tokens must be between 2 and 512.');
    }
  }
  return result;
}
