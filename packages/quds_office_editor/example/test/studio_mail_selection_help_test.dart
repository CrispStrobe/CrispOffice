import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_ui/quds_mail_ui.dart';
import 'package:quds_office_studio/studio_mail_workspace_strings.dart';
import 'package:quds_office_studio/studio_strings.dart';

void main() {
  final english = StudioStrings(StudioLanguage.en).mailMessageListStrings;
  for (final language in StudioLanguage.values) {
    testWidgets(
      'selection help is localized and readable at enlarged text for $language',
      (tester) async {
        await tester.binding.setSurfaceSize(const Size(360, 640));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final strings = StudioStrings(language).mailMessageListStrings;
        final direction = language == StudioLanguage.ar
            ? TextDirection.rtl
            : TextDirection.ltr;
        expect(strings.selectionHelp.trim(), isNotEmpty);
        expect(strings.selectionHelpTitle.trim(), isNotEmpty);
        expect(strings.selectionHelpText.trim(), isNotEmpty);
        expect(strings.selectionHelpText, contains('Escape'));
        expect(strings.selectionHelpText, contains(strings.bulkActions));
        final rangeKey = language == StudioLanguage.de ? 'Umschalt' : 'Shift';
        expect(strings.selectionHelpText, contains(rangeKey));
        if (language != StudioLanguage.en) {
          expect(strings.selectionHelp, isNot(english.selectionHelp));
          expect(strings.selectionHelpTitle, isNot(english.selectionHelpTitle));
          expect(strings.selectionHelpText, isNot(english.selectionHelpText));
        }
        var opens = 0;
        var actions = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.4)),
              child: Directionality(
                textDirection: direction,
                child: Scaffold(
                  body: MailMessageList(
                    items: const [
                      MailMessageListItem(
                        id: 'one',
                        subject: 'Review',
                        sender: 'sender@example.test',
                      ),
                    ],
                    strings: strings,
                    scopeId: 'account/inbox',
                    onOpen: (_) => opens++,
                    onBulkAction: (_, _) => actions++,
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final help = find.byKey(const ValueKey('mail-list-selection-help'));
        await tester.ensureVisible(help);
        await tester.tap(help);
        await tester.pumpAndSettle();
        expect(find.text(strings.selectionHelpTitle), findsOneWidget);
        final firstParagraph = find.text(
          strings.selectionHelpText.split('\n').first,
        );
        expect(firstParagraph, findsOneWidget);
        expect(Directionality.of(tester.element(firstParagraph)), direction);
        expect(
          MediaQuery.textScalerOf(tester.element(firstParagraph)).scale(10),
          14,
        );
        expect(tester.takeException(), isNull);
        final close = find.text(strings.close);
        await tester.ensureVisible(close);
        await tester.tap(close);
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(opens, 0);
        expect(actions, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
