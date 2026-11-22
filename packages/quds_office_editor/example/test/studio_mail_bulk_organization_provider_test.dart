import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_transport/quds_mail_transport.dart';
import 'package:quds_mail_ui/quds_mail_ui.dart';
import 'package:quds_office_studio/studio_mail_bulk_status.dart';
import 'package:quds_office_studio/studio_mail_ews.dart';
import 'package:quds_office_studio/studio_mail_mutation_strings.dart';
import 'package:quds_office_studio/studio_strings.dart';

import 'support/mail_draft_store.dart';

const _strings = StudioStrings(StudioLanguage.en);
const _success = MailSuccess<MailUnit>(MailUnit.value);
const _uncertain = MailFailure<MailUnit>(
  MailProblem(MailProblemCode.unavailable),
);

class _Provider extends Fake implements MailProvider {
  _Provider(this.account, this.kind);

  @override
  final MailAccountId account;
  final MailProviderKind kind;
  final commands = <MailOperation>[];
  final leases = <MailOperationLease>[];
  FutureOr<MailResult<MailUnit>> Function(MailOperation, int)? respond;
  bool allowMembership = true;
  bool advertiseGmailMove = false;
  int headerReads = 0;
  int bodyReads = 0;

  MailMailboxId box(String id) => MailMailboxId(id, account: account);

  MailOpaqueIdentity remote(String id) =>
      MailOpaqueIdentity(account: account, provider: kind, value: 'remote-$id');

  List<MailHeaderRecord> get headers => [
    for (final id in ['one', 'two', 'three'])
      MailHeaderRecord(
        id: MailMessageId(id),
        remote: remote(id),
        envelope: MailEnvelope(subject: 'Selected subject $id'),
        flags: const MailMessageFlags(),
      ),
  ];

  @override
  Future<MailResult<MailCapabilities>> capabilities(
    MailOperationLease lease,
  ) async => MailSuccess(
    MailCapabilities([
      MailCapability.mail,
      MailCapability.folders,
      if (allowMembership) MailCapability.delete,
      if (allowMembership &&
          (kind != MailProviderKind.gmail || advertiseGmailMove))
        MailCapability.move,
    ]),
  );

  @override
  Future<MailResult<List<MailMailbox>>> listMailboxes(
    MailOperationLease lease,
  ) async => MailSuccess([
    MailMailbox(id: box('inbox-exact'), displayName: 'Inbox'),
    MailMailbox(id: box('archive-exact'), displayName: 'Archive'),
  ]);

  @override
  Future<MailResult<MailHeaderPage>> fetchHeaders(
    MailMailboxId mailbox, {
    MailCursor? cursor,
    required int limit,
    required MailOperationLease lease,
  }) async {
    headerReads++;
    return MailSuccess(MailHeaderPage(messages: headers));
  }

  @override
  Future<MailResult<MailMessage>> fetchMessage(
    MailRemoteIdentity identity, {
    required MailReadBudget budget,
    required MailOperationLease lease,
  }) async {
    bodyReads++;
    final header = headers.firstWhere((item) => item.remote == identity);
    return MailSuccess(
      MailMessage(
        raw: MailBytes(
          Uint8List.fromList('Subject: synthetic\r\n\r\nbody'.codeUnits),
        ),
        envelope: header.envelope,
        body: const MailBody(plainText: 'Independent open reader'),
        localId: header.id,
        remoteIdentity: identity,
      ),
    );
  }

  @override
  Future<MailResult<MailUnit>> apply(
    MailOperation operation,
    MailOperationLease lease,
  ) async {
    lease.checkCurrent();
    commands.add(operation);
    leases.add(lease);
    return respond == null
        ? _success
        : await respond!(operation, commands.length);
  }
}

final class _EwsProvider extends _Provider implements MailEwsProvider {
  _EwsProvider(MailEwsConfiguration configuration)
    : super(configuration.account, MailProviderKind.ews);
}

final class _CloudProvider extends _Provider implements MailCloudProvider {
  _CloudProvider(MailCloudConfiguration configuration)
    : super(
        configuration.account,
        configuration.service == MailCloudService.gmail
            ? MailProviderKind.gmail
            : MailProviderKind.graph,
      );

  @override
  void dispose() {}
}

final class _Tokens extends Fake implements MailCloudTokenSource {
  @override
  void dispose() {}
}

