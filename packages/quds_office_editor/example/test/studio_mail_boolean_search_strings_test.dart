import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_office_studio/studio_mail_cached_search_strings.dart';
import 'package:quds_office_studio/studio_mail_workspace_strings.dart';
import 'package:quds_office_studio/studio_strings.dart';

void main() {
  for (final language in StudioLanguage.values) {
    test('Boolean search help and errors are available for $language', () {
      final strings = StudioStrings(language).mailMessageListStrings;
      expect(strings.searchHelpText, contains('AND'));
      expect(strings.searchHelpText, contains('OR'));
      expect(strings.searchHelpText, contains('NOT'));
      expect(
        strings.searchHelpText,
        contains('(from:alice OR from:bob) NOT subject:invoice'),
      );
      expect(
        strings.searchHelpText,
        contains('from:alice -subject:"weekly digest"'),
      );
      expect(strings.searchHelpText, contains('recipient:"Review Team"'));
      expect(
        strings.searchHelpText,
        contains('participant:alice@example.test'),
      );
      expect(
        strings.searchError(MailHeaderSearchError.unknownField),
        contains('recipient'),
      );
      expect(
        strings.searchError(MailHeaderSearchError.unknownField),
        contains('participant'),
      );
      final cachedHelp = StudioStrings(language).mailCachedSearchGrammar;
      expect(cachedHelp, contains('recipient:'));
      expect(cachedHelp, contains('participant:'));
      expect(cachedHelp, contains('Bcc'));
      for (final error in [
        MailHeaderSearchError.invalidExpression,
        MailHeaderSearchError.nestingTooDeep,
      ]) {
        final message = strings.searchError(error);
        expect(message.trim(), isNotEmpty);
        if (language != StudioLanguage.en) {
          expect(
            message,
            isNot(
              StudioStrings(StudioLanguage.en)
                  .mailMessageListStrings
                  .searchError(error),
            ),
          );
        }
      }
    });
  }
}
