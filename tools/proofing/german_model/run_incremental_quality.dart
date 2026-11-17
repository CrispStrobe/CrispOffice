// Live workspace qualification, not a separately published package.
// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_proofing_gector/quds_proofing_gector.dart';
import 'package:quds_proofing_gector/quds_proofing_gector_native.dart';

import 'incremental_quality.dart';

/// Runs the real native provider once per case and the application merge policy.
/// Explicit verified local assets only; no downloads, reference replay or CI.
Future<void> main(List<String> arguments) async {
  final options = _arguments(arguments);
  final output = File(options['output']!).absolute;
  await output.parent.create(recursive: true);
  // Reserve the destination before setup; an existing file or symlink fails.
  await output.create(exclusive: true);
  final report = <String, Object?>{
    'schema_version': 1,
    'kind': 'quds-german-incremental-quality',
    'started_at_utc': DateTime.now().toUtc().toIso8601String(),
    'completed': false,
    'operational_passed': false,
    'source_stable': false,
    'stage': 'admission',
    'projection_policy': qualityProjectionPolicy,
    'interpretation':
        'Declared synthetic-case quality measurement with real local native '
        'inference and the editor merge policy. One check per input; this is '
        'not a latency benchmark, representative German accuracy, target-device '
        'qualification or a distribution decision. Writing-only is the writing '
        'result from the same deterministic service request, not a second run.',
  };
  final total = Stopwatch()..start();
  try {
    await _save(output, report);
    await _run(options, output, report);
  } on Object catch (error) {
    report['error'] = error.toString();
    report['completed'] = false;
    report['operational_passed'] = false;
    exitCode = 1;
    stderr.writeln('Quality run failed; partial receipt retained: $error');
  } finally {
    total.stop();
    report['finished_at_utc'] = DateTime.now().toUtc().toIso8601String();
    report['elapsed_ms'] = total.elapsedMicroseconds / 1000;
    report['peak_process_rss_bytes'] = ProcessInfo.maxRss;
    await _save(output, report);
  }
  stdout.writeln(
    jsonEncode({
      'completed': report['completed'],
      'operational_passed': report['operational_passed'],
      'source_stable': report['source_stable'],
      if (report.containsKey('summary')) 'summary': report['summary'],
    }),
  );
}