final class _Harness {
  _Harness(this.kind);
  final MailProviderKind kind;
  final drafts = MemoryStudioMailDrafts();
  final providers = <_Provider>[];
  void Function(_Provider)? configure;
  _Provider get provider => providers.last;
  MailBulkFlagAction get action => kind == MailProviderKind.gmail
      ? MailBulkFlagAction.delete
      : MailBulkFlagAction.move;

  Widget dialog() {
    if (kind == MailProviderKind.ews) {
      return StudioMailEwsDialog(
        strings: _strings,
        draftStoreFactory: drafts.open,
        providerFactory: (configuration, credentials) {
          final provider = _EwsProvider(configuration);
          configure?.call(provider);
          providers.add(provider);
          return provider;
        },
      );
    }
    return StudioMailEwsDialog.cloud(
      strings: _strings,
      service: kind == MailProviderKind.gmail
          ? MailCloudService.gmail
          : MailCloudService.microsoft365,
      initialClientId: 'synthetic-desktop-client',
      draftStoreFactory: drafts.open,
      cloudAuthorizer: ({
        required configuration,
        required account,
        required openBrowser,
        required lease,
        log,
      }) async => MailSuccess(_Tokens()),
      cloudProviderFactory:
          ({required configuration, required tokenSource, log}) {
            final provider = _CloudProvider(configuration);
            configure?.call(provider);
            providers.add(provider);
            return provider;
          },
    );
  }
}

Finder _key(String key) => find.byKey(ValueKey(key));
MailMessageList _list(WidgetTester tester) =>
    tester.widget(find.byType(MailMessageList));
StudioMailBulkStatus _status(WidgetTester tester) =>
    tester.widget(find.byType(StudioMailBulkStatus));

Future<void> _pump(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump();
}

Future<void> _connect(WidgetTester tester, MailProviderKind kind) async {
  if (kind == MailProviderKind.ews) {
    await tester.enterText(
      _key('ews-endpoint'),
      'https://mail.example.test/EWS/Exchange.asmx',
    );
    await tester.enterText(_key('ews-mailbox'), 'reader@example.test');
    await tester.enterText(_key('ews-login'), 'reader');
    await tester.enterText(_key('ews-password'), 'synthetic-password');
  } else {
    await tester.enterText(_key('cloud-mailbox'), 'reader@example.test');
  }
  final connect = _key(
    kind == MailProviderKind.ews ? 'ews-connect' : 'cloud-connect',
  );
  await tester.ensureVisible(connect);
  await tester.tap(connect);
  await _pump(tester);
  expect(find.byType(MailMessageList), findsOneWidget);
}

Future<void> _show(WidgetTester tester, _Harness harness) async {
  tester.view
    ..physicalSize = const Size(1400, 1000)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(home: harness.dialog()));
  await _pump(tester);
  await _connect(tester, harness.kind);
}

Future<void> _start(
  WidgetTester tester,
  MailBulkFlagAction action, {
  List<String>? ids,
}) async {
  final list = _list(tester);
  list.onBulkAction!(action, ids ?? list.items.map((item) => item.id).toList());
  await _pump(tester);
}

Future<void> _confirm(WidgetTester tester, MailBulkFlagAction action) async {
  if (action == MailBulkFlagAction.move) {
    await tester.tap(_key('studio-mail-move-destination-0'));
    await tester.pump();
    await tester.tap(_key('studio-mail-move-apply'));
  } else {
    await tester.tap(_key('studio-mail-delete-apply'));
  }
  await _pump(tester);
}

void _counts(
  WidgetTester tester,
  int confirmed,
  int failed,
  int uncertain,
  int unattempted,
) {
  final report = _status(tester).report;
  expect(report.confirmedCount, confirmed);
  expect(report.failedCount, failed);
  expect(report.uncertainCount, uncertain);
  expect(report.unattemptedCount, unattempted);
}

