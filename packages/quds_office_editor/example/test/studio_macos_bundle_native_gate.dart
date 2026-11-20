// Explicit acceptance gate for a built macOS app. Not an automatically
// discovered test (no `_test.dart` suffix). It boots the Studio widget tree
// with the native libraries packaged inside the app and the dictionary and
// morphology data installed by the real installers, then checks a mixed
// Arabic/German/English Word document end to end:
//
//   packages/quds_office_editor/example/tool/build_macos_app.sh
//   APP=.../build/macos/Build/Products/Release/CrispOffice.app
//   QUDS_STUDIO_APP=$APP \
//   QUDS_STUDIO_DATA="$HOME/Library/Containers/com.crispstrobe.crispoffice/Data/Library/Application Support/quds_office_studio" \
//   flutter test --dart-define=QUDS_HARPER_LIBRARY=$APP/Contents/Frameworks/libquds_proofing_harper.dylib \
//     test/studio_macos_bundle_native_gate.dart
//
// QUDS_STUDIO_DATA may point at the app container or at an empty scratch
// directory: AyaSpell and the Camel Morph proofing-bin bundle are installed
// there with Studio's own hosts (verified downloads from their immutable
// revisions) when they are missing, as the Dictionaries dialog would.
// Missing inputs fail; there are no skips or fallbacks.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_language_id/quds_language_id.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:quds_office_studio/main.dart';
import 'package:quds_office_studio/studio_arabic_morph_host.dart';
import 'package:quds_office_studio/studio_arabic_morph_host_native.dart';
import 'package:quds_office_studio/studio_hunspell_host.dart';
import 'package:quds_office_studio/studio_hunspell_host_native.dart';
import 'package:quds_office_studio/studio_language_id_host.dart';

const _arabicSpelling = 'ذهب الولد الى المدرسه وقرأ الكتااب.';
const _arabicGrammar = 'لم يبقى أحد في القاعة. نزلنا في ثلاث فنادق.';
const _german =
    'Der Bericht wurde gestern veröffentlicht und das Ergebnis war '
    'überraschend, aber die Mitarbeiter haben den Fehlr nicht bemerkt.';
const _english =
    'This is an test of the proofing service, and the report was '
    'published yesterday by the committee.';

Finder _key(String value) => find.byKey(ValueKey<String>(value));

/// dart:io's own [HttpClient], bypassing the test binding's mock.
final class _RealHttpOverrides extends HttpOverrides {}

