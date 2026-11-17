import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_studio/main.dart';

void main() {
  testWidgets('Review exposes local AOT analysis without an endpoint setting', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const QudsOfficeStudioApp());
    await tester.pump();
    await tester.tap(find.text('مراجعة'));
    await tester.pump();
    expect(find.text('تحليل AOT'), findsOneWidget);
    await tester.tap(find.text('تحليل AOT'));
    // The editor's caret continues blinking behind the dialog.
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.text('AOT linguistic analysis'), findsOneWidget);
    expect(find.text('Local AOT · stays on this device'), findsOneWidget);
    expect(find.textContaining('Install the AOT worker'), findsNothing);
    await tester.tap(find.text('Close'));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('studio hosts Word, Excel, and PowerPoint workspaces', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const QudsOfficeStudioApp());
    await tester.pump();

    expect(find.text('Quds Office Studio'), findsOneWidget);
    expect(find.text('Word'), findsWidgets);

    await tester.tap(find.text('Excel').first);
    await tester.pump();
    expect(find.text('Budget'), findsWidgets);
    expect(find.text('Roster'), findsWidgets);

    await tester.tap(find.text('PowerPoint').first);
    await tester.pump();
    expect(find.textContaining('.pptx'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
