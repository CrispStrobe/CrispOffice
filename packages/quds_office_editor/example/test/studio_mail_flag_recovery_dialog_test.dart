@TestOn('vm')
library;

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:quds_office_studio/studio_mail_bulk_status.dart';
import 'package:quds_office_studio/studio_mail_flag_journal.dart';
import 'package:quds_office_studio/studio_mail_journal_dialog.dart';
import 'package:quds_office_studio/studio_mail_journal_strings.dart';
import 'package:quds_office_studio/studio_strings.dart';

import 'support/mail_flag_journal.dart';

part 'support/mail_membership_recovery_cases.dart';

const _output = String.fromEnvironment('MAIL_RECOVERY_SCREENSHOT_DIR');
const _captureKey = ValueKey('recovery-visual-capture');
const _id = 'recover-this-action';
Finder _key(String value) => find.byKey(ValueKey(value));

final class _Observer implements MailFlagObserver {
  _Observer(this.account);
  @override
  final MailAccountId account;
  final requests = <MailRemoteIdentity>[];
  final leases = <MailOperationLease>[];
  Future<MailResult<MailFlagObservation>> Function(MailRemoteIdentity)? respond;

  @override
  Future<MailResult<MailFlagObservation>> observeFlags(
    MailRemoteIdentity identity, {
    required MailOperationLease lease,
  }) async {
    requests.add(identity);
    leases.add(lease);
    return respond == null
        ? MailSuccess(
            MailFlagObservation.present(
              identity: identity,
              flags: const MailMessageFlags(isFlagged: true),
            ),
          )
        : await respond!(identity);
  }
}

final class _RecordingStore implements StudioMailFlagJournalStore {
  _RecordingStore(this.delegate);
  final StudioMailFlagJournalStore delegate;
  int loads = 0;
  int lists = 0;
  int binds = 0;
  @override
  MailAccountId get account => delegate.account;
  @override
  Future<MailStoredFlagBatchPage> list({int limit = 20, int offset = 0}) {
    lists++;
    return delegate.list(limit: limit, offset: offset);
  }

  @override
  Future<MailStoredFlagBatch?> load(String id) {
    loads++;
    return delegate.load(id);
  }

  @override
  Future<int> clearCompleted() => delegate.clearCompleted();
  @override
  MailBulkFlagJournal bind({
    required MailAccountId sourceAccount,
    required MailProviderKind provider,
    required List<String> subjects,
    required bool Function() isCurrent,
  }) {
    binds++;
    return delegate.bind(
      sourceAccount: sourceAccount,
      provider: provider,
      subjects: subjects,
      isCurrent: isCurrent,
    );
  }
}

