import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_office_studio/studio_mail_folder_picker.dart';
import 'package:quds_office_studio/studio_strings.dart';

const _strings = StudioStrings(StudioLanguage.en);
const _one = MailSavedHeaderSearchFolder(
  accountId: 'account-a',
  mailboxId: 'INBOX',
);
const _two = MailSavedHeaderSearchFolder(
  accountId: 'account-b',
  mailboxId: 'Archive',
);
const _missing = MailSavedHeaderSearchFolder(
  accountId: 'account-a',
  mailboxId: 'Removed',
);

final _options = [
  const StudioMailFolderOption(
    folder: _one,
    accountLabel: 'Account A',
    displayName: 'Inbox',
    available: true,
  ),
  const StudioMailFolderOption(
    folder: _two,
    accountLabel: 'Account B',
    displayName: 'Archive',
    available: true,
  ),
];

Finder _folder(MailSavedHeaderSearchFolder folder) => find.byKey(
  ValueKey('studio-mail-folder-${folder.accountId}-${folder.mailboxId}'),
);

Future<void> _press(WidgetTester tester, Finder target) async {
  // Missing folders can be below the dialog's clipped list viewport.
  await Scrollable.ensureVisible(tester.element(target), alignment: 0.5);
  await tester.pumpAndSettle();
  expect(target.hitTestable(), findsOneWidget);
  await tester.tap(target.hitTestable());
  await tester.pumpAndSettle();
}

Future<StudioMailFolderChoice?> _show(
  WidgetTester tester, {
  required List<StudioMailFolderOption> options,
  List<MailSavedHeaderSearchFolder>? initial,
}) async {
  StudioMailFolderChoice? outcome;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              outcome = await showDialog<StudioMailFolderChoice>(
                context: context,
                builder: (_) => StudioMailFolderPickerDialog(
                  strings: _strings,
                  accountIds: const ['account-a', 'account-b'],
                  options: options,
                  initialFolders: initial,
                ),
              );
            },
            child: const Text('Open folders'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open folders'));
  await tester.pumpAndSettle();
  expect(find.byType(StudioMailFolderPickerDialog), findsOneWidget);
  return outcome;
}

void main() {
  testWidgets('folder selection requires coverage for every chosen account', (
    tester,
  ) async {
    await _show(tester, options: _options);
    Finder apply() => find.byKey(const ValueKey('studio-mail-folder-apply'));
    expect(tester.widget<FilledButton>(apply()).onPressed, isNotNull);
    await _press(tester, _folder(_two));
    await tester.pump();
    expect(tester.widget<FilledButton>(apply()).onPressed, isNull);
    await _press(tester, _folder(_two));
    await tester.pump();
    expect(tester.widget<FilledButton>(apply()).onPressed, isNotNull);
    await _press(tester, apply());
    await tester.pumpAndSettle();
    expect(find.byType(StudioMailFolderPickerDialog), findsNothing);
  });

  testWidgets('missing selected folders stay explicit and cannot be applied', (
    tester,
  ) async {
    await _show(
      tester,
      options: [
        ..._options,
        const StudioMailFolderOption(
          folder: _missing,
          accountLabel: 'Account A',
          displayName: 'Removed',
          available: false,
        ),
      ],
      initial: [_missing, _two],
    );
    final apply = find.byKey(const ValueKey('studio-mail-folder-apply'));
    expect(tester.widget<FilledButton>(apply).onPressed, isNull);
    await _press(tester, _folder(_missing));
    await tester.pump();
    expect(tester.widget<FilledButton>(apply).onPressed, isNull);
    await _press(tester, _folder(_one));
    await tester.pump();
    expect(tester.widget<FilledButton>(apply).onPressed, isNotNull);
    await _press(tester, apply);
    await tester.pumpAndSettle();
    expect(find.byType(StudioMailFolderPickerDialog), findsNothing);
  });

  testWidgets('all retained folders is a separate explicit choice', (
    tester,
  ) async {
    await _show(tester, options: _options, initial: [_one, _two]);
    await _press(tester, find.byKey(const ValueKey('studio-mail-folder-all')));
    await tester.pumpAndSettle();
    expect(find.byType(StudioMailFolderPickerDialog), findsNothing);
  });
}
