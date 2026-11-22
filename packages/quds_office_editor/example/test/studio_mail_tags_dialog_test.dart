import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_office_studio/studio_mail_tag_strings.dart';
import 'package:quds_office_studio/studio_mail_tags_dialog.dart';
import 'package:quds_office_studio/studio_strings.dart';

void main() {
  testWidgets('selects known tags and adds a new one', (tester) async {
    Set<String>? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showStudioMailTagsDialog(
                context,
                strings: const StudioStrings(StudioLanguage.en),
                selected: [MailTag.parse('Work')],
                known: [MailTag.parse('Work'), MailTag.parse('Receipts')],
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('studio-mail-tag-known-receipts')),
    );
    await tester.enterText(
      find.byKey(const ValueKey('studio-mail-tag-name')),
      'Travel',
    );
    await tester.tap(find.byKey(const ValueKey('studio-mail-tag-add')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('studio-mail-tag-save')));
    await tester.pumpAndSettle();
    expect(result, {'Work', 'Receipts', 'Travel'});
  });

  testWidgets('invalid tag keeps the dialog open with an error', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showStudioMailTagsDialog(
              context,
              strings: const StudioStrings(StudioLanguage.en),
              selected: const [],
              known: const [],
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('studio-mail-tag-name')),
      'bad/tag',
    );
    await tester.tap(find.byKey(const ValueKey('studio-mail-tag-add')));
    await tester.pump();
    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('studio-mail-tag-name')),
    );
    expect(
      field.decoration?.errorText,
      const StudioStrings(StudioLanguage.en).mailTagInvalid,
    );
    expect(find.byKey(const ValueKey('studio-mail-tag-save')), findsOneWidget);
  });
}
