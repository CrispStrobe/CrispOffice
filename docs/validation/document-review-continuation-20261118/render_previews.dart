// Reproducible visual fixtures for document-review continuation.
// Copy this file into packages/quds_office_editor/test/_review_previews_test.dart.
// From packages/quds_office_editor, run:
//   QUDS_REVIEW_SCREENSHOT_DIR=/absolute/output/path FLUTTER_ROOT=/sdk/path \
//     flutter test --no-pub test/_review_previews_test.dart
// These four visual cases are separate from the behavior regression count.
// The images use explicitly labelled demonstration content and deterministic
// providers; they do not claim results from an installed native model.

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

const _captureKey = ValueKey<String>('continuation-preview-capture');
Finder _key(String value) => find.byKey(ValueKey<String>(value));

class _FixtureProvider extends OfficeProofingProvider {
  _FixtureProvider({this.gate});
  final Future<void>? gate;

  @override
  String get id => 'document-review-visual-fixture';

  @override
  bool supportsLanguage(String language) => true;

  @override
  Future<OfficeProofingResult> check(OfficeProofingRequest request) async {
    if (request.text.startsWith('Later paragraphs') && gate != null) await gate;
    return OfficeProofingResult(
      request: request,
      providerId: id,
      status: OfficeProofingStatus.success,
      findings: <OfficeProofingFinding>[
        for (final match in RegExp('Feler').allMatches(request.text))
          OfficeProofingFinding.forRequest(
            request,
            providerId: id,
            ruleId: 'fixture.spelling',
            start: match.start,
            end: match.end,
            message: 'Check this spelling.',
            category: OfficeProofingCategory.spelling,
            replacements: const <String>['Fehler'],
          ),
      ],
    );
  }
}

WmlParagraph _paragraph(
  String text, {
  bool title = false,
  bool arabic = false,
}) => WmlParagraph(
  properties: WmlParagraphProps(
    rightToLeft: arabic,
    justification: arabic ? WmlJustification.right : WmlJustification.left,
    spacingAfter: title ? 18 : 12,
    lineSpacing: 1.4,
  ),
  inlines: <WmlInline>[
    WmlRun(
      text: text,
      properties: WmlRunProps(
        bold: title,
        fontSizeHalfPoints: title ? 40 : (arabic ? 26 : 24),
        asciiFont: 'Liberation Sans',
        csFont: 'Noto Naskh Arabic',
        color: title ? '17324D' : '243447',
      ),
    ),
  ],
);

WmlDocument _changesDocument({bool arabic = false, bool narrow = false}) {
  final paragraphs = <WmlParagraph>[
    _paragraph(arabic ? 'خطة التسليم' : 'Delivery plan', title: true, arabic: arabic),
    _paragraph(
      arabic
          ? 'مستند تجريبي للتحرير والمراجعة.'
          : 'A demonstration document for editing and review.',
      arabic: arabic,
    ),
    _paragraph(
      arabic
          ? 'موعد مراجعة الإطلاق هو الجمعةالاثنين.'
          : 'The launch review is scheduled for FridayMonday.',
      arabic: arabic,
    ),
    _paragraph(
      arabic
          ? 'تتضمن القائمة المحدّثة مراجعة لإمكانية الوصول.'
          : 'The revised checklist includes an accessibility pass.',
      arabic: arabic,
    ),
    _paragraph(
      arabic
          ? 'احذف الملحق القديم قبل النشر.'
          : 'Remove the obsolete appendix before publication.',
      arabic: arabic,
    ),
    _paragraph(
      arabic
          ? 'يرسل مسؤول المستند المسودة النهائية بعد الموافقة.'
          : 'The document owner will circulate the final draft after approval.',
      arabic: arabic,
    ),
  ];
  final document = WmlDocument(
    proofingLanguage: arabic ? 'ar' : 'en-US',
    sections: <WmlSection>[
      WmlSection(
        pageSize: WmlPageSize(width: narrow ? 320 : 650, height: 840),
        margins: WmlPageMargins(
          top: narrow ? 28 : 50,
          bottom: 40,
          left: narrow ? 26 : 50,
          right: narrow ? 26 : 50,
        ),
        blocks: paragraphs,
      ),
    ],
  );
  void revision(int paragraphIndex, String text, WmlRevisionKind kind, String author) {
    final paragraph = paragraphs[paragraphIndex];
    final start = paragraph.text.indexOf(text);
    WordRevisions.record(
      document,
      paragraph: paragraph,
      paragraphIndex: paragraphIndex,
      kind: kind,
      start: start,
      end: start + text.length,
      text: text,
      author: author,
    ).dateIso = '2026-11-18T10:00:00Z';
  }
  revision(2, arabic ? 'الجمعة' : 'Friday', WmlRevisionKind.delete, arabic ? 'ميرا' : 'Mira');
  revision(2, arabic ? 'الاثنين' : 'Monday', WmlRevisionKind.insert, arabic ? 'ميرا' : 'Mira');
  revision(3, arabic ? 'مراجعة لإمكانية الوصول' : 'an accessibility pass', WmlRevisionKind.insert, arabic ? 'ميرا' : 'Mira');
  revision(4, arabic ? 'القديم ' : 'obsolete ', WmlRevisionKind.delete, arabic ? 'سامر' : 'Sam');
  return document;
}

