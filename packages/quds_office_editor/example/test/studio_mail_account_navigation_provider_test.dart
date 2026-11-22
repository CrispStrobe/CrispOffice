import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:quds_mail_transport/quds_mail_transport.dart';
import 'package:quds_office_studio/studio_mail_account_navigation.dart';
import 'package:quds_office_studio/studio_mail_account_navigation_strings.dart';
import 'package:quds_office_studio/studio_mail_cloud.dart';
import 'package:quds_office_studio/studio_mail_draft.dart';
import 'package:quds_office_studio/studio_mail_draft_store.dart';
import 'package:quds_office_studio/studio_mail_ews.dart';
import 'package:quds_office_studio/studio_mail_local_accounts.dart';
import 'package:quds_office_studio/studio_mail_mailbox_store.dart';
import 'package:quds_office_studio/studio_mail_strings.dart';
import 'package:quds_office_studio/studio_strings.dart';

const _strings = StudioStrings(StudioLanguage.en);
const _draft = StudioMailDraft(
  to: 'recipient@example.test',
  subject: 'Retained draft',
  body: 'Keep the current account and its uncertainty.',
);

StudioMailDraftAccount _identity(MailProviderKind kind) {
  final sender = '${kind.name}@example.test';
  return StudioMailDraftAccount(
    provider: kind.name,
    endpoint: switch (kind) {
      MailProviderKind.imap => 'imaps://imap.example.test:993',
      MailProviderKind.ews => 'https://mail.example.test/EWS/Exchange.asmx',
      MailProviderKind.gmail => 'https://gmail.googleapis.com/gmail/v1',
      MailProviderKind.graph => 'https://graph.microsoft.com/v1.0',
      _ => throw ArgumentError.value(kind),
    },
    login: switch (kind) {
      MailProviderKind.ews => jsonEncode(['DOMAIN', 'operator']),
      MailProviderKind.graph => jsonEncode([
        'organization.example.test',
        sender,
      ]),
      _ => sender,
    },
    sender: sender,
  );
}

final class _Directory implements StudioMailLocalAccountStore {
  final records = <String, MailLocalAccountRecord>{};
  Completer<void>? loadGate;
  int loads = 0;
  int remembers = 0;

  void seed(StudioMailDraftAccount identity, {int revision = 1}) {
    records[identity.account.value] = MailLocalAccountRecord(
      id: identity.account.value,
      provider: identity.provider,
      endpoint: identity.endpoint,
      login: identity.login,
      sender: identity.sender,
      revision: revision,
      lastConnectedAt: DateTime.utc(2026, 11, 22),
    );
  }

  @override
  Future<List<MailLocalAccountRecord>> load() async {
    loads++;
    await loadGate?.future;
    return List.unmodifiable(records.values);
  }

  @override
  Future<void> remember(StudioMailDraftAccount identity) async {
    remembers++;
    seed(
      identity,
      revision: (records[identity.account.value]?.revision ?? 0) + 1,
    );
  }

  @override
  Future<void> forget(MailLocalAccountRecord record) async {
    records.remove(record.id);
  }
}

final class _MailboxStore extends Fake
    implements StudioMailMailboxStore, StudioMailMailboxWatchStore {
  _MailboxStore(this.account);
  @override
  final MailAccountId account;
  MailCachedMailboxView? view;
  Completer<void>? cancelGate;
  int cancellations = 0;
  int cancellationsFinished = 0;

  @override
  Future<MailCachedMailboxView> saveView(
    MailMailbox mailbox,
    List<MailHeaderRecord> headers, {
    required bool hasMore,
    required MailOperationLease lease,
  }) async => view = MailCachedMailboxView(
    mailbox: mailbox,
    revision: (view?.revision ?? 0) + 1,
    capturedAt: DateTime.utc(2026, 11, 22),
    headers: headers,
    hasMore: hasMore,
  );

  @override
  Future<MailCachedMailboxView?> loadView(MailMailboxId mailbox) async => view;

  @override
  Stream<MailResult<MailCachedMailboxView?>> watchView(MailMailboxId mailbox) {
    late final StreamController<MailResult<MailCachedMailboxView?>> controller;
    controller = StreamController<MailResult<MailCachedMailboxView?>>(
      onListen: () => controller.add(MailSuccess(view)),
      onCancel: () async {
        cancellations++;
        await cancelGate?.future;
        cancellationsFinished++;
      },
    );
    return controller.stream;
  }
}

