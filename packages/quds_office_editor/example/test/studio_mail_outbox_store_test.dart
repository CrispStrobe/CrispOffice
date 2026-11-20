import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_mime/quds_mail_mime.dart';
import 'package:quds_mail_store/quds_mail_store_native.dart';
import 'package:quds_office_studio/studio_mail_draft.dart';
import 'package:quds_office_studio/studio_mail_draft_store.dart';
import 'package:quds_office_studio/studio_mail_draft_store_native.dart';
import 'package:quds_office_studio/studio_mail_outbox.dart';
import 'package:quds_office_studio/studio_mail_threading.dart';

const _sender = 'writer@example.test';

StudioMailDraftAccount _identity([String sender = _sender]) =>
    StudioMailDraftAccount(
      provider: 'imap',
      endpoint: 'imaps://imap.example.test:993',
      login: sender,
      sender: sender,
    );

StudioMailDraft _draft(String subject) => StudioMailDraft(
  to: 'reader@example.test',
  subject: subject,
  body: 'A frozen body: $subject.',
);

Matcher _problem(MailProblemCode code) => isA<StudioMailDraftStoreException>()
    .having((error) => error.code, 'code', code);

T _value<T>(MailResult<T> result) {
  expect(result, isA<MailSuccess<T>>());
  return (result as MailSuccess<T>).value;
}

MailSubmissionResult _result(
  MailOutboxEntry entry,
  MailSubmissionOutcome outcome,
) => MailSubmissionResult(attemptId: entry.attemptId!, outcome: outcome);

