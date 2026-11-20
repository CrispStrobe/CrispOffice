import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:test/test.dart';

final _profile = MailProfileId('outbox-tests', hostId: 'office');
final _account = MailAccountId('account', profile: _profile);
final _now = DateTime.utc(2026, 11, 20);

T _value<T>(MailResult<T> result) {
  expect(result, isA<MailSuccess<T>>());
  return (result as MailSuccess<T>).value;
}

void _problem<T>(MailResult<T> result, MailProblemCode code) {
  expect(result, isA<MailFailure<T>>());
  expect((result as MailFailure<T>).problem.code, code);
}

MailDraft _draft({int revision = 0, bool uncertain = false}) => MailDraft(
  id: 'draft',
  account: _account,
  revision: revision,
  envelope: MailEnvelope(subject: 'Frozen subject'),
  body: const MailBody(plainText: 'Original body'),
  attachments: [
    MailAttachment(
      partPath: '1',
      mediaType: 'application/octet-stream',
      displayName: 'original.bin',
      content: MailBytes(Uint8List.fromList([0, 1, 127, 255])),
    ),
  ],
  editorState: MailDraftEditorState(
    to: 'recipient@example.test',
    bcc: 'hidden@example.test',
    submissionUncertain: uncertain,
  ),
);

MailOutboxEntry _queued({
  String id = 'queue',
  String draftId = 'draft',
  int revision = 0,
  MailAccountId? account,
  bool uncertain = false,
  MailBytes? wire,
}) => MailOutboxEntry.queued(
  id: id,
  prepared: MailPreparedMessage(
    account: account ?? _account,
    draftId: draftId,
    draftRevision: revision,
    wire:
        wire ??
        MailBytes(utf8.encode('From: sender@example.test\r\n\r\nFrozen MIME')),
    envelope: MailTransportEnvelope(
      sender: 'sender@example.test',
      recipients: ['recipient@example.test', 'hidden@example.test'],
    ),
  ),
  now: _now,
  priorSubmissionUncertain: uncertain,
);

Future<SqliteMailRepository> _open(
  sqlite.Database database, {
  MailStoreFaultInjector? fault,
  MailStoreLimits limits = const MailStoreLimits(),
}) async => _value(
  await SqliteMailRepository.open(
    executor: NativeDatabase.opened(database, closeUnderlyingOnClose: false),
    profile: _profile,
    faultInjector: fault,
    limits: limits,
    clock: () => _now,
  ),
);

Future<void> _register(
  SqliteMailRepository store, [
  MailAccountId? account,
]) async {
  _value(
    await store.createAccount(
      MailStoreAccount(
        id: account ?? _account,
        provider: MailProviderKind.imap,
        displayName: 'Synthetic account',
      ),
    ),
  );
}

Future<void> _save(
  SqliteMailRepository store,
  MailOutboxEntry next, [
  MailOutboxEntry? previous,
]) async {
  _value(
    await store.saveOutbox(
      next,
      expectedState: previous?.state,
      expectedAttemptId: previous?.attemptId,
    ),
  );
}

Future<MailResult<MailUnit>> _remove(
  SqliteMailRepository store,
  MailOutboxEntry entry,
) => store.removeOutbox(
  entry.prepared.account,
  entry.id,
  expectedState: entry.state,
  expectedAttemptId: entry.attemptId,
);