final class _DraftStore extends Fake
    implements
        StudioMailDraftStore,
        StudioMailDraftCatalog,
        StudioMailMailboxStoreOwner {
  _DraftStore(this.account) : mailboxStore = _MailboxStore(account);
  @override
  final MailAccountId account;
  @override
  final _MailboxStore mailboxStore;
  @override
  String get selectedDraftId => 'retained';
  @override
  int get selectionEpoch => 0;
  StudioMailStoredDraft? snapshot;
  bool failSave = false;
  bool failClose = false;
  Completer<void>? loadGate;
  Completer<void>? saveGate;
  Completer<void>? closeGate;
  final savedUncertainty = <bool>[];
  int saves = 0;
  int loads = 0;
  int closeCalls = 0;
  int closed = 0;

  @override
  Future<StudioMailStoredDraft?> load() async {
    loads++;
    await loadGate?.future;
    return snapshot;
  }

  @override
  Future<void> save(
    StudioMailDraft draft, {
    required bool submissionUncertain,
  }) async {
    saves++;
    savedUncertainty.add(submissionUncertain);
    await saveGate?.future;
    if (failSave) {
      throw const StudioMailDraftStoreException(MailProblemCode.storageFailure);
    }
    snapshot = StudioMailStoredDraft(
      draft: draft,
      submissionUncertain:
          submissionUncertain || (snapshot?.submissionUncertain ?? false),
    );
  }

  @override
  Future<void> close() async {
    closeCalls++;
    await closeGate?.future;
    if (failClose) {
      throw const StudioMailDraftStoreException(MailProblemCode.storageFailure);
    }
    closed++;
  }
}

final class _Tokens extends Fake implements MailCloudTokenSource {
  int disposals = 0;
  @override
  void dispose() => disposals++;
}

