import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_engine/quds_productivity_automation.dart';
import 'package:quds_office_engine/quds_productivity_live.dart';
import 'package:quds_office_studio/studio_live_productivity.dart';

void main() {
  testWidgets('consent issues a grant and the view can revoke it', (
    tester,
  ) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StudioLiveProductivityButton(
            kind: ProductivityKind.tasks,
            scope: 'Personal tasks',
            scopeKey: 'personal',
            scopeIsCurrent: () => true,
            readRows: () => [
              {'title': 'Visible task'},
            ],
          ),
        ),
      ),
    );
    final button = find.byTooltip(studioLiveProductivityLabel);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.textContaining('Personal tasks'), findsOneWidget);
    expect(copied, isNull);

    await tester.tap(find.text('Grant read access'));
    for (
      var attempt = 0;
      attempt < 20 && find.text('Copy grant').evaluate().isEmpty;
      attempt++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy grant'));
    await tester.pumpAndSettle();
    expect(copied, isNotNull);

    expect(
      ProductivityGrantTicket.parse(copied!),
      isA<ProductivityGrantTicket>(),
    );

    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('Revoke access'), findsOneWidget);
    await tester.tap(find.text('Revoke access'));
    await tester.pumpAndSettle();

    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('Grant read access'), findsOneWidget);
    expect(find.text('Copy grant'), findsNothing);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
