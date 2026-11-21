import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_studio/studio_mail_workspace_strings.dart';
import 'package:quds_office_studio/studio_strings.dart';

void main() {
  final english = StudioStrings(StudioLanguage.en).mailMessageListStrings;
  for (final language in StudioLanguage.values) {
    test(
      'conversation controls and observed counts are localized for $language',
      () {
        final strings = StudioStrings(language).mailMessageListStrings;
        expect(strings.collapseConversation.trim(), isNotEmpty);
        expect(strings.expandConversation.trim(), isNotEmpty);
        expect(strings.collapseConversation, isNot(strings.expandConversation));
        final count = strings.conversationCount(7);
        final summary = strings.conversationSummary(7, 2, 3);
        final unknown = strings.conversationUnknown(4, 5);
        expect(count, contains('7'));
        for (final number in ['7', '2', '3']) {
          expect(summary, contains(number));
        }
        for (final number in ['4', '5']) {
          expect(unknown, contains(number));
        }
        final loaded = switch (language) {
          StudioLanguage.en => 'loaded',
          StudioLanguage.de => 'geladen',
          StudioLanguage.ar => 'محمّلة',
        };
        expect(count, contains(loaded));
        expect(summary, contains(loaded));
        if (language != StudioLanguage.en) {
          expect(
            strings.collapseConversation,
            isNot(english.collapseConversation),
          );
          expect(strings.expandConversation, isNot(english.expandConversation));
          expect(summary, isNot(english.conversationSummary(7, 2, 3)));
          expect(unknown, isNot(english.conversationUnknown(4, 5)));
        }
      },
    );
  }
}
