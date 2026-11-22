import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:quds_office_studio/studio_mail_account_navigation.dart';
import 'package:quds_office_studio/studio_mail_account_navigation_strings.dart';
import 'package:quds_office_studio/studio_mail_draft_store.dart';
import 'package:quds_office_studio/studio_mail_local_accounts.dart';
import 'package:quds_office_studio/studio_strings.dart';

const _strings = StudioStrings(StudioLanguage.en);
Finder _key(String suffix) =>
    find.byKey(ValueKey('studio-mail-account-navigation-$suffix'));
Finder _row(MailLocalAccountRecord record) =>
    find.byKey(ValueKey('studio-mail-navigation-account-${record.id}'));

MailLocalAccountRecord _record(String provider, {int revision = 1}) {
  final sender = '$provider@example.test';
  final identity = StudioMailDraftAccount(
    provider: provider,
    endpoint: switch (provider) {
      'imap' => 'imaps://imap.example.test:993',
      'ews' => 'https://exchange.example.test/EWS/Exchange.asmx',
      'gmail' => 'https://gmail.googleapis.com/gmail/v1',
      'graph' => 'https://graph.microsoft.com/v1.0',
      _ => throw StateError('Unknown fixture provider'),
    },
    login: switch (provider) {
      'ews' => jsonEncode(['DOMAIN', 'ExchangeLogin']),
      'graph' => jsonEncode(['common', sender]),
      _ => sender,
    },
    sender: sender,
  );
  return MailLocalAccountRecord(
    id: identity.account.value,
    provider: identity.provider,
    endpoint: identity.endpoint,
    login: identity.login,
    sender: identity.sender,
    lastConnectedAt: DateTime.utc(2026, 11, 22),
    revision: revision,
  );
}

final class _Directory implements StudioMailLocalAccountStore {
  _Directory(this.rows);

  List<MailLocalAccountRecord> rows;
  Completer<void>? gate;
  bool fail = false;
  int loads = 0;
  int writes = 0;

  @override
  Future<List<MailLocalAccountRecord>> load() async {
    loads++;
    await gate?.future;
    if (fail) throw StateError('private-directory-failure-detail');
    return List.unmodifiable(rows);
  }

  @override
  Future<void> remember(StudioMailDraftAccount identity) async => writes++;

  @override
  Future<void> forget(MailLocalAccountRecord record) async => writes++;
}

final class _Result {
  int completions = 0;
  StudioMailAccountNavigationTarget? value;
}

Future<void> _press(
  WidgetTester tester,
  Finder finder, {
  bool settle = true,
}) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pump();
  if (settle) await tester.pumpAndSettle();
}

Future<_Result> _show(
  WidgetTester tester,
  _Directory directory, {
  StudioStrings strings = _strings,
  StudioMailDraftAccount? currentAccount,
  bool Function()? isCurrent,
  Size size = const Size(900, 850),
  bool settle = true,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final result = _Result();
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              result.value = await showStudioMailAccountNavigation(
                context: context,
                strings: strings,
                store: directory,
                isCurrent: isCurrent ?? () => true,
                currentAccount: currentAccount,
              );
              result.completions++;
            },
            child: const Text('Choose'),
          ),
        ),
      ),
    ),
  );
  await _press(tester, find.text('Choose'), settle: settle);
  return result;
}

