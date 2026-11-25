// Live acceptance on the real desktop/mobile embedder: pressing Enter in the
// Studio Word canvas keeps the paragraph formatting, continues the character
// formatting and renumbers a numbered list instead of repeating its label.
//
//   flutter test -d macos integration_test/word_enter_formatting_test.dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:quds_office_studio/main.dart';

void _formatParagraph(WordEditorController controller) {
  controller.applyParagraphFormat((WmlParagraphProps props) {
    props.spacingBefore = 12;
    props.spacingAfter = 18;
    props.lineSpacing = 1.5;
    props.explicitLineSpacing = true;
    props.explicitSpacingBefore = true;
    props.explicitSpacingAfter = true;
    props.indent = const WmlIndent(left: 24, firstLine: 6);
    props.explicitIndent = true;
    props.justification = WmlJustification.center;
    props.explicitJustification = true;
  });
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Enter keeps the paragraph format in the Studio canvas', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const QudsOfficeStudioApp());
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final QudsWordEditor editor = tester.widget<QudsWordEditor>(
      find.byType(QudsWordEditor),
    );
    final WordEditorController controller = editor.controller;
    controller.document = WmlDocument.empty(text: 'Alpha Beta');
    controller.refresh();
    _formatParagraph(controller);
    controller.selectAll();
    controller.applyRunFormat((WmlRunProps props) {
      props.bold = true;
      props.fontSizeHalfPoints = 36;
    });
    controller.caret
      ..logicalIndex = 10
      ..collapseSelection();
    controller.refreshView();
    editor.focusNode!.requestFocus();
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(controller.input.isAttached, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    final paragraphs = controller.document.paragraphs.toList();
    expect(paragraphs.map((WmlParagraph p) => p.text), <String>[
      'Alpha Beta',
      '',
    ]);
    final inserted = paragraphs.last.properties;
    expect(inserted.spacingBefore, 12);
    expect(inserted.spacingAfter, 18);
    expect(inserted.lineSpacing, 1.5);
    expect(inserted.indent.left, 24);
    expect(inserted.indent.firstLine, 6);
    expect(inserted.justification, WmlJustification.center);

    controller.insertText('Bold');
    final run = controller.document.paragraphs.last.inlines.single as WmlRun;
    expect(run.properties.bold, isTrue);
    expect(run.properties.fontSizeHalfPoints, 36);

    // A numbered list continues in the live canvas too.
    controller.document = WmlDocument.empty(text: 'Item one');
    controller.refresh();
    controller.toggleList(numbered: true);
    controller.caret
      ..logicalIndex = 8
      ..collapseSelection();
    controller.insertParagraphBreak();
    controller.insertText('Item two');
    expect(
      controller.document.paragraphs.map(
        (WmlParagraph p) => p.properties.listLabel,
      ),
      <String>['1. ', '2. '],
    );
  });
}
