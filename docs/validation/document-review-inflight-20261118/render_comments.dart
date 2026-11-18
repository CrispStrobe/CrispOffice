// Run from packages/quds_office_editor/example:
// flutter test --no-pub ../../../docs/validation/document-review-inflight-20261118/render_comments.dart
// Set QUDS_REVIEW_VISUAL_OUTPUT to the screenshot directory's absolute path.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:quds_office_studio/main.dart';

const _captureKey = ValueKey<String>('comment-review-capture');

class _VisualProofing extends OfficeProofingProvider {
  @override
  String get id => 'comment-visual-fixture';

  @override
  bool supportsLanguage(String language) => true;

  @override
  Future<OfficeProofingResult> check(OfficeProofingRequest request) async =>
      OfficeProofingResult(
        request: request,
        providerId: id,
        status: OfficeProofingStatus.success,
        findings: [
          for (final match in RegExp('sentense').allMatches(request.text))
            OfficeProofingFinding.forRequest(
              request,
              providerId: id,
              ruleId: 'visual.spelling',
              start: match.start,
              end: match.end,
              message: 'Did you mean sentence?',
              category: OfficeProofingCategory.spelling,
              replacements: const ['sentence'],
            ),
        ],
      );
}

WmlParagraph _paragraph(String text) => WmlParagraph(
  properties: WmlParagraphProps(spacingAfter: 14),
  inlines: [
    WmlRun(text: text, properties: WmlRunProps(fontSizeHalfPoints: 28)),
  ],
);

WmlDocument _document() {
  final document = WmlDocument(
    proofingLanguage: 'en-US',
    sections: [
      WmlSection(
        blocks: [
          _paragraph('Project review: November update'),
          _paragraph(
            'The team will review the delivery schedule before the next planning meeting. '
            'Comments and writing suggestions stay alongside the document while we edit.',
          ),
          _paragraph(
            'Please confirm the final dates with the design team and add the agreed '
            'milestones to the project brief. Each reviewer can keep a separate reply '
            'draft for every discussion.',
          ),
        ],
      ),
    ],
  );
  document.comments.addAll([
    WmlComment(
      id: 1,
      text:
          'This sentense needs a clearer date. Can we confirm the next review meeting?',
      author: 'Maya Chen',
      initials: 'MC',
      dateIso: '2026-11-18T11:20:00Z',
    ),
    WmlComment(
      id: 2,
      text: 'Please check the milestones against the design schedule.',
      author: 'Jonas Weber',
      initials: 'JW',
      dateIso: '2026-11-18T11:35:00Z',
    ),
  ]);
  WordComment.applyRange(document.paragraphs.elementAt(1), 0, 48, 1);
  WordComment.applyRange(document.paragraphs.elementAt(2), 0, 40, 2);
  return document;
}

Future<void> _pump(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

Future<WordEditorController> _mount(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1760, 1000);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.binding.setSurfaceSize(const Size(1760, 1000));
  await tester.pumpWidget(
    const RepaintBoundary(key: _captureKey, child: QudsOfficeStudioApp()),
  );
  await _pump(tester);
  await tester.tap(find.byTooltip('English'));
  await _pump(tester);
  final controller = tester
      .widget<QudsWordEditor>(find.byType(QudsWordEditor))
      .controller;
  controller.proofing.enabled = false;
  controller.proofing.configure(
    OfficeProofingService(providers: [_VisualProofing()]),
  );
  controller.document = _document();
  controller.viewport.origin = Offset.zero;
  controller.viewport.scale = 0.65;
  controller.fitPaintMetrics(themeFamily: controller.config.theme.fontFamily);
  controller.refresh();
  controller.selectComment(1);
  controller.proofing.enabled = true;
  var complete = false;
  unawaited(
    controller.proofing.checkNow(includeManualProviders: false).then((_) {
      complete = true;
    }),
  );
  for (var i = 0; i < 30 && !complete; i++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
  expect(complete, isTrue);
  await _pump(tester);
  final first = find.byKey(const ValueKey('studio-comment-reply-1'));
  await tester.ensureVisible(first);
  await tester.enterText(
    first,
    'I will confirm the dates and update this paragraph.',
  );
  controller.selectComment(2);
  await _pump(tester);
  final second = find.byKey(const ValueKey('studio-comment-reply-2'));
  await tester.ensureVisible(second);
  await tester.enterText(
    second,
    'I will check the design milestones separately.',
  );
  controller.selectComment(1);
  await _pump(tester);
  await tester.ensureVisible(first);
  await tester.tap(first);
  await _pump(tester);
  expect(
    tester.widget<TextField>(first).controller!.text,
    'I will confirm the dates and update this paragraph.',
  );
  return controller;
}

Future<void> _capture(WidgetTester tester, String name) async {
  await tester.pump(const Duration(milliseconds: 120));
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureKey),
  );
  final picture = (await tester.runAsync(
    () => boundary.toImage(pixelRatio: 1),
  ))!;
  final bytes = (await tester.runAsync(
    () => picture.toByteData(format: ui.ImageByteFormat.png),
  ))!;
  picture.dispose();
  final destination = Directory(
    Platform.environment['QUDS_REVIEW_VISUAL_OUTPUT'] ??
        '../../../docs/validation/document-review-inflight-20261118/screenshots',
  );
  await tester.runAsync(() async {
    await destination.create(recursive: true);
    await File(
      '${destination.path}/$name.png',
    ).writeAsBytes(bytes.buffer.asUint8List());
  });
  expect(tester.takeException(), isNull);
}