void main() {
  for (final kind in [
    MailProviderKind.ews,
    MailProviderKind.graph,
    MailProviderKind.gmail,
  ]) {
    testWidgets(
      '${kind.name}: review freezes a reversed selection before dispatch',
      (tester) async {
        final harness = _Harness(kind);
        await _show(tester, harness);
        final ids = ['ews-message-three', 'ews-message-one'];
        _list(tester).onBulkAction!(harness.action, ids);
        ids
          ..clear()
          ..add('ews-message-two');
        await _pump(tester);
        expect(harness.provider.commands, isEmpty);
        expect(find.text(_strings.mailOrganizationCount(2)), findsOneWidget);
        expect(find.text('reader@example.test'), findsWidgets);
        expect(find.text('inbox-exact'), findsOneWidget);
        if (kind != MailProviderKind.gmail) {
          expect(find.text('archive-exact'), findsOneWidget);
        }
        await _confirm(tester, harness.action);
        final commands = harness.provider.commands;
        expect(commands.map((command) => command.message), [
          harness.provider.remote('three'),
          harness.provider.remote('one'),
        ]);
        expect(commands.map((command) => command.id).toSet(), hasLength(2));
        if (kind == MailProviderKind.gmail) {
          expect(commands, everyElement(isA<MailDelete>()));
        } else {
          expect(commands, everyElement(isA<MailMove>()));
          expect(
            commands.cast<MailMove>().map((command) => command.destination),
            [
              harness.provider.box('archive-exact'),
              harness.provider.box('archive-exact'),
            ],
          );
        }
        expect(_list(tester).items.map((item) => item.id), ['ews-message-two']);
        expect(_list(tester).bulkActionsEnabled, isFalse);
        expect(harness.provider.bodyReads, 0);
        expect(harness.provider.headerReads, 1);
        _counts(tester, 2, 0, 0, 0);
      },
    );

    testWidgets('${kind.name}: cancelling review sends no command', (
      tester,
    ) async {
      final harness = _Harness(kind);
      await _show(tester, harness);
      await _start(tester, harness.action);
      await tester.tap(_key('studio-mail-organization-cancel'));
      await _pump(tester);
      expect(harness.provider.commands, isEmpty);
      expect(_list(tester).items, hasLength(3));
      expect(_list(tester).busy, isFalse);
      expect(_list(tester).bulkActionsEnabled, isTrue);
    });

    testWidgets('${kind.name}: uncertain second result stops the frozen tail', (
      tester,
    ) async {
      final harness = _Harness(kind);
      harness.configure = (provider) {
        provider.respond = (_, index) => index == 1 ? _success : _uncertain;
      };
      await _show(tester, harness);
      await _start(tester, harness.action);
      await _confirm(tester, harness.action);
      expect(harness.provider.commands, hasLength(2));
      _counts(tester, 1, 0, 1, 1);
      expect(
        _status(tester).report.stopReason,
        MailBulkFlagStopReason.uncertain,
      );
      expect(_list(tester).items.map((item) => item.id), [
        'ews-message-two',
        'ews-message-three',
      ]);
      expect(_list(tester).bulkActionsEnabled, isFalse);
      await _start(tester, harness.action);
      expect(harness.provider.commands, hasLength(2));
      expect(_key('studio-mail-move-selection-dialog'), findsNothing);
      expect(_key('studio-mail-delete-selection-dialog'), findsNothing);
    });

    testWidgets(
      '${kind.name}: Stop settles one in-flight command without replay',
      (tester) async {
        final gate = Completer<MailResult<MailUnit>>();
        final harness = _Harness(kind);
        harness.configure = (provider) =>
            provider.respond = (_, _) => gate.future;
        await _show(tester, harness);
        await _start(tester, harness.action);
        await _confirm(tester, harness.action);
        expect(harness.provider.commands, hasLength(1));
        _status(tester).onStop!();
        expect(harness.provider.leases.single.isCurrent, isTrue);
        gate.complete(_success);
        await _pump(tester);
        _counts(tester, 1, 0, 0, 2);
        expect(
          _status(tester).report.stopReason,
          MailBulkFlagStopReason.cancelled,
        );
        expect(harness.provider.commands, hasLength(1));
        expect(_list(tester).busy, isFalse);
      },
    );

    testWidgets(
      '${kind.name}: folder ABA rejects an old organization callback',
      (tester) async {
        final harness = _Harness(kind);
        await _show(tester, harness);
        final old = _list(tester).onBulkAction!;
        final ids = _list(tester).items.map((item) => item.id).toList();
        await tester.tap(find.text('Archive'));
        await _pump(tester);
        await tester.tap(find.text('Inbox'));
        await _pump(tester);
        old(harness.action, ids);
        await _pump(tester);
        expect(harness.provider.commands, isEmpty);
        expect(_key('studio-mail-move-selection-dialog'), findsNothing);
        expect(_key('studio-mail-delete-selection-dialog'), findsNothing);
        expect(harness.provider.headerReads, 3);
      },
    );

    testWidgets(
      '${kind.name}: an old confirmation cannot enter a new session',
      (tester) async {
        final harness = _Harness(kind);
        await _show(tester, harness);
        final previous = harness.provider;
        final disconnect = tester
            .widget<IconButton>(find.byTooltip(_strings.disconnect))
            .onPressed!;
        await _start(tester, harness.action);
        // A previously captured host disconnect callback invalidates the exact
        // session even while the modal review prevents ordinary navigation.
        disconnect();
        await tester.pump();
        await _confirm(tester, harness.action);
        expect(previous.commands, isEmpty);
        await _connect(tester, kind);
        expect(harness.provider, isNot(same(previous)));
        expect(harness.provider.commands, isEmpty);
        expect(_list(tester).items, hasLength(3));
        expect(_list(tester).busy, isFalse);
      },
    );

    testWidgets(
      '${kind.name}: unrelated open reader survives bulk organization',
      (tester) async {
        final harness = _Harness(kind);
        await _show(tester, harness);
        _list(tester).onOpen('ews-message-three');
        await _pump(tester);
        final reader = tester
            .widget<MailMessageView>(find.byType(MailMessageView))
            .controller;
        await _start(
          tester,
          harness.action,
          ids: ['ews-message-one', 'ews-message-two'],
        );
        await _confirm(tester, harness.action);
        expect(_list(tester).selectedId, 'ews-message-three');
        expect(
          tester
              .widget<MailMessageView>(find.byType(MailMessageView))
              .controller,
          same(reader),
        );
        expect(harness.provider.bodyReads, 1);
        _counts(tester, 2, 0, 0, 0);
      },
    );
  }

  testWidgets('Gmail never offers or dispatches folder moves', (tester) async {
    final harness = _Harness(MailProviderKind.gmail);
    harness.configure = (provider) => provider.advertiseGmailMove = true;
    await _show(tester, harness);
    expect(
      _list(tester).supportedBulkActions,
      contains(MailBulkFlagAction.delete),
    );
    expect(
      _list(tester).supportedBulkActions,
      isNot(contains(MailBulkFlagAction.move)),
    );
    await _start(tester, MailBulkFlagAction.move);
    expect(_key('studio-mail-move-selection-dialog'), findsNothing);
    expect(harness.provider.commands, isEmpty);
    await tester.tap(_key('mail-list-select-shown'));
    await tester.pump();
    await tester.tap(_key('mail-list-bulk-actions'));
    await _pump(tester);
    expect(_key('mail-list-bulk-delete'), findsOneWidget);
    expect(_key('mail-list-bulk-move'), findsNothing);
  });

  testWidgets('definite item failure preserves the rest of a reviewed move', (
    tester,
  ) async {
    final harness = _Harness(MailProviderKind.ews);
    harness.configure = (provider) {
      provider.respond = (_, index) => index == 2
          ? const MailFailure<MailUnit>(
              MailProblem(
                MailProblemCode.permissionDenied,
                mutationMayHaveOccurred: false,
              ),
            )
          : _success;
    };
    await _show(tester, harness);
    await _start(tester, MailBulkFlagAction.move);
    await _confirm(tester, MailBulkFlagAction.move);
    expect(harness.provider.commands, hasLength(3));
    _counts(tester, 2, 1, 0, 0);
    expect(_list(tester).items.map((item) => item.id), ['ews-message-two']);
    expect(_list(tester).bulkActionsEnabled, isFalse);
  });

  testWidgets('missing capabilities reject forged organization callbacks', (
    tester,
  ) async {
    final harness = _Harness(MailProviderKind.ews);
    harness.configure = (provider) => provider.allowMembership = false;
    await _show(tester, harness);
    expect(_list(tester).supportedBulkActions, hasLength(4));
    for (final action in [MailBulkFlagAction.move, MailBulkFlagAction.delete]) {
      await _start(tester, action);
    }
    expect(_key('studio-mail-move-selection-dialog'), findsNothing);
    expect(_key('studio-mail-delete-selection-dialog'), findsNothing);
    expect(harness.provider.commands, isEmpty);
  });

  testWidgets('duplicate or unavailable targets never reach confirmation', (
    tester,
  ) async {
    final harness = _Harness(MailProviderKind.graph);
    await _show(tester, harness);
    for (final ids in [
      <String>[],
      ['ews-message-one', 'ews-message-one'],
      ['ews-message-one', 'ews-message-missing'],
    ]) {
      await _start(tester, MailBulkFlagAction.move, ids: ids);
    }
    expect(_key('studio-mail-move-selection-dialog'), findsNothing);
    expect(harness.provider.commands, isEmpty);
    expect(_list(tester).busy, isFalse);
  });
}
