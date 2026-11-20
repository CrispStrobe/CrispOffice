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
// When the bundled library is one with recorded grammar qualification, the
// gate also switches on manual German grammar through the host (as the
// Setup dialog does) and checks a sentence from the sealed W6 panel.
// Missing inputs fail; there are no skips or fallbacks.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_studio/studio_spacy_host.dart';
import 'package:quds_office_studio/studio_spacy_host_native.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:quds_proofing_spacy/quds_proofing_spacy_grammar.dart';

String _required(String name) {
  final value = Platform.environment[name];
  if (value == null || value.isEmpty) {
    fail('Set $name (see the header of this file).');
  }
  return value;
}

void main() {
  test('the bundled spaCy library analyzes German and English from the app', () async {
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
      if (bundled.codeSha256 != null) {
        expect(transport.identity.codeSha256, bundled.codeSha256);
      }
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
      expect(result.tokens.firstWhere((t) => t.text == 'Berlin').pos, 'PROPN');
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

    // The exact qualified bytes, or a release-signed copy of the same code
    // (build_macos_app.sh --sign records its code digest).
    if (spacyGrammarNativeSha256s.contains(bundled.sha256) ||
        spacyGrammarCodeSha256s.contains(bundled.codeSha256)) {
      expect(host.status.qualification!.grammarQualified, isTrue);
      expect(host.status.grammarOffered, isTrue);
      final wasEnabled = host.status.grammarEnabled;
      await host.setGrammarEnabled(true);
      expect(host.status.grammarEnabled, isTrue);
      // Studio's provider worker: the bundled library without NER.
      final grammarTransport = await host.openGrammarTransport();
      final provider = SpacyGrammarProvider.withTransport(
        transport: grammarTransport,
        enabled: true,
      );
      try {
        expect(grammarTransport.identity.librarySha256, bundled.sha256);
        expect(grammarTransport.identity.capabilityMask, 15);
        // The worker measured the code digest from the bytes it loaded; the
        // planner trusts only that, not spacy-native.json.
        expect(
          spacyGrammarQualifiedIdentity(grammarTransport.identity),
          isTrue,
        );
        if (bundled.codeSha256 != null) {
          expect(grammarTransport.identity.codeSha256, bundled.codeSha256);
        }
        // W6 panel: subject with an intervening prepositional modifier.
        const sentence = 'Die Katzen auf dem Sofa schläft.';
        final result = await provider.check(
          OfficeProofingRequest(
            documentId: 'gate',
            blockId: 'w6',
            revision: 1,
            text: sentence,
            language: 'de-DE',
          ),
        );
        expect(result.status, OfficeProofingStatus.success);
        final finding = result.findings.single;
        expect(finding.ruleId, spacyNounVerbRuleId);
        expect(finding.originalText, 'schläft');
        expect(finding.replacements, ['schlafen']);
        // ignore: avoid_print
        print(
          'grammar: "$sentence" -> ${finding.originalText} => '
          '${finding.replacements.single}',
        );
      } finally {
        await provider.dispose();
      }
      if (!wasEnabled) await host.setGrammarEnabled(false);
    } else {
      expect(host.status.grammarOffered, isFalse);
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
  }, timeout: const Timeout(Duration(minutes: 5)));
}
