import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_studio/main.dart';
import 'package:quds_office_studio/studio_chrome.dart';
import 'package:quds_office_studio/studio_pdf_surface.dart';

Future<void> _pump(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

Future<void> _finishTransition(WidgetTester tester) async {
  await _pump(tester);
  await tester.pump(const Duration(milliseconds: 350));
  await _pump(tester);
}

void main() {
  testWidgets('compact PDF navigation updates tabs and controller selection', (
    tester,
  ) async {
    expect(defaultTargetPlatform, TargetPlatform.linux);
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const QudsOfficeStudioApp());
    await _pump(tester);
    expect(find.byTooltip('Language'), findsOneWidget);
    await _pump(tester);
    final pdfApp = find.byWidgetPredicate(
      (widget) => widget is StudioAppSwitcher && widget.label == 'PDF',
    );
    await tester.ensureVisible(pdfApp);
    await _pump(tester);
    await tester.tap(pdfApp);
    await _pump(tester);
    final controller = tester
        .widget<StudioPdfSurface>(find.byType(StudioPdfSurface))
        .controller;
    expect(controller.file!.outline!.children, isNotEmpty);
    await tester.binding.setSurfaceSize(const Size(390, 1000));
    await _pump(tester);

    final navigation = find.byTooltip('Navigation');
    expect(navigation.hitTestable(), findsOneWidget);
    await tester.tap(navigation);
    await _finishTransition(tester);
    final sheet = find.byType(BottomSheet);
    expect(sheet, findsOneWidget);
    Finder inside(Finder matching) =>
        find.descendant(of: sheet, matching: matching);
    expect(inside(find.byType(Scrollbar)), findsWidgets);
    expect(inside(find.text('Page previews')), findsOneWidget);

    await tester.tap(inside(find.byTooltip('Outline')));
    await _pump(tester);
    expect(inside(find.text('Cover')), findsOneWidget);
    expect(inside(find.text('Page previews')), findsNothing);
    await tester.tap(inside(find.text('Typography')));
    await _pump(tester);
    expect(controller.pageIndex, 1);

    await tester.tap(inside(find.byTooltip('Page previews')));
    await _finishTransition(tester);
    expect(inside(find.text('Page previews')), findsOneWidget);
    expect(inside(find.text('Page 2  ·  current')), findsOneWidget);
    expect(inside(find.text('Cover')), findsNothing);

    // Resizing can restore the inline pane while this route is still open.
    // Both thumbnail views must tolerate the same controller update.
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    await _pump(tester);
    expect(sheet, findsOneWidget);
    // A controller update outside the modal must refresh its selected page too.
    controller.goToPage(0);
    await _finishTransition(tester);
    expect(inside(find.text('Page 1  ·  current')), findsOneWidget);
    expect(inside(find.text('Page 2  ·  current')), findsNothing);

    Navigator.of(tester.element(sheet)).pop();
    await _finishTransition(tester);
    expect(sheet, findsNothing);
    await tester.binding.setSurfaceSize(const Size(390, 1000));
    await _pump(tester);
    expect(navigation.hitTestable(), findsOneWidget);
    expect(controller.pageIndex, 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await _pump(tester);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
}