Future<void> _fonts() async {
  await (FontLoader('RecoveryLatin')
        ..addFont(
          rootBundle.load(
            'packages/quds_office_editor/fonts/LiberationSans-Regular.ttf',
          ),
        )
        ..addFont(
          rootBundle.load(
            'packages/quds_office_editor/fonts/LiberationSans-Bold.ttf',
          ),
        ))
      .load();
  await (FontLoader('RecoveryArabic')
        ..addFont(rootBundle.load('fonts/Tajawal-Regular.ttf'))
        ..addFont(rootBundle.load('fonts/Tajawal-Bold.ttf')))
      .load();
  await (FontLoader(
    'MaterialIcons',
  )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
}

Future<TestMailFlagJournal> _fixture(
  WidgetTester tester, {
  String subject = 'Quarterly review',
  String state = 'uncertain',
}) async {
  final fixture = (await tester.runAsync(() async {
    final fixture = await TestMailFlagJournal.create();
    if (state == 'running') {
      await fixture.prepare(_id, begin: true);
    } else {
      await fixture.run(
        _id,
        count: 1,
        subjects: [subject],
        apply: (_) async => state == 'confirmed'
            ? const MailBulkFlagAttempt.confirmed()
            : const MailBulkFlagAttempt.uncertain(
                MailProblem(
                  MailProblemCode.providerFailure,
                  mutationMayHaveOccurred: true,
                ),
              ),
      );
    }
    fixture.now = fixture.now.add(const Duration(minutes: 2));
    return fixture;
  }))!;
  addTearDown(() => settleMailJournal(tester, fixture.dispose));
  return fixture;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 100; i++) {
    await tester.pump(const Duration(milliseconds: 30));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    if (find.byType(LinearProgressIndicator).evaluate().isEmpty) break;
  }
  expect(find.byType(LinearProgressIndicator), findsNothing);
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

Future<void> _show(
  WidgetTester tester,
  StudioMailFlagJournalStore store, {
  StudioMailReconcileFlagBatch? recovery,
  StudioMailReconcileMembershipBatch? membershipRecovery,
  StudioLanguage language = StudioLanguage.en,
  Size size = const Size(900, 760),
  double scale = 1,
  bool Function()? isCurrent,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final strings = StudioStrings(language);
  await tester.pumpWidget(
    RepaintBoundary(
      key: _captureKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff256356)),
          fontFamily: language == StudioLanguage.ar
              ? 'RecoveryArabic'
              : 'RecoveryLatin',
          fontFamilyFallback: const ['RecoveryLatin', 'RecoveryArabic'],
        ),
        builder: (context, child) => Directionality(
          textDirection: language == StudioLanguage.ar
              ? TextDirection.rtl
              : TextDirection.ltr,
          child: MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                key: const ValueKey('open-recovery'),
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => StudioMailJournalDialog(
                    strings: strings,
                    store: store,
                    isCurrent: isCurrent ?? () => true,
                    onReconcile: recovery,
                    onReconcileMembership: membershipRecovery,
                  ),
                ),
                child: Text(strings.mailActivity),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(_key('open-recovery'));
  await _settle(tester);
}

Future<void> _tap(WidgetTester tester, String key, {bool settle = true}) async {
  await tester.ensureVisible(_key(key));
  await tester.pump(const Duration(milliseconds: 250));
  await tester.tap(_key(key));
  if (settle) {
    await _settle(tester);
  } else {
    await tester.pump();
  }
}

Future<void> _started(WidgetTester tester, _Observer observer) async {
  for (var i = 0; i < 100 && observer.requests.isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 5));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
  }
  expect(observer.requests, hasLength(1));
}

StudioMailReconcileFlagBatch _recovery(
  TestMailFlagJournal fixture,
  _Observer observer,
) => studioMailFlagRecovery(
  store: fixture.store,
  observer: observer,
  provider: fixture.provider,
  isCurrent: () => fixture.current,
)!;

