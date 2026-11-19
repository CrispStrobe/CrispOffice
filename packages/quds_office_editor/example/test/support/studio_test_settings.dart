import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_studio/studio_strings.dart';

export 'package:quds_office_studio/studio_strings.dart' show StudioLanguage;

Future<void> _finishDialogTransition(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump();
}

/// Selects fixture preferences through Studio's public Settings dialog.
/// English and hidden panes remain the product defaults; callers opt in only
/// to the language or pane required by the behavior they exercise.
Future<void> configureStudioForTest(
  WidgetTester tester, {
  StudioLanguage? language,
  bool? showComments,
  bool? showNotes,
}) async {
  final Finder settings = find.byWidgetPredicate(
    (Widget widget) =>
        widget is IconButton &&
        const <String>{
          'Settings',
          'Einstellungen',
          'الإعدادات',
        }.contains(widget.tooltip),
  );
  expect(settings, findsOneWidget);
  await tester.tap(settings);
  await _finishDialogTransition(tester);
  final Finder dialog = find.byType(AlertDialog);
  expect(dialog, findsOneWidget);

  if (language != null) {
    final Finder field = find.descendant(
      of: dialog,
      matching: find.byType(DropdownButtonFormField<StudioLanguage>),
    );
    await tester.ensureVisible(field);
    await tester.tap(field);
    await _finishDialogTransition(tester);
    final String label = switch (language) {
      StudioLanguage.en => 'English',
      StudioLanguage.de => 'Deutsch',
      StudioLanguage.ar => 'العربية',
    };
    await tester.tap(find.text(label).last);
    await _finishDialogTransition(tester);
  }

  Future<void> setSwitch(List<String> labels, bool? desired) async {
    if (desired == null) return;
    final Finder tile = find.descendant(
      of: dialog,
      matching: find.byWidgetPredicate(
        (Widget widget) =>
            widget is SwitchListTile &&
            widget.title is Text &&
            labels.contains((widget.title as Text).data),
      ),
    );
    expect(tile, findsOneWidget);
    if (tester.widget<SwitchListTile>(tile).value == desired) return;
    await tester.ensureVisible(tile);
    await tester.pump();
    await tester.tap(tile);
    await tester.pump();
  }

  await setSwitch(const <String>[
    'Show comments',
    'Kommentare anzeigen',
    'إظهار التعليقات',
  ], showComments);
  await setSwitch(const <String>[
    'Show notes',
    'Notizen anzeigen',
    'إظهار الملاحظات',
  ], showNotes);
  final Finder close = find.descendant(
    of: dialog,
    matching: find.byWidgetPredicate(
      (Widget widget) =>
          widget is TextButton &&
          widget.child is Text &&
          const <String>{
            'Close',
            'Schließen',
            'إغلاق',
          }.contains((widget.child as Text).data),
    ),
  );
  expect(close, findsOneWidget);
  await tester.tap(close);
  await _finishDialogTransition(tester);
  expect(dialog, findsNothing);
}
