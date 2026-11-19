import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:quds_office_studio/studio_page_layout_dialog.dart';
import 'package:quds_office_studio/studio_strings.dart';

Finder _key(String id) => find.byKey(ValueKey('page-layout-$id'));

Future<void> _frames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump();
}

Future<WordEditorController> _open(
  WidgetTester tester, {
  StudioLanguage language = StudioLanguage.en,
  Size size = const Size(1200, 900),
  double textScale = 1,
  WmlDocument? document,
  void Function(WordEditorController controller)? beforeOpen,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final controller = WordEditorController(
    document: document ?? WmlDocument.empty(text: 'Keep the document.'),
    config: const OfficeSurfaceConfig(autofocus: false),
  );
  beforeOpen?.call(controller);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await _frames(tester);
    controller.dispose();
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(fontFamily: 'Liberation Sans'),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: FilledButton(
            onPressed: () => showStudioPageLayoutDialog(
              context: context,
              controller: controller,
              language: language,
              unit: OfficeLengthUnit.millimeters,
            ),
            child: const Text('Open Page Layout'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open Page Layout'));
  await _frames(tester);
  expect(
    find.byKey(const ValueKey('studio-page-layout-dialog')),
    findsOneWidget,
  );
  return controller;
}

Future<void> _tab(WidgetTester tester, String id) async {
  await tester.ensureVisible(_key('tab-$id'));
  await tester.tap(_key('tab-$id'));
  await _frames(tester);
}

Future<void> _pick(WidgetTester tester, String id, String label) async {
  await tester.ensureVisible(_key(id));
  await tester.tap(_key(id));
  await _frames(tester);
  await tester.ensureVisible(find.text(label).last);
  await tester.tap(find.text(label).last);
  await _frames(tester);
}

Future<void> _type(WidgetTester tester, String id, String value) async {
  await tester.ensureVisible(_key(id));
  await tester.enterText(_key(id), value);
  await _frames(tester);
}

Future<void> _check(WidgetTester tester, String id) async {
  await tester.ensureVisible(_key(id));
  await tester.tap(_key(id));
  await _frames(tester);
}

void main() {
  testWidgets('Page Layout captures after recording pending note typing', (
    tester,
  ) async {
    late WmlNote note;
    final controller = await _open(
      tester,
      beforeOpen: (controller) {
        controller.insertFootnote(text: 'Original note');
        note = controller.document.footnotes.single;
        controller.commands.clear();
        controller.markClean();
        controller.setNoteText(note, 'Edited note');
        expect(controller.canUndo, isFalse);
        expect(controller.isDirty, isTrue);
      },
    );
    expect(controller.canUndo, isTrue);
    await _type(tester, 'left', '20 mm');
    await tester.tap(_key('apply'));
    await _frames(tester);
    expect(
      find.byKey(const ValueKey('studio-page-layout-dialog')),
      findsNothing,
    );
    expect(controller.pageMargins.left, closeTo(72 * 20 / 25.4, 0.000001));
    controller.undo();
    expect(controller.pageMargins.left, 72);
    expect(note.text, 'Edited note');
    controller.undo();
    expect(note.text, 'Original note');
    expect(controller.canUndo, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Cancel discards the complete Page Layout draft', (tester) async {
    final controller = await _open(tester);
    final before = controller.capturePageLayout();
    await _type(tester, 'left', '2,5 cm');
    await _tab(tester, 'paper');
    await _pick(tester, 'paper-preset', 'Letter');
    await _pick(tester, 'orientation', 'Landscape');
    await _tab(tester, 'columns');
    await _pick(tester, 'columns', '3');
    await tester.tap(_key('cancel'));
    await _frames(tester);
    expect(
      find.byKey(const ValueKey('studio-page-layout-dialog')),
      findsNothing,
    );
    expect(controller.isPageLayoutTargetCurrent(before), isTrue);
    expect(controller.isDirty, isFalse);
    expect(controller.canUndo, isFalse);
    expect(controller.document.paragraphs.single.text, 'Keep the document.');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'precise numeric settings apply together and Undo restores all tabs',
    (tester) async {
      final controller = await _open(tester);
      final before = controller.capturePageLayout();
      await _type(tester, 'left', '2,5 cm');
      await _type(tester, 'top', '12.7 mm');
      await _tab(tester, 'paper');
      await _type(tester, 'width', '700 pt');
      await _type(tester, 'height', '900 pt');
      await _tab(tester, 'layout');
      await _type(tester, 'header', '0.25 in');
      await _type(tester, 'footer', '12 pt');
      await _check(tester, 'first-page');
      await _check(tester, 'odd-even');
      await _check(tester, 'line-numbers');
      await _tab(tester, 'columns');
      await _pick(tester, 'columns', '2');
      await _type(tester, 'gap', '6 mm');
      await _check(tester, 'column-separator');
      await tester.tap(_key('apply'));
      await _frames(tester);

      final section = controller.document.sections.single;
      expect(section.pageSize.width, 700);
      expect(section.pageSize.height, 900);
      expect(section.margins.left, closeTo(72 * 2.5 / 2.54, 0.000001));
      expect(section.margins.top, closeTo(36, 0.000001));
      expect(section.margins.header, 18);
      expect(section.margins.footer, 12);
      expect(section.columnCount, 2);
      expect(section.columnSpace, closeTo(72 * 6 / 25.4, 0.000001));
      expect(section.columnSep, isTrue);
      expect(section.differentFirstPage, isTrue);
      expect(section.differentOddEven, isTrue);
      expect(section.lineNumbers, isTrue);
      expect(controller.contentRevision, before.contentRevision + 1);
      controller.undo();
      expect(
        WordPageLayoutSettings.fromSection(section).matches(before.settings),
        isTrue,
      );
      expect(controller.canUndo, isFalse);
      controller.redo();
      expect(section.pageSize.width, 700);
      expect(section.columnCount, 2);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('unit changes and unchanged Apply preserve original precision', (
    tester,
  ) async {
    final document = WmlDocument.empty(text: 'Precise');
    document.sections.single.margins = const WmlPageMargins(
      left: 71.123456789,
      header: 31.987654321,
    );
    final controller = await _open(tester, document: document);
    await _pick(tester, 'unit', 'Centimetres (cm)');
    await _pick(tester, 'unit', 'Inches (in)');
    await _pick(tester, 'unit', 'Millimetres (mm)');
    await tester.tap(_key('apply'));
    await _frames(tester);
    expect(controller.pageMargins.left, 71.123456789);
    expect(controller.pageMargins.header, 31.987654321);
    expect(controller.isDirty, isFalse);
    expect(controller.canUndo, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'whole-document scope applies values without replacing section starts',
    (tester) async {
      final first = WmlSection(
        blocks: <WmlBlock>[
          WmlParagraph(inlines: <WmlInline>[WmlRun(text: 'First')]),
        ],
      );
      final second = WmlSection(
        breakKind: WmlSectionBreakKind.oddPage,
        blocks: <WmlBlock>[
          WmlParagraph(inlines: <WmlInline>[WmlRun(text: 'Second')]),
        ],
      );
      final controller = await _open(
        tester,
        document: WmlDocument(sections: <WmlSection>[first, second]),
      );
      await _type(tester, 'left', '20 mm');
      await _pick(tester, 'scope', 'Whole document');
      await _tab(tester, 'layout');
      final sectionStart = find.descendant(
        of: _key('section-start'),
        matching: find.byType(DropdownButton<WmlSectionBreakKind>),
      );
      expect(
        tester
            .widget<DropdownButton<WmlSectionBreakKind>>(sectionStart)
            .onChanged,
        isNull,
      );
      await tester.tap(_key('apply'));
      await _frames(tester);
      expect(first.margins.left, closeTo(72 * 20 / 25.4, 0.000001));
      expect(second.margins.left, first.margins.left);
      expect(second.breakKind, WmlSectionBreakKind.oddPage);
      controller.undo();
      expect(first.margins.left, 72);
      expect(second.margins.left, 72);
      expect(controller.canUndo, isFalse);
    },
  );

  testWidgets(
    'invalid measurements stay in the dialog and leave the document intact',
    (tester) async {
      final controller = await _open(tester);
      final before = controller.capturePageLayout();
      await _type(tester, 'left', '1000');
      await tester.tap(_key('apply'));
      await _frames(tester);
      expect(_key('validation'), findsOneWidget);
      expect(find.textContaining('Reduce the margins'), findsOneWidget);
      expect(controller.isPageLayoutTargetCurrent(before), isTrue);
      expect(controller.isDirty, isFalse);
      await _type(tester, 'left', 'not a number');
      await tester.tap(_key('apply'));
      await _frames(tester);
      expect(find.textContaining('Check the measurements'), findsOneWidget);
      expect(controller.canUndo, isFalse);
      await _type(tester, 'left', '20 mm');
      await tester.tap(_key('apply'));
      await _frames(tester);
      expect(
        find.byKey(const ValueKey('studio-page-layout-dialog')),
        findsNothing,
      );
      expect(controller.pageMargins.left, closeTo(72 * 20 / 25.4, 0.000001));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a changed document invalidates an open layout draft', (
    tester,
  ) async {
    final controller = await _open(tester);
    await _type(tester, 'left', '20 mm');
    controller.insertText('New ');
    await tester.tap(_key('apply'));
    await _frames(tester);
    expect(find.textContaining('document changed while'), findsOneWidget);
    expect(controller.pageMargins.left, 72);
    expect(controller.document.paragraphs.single.text, startsWith('New '));
    await tester.tap(_key('cancel'));
    await _frames(tester);
    controller.undo();
    expect(controller.canUndo, isFalse);
    expect(tester.takeException(), isNull);
  });

  for (final language in <StudioLanguage>[
    StudioLanguage.de,
    StudioLanguage.ar,
  ]) {
    testWidgets(
      'Page Layout fits narrow enlarged-text ${language.name} chrome',
      (tester) async {
        final controller = await _open(
          tester,
          language: language,
          size: const Size(500, 900),
          textScale: 1.6,
        );
        for (final tab in <String>['margins', 'paper', 'layout', 'columns']) {
          await _tab(tester, tab);
          expect(_key('preview'), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
        if (language == StudioLanguage.ar) {
          await _tab(tester, 'margins');
          await _type(tester, 'left', '٢٫٥ cm');
          await tester.tap(_key('apply'));
          await _frames(tester);
          expect(
            controller.pageMargins.left,
            closeTo(72 * 2.5 / 2.54, 0.000001),
          );
        } else {
          await tester.tap(_key('cancel'));
          await _frames(tester);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}