class _Harness {
  _Harness({
    required this.document,
    this.arabic = false,
    this.size = const Size(1280, 1000),
    _FixtureProvider? provider,
  }) : controller = WordEditorController(
         document: document,
         revisionAuthor: arabic ? 'ميرا' : 'Mira',
         config: OfficeSurfaceConfig(
           showRulers: false,
           textDirection: arabic ? TextDirection.rtl : TextDirection.ltr,
         ),
         proofingService: OfficeProofingService(
           providers: <OfficeProofingProvider>[provider ?? _FixtureProvider()],
         ),
       );

  final WmlDocument document;
  final bool arabic;
  final Size size;
  final WordEditorController controller;

  Future<void> mount(WidgetTester tester, WordReviewPaneTab tab) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    controller.openReviewPane(tab: tab);
    await tester.pumpWidget(
      RepaintBoundary(
        key: _captureKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF315A83)),
            fontFamily: 'Liberation Sans',
            fontFamilyFallback: const <String>['Noto Naskh Arabic'],
          ),
          home: Scaffold(
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Directionality(
                  textDirection: arabic ? TextDirection.rtl : TextDirection.ltr,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    color: const Color(0xFFEDF2F7),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          arabic ? 'عرض توضيحي لمراجعة المستند' : 'Document review demonstration',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          arabic
                              ? 'محتوى تجريبي ومدققون محددون للاختبار'
                              : 'Example content and deterministic test checkers',
                          style: const TextStyle(fontSize: 12, color: Color(0xFF526779)),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(child: QudsWordEditor(controller: controller)),
              ],
            ),
          ),
        ),
      ),
    );
    await _drain(tester);
    expect(find.byType(Dialog), findsNothing);
    expect(tester.takeException(), isNull);
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    await tester.pump();
  }
}

Future<void> _drain(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 450));
  for (var frame = 0; frame < 12; frame++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
}

Future<void> _reveal(WidgetTester tester, String key) async {
  final finder = _key(key);
  final lists = find.descendant(
    of: _key('word-review-pane'),
    matching: find.byType(ListView),
  );
  if (finder.evaluate().isEmpty) {
    tester.widget<ListView>(lists.first).controller!.jumpTo(0);
    await tester.pump();
    if (finder.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        finder,
        100,
        scrollable: find.descendant(
          of: _key('word-review-pane'),
          matching: find.byType(Scrollable),
        ).first,
      );
    }
  }
  await tester.ensureVisible(finder);
  await tester.pump();
}

Future<void> _tap(WidgetTester tester, String key) async {
  await _reveal(tester, key);
  await tester.tap(_key(key));
  await _drain(tester);
}

Future<void> _choose(WidgetTester tester, String key, String label) async {
  await _tap(tester, key);
  await tester.tap(find.text(label).last);
  await _drain(tester);
  expect(tester.takeException(), isNull);
}

Future<void> _save(WidgetTester tester, String name) async {
  final output = Platform.environment['QUDS_REVIEW_SCREENSHOT_DIR'];
  if (output == null || output.isEmpty) {
    throw StateError('Set QUDS_REVIEW_SCREENSHOT_DIR to an absolute directory.');
  }
  await tester.pump();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureKey),
  );
  final image = await tester.runAsync(() => boundary.toImage(pixelRatio: 1));
  if (image == null) throw StateError('Could not capture the review fixture.');
  try {
    final bytes = await tester.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.png),
    );
    if (bytes == null) throw StateError('Could not encode the review fixture.');
    await tester.runAsync(() async {
      await Directory(output).create(recursive: true);
      await File('$output/$name.png').writeAsBytes(bytes.buffer.asUint8List());
    });
  } finally {
    image.dispose();
  }
}