void main() {
  late sqlite.Database database;
  late SqliteMailRepository store;
  MailStoreCheckpoint? failAt;

  setUp(() async {
    failAt = null;
    database = sqlite.sqlite3.openInMemory();
    store = await _open(
      database,
      fault: (point) {
        if (point == failAt) {
          throw const MailStoreStorageException(MailProblemCode.storageFailure);
        }
      },
    );
    await _register(store);
  });

  tearDown(() async {
    await store.close();
    database.close();
  });

  test(
    'enqueue freezes the whole payload and atomically retires the draft revision',
    () async {
      _value(await store.saveDraft(_draft(), expectedRevision: null));
      final queued = _queued();
      _value(await store.enqueueDraft(queued, expectedDraftRevision: 0));
      final restored = _value(await store.recoverOutbox(_account)).single;
      expect(restored.state, MailOutboxState.queued);
      expect(restored.prepared.wire.bytes, queued.prepared.wire.bytes);
      expect(restored.prepared.wireHash, queued.prepared.wireHash);
      expect(restored.prepared.envelope.recipients, [
        'recipient@example.test',
        'hidden@example.test',
      ]);
      final cleared = _value(await store.loadDraft(_account, 'draft'))!;
      expect(cleared.revision, 1);
      expect(cleared.editorState!.isCleared, isTrue);
      expect(cleared.attachments, isEmpty);
      expect(cleared.body.plainText, isNull);
      expect(
        database.select('SELECT hash FROM blobs').single['hash'],
        queued.prepared.wireHash,
      );
      _problem(
        await store.saveDraft(_draft(revision: 1), expectedRevision: 0),
        MailProblemCode.conflict,
      );
      _problem(
        await store.enqueueDraft(
          _queued(id: 'duplicate'),
          expectedDraftRevision: 0,
        ),
        MailProblemCode.conflict,
      );
      _problem(
        await store.enqueueDraft(
          _queued(id: 'cleared', revision: 1),
          expectedDraftRevision: 1,
        ),
        MailProblemCode.conflict,
      );
    },
  );

  for (final checkpoint in [
    MailStoreCheckpoint.afterOutboxWrite,
    MailStoreCheckpoint.afterDraftBlobs,
    MailStoreCheckpoint.beforeCommit,
  ]) {
    test(
      'enqueue rollback at ${checkpoint.name} retains the draft and no queue',
      () async {
        final draft = _draft();
        _value(await store.saveDraft(draft, expectedRevision: null));
        failAt = checkpoint;
        _problem(
          await store.enqueueDraft(_queued(), expectedDraftRevision: 0),
          MailProblemCode.storageFailure,
        );
        failAt = null;
        expect(_value(await store.recoverOutbox(_account)), isEmpty);
        final restored = _value(await store.loadDraft(_account, 'draft'))!;
        expect(restored.revision, 0);
        expect(restored.editorState!.isCleared, isFalse);
        expect(
          restored.attachments.single.content.bytes,
          draft.attachments.single.content.bytes,
        );
        expect(
          database.select('SELECT hash FROM blobs').single['hash'],
          draft.attachments.single.content.sha256,
        );
        _value(await store.enqueueDraft(_queued(), expectedDraftRevision: 0));
        expect(
          _value(await store.recoverOutbox(_account)).single.state,
          MailOutboxState.queued,
        );
      },
    );
  }

  test(
    'enqueue rejects missing, stale, mismatched and already owned identities',
    () async {
      _problem(
        await store.enqueueDraft(_queued(), expectedDraftRevision: 0),
        MailProblemCode.conflict,
      );
      _value(await store.saveDraft(_draft(), expectedRevision: null));
      for (final entry in [_queued(draftId: 'other'), _queued(revision: 1)]) {
        _problem(
          await store.enqueueDraft(entry, expectedDraftRevision: 0),
          MailProblemCode.conflict,
        );
      }
      _problem(
        await store.enqueueDraft(_queued(), expectedDraftRevision: 1),
        MailProblemCode.conflict,
      );
      final other = MailAccountId('other', profile: _profile);
      await _register(store, other);
      _problem(
        await store.enqueueDraft(
          _queued(account: other),
          expectedDraftRevision: 0,
        ),
        MailProblemCode.conflict,
      );
      final foreign = MailAccountId(
        'account',
        profile: MailProfileId('different', hostId: 'office'),
      );
      _problem(
        await store.enqueueDraft(
          _queued(account: foreign),
          expectedDraftRevision: 0,
        ),
        MailProblemCode.permissionDenied,
      );
      final occupied = _queued();
      await _save(store, occupied);
      _problem(
        await store.enqueueDraft(occupied, expectedDraftRevision: 0),
        MailProblemCode.conflict,
      );
      _problem(
        await store.enqueueDraft(
          _queued(id: 'active').beginAttempt(attemptId: 'a', now: _now),
          expectedDraftRevision: 0,
        ),
        MailProblemCode.conflict,
      );
      expect(_value(await store.loadDraft(_account, 'draft'))!.revision, 0);
    },
  );

  for (final uncertain in [false, true]) {
    test('enqueue preserves exact legacy uncertainty $uncertain', () async {
      _value(
        await store.saveDraft(
          _draft(uncertain: uncertain),
          expectedRevision: null,
        ),
      );
      _problem(
        await store.enqueueDraft(
          _queued(uncertain: !uncertain),
          expectedDraftRevision: 0,
        ),
        MailProblemCode.conflict,
      );
      _value(
        await store.enqueueDraft(
          _queued(uncertain: uncertain),
          expectedDraftRevision: 0,
        ),
      );
      final entry = _value(await store.recoverOutbox(_account)).single;
      expect(entry.priorSubmissionUncertain, uncertain);
      expect(entry.canBeginAttempt, !uncertain);
      expect(entry.canBeginAcknowledgedAttempt, uncertain);
    });
  }

  test(
    'enqueue quota failure preserves original attachments and editable draft',
    () async {
      _value(await store.saveDraft(_draft(), expectedRevision: null));
      await store.close();
      store = await _open(
        database,
        limits: const MailStoreLimits(
          maxBlobBytes: 128,
          maxTransactionBlobBytes: 256,
        ),
      );
      final oversized = _queued(wire: MailBytes(Uint8List(129)));
      _problem(
        await store.enqueueDraft(oversized, expectedDraftRevision: 0),
        MailProblemCode.quotaExceeded,
      );
      expect(_value(await store.recoverOutbox(_account)), isEmpty);
      expect(
        _value(
          await store.loadDraft(_account, 'draft'),
        )!.attachments.single.content.bytes,
        [0, 1, 127, 255],
      );
      _value(await store.enqueueDraft(_queued(), expectedDraftRevision: 0));
    },
  );

  for (final outcome in [
    MailSubmissionOutcome.accepted,
    MailSubmissionOutcome.rejected,
  ]) {
    test(
      'remove ${outcome.name} requires matching state and attempt and releases bytes',
      () async {
        final queued = _queued();
        await _save(store, queued);
        final active = queued.beginAttempt(attemptId: 'a', now: _now);
        await _save(store, active, queued);
        final terminal = active.complete(
          MailSubmissionResult(attemptId: 'a', outcome: outcome),
          now: _now,
        );
        await _save(store, terminal, active);
        _problem(
          await store.removeOutbox(
            _account,
            terminal.id,
            expectedState: MailOutboxState.queued,
            expectedAttemptId: 'a',
          ),
          MailProblemCode.conflict,
        );
        _problem(
          await store.removeOutbox(
            _account,
            terminal.id,
            expectedState: terminal.state,
            expectedAttemptId: 'stale',
          ),
          MailProblemCode.conflict,
        );
        _value(await _remove(store, terminal));
        expect(_value(await store.recoverOutbox(_account)), isEmpty);
        expect(database.select('SELECT * FROM blobs'), isEmpty);
        expect(database.select('SELECT * FROM blob_refs'), isEmpty);
        expect(database.select('SELECT * FROM outbox_attempts'), isEmpty);
      },
    );
  }

  test(
    'removing cancelled work retains bytes shared by a second queued item',
    () async {
      final first = _queued(id: 'first');
      final second = _queued(id: 'second');
      await _save(store, first);
      await _save(store, second);
      final cancelled = first.cancel(now: _now);
      await _save(store, cancelled, first);
      _value(await _remove(store, cancelled));
      expect(database.select('SELECT * FROM blobs'), hasLength(1));
      expect(_value(await store.recoverOutbox(_account)).single.id, 'second');
      final secondCancelled = second.cancel(now: _now);
      await _save(store, secondCancelled, second);
      _value(await _remove(store, secondCancelled));
      expect(database.select('SELECT * FROM blobs'), isEmpty);
    },
  );

  test(
    'queued, active, retryable and uncertain entries cannot be removed',
    () async {
      final queued = _queued();
      await _save(store, queued);
      _problem(await _remove(store, queued), MailProblemCode.conflict);
      var active = queued.beginAttempt(attemptId: 'a', now: _now);
      await _save(store, active, queued);
      _problem(await _remove(store, active), MailProblemCode.conflict);
      final failed = active.complete(
        MailSubmissionResult(
          attemptId: 'a',
          outcome: MailSubmissionOutcome.retryableFailure,
        ),
        now: _now,
      );
      await _save(store, failed, active);
      _problem(await _remove(store, failed), MailProblemCode.conflict);
      active = failed.beginAttempt(attemptId: 'b', now: _now);
      await _save(store, active, failed);
      final uncertain = active.recoverInterrupted(now: _now);
      await _save(store, uncertain, active);
      _problem(await _remove(store, uncertain), MailProblemCode.conflict);
    },
  );

  for (final outcome in MailSubmissionOutcome.values) {
    test(
      'earlier uncertainty remains stored and unremovable after ${outcome.name}',
      () async {
        final queued = _queued(uncertain: true);
        await _save(store, queued);
        final active = queued.beginAcknowledgedAttempt(
          attemptId: 'a',
          now: _now,
        );
        await _save(store, active, queued);
        final completed = active.complete(
          MailSubmissionResult(attemptId: 'a', outcome: outcome),
          now: _now,
        );
        await _save(store, completed, active);
        _problem(await _remove(store, completed), MailProblemCode.conflict);
        await store.close();
        store = await _open(database);
        final recovered = _value(await store.recoverOutbox(_account)).single;
        expect(recovered.priorSubmissionUncertain, isTrue);
        expect(recovered.canBeginAttempt, isFalse);
        expect(recovered.canCancel, isFalse);
        expect(recovered.result!.outcome, outcome);
      },
    );
  }

  test(
    'remove failure rolls back record, attempt history and payload ownership',
    () async {
      final queued = _queued();
      await _save(store, queued);
      final active = queued.beginAttempt(attemptId: 'a', now: _now);
      await _save(store, active, queued);
      final accepted = active.complete(
        MailSubmissionResult(
          attemptId: 'a',
          outcome: MailSubmissionOutcome.accepted,
        ),
        now: _now,
      );
      await _save(store, accepted, active);
      failAt = MailStoreCheckpoint.afterOutboxWrite;
      _problem(await _remove(store, accepted), MailProblemCode.storageFailure);
      failAt = null;
      expect(
        _value(await store.recoverOutbox(_account)).single.state,
        MailOutboxState.submitted,
      );
      expect(database.select('SELECT * FROM outbox_attempts'), hasLength(1));
      expect(database.select('SELECT * FROM blobs'), hasLength(1));
      _value(await _remove(store, accepted));
    },
  );

  test(
    'terminal cleanup remains possible under a lowered account quota',
    () async {
      final queued = _queued();
      await _save(store, queued);
      final cancelled = queued.cancel(now: _now);
      await _save(store, cancelled, queued);
      await store.close();
      store = await _open(
        database,
        limits: const MailStoreLimits(maxAccountBytes: 1),
      );
      _value(await _remove(store, cancelled));
      expect(database.select('SELECT * FROM blobs'), isEmpty);
    },
  );

  test(
    'file reopen recovers an interrupted acknowledged send without resurrecting compose',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'mail-outbox-transfer-',
      );
      final file = File('${directory.path}/mail.sqlite');
      sqlite.Database? disk;
      SqliteMailRepository? durable;
      try {
        disk = sqlite.sqlite3.open(file.path);
        durable = await _open(disk);
        await _register(durable);
        _value(
          await durable.saveDraft(
            _draft(uncertain: true),
            expectedRevision: null,
          ),
        );
        final queued = _queued(uncertain: true);
        _value(await durable.enqueueDraft(queued, expectedDraftRevision: 0));
        await durable.close();
        disk.close();
        disk = sqlite.sqlite3.open(file.path);
        durable = await _open(disk);
        final recoveredQueue = _value(
          await durable.recoverOutbox(_account),
        ).single;
        expect(recoveredQueue.state, MailOutboxState.queued);
        expect(recoveredQueue.priorSubmissionUncertain, isTrue);
        final active = recoveredQueue.beginAcknowledgedAttempt(
          attemptId: 'first',
          now: _now,
        );
        await _save(durable, active, recoveredQueue);
        expect(
          _value(await durable.recoverOutbox(_account)).single.state,
          MailOutboxState.submitting,
        );
        await durable.close();
        disk.close();
        disk = sqlite.sqlite3.open(file.path);
        durable = await _open(disk);
        final uncertain = _value(await durable.recoverOutbox(_account)).single;
        expect(uncertain.state, MailOutboxState.uncertain);
        expect(uncertain.priorSubmissionUncertain, isTrue);
        expect(uncertain.prepared.wireHash, queued.prepared.wireHash);
        expect(
          _value(
            await durable.loadDraft(_account, 'draft'),
          )!.editorState!.isCleared,
          isTrue,
        );
        final retry = uncertain.beginAcknowledgedAttempt(
          attemptId: 'second',
          now: _now,
        );
        await _save(durable, retry, uncertain);
        final rejected = retry.complete(
          MailSubmissionResult(
            attemptId: 'second',
            outcome: MailSubmissionOutcome.rejected,
          ),
          now: _now,
        );
        await _save(durable, rejected, retry);
        final reused = rejected.beginAcknowledgedAttempt(
          attemptId: 'first',
          now: _now,
        );
        _problem(
          await durable.saveOutbox(
            reused,
            expectedState: rejected.state,
            expectedAttemptId: rejected.attemptId,
          ),
          MailProblemCode.conflict,
        );
        expect(
          _value(await durable.recoverOutbox(_account)).single.attemptId,
          'second',
        );
      } finally {
        await durable?.close();
        disk?.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
