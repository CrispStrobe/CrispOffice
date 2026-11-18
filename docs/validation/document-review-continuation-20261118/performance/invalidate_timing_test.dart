import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

final class _FastProvider extends OfficeProofingProvider {
  _FastProvider(this.withFindings);
  final bool withFindings;
  @override String get id => 'timing-fixture';
  @override bool supportsLanguage(String language) => true;
  @override
  Future<OfficeProofingResult> check(OfficeProofingRequest request) async =>
      OfficeProofingResult(
        request: request,
        providerId: id,
        status: OfficeProofingStatus.success,
        findings: withFindings
            ? [OfficeProofingFinding.forRequest(
                request, providerId: id, start: 0, end: 4,
                ruleId: 'timing', message: 'Timing fixture',
                category: OfficeProofingCategory.spelling,
                replacements: const ['test'])]
            : const [],
      );
}

void main() {
  for (final withFindings in [false, true]) {
    test('synchronous invalidate timing findings=' + withFindings.toString(), () async {
      final text = List.filled(16, 'word ').join();
      final paragraphs = List.generate(
        500, (_) => WmlParagraph(inlines: [WmlRun(text: text)]),
      );
      final document = WmlDocument(
        sections: [WmlSection(blocks: paragraphs)],
      );
      var revision = 0;
      final session = WordProofingSession(
        document: () => document,
        revision: () => revision,
        service: OfficeProofingService(providers: [_FastProvider(withFindings)]),
        debounce: const Duration(hours: 1),
      );
      addTearDown(session.dispose);
      session.enableBackgroundByDefault();
      await session.checkNow(includeManualProviders: false);
      void edit(int i) {
        paragraphs.first.inlines = [
          WmlRun(text: text.substring(0, 79) + (i.isEven ? 'x' : 'y')),
        ];
        revision++;
      }
      for (var i = 0; i < 30; i++) {
        edit(i);
        session.observeDocument();
      }
      final elapsed = <int>[];
      for (var i = 0; i < 100; i++) {
        edit(i);
        final watch = Stopwatch()..start();
        session.observeDocument();
        watch.stop();
        elapsed.add(watch.elapsedMicroseconds);
      }
      elapsed.sort();
      print(jsonEncode({
        'kind': 'synchronous-observeDocument',
        'paragraphs': 500,
        'characters_per_paragraph': 80,
        'warmup_edits': 30,
        'measured_edits': elapsed.length,
        'primed_cache': true,
        'initial_findings_per_paragraph': withFindings ? 1 : 0,
        'retained_issues': session.summary.issues.length,
        'unit': 'microseconds',
        'median': (elapsed[49] + elapsed[50]) / 2,
        'p95': elapsed[94],
        'max': elapsed.last,
        'min': elapsed.first,
        'mean': elapsed.reduce((a, b) => a + b) / elapsed.length,
        'runtime_mode': 'flutter-test JIT on this host; diagnostic only',
      }));
      expect(elapsed.length, 100);
    });
  }
}

