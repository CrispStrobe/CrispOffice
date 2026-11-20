import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:quds_office_studio/studio_mail_draft_store.dart';
import 'package:quds_office_studio/studio_mail_outbox.dart';
import 'package:quds_office_studio/studio_mail_outbox_dialog.dart';
import 'package:quds_office_studio/studio_mail_outbox_strings.dart';
import 'package:quds_office_studio/studio_strings.dart';

import 'support/mail_outbox_store.dart';

const _strings = StudioStrings(StudioLanguage.en);
const _sender = 'sender@example.test';

StudioMailDraftAccount _identity() => StudioMailDraftAccount(
  provider: 'imap',
  endpoint: 'imaps://imap.example.test:993',
  login: _sender,
  sender: _sender,
);

Finder _action(String action, MailOutboxEntry entry) =>
    find.byKey(ValueKey('studio-mail-outbox-$action-${entry.id}'));
Finder get _confirm => find.byKey(const ValueKey('studio-mail-outbox-confirm'));
Finder get _acknowledge =>
    find.byKey(const ValueKey('studio-mail-outbox-acknowledge'));

Future<void> _pump(WidgetTester tester) => pumpNativeOutboxWidgets(tester);

Future<void> _show(
  WidgetTester tester, {
  required StudioMailOutboxStore store,
  required StudioMailOutboxSubmit submit,
  bool Function()? isCurrent,
  StudioStrings strings = _strings,
}) async {
  await tester.binding.setSurfaceSize(const Size(1200, 950));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            child: const Text('Open Outbox fixture'),
            onPressed: () => showDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: (_) => StudioMailOutboxDialog(
                strings: strings,
                store: store,
                submit: submit,
                isCurrent: isCurrent ?? () => true,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open Outbox fixture'));
  await _pump(tester);
}

Future<({NativeOutboxFixture fixture, SqliteStudioMailDraftStore store})>
_fixture(WidgetTester tester) async {
  final fixture = (await tester.runAsync(
    () => NativeOutboxFixture.create(_identity()),
  ))!;
  addTearDown(fixture.close);
  return (
    fixture: fixture,
    store: await nativeOutboxIo(tester, fixture.openLoaded),
  );
}

Future<MailOutboxEntry> _uncertain(SqliteStudioMailDraftStore store) async {
  final queued = await store.enqueueOutbox(outboxFixtureDraft(), _sender);
  final attempt = await store.beginOutboxAttempt(queued);
  return store.completeOutboxAttempt(
    attempt,
    MailSubmissionResult(
      attemptId: attempt.attemptId!,
      outcome: MailSubmissionOutcome.uncertain,
    ),
  );
}

void main() {
  testWidgets('opening refreshing and reopening never sends a saved queue', (
    tester,
  ) async {
    final (:store, :fixture) = await _fixture(tester);
    final entry = await nativeOutboxIo(
      tester,
      () => store.enqueueOutbox(outboxFixtureDraft(), _sender),
    );
    var submissions = 0;
    await _show(
      tester,
      store: store,
      submit: (message, {required attemptId}) async {
        submissions++;
        return MailSubmissionResult(
          attemptId: attemptId,
          outcome: MailSubmissionOutcome.accepted,
        );
      },
    );
    expect(find.text('Frozen مرحبًا'), findsOneWidget);
    expect(
      find.text(_strings.mailOutboxState(MailOutboxState.queued)),
      findsOneWidget,
    );
    expect(
      find.text('to@example.test, copy@example.test, hidden@example.test'),
      findsNothing,
    );
    await tester.tap(find.text(_strings.mailOutboxRecipients));
    await _pump(tester);
    expect(
      find.text('to@example.test, copy@example.test, hidden@example.test'),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip(_strings.refresh));
    await _pump(tester);
    await tester.tap(find.byTooltip(_strings.close));
    await _pump(tester);
    await tester.tap(find.text('Open Outbox fixture'));
    await _pump(tester);
    expect(submissions, 0);
    final persisted = (await nativeOutboxIo(tester, store.loadOutbox)).single;
    expect(persisted.state, MailOutboxState.queued);
    expect(persisted.attemptNumber, 0);
    expect(persisted.prepared.wire.bytes, entry.prepared.wire.bytes);
    expect(await nativeOutboxIo(tester, store.load), isNull);
    expect(fixture.failNextCheckpoint, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'one in-flight action blocks duplicate callbacks and navigation',
    (tester) async {
      final (:store, fixture: _) = await _fixture(tester);
      final entry = await nativeOutboxIo(
        tester,
        () => store.enqueueOutbox(outboxFixtureDraft(), _sender),
      );
      final gate = Completer<MailSubmissionResult>();
      final attempts = <String>[];
      await _show(
        tester,
        store: store,
        submit: (message, {required attemptId}) async {
          attempts.add(attemptId);
          expect(
            (await store.loadOutbox()).single.state,
            MailOutboxState.submitting,
          );
          expect(message.wire.bytes, entry.prepared.wire.bytes);
          expect(
            message.envelope.recipients,
            entry.prepared.envelope.recipients,
          );
          return gate.future;
        },
      );
      final callback = tester
          .widget<FilledButton>(_action('send', entry))
          .onPressed!;
      callback();
      callback();
      await _pump(tester);
      expect(attempts, hasLength(1));
      expect(_action('send', entry), findsNothing);
      expect(
        find.text(_strings.mailOutboxState(MailOutboxState.submitting)),
        findsOneWidget,
      );
      expect(
        tester.widget<IconButton>(find.byTooltip(_strings.refresh)).onPressed,
        isNull,
      );
      expect(
        tester.widget<IconButton>(find.byTooltip(_strings.close)).onPressed,
        isNull,
      );
      gate.complete(
        MailSubmissionResult(
          attemptId: attempts.single,
          outcome: MailSubmissionOutcome.accepted,
        ),
      );
      await _pump(tester);
      expect(
        (await nativeOutboxIo(tester, store.loadOutbox)).single.state,
        MailOutboxState.submitted,
      );
      expect(_action('send', entry), findsNothing);
      expect(_action('cancel', entry), findsNothing);
      expect(_action('remove', entry), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('uncertain retry needs fresh acknowledgement after a rejection', (
    tester,
  ) async {
    final (:store, fixture: _) = await _fixture(tester);
    final entry = await nativeOutboxIo(tester, () => _uncertain(store));
    var submissions = 0;
    await _show(
      tester,
      store: store,
      submit: (message, {required attemptId}) async {
        submissions++;
        expect(message.wire.bytes, entry.prepared.wire.bytes);
        return MailSubmissionResult(
          attemptId: attemptId,
          outcome: MailSubmissionOutcome.rejected,
        );
      },
    );
    expect(_action('cancel', entry), findsNothing);
    expect(_action('remove', entry), findsNothing);
    await tester.tap(_action('send', entry));
    await _pump(tester);
    expect(tester.widget<FilledButton>(_confirm).onPressed, isNull);
    expect(submissions, 0);
    await tester.tap(_acknowledge);
    await tester.pump();
    expect(tester.widget<FilledButton>(_confirm).onPressed, isNotNull);
    await tester.tap(_confirm);
    await _pump(tester);
    expect(submissions, 1);
    final rejected = (await nativeOutboxIo(tester, store.loadOutbox)).single;
    expect(rejected.state, MailOutboxState.permanentFailure);
    expect(rejected.priorSubmissionUncertain, isTrue);
    expect(rejected.attemptNumber, 2);
    expect(_action('cancel', entry), findsNothing);
    expect(_action('remove', entry), findsNothing);
    await tester.tap(_action('send', entry));
    await _pump(tester);
    expect(tester.widget<CheckboxListTile>(_acknowledge).value, isFalse);
    expect(tester.widget<FilledButton>(_confirm).onPressed, isNull);
    await tester.tap(find.widgetWithText(TextButton, _strings.cancel));
    await _pump(tester);
    expect(submissions, 1);
    expect(
      (await nativeOutboxIo(tester, store.loadOutbox)).single.attemptNumber,
      2,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancel and local removal each require their own confirmation', (
    tester,
  ) async {
    final (:store, fixture: _) = await _fixture(tester);
    final entry = await nativeOutboxIo(
      tester,
      () => store.enqueueOutbox(outboxFixtureDraft(), _sender),
    );
    await _show(
      tester,
      store: store,
      submit: (_, {required attemptId}) async =>
          throw StateError('Must not send'),
    );
    expect(_action('remove', entry), findsNothing);
    await tester.tap(_action('cancel', entry));
    await _pump(tester);
    await tester.tap(find.widgetWithText(TextButton, _strings.cancel));
    await _pump(tester);
    expect(
      (await nativeOutboxIo(tester, store.loadOutbox)).single.state,
      MailOutboxState.queued,
    );
    await tester.tap(_action('cancel', entry));
    await _pump(tester);
    await tester.tap(_confirm);
    await _pump(tester);
    expect(
      (await nativeOutboxIo(tester, store.loadOutbox)).single.state,
      MailOutboxState.cancelled,
    );
    expect(_action('send', entry), findsNothing);
    expect(_action('cancel', entry), findsNothing);
    await tester.tap(_action('remove', entry));
    await _pump(tester);
    expect(find.text(_strings.mailOutboxRemoveExplanation), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, _strings.cancel));
    await _pump(tester);
    expect(await nativeOutboxIo(tester, store.loadOutbox), hasLength(1));
    await tester.tap(_action('remove', entry));
    await _pump(tester);
    await tester.tap(_confirm);
    await _pump(tester);
    expect(await nativeOutboxIo(tester, store.loadOutbox), isEmpty);
    expect(find.text(_strings.mailOutboxEmpty), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('attempt commit failure prevents transport and retains queue', (
    tester,
  ) async {
    final (:store, :fixture) = await _fixture(tester);
    final entry = await nativeOutboxIo(
      tester,
      () => store.enqueueOutbox(outboxFixtureDraft(), _sender),
    );
    var submissions = 0;
    await _show(
      tester,
      store: store,
      submit: (_, {required attemptId}) async {
        submissions++;
        return MailSubmissionResult(
          attemptId: attemptId,
          outcome: MailSubmissionOutcome.accepted,
        );
      },
    );
    fixture.failNextCheckpoint = MailStoreCheckpoint.beforeCommit;
    await tester.tap(_action('send', entry));
    await _pump(tester);
    expect(submissions, 0);
    expect(
      (await nativeOutboxIo(tester, store.loadOutbox)).single.state,
      MailOutboxState.queued,
    );
    expect(find.text(_strings.mailOutboxFailed), findsOneWidget);
    await tester.tap(find.byTooltip(_strings.refresh));
    await _pump(tester);
    expect(submissions, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'lost accepted-result commit recovers uncertain without resending',
    (tester) async {
      final (:store, :fixture) = await _fixture(tester);
      final entry = await nativeOutboxIo(
        tester,
        () => store.enqueueOutbox(outboxFixtureDraft(), _sender),
      );
      var submissions = 0;
      await _show(
        tester,
        store: store,
        submit: (_, {required attemptId}) async {
          submissions++;
          fixture.failNextCheckpoint = MailStoreCheckpoint.beforeCommit;
          return MailSubmissionResult(
            attemptId: attemptId,
            outcome: MailSubmissionOutcome.accepted,
          );
        },
      );
      await tester.tap(_action('send', entry));
      await _pump(tester);
      expect(submissions, 1);
      expect(
        (await nativeOutboxIo(tester, store.loadOutbox)).single.state,
        MailOutboxState.uncertain,
      );
      expect(find.text(_strings.mailOutboxFailed), findsOneWidget);
      expect(_action('cancel', entry), findsNothing);
      expect(_action('remove', entry), findsNothing);
      await tester.tap(find.byTooltip(_strings.refresh));
      await _pump(tester);
      expect(submissions, 1);
      await tester.tap(_action('send', entry));
      await _pump(tester);
      expect(tester.widget<FilledButton>(_confirm).onPressed, isNull);
      await tester.tap(find.widgetWithText(TextButton, _strings.cancel));
      await _pump(tester);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('account invalidation while acknowledging prevents submission', (
    tester,
  ) async {
    final (:store, fixture: _) = await _fixture(tester);
    final entry = await nativeOutboxIo(tester, () => _uncertain(store));
    var current = true;
    var submissions = 0;
    await _show(
      tester,
      store: store,
      isCurrent: () => current,
      submit: (_, {required attemptId}) async {
        submissions++;
        return MailSubmissionResult(
          attemptId: attemptId,
          outcome: MailSubmissionOutcome.accepted,
        );
      },
    );
    await tester.tap(_action('send', entry));
    await _pump(tester);
    await tester.tap(_acknowledge);
    await tester.pump();
    current = false;
    await tester.tap(_confirm);
    await _pump(tester);
    expect(submissions, 0);
    expect(
      (await nativeOutboxIo(tester, store.loadOutbox)).single.attemptNumber,
      1,
    );
    expect(tester.takeException(), isNull);
  });

  for (final language in [StudioLanguage.de, StudioLanguage.ar]) {
    testWidgets('localized queue controls are usable in ${language.name}', (
      tester,
    ) async {
      final (:store, fixture: _) = await _fixture(tester);
      final entry = await nativeOutboxIo(
        tester,
        () => store.enqueueOutbox(outboxFixtureDraft(), _sender),
      );
      final strings = StudioStrings(language);
      await _show(
        tester,
        store: store,
        strings: strings,
        submit: (_, {required attemptId}) async =>
            throw StateError('Must not send'),
      );
      expect(find.text(strings.mailOutbox), findsOneWidget);
      expect(
        find.text(strings.mailOutboxState(MailOutboxState.queued)),
        findsOneWidget,
      );
      expect(_action('send', entry), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
