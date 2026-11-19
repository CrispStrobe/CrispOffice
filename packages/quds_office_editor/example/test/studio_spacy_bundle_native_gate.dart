// Explicit acceptance gate for the spaCy runtime inside a built macOS app.
// Not an automatically discovered test (no `_test.dart` suffix). It finds the
// signed library in the app's Contents/Frameworks through the same detection
// Studio uses (Contents/Resources/spacy-native.json), installs the verified
// model files from their immutable Hugging Face revisions with Studio's own
// host when they are missing, and analyzes German (with the optional named
// entities) and English text in the real isolate worker:
//
//   packages/quds_office_editor/example/tool/build_macos_app.sh
//   APP=.../build/macos/Build/Products/Release/quds_office_studio.app
//   QUDS_STUDIO_APP=$APP \
//   QUDS_STUDIO_DATA="$HOME/Library/Containers/com.quds.qudsOfficeStudio/Data/Library/Application Support/quds_office_studio" \
//   flutter test test/studio_spacy_bundle_native_gate.dart
//
// QUDS_STUDIO_DATA may point at the app container (the launched app then
// finds the same verified installation) or at an empty scratch directory.
// Missing inputs fail; there are no skips or fallbacks.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_studio/studio_spacy_host.dart';
import 'package:quds_office_studio/studio_spacy_host_native.dart';
import 'package:quds_proofing_spacy/quds_proofing_spacy.dart';

String _required(String name) {
  final value = Platform.environment[name];
  if (value == null || value.isEmpty) {
    fail('Set $name (see the header of this file).');
  }
  return value;
}

void main() {
  test(
    'the bundled spaCy library analyzes German and English from the app',
    () async {
      final app = _required('QUDS_STUDIO_APP');
      final data = _required('QUDS_STUDIO_DATA');
      final bundled = detectBundledSpacyLibrary(const {
        'QUDS_SPACY_BUNDLED': '1',
      }, executable: '$app/Contents/MacOS/quds_office_studio');
      expect(bundled, isNotNull, reason: 'no spacy-native.json in $app');
      expect(bundled!.path, startsWith('$app/Contents/Frameworks/'));
      final host = NativeStudioSpacyHost(
        root: Directory('$data/spacy'),
        environment: const {},
        platform: SpacyPlatform.macosArm64,
        bundledLibrary: bundled,
      );
      await host.refresh();
      expect(host.status.bundledLibrary, isTrue);
      expect(host.status.problem, isNull);
      if (host.status.source == StudioSpacySource.none) await host.install();
      if (!host.status.analysisEnabled) await host.setAnalysisEnabled(true);
      if (!host.status.nerEnabled) await host.setNerEnabled(true);
      if (!host.status.language(SpacyLanguage.english)!.installed) {
        await host.installLanguage(SpacyLanguage.english);
      }
      expect(host.status.source, StudioSpacySource.installed);
      expect(host.status.librarySha256, bundled.sha256);
      // Model files only: no downloaded executable code.
      expect(Directory('$data/spacy/packages').existsSync(), isFalse);

      const german = 'Angela Merkel besuchte gestern die Universität in Berlin.';
      final transport = await host.openTransport();
      try {
        expect(transport.identity.librarySha256, bundled.sha256);
        final result = await transport.analyze(
          LinguisticAnalysisRequest(
            text: german,
            documentId: 'gate',
            blockId: 'de',
            revision: 1,
          ),
        );
        final lemmas = {for (final t in result.tokens) t.text: t.lemma};
        expect(lemmas['besuchte'], 'besuchen');
        expect(
          result.tokens.firstWhere((t) => t.text == 'Berlin').pos,
          'PROPN',
        );
        expect(result.sentences, hasLength(1));
        expect(
          result.entities.map((e) => '${e.label}:${e.text}'),
          containsAll(['PER:Angela Merkel', 'LOC:Berlin']),
        );
        // ignore: avoid_print
        print(
          'de: ${[for (final t in result.tokens) '${t.text}/${t.lemma}/${t.pos}/${t.dependency}'].join(' ')}'
          ' | entities ${[for (final e in result.entities) '${e.label}:${e.text}']}',
        );
      } finally {
        await transport.dispose();
      }

      const english = 'Tim Cook visited London on Monday.';
      final englishTransport = await host.openLanguageTransport(
        SpacyLanguage.english,
      );
      try {
        final result = await englishTransport.analyze(
          LinguisticAnalysisRequest(
            text: english,
            documentId: 'gate',
            blockId: 'en',
            revision: 1,
            locale: 'en-US',
          ),
        );
        expect(
          {for (final t in result.tokens) t.text: t.lemma}['visited'],
          'visit',
        );
        expect(
          result.entities.map((e) => '${e.label}:${e.text}'),
          containsAll(['PERSON:Tim Cook', 'GPE:London']),
        );
        // ignore: avoid_print
        print(
          'en: ${[for (final t in result.tokens) '${t.text}/${t.lemma}/${t.pos}'].join(' ')}'
          ' | entities ${[for (final e in result.entities) '${e.label}:${e.text}']}',
        );
      } finally {
        await englishTransport.dispose();
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