void main() {
  testWidgets('all providers are visible and the current account is disabled', (
    tester,
  ) async {
    final rows = ['imap', 'ews', 'gmail', 'graph'].map(_record).toList();
    final directory = _Directory(rows);
    final result = await _show(
      tester,
      directory,
      currentAccount: studioMailLocalAccountIdentity(rows.first),
    );
    for (final record in rows) {
      expect(_row(record), findsOneWidget);
      expect(find.text(record.id), findsNothing);
    }
    expect(tester.widget<ListTile>(_row(rows.first)).onTap, isNull);
    expect(tester.widget<FilledButton>(_key('continue')).onPressed, isNull);
    expect(
      find.textContaining(_strings.mailAccountNavigationCurrent),
      findsOneWidget,
    );
    await _press(tester, _row(rows[2]));
    expect(result.completions, 0);
    expect(directory.loads, 1);
    await _press(tester, _key('continue'));
    expect(result.completions, 1);
    expect(result.value!.record, same(rows[2]));
    expect(directory.loads, 2);
    expect(directory.writes, 0);
  });

  for (final revised in [false, true]) {
    testWidgets(
      '${revised ? 'revision change' : 'removal'} requires a refresh',
      (tester) async {
        final row = _record('ews');
        final directory = _Directory([row]);
        final result = await _show(tester, directory);
        await _press(tester, _row(row));
        directory.rows = revised ? [_record('ews', revision: 2)] : [];
        await _press(tester, _key('continue'));
        expect(result.completions, 0);
        expect(
          find.text(_strings.mailAccountNavigationChanged),
          findsOneWidget,
        );
        expect(tester.widget<FilledButton>(_key('continue')).onPressed, isNull);
        await _press(tester, _key('refresh'));
        expect(find.text(_strings.mailAccountNavigationChanged), findsNothing);
        if (revised) {
          await _press(tester, _row(directory.rows.single));
          await _press(tester, _key('continue'));
          expect(result.value!.record.revision, 2);
        } else {
          expect(
            find.text(_strings.mailAccountNavigationEmpty),
            findsOneWidget,
          );
          await _press(tester, _key('cancel'));
          expect(result.value, isNull);
        }
        expect(result.completions, 1);
        expect(directory.writes, 0);
      },
    );
  }

  testWidgets(
    'directory failure is visible and refresh recovers without writes',
    (tester) async {
      final row = _record('graph');
      final directory = _Directory([row])..fail = true;
      final result = await _show(tester, directory);
      expect(find.text(_strings.mailAccountNavigationFailed), findsOneWidget);
      expect(
        find.textContaining('private-directory-failure-detail'),
        findsNothing,
      );
      expect(_row(row), findsNothing);
      directory.fail = false;
      await _press(tester, _key('refresh'));
      expect(_row(row), findsOneWidget);
      await _press(tester, _row(row));
      await _press(tester, _key('continue'));
      expect(result.value!.record.id, row.id);
      expect(directory.writes, 0);
    },
  );

  testWidgets(
    'duplicate directory rows are rejected rather than partly shown',
    (tester) async {
      final row = _record('gmail');
      await _show(tester, _Directory([row, row]));
      expect(find.text(_strings.mailAccountNavigationFailed), findsOneWidget);
      expect(find.byType(ListTile), findsNothing);
      expect(tester.widget<FilledButton>(_key('continue')).onPressed, isNull);
      await _press(tester, _key('cancel'));
    },
  );

  testWidgets('cancel while validation is pending suppresses its late result', (
    tester,
  ) async {
    final row = _record('imap');
    final directory = _Directory([row]);
    final result = await _show(tester, directory);
    await _press(tester, _row(row));
    directory.gate = Completer<void>();
    await _press(tester, _key('continue'), settle: false);
    expect(directory.loads, 2);
    await _press(tester, _key('cancel'));
    expect(result.completions, 1);
    expect(result.value, isNull);
    directory.gate!.complete();
    await tester.pumpAndSettle();
    expect(result.completions, 1);
    expect(result.value, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('retired parent cannot receive a pending selected target', (
    tester,
  ) async {
    final row = _record('ews');
    final directory = _Directory([row]);
    var current = true;
    final result = await _show(tester, directory, isCurrent: () => current);
    await _press(tester, _row(row));
    directory.gate = Completer<void>();
    await _press(tester, _key('continue'), settle: false);
    current = false;
    directory.gate!.complete();
    await tester.pump();
    expect(result.completions, 0);
    await _press(tester, _key('cancel'));
    expect(result.completions, 1);
    expect(result.value, isNull);
    expect(directory.writes, 0);
  });

  testWidgets('cancel during initial loading drains without adopting rows', (
    tester,
  ) async {
    final directory = _Directory([_record('graph')])..gate = Completer<void>();
    final result = await _show(tester, directory, settle: false);
    await _press(tester, _key('cancel'));
    directory.gate!.complete();
    await tester.pumpAndSettle();
    expect(result.value, isNull);
    expect(result.completions, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('stale parent never opens a chooser or reads the directory', (
    tester,
  ) async {
    final directory = _Directory([_record('gmail')]);
    final result = await _show(tester, directory, isCurrent: () => false);
    expect(result.completions, 1);
    expect(result.value, isNull);
    expect(directory.loads, 0);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('keyboard can choose a target before explicit continue', (
    tester,
  ) async {
    final row = _record('gmail');
    final directory = _Directory([row]);
    final result = await _show(tester, directory);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(tester.widget<ListTile>(_row(row)).selected, isTrue);
    expect(result.completions, 0);
    expect(directory.loads, 1);
    await _press(tester, _key('continue'));
    expect(result.value!.record.id, row.id);
  });

  for (final language in StudioLanguage.values) {
    testWidgets('${language.name} compact chooser remains usable', (
      tester,
    ) async {
      final strings = StudioStrings(language);
      final directory = _Directory([
        for (final provider in ['imap', 'ews', 'gmail', 'graph'])
          _record(provider),
      ]);
      final result = await _show(
        tester,
        directory,
        strings: strings,
        size: const Size(360, 740),
      );
      expect(find.text(strings.mailAccountNavigationTitle), findsOneWidget);
      expect(
        Directionality.of(tester.element(find.byType(AlertDialog))),
        language == StudioLanguage.ar ? TextDirection.rtl : TextDirection.ltr,
      );
      await _press(tester, _row(directory.rows.last));
      await _press(tester, _key('continue'));
      expect(result.value!.record.provider.name, 'graph');
      expect(tester.takeException(), isNull);
    });
  }
}
