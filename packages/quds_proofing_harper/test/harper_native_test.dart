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
      expect(
        (await provider.check(result.request)).status,
        OfficeProofingStatus.unavailable,
      );
      await provider.dispose();
    },
  );

  test(
    'disposal while the native worker starts completes queued checks',
    () async {
      final provider = HarperProofingProvider(
        nativeLibraryPath: '/missing/quds_harper_library',
      );
      final request = OfficeProofingRequest(
        documentId: 'd',
        blockId: 'b',
        revision: 1,
        text: 'This is an test.',
        language: 'en-US',
      );
      final first = provider.check(request);
      final second = provider.check(request);
      await provider.dispose();
      for (final result in await Future.wait([first, second])) {
        expect(result.status, OfficeProofingStatus.unavailable);
      }
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
    },
    skip: path == null
        ? 'Set QUDS_HARPER_TEST_LIBRARY to the built native library.'
        : false,
  );
}
