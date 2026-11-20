import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:quds_office_studio/studio_mail_draft.dart';
import 'package:quds_office_studio/studio_mail_draft_store.dart';
import 'package:quds_office_studio/studio_mail_outbox_dialog.dart';
import 'package:quds_office_studio/studio_mail_outbox_export.dart';
import 'package:quds_office_studio/studio_mail_outbox_review.dart';
import 'package:quds_office_studio/studio_mail_outbox_strings.dart';
import 'package:quds_office_studio/studio_strings.dart';

import 'support/mail_outbox_store.dart';

const _strings = StudioStrings(StudioLanguage.en);
const _sender = 'sender@example.test';
final _identity = StudioMailDraftAccount(
  provider: 'imap',
  endpoint: 'imaps://imap.example.test:993',
  login: _sender,
  sender: _sender,
);

Future<({SqliteOutboxFixture fixture, SqliteStudioMailDraftStore store})>
_fixture(WidgetTester tester) async {
  final fixture = await awaitOutboxOperation(
    tester,
    SqliteOutboxFixture.create(_identity),
  );
  addTearDown(() => awaitOutboxOperation(tester, fixture.close()));
  return (
    fixture: fixture,
    store: await awaitOutboxOperation(tester, fixture.openLoaded()),
  );
}

Finder _action(String name, MailOutboxEntry entry) =>
    find.byKey(ValueKey('studio-mail-outbox-$name-${entry.id}'));
Finder get _confirm => find.byKey(const ValueKey('studio-mail-outbox-confirm'));

Future<void> _press(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await pumpOutboxWidgets(tester);
}

Future<void> _show(
  WidgetTester tester,
  SqliteStudioMailDraftStore store, {
  StudioMailOutboxExporter? exporter,
  void Function(StudioMailDraft?)? onClosed,
  bool Function()? isCurrent,
  StudioStrings strings = _strings,
}) async {
  await tester.binding.setSurfaceSize(const Size(900, 800));
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
            child: const Text('Open'),
            onPressed: () async {
              final edited = await showDialog<StudioMailDraft>(
                context: context,
                barrierDismissible: false,
                builder: (_) => StudioMailOutboxDialog(
                  strings: strings,
                  store: store,
                  isCurrent: isCurrent ?? () => true,
                  submit: (_, {required attemptId}) async =>
                      throw StateError('Review must not submit'),
                  exporter:
                      exporter ??
                      (
                        _,
                        _, {
                        required cancellation,
                        required isCurrent,
                      }) async => const MailSuccess(false),
                ),
              );
              onClosed?.call(edited);
            },
          ),
        ),
      ),
    ),
  );
  await _press(tester, find.text('Open'));
}

Future<MailOutboxEntry> _uncertain(
  WidgetTester tester,
  SqliteStudioMailDraftStore store,
) async {
  final queued = await awaitOutboxOperation(
    tester,
    store.enqueueOutbox(outboxFixtureDraft(), _sender),
  );
  final attempt = await awaitOutboxOperation(
    tester,
    store.beginOutboxAttempt(queued),
  );
  return awaitOutboxOperation(
    tester,
    store.completeOutboxAttempt(
      attempt,
      MailSubmissionResult(
        attemptId: attempt.attemptId!,
        outcome: MailSubmissionOutcome.uncertain,
      ),
    ),
  );
}

