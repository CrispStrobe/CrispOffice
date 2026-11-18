// Run from packages/quds_office_editor/example:
// flutter test --no-pub ../../../docs/validation/document-review-keyboard-comments-20261118/render_comments.dart
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
        '../../../docs/validation/document-review-keyboard-comments-20261118/screenshots',
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

void main() {
  testWidgets('render Studio comment drafts and writing review', (
    tester,
  ) async {
    await tester.runAsync(_loadFonts);
    final controller = await _mount(tester);
    await _capture(tester, 'comments-drafts-desktop');
    final comment = controller.document.comments.first;
    final canvas = tester.widget<WordCanvas>(
      find.byKey(const ValueKey('studio-comment-canvas-1')),
    );
    canvas.onReviewTap!(
      OfficeContextHit(
        kind: OfficeContextKind.comment,
        globalPosition: Offset.zero,
        commentId: 1,
        paragraph: comment.paragraphs.single,
        proofingOffset: 8,
      ),
    );
    await tester.pump(kDoubleTapTimeout);
    await _pump(tester);
    expect(controller.reviewPaneVisible, isTrue);
    await _capture(tester, 'comments-writing-desktop');
    controller.closeReviewPane();
    await tester.binding.setSurfaceSize(const Size(900, 1000));
    await _pump(tester);
    final reply = find.byKey(const ValueKey('studio-comment-reply-action-1'));
    await tester.ensureVisible(reply);
    await tester.tap(reply);
    await _pump(tester);
    final commentScroll = find
        .descendant(
          of: find.byKey(const ValueKey('studio-comments-pane')),
          matching: find.byType(Scrollable),
        )
        .first;
    tester.state<ScrollableState>(commentScroll).position.jumpTo(0);
    await _pump(tester);
    await _capture(tester, 'comments-drafts-english-narrow');
    await tester.tap(find.byTooltip('العربية'));
    await _pump(tester);
    await tester.ensureVisible(reply);
    await tester.tap(reply);
    await _pump(tester);
    tester.state<ScrollableState>(commentScroll).position.jumpTo(0);
    await _pump(tester);
    await _capture(tester, 'comments-drafts-arabic-narrow');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.binding.setSurfaceSize(null);
  });
}
