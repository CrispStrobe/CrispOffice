import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:quds_office_studio/studio_mail_cached_search.dart';
import 'package:quds_office_studio/studio_mail_search_folder_picker.dart';
import 'package:quds_office_studio/studio_strings.dart';

const _strings = StudioStrings(StudioLanguage.en);
Finder _key(String suffix) =>
    find.byKey(ValueKey('studio-mail-folder-$suffix'));
Finder _folder(String account, String mailbox) =>
    _key(jsonEncode([account, mailbox]));

MailLocalAccountRecord _account(String id) => MailLocalAccountRecord(
  id: id,
  provider: MailProviderKind.imap,
  endpoint: 'imaps://mail.example.test:993',
  login: '$id@example.test',
  sender: '$id@example.test',
  lastConnectedAt: DateTime.utc(2026, 11, 22),
);

StudioMailCachedSearchFolderCatalog _catalog(
  String account, {
  String mailbox = 'Inbox',
  String name = 'Inbox',
  MailProblemCode? problem,
}) => StudioMailCachedSearchFolderCatalog(
  account: _account(account),
  folders: [
    if (problem == null)
      MailMailbox(
        id: MailMailboxId(
          mailbox,
          account: MailAccountId(
            account,
            profile: MailProfileId(
              'folder-picker-profile',
              hostId: 'folder-picker-test',
            ),
          ),
        ),
        displayName: name,
      ),
  ],
  problem: problem,
);

final class _Result {
  bool completed = false;
  StudioMailSearchFolderSelection? value;
}

Future<void> _press(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

bool _checked(WidgetTester tester, Finder row) => tester
    .widget<Checkbox>(find.descendant(of: row, matching: find.byType(Checkbox)))
    .value!;

Future<_Result> _show(
  WidgetTester tester, {
  required List<StudioMailCachedSearchFolderCatalog> catalog,
  List<MailSavedHeaderSearchFolder>? selected,
  StudioStrings strings = _strings,
  Size size = const Size(900, 800),
  double scale = 1,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final result = _Result();
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result.value = await showDialog<StudioMailSearchFolderSelection>(
                context: context,
                builder: (_) => Directionality(
                  textDirection: strings.language == StudioLanguage.ar
                      ? TextDirection.rtl
                      : TextDirection.ltr,
                  child: StudioMailSearchFolderPicker(
                    strings: strings,
                    catalog: catalog,
                    selectedFolders: selected,
                  ),
                ),
              );
              result.completed = true;
            },
            child: const Text('Choose folders'),
          ),
        ),
      ),
    ),
  );
  await _press(tester, find.text('Choose folders'));
  return result;
}