void main() {
  testWidgets(
    'review preserves private recipients, exact export and queue without submitting',
    (tester) async {
      final (:store, fixture: _) = await _fixture(tester);
      final queued = await awaitOutboxOperation(
        tester,
        store.enqueueOutbox(
          StudioMailDraft(
            to: 'to@example.test',
            cc: 'copy@example.test',
            bcc: 'hidden@example.test',
            subject: 'Frozen مرحبًا',
            body: '<img src="https://example.test/tracker"> text',
            attachments: StudioMailAttachments.from([
              StudioMailAttachment(
                name: 'résumé.bin',
                bytes: Uint8List.fromList([0, 10, 128, 255]),
              ),
            ]),
          ),
          _sender,
        ),
      );
      final exports = <(String, MailBytes)>[];
      await _show(
        tester,
        store,
        exporter:
            (name, bytes, {required cancellation, required isCurrent}) async {
              expectSync(isCurrent(), true);
              expectSync(cancellation.isCancelled, false);
              exports.add((name, bytes));
              return const MailSuccess(true);
            },
      );
      await _press(tester, _action('review', queued));
      expect(find.byType(StudioMailOutboxReviewDialog), findsOneWidget);
      expect(find.text('hidden@example.test'), findsOneWidget);
      expect(
        find.text('<img src="https://example.test/tracker"> text'),
        findsOneWidget,
      );
      expect(find.byType(Image), findsNothing);
      await _press(
        tester,
        find.byKey(const ValueKey('studio-mail-outbox-export-eml')),
      );
      expect(exports.single.$1, 'outbox-message.eml');
      expect(exports.single.$2.bytes, queued.prepared.wire.bytes);
      expect(
        ascii.decode(exports.single.$2.bytes),
        isNot(contains('hidden@example.test')),
      );
      await _press(
        tester,
        find.byKey(const ValueKey('studio-mail-outbox-export-envelope')),
      );
      expect(exports, hasLength(1));
      expect(
        find.text(_strings.mailOutboxExportPrivateExplanation),
        findsOneWidget,
      );
      await _press(
        tester,
        find.byKey(const ValueKey('studio-mail-outbox-export-private-confirm')),
      );
      expect(exports, hasLength(2));
      final json = jsonDecode(utf8.decode(exports.last.$2.bytes)) as Map;
      expect(json['recipients'], queued.prepared.envelope.recipients);
      expect(json['messageSha256'], queued.prepared.wireHash);
      await _press(
        tester,
        find.byKey(const ValueKey('studio-mail-outbox-review-close')),
      );
      final current = (await awaitOutboxOperation(
        tester,
        store.loadOutbox(),
      )).single;
      expect(current.state, MailOutboxState.queued);
      expect(current.attemptNumber, 0);
      expect(current.prepared.wire.bytes, queued.prepared.wire.bytes);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'editing creates a distinct selected durable draft and leaves siblings and original bytes intact',
    (tester) async {
      final (:store, fixture: _) = await _fixture(tester);
      final queued = await awaitOutboxOperation(
        tester,
        store.enqueueOutbox(outboxFixtureDraft(), _sender),
      );
      final originalId = store.selectedDraftId;
      await awaitOutboxOperation(
        tester,
        store.createDraft(
          outboxFixtureDraft(subject: 'Other unfinished message'),
        ),
      );
      final siblingId = store.selectedDraftId;
      final beforeEpoch = store.selectionEpoch;
      StudioMailDraft? returned;
      await _show(tester, store, onClosed: (draft) => returned = draft);
      await _press(tester, _action('edit', queued));
      expect(find.text(_strings.mailOutboxEditExplanation), findsOneWidget);
      await _press(tester, _confirm);
      expect(returned?.subject, 'Frozen مرحبًا');
      expect(returned?.bcc, 'hidden@example.test');
      expect(find.byType(StudioMailOutboxDialog), findsNothing);
      expect(store.selectedDraftId, isNot(originalId));
      expect(store.selectedDraftId, isNot(siblingId));
      expect(store.selectionEpoch, beforeEpoch + 1);
      final rows = await awaitOutboxOperation(tester, store.listDrafts());
      expect(
        rows.drafts.map((draft) => draft.subject),
        containsAll(['Frozen مرحبًا', 'Other unfinished message']),
      );
      expect(rows.drafts, hasLength(2));
      final cancelled = (await awaitOutboxOperation(
        tester,
        store.loadOutbox(),
      )).single;
      expect(cancelled.state, MailOutboxState.cancelled);
      expect(cancelled.prepared.wire.bytes, queued.prepared.wire.bytes);
      final reopened = await awaitOutboxOperation(tester, store.load());
      expect(reopened?.draft.bcc, 'hidden@example.test');
      expect(reopened?.submissionUncertain, false);
      final requeued = await awaitOutboxOperation(
        tester,
        store.enqueueOutbox(returned!, _sender),
      );
      expect(requeued.id, isNot(queued.id));
      expect(requeued.prepared.draftId, isNot(queued.prepared.draftId));
      expect(requeued.prepared.wireHash, isNot(queued.prepared.wireHash));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'failed atomic edit keeps queue and selection and permits a fresh explicit retry',
    (tester) async {
      final (:store, :fixture) = await _fixture(tester);
      final queued = await awaitOutboxOperation(
        tester,
        store.enqueueOutbox(outboxFixtureDraft(), _sender),
      );
      final selectedId = store.selectedDraftId;
      final selectedEpoch = store.selectionEpoch;
      fixture.failNextCheckpoint = MailStoreCheckpoint.afterOutboxWrite;
      await _show(tester, store);
      await _press(tester, _action('edit', queued));
      await _press(tester, _confirm);
      expect(find.text(_strings.mailOutboxFailed), findsOneWidget);
      expect(store.selectedDraftId, selectedId);
      expect(store.selectionEpoch, selectedEpoch);
      expect(
        (await awaitOutboxOperation(tester, store.listDrafts())).drafts,
        isEmpty,
      );
      expect(
        (await awaitOutboxOperation(tester, store.loadOutbox())).single.state,
        MailOutboxState.queued,
      );
      await _press(tester, _action('edit', queued));
      await _press(tester, _confirm);
      expect(find.byType(StudioMailOutboxDialog), findsNothing);
      expect(
        (await awaitOutboxOperation(tester, store.listDrafts())).drafts,
        hasLength(1),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'stopping uncertain retries preserves unknown delivery and requires separate cleanup',
    (tester) async {
      final (:store, fixture: _) = await _fixture(tester);
      final uncertain = await _uncertain(tester, store);
      await _show(tester, store);
      expect(_action('edit', uncertain), findsNothing);
      expect(_action('cancel', uncertain), findsNothing);
      expect(_action('remove', uncertain), findsNothing);
      await _press(tester, _action('stop', uncertain));
      expect(
        find.text(_strings.mailOutboxStopRetryingExplanation),
        findsOneWidget,
      );
      await _press(tester, _confirm);
      final closed = (await awaitOutboxOperation(
        tester,
        store.loadOutbox(),
      )).single;
      expect(closed.state, MailOutboxState.closedUncertain);
      expect(closed.result?.outcome, MailSubmissionOutcome.uncertain);
      expect(closed.attemptId, uncertain.attemptId);
      expect(closed.prepared.wire.bytes, uncertain.prepared.wire.bytes);
      expect(_action('send', closed), findsNothing);
      expect(_action('stop', closed), findsNothing);
      expect(find.text(_strings.mailOutboxClosedExplanation), findsOneWidget);
      await _press(tester, _action('remove', closed));
      expect(
        find.text(_strings.mailOutboxRemoveUnknownExplanation),
        findsOneWidget,
      );
      final cancel = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text(_strings.cancel),
      );
      await _press(tester, cancel);
      expect(
        (await awaitOutboxOperation(tester, store.loadOutbox())),
        hasLength(1),
      );
      await _press(tester, _action('remove', closed));
      await _press(tester, _confirm);
      expect((await awaitOutboxOperation(tester, store.loadOutbox())), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('stale confirmation cannot edit or close an entry', (
    tester,
  ) async {
    final (:store, fixture: _) = await _fixture(tester);
    final queued = await awaitOutboxOperation(
      tester,
      store.enqueueOutbox(outboxFixtureDraft(), _sender),
    );
    var current = true;
    await _show(tester, store, isCurrent: () => current);
    await _press(tester, _action('edit', queued));
    current = false;
    await _press(tester, _confirm);
    expect(
      (await awaitOutboxOperation(tester, store.loadOutbox())).single.state,
      MailOutboxState.queued,
    );
    expect(
      (await awaitOutboxOperation(tester, store.listDrafts())).drafts,
      isEmpty,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('stale edit callbacks cannot overwrite the newly selected copy', (
    tester,
  ) async {
    final (:store, fixture: _) = await _fixture(tester);
    final queued = await awaitOutboxOperation(
      tester,
      store.enqueueOutbox(outboxFixtureDraft(), _sender),
    );
    final editing = store.editOutboxAsDraft(queued);
    final staleSave = store.save(
      outboxFixtureDraft(subject: 'Stale editor'),
      submissionUncertain: false,
    );
    final staleExpectation = expectLater(
      staleSave,
      throwsA(
        isA<StudioMailDraftStoreException>().having(
          (error) => error.code,
          'reason',
          MailProblemCode.staleOperation,
        ),
      ),
    );
    await awaitOutboxOperation(tester, editing);
    await staleExpectation;
    expect(
      (await awaitOutboxOperation(tester, store.load()))?.draft.subject,
      'Frozen مرحبًا',
    );
    final duplicate = store.editOutboxAsDraft(queued);
    final duplicateExpectation = expectLater(
      duplicate,
      throwsA(isA<StudioMailDraftStoreException>()),
    );
    await awaitOutboxOperation(tester, duplicateExpectation);
    expect(
      (await awaitOutboxOperation(tester, store.listDrafts())).drafts,
      hasLength(1),
    );
  });
}
