import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:quds_office_studio/main.dart';

Future<void> _pump(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump();
}

QudsWordEditor _editor(WidgetTester tester) =>
    tester.widget<QudsWordEditor>(find.byType(QudsWordEditor));

Future<void> _settings(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Settings'));
  await _pump(tester);
  expect(find.byType(AlertDialog), findsOneWidget);
}

Future<void> _closeSettings(WidgetTester tester) async {
  await tester.tap(
    find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(TextButton, 'Close'),
    ),
  );
  await _pump(tester);
}

void main() {
  testWidgets('Show notes settings update the existing Word surface', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const QudsOfficeStudioApp());
    await tester.pump();
    final controller = _editor(tester).controller;
    controller.proofing.enabled = false;
    controller.proofing.configure(OfficeProofingService(providers: []));
    final note = WmlNote(
      id: 1,
      endnote: false,
      paragraphs: [
        WmlParagraph(inlines: [WmlRun(text: 'A retained footnote.')]),
      ],
    );
    final document = WmlDocument.empty(text: 'Document body.')
      ..footnotes.add(note);
    controller.document = document;
    controller.refresh();
    await _pump(tester);

    expect(find.byTooltip('Language'), findsOneWidget);
    expect(_editor(tester).config!.showNotesPane, isFalse);
    expect(controller.config.showNotesPane, isFalse);
    expect(find.byType(WordNotesPane), findsNothing);

    await _settings(tester);
    final notes = find.widgetWithText(SwitchListTile, 'Show notes');
    expect(tester.widget<SwitchListTile>(notes).value, isFalse);
    await tester.ensureVisible(notes);
    await tester.tap(notes);
    await tester.pump();
    expect(tester.widget<SwitchListTile>(notes).value, isTrue);
    await _closeSettings(tester);

    expect(_editor(tester).controller, same(controller));
    expect(_editor(tester).config!.showNotesPane, isTrue);
    expect(controller.config.showNotesPane, isTrue);
    expect(find.byType(WordNotesPane), findsOneWidget);
    final field = find.byKey(const ValueKey<String>('notes-edit-1'));
    expect(field, findsOneWidget);
    expect(
      tester.widget<TextField>(field).controller!.text,
      'A retained footnote.',
    );

    await _settings(tester);
    expect(tester.widget<SwitchListTile>(notes).value, isTrue);
    await tester.ensureVisible(notes);
    await tester.tap(notes);
    await tester.pump();
    expect(tester.widget<SwitchListTile>(notes).value, isFalse);
    await _closeSettings(tester);

    expect(_editor(tester).config!.showNotesPane, isFalse);
    expect(controller.config.showNotesPane, isFalse);
    expect(find.byType(WordNotesPane), findsNothing);
    expect(controller.document, same(document));
    expect(controller.document.footnotes.single, same(note));
    expect(note.paragraphs.single.text, 'A retained footnote.');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
