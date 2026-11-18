// Run from packages/quds_office_editor with the pinned runtime environment:
// QUDS_REVIEW_VISUAL_OUTPUT=<absolute directory> flutter test --no-pub \
//   ../../docs/validation/document-review-inflight-20261118/render_text_options.dart
// Visual fixture cases are reported separately from regression tests.
// The fixture deliberately uses the editor package's dependencies when invoked
// from that package, while remaining beside its recorded visual evidence.
// ignore_for_file: depend_on_referenced_packages
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

const _captureKey = ValueKey<String>('text-proofing-capture');

final class _Provider extends OfficeProofingProvider {
  @override
  String get id => 'text-proofing-visual-fixture';

  @override
  bool supportsLanguage(String language) => true;

  @override
  Future<OfficeProofingResult> check(OfficeProofingRequest request) async =>
      OfficeProofingResult(
        request: request,
        providerId: id,
        status: OfficeProofingStatus.success,
        findings: [
          for (final token in const {
            'Feler': 'Fehler',
            'schedual': 'schedule',
          }.entries)
            for (final match in RegExp(token.key).allMatches(request.text))
              OfficeProofingFinding.forRequest(
                request,
                providerId: id,
                ruleId: 'visual.spelling',
                start: match.start,
                end: match.end,
                message: 'Check this spelling.',
                category: OfficeProofingCategory.spelling,
                replacements: [token.value],
              ),
        ],
      );
}

WmlRun _run(String text, {String? language, bool title = false}) => WmlRun(
  text: text,
  properties: WmlRunProps(
    asciiFont: 'Liberation Sans',
    fontSizeHalfPoints: title ? 38 : 25,
    bold: title,
    color: title ? '17324D' : '243447',
    proofingLanguage: language,
  ),
);

WmlParagraph _paragraph(List<WmlInline> inlines) => WmlParagraph(
  properties: WmlParagraphProps(spacingAfter: 18, lineSpacing: 1.4),
  inlines: inlines,
);

WmlDocument _document() => WmlDocument(
  proofingLanguage: 'de-DE',
  sections: [
    WmlSection(
      pageSize: const WmlPageSize(width: 520, height: 680),
      margins: const WmlPageMargins(top: 48, bottom: 48, left: 46, right: 46),
      blocks: [
        _paragraph([_run('Multilingual document review', title: true)]),
        _paragraph([
          _run('Bitte den Feler prüfen. ', language: 'de-DE'),
          _run('Confirm the schedual before Friday.', language: 'en-US'),
        ]),
        _paragraph([
          _run(
            'Set a language for a quotation, or exclude a code sample from '
            'writing checks. The document remains editable while these '
            'controls stay open.',
            language: 'en-US',
          ),
        ]),
        _paragraph([
          _run(
            'Text settings follow the selection. Each change is one Undo '
            'step, including selections across paragraphs.',
            language: 'en-US',
          ),
        ]),
      ],
    ),
  ],
);

Future<void> _frames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 450));
  for (var i = 0; i < 15; i++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
}

Future<void> _fonts() async {
  await OfficeHostFonts.ensureRegistered();
  final sdk = Platform.environment['FLUTTER_ROOT'];
  if (sdk == null) throw StateError('FLUTTER_ROOT must name the pinned SDK.');
  await (FontLoader('MaterialIcons')..addFont(
        File(
          '$sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
        ).readAsBytes().then(ByteData.sublistView),
      ))
      .load();
}

String get _output => Platform.environment['QUDS_REVIEW_VISUAL_OUTPUT']!;

Future<void> _save(WidgetTester tester, String name) async {
  await tester.pump();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureKey),
  );
  final image = (await tester.runAsync(() => boundary.toImage(pixelRatio: 1)))!;
  try {
    final data = (await tester.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.png),
    ))!;
    await tester.runAsync(() async {
      await Directory(_output).create(recursive: true);
      await File('$_output/$name.png').writeAsBytes(data.buffer.asUint8List());
    });
  } finally {
    image.dispose();
  }
  expect(tester.takeException(), isNull);
}

Future<WordEditorController> _mount(
  WidgetTester tester, {
  bool arabic = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = arabic
      ? const Size(650, 1000)
      : const Size(1280, 960);
  final controller = WordEditorController(
    document: _document(),
    config: OfficeSurfaceConfig(
      showRulers: false,
      textDirection: arabic ? TextDirection.rtl : TextDirection.ltr,
    ),
    proofingService: OfficeProofingService(providers: [_Provider()]),
  );
  if (arabic) controller.viewport.scale = .78;
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    await tester.pump(const Duration(milliseconds: 1));
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    RepaintBoundary(
      key: _captureKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          fontFamily: 'Liberation Sans',
          fontFamilyFallback: const ['Noto Naskh Arabic'],
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF315A83)),
        ),
        home: Scaffold(body: QudsWordEditor(controller: controller)),
      ),
    ),
  );
  await _frames(tester);
  return controller;
}

Future<void> _showOptions(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('word-review-language-status')));
  await _frames(tester);
  expect(
    find.byKey(const ValueKey('live-proofing-text-language')).hitTestable(),
    findsOneWidget,
  );
  expect(find.byType(Dialog), findsNothing);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_fonts);

  testWidgets(
    'capture mixed text languages and an explicit checking exclusion',
    (tester) async {
      final controller = await _mount(tester);
      final paragraph = controller.document.paragraphs.elementAt(1);
      controller.caret
        ..paragraphIndex = 1
        ..selectionAnchorParagraph = 1
        ..selectionAnchor = 0
        ..logicalIndex = paragraph.text.length;
      controller.refreshView();
      await _showOptions(tester);
      expect(controller.textProofingTarget!.language, isNull);
      expect(controller.proofing.summary.issues, hasLength(2));
      await _save(tester, 'text-proofing-mixed-desktop');

      final start = paragraph.text.indexOf('Feler');
      controller.caret
        ..selectionAnchor = start
        ..logicalIndex = start + 'Feler'.length;
      controller.refreshView();
      await _frames(tester);
      final toggle = find.byKey(const ValueKey('live-proofing-text-enabled'));
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await _frames(tester);
      expect(controller.textProofingTarget!.checkingEnabled, isFalse);
      expect(controller.proofing.summary.issues, hasLength(1));
      expect(controller.canUndo, isTrue);
      await _save(tester, 'text-proofing-excluded-desktop');
    },
  );

  testWidgets('capture language controls below a narrow RTL document', (
    tester,
  ) async {
    final controller = await _mount(tester, arabic: true);
    controller.caret
      ..paragraphIndex = 1
      ..selectionAnchorParagraph = 1
      ..selectionAnchor = 0
      ..logicalIndex = 23;
    controller.refreshView();
    await _showOptions(tester);
    expect(controller.canUndo, isFalse);
    await _save(tester, 'text-proofing-arabic-narrow');
  });
}
