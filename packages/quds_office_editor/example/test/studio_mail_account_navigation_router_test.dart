import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_office_studio/studio_mail_account_navigation.dart';
import 'package:quds_office_studio/studio_mail_draft_store.dart';
import 'package:quds_office_studio/studio_mail_native.dart';
import 'package:quds_office_studio/studio_strings.dart';

import 'support/mail_credentials.dart';
import 'support/mail_local_accounts.dart';

const _strings = StudioStrings(StudioLanguage.en);

StudioMailDraftAccount _identity(String provider) => StudioMailDraftAccount(
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
    'graph' => jsonEncode(['common', '$provider@example.test']),
    _ => '$provider@example.test',
  },
  sender: '$provider@example.test',
);

final class _RouteEntry {
  const _RouteEntry(this.route, this.provider, this.target, this.navigate);

  final ModalRoute<Object?> route;
  final MailProviderKind provider;
  final StudioMailAccountNavigationTarget? target;
  final ValueChanged<StudioMailAccountNavigationTarget> navigate;
}

final class _RouterFixture {
  _RouterFixture() {
    for (final provider in ['imap', 'ews', 'gmail', 'graph']) {
      directory.seed(_identity(provider));
    }
  }

  final directory = MemoryMailLocalAccounts();
  final routes = <_RouteEntry>[];
  int clientCreations = 0;
  int storeOpens = 0;

  StudioMailAccountNavigationTarget target(String provider) =>
      StudioMailAccountNavigationTarget.fromRecord(
        directory.records.values.singleWhere(
          (record) => record.provider.name == provider,
        ),
      );

  Widget destination(
    BuildContext context,
    MailProviderKind provider,
    StudioMailAccountNavigationTarget? target,
    ValueChanged<StudioMailAccountNavigationTarget> navigate,
  ) {
    final route = ModalRoute.of<Object?>(context)!;
    if (!routes.any((entry) => identical(entry.route, route))) {
      routes.add(_RouteEntry(route, provider, target, navigate));
    }
    return Dialog.fullscreen(
      child: Scaffold(
        body: Column(
          children: [
            Text('Provider setup: ${provider.name}'),
            TextButton(
              key: const ValueKey('fixture-close-provider'),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close provider setup'),
            ),
          ],
        ),
      ),
    );
  }
}

Finder _key(String value) => find.byKey(ValueKey(value));
Finder get _email => find.byWidgetPredicate(
  (widget) =>
      widget is TextField &&
      widget.decoration?.labelText == _strings.emailAddress,
);

Future<void> _pump(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump();
}

Future<void> _press(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await _pump(tester);
}

Future<void> _show(WidgetTester tester, _RouterFixture fixture) async {
  await tester.binding.setSurfaceSize(const Size(1280, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: StudioMailDialog(
        strings: _strings,
        credentialStore: SessionMailCredentials(),
        localAccountStore: fixture.directory,
        autoConnectSavedAccount: false,
        accountDestinationBuilder: fixture.destination,
        clientFactory: (_) {
          fixture.clientCreations++;
          throw StateError('Account navigation cannot connect a provider');
        },
        draftStoreFactory: (_) async {
          fixture.storeOpens++;
          throw StateError('Disconnected routing cannot acquire an account');
        },
      ),
    ),
  );
  await _pump(tester);
}

void main() {
  testWidgets('duplicate and delayed callbacks cannot pop a newer provider', (
    tester,
  ) async {
    final fixture = _RouterFixture();
    await _show(tester, fixture);
    await _press(tester, _key('studio-mail-open-ews'));
    expect(fixture.routes, hasLength(1));
    final first = fixture.routes.single;
    expect(first.provider, MailProviderKind.ews);

    first.navigate(fixture.target('gmail'));
    // A duplicate arrives before the first route finishes its exit animation.
    first.navigate(fixture.target('graph'));
    await _pump(tester);
    expect(fixture.routes, hasLength(2));
    final second = fixture.routes.last;
    expect(second.provider, MailProviderKind.gmail);
    expect(second.target!.identity.account, _identity('gmail').account);
    expect(second.route.isCurrent, isTrue);

    // The old callback is retained by a host operation that finishes later.
    first.navigate(fixture.target('graph'));
    await _pump(tester);
    expect(fixture.routes, hasLength(2));
    expect(second.route.isCurrent, isTrue);
    expect(find.text('Provider setup: gmail'), findsOneWidget);

    second.navigate(fixture.target('imap'));
    await _pump(tester);
    expect(find.text('Provider setup: gmail'), findsNothing);
    expect(
      tester.widget<Text>(_key('studio-mail-navigation-target')).data,
      'imap@example.test',
    );
    // Neither completed provider route may navigate the restored native host.
    first.navigate(fixture.target('graph'));
    second.navigate(fixture.target('ews'));
    await _pump(tester);
    expect(fixture.routes, hasLength(2));
    expect(
      tester.widget<Text>(_key('studio-mail-navigation-target')).data,
      'imap@example.test',
    );
    expect(fixture.clientCreations, 0);
    expect(fixture.storeOpens, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('callback from a normally closed provider route stays retired', (
    tester,
  ) async {
    final fixture = _RouterFixture();
    await _show(tester, fixture);
    await _press(tester, _key('studio-mail-open-ews'));
    final previous = fixture.routes.single;
    await _press(tester, _key('fixture-close-provider'));
    await _press(tester, _key('studio-mail-open-gmail'));
    final current = fixture.routes.last;
    expect(current.provider, MailProviderKind.gmail);
    previous.navigate(fixture.target('graph'));
    await _pump(tester);
    expect(current.route.isCurrent, isTrue);
    expect(fixture.routes, hasLength(2));
    expect(find.text('Provider setup: gmail'), findsOneWidget);
    await _press(tester, _key('fixture-close-provider'));
    expect(tester.takeException(), isNull);
    expect(fixture.clientCreations, 0);
    expect(fixture.storeOpens, 0);
  });

  testWidgets(
    'setup keyboard input is retired during an async account change',
    (tester) async {
      final fixture = _RouterFixture();
      final validated = Completer<void>();
      // The chooser reads once, then rereads on Continue. Hold the root's
      // independent third read after the chooser route has closed.
      fixture.directory.onLoad = (count) {
        if (count == 3) fixture.directory.loadGate = validated;
      };
      await _show(tester, fixture);
      await tester.enterText(_email, 'unfinished@example.test');
      final editable = tester.widget<EditableText>(
        find.descendant(of: _email, matching: find.byType(EditableText)),
      );
      final focus = editable.focusNode;
      expect(focus.hasFocus, isTrue);
      await _press(tester, _key('studio-mail-navigate-account'));
      final target = fixture.target('imap');
      await _press(
        tester,
        _key('studio-mail-navigation-account-${target.record.id}'),
      );
      await _press(tester, _key('studio-mail-account-navigation-continue'));
      expect(fixture.directory.loads, 3);
      expect(focus.canRequestFocus, isFalse);
      focus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
      await tester.pump();
      expect(focus.hasFocus, isFalse);
      expect(editable.controller.text, 'unfinished@example.test');

      validated.complete();
      await _pump(tester);
      expect(
        tester.widget<Text>(_key('studio-mail-navigation-target')).data,
        'imap@example.test',
      );
      expect(
        tester.widget<TextField>(_email).controller!.text,
        'imap@example.test',
      );
      expect(fixture.clientCreations, 0);
      expect(fixture.storeOpens, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
