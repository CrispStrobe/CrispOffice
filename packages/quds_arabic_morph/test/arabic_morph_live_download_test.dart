// Optional network qualification; normal native tests use a pinned local bundle.
@TestOn('vm')
library;

import 'dart:io';

import 'package:quds_arabic_morph/installer_io.dart';
import 'package:quds_arabic_morph/quds_arabic_morph.dart';
import 'package:test/test.dart';

final _library = Platform.environment['QUDS_ARABIC_MORPH_TEST_LIBRARY'];

void main() {
  test(
    'live download from the pinned Hugging Face revision',
    () async {
      final root = Directory.systemTemp.createTempSync('arabic-morph-live-');
      try {
        final files = await MorphInstaller(
          root,
        ).install(camelMorphMsaProofingBin);
        expect(
          File(
            '${File(files.manifestPath).parent.path}/'
            '${camelMorphMsaProofingBin.database.file}',
          ).lengthSync(),
          camelMorphMsaProofingBin.database.bytes,
        );
        if (_library != null) {
          final morphology = CamelArabicMorphology(
            database: files,
            nativeLibraryPath: _library,
          );
          final result = await morphology.analyzeWords(['كتبوا']);
          expect(result['كتبوا'], isNotEmpty);
          await morphology.dispose();
        }
      } finally {
        root.deleteSync(recursive: true);
      }
    },
    skip: Platform.environment['QUDS_ARABIC_MORPH_LIVE_DOWNLOAD'] == '1'
        ? false
        : 'Set QUDS_ARABIC_MORPH_LIVE_DOWNLOAD=1 to download from Hugging Face.',
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
