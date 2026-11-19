import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:quds_office_studio/studio_chrome.dart';

Future<void> _finishModeTransition(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump();
}

/// Changes the document mode through the same ribbon menu used by the host.
Future<void> selectStudioDocumentMode(
  WidgetTester tester,
  OfficeInteractionMode mode,
) async {
  final menu = find.byKey(const ValueKey('ribbon-menu-document-mode'));
  if (menu.evaluate().isEmpty) {
    await tester.tap(find.byKey(const ValueKey('ribbon-tab-file')));
    await _finishModeTransition(tester);
  }
  if (menu.evaluate().isEmpty) {
    final ribbon = find.descendant(
      of: find.byType(StudioRibbonStrip),
      matching: find.byType(Scrollable),
    );
    tester.state<ScrollableState>(ribbon).position.jumpTo(0);
    await tester.pump();
    if (menu.evaluate().isEmpty) {
      await tester.scrollUntilVisible(menu, 240, scrollable: ribbon);
    }
  }
  await tester.ensureVisible(menu);
  await tester.pump();
  await tester.tap(menu);
  await _finishModeTransition(tester);
  final label = switch (mode) {
    OfficeInteractionMode.editing => 'Edit document',
    OfficeInteractionMode.selecting => 'Read and copy',
    OfficeInteractionMode.viewing => 'Preview only',
  };
  final choice = find.widgetWithText(MenuItemButton, label);
  expect(choice, findsOneWidget);
  await tester.tap(choice);
  await _finishModeTransition(tester);
}