final class _Provider extends Fake
    implements MailEwsProvider, MailCloudProvider {
  _Provider(this.account, this.kind);
  @override
  final MailAccountId account;
  final MailProviderKind kind;
  Completer<MailResult<MailCapabilities>>? capabilitiesGate;
  MailOperationLease? lease;
  int capabilitiesCalls = 0;
  int lists = 0;
  int headers = 0;
  int disposals = 0;

  static MailCapabilities get supported => MailCapabilities(const [
    MailCapability.mail,
    MailCapability.folders,
    MailCapability.send,
  ]);

  @override
  Future<MailResult<MailCapabilities>> capabilities(
    MailOperationLease lease,
  ) async {
    this.lease = lease;
    capabilitiesCalls++;
    return capabilitiesGate == null
        ? MailSuccess(supported)
        : await capabilitiesGate!.future;
  }

  @override
  Future<MailResult<List<MailMailbox>>> listMailboxes(
    MailOperationLease lease,
  ) async {
    this.lease = lease;
    lists++;
    return MailSuccess([
      MailMailbox(
        id: MailMailboxId('inbox', account: account),
        displayName: 'Inbox',
      ),
    ]);
  }

  @override
  Future<MailResult<MailHeaderPage>> fetchHeaders(
    MailMailboxId mailbox, {
    MailCursor? cursor,
    required int limit,
    required MailOperationLease lease,
  }) async {
    this.lease = lease;
    headers++;
    return MailSuccess(
      MailHeaderPage(
        messages: [
          MailHeaderRecord(
            id: MailMessageId('one'),
            remote: MailOpaqueIdentity(
              account: account,
              provider: kind,
              value: 'one',
            ),
            envelope: MailEnvelope(subject: 'Current account message'),
            flags: const MailMessageFlags(),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() => disposals++;
}

final class _Harness {
  _Harness(this.kind) {
    identity = _identity(kind);
    destination = _identity(
      kind == MailProviderKind.gmail
          ? MailProviderKind.ews
          : MailProviderKind.gmail,
    );
    directory
      ..seed(identity)
      ..seed(destination);
    target = StudioMailAccountNavigationTarget.fromRecord(
      directory.records[identity.account.value]!,
    );
    owner = _DraftStore(identity.account);
  }

  final MailProviderKind kind;
  final directory = _Directory();
  late final StudioMailDraftAccount identity;
  late final StudioMailDraftAccount destination;
  late final StudioMailAccountNavigationTarget target;
  late final _DraftStore owner;
  final tokens = _Tokens();
  final navigations = <StudioMailAccountNavigationTarget>[];
  final providers = <_Provider>[];
  Completer<MailResult<MailCapabilities>>? capabilitiesGate;
  Completer<MailResult<MailCloudTokenSource>>? authorizationGate;
  Completer<void>? openGate;
  int authorizations = 0;
  int storeOpens = 0;

  _Provider create(MailAccountId account) {
    expect(account, identity.account);
    final provider = _Provider(account, kind)
      ..capabilitiesGate = capabilitiesGate;
    providers.add(provider);
    return provider;
  }

  Future<StudioMailDraftStore> open(StudioMailDraftAccount account) async {
    expect(account.account, identity.account);
    storeOpens++;
    await openGate?.future;
    return owner;
  }

  Widget dialog() => kind == MailProviderKind.ews
      ? StudioMailEwsDialog(
          strings: _strings,
          initialAccount: target,
          localAccountStore: directory,
          draftStoreFactory: open,
          providerFactory: (configuration, _) => create(configuration.account),
          onAccountNavigation: navigations.add,
        )
      : StudioMailCloudDialog(
          strings: _strings,
          service: kind == MailProviderKind.gmail
              ? MailCloudService.gmail
              : MailCloudService.microsoft365,
          initialAccount: target,
          localAccountStore: directory,
          draftStoreFactory: open,
          authorizer:
              ({
                required configuration,
                required account,
                required openBrowser,
                required lease,
                log,
              }) async {
                expect(account, identity.account);
                authorizations++;
                return authorizationGate == null
                    ? MailSuccess(tokens)
                    : await authorizationGate!.future;
              },
          providerFactory:
              ({required configuration, required tokenSource, log}) =>
                  create(configuration.account),
          onAccountNavigation: navigations.add,
        );
}

Finder _key(String value) => find.byKey(ValueKey(value));
Finder _icon(String tooltip) => find.byWidgetPredicate(
  (widget) => widget is IconButton && widget.tooltip == tooltip,
);
String _text(WidgetTester tester, String key) =>
    tester.widget<TextField>(_key(key)).controller!.text;

Future<void> _pump(WidgetTester tester) async {
  // Stream cancellation can await Dart's shared root-zone completed future.
  // Give that future a real event turn; fake clock pumps alone leave cleanup
  // pending until test teardown even after the explicit cancellation gate opens.
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump();
}

Future<void> _press(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await _pump(tester);
}

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var attempt = 0; attempt < 100 && !ready(); attempt++) {
    await tester.pump(const Duration(milliseconds: 10));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  }
  expect(
    ready(),
    isTrue,
    reason: 'The account transition must finish draining.',
  );
}

Future<void> _show(WidgetTester tester, _Harness harness) async {
  await tester.binding.setSurfaceSize(const Size(1440, 1100));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  addTearDown(() async {
    for (final gate in [
      harness.directory.loadGate,
      harness.openGate,
      harness.owner.loadGate,
      harness.owner.saveGate,
      harness.owner.closeGate,
      harness.owner.mailboxStore.cancelGate,
    ]) {
      if (gate != null && !gate.isCompleted) gate.complete();
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await _pump(tester);
  });
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => harness.dialog(),
            ),
            child: const Text('Open provider'),
          ),
        ),
      ),
    ),
  );
  await _press(tester, find.text('Open provider'));
}

