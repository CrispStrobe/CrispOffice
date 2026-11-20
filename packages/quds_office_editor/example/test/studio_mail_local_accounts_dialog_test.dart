import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:quds_office_studio/studio_mail_cached_mail.dart';
import 'package:quds_office_studio/studio_mail_cached_strings.dart';
import 'package:quds_office_studio/studio_mail_compose.dart';
import 'package:quds_office_studio/studio_mail_draft_store.dart';
import 'package:quds_office_studio/studio_mail_drafts_dialog.dart';
import 'package:quds_office_studio/studio_mail_local_accounts_dialog.dart';
import 'package:quds_office_studio/studio_mail_local_accounts_strings.dart';
import 'package:quds_office_studio/studio_mail_strings.dart';
import 'package:quds_office_studio/studio_strings.dart';

import 'support/mail_local_accounts.dart';
import 'support/mail_outbox_store.dart';

const _strings = StudioStrings(StudioLanguage.en);

StudioMailDraftAccount _identity(String provider) => StudioMailDraftAccount(
  provider: provider,
  endpoint: provider == 'imap'
      ? 'imaps://imap.example.test:1993'
      : 'https://mail.example.test/${provider == 'ews' ? 'EWS/Exchange.asmx' : 'v1'}',
  login: provider == 'ews' || provider == 'graph'
      ? '["scope","Writer@example.test"]'
      : 'Writer@example.test',
  sender: 'Writer@example.test',
);

Future<void> _press(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await pumpOutboxWidgets(tester);
}

Future<void> _show(
  WidgetTester tester,
  MemoryMailLocalAccounts store, {
  StudioMailDraftStoreFactory? open,
  bool Function()? isCurrent,
  MailProviderKind? provider,
  StudioStrings strings = _strings,
  Size size = const Size(1000, 850),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Directionality(
        textDirection: strings.language == StudioLanguage.ar
            ? TextDirection.rtl
            : TextDirection.ltr,
        child: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => Directionality(
                  textDirection: strings.language == StudioLanguage.ar
                      ? TextDirection.rtl
                      : TextDirection.ltr,
                  child: StudioMailLocalAccountsDialog(
                    strings: strings,
                    store: store,
                    isCurrent: isCurrent ?? () => true,
                    provider: provider,
                    draftStoreFactory: open,
                  ),
                ),
              ),
              child: const Text('Offline accounts'),
            ),
          ),
        ),
      ),
    ),
  );
  await _press(tester, find.text('Offline accounts'));
}

