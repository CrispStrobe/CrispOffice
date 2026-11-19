import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Turns on a Studio settings switch such as 'Show comments' or 'Show notes'.
///
/// CrispOffice hides the outline, comments and notes panes by default; tests
/// that drive those panes enable them the way a user does, through Settings.
Future<void> enableStudioSetting(WidgetTester tester, String title) async {
  await tester.tap(find.byTooltip('Settings'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  final tile = find.widgetWithText(SwitchListTile, title);
  await tester.ensureVisible(tile);
  await tester.pump();
  expect(tester.widget<SwitchListTile>(tile).value, isFalse);
  await tester.tap(tile);
  await tester.pump();
  expect(tester.widget<SwitchListTile>(tile).value, isTrue);
  await tester.tap(
    find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(TextButton, 'Close'),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  expect(find.byType(AlertDialog), findsNothing);
}

/// Switches the Studio chrome from English to Arabic.
///
/// The title-bar language button cycles English -> German -> Arabic; its
/// tooltip is the localized word for "Language".
Future<void> switchStudioToArabic(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Language'));
  await tester.pump();
  await tester.tap(find.byTooltip('Sprache'));
  await tester.pump();
  expect(find.byTooltip('اللغة'), findsOneWidget);
}