Future<void> _loadFonts() async {
  await OfficeHostFonts.ensureRegistered();
  Future<void> load(String family, List<String> paths) async {
    final loader = FontLoader(family);
    for (final path in paths) {
      loader.addFont(File(path).readAsBytes().then(ByteData.sublistView));
    }
    await loader.load();
  }

  await load('Tajawal', [
    'fonts/Tajawal-Regular.ttf',
    'fonts/Tajawal-Bold.ttf',
  ]);
  await load('Cairo', ['fonts/Cairo-Regular.ttf']);
  final sdk = Platform.environment['FLUTTER_ROOT'];
  if (sdk == null) throw StateError('FLUTTER_ROOT must name the test SDK.');
  await load('MaterialIcons', [
    '$sdk/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  ]);
}

Future<void> _showSuggestions(
  WidgetTester tester,
  WordEditorController controller, {
  bool secondary = false,
}) async {
  controller.beginCommentEdit(1);
  await _pump(tester);
  final finder = find.byKey(const ValueKey('studio-comment-canvas-1'));
  await tester.ensureVisible(finder);
  await _pump(tester);
  final canvas = tester.renderObject<RenderWordCanvas>(finder);
  final line = controller.commentLaidOut!.pages
      .expand((page) => page.lines)
      .firstWhere(
        (line) =>
            line.paragraphIndex == 0 &&
            line.glyphs.any(
              (glyph) => glyph.glyph.logicalIndex <= 8 && 8 < glyph.logicalEnd,
            ),
      );
  final glyph = line.glyphs.firstWhere(
    (glyph) => glyph.glyph.logicalIndex <= 8 && 8 < glyph.logicalEnd,
  );
  final position = canvas.localToGlobal(
    canvas.windowForPagePoint(
      line.pageIndex,
      Offset(glyph.x + glyph.advance * .35, line.y + line.height * .5),
    ),
  );
  final gesture = await tester.startGesture(
    position,
    kind: PointerDeviceKind.mouse,
    buttons: secondary ? kSecondaryMouseButton : kPrimaryMouseButton,
  );
  await gesture.up();
  await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 10));
  await _pump(tester);
  expect(find.byKey(const Key('office-context-menu')), findsOneWidget);
  final menu = tester.getRect(find.byKey(const Key('office-context-menu')));
  final screen = MediaQuery.sizeOf(tester.element(finder));
  expect(menu.right, lessThanOrEqualTo(screen.width));
  expect(menu.bottom, lessThanOrEqualTo(screen.height));
  expect(menu.inflate(12).contains(position), isTrue);
  expect(find.text('sentence'), findsOneWidget);
  expect(controller.reviewPaneVisible, isFalse);
  expect(find.byType(Dialog), findsNothing);
}

void main() {
  testWidgets('render inline and context-menu comment corrections', (
    tester,
  ) async {
    await tester.runAsync(_loadFonts);
    final controller = await _mount(tester);
    await _showSuggestions(tester, controller);
    expect(
      tester
          .widget<QudsWordEditor>(find.byType(QudsWordEditor))
          .focusNode!
          .hasPrimaryFocus,
      isTrue,
    );
    expect(controller.input.isAttached, isTrue);
    await _capture(tester, 'comments-inline-suggestions-desktop');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _pump(tester);
    expect(find.byKey(const Key('office-context-menu')), findsNothing);

    await _showSuggestions(tester, controller, secondary: true);
    expect(find.text('Delete comment'), findsOneWidget);
    await _capture(tester, 'comments-context-suggestions-desktop');
    await tester.tap(find.text('Open writing pane'));
    await _pump(tester);
    expect(controller.reviewPaneVisible, isTrue);
    expect(controller.selectedProofingIssue!.story, 'Comment 1');
    await _capture(tester, 'comments-writing-desktop');
    controller.closeReviewPane();
    await _pump(tester);

    tester.view.physicalSize = const Size(900, 1000);
    await tester.binding.setSurfaceSize(const Size(900, 1000));
    await _pump(tester);
    await tester.tap(find.byTooltip('العربية'));
    await _pump(tester);
    await _showSuggestions(tester, controller);
    expect(find.text('تجاهل مرة واحدة'), findsOneWidget);
    await _capture(tester, 'comments-inline-suggestions-arabic-narrow');
    expect(controller.document.comments.first.text, contains('sentense'));
    expect(controller.canUndo, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    await tester.binding.setSurfaceSize(null);
    expect(tester.takeException(), isNull);
  });
}
