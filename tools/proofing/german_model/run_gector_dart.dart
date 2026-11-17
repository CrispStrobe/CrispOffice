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
  // A compiled executable can live outside the checkout. Its script URI is
  // the binary path, so callers must be able to identify the source explicitly.
  final sourceRoot = options['source-root'];
  final root = sourceRoot == null
      ? Directory.fromUri(Platform.script.resolve('../../../'))
      : Directory(sourceRoot).absolute;
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
  );
  final service = OfficeProofingService(providers: [provider]);
  setup.stop();
  final results = <Map<String, Object?>>[];
  final probes = <Map<String, Object?>>[];
  final controls = <Map<String, Object?>>[];
  final shortSamples = <double>[];
  partial.addAll({
    'stage': 'complete-checks',
    'cases': results,
    'long_complete_check_probes': probes,
    'controls': controls,
  });
  var revision = 0;
  Future<Map<String, Object?>> check(
    String id,
    String text, {
    String language = 'de-DE',
    Set<String> ignored = const {},
  }) async {
    final request = OfficeProofingRequest(
      documentId: 'native-dart-qualification',
      blockId: id,
      revision: revision++,
      text: text,
      language: language,
      startOffset: 7,
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
    final words = GectorSourceText(text, bundle.configuration);
    final tokens = bundle.tokenizer.encode(words.words(words.plain)).tokenCount;
    final samples = runs.map((r) => r['elapsed_ms']! as double).toList();
    return {
      ...runs.first,
      'tokens_first_pass': tokens,
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
  final report = <String, Object?>{
    'schema_version': 1,
    'kind': 'quds-gector-native-dart-complete-check',
    'timestamp_utc': DateTime.now().toUtc().toIso8601String(),
    'completed': true,
    'operational_passed': operationalPass,
    'interpretation':
        'Guarded provider and service, including persistent-isolate '
        'IPC, tokenization, all model passes, dictionary checks and source-bound '
        'result validation. Guarded outputs may differ from the unguarded oracle. '
        'This small panel is not target-device or representative quality qualification.',
    'runtime': {
      'dart': Platform.version,
      'product_mode': const bool.fromEnvironment('dart.vm.product'),
      'executable': Platform.resolvedExecutable,
      'executable_sha256':
          (await sha256
                  .bind(File(Platform.resolvedExecutable).openRead())
                  .first)
              .toString(),
      'script': Platform.script.toString(),
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
  };
  await output.parent.create(recursive: true);
  await output.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(report)}\n',
  );
  stdout.writeln(
    jsonEncode({
      'operational_passed': operationalPass,
      'cases': results.length,
      'controls': controls.length,
      'setup_ms': report['setup_ms'],
      'peak_process_rss_bytes': report['peak_process_rss_bytes'],
      'short_check_timing': shortTiming,
      'engineering_budgets': report['engineering_budgets'],
    }),
  );
  if (!operationalPass) exitCode = 1;
}

Map<String, Object?> _map(Object? value) => value! as Map<String, Object?>;

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
  const optional = {'source-root'};
  final result = <String, String>{};
  for (var index = 0; index < arguments.length; index += 2) {
    if (index + 1 >= arguments.length || !arguments[index].startsWith('--')) {
      throw ArgumentError(
        'Expected --name value pairs: ${required.join(', ')}',
      );
    }
    final key = arguments[index].substring(2);
    if ((!required.contains(key) && !optional.contains(key)) ||
        result.containsKey(key)) {
      throw ArgumentError('Unknown or duplicated option: $key');
    }
    result[key] = arguments[index + 1];
  }
  if (!required.every(result.containsKey)) {
    throw ArgumentError('Required options: ${required.join(', ')}');
  }
  return result;
}
