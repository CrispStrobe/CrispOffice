// Reproducible production Dart client/provider smoke using synthetic text only.
// Run in an empty working directory, with --packages pointing at the resolved
// workspace package_config.json, and pass the built worker's absolute path.
// The archive itself is not a Dart package; the explicit workspace config
// supplies the two tested packages when reproducing this integration check.
// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';
import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_proofing_aot/quds_proofing_aot.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    stderr.writeln('Pass the absolute path of the built quds_aot_worker.');
    exitCode = 2;
    return;
  }
  if (Directory.current.listSync().isNotEmpty) {
    throw StateError('Run this smoke in an empty directory.');
  }
  final Stopwatch stopwatch = Stopwatch()..start();
  final AotClient client = AotClient.local(executable: arguments.single);
  final AotProofingProvider provider = AotProofingProvider(
    analyzer: client,
    ownsAnalyzer: false,
    timeout: const Duration(seconds: 60),
  );
  final List<Map<String, Object?>> checks = <Map<String, Object?>>[];
  final List<Map<String, Object?>> analyses = <Map<String, Object?>>[];
  final List<Map<String, Object?>> morphology = <Map<String, Object?>>[];
  try {
    const List<(String, String?, String?)> samples =
        <(String, String?, String?)>[
          ('Ich geht.', 'geht', 'gehe'),
          ('mit den Hund', 'den', 'dem'),
          ('Der kleines Hund schläft.', 'kleines', 'kleine'),
          ('Ich gehe.', null, null),
          ('mit dem Hund', null, null),
          ('Der kleine Hund schläft.', null, null),
          ('Es kommen Gäste.', null, null),
          ('Sie gehen.', null, null),
          ('Ich versuche zu helfen.', null, null),
          ('Ich versuche, zu helfen.', null, null),
        ];
    for (final (String text, String? original, String? replacement)
        in samples) {
      final OfficeProofingResult report = await provider.check(
        OfficeProofingRequest(
          documentId: 'native-smoke',
          blockId: 'paragraph',
          revision: 1,
          text: text,
          language: 'de-DE',
        ),
      );
      final bool passed =
          report.status == OfficeProofingStatus.success &&
          (original == null
              ? report.findings.isEmpty
              : report.findings.any(
                  (OfficeProofingFinding finding) =>
                      finding.originalText == original &&
                      finding.replacements.contains(replacement),
                ));
      checks.add(<String, Object?>{
        'text': text,
        'passed': passed,
        'status': report.status.name,
        'findings': <Object?>[
          for (final OfficeProofingFinding finding in report.findings)
            <String, Object?>{
              'rule': finding.ruleId,
              'original': finding.originalText,
              'replacements': finding.replacements,
              'start': finding.start,
              'end': finding.end,
            },
        ],
      });
    }
    for (final (String text, AotLanguage language) in <(String, AotLanguage)>[
      ('Der kleine Hund schläft.', AotLanguage.german),
      ('Мама мыла раму.', AotLanguage.russian),
      ('Ich versuche zu helfen.', AotLanguage.german),
      ('Ich versuche, zu helfen.', AotLanguage.german),
    ]) {
      final AotAnalysis analysis = await client.analyze(
        text,
        language: language,
      );
      analyses.add(<String, Object?>{
        'text': text,
        'language': language.name,
        'passed': analysis.fullyAligned && analysis.tokens.isNotEmpty,
        'fullyAligned': analysis.fullyAligned,
        'tokens': <Object?>[
          for (final AotToken token in analysis.tokens)
            <String, Object?>{
              'sourceText': token.text,
              'analysisText': token.analysisText,
              'start': token.start,
              'end': token.end,
            },
        ],
      });
    }
    for (final (String word, AotLanguage language) in <(String, AotLanguage)>[
      ('Hund', AotLanguage.german),
      ('кошки', AotLanguage.russian),
      ('goes', AotLanguage.english),
    ]) {
      final AotMorphology result = await client.morphology(
        word,
        language: language,
        withParadigms: true,
      );
      final AotMorphology cached = await client.morphology(
        word,
        language: language,
        withParadigms: true,
      );
      morphology.add(<String, Object?>{
        'word': word,
        'language': language.name,
        'passed':
            result.readings.any((AotMorphReading reading) => reading.found) &&
            identical(result, cached),
        'cacheReused': identical(result, cached),
        'lemmas': <String>[
          for (final AotMorphReading reading in result.readings) reading.lemma,
        ],
        'paradigmForms': result.readings.fold<int>(
          0,
          (int total, AotMorphReading reading) => total + reading.forms.length,
        ),
      });
    }
  } finally {
    await provider.dispose();
    await client.dispose();
  }
  final List<String> outputs = Directory.current
      .listSync()
      .map((FileSystemEntity file) => file.path)
      .toList();
  final bool passed =
      outputs.isEmpty &&
      <Map<String, Object?>>[
        ...checks,
        ...analyses,
        ...morphology,
      ].every((Map<String, Object?> record) => record['passed'] == true);
  stdout.writeln(
    const JsonEncoder.withIndent('  ').convert(<String, Object?>{
      'passed': passed,
      'elapsedMilliseconds': stopwatch.elapsedMilliseconds,
      'transport': 'AotClient.local / AotProcessTransport',
      'syntheticTextOnly': true,
      'networkEndpoint': null,
      'workingDirectoryOutputs': outputs,
      'proofing': checks,
      'analysis': analyses,
      'morphology': morphology,
    }),
  );
  if (!passed) exitCode = 1;
}
