import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:quds_office_studio/studio_mail_draft.dart';
import 'package:quds_office_studio/studio_mail_draft_store.dart';
import 'package:quds_office_studio/studio_mail_outbox.dart';
import 'package:quds_office_studio/studio_mail_outbox_dialog.dart';
import 'package:quds_office_studio/studio_mail_outbox_strings.dart';
import 'package:quds_office_studio/studio_mail_schedule_strings.dart';
import 'package:quds_office_studio/studio_strings.dart';

import 'support/mail_outbox_store.dart';

const _strings = StudioStrings(StudioLanguage.en);
const _sender = 'sender@example.test';

final class _Clock {
  DateTime now = DateTime.utc(2026, 11, 21, 12);
  Duration elapsed = Duration.zero;

  Future<void> advance(WidgetTester tester, Duration duration) async {
    now = now.add(duration);
    elapsed += duration;
    await tester.pump(duration);
    await pumpOutboxWidgets(tester);
  }
}

Finder _action(String action, MailOutboxEntry entry) =>
    find.byKey(ValueKey('studio-mail-outbox-$action-${entry.id}'));

Finder _icon(String tooltip) => find.descendant(
  of: find.byType(StudioMailOutboxDialog),
  matching: find.byWidgetPredicate(
    (widget) => widget is IconButton && widget.tooltip == tooltip,
  ),
);

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await pumpOutboxWidgets(tester);
}

/// Delays adapter acknowledgements without replacing the underlying database.
/// Every actual schedule/attempt/receipt still uses the real native adapter.
final class _GatedStore
    implements StudioMailOutboxStore, StudioMailOutboxSchedulingStore {
  _GatedStore(this.inner);

  final SqliteStudioMailDraftStore inner;
  Completer<void>? nextLoadGate;
  Completer<void>? scheduleGate;
  Completer<void>? beginGate;
  bool loadWaiting = false;
  bool scheduleWaiting = false;
  bool beginWaiting = false;

  @override
  MailAccountId get account => inner.account;

  @override
  Future<List<MailOutboxEntry>> loadOutbox() async {
    final gate = nextLoadGate;
    nextLoadGate = null;
    if (gate != null) {
      loadWaiting = true;
      await gate.future;
      loadWaiting = false;
    }
    return inner.loadOutbox();
  }

  @override
  Future<MailOutboxEntry> scheduleOutbox(
    MailOutboxEntry entry, {
    required DateTime? sendNotBefore,
  }) async {
    final gate = scheduleGate;
    if (gate != null) {
      scheduleWaiting = true;
      await gate.future;
      scheduleWaiting = false;
    }
    return inner.scheduleOutbox(entry, sendNotBefore: sendNotBefore);
  }

  @override
  Future<MailOutboxEntry> beginOutboxAttempt(
    MailOutboxEntry entry, {
    bool acknowledgeUncertain = false,
  }) async {
    final attempt = await inner.beginOutboxAttempt(
      entry,
      acknowledgeUncertain: acknowledgeUncertain,
    );
    final gate = beginGate;
    if (gate != null) {
      beginWaiting = true;
      await gate.future;
      beginWaiting = false;
    }
    return attempt;
  }

  @override
  Future<MailOutboxEntry> enqueueOutbox(StudioMailDraft draft, String sender) =>
      inner.enqueueOutbox(draft, sender);

  @override
  Future<MailOutboxEntry> completeOutboxAttempt(
    MailOutboxEntry entry,
    MailSubmissionResult result,
  ) => inner.completeOutboxAttempt(entry, result);

  @override
  Future<MailOutboxEntry> cancelOutbox(MailOutboxEntry entry) =>
      inner.cancelOutbox(entry);

  @override
  Future<void> removeOutbox(MailOutboxEntry entry) => inner.removeOutbox(entry);
}

final class _Fixture {
  _Fixture(this.database, this.store, this.clock, this.entry);

  final SqliteOutboxFixture database;
  final SqliteStudioMailDraftStore store;
  final _Clock clock;
  final MailOutboxEntry entry;
  int submissions = 0;
  bool current = true;

