import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:quds_office_studio/main.dart';
import 'package:quds_office_studio/studio_chrome.dart';

final class _ReviewProbe extends OfficeProofingProvider {
  _ReviewProbe(this.id);

  @override
  final String id;
  int calls = 0;

  @override
  bool supportsLanguage(String language) => true;

  @override
  Future<OfficeProofingResult> check(OfficeProofingRequest request) async {
    calls++;
    return OfficeProofingResult(
      request: request,
      providerId: id,
      status: OfficeProofingStatus.success,
    );
  }
}

Future<WordEditorController> _studio(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1440, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(const QudsOfficeStudioApp());
  await tester.pump();
  expect(find.byTooltip('Language'), findsOneWidget);
  await tester.pump();
  final controller = tester
      .widget<QudsWordEditor>(find.byType(QudsWordEditor))
      .controller;
  controller.document = WmlDocument.empty(text: 'Ein Beispiel.')
    ..proofingLanguage = 'de-DE';
  controller.refresh();
  await tester.pump();
  return controller;
}

Finder _command(String label) => find.byWidgetPredicate(
  (widget) => widget is StudioCmd && widget.label == label,
);

Future<void> _review(WidgetTester tester) async {
  await tester.tap(find.text('Review').first);
  await tester.pump();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    final ribbon = find.descendant(
      of: find.byType(StudioRibbonStrip),
      matching: find.byType(Scrollable),
    );
    tester.state<ScrollableState>(ribbon).position.jumpTo(0);
    await tester.pump();
    if (finder.evaluate().isEmpty) {
      await tester.scrollUntilVisible(finder, 240, scrollable: ribbon);
    }
  }
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pump();
}

Future<void> _finishCheck(
  WidgetTester tester,
  WordEditorController controller,
) async {
  for (var tick = 0; tick < 20 && controller.proofing.checking; tick++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
  expect(controller.proofing.checking, isFalse);
}

void main() {
  testWidgets(
    'F7 opens live review and only explicit checks run manual grammar',
    (tester) async {
      final controller = await _studio(tester);
      final ordinary = _ReviewProbe('ordinary');
      final manual = _ReviewProbe('manual');
      controller.proofing.configure(
        OfficeProofingService(providers: [ordinary]),
      );
      controller.proofing.configureManual(
        OfficeProofingService(providers: [manual]),
      );
      expect(controller.proofing.enabled, isTrue);
      await tester.pump(const Duration(milliseconds: 450));
      await _finishCheck(tester, controller);
      expect(ordinary.calls, greaterThan(0));
      expect(manual.calls, 0);

      final editor = tester.widget<QudsWordEditor>(find.byType(QudsWordEditor));
      editor.focusNode!.requestFocus();
      await tester.pump();
      final barriers = find.byType(ModalBarrier).evaluate().length;
      await tester.sendKeyEvent(LogicalKeyboardKey.f7);
      await tester.pump();
      await _finishCheck(tester, controller);
      expect(controller.reviewPaneVisible, isTrue);
      expect(controller.reviewPaneTab, WordReviewPaneTab.proofing);
      expect(find.byKey(const ValueKey('word-review-pane')), findsOneWidget);
      expect(manual.calls, 1);
      expect(find.byType(Dialog), findsNothing);
      expect(find.byType(ModalBarrier), findsNWidgets(barriers));

      // Zooming changes only the viewport, so reviewed results remain current.
      final checked = controller.proofing.summary;
      expect(checked.hasResults, isTrue);
      final scale = controller.viewport.scale;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.equal);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(controller.viewport.scale, greaterThan(scale));
      expect(controller.proofing.summary, same(checked));

      final before = controller.document.paragraphs.single.text;
      controller.insertText('Neu ');
      await tester.pump(const Duration(milliseconds: 450));
      await _finishCheck(tester, controller);
      expect(controller.document.paragraphs.single.text, isNot(before));
      expect(controller.reviewPaneVisible, isTrue);
      expect(manual.calls, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'typing check preference survives switching Studio applications',
    (tester) async {
      final controller = await _studio(tester);
      controller.proofing.configure(OfficeProofingService(providers: []));
      await _review(tester);
      final checkAsYouType = _command('Check as you type');
      expect(tester.widget<StudioCmd>(checkAsYouType).selected, isTrue);
      await _tap(tester, checkAsYouType);
      expect(controller.proofing.enabled, isFalse);
      await tester.pump();
      expect(tester.widget<StudioCmd>(checkAsYouType).selected, isFalse);

      await tester.tap(find.text('Spreadsheets').first);
      await tester.pump();
      await tester.tap(find.text('Documents').first);
      await tester.pump();
      expect(controller.proofing.enabled, isFalse);
      await _review(tester);
      expect(tester.widget<StudioCmd>(checkAsYouType).selected, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('review commands remain nonmodal and read-only in viewing mode', (
    tester,
  ) async {
    final controller = await _studio(tester);
    controller.proofing.configure(OfficeProofingService(providers: []));
    await tester.tap(find.text('File').first);
    await tester.pump();
    await _tap(tester, _command('View'));
    await _review(tester);
    final document = controller.document;
    final text = document.paragraphs.single.text;
    final language = document.proofingLanguage;
    final modified = document.properties.modifiedIso;
    final before = controller.contentRevision;

    await _tap(tester, _command('Review changes'));
    expect(controller.reviewPaneVisible, isTrue);
    expect(controller.reviewPaneTab, WordReviewPaneTab.changes);
    expect(find.byKey(const ValueKey('word-review-pane')), findsOneWidget);
    await tester.pump();
    expect(
      tester.widget<StudioCmd>(_command('Review changes')).selected,
      isTrue,
    );
    expect(find.byType(Dialog), findsNothing);
    expect(tester.widget<StudioCmd>(_command('Track')).onPressed, isNull);
    expect(tester.widget<StudioCmd>(_command('Restrict')).onPressed, isNull);

    await _tap(tester, _command('Spelling'));
    await _finishCheck(tester, controller);
    expect(controller.reviewPaneTab, WordReviewPaneTab.proofing);
    expect(find.byType(Dialog), findsNothing);
    expect(controller.contentRevision, before);
    expect(controller.document, same(document));
    expect(document.paragraphs.single.text, text);
    expect(document.proofingLanguage, language);
    expect(document.properties.modifiedIso, modified);
    expect(document.revisions, isEmpty);
    expect(document.trackRevisions, isFalse);
    expect(document.restrictEditing, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });
}
