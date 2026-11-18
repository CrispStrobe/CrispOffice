// Real-file native qualification. No network or Flutter dependency.
import 'dart:convert';
import 'dart:io';
// Standalone tool uses the qualified workspace's existing crypto dependency.
// ignore: depend_on_referenced_packages
import 'package:crypto/crypto.dart';
// Standalone tool invoked with the qualified workspace's package configuration.
// ignore: depend_on_referenced_packages
import 'package:quds_office_engine/src/thesaurus/office_thesaurus.dart';

Future<void> main(List<String> args) async {
  if (args.length != 2) {
    throw ArgumentError('Usage: benchmark.dart PACK_ROOT OUTPUT_JSON');
  }
  final root = Directory(args[0]);
  final providerFile = File.fromUri(
    Platform.script.resolve(
      '../../packages/quds_office_engine/lib/src/thesaurus/office_thesaurus.dart',
    ),
  );
  final baselineRss = ProcessInfo.currentRss;
  final reports = <String, Object?>{};
  final panel = <String, List<String>>{
    'en-US': ['bank', 'ice cream', 'mice', 'walked', 'colour', 'good', 'run'],
    'de-DE': [
      'Bank',
      'Häusern',
      'Maße',
      'Masse',
      'sich freuen',
      'Jänner',
      'Oheim',
    ],
  };
  for (final language in panel.keys) {
    var bytesRead = 0, filesRead = 0;
    final service = OfficeThesaurusService(
      loadAsset: (path) async {
        final file = File('${root.path}/$path');
        if (!file.existsSync()) return null;
        final bytes = await file.readAsBytes();
        bytesRead += bytes.length;
        filesRead++;
        return utf8.decode(bytes);
      },
      loadCompressedAsset: (path) async {
        final file = File('${root.path}/$path');
        if (!file.existsSync()) return null;
        final bytes = await file.readAsBytes();
        bytesRead += bytes.length;
        filesRead++;
        return bytes;
      },
    );
    final queryReports = <String, Object?>{};
    final uncached = <double>[], resultCached = <double>[];
    for (final text in panel[language]!) {
      final watch = Stopwatch()..start();
      final result = await service.lookup(
        OfficeThesaurusQuery(text: text, language: language),
      );
      watch.stop();
      if (result.status != OfficeThesaurusStatus.ready) {
        throw StateError('$language/$text: ${result.status} ${result.message}');
      }
      if (text == 'Häusern' &&
          !result.matchedTerms.any((m) => m.text == 'Haus')) {
        throw StateError(
          'German finite noun morphology did not resolve Häusern to Haus',
        );
      }
      if (text == 'mice' && result.senses.any((s) => s.pos != 'n')) {
        throw StateError('English source-form morphology lost its noun POS');
      }
      if (text == 'walked' && result.senses.any((s) => s.pos != 'v')) {
        throw StateError('English detachment morphology lost its verb POS');
      }
      queryReports[text] = {
        'firstQueryMs': watch.elapsedMicroseconds / 1000,
        'senseIds': result.senses.map((s) => s.id).toList(),
        'matchedTerms': [
          for (final m in result.matchedTerms)
            {'text': m.text, 'reason': m.reason},
        ],
      };
      // Original query text is retained in cache keys. These normalized-equivalent
      // variants measure provider work with result caching intentionally bypassed.
      for (var pass = 1; pass <= 10; pass++) {
        watch
          ..reset()
          ..start();
        final variant = await service.lookup(
          OfficeThesaurusQuery(text: '$text${' ' * pass}', language: language),
        );
        watch.stop();
        if (variant.status != OfficeThesaurusStatus.ready) {
          throw StateError(
            'Variant lookup failed: $language/$text/$pass ${variant.status} ${variant.message}',
          );
        }
        uncached.add(watch.elapsedMicroseconds / 1000);
        watch
          ..reset()
          ..start();
        await service.lookup(
          OfficeThesaurusQuery(text: '$text${' ' * pass}', language: language),
        );
        watch.stop();
        resultCached.add(watch.elapsedMicroseconds / 1000);
      }
    }
    final noEntry = await service.lookup(
      OfficeThesaurusQuery(
        text: 'qudszznonexistentlexicalprobe',
        language: language,
      ),
    );
    if (noEntry.status != OfficeThesaurusStatus.noEntry) {
      throw StateError('Negative control failed');
    }
    final result = await service.lookup(
      OfficeThesaurusQuery(text: panel[language]!.first, language: language),
    );
    final notices = await service.notices(result);
    reports[language] = {
      'queries': queryReports,
      'manifestSha256': result.pack!.digest,
      'bytesReadIncludingReloads': bytesRead,
      'filesReadIncludingReloads': filesRead,
      'cachedShards': service.cachedShardCount,
      'cachedResults': service.cachedResultCount,
      'maxCachedShards': service.maxCachedShards,
      'maxCachedResults': service.maxCachedResults,
      'verifiedNotices': notices.map((n) => n.path).toList(),
      'normalizedEquivalentUncachedResult': statistics(uncached),
      'cachedResult': statistics(resultCached),
    };
  }
  final receipt = {
    'status': 'passed',
    'dartVersion': Platform.version,
    'operatingSystem': Platform.operatingSystem,
    'processors': Platform.numberOfProcessors,
    'providerSha256': sha256.convert(providerFile.readAsBytesSync()).toString(),
    'benchmarkSha256': sha256
        .convert(File.fromUri(Platform.script).readAsBytesSync())
        .toString(),
    if (File('/proc/cpuinfo').existsSync())
      'cpuModel': File('/proc/cpuinfo')
          .readAsLinesSync()
          .where((line) => line.startsWith('model name'))
          .first
          .split(':')
          .last
          .trim(),
    'baselineRssBytes': baselineRss,
    'finalRssBytes': ProcessInfo.currentRss,
    'peakProcessRssBytes': ProcessInfo.maxRss,
    'network':
        'No network loader; all assets and notices read from local files.',
    'method':
        'First query per term is measured separately; 10 normalized-equivalent whitespace variants bypass result caching, each immediately repeated for cached-result timing. Max 64 parsed shards and 64 result entries.',
    'languages': reports,
  };
  File(args[1]).writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(receipt)}\n',
  );
  stdout.writeln(
    jsonEncode({
      'status': 'passed',
      'peakProcessRssBytes': ProcessInfo.maxRss,
      for (final entry in reports.entries)
        entry.key: {
          'provider':
              (entry.value as Map)['normalizedEquivalentUncachedResult'],
          'cached': (entry.value as Map)['cachedResult'],
        },
    }),
  );
}

Map<String, Object> statistics(List<double> values) {
  final sorted = [...values]..sort();
  double percentile(double fraction) =>
      sorted[((sorted.length - 1) * fraction).ceil()];
  return {
    'samples': sorted.length,
    'p50Ms': percentile(.5),
    'p95Ms': percentile(.95),
    'maxMs': sorted.last,
  };
}
