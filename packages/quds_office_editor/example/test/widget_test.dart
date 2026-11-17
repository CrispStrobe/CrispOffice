import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_studio/main.dart';

void main() {
  testWidgets('Review keeps spelling available without the retired AOT action', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const QudsOfficeStudioApp());
    await tester.pump();
    await tester.tap(find.text('مراجعة'));
    await tester.pump();
    expect(find.text('تدقيق'), findsOneWidget);
    expect(find.text('تحليل AOT'), findsNothing);
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