  Future<MailOutboxEntry> saved(WidgetTester tester) async =>
      (await awaitOutboxOperation(tester, store.loadOutbox())).single;

  Future<void> show(
    WidgetTester tester, {
    StudioStrings strings = _strings,
    Size size = const Size(1200, 950),
    StudioMailOutboxStore? adapter,
    ValueNotifier<StudioMailOutboxStore>? owner,
  }) async {
    final selection = owner ?? ValueNotifier(adapter ?? store);
    if (owner == null) addTearDown(selection.dispose);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => Directionality(
          textDirection: strings.language == StudioLanguage.ar
              ? TextDirection.rtl
              : TextDirection.ltr,
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                barrierDismissible: false,
                builder: (_) => ValueListenableBuilder<StudioMailOutboxStore>(
                  valueListenable: selection,
                  builder: (context, selected, _) => StudioMailOutboxDialog(
                    strings: strings,
                    store: selected,
                    clock: () => clock.now,
                    elapsed: () => clock.elapsed,
                    isCurrent: () => current,
                    submit: (message, {required attemptId}) async {
                      submissions++;
                      expectSync(message.wire.bytes, entry.prepared.wire.bytes);
                      expectSync(
                        message.envelope.recipients,
                        entry.prepared.envelope.recipients,
                      );
                      return MailSubmissionResult(
                        attemptId: attemptId,
                        outcome: MailSubmissionOutcome.accepted,
                      );
                    },
                  ),
                ),
              ),
              child: const Text('Open scheduled Outbox'),
            ),
          ),
        ),
      ),
    );
    await _tap(tester, find.text('Open scheduled Outbox'));
  }
}

Future<_Fixture> _fixture(WidgetTester tester) async {
  final identity = StudioMailDraftAccount(
    provider: 'imap',
    endpoint: 'imaps://imap.example.test:993',
    login: _sender,
    sender: _sender,
  );
  final database = await awaitOutboxOperation(
    tester,
    SqliteOutboxFixture.create(identity),
  );
  final clock = _Clock();
  final store = SqliteStudioMailDraftStore(
    repository: database.repository,
    account: identity.account,
    clock: () => clock.now,
  );
  database.adapters.add(store);
  await awaitOutboxOperation(tester, store.load());
  final entry = await awaitOutboxOperation(
    tester,
    store.enqueueOutbox(outboxFixtureDraft(), _sender),
  );
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await awaitOutboxOperation(tester, database.close());
  });
  return _Fixture(database, store, clock, entry);
}

