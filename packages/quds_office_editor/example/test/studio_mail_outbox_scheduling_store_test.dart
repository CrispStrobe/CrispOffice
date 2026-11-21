import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store_native.dart';
import 'package:quds_office_studio/studio_mail_draft.dart';
import 'package:quds_office_studio/studio_mail_draft_store.dart';
import 'package:quds_office_studio/studio_mail_outbox.dart';

const _sender = 'writer@example.test';
final _identity = StudioMailDraftAccount(
  provider: 'imap',
  endpoint: 'imaps://imap.example.test:993',
  login: _sender,
  sender: _sender,
);

T _value<T>(MailResult<T> result) {
  expectSync(result, isA<MailSuccess<T>>());
  return (result as MailSuccess<T>).value;
}

Matcher _problem(MailProblemCode code) => isA<StudioMailDraftStoreException>()
    .having((error) => error.code, 'code', code);

void main() {
  late Directory directory;
  late DateTime now;
  late SqliteMailRepository repository;
  late SqliteStudioMailDraftStore store;
  MailStoreCheckpoint? fail;

  Future<void> open({bool createAccount = true}) async {
    repository = _value(
      await openNativeMailStore(
        appDirectory: directory,
        profile: _identity.profile,
        clock: () => now,
        faultInjector: (checkpoint) {
          if (checkpoint == fail) {
            fail = null;
            throw const MailStoreStorageException(
              MailProblemCode.storageFailure,
            );
          }
        },
      ),
    );
    if (createAccount) {
      _value(
        await repository.createAccount(
          MailStoreAccount(
            id: _identity.account,
            provider: _identity.provider,
            displayName: 'Scheduling fixture',
          ),
        ),
      );
    }
    store = SqliteStudioMailDraftStore(
      repository: repository,
      account: _identity.account,
      ownsRepository: true,
      clock: () => now,
    );
    await store.load();
  }

  Future<MailOutboxEntry> queued() => store.enqueueOutbox(
    const StudioMailDraft(
      to: 'reader@example.test',
      bcc: 'hidden@example.test',
      subject: 'Scheduled fixture',
      body: 'Original frozen text.',
    ),
    _sender,
  );

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('studio-mail-schedule-');
    now = DateTime.utc(2026, 11, 21, 10);
    fail = null;
    await open();
  });
  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });

  test(
    'deadline and private frozen recipients survive owner and database reopen',
    () async {
      final original = await queued();
      final deadline = now.add(const Duration(hours: 1));
      final scheduled = await store.scheduleOutbox(
        original,
        sendNotBefore: deadline,
      );
      await store.close();
      await open(createAccount: false);
      final restored = (await store.loadOutbox()).single;
      expect(restored.sendNotBefore, deadline);
      expect(restored.scheduleRevision, scheduled.scheduleRevision);
      expect(restored.state, MailOutboxState.queued);
      expect(restored.attemptNumber, 0);
      expect(restored.prepared.wireHash, original.prepared.wireHash);
      expect(
        restored.prepared.envelope.recipients,
        original.prepared.envelope.recipients,
      );
      expect(store, isA<StudioMailOutboxSchedulingStore>());
    },
  );

  test(
    'raw backward clock cannot borrow a clamped timestamp to send early',
    () async {
      final original = await queued();
      final scheduled = await store.scheduleOutbox(
        original,
        sendNotBefore: now.add(const Duration(minutes: 1)),
      );
      now = now.subtract(const Duration(days: 1));
      await expectLater(
        store.beginOutboxAttempt(scheduled),
        throwsA(_problem(MailProblemCode.conflict)),
      );
      expect((await store.loadOutbox()).single.attemptNumber, 0);
      now = scheduled.sendNotBefore!;
      final attempt = await store.beginOutboxAttempt(scheduled);
      expect(attempt.state, MailOutboxState.submitting);
      expect(attempt.scheduleRevision, scheduled.scheduleRevision);
    },
  );

  test(
    'stale schedule snapshots cannot send cancel undo or edit after ABA',
    () async {
      final original = await queued();
      final deadline = now.add(const Duration(minutes: 1));
      final first = await store.scheduleOutbox(
        original,
        sendNotBefore: deadline,
      );
      final cleared = await store.scheduleOutbox(first, sendNotBefore: null);
      final latest = await store.scheduleOutbox(
        cleared,
        sendNotBefore: deadline,
      );
      now = deadline;
      for (final operation in <Future<Object?> Function()>[
        () => store.beginOutboxAttempt(first),
        () => store.cancelOutbox(first),
        () => store.scheduleOutbox(first, sendNotBefore: null),
        () => store.editOutboxAsDraft(first),
      ]) {
        await expectLater(
          operation(),
          throwsA(_problem(MailProblemCode.conflict)),
        );
      }
      expect(
        (await store.loadOutbox()).single.scheduleRevision,
        latest.scheduleRevision,
      );
      expect((await store.loadOutbox()).single.attemptNumber, 0);
    },
  );

  test(
    'failed undo rolls back deadline and keeps the original queue payload',
    () async {
      final original = await queued();
      final scheduled = await store.scheduleOutbox(
        original,
        sendNotBefore: now.add(const Duration(minutes: 1)),
      );
      fail = MailStoreCheckpoint.afterOutboxWrite;
      await expectLater(
        store.scheduleOutbox(scheduled, sendNotBefore: null),
        throwsA(_problem(MailProblemCode.storageFailure)),
      );
      final restored = (await store.loadOutbox()).single;
      expect(restored.sendNotBefore, scheduled.sendNotBefore);
      expect(restored.scheduleRevision, scheduled.scheduleRevision);
      expect(restored.prepared.wireHash, original.prepared.wireHash);
      final undone = await store.scheduleOutbox(restored, sendNotBefore: null);
      expect(undone.sendNotBefore, isNull);
      expect(undone.state, MailOutboxState.queued);
      expect(undone.attemptNumber, 0);
    },
  );

  test(
    'past or foreign schedules are rejected without changing queue data',
    () async {
      final original = await queued();
      await expectLater(
        store.scheduleOutbox(original, sendNotBefore: now),
        throwsA(_problem(MailProblemCode.invalidInput)),
      );
      final other = MailAccountId('other', profile: _identity.profile);
      final foreign = MailOutboxEntry.queued(
        id: original.id,
        now: now,
        prepared: MailPreparedMessage(
          account: other,
          draftId: original.prepared.draftId,
          draftRevision: original.prepared.draftRevision,
          wire: original.prepared.wire,
          envelope: original.prepared.envelope,
        ),
      );
      await expectLater(
        store.scheduleOutbox(
          foreign,
          sendNotBefore: now.add(const Duration(minutes: 1)),
        ),
        throwsA(_problem(MailProblemCode.permissionDenied)),
      );
      expect((await store.loadOutbox()).single.scheduleRevision, 0);
    },
  );

  test(
    'failed submission keeps its schedule history but cannot be rescheduled',
    () async {
      final scheduled = await store.scheduleOutbox(
        await queued(),
        sendNotBefore: now.add(const Duration(minutes: 1)),
      );
      now = scheduled.sendNotBefore!;
      final attempt = await store.beginOutboxAttempt(scheduled);
      final failed = await store.completeOutboxAttempt(
        attempt,
        MailSubmissionResult(
          attemptId: attempt.attemptId!,
          outcome: MailSubmissionOutcome.retryableFailure,
        ),
      );
      expect(failed.scheduleRevision, scheduled.scheduleRevision);
      expect(failed.sendNotBefore, scheduled.sendNotBefore);
      await expectLater(
        store.scheduleOutbox(
          failed,
          sendNotBefore: now.add(const Duration(minutes: 1)),
        ),
        throwsA(_problem(MailProblemCode.conflict)),
      );
      expect((await store.loadOutbox()).single.attemptNumber, 1);
    },
  );

  test(
    'scheduled interrupted submission reopens as uncertain without retransmission',
    () async {
      final scheduled = await store.scheduleOutbox(
        await queued(),
        sendNotBefore: now.add(const Duration(minutes: 1)),
      );
      now = scheduled.sendNotBefore!;
      await store.beginOutboxAttempt(scheduled);
      await store.close();
      await open(createAccount: false);
      final recovered = (await store.loadOutbox()).single;
      expect(recovered.state, MailOutboxState.uncertain);
      expect(recovered.scheduleRevision, scheduled.scheduleRevision);
      expect(recovered.sendNotBefore, scheduled.sendNotBefore);
      await expectLater(
        store.beginOutboxAttempt(recovered),
        throwsA(_problem(MailProblemCode.conflict)),
      );
      await expectLater(
        store.scheduleOutbox(
          recovered,
          sendNotBefore: now.add(const Duration(minutes: 1)),
        ),
        throwsA(_problem(MailProblemCode.conflict)),
      );
    },
  );
}