Future<void> _credentials(WidgetTester tester, _Harness harness) async {
  if (harness.kind == MailProviderKind.ews) {
    await tester.enterText(_key('ews-password'), 'session-password');
  } else {
    await tester.enterText(_key('cloud-client-id'), 'registered-client-id');
  }
}

Future<void> _connect(WidgetTester tester, _Harness harness) async {
  await _credentials(tester, harness);
  await _press(
    tester,
    _key(
      harness.kind == MailProviderKind.ews ? 'ews-connect' : 'cloud-connect',
    ),
  );
}

Future<void> _choose(WidgetTester tester, _Harness harness) async {
  await _press(tester, _key('studio-mail-switch-account'));
  await _press(
    tester,
    _key('studio-mail-navigation-account-${harness.destination.account.value}'),
  );
  await _press(tester, _key('studio-mail-account-navigation-continue'));
}

void main() {
  for (final kind in [
    MailProviderKind.ews,
    MailProviderKind.gmail,
    MailProviderKind.graph,
  ]) {
    testWidgets('${kind.name}: non-secret prefill waits for explicit sign-in', (
      tester,
    ) async {
      final harness = _Harness(kind);
      await _show(tester, harness);
      expect(
        _text(
          tester,
          kind == MailProviderKind.ews ? 'ews-mailbox' : 'cloud-mailbox',
        ),
        harness.identity.sender,
      );
      if (kind == MailProviderKind.ews) {
        expect(_text(tester, 'ews-endpoint'), harness.identity.endpoint);
        expect(_text(tester, 'ews-domain'), 'DOMAIN');
        expect(_text(tester, 'ews-login'), 'operator');
        expect(_text(tester, 'ews-password'), isEmpty);
      } else {
        expect(_text(tester, 'cloud-client-id'), isEmpty);
        if (kind == MailProviderKind.graph) {
          expect(_text(tester, 'cloud-tenant'), 'organization.example.test');
        } else {
          expect(_text(tester, 'cloud-client-secret'), isEmpty);
        }
      }
      expect(harness.providers, isEmpty);
      expect(harness.authorizations, 0);
      expect(harness.storeOpens, 0);
      await _connect(tester, harness);
      expect(harness.providers.single.account, harness.identity.account);
      expect(harness.providers.single.headers, 1);
      expect(harness.storeOpens, 1);
      expect(harness.directory.remembers, 1);
      expect(find.text('Current account message'), findsOneWidget);
    });

    final edits = switch (kind) {
      MailProviderKind.ews => {
        'ews-mailbox': 'other@example.test',
        'ews-endpoint': 'https://other.example.test/EWS/Exchange.asmx',
        'ews-domain': 'OTHER',
        'ews-login': 'other-operator',
      },
      MailProviderKind.graph => {
        'cloud-mailbox': 'other@example.test',
        'cloud-tenant': 'other.example.test',
      },
      _ => {'cloud-mailbox': 'other@example.test'},
    };
    for (final edit in edits.entries) {
      testWidgets(
        '${kind.name}: edited ${edit.key} cannot redirect selected identity',
        (tester) async {
          final harness = _Harness(kind);
          await _show(tester, harness);
          await tester.enterText(_key(edit.key), edit.value);
          await _connect(tester, harness);
          expect(harness.authorizations, 0);
          expect(harness.providers, isEmpty);
          expect(harness.storeOpens, 0);
          expect(
            find.text(_strings.mailAccountNavigationIdentityMismatch),
            findsOneWidget,
          );
        },
      );
    }

    for (final removed in [true, false]) {
      testWidgets(
        '${kind.name}: ${removed ? 'removed' : 'revised'} target fails before provider authorization',
        (tester) async {
          final harness = _Harness(kind);
          await _show(tester, harness);
          if (removed) {
            harness.directory.records.remove(harness.identity.account.value);
          } else {
            harness.directory.seed(harness.identity, revision: 2);
          }
          await _connect(tester, harness);
          expect(harness.authorizations, 0);
          expect(harness.providers, isEmpty);
          expect(harness.storeOpens, 0);
          expect(
            find.text(_strings.mailAccountNavigationChanged),
            findsOneWidget,
          );
        },
      );
    }

    testWidgets(
      '${kind.name}: late target validation cannot authenticate a closed host',
      (tester) async {
        final harness = _Harness(kind);
        await _show(tester, harness);
        harness.directory.loadGate = Completer<void>();
        await _connect(tester, harness);
        expect(harness.directory.loads, 1);
        await _press(tester, _icon(_strings.close));
        harness.directory.loadGate!.complete();
        await _pump(tester);
        expect(find.byType(StudioMailEwsDialog), findsNothing);
        expect(harness.providers, isEmpty);
        expect(harness.authorizations, 0);
        expect(harness.storeOpens, 0);
      },
    );

    testWidgets(
      '${kind.name}: target removal during authorization blocks later dispatch',
      (tester) async {
        final harness = _Harness(kind);
        if (kind == MailProviderKind.ews) {
          harness.capabilitiesGate = Completer<MailResult<MailCapabilities>>();
        } else {
          harness.authorizationGate =
              Completer<MailResult<MailCloudTokenSource>>();
        }
        await _show(tester, harness);
        await _connect(tester, harness);
        harness.directory.records.remove(harness.identity.account.value);
        if (kind == MailProviderKind.ews) {
          harness.capabilitiesGate!.complete(MailSuccess(_Provider.supported));
        } else {
          harness.authorizationGate!.complete(MailSuccess(harness.tokens));
        }
        await _pump(tester);
        expect(harness.storeOpens, 0);
        if (kind == MailProviderKind.ews) {
          expect(harness.providers.single.lists, 0);
          expect(harness.providers.single.headers, 0);
          expect(harness.providers.single.lease!.isCurrent, isFalse);
        } else {
          expect(harness.providers, isEmpty);
          expect(harness.tokens.disposals, 1);
        }
      },
    );

    testWidgets(
      '${kind.name}: setup picker selection never opens a provider or draft store',
      (tester) async {
        final harness = _Harness(kind);
        await _show(tester, harness);
        await _choose(tester, harness);
        expect(
          harness.navigations.single.identity.account,
          harness.destination.account,
        );
        expect(harness.authorizations, 0);
        expect(harness.providers, isEmpty);
        expect(harness.storeOpens, 0);
        expect(harness.owner.closeCalls, 0);
      },
    );

    for (final duringOpen in [true, false]) {
      testWidgets(
        '${kind.name}: removed target during store ${duringOpen ? 'open' : 'load'} retires an unadopted candidate',
        (tester) async {
          final harness = _Harness(kind);
          harness.owner.snapshot = const StudioMailStoredDraft(
            draft: _draft,
            submissionUncertain: true,
          );
          final gate = Completer<void>();
          if (duringOpen) {
            harness.openGate = gate;
          } else {
            harness.owner.loadGate = gate;
          }
          await _show(tester, harness);
          await _connect(tester, harness);
          expect(harness.storeOpens, 1);
          expect(harness.owner.loads, duringOpen ? 0 : 1);
          harness.directory.records.remove(harness.identity.account.value);
          gate.complete();
          await _until(
            tester,
            () => !harness.providers.single.lease!.isCurrent,
          );
          await _pump(tester);
          expect(harness.owner.closed, 1);
          expect(harness.owner.loads, duringOpen ? 0 : 1);
          expect(harness.directory.remembers, 0);
          expect(harness.navigations, isEmpty);
          expect(harness.owner.snapshot!.draft.body, _draft.body);
          expect(find.text('Current account message'), findsNothing);
          expect(
            find.text(_strings.mailAccountNavigationChanged),
            findsOneWidget,
          );
        },
      );
    }

    testWidgets(
      '${kind.name}: failed release of a stale open candidate blocks another account',
      (tester) async {
        final harness = _Harness(kind);
        harness.openGate = Completer<void>();
        await _show(tester, harness);
        await _connect(tester, harness);
        harness.owner.failClose = true;
        harness.directory.records.remove(harness.identity.account.value);
        harness.openGate!.complete();
        await _until(tester, () => !harness.providers.single.lease!.isCurrent);
        await _pump(tester);
        expect(harness.owner.loads, 0);
        expect(harness.owner.closeCalls, 1);
        expect(harness.owner.closed, 0);
        expect(harness.directory.remembers, 0);
        expect(harness.navigations, isEmpty);
        expect(find.text(_strings.mailDraftStorageFailed), findsOneWidget);
        expect(
          tester
              .widget<IconButton>(_key('studio-mail-switch-account'))
              .onPressed,
          isNull,
        );
        expect(
          tester
              .widget<FilledButton>(
                _key(
                  kind == MailProviderKind.ews
                      ? 'ews-connect'
                      : 'cloud-connect',
                ),
              )
              .onPressed,
          isNull,
        );
        harness.owner.failClose = false;
        await _press(tester, _icon(_strings.close));
        await _until(
          tester,
          () => find.byType(StudioMailEwsDialog).evaluate().isEmpty,
        );
        expect(harness.owner.closeCalls, 2);
        expect(harness.owner.closed, 1);
      },
    );

    testWidgets(
      '${kind.name}: failed switch save retains the current connected uncertain draft',
      (tester) async {
        final harness = _Harness(kind);
        harness.owner.snapshot = const StudioMailStoredDraft(
          draft: _draft,
          submissionUncertain: true,
        );
        await _show(tester, harness);
        await _connect(tester, harness);
        harness.owner.failSave = true;
        await _choose(tester, harness);
        expect(harness.navigations, isEmpty);
        expect(harness.owner.savedUncertainty, [true]);
        expect(harness.owner.closeCalls, 0);
        expect(harness.providers.single.lease!.isCurrent, isTrue);
        expect(harness.providers.single.disposals, 0);
        expect(find.text('Current account message'), findsOneWidget);
        expect(find.text(_strings.mailDraftSaveFailed), findsOneWidget);
        expect(
          tester
              .widget<IconButton>(_key('studio-mail-switch-account'))
              .onPressed,
          isNotNull,
        );
      },
    );

    testWidgets(
      '${kind.name}: switch revalidates destination after saving and retains source on removal',
      (tester) async {
        final harness = _Harness(kind);
        harness.owner.snapshot = const StudioMailStoredDraft(
          draft: _draft,
          submissionUncertain: true,
        );
        await _show(tester, harness);
        await _connect(tester, harness);
        harness.owner.saveGate = Completer<void>();
        await _choose(tester, harness);
        expect(harness.owner.saves, 1);
        harness.directory.records.remove(harness.destination.account.value);
        harness.owner.saveGate!.complete();
        await _pump(tester);
        expect(harness.navigations, isEmpty);
        expect(harness.owner.closeCalls, 0);
        expect(harness.providers.single.lease!.isCurrent, isTrue);
        expect(
          find.text(_strings.mailAccountNavigationChanged),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      '${kind.name}: switch drains observers and draft owner before one callback',
      (tester) async {
        final harness = _Harness(kind);
        harness.owner.snapshot = const StudioMailStoredDraft(
          draft: _draft,
          submissionUncertain: true,
        );
        await _show(tester, harness);
        await _connect(tester, harness);
        final oldSwitch = tester
            .widget<IconButton>(_key('studio-mail-switch-account'))
            .onPressed!;
        harness.owner.mailboxStore.cancelGate = Completer<void>();
        harness.owner.closeGate = Completer<void>();
        await _choose(tester, harness);
        expect(harness.providers.single.lease!.isCurrent, isFalse);
        expect(harness.owner.savedUncertainty, [true]);
        expect(harness.owner.mailboxStore.cancellations, 1);
        expect(harness.owner.mailboxStore.cancellationsFinished, 0);
        expect(harness.owner.closeCalls, 0);
        expect(harness.navigations, isEmpty);
        oldSwitch();
        await _pump(tester);
        expect(harness.owner.saves, 1);
        expect(
          tester
              .widget<IconButton>(_key('studio-mail-switch-account'))
              .onPressed,
          isNull,
        );
        harness.owner.mailboxStore.cancelGate!.complete();
        await _until(tester, () => harness.owner.closeCalls == 1);
        expect(harness.owner.mailboxStore.cancellationsFinished, 1);
        expect(harness.owner.closeCalls, 1);
        expect(harness.navigations, isEmpty);
        harness.owner.closeGate!.complete();
        await _until(tester, () => harness.navigations.length == 1);
        expect(harness.owner.closed, 1);
        expect(
          harness.navigations.single.identity.account,
          harness.destination.account,
        );
        expect(harness.providers, hasLength(1));
        expect(harness.authorizations, kind == MailProviderKind.ews ? 0 : 1);
        oldSwitch();
        await _pump(tester);
        expect(harness.navigations, hasLength(1));
      },
    );

    testWidgets('${kind.name}: close retains connection on failed draft save', (
      tester,
    ) async {
      final harness = _Harness(kind);
      harness.owner.snapshot = const StudioMailStoredDraft(
        draft: _draft,
        submissionUncertain: true,
      );
      await _show(tester, harness);
      await _connect(tester, harness);
      harness.owner.failSave = true;
      await _press(tester, _icon(_strings.close));
      expect(find.byType(StudioMailEwsDialog), findsOneWidget);
      expect(harness.providers.single.lease!.isCurrent, isTrue);
      expect(harness.owner.closeCalls, 0);
      expect(find.text(_strings.mailDraftSaveFailed), findsOneWidget);
      harness.owner.failSave = false;
      await _press(tester, _icon(_strings.close));
      await _until(
        tester,
        () => find.byType(StudioMailEwsDialog).evaluate().isEmpty,
      );
      expect(find.byType(StudioMailEwsDialog), findsNothing);
      expect(harness.owner.closed, 1);
      expect(harness.owner.snapshot!.submissionUncertain, isTrue);
    });

    testWidgets(
      '${kind.name}: own remembered revision permits a later explicit reconnect',
      (tester) async {
        final harness = _Harness(kind);
        await _show(tester, harness);
        await _connect(tester, harness);
        expect(
          harness.directory.records[harness.identity.account.value]!.revision,
          2,
        );
        await _press(tester, _icon(_strings.disconnect));
        expect(harness.providers, hasLength(1));
        await _connect(tester, harness);
        await _until(tester, () => harness.storeOpens == 2);
        expect(harness.providers, hasLength(2));
        expect(harness.providers.last.headers, 1);
        expect(harness.storeOpens, 2);
        expect(
          harness.directory.records[harness.identity.account.value]!.revision,
          3,
        );
      },
    );

    for (final switching in [true, false]) {
      testWidgets(
        '${kind.name}: ${switching ? 'switch' : 'close'} never exits after failed owner release',
        (tester) async {
          final harness = _Harness(kind);
          harness.owner.snapshot = const StudioMailStoredDraft(
            draft: _draft,
            submissionUncertain: true,
          );
          await _show(tester, harness);
          await _connect(tester, harness);
          harness.owner.failClose = true;
          if (switching) {
            await _choose(tester, harness);
          } else {
            await _press(tester, _icon(_strings.close));
          }
          await _until(tester, () => harness.owner.closeCalls == 1);
          await _pump(tester);
          expect(harness.navigations, isEmpty);
          expect(harness.owner.closed, 0);
          expect(harness.providers.single.lease!.isCurrent, isFalse);
          expect(find.byType(StudioMailEwsDialog), findsOneWidget);
          expect(find.text(_strings.mailDraftStorageFailed), findsOneWidget);
          expect(
            tester
                .widget<FilledButton>(
                  _key(
                    kind == MailProviderKind.ews
                        ? 'ews-connect'
                        : 'cloud-connect',
                  ),
                )
                .onPressed,
            isNull,
          );
          harness.owner.failClose = false;
          await _press(tester, _icon(_strings.close));
          await _until(
            tester,
            () => find.byType(StudioMailEwsDialog).evaluate().isEmpty,
          );
          expect(harness.owner.closeCalls, 2);
          expect(harness.owner.closed, 1);
          expect(harness.navigations, isEmpty);
          expect(harness.owner.snapshot!.submissionUncertain, isTrue);
        },
      );
    }
  }
}
