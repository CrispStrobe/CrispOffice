// Studio wiring of automatic language detection: the bundled model asset,
// the host, the setting, the language options in the review pane and the
// licence page. A fake classifier stands in for CLD3 here; the real native
// library is exercised by packages/quds_language_id/test.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_language_id/quds_language_id.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:quds_office_studio/main.dart';
import 'package:quds_office_studio/studio_language_id_host.dart';
import 'package:quds_office_studio/studio_licenses.dart';

final class _FakeIdentifier implements LanguageIdentifier {
  @override
  bool get isAvailable => true;

  @override
  Future<List<List<LanguageGuess>>> identify(List<String> texts) async => [
    for (final text in texts)
      RegExp(r'\p{Script=Arabic}', unicode: true).hasMatch(text)
          ? const [LanguageGuess('ar', 0.99)]
          : const [LanguageGuess('de', 0.999)],
  ];
}

const _german =
    'Der Bericht wurde gestern veröffentlicht und sorgte für Aufsehen.';
const _arabic = 'وقد نشر التقرير أمس وأثار ضجة كبيرة في الأوساط السياسية.';

Future<void> _pump(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 450));
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
}

Finder _key(String value) => find.byKey(ValueKey<String>(value));

void main() {
  test('the bundled model asset is the pinned CLD3 model', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final data = await rootBundle.load(Cld3Model.assetKey);
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    expect(bytes.length, Cld3Model.bytes);
    expect(Cld3Model.verify(bytes), isTrue);
  });

  test('a host without the native library reports the problem', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final host = BundledStudioLanguageIdHost(
      createIdentifier: (model) => Cld3LanguageIdentifier(
        model: model,
        nativeLibraryPath: '/nonexistent/libquds_language_id.dylib',
      ),
    );
    addTearDown(host.dispose);
    await host.load();
    expect(host.detector, isNull);
    expect(host.problem, contains('library'));
  });

  testWidgets('Studio routes by detection, shows scripts and applies', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final detector = ParagraphLanguageDetector(_FakeIdentifier());
    studioLanguageIdHost = FixedStudioLanguageIdHost(detector);
    await tester.pumpWidget(const QudsOfficeStudioApp());
    await tester.pump();
    final controller = tester
        .widget<QudsWordEditor>(find.byType(QudsWordEditor))
        .controller;
    expect(identical(controller.proofing.languageDetector, detector), isTrue);
    expect(controller.proofing.automaticLanguageDetection, isTrue);
    controller.document = WmlDocument(
      proofingLanguage: 'en-US',
      sections: [
        WmlSection(
          blocks: [
            WmlParagraph(inlines: [WmlRun(text: '$_german $_arabic')]),
          ],
        ),
      ],
    );
    controller.refresh();
    controller.caret
      ..paragraphIndex = 0
      ..logicalIndex = 2
      ..collapseSelection();
    controller.refreshView();
    await _pump(tester);

    // The settings dialog turns automatic detection off and on again.
    await tester.tap(find.byTooltip('Settings'));
    await _pump(tester);
    final setting = _key('studio-setting-detect-language');
    await tester.ensureVisible(setting);
    expect(tester.widget<SwitchListTile>(setting).value, isTrue);
    await tester.tap(setting);
    await tester.pump();
    expect(controller.proofing.automaticLanguageDetection, isFalse);
    await tester.tap(setting);
    await tester.pump();
    expect(controller.proofing.automaticLanguageDetection, isTrue);
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(TextButton, 'Close'),
      ),
    );
    await _pump(tester);

    controller.openReviewPane(tab: WordReviewPaneTab.proofing);
    controller.setTextProofingOptionsVisible(true);
    await _pump(tester);
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
    await _pump(tester);
    String text(String key) => tester.widget<Text>(_key(key)).data!;
    expect(
      text('live-proofing-text-scripts'),
      'Latin text: English · Arabic text: English',
    );
    expect(
      text('live-proofing-text-detected'),
      'Detected: Latin text: German · Arabic text: Arabic',
    );
    await tester.tap(_key('live-proofing-apply-detected'));
    await _pump(tester);
    expect(tester.takeException(), isNull);
    final runs = controller.document.paragraphs.first.inlines
        .whereType<WmlRun>()
        .toList();
    expect(
      runs
          .firstWhere((r) => r.text.contains('Bericht'))
          .properties
          .proofingLanguage,
      'de-DE',
    );
    expect(
      runs
          .firstWhere((r) => r.text.contains('التقرير'))
          .properties
          .complexScriptLanguage,
      'ar-SA',
    );
    expect(
      text('live-proofing-text-scripts'),
      'Latin text: German · Arabic text: Arabic',
    );
    controller.undo();
    await _pump(tester);
    expect(
      controller.document.paragraphs.first.inlines
          .whereType<WmlRun>()
          .single
          .properties
          .proofingLanguage,
      isNull,
    );
  });

  testWidgets('the licence page lists CLD3 (Apache-2.0) and CrispASR', (
    tester,
  ) async {
    registerStudioLicenses();
    final entries = await LicenseRegistry.licenses.toList();
    String textOf(String package) => entries
        .where((entry) => entry.packages.contains(package))
        .expand((entry) => entry.paragraphs)
        .map((paragraph) => paragraph.text)
        .join('\n');
    final model = textOf('CLD3 language detection model (Apache-2.0)');
    expect(model, contains('Copyright 2016 Google Inc.'));
    expect(model, contains('Apache License'));
    expect(
      textOf('Language identification runtime (CrispASR, MIT)'),
      contains('MIT License'),
    );
  });
}
