import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('installed English and German corpus panel, notices and warm lookup', () async {
    final report = <String, Object?>{
      'started_at_utc': DateTime.now().toUtc().toIso8601String(),
      'dart_version': Platform.version,
      'operating_system': Platform.operatingSystem,
      'operating_system_version': Platform.operatingSystemVersion,
      'process_rss_before_bytes': ProcessInfo.currentRss,
      'queries': <Object?>[],
    };
    try {
      final service = BundledOfficeThesaurus.create();
      final queries = <(String, String)>[
        ('bank', 'en-US'),
        ('run', 'en-US'),
        ('happy', 'en-GB'),
        ('ice cream', 'en-US'),
        ('children', 'en-US'),
        ('dogs', 'en-US'),
        ('Bank', 'de-DE'),
        ('Häusern', 'de-DE'),
        ('Maße', 'de-DE'),
        ('Masse', 'de-DE'),
        ('sich freuen', 'de-DE'),
        ('Straße', 'de-CH'),
        ('qudsxyzzynotaword', 'en-US'),
        ('qudsxyzzynotaword', 'de-DE'),
        ('banque', 'fr-FR'),
      ];
      final results = <String, OfficeThesaurusResult>{};
      for (final (word, language) in queries) {
        final clock = Stopwatch()..start();
        final result = await service.lookup(OfficeThesaurusQuery(text: word, language: language));
        clock.stop();
        results['$word:$language'] = result;
        (report['queries'] as List<Object?>).add(<String, Object?>{
          'text': word,
          'language': language,
          'status': result.status.name,
          'message': result.message,
          'elapsed_ms': clock.elapsedMicroseconds / 1000,
          'pack': result.packIdentity,
          'matches': [for (final m in result.matchedTerms) {'text': m.text, 'reason': m.reason, 'pos': m.pos}],
          'senses': [for (final s in result.senses) {
            'id': s.id, 'source': s.source, 'pos': s.pos, 'gloss': s.gloss,
            'labels': s.labels, 'examples': s.examples,
            'terms': [for (final t in s.terms) {'id': t.id, 'text': t.text, 'labels': t.labels}],
            'relations': [for (final r in s.relations) {'type': r.type, 'target': r.target}],
          }],
        });
        final expected = language == 'fr-FR'
            ? OfficeThesaurusStatus.unsupportedLanguage
            : word.startsWith('qudsxyz')
                ? OfficeThesaurusStatus.noEntry
                : OfficeThesaurusStatus.ready;
        expect(result.status, expected, reason: '$word ($language): ${result.message}');
      }
      expect(results['bank:en-US']!.senses.length, greaterThan(1));
      expect(results['Bank:de-DE']!.senses.length, greaterThan(1));
      expect(results['Maße:de-DE']!.senses.map((s) => s.id).toSet(),
          isNot(results['Masse:de-DE']!.senses.map((s) => s.id).toSet()));
      expect(results['Häusern:de-DE']!.matchedTerms.any((m) => m.text == 'Haus'), isTrue);
      final noticeRecords = <Object?>[];
      for (final key in ['bank:en-US', 'Bank:de-DE']) {
        final result = results[key]!;
        final notices = await service.notices(result);
        expect(notices.length, greaterThanOrEqualTo(2));
        expect(notices.every((n) => n.text.trim().isNotEmpty), isTrue);
        noticeRecords.add({'pack': result.packIdentity,
          'notices': [for(final n in notices) {'path': n.path, 'characters': n.text.length}]});
      }
      report['notices'] = noticeRecords;
      final warmMs = <double>[];
      for (var iteration = 0; iteration < 5; iteration++) {
        for (final (word, language) in queries) {
          final clock = Stopwatch()..start();
          await service.lookup(OfficeThesaurusQuery(text: word, language: language));
          clock.stop();
          warmMs.add(clock.elapsedMicroseconds / 1000);
        }
      }
      final sorted = List<double>.of(warmMs)..sort();
      report.addAll({
        'warm_query_count': warmMs.length,
        'warm_ms': warmMs,
        'warm_p50_ms': sorted[(sorted.length * .5).floor()],
        'warm_p95_ms': sorted[(sorted.length * .95).floor()],
        'cached_shards': service.cachedShardCount,
        'cached_results': service.cachedResultCount,
        'cache_limits': {'shards': service.maxCachedShards, 'results': service.maxCachedResults},
        'status': 'passed',
      });
      expect(service.cachedShardCount, lessThanOrEqualTo(service.maxCachedShards));
      expect(service.cachedResultCount, lessThanOrEqualTo(service.maxCachedResults));
    } catch (error, stack) {
      report['status'] = 'failed';
      report['error'] = '$error\n$stack';
      rethrow;
    } finally {
      report['process_rss_after_bytes'] = ProcessInfo.currentRss;
      report['process_peak_rss_bytes'] = ProcessInfo.maxRss;
      report['finished_at_utc'] = DateTime.now().toUtc().toIso8601String();
      final path = Platform.environment['QUDS_THESAURUS_NATIVE_REPORT'];
      if (path != null) {
        await File(path).writeAsString('${const JsonEncoder.withIndent('  ').convert(report)}\n');
      }
    }
  });
}