void main() {
  final app = Platform.environment['QUDS_STUDIO_APP'];
  final data = Platform.environment['QUDS_STUDIO_DATA'];

  testWidgets(
    'bundled libraries proof a mixed Arabic/German/English document',
    (tester) async {
      expect(app, isNotNull, reason: 'Set QUDS_STUDIO_APP to the built .app.');
      expect(data, isNotNull, reason: 'Set QUDS_STUDIO_DATA to the data root.');
      const harper = String.fromEnvironment('QUDS_HARPER_LIBRARY');
      final frameworks = '$app/Contents/Frameworks';
      expect(harper, startsWith(frameworks));
      for (final name in [
        'libquds_proofing_hunspell.dylib',
        'libquds_arabic_morph.dylib',
        'libquds_language_id.dylib',
        'libquds_proofing_harper.dylib',
      ]) {
        expect(File('$frameworks/$name').existsSync(), isTrue, reason: name);
      }
      // The model asset packaged in the app is the pinned CLD3 model.
      final asset = File(
        '$frameworks/App.framework/Resources/flutter_assets/'
        'packages/quds_language_id/assets/cld3-f16.gguf',
      );
      expect(Cld3Model.verify(asset.readAsBytesSync()), isTrue);

      final root = Directory(data!);
      final hunspell = NativeStudioHunspellHost(
        root: root,
        libraryPath: '$frameworks/libquds_proofing_hunspell.dylib',
      );
      final morph = NativeStudioArabicMorphHost(
        root: root,
        libraryPath: '$frameworks/libquds_arabic_morph.dylib',
      );
      final languageId = BundledStudioLanguageIdHost(
        createIdentifier: (model) => Cld3LanguageIdentifier(
          model: model,
          nativeLibraryPath: '$frameworks/libquds_language_id.dylib',
        ),
      );
      await tester.runAsync(() async {
        await hunspell.refresh();
        await morph.refresh();
        // The test binding answers every request with HTTP 400; downloads
        // use a real client in this scope only.
        await HttpOverrides.runWithHttpOverrides(() async {
          for (final item in hunspell.statuses) {
            if (!item.installed) await hunspell.install(item.bundle);
          }
          if (!morph.status.installed) await morph.install();
        }, _RealHttpOverrides());
        await languageId.load();
      });
      expect(hunspell.statuses.single.installed, isTrue);
      expect(morph.status.loaded, isTrue, reason: morph.status.problem);
      expect(languageId.detector, isNotNull, reason: languageId.problem);
      studioHunspellHost = hunspell;
      studioArabicMorphHost = morph;
      studioLanguageIdHost = languageId;

      await tester.binding.setSurfaceSize(const Size(1440, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const QudsOfficeStudioApp());
      await tester.pump();
      final controller = tester
          .widget<QudsWordEditor>(find.byType(QudsWordEditor))
          .controller;
      expect(controller.proofing.automaticLanguageDetection, isTrue);
      controller.document = WmlDocument(
        proofingLanguage: 'en-US',
        sections: [
          WmlSection(
            blocks: [
              for (final text in [
                _arabicSpelling,
                _arabicGrammar,
                _german,
                _english,
              ])
                WmlParagraph(inlines: [WmlRun(text: text)]),
            ],
          ),
        ],
      );
      controller.refresh();
      controller.refreshView();

      Map<String, Set<String>> rules() {
        final byText = <String, Set<String>>{};
        controller.proofing.findingsByParagraph.forEach((paragraph, findings) {
          final text = paragraph.inlines.whereType<WmlRun>().map((r) => r.text);
          byText[text.join()] = {
            for (final f in findings) '${f.providerId}/${f.ruleId}',
          };
        });
        return byText;
      }

      bool has(String text, String rule) =>
          (rules()[text] ?? const {}).any((r) => r.endsWith('/$rule'));
      final watch = Stopwatch()..start();
      while (watch.elapsed < const Duration(seconds: 60) &&
          !(has(_arabicGrammar, 'ar.numeral.gender') &&
              has(_arabicSpelling, 'ar.ta-marbuta.final') &&
              (rules()[_arabicSpelling] ?? const {}).any(
                (r) => r.startsWith('hunspell-'),
              ) &&
              has(_german, 'de.spelling.unknown') &&
              has(_english, 'harper.AnA'))) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      final found = rules();
      // ignore: avoid_print
      print('findings: $found');
      // Arabic writing rules (no download) and AyaSpell (MPL, downloaded).
      expect(
        has(_arabicSpelling, 'ar.hamza.initial'),
        isTrue,
        reason: '$found',
      );
      expect(has(_arabicSpelling, 'ar.ta-marbuta.final'), isTrue);
      expect(
        found[_arabicSpelling]!.any((r) => r.startsWith('hunspell-')),
        isTrue,
      );
      // Morphology-based rules (Camel Morph proofing-bin).
      expect(has(_arabicGrammar, 'ar.grammar.jussive'), isTrue);
      expect(has(_arabicGrammar, 'ar.numeral.gender'), isTrue);
      // German routed by detection in an en-US document, English by Harper.
      expect(has(_german, 'de.spelling.unknown'), isTrue);
      expect(has(_english, 'harper.AnA'), isTrue);
      expect(found[_english]!.any((r) => r.contains('/de.')), isFalse);

      // The review pane shows the detected language of the caret paragraph.
      controller.caret
        ..paragraphIndex = 2
        ..logicalIndex = 3
        ..collapseSelection();
      controller.refreshView();
      controller.openReviewPane(tab: WordReviewPaneTab.proofing);
      controller.setTextProofingOptionsVisible(true);
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
      final scrollable = find
          .descendant(
            of: _key('word-review-pane'),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        _key('live-proofing-apply-detected'),
        120,
        scrollable: scrollable,
      );
      final detected = tester
          .widget<Text>(_key('live-proofing-text-detected'))
          .data!;
      // ignore: avoid_print
      print(detected);
      expect(detected, startsWith('Detected:'));
      expect(detected, contains('German'));
      await tester.tap(_key('live-proofing-apply-detected'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        controller.document.paragraphs
            .elementAt(2)
            .inlines
            .whereType<WmlRun>()
            .first
            .properties
            .proofingLanguage,
        'de-DE',
      );
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
      // Native transports keep bounded disposal grace timers (2 s and 10 s).
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pump(const Duration(seconds: 11));
      await tester.runAsync(() async {
        morph.dispose();
        languageId.dispose();
      });
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
