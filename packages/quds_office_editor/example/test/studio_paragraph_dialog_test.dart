import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:quds_office_studio/studio_paragraph_dialog.dart';
import 'package:quds_office_studio/studio_strings.dart';

Finder _key(String value) => find.byKey(ValueKey('paragraph-$value'));

Future<void> _frames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump();
}

WmlParagraph _paragraph(String text, [WmlParagraphProps? properties]) =>
    WmlParagraph(
      inlines: [WmlRun(text: text)],
      properties: properties,
    );

Object _format(WmlParagraphProps props) => (
  before: props.spacingBefore,
  after: props.spacingAfter,
  line: props.lineSpacing,
  rule: props.lineSpacingRule,
  left: props.indent.left,
  right: props.indent.right,
  first: props.indent.firstLine,
  hanging: props.indent.hanging,
  keep: props.keepTogether,
  page: props.pageBreakBefore,
  column: props.columnBreakBefore,
  explicitBefore: props.explicitSpacingBefore,
  explicitAfter: props.explicitSpacingAfter,
  explicitLine: props.explicitLineSpacing,
  explicitIndent: props.explicitIndent,
);

Future<WordEditorController> _open(
  WidgetTester tester, {
  WmlDocument? document,
  StudioLanguage language = StudioLanguage.en,
  Size size = const Size(1100, 900),
  double textScale = 1,
  void Function(WordEditorController)? prepare,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final controller = WordEditorController(
    document: document ?? WmlDocument.empty(text: 'Selected paragraph.'),
    config: const OfficeSurfaceConfig(autofocus: false),
  );
  controller.proofing.enabled = false;
  controller.proofing.configure(OfficeProofingService(providers: []));
  prepare?.call(controller);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await _frames(tester);
    if (!controller.isDisposed) controller.dispose();
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
            onPressed: () => showStudioParagraphDialog(
              context: context,
              controller: controller,
              language: language,
              unit: OfficeLengthUnit.millimeters,
            ),
            child: const Text('Open Paragraph'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open Paragraph'));
  await _frames(tester);
  return controller;
}

Future<void> _type(WidgetTester tester, String field, String value) async {
  await tester.ensureVisible(_key(field));
  await tester.enterText(_key(field), value);
  await _frames(tester);
}

Future<void> _pick(WidgetTester tester, String field, String label) async {
  await tester.ensureVisible(_key(field));
  await tester.tap(_key(field));
  await _frames(tester);
  await tester.ensureVisible(find.text(label).last);
  await tester.tap(find.text(label).last);
  await _frames(tester);
}

Future<void> _check(WidgetTester tester, String field) async {
  await tester.ensureVisible(_key(field));
  await tester.tap(_key(field));
  await _frames(tester);
}

void main() {
  testWidgets('Cancel discards spacing, indent and pagination drafts', (
    tester,
  ) async {
    final controller = await _open(tester);
    final paragraph = controller.document.paragraphs.single;
    final before = _format(paragraph.properties);
    final revision = controller.contentRevision;
    await _type(tester, 'before', '12 pt');
    await _type(tester, 'left', '1.5 cm');
    await _pick(tester, 'special-kind', 'First line');
    await _type(tester, 'special', '6 mm');
    await _check(tester, 'pageBreak');
    await tester.tap(_key('cancel'));
    await _frames(tester);
    expect(find.byKey(const ValueKey('studio-paragraph-dialog')), findsNothing);
    expect(_format(paragraph.properties), before);
    expect(controller.contentRevision, revision);
    expect(controller.isDirty, isFalse);
    expect(controller.canUndo, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'selected paragraphs apply precisely in one undo and round trip',
    (tester) async {
      final first = _paragraph('First', WmlParagraphProps(spacingAfter: 7));
      final second = _paragraph('Second', WmlParagraphProps(spacingAfter: 19));
      final last = _paragraph('Not selected');
      final document = WmlDocument(
        sections: [
          WmlSection(blocks: [first, second, last]),
        ],
      );
      final initial = [
        for (final paragraph in [first, second, last])
          _format(paragraph.properties),
      ];
      final controller = await _open(
        tester,
        document: document,
        prepare: (controller) {
          controller.caret
            ..paragraphIndex = 1
            ..logicalIndex = 2
            ..selectionAnchorParagraph = 0
            ..selectionAnchor = 0;
        },
      );
      final revision = controller.contentRevision;
      await _type(tester, 'before', '12.7 mm');
      await _type(tester, 'line', '1,75');
      await _type(tester, 'left', '2,5 cm');
      await _type(tester, 'right', '0.25 in');
      await _pick(tester, 'special-kind', 'Hanging');
      await _type(tester, 'special', '9 pt');
      await _check(tester, 'keepLines');
      await _check(tester, 'pageBreak');
      await tester.tap(_key('apply'));
      await _frames(tester);
      expect(
        find.byKey(const ValueKey('studio-paragraph-dialog')),
        findsNothing,
      );
      for (final paragraph in [first, second]) {
        final props = paragraph.properties;
        expect(props.spacingBefore, closeTo(36, 0.0000001));
        expect(props.lineSpacing, 1.75);
        expect(props.lineSpacingRule, WmlLineSpacingRule.auto);
        expect(props.indent.left, closeTo(72 * 2.5 / 2.54, 0.0000001));
        expect(props.indent.right, 18);
        expect(props.indent.firstLine, 0);
        expect(props.indent.hanging, 9);
        expect(props.keepTogether, isTrue);
        expect(props.pageBreakBefore, isTrue);
        expect(props.explicitSpacingBefore, isTrue);
        expect(props.explicitSpacingAfter, isFalse);
        expect(props.explicitIndent, isTrue);
        expect(props.explicitLineSpacing, isTrue);
      }
      expect(first.properties.spacingAfter, 7);
      expect(second.properties.spacingAfter, 19);
      expect(_format(last.properties), initial.last);
      expect(controller.contentRevision, revision + 1);
      final saved = WordDeserializer().readBytes(
        WordSerializer().writeBytes(document),
      );
      expect(saved.paragraphs.first.properties.spacingBefore, 36);
      expect(saved.paragraphs.first.properties.lineSpacing, 1.75);
      expect(saved.paragraphs.first.properties.indent.hanging, 9);
      expect(saved.paragraphs.first.properties.keepTogether, isTrue);
      expect(saved.paragraphs.first.properties.pageBreakBefore, isTrue);
      controller.undo();
      expect([
        for (final paragraph in [first, second, last])
          _format(paragraph.properties),
      ], initial);
      expect(controller.canUndo, isFalse);
      controller.redo();
      expect(first.properties.lineSpacing, 1.75);
      expect(second.properties.indent.hanging, 9);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('unit changes and no-op Apply preserve exact imported values', (
    tester,
  ) async {
    final paragraph = _paragraph(
      'Exact',
      WmlParagraphProps(
        spacingBefore: 7.123456789,
        spacingAfter: 9.876543219,
        lineSpacing: 13.987654321,
        lineSpacingRule: WmlLineSpacingRule.exact,
        indent: const WmlIndent(left: 31.234567891, firstLine: 12.543219876),
      ),
    );
    final initial = _format(paragraph.properties);
    final controller = await _open(
      tester,
      document: WmlDocument(
        sections: [
          WmlSection(blocks: [paragraph]),
        ],
      ),
    );
    await _pick(tester, 'unit', 'Centimetres (cm)');
    await _pick(tester, 'unit', 'Inches (in)');
    await _pick(tester, 'unit', 'Millimetres (mm)');
    await tester.tap(_key('apply'));
    await _frames(tester);
    expect(_format(paragraph.properties), initial);
    expect(controller.isDirty, isFalse);
    expect(controller.canUndo, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('exact line height and first-line indent use point conversion', (
    tester,
  ) async {
    final controller = await _open(tester);
    final paragraph = controller.document.paragraphs.single;
    final initial = _format(paragraph.properties);
    await _pick(tester, 'line-rule', 'Exactly');
    await _type(tester, 'line', '6.35 mm');
    await _pick(tester, 'special-kind', 'First line');
    await _type(tester, 'special', '0.25 in');
    await tester.tap(_key('apply'));
    await _frames(tester);
    expect(paragraph.properties.lineSpacingRule, WmlLineSpacingRule.exact);
    expect(paragraph.properties.lineSpacing, closeTo(18, 0.0000001));
    expect(paragraph.properties.indent.firstLine, 18);
    expect(paragraph.properties.indent.hanging, 0);
    controller.undo();
    expect(_format(paragraph.properties), initial);
    expect(controller.canUndo, isFalse);
  });

  testWidgets('mixed line rules, indents and pagination remain unchanged', (
    tester,
  ) async {
    final first = _paragraph(
      'First',
      WmlParagraphProps(
        lineSpacing: 1.5,
        indent: const WmlIndent(left: 36, hanging: 9),
        keepTogether: true,
      ),
    );
    final second = _paragraph(
      'Second',
      WmlParagraphProps(
        lineSpacing: 18,
        lineSpacingRule: WmlLineSpacingRule.atLeast,
        indent: const WmlIndent(firstLine: 12),
      ),
    );
    final controller = await _open(
      tester,
      document: WmlDocument(
        sections: [
          WmlSection(blocks: [first, second]),
        ],
      ),
      prepare: (controller) {
        controller.caret
          ..paragraphIndex = 1
          ..logicalIndex = 3
          ..selectionAnchorParagraph = 0
          ..selectionAnchor = 0;
      },
    );
    await _type(tester, 'after', '10 pt');
    await tester.tap(_key('apply'));
    await _frames(tester);
    expect(first.properties.spacingAfter, 10);
    expect(second.properties.spacingAfter, 10);
    expect(first.properties.lineSpacing, 1.5);
    expect(second.properties.lineSpacing, 18);
    expect(second.properties.lineSpacingRule, WmlLineSpacingRule.atLeast);
    expect(first.properties.indent.hanging, 9);
    expect(second.properties.indent.firstLine, 12);
    expect(first.properties.keepTogether, isTrue);
    expect(second.properties.keepTogether, isFalse);
    expect(first.properties.explicitLineSpacing, isFalse);
    expect(second.properties.explicitIndent, isFalse);
    expect(controller.canUndo, isTrue);
  });

  testWidgets('invalid numbers and geometry cannot mutate paragraphs', (
    tester,
  ) async {
    final controller = await _open(tester);
    final paragraph = controller.document.paragraphs.single;
    final initial = _format(paragraph.properties);
    for (final value in ['NaN', 'Infinity', '1e8 mm', '1,2.3 mm', '-1 pt']) {
      await _type(tester, 'before', value);
      await tester.tap(_key('apply'));
      await _frames(tester);
      expect(_key('validation'), findsOneWidget);
      expect(_format(paragraph.properties), initial);
      expect(controller.canUndo, isFalse);
    }
    await _type(tester, 'before', '0');
    await _type(tester, 'left', '1000 pt');
    await tester.tap(_key('apply'));
    await _frames(tester);
    expect(find.textContaining('12 pt of text width'), findsOneWidget);
    await _type(tester, 'left', '0');
    await _type(tester, 'line', '0');
    await tester.tap(_key('apply'));
    await _frames(tester);
    expect(find.textContaining('greater than zero'), findsOneWidget);
    expect(_format(paragraph.properties), initial);
    expect(controller.isDirty, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'pagination controls turn off existing flags and avoid conflicting breaks',
    (tester) async {
      final paragraph = _paragraph(
        'Breaks',
        WmlParagraphProps(keepTogether: true, pageBreakBefore: true),
      );
      final controller = await _open(
        tester,
        document: WmlDocument(
          sections: [
            WmlSection(blocks: [paragraph]),
          ],
        ),
      );
      await _check(tester, 'keepLines');
      await _check(tester, 'columnBreak');
      await tester.tap(_key('apply'));
      await _frames(tester);
      expect(paragraph.properties.keepTogether, isFalse);
      expect(paragraph.properties.pageBreakBefore, isFalse);
      expect(paragraph.properties.columnBreakBefore, isTrue);
      controller.undo();
      expect(paragraph.properties.keepTogether, isTrue);
      expect(paragraph.properties.pageBreakBefore, isTrue);
      expect(paragraph.properties.columnBreakBefore, isFalse);
    },
  );

  for (final scenario in <String>[
    'document',
    'revision',
    'selection',
    'story',
    'permission',
    'disposed',
  ]) {
    testWidgets('a changed $scenario rejects the detached paragraph draft', (
      tester,
    ) async {
      final first = _paragraph('Body one');
      final second = _paragraph('Body two');
      final header = _paragraph('Header');
      final document = WmlDocument(
        sections: [
          WmlSection(
            blocks: [first, second],
            header: [header],
            footer: [_paragraph('Footer')],
          ),
        ],
      );
      final controller = await _open(tester, document: document);
      await _type(tester, 'before', '24 pt');
      switch (scenario) {
        case 'document':
          controller.document = WmlDocument.empty(text: 'Replacement');
        case 'revision':
          controller.applyParagraphFormat((props) => props.spacingAfter = 23);
        case 'selection':
          controller.caret
            ..paragraphIndex = 1
            ..logicalIndex = 0
            ..collapseSelection();
        case 'story':
          controller.beginHeaderFooterEdit(0, footer: false);
        case 'permission':
          controller.config = controller.config.copyWith(
            mode: OfficeInteractionMode.selecting,
          );
        case 'disposed':
          controller.dispose();
      }
      final revision = controller.contentRevision;
      await tester.tap(_key('apply'));
      await _frames(tester);
      expect(_key('validation'), findsOneWidget);
      expect(
        find.textContaining('document or selection changed'),
        findsOneWidget,
      );
      expect(first.properties.spacingBefore, 0);
      expect(second.properties.spacingBefore, 0);
      expect(header.properties.spacingBefore, 0);
      expect(controller.contentRevision, revision);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('header paragraph changes stay in the captured header story', (
    tester,
  ) async {
    final body = _paragraph('Body');
    final header = _paragraph('Header');
    final footer = _paragraph('Footer');
    final document = WmlDocument(
      sections: [
        WmlSection(blocks: [body], header: [header], footer: [footer]),
      ],
    );
    final controller = await _open(
      tester,
      document: document,
      prepare: (controller) =>
          controller.beginHeaderFooterEdit(0, footer: false),
    );
    await _type(tester, 'after', '14 pt');
    await tester.tap(_key('apply'));
    await _frames(tester);
    expect(header.properties.spacingAfter, 14);
    expect(body.properties.spacingAfter, 8);
    expect(footer.properties.spacingAfter, 8);
    controller.undo();
    expect(header.properties.spacingAfter, 8);
    expect(controller.canUndo, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('inspection of an empty document does not create content', (
    tester,
  ) async {
    final controller = await _open(
      tester,
      prepare: (controller) =>
          controller.document.sections.single.blocks.clear(),
    );
    expect(_key('unavailable'), findsOneWidget);
    expect(controller.document.sections.single.blocks, isEmpty);
    expect(controller.isDirty, isFalse);
    expect(controller.canUndo, isFalse);
    await tester.tap(_key('close'));
    await _frames(tester);
    expect(controller.document.sections.single.blocks, isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final language in StudioLanguage.values) {
    testWidgets(
      '${language.name} dialog supports narrow enlarged text and precise local numbers',
      (tester) async {
        final controller = await _open(
          tester,
          language: language,
          size: const Size(420, 700),
          textScale: 1.8,
        );
        final title = switch (language) {
          StudioLanguage.en => 'Paragraph',
          StudioLanguage.de => 'Absatz',
          StudioLanguage.ar => 'الفقرة',
        };
        expect(find.text(title), findsOneWidget);
        if (language == StudioLanguage.ar) {
          expect(
            Directionality.of(tester.element(_key('before'))),
            TextDirection.rtl,
          );
        }
        await _type(tester, 'before', switch (language) {
          StudioLanguage.en => '0.5 in',
          StudioLanguage.de => '1,27 cm',
          StudioLanguage.ar => '١٢٫٧ mm',
        });
        await tester.tap(_key('apply'));
        await _frames(tester);
        expect(
          controller.document.paragraphs.single.properties.spacingBefore,
          closeTo(36, 0.0000001),
        );
        expect(
          find.byKey(const ValueKey('studio-paragraph-dialog')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
