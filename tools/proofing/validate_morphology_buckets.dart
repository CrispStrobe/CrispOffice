// Workspace-level qualification; use the root .dart_tool/package_config.json.
// ignore_for_file: depend_on_referenced_packages
//
// Source binding: run from the same pinned checkout as the proofing tests.
// Retain the commit, dirty status, SHA-256 of morphology_manifest.json and the
// runtime binary alongside this output. Optionally label that external receipt
// with -DQUDS_MORPHOLOGY_SOURCE_BINDING=<receipt or source identifier>. A passed
// parse is not evidence for another revision or general linguistic accuracy.

import 'dart:convert';
import 'package:quds_office_engine/src/proofing/german_morphology.dart';

Future<void> main() async {
  int bucket(String word) {
    int hash = 0;
    for (final int unit in word.codeUnits) {
      hash = (hash * 31 + unit) & 255;
    }
    return hash;
  }

  final Map<int, String> probes = <int, String>{};
  for (int i = 0; probes.length < 256 && i < 100000; i++) {
    final String word = 'bucket$i';
    probes.putIfAbsent(bucket(word), () => word);
  }
  if (probes.length != 256) throw StateError('Cannot cover every bucket');
  final GermanNounMorphology morphology = GermanNounMorphology.shared;
  final Stopwatch timer = Stopwatch()..start();
  await morphology.prepareWords(probes.values);
  timer.stop();
  if (morphology.loadedBucketCount != 256 ||
      morphology.cachedReadingCount != morphology.readingCount) {
    throw StateError('Incomplete bucket or reading coverage');
  }
  print(
    jsonEncode(<String, Object>{
      'status': 'passed',
      'source_binding': const String.fromEnvironment(
        'QUDS_MORPHOLOGY_SOURCE_BINDING',
        defaultValue: 'External source-and-runtime receipt required',
      ),
      'buckets': morphology.loadedBucketCount,
      'readings': morphology.cachedReadingCount,
      'elapsed_milliseconds': timer.elapsedMilliseconds,
      'coverage':
          'Every bucket parsed, mask/id/descriptor checks passed; not linguistic accuracy.',
    }),
  );
}