void main() {
  testWidgets('same labels retain exact account and folder identities', (
    tester,
  ) async {
    final result = await _show(
      tester,
      catalog: [
        _catalog('alice', mailbox: 'provider-a', name: 'Inbox'),
        _catalog('bob', mailbox: 'provider-b', name: 'Inbox'),
      ],
      selected: [],
    );
    expect(tester.widget<SwitchListTile>(_key('all')).value, isFalse);
    expect(tester.widget<FilledButton>(_key('apply')).onPressed, isNull);
    await _press(tester, _folder('alice', 'provider-a'));
    expect(_checked(tester, _folder('alice', 'provider-a')), isTrue);
    expect(_checked(tester, _folder('bob', 'provider-b')), isFalse);
    await _press(tester, _key('apply'));
    expect(result.completed, isTrue);
    expect(result.value, isNotNull);
    expect(result.value!.folders, hasLength(1));
    final selected = result.value!.folders!.single;
    expect(selected.accountId, 'alice');
    expect(selected.mailboxId, 'provider-a');
    expect(selected.displayName, 'Inbox');
  });

  testWidgets('empty explicit selection cannot silently widen to all folders', (
    tester,
  ) async {
    const selected = MailSavedHeaderSearchFolder(
      accountId: 'alice',
      mailboxId: 'Inbox',
    );
    final original = <MailSavedHeaderSearchFolder>[selected];
    final result = await _show(
      tester,
      catalog: [_catalog('alice')],
      selected: original,
    );
    await _press(tester, _folder('alice', 'Inbox'));
    expect(_checked(tester, _folder('alice', 'Inbox')), isFalse);
    expect(tester.widget<SwitchListTile>(_key('all')).value, isFalse);
    expect(tester.widget<FilledButton>(_key('apply')).onPressed, isNull);
    expect(result.completed, isFalse);
    await _press(tester, _key('cancel'));
    expect(result.completed, isTrue);
    expect(result.value, isNull);
    expect(original, [selected], reason: 'Cancel preserves the caller scope.');
  });

  testWidgets('only explicit all-folders choice produces an all-folder scope', (
    tester,
  ) async {
    final result = await _show(
      tester,
      catalog: [_catalog('alice')],
      selected: [
        const MailSavedHeaderSearchFolder(
          accountId: 'alice',
          mailboxId: 'Inbox',
        ),
      ],
    );
    expect(tester.widget<SwitchListTile>(_key('all')).value, isFalse);
    await _press(tester, _key('all'));
    expect(tester.widget<SwitchListTile>(_key('all')).value, isTrue);
    await _press(tester, _key('apply'));
    expect(result.completed, isTrue);
    expect(
      result.value,
      isNotNull,
      reason: 'Applying all is not cancellation.',
    );
    expect(result.value!.folders, isNull);
  });

  testWidgets('missing folder stays selected and never matches a reused name', (
    tester,
  ) async {
    const missing = MailSavedHeaderSearchFolder(
      accountId: 'alice',
      mailboxId: 'removed-folder',
      displayName: 'Projects',
    );
    final result = await _show(
      tester,
      catalog: [_catalog('alice', mailbox: 'new-folder', name: 'Projects')],
      selected: [missing],
    );
    expect(_checked(tester, _folder('alice', 'removed-folder')), isTrue);
    expect(_checked(tester, _folder('alice', 'new-folder')), isFalse);
    await _press(tester, _key('apply'));
    expect(result.value!.folders, [missing]);
  });

  testWidgets(
    'repair replaces missing identity only after explicit selection',
    (tester) async {
      final result = await _show(
        tester,
        catalog: [_catalog('alice', mailbox: 'new-folder', name: 'Projects')],
        selected: [
          const MailSavedHeaderSearchFolder(
            accountId: 'alice',
            mailboxId: 'removed-folder',
            displayName: 'Projects',
          ),
        ],
      );
      await _press(tester, _folder('alice', 'removed-folder'));
      expect(tester.widget<FilledButton>(_key('apply')).onPressed, isNull);
      await _press(tester, _folder('alice', 'new-folder'));
      await _press(tester, _key('apply'));
      expect(result.value!.folders, [
        const MailSavedHeaderSearchFolder(
          accountId: 'alice',
          mailboxId: 'new-folder',
        ),
      ]);
    },
  );

  testWidgets('failed folder catalog retains missing selection and raw ID', (
    tester,
  ) async {
    const missing = MailSavedHeaderSearchFolder(
      accountId: 'alice',
      mailboxId: 'provider/id-without-label',
    );
    final result = await _show(
      tester,
      catalog: [_catalog('alice', problem: MailProblemCode.storageFailure)],
      selected: [missing],
    );
    expect(find.textContaining(missing.mailboxId), findsWidgets);
    expect(_checked(tester, _folder('alice', missing.mailboxId)), isTrue);
    await _press(tester, _key('apply'));
    expect(result.value!.folders, [missing]);
    expect(tester.takeException(), isNull);
  });

  for (final language in StudioLanguage.values) {
    testWidgets('narrow enlarged ${language.name} picker remains usable', (
      tester,
    ) async {
      final result = await _show(
        tester,
        catalog: [
          _catalog(
            'long-account-identity',
            mailbox: 'new-folder',
            name: 'Project correspondence / Quarterly reports / الرسائل',
          ),
        ],
        selected: [
          const MailSavedHeaderSearchFolder(
            accountId: 'long-account-identity',
            mailboxId: 'missing-folder',
            displayName: 'Previously selected project correspondence / الرسائل',
          ),
        ],
        strings: StudioStrings(language),
        size: const Size(360, 800),
        scale: 2,
      );
      expect(tester.takeException(), isNull);
      expect(
        Directionality.of(tester.element(_key('picker'))),
        language == StudioLanguage.ar ? TextDirection.rtl : TextDirection.ltr,
      );
      await _press(tester, _key('cancel'));
      expect(result.completed, isTrue);
      expect(result.value, isNull);
      expect(tester.takeException(), isNull);
    });
  }
}