void main() {
  late Directory directory;
  final opened = <StudioMailDraftStore>[];

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('studio-mail-outbox-');
  });

  tearDown(() async {
    for (final store in opened.reversed) {
      await store.close();
    }
    opened.clear();
    await directory.delete(recursive: true);
  });

  Future<SqliteStudioMailDraftStore> openNative({
    StudioMailDraftAccount? identity,
    MailStoreFaultInjector? fault,
  }) async {
    final store = await openStudioMailDraftStore(
      identity ?? _identity(),
      appDirectory: directory,
      faultInjector: fault,
    );
    opened.add(store);
    await store.load();
    expect(store, isA<StudioMailOutboxStore>());
    return store as SqliteStudioMailDraftStore;
  }

  Future<({SqliteStudioMailDraftStore store, SqliteMailRepository repository})>
  openRepository({
    MailStoreFaultInjector? fault,
    DateTime Function()? clock,
  }) async {
    final identity = _identity();
    final repository = _value(
      await openNativeMailStore(
        appDirectory: directory,
        profile: identity.profile,
        faultInjector: fault,
      ),
    );
    _value(
      await repository.createAccount(
        MailStoreAccount(
          id: identity.account,
          provider: identity.provider,
          displayName: 'Outbox fixture',
        ),
      ),
    );
    final store = SqliteStudioMailDraftStore(
      repository: repository,
      account: identity.account,
      ownsRepository: true,
      clock: clock,
    );
    opened.add(store);
    await store.load();
    return (store: store, repository: repository);
  }

  test(
    'queue freezes MIME and private envelope with a cleared draft revision',
    () async {
      final fixture = await openRepository();
      final store = fixture.store;
      final bytes = Uint8List.fromList([0, 13, 10, 128, 255]);
      final draft = StudioMailDraft(
        to: 'reader@Example.test',
        cc: 'reader@example.test; copy@example.test',
        bcc: 'copy@example.test, hidden@example.test',
        subject: 'Frozen مرحبا',
        body: 'A <safe> body with an attachment.',
        thread: StudioMailThread.replyTo(
          MailEnvelope(
            messageId: '<parent@example.test>',
            references: ['<root@example.test>'],
          ),
        ),
        attachments: StudioMailAttachments.from([
          StudioMailAttachment(name: 'original.bin', bytes: bytes),
        ]),
      );
      bytes.fillRange(0, bytes.length, 42);
      final queued = await store.enqueueOutbox(draft, _sender);
      expect(queued.state, MailOutboxState.queued);
      expect(queued.id, matches(RegExp(r'^outbox-[a-f0-9]{48}$')));
      expect(queued.prepared.envelope.sender, _sender);
      expect(queued.prepared.envelope.recipients, [
        'reader@Example.test',
        'copy@example.test',
        'hidden@example.test',
      ]);
      final wire = queued.prepared.wire.copyBytes();
      final parsed = const QudsMimeCodec().parse(wire);
      expect(parsed.status, MailParseStatus.complete);
      final message = parsed.message!;
      expect(message.envelope.subject, draft.subject);
      expect(message.envelope.messageId, isNotNull);
      expect(message.envelope.inReplyTo, '<parent@example.test>');
      expect(message.envelope.bcc, isEmpty);
      expect(utf8.decode(wire), isNot(contains('hidden@example.test')));
      expect(message.attachments.single.content.bytes, [0, 13, 10, 128, 255]);
      expect(message.attachments.single.displayName, 'original.bin');
      expect(await store.load(), isNull);
      final cleared = _value(
        await fixture.repository.loadDraft(
          store.account,
          SqliteStudioMailDraftStore.draftId,
        ),
      )!;
      expect(cleared.revision, queued.prepared.draftRevision + 1);
      expect(cleared.editorState!.isCleared, isTrue);
      expect(cleared.attachments, isEmpty);

      await store.save(_draft('Later editing'), submissionUncertain: false);
      wire.fillRange(0, wire.length, 0);
      final restored = (await store.loadOutbox()).single;
      expect(restored.prepared.wireHash, queued.prepared.wireHash);
      expect(restored.prepared.wire.bytes, queued.prepared.wire.bytes);
      expect((await store.load())!.draft.subject, 'Later editing');
    },
  );

  test(
    'native reopen retains queued bytes and recovers interrupted attempts',
    () async {
      final first = await openNative();
      final queued = await first.enqueueOutbox(_draft('Waiting'), _sender);
      final toSend = await first.enqueueOutbox(_draft('Interrupted'), _sender);
      final attempt = await first.beginOutboxAttempt(toSend);
      expect(attempt.attemptId, matches(RegExp(r'^attempt-[a-f0-9]{48}$')));
      final live = await first.loadOutbox();
      expect(
        live.singleWhere((entry) => entry.id == attempt.id).state,
        MailOutboxState.submitting,
      );
      await first.close();

      final reopened = await openNative();
      final entries = await reopened.loadOutbox();
      expect(entries, hasLength(2));
      final waiting = entries.singleWhere((entry) => entry.id == queued.id);
      final interrupted = entries.singleWhere(
        (entry) => entry.id == attempt.id,
      );
      expect(waiting.state, MailOutboxState.queued);
      expect(waiting.prepared.wire.bytes, queued.prepared.wire.bytes);
      expect(interrupted.state, MailOutboxState.uncertain);
      expect(interrupted.attemptId, attempt.attemptId);
      expect(interrupted.prepared.wire.bytes, attempt.prepared.wire.bytes);
      await expectLater(
        reopened.beginOutboxAttempt(interrupted),
        throwsA(_problem(MailProblemCode.conflict)),
      );
      await expectLater(
        reopened.cancelOutbox(interrupted),
        throwsA(_problem(MailProblemCode.conflict)),
      );
      expect(await reopened.load(), isNull);
    },
  );

  for (final checkpoint in [
    MailStoreCheckpoint.afterOutboxWrite,
    MailStoreCheckpoint.afterDraftBlobs,
    MailStoreCheckpoint.beforeCommit,
  ]) {
    test(
      'transfer failure at ${checkpoint.name} retains the complete draft',
      () async {
        var armed = false;
        var transferStarted = false;
        final store = await openNative(
          fault: (point) {
            if (point == MailStoreCheckpoint.afterOutboxWrite) {
              transferStarted = true;
            }
            if (armed && transferStarted && point == checkpoint) {
              throw StateError('private-storage-error');
            }
          },
        );
        final draft = StudioMailDraft(
          to: 'reader@example.test',
          bcc: 'hidden@example.test',
          subject: 'Keep latest snapshot',
          body: 'Exact content before transfer',
          attachments: StudioMailAttachments.from([
            StudioMailAttachment(
              name: 'keep.bin',
              bytes: Uint8List.fromList([1, 0, 255]),
            ),
          ]),
        );
        armed = true;
        await expectLater(
          store.enqueueOutbox(draft, _sender),
          throwsA(_problem(MailProblemCode.storageFailure)),
        );
        armed = false;
        expect(await store.loadOutbox(), isEmpty);
        await store.close();
        final reopened = await openNative();
        expect(await reopened.loadOutbox(), isEmpty);
        final retained = (await reopened.load())!;
        expect(retained.draft.subject, draft.subject);
        expect(retained.draft.bcc, draft.bcc);
        expect(retained.draft.attachments.items.single.content.bytes, [
          1,
          0,
          255,
        ]);
      },
    );
  }

  test(
    'invalid recipients are saved without becoming a queued message',
    () async {
      final store = (await openRepository()).store;
      const draft = StudioMailDraft(
        to: 'reader@',
        subject: 'Unfinished',
        body: 'Preserve this input',
      );
      await expectLater(
        store.enqueueOutbox(draft, _sender),
        throwsA(_problem(MailProblemCode.invalidInput)),
      );
      expect((await store.load())!.draft.to, 'reader@');
      expect(await store.loadOutbox(), isEmpty);
    },
  );

  test(
    'full queue rejects admission while preserving the latest draft',
    () async {
      final fixture = await openRepository();
      final store = fixture.store;
      for (
        var index = 0;
        index < SqliteStudioMailDraftStore.maxOutboxEntries;
        index++
      ) {
        _value(
          await fixture.repository.saveOutbox(
            MailOutboxEntry.queued(
              id: 'seed-$index',
              prepared: MailPreparedMessage(
                account: store.account,
                draftId: 'seed-draft-$index',
                draftRevision: 0,
                wire: MailBytes(utf8.encode('Subject: seed\r\n\r\n$index')),
                envelope: MailTransportEnvelope(
                  sender: _sender,
                  recipients: ['reader@example.test'],
                ),
              ),
              now: DateTime.utc(2026, 11, 20),
            ),
            expectedState: null,
            expectedAttemptId: null,
          ),
        );
      }
      await expectLater(
        store.enqueueOutbox(_draft('Queue is full'), _sender),
        throwsA(_problem(MailProblemCode.quotaExceeded)),
      );
      expect((await store.load())!.draft.subject, 'Queue is full');
      expect(await store.loadOutbox(), hasLength(100));
    },
  );

  test('stale draft owner cannot queue over a newer saved revision', () async {
    final fixture = await openRepository();
    final stale = SqliteStudioMailDraftStore(
      repository: fixture.repository,
      account: fixture.store.account,
    );
    opened.add(stale);
    await stale.load();
    await fixture.store.save(_draft('Newer'), submissionUncertain: false);
    await expectLater(
      stale.enqueueOutbox(_draft('Stale'), _sender),
      throwsA(_problem(MailProblemCode.conflict)),
    );
    expect(await fixture.store.loadOutbox(), isEmpty);
    expect((await fixture.store.load())!.draft.subject, 'Newer');
  });

  test(
    'duplicate begin and stale completion cannot acquire another attempt',
    () async {
      final store = (await openRepository()).store;
      final queued = await store.enqueueOutbox(_draft('Once'), _sender);
      final beginning = store.beginOutboxAttempt(queued);
      final duplicate = expectLater(
        store.beginOutboxAttempt(queued),
        throwsA(_problem(MailProblemCode.conflict)),
      );
      final attempt = await beginning;
      await duplicate;
      expect(
        (await store.loadOutbox()).single.state,
        MailOutboxState.submitting,
      );
      final accepted = await store.completeOutboxAttempt(
        attempt,
        _result(attempt, MailSubmissionOutcome.accepted),
      );
      expect(accepted.state, MailOutboxState.submitted);
      await expectLater(
        store.completeOutboxAttempt(
          attempt,
          _result(attempt, MailSubmissionOutcome.retryableFailure),
        ),
        throwsA(_problem(MailProblemCode.conflict)),
      );
      expect(
        (await store.loadOutbox()).single.state,
        MailOutboxState.submitted,
      );
      await store.removeOutbox(accepted);
      expect(await store.loadOutbox(), isEmpty);
    },
  );

  test('failed attempt persistence leaves the message safely queued', () async {
    var fail = false;
    final store = (await openRepository(
      fault: (point) {
        if (fail && point == MailStoreCheckpoint.afterOutboxWrite) {
          throw StateError('private-marker-failure');
        }
      },
    )).store;
    final queued = await store.enqueueOutbox(_draft('No network yet'), _sender);
    fail = true;
    await expectLater(
      store.beginOutboxAttempt(queued),
      throwsA(_problem(MailProblemCode.storageFailure)),
    );
    fail = false;
    final retained = (await store.loadOutbox()).single;
    expect(retained.state, MailOutboxState.queued);
    expect(retained.attemptNumber, 0);
    final attempt = await store.beginOutboxAttempt(retained);
    expect(attempt.attemptNumber, 1);
  });

  test(
    'failed accepted-result commit recovers uncertainty with the same owner',
    () async {
      var fail = false;
      final store = (await openRepository(
        fault: (point) {
          if (fail && point == MailStoreCheckpoint.afterOutboxWrite) {
            throw StateError('private-result-write-failure');
          }
        },
      )).store;
      final queued = await store.enqueueOutbox(_draft('May be sent'), _sender);
      final attempt = await store.beginOutboxAttempt(queued);
      fail = true;
      await expectLater(
        store.completeOutboxAttempt(
          attempt,
          _result(attempt, MailSubmissionOutcome.accepted),
        ),
        throwsA(_problem(MailProblemCode.storageFailure)),
      );
      fail = false;
      final recovered = (await store.loadOutbox()).single;
      expect(recovered.state, MailOutboxState.uncertain);
      expect(recovered.attemptId, attempt.attemptId);
      expect(recovered.prepared.wire.bytes, queued.prepared.wire.bytes);
      await expectLater(
        store.beginOutboxAttempt(recovered),
        throwsA(_problem(MailProblemCode.conflict)),
      );
    },
  );

  test(
    'each uncertain retry requires acknowledgement and freezes every byte',
    () async {
      final store = await openNative();
      final queued = await store.enqueueOutbox(_draft('Exact retry'), _sender);
      final first = await store.beginOutboxAttempt(queued);
      final uncertain = await store.completeOutboxAttempt(
        first,
        _result(first, MailSubmissionOutcome.uncertain),
      );
      final retry = await store.beginOutboxAttempt(
        uncertain,
        acknowledgeUncertain: true,
      );
      expect(retry.attemptId, isNot(first.attemptId));
      expect(retry.prepared.wire.bytes, first.prepared.wire.bytes);
      expect(
        retry.prepared.envelope.recipients,
        first.prepared.envelope.recipients,
      );
      final rejected = await store.completeOutboxAttempt(
        retry,
        _result(retry, MailSubmissionOutcome.rejected),
      );
      expect(rejected.priorSubmissionUncertain, isTrue);
      await store.close();
      final reopened = await openNative();
      final retained = (await reopened.loadOutbox()).single;
      expect(retained.priorSubmissionUncertain, isTrue);
      await expectLater(
        reopened.beginOutboxAttempt(retained),
        throwsA(_problem(MailProblemCode.conflict)),
      );
      await expectLater(
        reopened.cancelOutbox(retained),
        throwsA(_problem(MailProblemCode.conflict)),
      );
      await expectLater(
        reopened.removeOutbox(retained),
        throwsA(_problem(MailProblemCode.conflict)),
      );
      final acknowledged = await reopened.beginOutboxAttempt(
        retained,
        acknowledgeUncertain: true,
      );
      expect(acknowledged.attemptNumber, 3);
      expect(acknowledged.prepared.wire.bytes, queued.prepared.wire.bytes);
    },
  );

  test(
    'legacy uncertain draft moves into a guarded queue without clearing risk',
    () async {
      final store = (await openRepository()).store;
      final draft = _draft('Older interrupted send');
      await store.save(draft, submissionUncertain: true);
      final queued = await store.enqueueOutbox(draft, _sender);
      expect(queued.priorSubmissionUncertain, isTrue);
      expect(await store.load(), isNull);
      await expectLater(
        store.beginOutboxAttempt(queued),
        throwsA(_problem(MailProblemCode.conflict)),
      );
      await expectLater(
        store.cancelOutbox(queued),
        throwsA(_problem(MailProblemCode.conflict)),
      );
      final next = await store.enqueueOutbox(
        _draft('Independent new draft'),
        _sender,
      );
      expect(next.priorSubmissionUncertain, isFalse);
      expect(next.id, isNot(queued.id));
    },
  );

  test('cancellation and removal cannot reopen a stale queued item', () async {
    final store = (await openRepository()).store;
    final queued = await store.enqueueOutbox(
      _draft('Cancel explicitly'),
      _sender,
    );
    await expectLater(
      store.removeOutbox(queued),
      throwsA(_problem(MailProblemCode.conflict)),
    );
    final cancelled = await store.cancelOutbox(queued);
    expect(cancelled.state, MailOutboxState.cancelled);
    await expectLater(
      store.beginOutboxAttempt(queued),
      throwsA(_problem(MailProblemCode.conflict)),
    );
    await store.removeOutbox(cancelled);
    expect(await store.loadOutbox(), isEmpty);
    await expectLater(
      store.beginOutboxAttempt(queued),
      throwsA(_problem(MailProblemCode.conflict)),
    );
  });

  test(
    'all entry operations reject a foreign account before changing data',
    () async {
      final store = (await openRepository()).store;
      final queued = await store.enqueueOutbox(_draft('Owned'), _sender);
      final foreign = MailOutboxEntry.queued(
        id: queued.id,
        prepared: MailPreparedMessage(
          account: _identity('other@example.test').account,
          draftId: queued.prepared.draftId,
          draftRevision: queued.prepared.draftRevision,
          wire: queued.prepared.wire,
          envelope: queued.prepared.envelope,
        ),
        now: queued.createdAt,
      );
      final foreignAttempt = foreign.beginAttempt(
        attemptId: 'foreign-attempt',
        now: foreign.createdAt,
      );
      for (final operation in <Future<Object?> Function()>[
        () => store.beginOutboxAttempt(foreign),
        () => store.cancelOutbox(foreign),
        () => store.removeOutbox(foreign),
        () => store.completeOutboxAttempt(
          foreignAttempt,
          _result(foreignAttempt, MailSubmissionOutcome.accepted),
        ),
      ]) {
        await expectLater(
          operation(),
          throwsA(_problem(MailProblemCode.permissionDenied)),
        );
      }
      expect((await store.loadOutbox()).single.state, MailOutboxState.queued);
    },
  );

  test(
    'separate native accounts expose only their own queued messages',
    () async {
      final first = await openNative();
      final second = await openNative(
        identity: _identity('other@example.test'),
      );
      final one = await first.enqueueOutbox(_draft('First account'), _sender);
      final two = await second.enqueueOutbox(
        _draft('Second account'),
        'other@example.test',
      );
      expect((await first.loadOutbox()).single.id, one.id);
      expect((await second.loadOutbox()).single.id, two.id);
    },
  );

  test(
    'backward clock changes cannot move an entry timestamp backward',
    () async {
      var now = DateTime.utc(2026, 11, 20, 12);
      final store = (await openRepository(clock: () => now)).store;
      final queued = await store.enqueueOutbox(_draft('Clock'), _sender);
      now = now.subtract(const Duration(days: 1));
      final attempt = await store.beginOutboxAttempt(queued);
      final rejected = await store.completeOutboxAttempt(
        attempt,
        _result(attempt, MailSubmissionOutcome.retryableFailure),
      );
      final cancelled = await store.cancelOutbox(rejected);
      expect(attempt.updatedAt, queued.createdAt);
      expect(rejected.updatedAt, queued.createdAt);
      expect(cancelled.updatedAt, queued.createdAt);
    },
  );

  test(
    'close waits for the durable marker and rejects later operations',
    () async {
      var pause = false;
      final entered = Completer<void>();
      final release = Completer<void>();
      final store = await openNative(
        fault: (point) async {
          if (pause && point == MailStoreCheckpoint.afterOutboxWrite) {
            entered.complete();
            await release.future;
          }
        },
      );
      final queued = await store.enqueueOutbox(
        _draft('Closing owner'),
        _sender,
      );
      pause = true;
      final beginning = store.beginOutboxAttempt(queued);
      await entered.future;
      var closed = false;
      final closing = store.close().then((_) => closed = true);
      await expectLater(
        store.loadOutbox(),
        throwsA(_problem(MailProblemCode.unavailable)),
      );
      expect(closed, isFalse);
      release.complete();
      await beginning;
      await closing;
      expect(closed, isTrue);
      final reopened = await openNative();
      expect(
        (await reopened.loadOutbox()).single.state,
        MailOutboxState.uncertain,
      );
      await expectLater(
        store.enqueueOutbox(_draft('After close'), _sender),
        throwsA(_problem(MailProblemCode.unavailable)),
      );
    },
  );
}
