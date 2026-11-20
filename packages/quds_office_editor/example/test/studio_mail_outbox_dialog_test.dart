import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
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
Finder _outboxIcon(String tooltip) => find.descendant(
  of: find.byType(StudioMailOutboxDialog),
  matching: find.byWidgetPredicate(
    (widget) => widget is IconButton && widget.tooltip == tooltip,
  ),
);

var _fontsLoaded = false;
Future<void> _loadPreviewFonts(WidgetTester tester) async {
  if (_fontsLoaded) return;
  await tester.runAsync(() async {
    final textFont = FontLoader('OutboxPreview')
      ..addFont(rootBundle.load('fonts/Tajawal-Regular.ttf'));
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await textFont.load();
    await icons.load();
  });
  _fontsLoaded = true;
}

Future<void> _pump(WidgetTester tester) => pumpOutboxWidgets(tester);

Future<void> _show(
  WidgetTester tester, {
  required StudioMailOutboxStore store,
  required StudioMailOutboxSubmit submit,
  bool Function()? isCurrent,
  StudioStrings strings = _strings,
  Size size = const Size(1200, 950),
  bool previewFonts = false,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    RepaintBoundary(
      key: const ValueKey('outbox-capture'),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: previewFonts ? ThemeData(fontFamily: 'OutboxPreview') : null,
        builder: (context, child) => Directionality(
          textDirection: strings.language == StudioLanguage.ar
              ? TextDirection.rtl
              : TextDirection.ltr,
          child: child!,
        ),
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
    ),
  );
  await tester.tap(find.text('Open Outbox fixture'));
  await _pump(tester);
}

