import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:quds_office_studio/main.dart';

import 'support/studio_test_settings.dart';

void main() {
  testWidgets(
    'Review keeps spelling available without the retired AOT action',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const QudsOfficeStudioApp());
      await tester.pump();
      final controller = tester
          .widget<QudsWordEditor>(find.byType(QudsWordEditor))
          .controller;
      controller.proofing.configure(OfficeProofingService(providers: []));
      await configureStudioForTest(tester, language: StudioLanguage.ar);
      await tester.tap(find.text('مراجعة'));
      await tester.pump();
      expect(find.text('تدقيق'), findsOneWidget);
      expect(find.text('تحليل AOT'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'studio hosts document, spreadsheet, and presentation workspaces',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const QudsOfficeStudioApp());
      await tester.pump();

      expect(find.text('CrispOffice'), findsOneWidget);
      expect(find.text('Documents'), findsWidgets);

      await tester.tap(find.text('Spreadsheets').first);
      await tester.pump();
      expect(find.text('Budget'), findsWidgets);
      expect(find.text('Roster'), findsWidgets);

      await tester.tap(find.text('Presentations').first);
      await tester.pump();
      expect(find.textContaining('.pptx'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Settings shows and hides Notes without another config change', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const QudsOfficeStudioApp());
    await tester.pump();
    final WordEditorController controller = tester
        .widget<QudsWordEditor>(find.byType(QudsWordEditor))
        .controller;
    controller.proofing.configure(OfficeProofingService(providers: []));
    final WmlNote note = WordNotes.insert(
      controller.document,
      controller.document.paragraphs.first,
      endnote: false,
      text: 'Toggle this note.',
    );
    controller.refresh();
    await tester.pump();
    final Finder noteEditor = find.byKey(
      ValueKey<String>('notes-edit-${note.id}'),
    );
    expect(noteEditor, findsNothing);

    await configureStudioForTest(tester, showNotes: true);
    expect(
      tester
          .widget<QudsWordEditor>(find.byType(QudsWordEditor))
          .config
          ?.showNotesPane,
      isTrue,
    );
    expect(noteEditor, findsOneWidget);

    await configureStudioForTest(tester, showNotes: false);
    expect(
      tester
          .widget<QudsWordEditor>(find.byType(QudsWordEditor))
          .config
          ?.showNotesPane,
      isFalse,
    );
    expect(noteEditor, findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
    expect(tester.takeException(), isNull);
  });
}