Future<void> _run(
  Map<String, String> options,
  File output,
  Map<String, Object?> report,
) async {
  final root = options.containsKey('source-root')
      ? Directory(options['source-root']!).absolute
      : Directory.fromUri(Platform.script.resolve('../../../'));
  final corpus = File(options['cases']!).absolute;
  final before = await _sources(root, corpus);
  report['source_files'] = before;
  final bytes = await corpus.readAsBytes();
  final corpusHash = sha256.convert(bytes).toString();
  if (before['declared-corpus'] != corpusHash) {
    throw StateError('Corpus changed during admission.');
  }
  final cases = parseQualityCases(jsonDecode(utf8.decode(bytes)));
  report.addAll({
    'cases_sha256': corpusHash,
    'corpus_file': corpus.uri.pathSegments.last,
    'declared_cases': cases.map((sample) => sample.toJson()).toList(),
    'runtime': {
      'dart': Platform.version,
      'product_mode': const bool.fromEnvironment('dart.vm.product'),
      'executable': await _pin(File(Platform.resolvedExecutable)),
      'entrypoint': await _pin(File.fromUri(Platform.script)),
      'os': Platform.operatingSystem,
      'os_version': Platform.operatingSystemVersion,
      'processors': Platform.numberOfProcessors,
      'native_threads': 2,
      'warmups_per_case': 0,
      'checks_per_case': 1,
    },
    'stage': 'verified-startup',
  });
  await _save(output, report);
  final model = File(options['model']!).absolute;
  final artifact = GectorModelArtifact(
    file: model.uri.pathSegments.last,
    bytes: await model.length(),
    sha256: options['model-sha256']!,
  );
  final observations = <QualityObservation>[];
  final rows = <Map<String, Object?>>[];
  report['cases'] = rows;
  OfficeProofingService? deterministicService;
  OfficeProofingService? modelService;
  final startup = Stopwatch()..start();
  try {
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
    modelService = OfficeProofingService(providers: [provider]);
    final spelling = GermanSpellingProvider(vocabulary: vocabulary);
    deterministicService = OfficeProofingService(
      providers: [spelling, GermanWritingRulesProvider()],
    );
    await spelling.warmUp();
    startup.stop();
    report.addAll({
      'startup_ms': startup.elapsedMicroseconds / 1000,
      'startup_scope':
          'Verified bundle, persistent native worker and both spelling lexicons; '
          'writing-rule morphology may initialize during the first request.',
      'model': {
        'file': artifact.file,
        'sha256': artifact.sha256,
        'bytes': artifact.bytes,
        'revision': artifact.revision,
        'source_model_sha256': artifact.sourceModelSha256,
      },
      'native_library_sha256': options['library-sha256'],
      'bundle_assets': bundle.assetDigests,
      'live_native_provider': true,
      'vocabulary': 'empty personal vocabulary, unchanged throughout the run',
      'service_timeout_ms': deterministicService.timeout.inMilliseconds,
      'model_provider_timeout_ms': provider.timeout.inMilliseconds,
    });
    await _save(output, report);
    for (var index = 0; index < cases.length; index++) {
      final sample = cases[index];
      report['stage'] = 'case:${sample.id}';
      final request = OfficeProofingRequest(
        documentId: 'incremental-quality-$corpusHash',
        blockId: sample.id,
        revision: index,
        text: sample.input,
        language: sample.locale,
        startOffset: 37,
      );
      final timer = Stopwatch()..start();
      final deterministic = await deterministicService.check(request);
      final deterministicMs = timer.elapsedMicroseconds / 1000;
      timer.reset();
      final modelReport = await modelService.check(request);
      timer.stop();
      final writing = OfficeProofingReport(
        request: request,
        results: [
          deterministic.results.singleWhere(
            (result) => result.providerId == 'german-writing',
          ),
        ],
      );
      final combined = mergeOfficeProofingReports(
        primary: deterministic,
        secondary: modelReport,
      );
      final observation = QualityObservation(sample, {
        'writing_only': projectQualityReport(writing),
        'deterministic': projectQualityReport(deterministic),
        'model_only': projectQualityReport(modelReport),
        'combined': projectQualityReport(combined),
      });
      observations.add(observation);
      final expectedStatuses = {
        for (final checker in deterministicService.providers)
          checker.id: checker.supportsLanguage(request.language)
              ? OfficeProofingStatus.success.name
              : OfficeProofingStatus.unsupported.name,
        provider.id: sample.expectedModelStatus,
      };
      rows.add({
        ...observation.toJson(),
        'timing_ms': {
          'deterministic': deterministicMs,
          'model': timer.elapsedMicroseconds / 1000,
        },
        'expected_statuses': expectedStatuses,
        'status_contract_passed':
            [...deterministic.results, ...modelReport.results].every(
              (result) =>
                  expectedStatuses[result.providerId] == result.status.name,
            ),
      });
      // Each completed case survives a later failure or interrupted run.
      await _save(output, report);
    }
  } finally {
    await modelService?.dispose();
    await deterministicService?.dispose();
  }
  report['stage'] = 'source-seal';
  final after = await _sources(root, corpus);
  final stable = jsonEncode(before) == jsonEncode(after);
  final summary = summarizeQuality(cases, observations);
  final statusesPassed = rows.every(
    (row) => row['status_contract_passed'] == true,
  );
  report.addAll({
    'source_files_after': after,
    'source_stable': stable,
    'status_contract_passed': statusesPassed,
    'summary': summary,
    'completed': true,
    'operational_passed':
        stable && statusesPassed && summary['operational_passed'] == true,
    'stage': 'complete',
  });
  if (report['operational_passed'] != true) exitCode = 1;
}

Future<void> _save(File output, Map<String, Object?> report) async {
  final temporary = await output.parent.createTemp('.quality-checkpoint-');
  try {
    final replacement = File('${temporary.path}/report.json');
    await replacement.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(report)}\n',
      flush: true,
    );
    // Same-filesystem rename replaces only the destination reserved by main.
    // Interruption before rename leaves the previous complete checkpoint intact.
    await replacement.rename(output.path);
  } finally {
    await temporary.delete(recursive: true);
  }
}

Future<String> _digest(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();

Future<Map<String, Object?>> _pin(File file) async => {
  'file': file.uri.pathSegments.last,
  'bytes': await file.length(),
  'sha256': await _digest(file),
};

Future<Map<String, String>> _sources(Directory root, File corpus) async {
  final paths = <String>[
    'pubspec.yaml',
    'pubspec.lock',
    'packages/quds_office_engine/pubspec.yaml',
    'packages/quds_proofing_gector/pubspec.yaml',
    '.dart_tool/package_config.json',
    'tools/proofing/german_model/run_incremental_quality.dart',
    'tools/proofing/german_model/incremental_quality.dart',
    'tools/proofing/german_model/artifacts.json',
  ];
  for (final directory in [
    'packages/quds_office_engine/lib/src/proofing/',
    'packages/quds_office_engine/lib/src/opc/zip/',
    'packages/quds_proofing_gector/lib/',
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
      path: await _digest(File.fromUri(root.uri.resolve(path))),
    'declared-corpus': await _digest(corpus),
  };
}

Map<String, String> _arguments(List<String> arguments) {
  const required = {
    'cases',
    'bundle-dir',
    'model',
    'model-sha256',
    'library',
    'library-sha256',
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
    if ((!required.contains(key) && key != 'source-root') ||
        result.containsKey(key) ||
        arguments[index + 1].isEmpty) {
      throw ArgumentError('Unknown, duplicated or empty option: $key');
    }
    result[key] = arguments[index + 1];
  }
  if (!required.every(result.containsKey)) {
    throw ArgumentError('Required options: ${required.join(', ')}');
  }
  return result;
}