Future<({SqliteOutboxFixture fixture, SqliteStudioMailDraftStore store})>
_fixture(WidgetTester tester) async {
  final fixture = await awaitOutboxOperation(
    tester,
    SqliteOutboxFixture.create(_identity()),
  );
  addTearDown(() => awaitOutboxOperation(tester, fixture.close()));
  return (
    fixture: fixture,
    store: await awaitOutboxOperation(tester, fixture.openLoaded()),
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
    final entry = await awaitOutboxOperation(
      tester,
      store.enqueueOutbox(outboxFixtureDraft(), _sender),
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
    await tester.tap(_outboxIcon(_strings.refresh));
    await _pump(tester);
    await tester.tap(_outboxIcon(_strings.close));
    await _pump(tester);
    await tester.tap(find.text('Open Outbox fixture'));
    await _pump(tester);
    expect(submissions, 0);
    final persisted = (await awaitOutboxOperation(
      tester,
      store.loadOutbox(),
    )).single;
    expect(persisted.state, MailOutboxState.queued);
    expect(persisted.attemptNumber, 0);
    expect(persisted.prepared.wire.bytes, entry.prepared.wire.bytes);
    expect(await awaitOutboxOperation(tester, store.load()), isNull);
    expect(fixture.failNextCheckpoint, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'one in-flight action blocks duplicate callbacks and navigation',
    (tester) async {
      final (:store, fixture: _) = await _fixture(tester);
      final entry = await awaitOutboxOperation(
        tester,
        store.enqueueOutbox(outboxFixtureDraft(), _sender),
      );
      final gate = Completer<MailSubmissionResult>();
      final attempts = <String>[];
      await _show(
        tester,
        store: store,
        submit: (message, {required attemptId}) async {
          attempts.add(attemptId);
          expectSync(
            (await store.loadOutbox()).single.state,
            MailOutboxState.submitting,
          );
          expectSync(message.wire.bytes, entry.prepared.wire.bytes);
          expectSync(
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
        tester.widget<IconButton>(_outboxIcon(_strings.refresh)).onPressed,
        isNull,
      );
      expect(
        tester.widget<IconButton>(_outboxIcon(_strings.close)).onPressed,
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
        (await awaitOutboxOperation(tester, store.loadOutbox())).single.state,
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
    final entry = await awaitOutboxOperation(tester, _uncertain(store));
    var submissions = 0;
    await _show(
      tester,
      store: store,
      submit: (message, {required attemptId}) async {
        submissions++;
        expectSync(message.wire.bytes, entry.prepared.wire.bytes);
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
    final rejected = (await awaitOutboxOperation(
      tester,
      store.loadOutbox(),
    )).single;
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
      (await awaitOutboxOperation(
        tester,
        store.loadOutbox(),
      )).single.attemptNumber,
      2,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancel and local removal each require their own confirmation', (
    tester,
  ) async {
    final (:store, fixture: _) = await _fixture(tester);
    final entry = await awaitOutboxOperation(
      tester,
      store.enqueueOutbox(outboxFixtureDraft(), _sender),
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
      (await awaitOutboxOperation(tester, store.loadOutbox())).single.state,
      MailOutboxState.queued,
    );
    await tester.tap(_action('cancel', entry));
    await _pump(tester);
    await tester.tap(_confirm);
    await _pump(tester);
    expect(
      (await awaitOutboxOperation(tester, store.loadOutbox())).single.state,
      MailOutboxState.cancelled,
    );
    expect(_action('send', entry), findsNothing);
    expect(_action('cancel', entry), findsNothing);
    await tester.tap(_action('remove', entry));
    await _pump(tester);
    expect(find.text(_strings.mailOutboxRemoveExplanation), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, _strings.cancel));
    await _pump(tester);
    expect(
      await awaitOutboxOperation(tester, store.loadOutbox()),
      hasLength(1),
    );
    await tester.tap(_action('remove', entry));
    await _pump(tester);
    await tester.tap(_confirm);
    await _pump(tester);
    expect(await awaitOutboxOperation(tester, store.loadOutbox()), isEmpty);
    expect(find.text(_strings.mailOutboxEmpty), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('attempt commit failure prevents transport and retains queue', (
    tester,
  ) async {
    final (:store, :fixture) = await _fixture(tester);
    final entry = await awaitOutboxOperation(
      tester,
      store.enqueueOutbox(outboxFixtureDraft(), _sender),
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
      (await awaitOutboxOperation(tester, store.loadOutbox())).single.state,
      MailOutboxState.queued,
    );
    expect(find.text(_strings.mailOutboxFailed), findsOneWidget);
    await tester.tap(_outboxIcon(_strings.refresh));
    await _pump(tester);
    expect(submissions, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'lost accepted-result commit recovers uncertain without resending',
    (tester) async {
      final (:store, :fixture) = await _fixture(tester);
      final entry = await awaitOutboxOperation(
        tester,
        store.enqueueOutbox(outboxFixtureDraft(), _sender),
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
        (await awaitOutboxOperation(tester, store.loadOutbox())).single.state,
        MailOutboxState.uncertain,
      );
      expect(find.text(_strings.mailOutboxFailed), findsOneWidget);
      expect(_action('cancel', entry), findsNothing);
      expect(_action('remove', entry), findsNothing);
      await tester.tap(_outboxIcon(_strings.refresh));
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
    final entry = await awaitOutboxOperation(tester, _uncertain(store));
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
      (await awaitOutboxOperation(
        tester,
        store.loadOutbox(),
      )).single.attemptNumber,
      1,
    );
    expect(tester.takeException(), isNull);
  });

  for (final language in StudioLanguage.values) {
    testWidgets('localized queue controls are usable in ${language.name}', (
      tester,
    ) async {
      final (:store, fixture: _) = await _fixture(tester);
      final entry = await awaitOutboxOperation(
        tester,
        store.enqueueOutbox(outboxFixtureDraft(), _sender),
      );
      final strings = StudioStrings(language);
      await _loadPreviewFonts(tester);
      await _show(
        tester,
        store: store,
        strings: strings,
        size: const Size(700, 660),
        previewFonts: true,
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
      final captureDirectory =
          Platform.environment['MAIL_OUTBOX_SCREENSHOT_DIR'];
      if (captureDirectory != null) {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('outbox-capture')),
        );
        await tester.runAsync(() async {
          final directory = await Directory(
            captureDirectory,
          ).create(recursive: true);
          final image = await boundary.toImage(pixelRatio: 1);
          try {
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File(
              '${directory.path}/outbox-${language.name}.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
          } finally {
            image.dispose();
          }
        });
      }
      expect(tester.takeException(), isNull);
    });
  }
}
