// Run from packages/quds_office_editor/example:
// flutter test --no-pub ../../../docs/validation/document-review-drafts-20261118/render_comments.dart
// Set QUDS_REVIEW_VISUAL_OUTPUT to an output directory outside the checkout.
// These deterministic visual providers exercise the actual Studio surfaces.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:quds_office_studio/main.dart';

const _captureKey = ValueKey<String>('comment-draft-review-capture');

class _VisualProofing extends OfficeProofingProvider {
  @override
  String get id => 'comment-draft-visual-fixture';

  @override
  bool supportsLanguage(String language) => true;

  @override
  Future<OfficeProofingResult> check(OfficeProofingRequest request) async =>
      OfficeProofingResult(
        request: request,
        providerId: id,
        status: OfficeProofingStatus.success,
        findings: [
          for (final entry in const [
            (
              'sentense',
              'sentence',
              'Did you mean sentence?',
              OfficeProofingCategory.spelling,
            ),
            (
              'very very',
              'very',
              'Consider removing the repeated word.',
              OfficeProofingCategory.style,
            ),
            (
              'موعددد',
              'موعد',
              'هل تقصد موعد؟',
              OfficeProofingCategory.spelling,
            ),
            (
              'جدا جدا',
              'جدا',
              'يمكن حذف الكلمة المكررة.',
              OfficeProofingCategory.style,
            ),
          ])
            for (final match in RegExp(entry.$1).allMatches(request.text))
              OfficeProofingFinding.forRequest(
                request,
                providerId: id,
                ruleId: 'visual.${entry.$4.name}',
                start: match.start,
                end: match.end,
                message: entry.$3,
                category: entry.$4,
                replacements: [entry.$2],
              ),
        ],
      );
}

WmlParagraph _paragraph(String text, {bool arabic = false}) => WmlParagraph(
  properties: WmlParagraphProps(
    spacingAfter: 14,
    rightToLeft: arabic,
    justification: arabic ? WmlJustification.right : WmlJustification.left,
  ),
  inlines: [
    WmlRun(text: text, properties: WmlRunProps(fontSizeHalfPoints: 28)),
  ],
);

WmlDocument _document({bool arabic = false}) {
  final document = WmlDocument(
    proofingLanguage: arabic ? 'ar' : 'en-US',
    sections: [
      WmlSection(
        blocks: [
          _paragraph(
            arabic
                ? 'مراجعة المشروع: تحديث نوفمبر'
                : 'Project review: November update',
            arabic: arabic,
          ),
          _paragraph(
            arabic
                ? 'سنراجع جدول التسليم قبل اجتماع التخطيط القادم. تبقى التعليقات '
                      'واقتراحات الكتابة بجوار المستند أثناء التحرير.'
                : 'The team will review the delivery schedule before the next planning '
                      'meeting. Comments and writing suggestions stay alongside the '
                      'document while we edit.',
            arabic: arabic,
          ),
          _paragraph(
            arabic
                ? 'يرجى تأكيد المواعيد النهائية مع فريق التصميم وإضافة الخطوات '
                      'المتفق عليها إلى ملخص المشروع. تبقى مسودة كل رد خاصة حتى نشرها.'
                : 'Please confirm the final dates with the design team and add the '
                      'agreed milestones to the project brief. Each reply stays a '
                      'draft until its reviewer chooses to post it.',
            arabic: arabic,
          ),
        ],
      ),
    ],
  );
  document.comments.addAll([
    WmlComment(
      id: 1,
      text: arabic
          ? 'هل يمكن تأكيد موعد الاجتماع القادم قبل إرسال ملخص المشروع؟'
          : 'This sentense needs a clearer date. Can we confirm the next review meeting?',
      author: arabic ? 'مريم حسن' : 'Maya Chen',
      initials: arabic ? 'مح' : 'MC',
      dateIso: '2026-11-18T11:20:00Z',
    ),
    WmlComment(
      id: 2,
      text: arabic
          ? 'يرجى مراجعة الخطوات مع فريق التصميم.'
          : 'Please check the milestones against the design schedule.',
      author: arabic ? 'ليلى منصور' : 'Jonas Weber',
      initials: arabic ? 'لم' : 'JW',
      dateIso: '2026-11-18T11:35:00Z',
    ),
  ]);
  WordComment.applyRange(document.paragraphs.elementAt(1), 0, 36, 1);
  WordComment.applyRange(document.paragraphs.elementAt(2), 0, 34, 2);
  return document;
}

