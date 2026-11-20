import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:quds_office_studio/studio_material_theme.dart';
import 'package:quds_office_studio/studio_pdf_tools.dart';

void main() {
  for (final bool dark in [false, true]) {
    testWidgets('themed PDF organize row has finite buttons, dark=$dark', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1200, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: studioMaterialTheme(
            ThemeData(),
            office: dark ? OfficeTheme.dark : OfficeTheme.light,
            accent: Colors.teal,
            dark: dark,
          ),
          home: const Scaffold(
            body: PdfToolsLabDialog(arabic: false, accent: Colors.teal),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.widgetWithText(Tab, 'Organize'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final Finder button = find.widgetWithText(OutlinedButton, 'Blank page');
      expect(button, findsOneWidget);
      final Size size = tester.getSize(button);
      expect(size.width.isFinite, isTrue);
      expect(size.width, inExclusiveRange(0, 400));
      expect(size.height, greaterThanOrEqualTo(44));
      final ThemeData theme = Theme.of(tester.element(button));
      expect(theme.brightness, dark ? Brightness.dark : Brightness.light);
      expect(theme.cardTheme.color, theme.colorScheme.surface);
      expect(theme.inputDecorationTheme.filled, isTrue);
    });
  }
}