void main() {
  for (final provider in ['imap', 'ews', 'gmail', 'graph']) {
    testWidgets('$provider cached-mail button opens only the local mailbox', (
      tester,
    ) async {
      final identity = _identity(provider);
      final fixture = await awaitOutboxOperation(
        tester,
        SqliteOutboxFixture.create(identity),
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await awaitOutboxOperation(tester, fixture.close());
      });
      final directory = MemoryMailLocalAccounts()..seed(identity);
      await _show(tester, directory, open: fixture.open);
      await _press(
        tester,
        find.byKey(
          ValueKey('studio-mail-cached-account-${identity.account.value}'),
        ),
      );
      for (
        var i = 0;
        i < 100 && find.text(_strings.mailCacheEmpty).evaluate().isEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      final dialog = tester.widget<StudioMailCachedMailDialog>(
        find.byType(StudioMailCachedMailDialog),
      );
      expect(dialog.identity.account, identity.account);
      expect(find.text(_strings.mailCacheEmpty), findsOneWidget);
      expect(find.byType(StudioMailComposeDialog), findsNothing);
      expect(find.byType(StudioMailDraftsDialog), findsNothing);
      expect(fixture.adapters.single.selectionEpoch, 0);
      expect(directory.loads, 2);
      expect(directory.remembered, isEmpty);
      await _press(
        tester,
        find.byKey(const ValueKey('studio-mail-cache-close')),
      );
      expect(find.byType(StudioMailCachedMailDialog), findsNothing);
      expect(find.byType(ListTile), findsOneWidget);
    });
  }

  for (final cachedMail in [false, true]) {
    testWidgets(
      'registration refresh blocks stale ${cachedMail ? 'cache' : 'draft'} entry',
      (tester) async {
        final identity = _identity('imap');
        final directory = MemoryMailLocalAccounts()..seed(identity);
        directory.onLoad = (count) {
          if (count != 2) return;
          final old = directory.records.values.single;
          directory.records[old.id] = MailLocalAccountRecord(
            id: old.id,
            provider: old.provider,
            endpoint: old.endpoint,
            login: old.login,
            sender: old.sender,
            lastConnectedAt: old.lastConnectedAt,
            revision: old.revision + 1,
          );
        };
        var opens = 0;
        await _show(
          tester,
          directory,
          open: (_) async {
            opens++;
            throw StateError('must not acquire stale owner');
          },
        );
        await _press(
          tester,
          cachedMail
              ? find.byKey(
                  ValueKey(
                    'studio-mail-cached-account-${identity.account.value}',
                  ),
                )
              : find.byType(ListTile),
        );
        expect(opens, 0);
        expect(find.text(_strings.mailLocalAccountsFailed), findsOneWidget);
        expect(find.byType(StudioMailCachedMailDialog), findsNothing);
        expect(find.byType(StudioMailDraftsDialog), findsNothing);
      },
    );
  }

  for (final provider in ['imap', 'ews', 'gmail', 'graph']) {
    testWidgets(
      '$provider resumes the existing draft in save-only composition',
      (tester) async {
        final identity = _identity(provider);
        final fixture = await awaitOutboxOperation(
          tester,
          SqliteOutboxFixture.create(identity),
        );
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await awaitOutboxOperation(tester, fixture.close());
        });
        final seed = await awaitOutboxOperation(tester, fixture.openLoaded());
        await awaitOutboxOperation(
          tester,
          seed.save(
            const StudioMailDraft(
              to: 'reader@example.test',
              subject: 'Existing offline draft',
              body: 'Preserved',
            ),
            submissionUncertain: true,
          ),
        );
        await awaitOutboxOperation(tester, seed.close());
        final directory = MemoryMailLocalAccounts()..seed(identity);
        await _show(tester, directory, open: fixture.open);
        await _press(tester, find.byType(ListTile));
        for (
          var i = 0;
          i < 100 && find.text('Existing offline draft').evaluate().isEmpty;
          i++
        ) {
          await tester.pump(const Duration(milliseconds: 10));
        }
        await _press(tester, find.text('Existing offline draft'));
        final composer = tester.widget<StudioMailComposeDialog>(
          find.byType(StudioMailComposeDialog),
        );
        expect(composer.from, identity.sender);
        expect(composer.canSend, isFalse);
        expect(composer.onQueueDraft, isNull);
        expect(composer.previousSubmissionUncertain, isTrue);
        final subject = find.byWidgetPredicate(
          (widget) =>
              widget is TextField &&
              widget.decoration?.labelText == _strings.subject,
        );
        await tester.enterText(subject, 'Edited offline');
        await _press(tester, find.text(_strings.mailDraftSaveClose));
        final store = fixture.adapters.last;
        expect(
          (await awaitOutboxOperation(tester, store.load()))!.draft.subject,
          'Edited offline',
        );
        expect(directory.remembered, isEmpty);
      },
    );
  }

  testWidgets('provider filtering keeps equal sender accounts distinct', (
    tester,
  ) async {
    final directory = MemoryMailLocalAccounts();
    for (final provider in ['imap', 'ews', 'gmail', 'graph']) {
      directory.seed(_identity(provider));
    }
    await _show(tester, directory, provider: MailProviderKind.ews);
    expect(find.byType(ListTile), findsOneWidget);
    expect(find.textContaining('/EWS/Exchange.asmx'), findsOneWidget);
    expect(find.textContaining('Microsoft 365'), findsNothing);
  });

  testWidgets(
    'remove requires confirmation and only removes the selected shortcut',
    (tester) async {
      final directory = MemoryMailLocalAccounts()
        ..seed(_identity('imap'))
        ..seed(_identity('ews'));
      await _show(tester, directory);
      await _press(
        tester,
        find.byTooltip(_strings.mailLocalAccountRemove).first,
      );
      await _press(tester, find.text(_strings.cancel));
      expect(directory.records, hasLength(2));
      await _press(
        tester,
        find.byTooltip(_strings.mailLocalAccountRemove).first,
      );
      await _press(
        tester,
        find.widgetWithText(FilledButton, _strings.mailLocalAccountRemove),
      );
      expect(directory.records, hasLength(1));
      expect(directory.records.values.single.provider, MailProviderKind.ews);
    },
  );

  testWidgets(
    'a failed read exposes retry without treating the list as empty',
    (tester) async {
      final directory = MemoryMailLocalAccounts()
        ..seed(_identity('imap'))
        ..failLoad = true;
      await _show(tester, directory);
      expect(find.text(_strings.mailLocalAccountsFailed), findsOneWidget);
      expect(find.text(_strings.mailLocalAccountsEmpty), findsNothing);
      directory.failLoad = false;
      await _press(tester, find.text(_strings.refresh));
      expect(find.byType(ListTile), findsOneWidget);
    },
  );

  testWidgets('a removed or stale identity cannot acquire a draft store', (
    tester,
  ) async {
    final directory = MemoryMailLocalAccounts()..seed(_identity('imap'));
    directory.onLoad = (count) {
      if (count == 2) directory.records.clear();
    };
    var opens = 0;
    await _show(
      tester,
      directory,
      open: (_) async {
        opens++;
        throw StateError('must not open');
      },
    );
    await _press(tester, find.byType(ListTile));
    expect(opens, 0);
    expect(find.text(_strings.mailLocalAccountsFailed), findsOneWidget);
    expect(find.byType(StudioMailDraftsDialog), findsNothing);
  });

  testWidgets('a delayed read after owner invalidation is not adopted', (
    tester,
  ) async {
    final directory = MemoryMailLocalAccounts()
      ..seed(_identity('imap'))
      ..loadGate = Completer<void>();
    var current = true;
    await _show(tester, directory, isCurrent: () => current);
    current = false;
    directory.loadGate!.complete();
    await pumpOutboxWidgets(tester);
    expect(find.byType(ListTile), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final language in StudioLanguage.values) {
    testWidgets(
      'compact ${language.name} directory keeps controls visible and wraps account text',
      (tester) async {
        final directory = MemoryMailLocalAccounts()
          ..seed(_identity('imap'))
          ..seed(_identity('ews'));
        await _show(
          tester,
          directory,
          strings: StudioStrings(language),
          size: const Size(420, 820),
        );
        expect(find.byType(ListTile), findsNWidgets(2));
        expect(tester.takeException(), isNull);
        expect(find.text(StudioStrings(language).close), findsOneWidget);
      },
    );
  }
}
