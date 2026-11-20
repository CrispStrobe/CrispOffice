import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:quds_office_studio/studio_mail_draft.dart';
import 'package:quds_office_studio/studio_mail_draft_store.dart';
import 'package:quds_office_studio/studio_mail_drafts_dialog.dart';
import 'package:quds_office_studio/studio_mail_drafts_strings.dart';
import 'package:quds_office_studio/studio_strings.dart';

import 'support/mail_outbox_store.dart';

final _identity = StudioMailDraftAccount(
  provider: 'imap',
  endpoint: 'imaps://imap.example.test:993',
  login: 'reader@example.test',
  sender: 'reader@example.test',
);
const _strings = StudioStrings(StudioLanguage.en);
const _draft = StudioMailDraft(
  to: 'to@example.test',
  subject: 'An independent message',
  body: 'Saved content.',
);

Future<SqliteOutboxFixture> _fixture(WidgetTester tester) async {
  final fixture = await awaitOutboxOperation(
    tester,
    SqliteOutboxFixture.create(_identity),
  );
  addTearDown(() => awaitOutboxOperation(tester, fixture.close()));
  return fixture;
}

Future<void> _mount(
  WidgetTester tester,
  SqliteStudioMailDraftStore store, {
  StudioStrings strings = _strings,
  bool Function()? isCurrent,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showDialog<StudioMailStoredDraft>(
              context: context,
              builder: (_) => StudioMailDraftsDialog(
                strings: strings,
                catalog: store,
                isCurrent: isCurrent ?? () => true,
              ),
            ),
            child: const Text('Open drafts'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open drafts'));
  await pumpOutboxWidgets(tester);
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await pumpOutboxWidgets(tester);
}

void main() {
  testWidgets(
    'delete selected uncertain draft confirms and retains its sibling',
    (tester) async {
      final fixture = await _fixture(tester);
      final store = await awaitOutboxOperation(tester, fixture.openLoaded());
      await awaitOutboxOperation(
        tester,
        store.save(_draft, submissionUncertain: true),
      );
      await awaitOutboxOperation(
        tester,
        store.createDraft(
          const StudioMailDraft(to: '', subject: 'Keep me', body: ''),
        ),
      );
      final otherId = store.selectedDraftId;
      await _mount(tester, store);
      await _tap(
        tester,
        find.byKey(
          const ValueKey('studio-mail-delete-draft-studio-foreground-compose'),
        ),
      );
      expect(
        find.text(_strings.mailDraftDeleteUncertainExplanation),
        findsOneWidget,
      );
      await _tap(tester, find.text(_strings.cancel));
      expect(
        (await awaitOutboxOperation(tester, store.listDrafts())).drafts,
        hasLength(2),
      );
      await _tap(
        tester,
        find.byKey(
          const ValueKey('studio-mail-delete-draft-studio-foreground-compose'),
        ),
      );
      await _tap(
        tester,
        find.byKey(const ValueKey('studio-mail-confirm-delete-draft')),
      );
      final remaining = (await awaitOutboxOperation(
        tester,
        store.listDrafts(),
      )).drafts;
      expect(remaining.single.id, otherId);
      expect(store.selectedDraftId, otherId);
      expect(
        (await awaitOutboxOperation(tester, store.load()))!.draft.subject,
        'Keep me',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('stale confirmation cannot delete a newer stored revision', (
    tester,
  ) async {
    final fixture = await _fixture(tester);
    final store = await awaitOutboxOperation(tester, fixture.openLoaded());
    await awaitOutboxOperation(
      tester,
      store.save(_draft, submissionUncertain: false),
    );
    await _mount(tester, store);
    await _tap(
      tester,
      find.byKey(
        const ValueKey('studio-mail-delete-draft-studio-foreground-compose'),
      ),
    );
    await awaitOutboxOperation(
      tester,
      store.save(
        const StudioMailDraft(
          to: 'new@example.test',
          subject: 'Newer content',
          body: 'Retain',
        ),
        submissionUncertain: false,
      ),
    );
    await _tap(
      tester,
      find.byKey(const ValueKey('studio-mail-confirm-delete-draft')),
    );
    expect(find.text(_strings.mailDraftListFailed), findsOneWidget);
    expect(
      (await awaitOutboxOperation(tester, store.load()))!.draft.subject,
      'Newer content',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'failed new-draft transaction leaves selection and existing work intact',
    (tester) async {
      final fixture = await _fixture(tester);
      final store = await awaitOutboxOperation(tester, fixture.openLoaded());
      await awaitOutboxOperation(
        tester,
        store.save(_draft, submissionUncertain: false),
      );
      await _mount(tester, store);
      fixture.failNextCheckpoint = MailStoreCheckpoint.afterDraftBlobs;
      await _tap(tester, find.byKey(const ValueKey('studio-mail-new-draft')));
      expect(find.byType(StudioMailDraftsDialog), findsOneWidget);
      expect(find.text(_strings.mailDraftListFailed), findsOneWidget);
      expect(store.selectedDraftId, SqliteStudioMailDraftStore.draftId);
      expect(
        (await awaitOutboxOperation(tester, store.listDrafts())).drafts,
        hasLength(1),
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final language in StudioLanguage.values) {
    testWidgets('${language.name} draft list fits a narrow window', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(480, 780));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final fixture = await _fixture(tester);
      final store = await awaitOutboxOperation(tester, fixture.openLoaded());
      await awaitOutboxOperation(
        tester,
        store.save(_draft, submissionUncertain: true),
      );
      final strings = StudioStrings(language);
      await _mount(tester, store, strings: strings);
      expect(find.text(strings.mailDrafts), findsOneWidget);
      expect(find.text(strings.mailDraftUncertain), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'a retired account cannot create a draft through a captured button',
    (tester) async {
      final fixture = await _fixture(tester);
      final store = await awaitOutboxOperation(tester, fixture.openLoaded());
      var current = true;
      await _mount(tester, store, isCurrent: () => current);
      final button = tester.widget<FilledButton>(
        find.byKey(const ValueKey('studio-mail-new-draft')),
      );
      current = false;
      button.onPressed!();
      await pumpOutboxWidgets(tester);
      expect(
        (await awaitOutboxOperation(tester, store.listDrafts())).drafts,
        isEmpty,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
