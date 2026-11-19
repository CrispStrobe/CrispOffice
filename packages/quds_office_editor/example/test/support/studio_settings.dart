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
  await tester.tap(find.widgetWithText(TextButton, 'Close'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  expect(find.byType(AlertDialog), findsNothing);
}
