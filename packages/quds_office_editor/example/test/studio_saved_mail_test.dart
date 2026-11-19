import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:quds_office_studio/main.dart';
import 'package:quds_office_studio/studio_chrome.dart';
import 'package:quds_office_studio/studio_mail.dart';
import 'package:quds_office_studio/studio_strings.dart';

import 'support/studio_mail_fixture.dart';

// The former five saved-.eml cases are preserved with their exact source and
// provenance under docs/validation/office-resume-main-20261119/review/.
// This surviving navigation case exercises the current network account UI.
void main() {
  testWidgets('Studio cycles languages and Mail preserves its active sheet', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const QudsOfficeStudioApp());
    await tester.pump();
    final word = tester.widget<QudsWordEditor>(find.byType(QudsWordEditor));
    word.controller.proofing.enabled = false;
    word.controller.proofing.configure(OfficeProofingService(providers: []));
    await pumpMail(tester);

    void expectModules(List<String> labels) {
      expect(
        tester
            .widgetList<StudioAppSwitcher>(find.byType(StudioAppSwitcher))
            .map((widget) => widget.label),
        labels,
      );
    }

    expectModules(<String>[
      'Documents',
      'Spreadsheets',
      'Presentations',
      'PDF',
      'Mail',
    ]);
    await tester.tap(find.byTooltip('Language'));
    await pumpMail(tester);
    expectModules(<String>[
      'Dokumente',
      'Tabellen',
      'Präsentationen',
      'PDF',
      'E-Mail',
    ]);
    await tester.tap(find.text('Tabellen'));
    await pumpMail(tester);
    final sheet = tester.widget<QudsSheetEditor>(find.byType(QudsSheetEditor));
    await tester.tap(find.text('E-Mail'));
    await pumpMail(tester);
    const german = StudioStrings(StudioLanguage.de);
    expect(find.byType(StudioMailDialog), findsOneWidget);
    expect(find.widgetWithText(FilledButton, german.connect), findsOneWidget);
    expect(mailField(german.emailAddress), findsOneWidget);
    expect(mailField(german.password), findsOneWidget);
    expect(
      find.widgetWithText(SwitchListTile, german.manualServers),
      findsOneWidget,
    );
    expect(find.text(german.mailSessionNotice), findsOneWidget);
    await tester.tap(find.byTooltip(german.close).last);
    await pumpMail(tester);
    expect(find.byType(StudioMailDialog), findsNothing);
    expect(
      tester.widget<QudsSheetEditor>(find.byType(QudsSheetEditor)).controller,
      same(sheet.controller),
    );
    await tester.tap(find.byTooltip('Sprache'));
    await pumpMail(tester);
    expectModules(<String>[
      'المستندات',
      'جداول البيانات',
      'العروض التقديمية',
      'PDF',
      'البريد',
    ]);
    await tester.tap(find.byTooltip('اللغة'));
    await pumpMail(tester);
    expectModules(<String>[
      'Documents',
      'Spreadsheets',
      'Presentations',
      'PDF',
      'Mail',
    ]);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
