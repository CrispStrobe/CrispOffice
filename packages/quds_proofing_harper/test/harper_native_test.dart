@TestOn('vm')
library;

import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_proofing_harper/quds_proofing_harper.dart';
import 'package:test/test.dart';

void main() {
  test(
    'missing native library is unavailable without unhandled isolate errors',
    () async {
      final provider = HarperProofingProvider(
        nativeLibraryPath: '/missing/quds_harper_library',
      );
      final result = await provider.check(
        OfficeProofingRequest(
          documentId: 'd',
          blockId: 'b',
          revision: 1,
          text: 'This is an test.',
          language: 'en-US',
        ),
      );
      expect(result.status, OfficeProofingStatus.unavailable);
      final repeated = await provider
          .check(result.request)
          .timeout(const Duration(seconds: 1));
      expect(repeated.status, OfficeProofingStatus.unavailable);
      await provider.dispose();
    },
  );

  final path = Platform.environment['QUDS_HARPER_TEST_LIBRARY'];
  test(
    'real persistent native worker checks grammar and UTF16 source spans',
    () async {
      final provider = HarperProofingProvider(nativeLibraryPath: path);
      addTearDown(provider.dispose);
      for (var revision = 1; revision <= 3; revision++) {
        final result = await provider.check(
          OfficeProofingRequest(
            documentId: 'd',
            blockId: 'b',
            revision: revision,
            text: '😀 This is an test.',
            language: 'en-US',
            startOffset: 3,
          ),
        );
        expect(
          result.status,
          OfficeProofingStatus.success,
          reason: result.message,
        );
        final article = result.findings.firstWhere(
          (finding) => finding.ruleId == 'harper.AnA',
        );
        expect(article.originalText, 'an');
        expect(article.start, 14);
        expect(article.end, 16);
        expect(article.replacements, contains('a'));
        expect(article.revision, revision);
      }
      final concurrent = await Future.wait(
        List.generate(
          8,
          (index) => provider.check(
            OfficeProofingRequest(
              documentId: 'd',
              blockId: 'concurrent-$index',
              revision: index,
              text: '😀 This is an test.',
              language: 'en-US',
              ignoredRuleIds: index.isEven ? {'harper.AnA'} : {},
            ),
          ),
        ),
      );
      for (var index = 0; index < concurrent.length; index++) {
        final result = concurrent[index];
        expect(
          result.status,
          OfficeProofingStatus.success,
          reason: result.message,
        );
        expect(result.request.blockId, 'concurrent-$index');
        expect(
          result.findings.any((f) => f.ruleId == 'harper.AnA'),
          index.isOdd,
        );
      }
    },
    skip: path == null
        ? 'Set QUDS_HARPER_TEST_LIBRARY to the built native library.'
        : false,
  );

  test(
    'disposal while the isolate starts settles outstanding checks',
    () async {
      final provider = HarperProofingProvider(
        nativeLibraryPath: path ?? '/missing/quds_harper_library',
      );
      final pending = List.generate(
        4,
        (index) => provider.check(
          OfficeProofingRequest(
            documentId: 'd',
            blockId: '$index',
            revision: 1,
            text: 'This is an test.',
            language: 'en-US',
          ),
        ),
      );
      await provider.dispose();
      final results = await Future.wait(
        pending,
      ).timeout(const Duration(seconds: 1));
      expect(
        results.every((r) => r.status == OfficeProofingStatus.unavailable),
        isTrue,
      );
    },
  );
}
