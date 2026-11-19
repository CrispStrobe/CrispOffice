// Load time, memory and throughput of the native backend through the Dart
// API (FFI isolate, JSON decoding, compact maps, isolate transfer):
//   dart run tool/pud_benchmark.dart <library> <noprob bundle dir> <corpus.txt>
// The corpus has one sentence per line (e.g. the 1,000 `# text` lines of
// UD Arabic-PUD r2.14 test); distinct Arabic words are analyzed cold, then
// again from the session cache.
import 'dart:convert';
import 'dart:io';

import 'package:quds_arabic_morph/quds_arabic_morph.dart';

Future<void> main(List<String> args) async {
  if (args.length != 3) {
    stderr.writeln('usage: pud_benchmark.dart <library> <bundle dir> <corpus>');
    exit(64);
  }
  final [library, bundle, corpus] = args;
  final arabic = RegExp(r'[ؠ-يٮ-ۓ]');
  final word = RegExp(r'[\p{L}\p{M}]+', unicode: true);
  final lines = File(corpus).readAsLinesSync();
  final tokens = [
    for (final line in lines)
      for (final match in word.allMatches(line))
        if (arabic.hasMatch(match[0]!)) match[0]!,
  ];
  final distinct = tokens.toSet().toList();
  int mb(int bytes) => bytes ~/ (1024 * 1024);
  final rssStart = ProcessInfo.currentRss;

  final morphology = CamelArabicMorphology(
    database: MorphDatabaseFiles(
      camelMorphMsaNoprob,
      manifestPath: '$bundle/manifest.json',
    ),
    nativeLibraryPath: library,
  );
  final load = Stopwatch()..start();
  await morphology.load();
  load.stop();
  if (!morphology.isAvailable) throw StateError('${morphology.failure}');
  final rssLoaded = ProcessInfo.currentRss;

  final cold = Stopwatch()..start();
  final result = await morphology.analyzeWords(distinct);
  cold.stop();
  final rssAnalyzed = ProcessInfo.currentRss;
  final warm = Stopwatch()..start();
  await morphology.analyzeWords(tokens);
  warm.stop();

  final analyses = result.values.fold<int>(0, (sum, list) => sum + list.length);
  final report = {
    'sentences': lines.length,
    'arabic_tokens': tokens.length,
    'distinct_words': distinct.length,
    'analyzed_words': result.values.where((list) => list.isNotEmpty).length,
    'analyses': analyses,
    'load_seconds': load.elapsedMilliseconds / 1000,
    'cold_seconds': cold.elapsedMilliseconds / 1000,
    'cold_words_per_second':
        (distinct.length / cold.elapsed.inMicroseconds * 1e6).round(),
    'cached_tokens_seconds': warm.elapsedMilliseconds / 1000,
    'rss_mb': {
      'start': mb(rssStart),
      'after_load': mb(rssLoaded),
      'after_analysis_and_cache': mb(rssAnalyzed),
      'peak': mb(ProcessInfo.maxRss),
    },
    'platform': Platform.operatingSystemVersion,
    'info': morphology.info,
  };
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(report));
  await morphology.dispose();
}