Future<void> _capture(WidgetTester tester, String name) async {
  expect(tester.takeException(), isNull);
  if (_output.isEmpty) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureKey),
  );
  await tester.runAsync(() async {
    await Directory(_output).create(recursive: true);
    final image = await boundary.toImage(pixelRatio: 1.5);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(
        '$_output/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_fonts);
  _membershipRecoveryTests();

  testWidgets(
    'cached activity and repeated opening never create a provider request',
    (tester) async {
      final fixture = await _fixture(tester);
      final store = _RecordingStore(fixture.store);
      final observer = _Observer(fixture.source());
      await _show(tester, store);
      await _tap(tester, 'studio-mail-activity-$_id');
      expect(_key('studio-mail-activity-check'), findsNothing);
      expect(_key('studio-mail-activity-reconnect'), findsOneWidget);
      expect(_key('studio-mail-activity-checked-counts'), findsOneWidget);
      await _tap(tester, 'studio-mail-activity-close');
      await _tap(tester, 'open-recovery');
      await _tap(tester, 'studio-mail-activity-$_id');
      expect(observer.requests, isEmpty);
      expect(store.binds, 0);
      expect(store.loads, 2);
      expect(fixture.dispatched, hasLength(1));
    },
  );

  for (final state in ['confirmed', 'running']) {
    testWidgets('$state receipt does not offer a server check', (tester) async {
      final fixture = await _fixture(tester, state: state);
      final observer = _Observer(fixture.source());
      await _show(
        tester,
        fixture.store,
        recovery: _recovery(fixture, observer),
      );
      await _tap(tester, 'studio-mail-activity-$_id');
      expect(_key('studio-mail-activity-check'), findsNothing);
      expect(_key('studio-mail-activity-stop-check'), findsNothing);
      expect(observer.requests, isEmpty);
    });
  }

  testWidgets(
    'an explicit connected check adds an observation while the action stays uncertain',
    (tester) async {
      final fixture = await _fixture(tester);
      final observer = _Observer(fixture.source('new-connection'));
      await _show(
        tester,
        fixture.store,
        recovery: _recovery(fixture, observer),
      );
      expect(observer.requests, isEmpty);
      await _tap(tester, 'studio-mail-activity-$_id');
      expect(observer.requests, isEmpty);
      expect(_key('studio-mail-activity-check'), findsOneWidget);
      await _tap(tester, 'studio-mail-activity-check');
      expect(observer.requests, hasLength(1));
      expect(_key('studio-mail-activity-check'), findsNothing);
      expect(_key('studio-mail-activity-observation-0'), findsOneWidget);
      expect(find.text('1 checked · 0 still to check'), findsOneWidget);
      expect(
        find.textContaining('Flagged at the time of the check'),
        findsOneWidget,
      );
      final status = tester.widget<StudioMailBulkStatus>(
        find.byType(StudioMailBulkStatus),
      );
      expect(status.report.uncertainCount, 1);
      expect(status.report.confirmedCount, 0);
      await _tap(tester, 'studio-mail-bulk-details');
      expect(find.text('Uncertain'), findsOneWidget);
      await _tap(tester, 'studio-mail-bulk-details-close');
      await _tap(tester, 'studio-mail-activity-close');
      await _tap(tester, 'open-recovery');
      await _tap(tester, 'studio-mail-activity-$_id');
      expect(observer.requests, hasLength(1));
      expect(_key('studio-mail-activity-observation-0'), findsOneWidget);
      expect(fixture.dispatched, hasLength(1));
    },
  );

  testWidgets(
    'failed checks reload local history and remain explicitly retryable',
    (tester) async {
      final fixture = await _fixture(tester);
      final store = _RecordingStore(fixture.store);
      final observer = _Observer(fixture.source())
        ..respond = (_) async => const MailFailure(
          MailProblem(MailProblemCode.authenticationRequired),
        );
      await _show(tester, store, recovery: _recovery(fixture, observer));
      await _tap(tester, 'studio-mail-activity-$_id');
      await _tap(tester, 'studio-mail-activity-check');
      expect(
        store.loads,
        2,
        reason: 'Failure must reload only the local receipt.',
      );
      expect(observer.requests, hasLength(1));
      expect(_key('studio-mail-activity-observation-0'), findsNothing);
      expect(find.text('0 checked · 1 still to check'), findsOneWidget);
      expect(
        find.text(
          const StudioStrings(
            StudioLanguage.en,
          ).mailActivityCheckFailed(MailProblemCode.authenticationRequired),
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(_key('studio-mail-activity-check'))
            .onPressed,
        isNotNull,
      );
      observer.respond = null;
      await _tap(tester, 'studio-mail-activity-check');
      expect(observer.requests, hasLength(2));
      expect(_key('studio-mail-activity-error'), findsNothing);
      expect(find.text('1 checked · 0 still to check'), findsOneWidget);
      expect(fixture.dispatched, hasLength(1));
    },
  );

  testWidgets('duplicate taps do not duplicate an in-flight status request', (
    tester,
  ) async {
    final fixture = await _fixture(tester);
    final response = Completer<MailResult<MailFlagObservation>>();
    final observer = _Observer(fixture.source())
      ..respond = (_) => response.future;
    await _show(tester, fixture.store, recovery: _recovery(fixture, observer));
    await _tap(tester, 'studio-mail-activity-$_id');
    final staleCallback = tester
        .widget<FilledButton>(_key('studio-mail-activity-check'))
        .onPressed!;
    staleCallback();
    staleCallback();
    await tester.pump();
    await _started(tester, observer);
    expect(
      tester.widget<FilledButton>(_key('studio-mail-activity-check')).onPressed,
      isNull,
    );
    expect(_key('studio-mail-activity-stop-check'), findsOneWidget);
    response.complete(
      MailSuccess(
        MailFlagObservation.missing(identity: observer.requests.single),
      ),
    );
    await _settle(tester);
    expect(observer.requests, hasLength(1));
    expect(_key('studio-mail-activity-observation-0'), findsOneWidget);
  });

  testWidgets(
    'Stop finishes a stuck read and ignores its late successful response',
    (tester) async {
      final fixture = await _fixture(tester);
      final response = Completer<MailResult<MailFlagObservation>>();
      final observer = _Observer(fixture.source())
        ..respond = (_) => response.future;
      await _show(
        tester,
        fixture.store,
        recovery: _recovery(fixture, observer),
      );
      await _tap(tester, 'studio-mail-activity-$_id');
      await _tap(tester, 'studio-mail-activity-check', settle: false);
      await _started(tester, observer);
      await _tap(tester, 'studio-mail-activity-stop-check');
      expect(
        response.isCompleted,
        isFalse,
        reason: 'Stop must not wait for this provider.',
      );
      expect(observer.leases.single.isCurrent, isFalse);
      expect(
        find.text(
          const StudioStrings(
            StudioLanguage.en,
          ).mailActivityCheckFailed(MailProblemCode.cancelled),
        ),
        findsOneWidget,
      );
      response.complete(
        MailSuccess(
          MailFlagObservation.missing(identity: observer.requests.single),
        ),
      );
      await _settle(tester);
      expect(_key('studio-mail-activity-observation-0'), findsNothing);
      expect(find.text('0 checked · 1 still to check'), findsOneWidget);
      expect(observer.requests, hasLength(1));
      expect(fixture.dispatched, hasLength(1));
    },
  );

  testWidgets(
    'closing a pending check discards a late provider failure without reopening',
    (tester) async {
      final fixture = await _fixture(tester);
      final response = Completer<MailResult<MailFlagObservation>>();
      final observer = _Observer(fixture.source())
        ..respond = (_) => response.future;
      await _show(
        tester,
        fixture.store,
        recovery: _recovery(fixture, observer),
      );
      await _tap(tester, 'studio-mail-activity-$_id');
      await _tap(tester, 'studio-mail-activity-check', settle: false);
      await _started(tester, observer);
      await _tap(tester, 'studio-mail-activity-close');
      expect(_key('studio-mail-activity-dialog'), findsNothing);
      response.completeError(StateError('Synthetic late provider error'));
      await _settle(tester);
      await _tap(tester, 'open-recovery');
      await _tap(tester, 'studio-mail-activity-$_id');
      expect(find.text('0 checked · 1 still to check'), findsOneWidget);
      expect(_key('studio-mail-activity-error'), findsNothing);
      expect(observer.requests, hasLength(1));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'retiring the account prevents late UI and durable observation publication',
    (tester) async {
      final fixture = await _fixture(tester);
      final response = Completer<MailResult<MailFlagObservation>>();
      final observer = _Observer(fixture.source())
        ..respond = (_) => response.future;
      await _show(
        tester,
        fixture.store,
        recovery: _recovery(fixture, observer),
        isCurrent: () => fixture.current,
      );
      await _tap(tester, 'studio-mail-activity-$_id');
      await _tap(tester, 'studio-mail-activity-check', settle: false);
      await _started(tester, observer);
      fixture.current = false;
      await tester.pump(const Duration(milliseconds: 50));
      response.complete(
        MailSuccess(
          MailFlagObservation.missing(identity: observer.requests.single),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      await _tap(tester, 'studio-mail-activity-close');
      fixture.current = true;
      await _tap(tester, 'open-recovery');
      await _tap(tester, 'studio-mail-activity-$_id');
      expect(_key('studio-mail-activity-observation-0'), findsNothing);
      expect(find.text('0 checked · 1 still to check'), findsOneWidget);
      expect(observer.requests, hasLength(1));
    },
  );

  testWidgets(
    'a committed observation survives a later callback failure and local reload',
    (tester) async {
      final fixture = await _fixture(tester);
      final store = _RecordingStore(fixture.store);
      final observer = _Observer(fixture.source());
      final actual = _recovery(fixture, observer);
      await _show(
        tester,
        store,
        recovery: (batch, cancellation, current) async {
          await actual(batch, cancellation, current);
          throw const StudioMailFlagJournalException(
            MailProblemCode.unavailable,
          );
        },
      );
      await _tap(tester, 'studio-mail-activity-$_id');
      await _tap(tester, 'studio-mail-activity-check');
      expect(store.loads, 2);
      expect(observer.requests, hasLength(1));
      expect(_key('studio-mail-activity-error'), findsOneWidget);
      expect(_key('studio-mail-activity-check'), findsNothing);
      expect(_key('studio-mail-activity-observation-0'), findsOneWidget);
      expect(find.text('1 checked · 0 still to check'), findsOneWidget);
    },
  );

  for (final language in StudioLanguage.values) {
    testWidgets(
      '${language.name} compact recovery uses readable localized controls at 1.4 text scale',
      (tester) async {
        final subject = switch (language) {
          StudioLanguage.en => 'Quarterly planning review',
          StudioLanguage.de => 'Besprechung der Quartalsplanung',
          StudioLanguage.ar => 'مراجعة خطة الربع القادم',
        };
        final fixture = await _fixture(tester, subject: subject);
        final observer = _Observer(fixture.source());
        final strings = StudioStrings(language);
        await _show(
          tester,
          fixture.store,
          recovery: _recovery(fixture, observer),
          language: language,
          size: const Size(360, 760),
          scale: 1.4,
        );
        await _tap(tester, 'studio-mail-activity-$_id');
        await tester.ensureVisible(_key('studio-mail-activity-check'));
        await tester.pumpAndSettle();
        expect(find.text(strings.mailActivityCheck), findsOneWidget);
        expect(
          Directionality.of(
            tester.element(_key('studio-mail-activity-dialog')),
          ),
          language == StudioLanguage.ar ? TextDirection.rtl : TextDirection.ltr,
        );
        final dialog = tester.getRect(_key('studio-mail-activity-dialog'));
        final button = tester.getRect(_key('studio-mail-activity-check'));
        expect(button.left, greaterThanOrEqualTo(dialog.left));
        expect(button.right, lessThanOrEqualTo(dialog.right));
        expect(
          _key('studio-mail-activity-close').hitTestable(),
          findsOneWidget,
        );
        if (language != StudioLanguage.en) {
          await _capture(tester, '${language.name}-compact-check');
        }
        await _tap(tester, 'studio-mail-activity-check');
        await tester.ensureVisible(_key('studio-mail-activity-observation-0'));
        await tester.pumpAndSettle();
        expect(
          find.text(
            strings.mailActivityObserved(
              MailFlagResolutionKind.matches,
              MailBulkFlagAction.flag,
            ),
          ),
          findsOneWidget,
        );
        expect(find.text(subject), findsOneWidget);
        expect(
          _key('studio-mail-activity-close').hitTestable(),
          findsOneWidget,
        );
        if (language != StudioLanguage.en) {
          await _capture(tester, '${language.name}-compact-observed');
        }
        expect(tester.takeException(), isNull);
        expect(observer.requests, hasLength(1));
      },
    );
  }

  testWidgets('English desktop keeps the receipt and checked state readable', (
    tester,
  ) async {
    final fixture = await _fixture(
      tester,
      subject: 'Quarterly planning review',
    );
    final observer = _Observer(fixture.source());
    await _show(tester, fixture.store, recovery: _recovery(fixture, observer));
    await _tap(tester, 'studio-mail-activity-$_id');
    await tester.ensureVisible(_key('studio-mail-activity-check'));
    await tester.pumpAndSettle();
    expect(_key('studio-mail-activity-close').hitTestable(), findsOneWidget);
    await _capture(tester, 'en-desktop-check');
    await _tap(tester, 'studio-mail-activity-check');
    await tester.ensureVisible(_key('studio-mail-activity-observation-0'));
    await tester.pumpAndSettle();
    expect(find.text('1 checked · 0 still to check'), findsOneWidget);
    expect(_key('studio-mail-activity-close').hitTestable(), findsOneWidget);
    await _capture(tester, 'en-desktop-observed');
    expect(observer.requests, hasLength(1));
    expect(tester.takeException(), isNull);
  });
}