Future<void> _fonts() async {
  await OfficeHostFonts.ensureRegistered();
  final sdk = Platform.environment['FLUTTER_ROOT'];
  final configured = Platform.environment['QUDS_REVIEW_ICON_FONT'];
  final path = configured ??
      (sdk == null ? null : '$sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (path == null || !await File(path).exists()) {
    throw StateError('A genuine MaterialIcons font is required for these fixtures.');
  }
  final loader = FontLoader('MaterialIcons')
    ..addFont(File(path).readAsBytes().then(ByteData.sublistView));
  await loader.load();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_fonts);

  testWidgets('desktop change projections and filtered batches', (tester) async {
    final harness = _Harness(document: _changesDocument());
    try {
      await harness.mount(tester, WordReviewPaneTab.changes);
      await _choose(tester, 'live-review-preview-mode', 'Original text');
      await _save(tester, 'changes-original-desktop');
      await _choose(tester, 'live-review-preview-mode', 'Final text');
      await _save(tester, 'changes-final-desktop');
      await _tap(tester, 'live-review-filters');
      await _choose(tester, 'live-review-author-filter', 'Mira');
      await _choose(tester, 'live-review-kind-filter', 'Insertions');
      await _tap(tester, 'live-review-filters');
      await _reveal(tester, 'live-review-accept-shown');
      expect(
        tester.widget<Text>(_key('live-review-filter-count')).data,
        '2 of 4 pending changes',
      );
      await _save(tester, 'changes-filtered-desktop');
      expect(harness.document.revisions, hasLength(4));
      expect(harness.controller.canUndo, isFalse);
    } finally {
      await harness.close(tester);
    }
  });

  testWidgets('progressive writing retains actionable findings', (tester) async {
    final gate = Completer<void>();
    final document = WmlDocument(
      proofingLanguage: 'de-DE',
      sections: <WmlSection>[
        WmlSection(
          pageSize: const WmlPageSize(width: 650, height: 840),
          margins: const WmlPageMargins(top: 50, bottom: 40, left: 50, right: 50),
          blocks: <WmlBlock>[
            _paragraph('Writing while checks continue', title: true),
            _paragraph('A Feler remains visible while later paragraphs are checked.'),
            _paragraph('Later paragraphs are being checked in the background.'),
            _paragraph('You can keep editing or choose a correction in the Writing pane.'),
          ],
        ),
      ],
    );
    final harness = _Harness(document: document, provider: _FixtureProvider(gate: gate.future));
    try {
      await harness.mount(tester, WordReviewPaneTab.proofing);
      expect(harness.controller.proofing.checking, isTrue);
      await _reveal(tester, 'live-proofing-replace-0');
      expect(
        tester.widget<OutlinedButton>(_key('live-proofing-replace-0')).onPressed,
        isNotNull,
      );
      await _save(tester, 'writing-in-flight-desktop');
      gate.complete();
      await _drain(tester);
    } finally {
      if (!gate.isCompleted) gate.complete();
      await harness.close(tester);
    }
  });

  for (final arabic in <bool>[false, true]) {
    testWidgets('narrow ${arabic ? 'Arabic' : 'English'} changes preview', (tester) async {
      final harness = _Harness(
        document: _changesDocument(arabic: arabic, narrow: true),
        arabic: arabic,
        size: const Size(360, 760),
      );
      try {
        await harness.mount(tester, WordReviewPaneTab.changes);
        await _choose(
          tester,
          'live-review-preview-mode',
          arabic ? 'النص النهائي' : 'Final text',
        );
        await _reveal(tester, 'live-review-preview-text');
        final canvas = tester.getRect(find.byType(WordCanvas));
        final pane = tester.getRect(_key('word-review-pane'));
        expect(canvas.height, greaterThan(150));
        expect(pane.top, greaterThanOrEqualTo(canvas.bottom));
        expect(tester.takeException(), isNull);
        await _save(
          tester,
          arabic ? 'changes-arabic-narrow' : 'changes-english-narrow',
        );
      } finally {
        await harness.close(tester);
      }
    });
  }
}
