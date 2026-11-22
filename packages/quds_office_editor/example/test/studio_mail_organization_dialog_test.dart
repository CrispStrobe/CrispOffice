import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_office_studio/studio_mail_mutation_strings.dart';
import 'package:quds_office_studio/studio_mail_organization_dialog.dart';
import 'package:quds_office_studio/studio_strings.dart';

final _account = MailAccountId(
  'account',
  profile: MailProfileId('profile', hostId: 'organization-dialog-test'),
);

MailMailbox _folder(String id, String name, {MailAccountId? account}) =>
    MailMailbox(
      id: MailMailboxId(id, account: account ?? _account),
      displayName: name,
    );

Finder _key(String key) => find.byKey(ValueKey(key));

Future<void> _show(
  WidgetTester tester,
  Future<void> Function(BuildContext context) action, {
  double scale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => action(context),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'folder selection requires Apply and freezes exact destinations',
    (tester) async {
      const strings = StudioStrings(StudioLanguage.en);
      final source = _folder('inbox-exact-id', 'Inbox');
      final destinations = [
        source,
        _folder('archive-a', 'Archive'),
        _folder('archive-b', 'Archive'),
      ];
      MailMailboxId? result;
      var completed = false;
      await _show(tester, (context) async {
        result = await showStudioMailMoveSelection(
          context,
          strings: strings,
          count: 2,
          accountLabel: 'reader@example.test',
          source: source,
          destinations: destinations,
        );
        completed = true;
      });
      destinations.clear();
      expect(find.text('Selected messages: 2'), findsOneWidget);
      expect(find.text('reader@example.test'), findsOneWidget);
      expect(find.text('inbox-exact-id'), findsOneWidget);
      expect(find.text('Archive'), findsNWidgets(2));
      expect(find.text('archive-a'), findsOneWidget);
      expect(find.text('archive-b'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(_key('studio-mail-move-apply')).onPressed,
        isNull,
      );
      await tester.tap(_key('studio-mail-move-destination-1'));
      await tester.pump();
      expect(completed, isFalse);
      await tester.tap(_key('studio-mail-move-apply'));
      await tester.pumpAndSettle();
      expect(result, _folder('archive-b', 'Archive').id);
      expect(completed, isTrue);
    },
  );

  testWidgets('foreign-account and source folders cannot be chosen', (
    tester,
  ) async {
    final source = _folder('inbox', 'Inbox');
    final foreign = MailAccountId('other', profile: _account.profile);
    await _show(tester, (context) async {
      await showStudioMailMoveSelection(
        context,
        strings: const StudioStrings(StudioLanguage.en),
        count: 2,
        accountLabel: 'reader@example.test',
        source: source,
        destinations: [
          source,
          _folder('archive', 'Foreign', account: foreign),
        ],
      );
    });
    expect(find.text('Foreign'), findsNothing);
    expect(_key('studio-mail-move-destination-0'), findsNothing);
    expect(
      tester.widget<FilledButton>(_key('studio-mail-move-apply')).onPressed,
      isNull,
    );
    await tester.tap(_key('studio-mail-organization-cancel'));
    await tester.pumpAndSettle();
  });

  for (final language in StudioLanguage.values) {
    for (final moving in [true, false]) {
      testWidgets(
        '${language.name} ${moving ? 'move' : 'delete'} fits compact enlarged text and cancels',
        (tester) async {
          tester.view
            ..physicalSize = const Size(360, 640)
            ..devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final strings = StudioStrings(language);
          final source = _folder(
            'inbox/retained/project-with-a-long-folder-identifier',
            'Research and correspondence / Forschung und Korrespondenz / البحث',
          );
          var completed = false;
          await _show(tester, (context) async {
            if (moving) {
              expect(
                await showStudioMailMoveSelection(
                  context,
                  strings: strings,
                  count: 37,
                  accountLabel: 'long.account.name@example.test',
                  source: source,
                  destinations: [
                    _folder('archive/exact-id', 'Archive / الأرشيف'),
                  ],
                ),
                isNull,
              );
            } else {
              expect(
                await confirmStudioMailDeleteSelection(
                  context,
                  strings: strings,
                  count: 37,
                  accountLabel: 'long.account.name@example.test',
                  source: source,
                  provider: MailProviderKind.imap,
                ),
                isFalse,
              );
            }
            completed = true;
          }, scale: 1.8);
          final dialog = _key(
            moving
                ? 'studio-mail-move-selection-dialog'
                : 'studio-mail-delete-selection-dialog',
          );
          expect(
            Directionality.of(tester.element(dialog)),
            language == StudioLanguage.ar
                ? TextDirection.rtl
                : TextDirection.ltr,
          );
          expect(find.text(strings.mailOrganizationCount(37)), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.ensureVisible(_key('studio-mail-organization-cancel'));
          await tester.tap(_key('studio-mail-organization-cancel'));
          await tester.pumpAndSettle();
          expect(completed, isTrue);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final provider in [
    MailProviderKind.imap,
    MailProviderKind.ews,
    MailProviderKind.graph,
    MailProviderKind.gmail,
  ]) {
    testWidgets('${provider.name} confirms its distinct delete meaning', (
      tester,
    ) async {
      const strings = StudioStrings(StudioLanguage.en);
      bool? result;
      await _show(tester, (context) async {
        result = await confirmStudioMailDeleteSelection(
          context,
          strings: strings,
          count: 2,
          accountLabel: 'reader@example.test',
          source: _folder('inbox', 'Inbox'),
          provider: provider,
        );
      });
      expect(
        find.text(strings.mailOrganizationDeleteExplanation(provider)),
        findsOneWidget,
      );
      expect(result, isNull);
      await tester.tap(_key('studio-mail-delete-apply'));
      await tester.pumpAndSettle();
      expect(result, isTrue);
    });
  }
}