Future<void> _pump(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

Finder get _reply => find.byKey(const Key('studio-comment-reply-1'));
Finder get _suggestion =>
    find.byKey(const Key('studio-comment-draft-replace-1-0'));
Finder get _menu => find.byKey(const Key('office-context-menu'));

QudsWordEditor _editor(WidgetTester tester) =>
    tester.widget<QudsWordEditor>(find.byType(QudsWordEditor));

Future<WordEditorController> _mount(
  WidgetTester tester, {
  bool arabic = false,
  Size size = const Size(1440, 1000),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.binding.setSurfaceSize(size);
  await tester.pumpWidget(
    const RepaintBoundary(key: _captureKey, child: QudsOfficeStudioApp()),
  );
  await _pump(tester);
  if (!arabic) {
    await tester.tap(find.byTooltip('English'));
    await _pump(tester);
  }
  final controller = _editor(tester).controller;
  controller.proofing.enabled = false;
  controller.proofing.configure(
    OfficeProofingService(providers: [_VisualProofing()]),
  );
  controller.document = _document(arabic: arabic);
  controller.viewport.origin = Offset.zero;
  controller.viewport.scale = 0.7;
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
  for (var i = 0; i < 50 && !complete; i++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
  expect(complete, isTrue);
  await _pump(tester);
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
  final size = Size(picture.width.toDouble(), picture.height.toDouble());
  picture.dispose();
  final destination = Directory(
    Platform.environment['QUDS_REVIEW_VISUAL_OUTPUT'] ??
        '../../../docs/validation/document-review-drafts-20261118/screenshots',
  );
  await tester.runAsync(() async {
    await destination.create(recursive: true);
    await File(
      '${destination.path}/$name.png',
    ).writeAsBytes(bytes.buffer.asUint8List());
  });
  debugPrint('QUDS_VISUAL $name ${size.width.toInt()}x${size.height.toInt()}');
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

Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
  expect(tester.takeException(), isNull);
}

void main() {
  for (final arabic in [false, true]) {
    testWidgets(
      arabic
          ? 'render Arabic narrow draft checks beside reply text'
          : 'render desktop draft checks and an unposted correction',
      (tester) async {
        await tester.runAsync(_loadFonts);
        final controller = await _mount(
          tester,
          arabic: arabic,
          size: arabic ? const Size(780, 1000) : const Size(1440, 1000),
        );
        final revision = controller.contentRevision;
        final comments = controller.document.comments.length;
        final text = arabic
            ? 'سأؤكد موعددد الاجتماع وأضيف التفاصيل. سيكون الملخص واضحا جدا جدا.'
            : 'I will clarify this sentense and confirm the date. We can be very very specific.';
        await tester.ensureVisible(_reply);
        await tester.enterText(_reply, text);
        await _pump(tester);
        expect(_suggestion, findsNothing);
        await tester.pump(const Duration(milliseconds: 401));
        for (var index = 0; index < 12; index++) {
          await tester.pump(const Duration(milliseconds: 1));
        }
        expect(_suggestion, findsOneWidget);
        await tester.ensureVisible(_suggestion);
        await _pump(tester);
        final field = tester.widget<TextField>(_reply);
        final span = field.controller!.buildTextSpan(
          context: tester.element(_reply),
          style: field.style,
          withComposing: true,
        );
        final marked = span.children!.whereType<TextSpan>().where(
          (span) => span.style?.decorationStyle == TextDecorationStyle.wavy,
        );
        expect(marked, hasLength(2));
        expect(
          find.text(arabic ? '2 اقتراحات في الرد.' : '2 suggestions in reply.'),
          findsOneWidget,
        );
        expect(controller.document.comments.length, comments);
        expect(controller.contentRevision, revision);
        expect(controller.canUndo, isFalse);
        expect(find.byType(Dialog), findsNothing);
        if (arabic) {
          expect(Directionality.of(tester.element(_reply)), TextDirection.rtl);
        }
        await _capture(
          tester,
          arabic ? 'comment-draft-arabic-narrow' : 'comment-draft-desktop',
        );
        await tester.tap(_suggestion);
        await _pump(tester);
        expect(
          field.controller!.text,
          text.replaceFirst(
            arabic ? 'موعددد' : 'sentense',
            arabic ? 'موعد' : 'sentence',
          ),
        );
        expect(field.focusNode!.hasFocus, isTrue);
        expect(controller.document.comments.length, comments);
        expect(controller.contentRevision, revision);
        expect(controller.canUndo, isFalse);
        await _close(tester);
      },
    );
  }

  testWidgets('render keyboard correction menu at the comment caret', (
    tester,
  ) async {
    await tester.runAsync(_loadFonts);
    final controller = await _mount(tester);
    controller.beginCommentEdit(1);
    controller.commentCaret
      ..logicalIndex = 8
      ..collapseSelection();
    controller.refreshView();
    _editor(tester).focusNode!.requestFocus();
    await _pump(tester);
    final canvas = find.byKey(const Key('studio-comment-canvas-1'));
    await tester.ensureVisible(canvas);
    await _pump(tester);
    final revision = controller.contentRevision;
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.f10);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await _pump(tester);
    expect(_menu, findsOneWidget);
    expect(find.text('Did you mean sentence?'), findsOneWidget);
    expect(find.text('sentence'), findsOneWidget);
    expect(find.text('Delete comment'), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    final rect = tester.getRect(_menu);
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(1440));
    expect(rect.bottom, lessThanOrEqualTo(1000));
    expect(controller.contentRevision, revision);
    expect(controller.canUndo, isFalse);
    await _capture(tester, 'comment-keyboard-menu-desktop');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await _pump(tester);
    expect(_menu, findsNothing);
    expect(
      controller.document.comments.first.text,
      startsWith('This sentence'),
    );
    expect(_editor(tester).focusNode!.hasPrimaryFocus, isTrue);
    controller.undo();
    await _pump(tester);
    expect(
      controller.document.comments.first.text,
      startsWith('This sentense'),
    );
    expect(controller.canUndo, isFalse);
    await _close(tester);
  });
}