void main() {
  setUpAll(initializeDateFormatting);

  testWidgets('undo delay never submits early and Undo retains frozen queue', (
    tester,
  ) async {
    final fixture = await _fixture(tester);
    await fixture.show(tester);
    await _tap(tester, _action('delay', fixture.entry));
    final scheduled = await fixture.saved(tester);
    expect(
      scheduled.sendNotBefore,
      fixture.clock.now.add(const Duration(seconds: 10)),
    );
    expect(scheduled.attemptNumber, 0);
    await fixture.clock.advance(tester, const Duration(seconds: 9));
    expect(fixture.submissions, 0);

    await _tap(tester, _action('undo', fixture.entry));
    final undone = await fixture.saved(tester);
    expect(undone.sendNotBefore, isNull);
    expect(undone.state, MailOutboxState.queued);
    expect(undone.scheduleRevision, scheduled.scheduleRevision + 1);
    expect(undone.prepared.wire.bytes, fixture.entry.prepared.wire.bytes);
    expect(
      undone.prepared.envelope.sender,
      fixture.entry.prepared.envelope.sender,
    );
    expect(
      undone.prepared.envelope.recipients,
      fixture.entry.prepared.envelope.recipients,
    );
    await fixture.clock.advance(tester, const Duration(minutes: 1));
    expect(fixture.submissions, 0);
    expect((await fixture.saved(tester)).attemptNumber, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a due undo-delay entry is submitted exactly once', (
    tester,
  ) async {
    final fixture = await _fixture(tester);
    await fixture.show(tester);
    await _tap(tester, _action('delay', fixture.entry));
    await fixture.clock.advance(tester, const Duration(seconds: 9));
    expect(fixture.submissions, 0);
    await fixture.clock.advance(tester, const Duration(seconds: 1));
    final sent = await fixture.saved(tester);
    expect(fixture.submissions, 1);
    expect(sent.state, MailOutboxState.submitted);
    expect(sent.attemptNumber, 1);
    await fixture.clock.advance(tester, const Duration(minutes: 1));
    expect(fixture.submissions, 1);
    expect(_action('resume', fixture.entry), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed schedule storage leaves the queue unarmed', (
    tester,
  ) async {
    final fixture = await _fixture(tester);
    await fixture.show(tester);
    fixture.database.failNextCheckpoint = MailStoreCheckpoint.afterOutboxWrite;
    await _tap(tester, _action('delay', fixture.entry));
    expect(find.text(_strings.mailOutboxFailed), findsOneWidget);
    expect((await fixture.saved(tester)).sendNotBefore, isNull);
    await fixture.clock.advance(tester, const Duration(minutes: 1));
    expect(fixture.submissions, 0);
    expect((await fixture.saved(tester)).attemptNumber, 0);
    expect(fixture.database.failNextCheckpoint, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'failed Undo storage pauses sending and preserves saved evidence',
    (tester) async {
      final fixture = await _fixture(tester);
      await fixture.show(tester);
      await _tap(tester, _action('delay', fixture.entry));
      final scheduled = await fixture.saved(tester);
      fixture.database.failNextCheckpoint =
          MailStoreCheckpoint.afterOutboxWrite;
      await _tap(tester, _action('undo', fixture.entry));
      expect(find.text(_strings.mailOutboxFailed), findsOneWidget);
      expect(_action('resume', fixture.entry), findsOneWidget);
      await fixture.clock.advance(tester, const Duration(minutes: 1));
      final retained = await fixture.saved(tester);
      expect(fixture.submissions, 0);
      expect(retained.sendNotBefore, scheduled.sendNotBefore);
      expect(retained.scheduleRevision, scheduled.scheduleRevision);
      expect(retained.attemptNumber, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'reopening an overdue schedule needs explicit Resume confirmation',
    (tester) async {
      final fixture = await _fixture(tester);
      await fixture.show(tester);
      await _tap(tester, _action('delay', fixture.entry));
      await _tap(tester, _icon(_strings.close));
      await fixture.clock.advance(tester, const Duration(minutes: 1));
      await _tap(tester, find.text('Open scheduled Outbox'));
      await fixture.clock.advance(tester, const Duration(seconds: 3));
      expect(fixture.submissions, 0);
      expect(find.text(_strings.mailSchedulePaused), findsOneWidget);
      await _tap(tester, _action('resume', fixture.entry));
      await fixture.clock.advance(tester, const Duration(seconds: 3));
      expect(fixture.submissions, 0);
      await _tap(
        tester,
        find.byKey(const ValueKey('studio-mail-outbox-confirm')),
      );
      await fixture.clock.advance(tester, const Duration(seconds: 1));
      expect(fixture.submissions, 1);
      expect((await fixture.saved(tester)).state, MailOutboxState.submitted);
      expect(tester.takeException(), isNull);
    },
  );

  for (final reason in ['app pause', 'account switch']) {
    testWidgets('$reason revokes automatic permission until explicit resume', (
      tester,
    ) async {
      final fixture = await _fixture(tester);
      await fixture.show(tester);
      await _tap(tester, _action('delay', fixture.entry));
      if (reason == 'app pause') {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      } else {
        fixture.current = false;
      }
      await fixture.clock.advance(tester, const Duration(seconds: 11));
      expect(fixture.submissions, 0);
      if (reason == 'app pause') {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      } else {
        fixture.current = true;
      }
      await fixture.clock.advance(tester, const Duration(seconds: 2));
      expect(fixture.submissions, 0);
      expect(_action('resume', fixture.entry), findsOneWidget);
      expect((await fixture.saved(tester)).attemptNumber, 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('rescheduling replaces the old deadline and its automatic arm', (
    tester,
  ) async {
    final fixture = await _fixture(tester);
    await fixture.show(tester);
    await _tap(tester, _action('delay', fixture.entry));
    final original = await fixture.saved(tester);
    await _tap(tester, _action('schedule', fixture.entry));
    await _tap(tester, find.byKey(const ValueKey('studio-mail-schedule-hour')));
    await _tap(
      tester,
      find.byKey(const ValueKey('studio-mail-schedule-confirm')),
    );
    final scheduled = await fixture.saved(tester);
    expect(scheduled.scheduleRevision, original.scheduleRevision + 1);
    expect(
      scheduled.sendNotBefore,
      fixture.clock.now.add(const Duration(hours: 1)),
    );
    await fixture.clock.advance(tester, const Duration(seconds: 11));
    expect(fixture.submissions, 0);
    await fixture.clock.advance(tester, const Duration(hours: 1));
    expect(fixture.submissions, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('refresh revokes an arm changed by another adapter', (
    tester,
  ) async {
    final fixture = await _fixture(tester);
    await fixture.show(tester);
    await _tap(tester, _action('delay', fixture.entry));
    final original = await fixture.saved(tester);
    final other = SqliteStudioMailDraftStore(
      repository: fixture.database.repository,
      account: fixture.store.account,
      clock: () => fixture.clock.now,
    );
    fixture.database.adapters.add(other);
    await awaitOutboxOperation(
      tester,
      other.scheduleOutbox(original, sendNotBefore: original.sendNotBefore),
    );
    await _tap(tester, _icon(_strings.refresh));
    expect(_action('resume', fixture.entry), findsOneWidget);
    await fixture.clock.advance(tester, const Duration(seconds: 11));
    expect(fixture.submissions, 0);
    expect((await fixture.saved(tester)).attemptNumber, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a slow post-save reload preserves the full usable Undo window', (
    tester,
  ) async {
    final fixture = await _fixture(tester);
    final adapter = _GatedStore(fixture.store);
    await fixture.show(tester, adapter: adapter);
    final reload = Completer<void>();
    adapter.nextLoadGate = reload;
    await _tap(tester, _action('delay', fixture.entry));
    expect(adapter.loadWaiting, isTrue);
    await fixture.clock.advance(tester, const Duration(seconds: 30));
    expect(fixture.submissions, 0);
    reload.complete();
    await pumpOutboxWidgets(tester);
    expect(
      tester.widget<TextButton>(_action('undo', fixture.entry)).onPressed,
      isNotNull,
    );
    await fixture.clock.advance(tester, const Duration(seconds: 9));
    expect(fixture.submissions, 0);
    await fixture.clock.advance(tester, const Duration(seconds: 1));
    expect(fixture.submissions, 1);
    expect((await fixture.saved(tester)).state, MailOutboxState.submitted);
    expect(tester.takeException(), isNull);
  });

  for (final reason in ['app pause', 'account owner change']) {
    testWidgets(
      '$reason while attempt persistence waits prevents provider send',
      (tester) async {
        final fixture = await _fixture(tester);
        final adapter = _GatedStore(fixture.store);
        final owner = ValueNotifier<StudioMailOutboxStore>(adapter);
        addTearDown(owner.dispose);
        await fixture.show(tester, owner: owner);
        final begin = Completer<void>();
        adapter.beginGate = begin;
        await _tap(tester, _action('delay', fixture.entry));
        await fixture.clock.advance(tester, const Duration(seconds: 10));
        expect(adapter.beginWaiting, isTrue);
        expect(fixture.submissions, 0);
        if (reason == 'app pause') {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.paused,
          );
        } else {
          owner.value = _GatedStore(fixture.store);
        }
        await fixture.clock.advance(tester, const Duration(seconds: 1));
        if (reason == 'app pause') {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
        } else {
          owner.value = adapter;
        }
        await pumpOutboxWidgets(tester);
        begin.complete();
        await pumpOutboxWidgets(tester);
        await fixture.clock.advance(tester, const Duration(seconds: 30));
        expect(fixture.submissions, 0);
        final saved = await fixture.saved(tester);
        expect(saved.attemptNumber, 1);
        expect(saved.state, MailOutboxState.retryableFailure);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('pause and resume during a schedule save cannot rearm it', (
    tester,
  ) async {
    final fixture = await _fixture(tester);
    final adapter = _GatedStore(fixture.store);
    await fixture.show(tester, adapter: adapter);
    final schedule = Completer<void>();
    adapter.scheduleGate = schedule;
    await _tap(tester, _action('delay', fixture.entry));
    expect(adapter.scheduleWaiting, isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await pumpOutboxWidgets(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    schedule.complete();
    await pumpOutboxWidgets(tester);
    await fixture.clock.advance(tester, const Duration(seconds: 11));
    expect(fixture.submissions, 0);
    expect(_action('resume', fixture.entry), findsOneWidget);
    expect((await fixture.saved(tester)).sendNotBefore, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a backward clock jump during attempt persistence stops send', (
    tester,
  ) async {
    final fixture = await _fixture(tester);
    final adapter = _GatedStore(fixture.store);
    await fixture.show(tester, adapter: adapter);
    final begin = Completer<void>();
    adapter.beginGate = begin;
    await _tap(tester, _action('delay', fixture.entry));
    await fixture.clock.advance(tester, const Duration(seconds: 10));
    expect(adapter.beginWaiting, isTrue);
    fixture.clock.now = fixture.clock.now.subtract(const Duration(hours: 1));
    begin.complete();
    await pumpOutboxWidgets(tester);
    expect(fixture.submissions, 0);
    expect(
      (await fixture.saved(tester)).state,
      MailOutboxState.retryableFailure,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('pause and resume during fresh Resume read cannot rearm it', (
    tester,
  ) async {
    final fixture = await _fixture(tester);
    await awaitOutboxOperation(
      tester,
      fixture.store.scheduleOutbox(
        fixture.entry,
        sendNotBefore: fixture.clock.now.add(const Duration(seconds: 10)),
      ),
    );
    await fixture.clock.advance(tester, const Duration(seconds: 11));
    final adapter = _GatedStore(fixture.store);
    await fixture.show(tester, adapter: adapter);
    await _tap(tester, _action('resume', fixture.entry));
    final refresh = Completer<void>();
    adapter.nextLoadGate = refresh;
    await _tap(
      tester,
      find.byKey(const ValueKey('studio-mail-outbox-confirm')),
    );
    expect(adapter.loadWaiting, isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await pumpOutboxWidgets(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    refresh.complete();
    await pumpOutboxWidgets(tester);
    await fixture.clock.advance(tester, const Duration(seconds: 3));
    expect(fixture.submissions, 0);
    expect(_action('resume', fixture.entry), findsOneWidget);
    expect((await fixture.saved(tester)).attemptNumber, 0);
    expect(tester.takeException(), isNull);
  });

  for (final language in StudioLanguage.values) {
    testWidgets('scheduled Outbox fits a narrow ${language.name} window', (
      tester,
    ) async {
      final strings = StudioStrings(language);
      final fixture = await _fixture(tester);
      await awaitOutboxOperation(
        tester,
        fixture.store.scheduleOutbox(
          fixture.entry,
          sendNotBefore: fixture.clock.now.add(const Duration(hours: 1)),
        ),
      );
      await fixture.show(tester, strings: strings, size: const Size(390, 780));
      expect(find.text(strings.mailSchedulePaused), findsOneWidget);
      await tester.ensureVisible(_action('resume', fixture.entry));
      await pumpOutboxWidgets(tester);
      expect(fixture.submissions, 0);
      expect(tester.takeException(), isNull);
    });
  }
}
