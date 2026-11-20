import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:quds_mail_store/src/codec.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:test/test.dart';

final _profile = MailProfileId('outbox-management', hostId: 'office');
final _account = MailAccountId('account', profile: _profile);
final _now = DateTime.utc(2026, 11, 20);
final _later = _now.add(const Duration(minutes: 1));

T _value<T>(MailResult<T> result) {
  expect(result, isA<MailSuccess<T>>());
  return (result as MailSuccess<T>).value;
}

void _problem<T>(MailResult<T> result, MailProblemCode code) {
  expect(result, isA<MailFailure<T>>());
  expect((result as MailFailure<T>).problem.code, code);
}

MailDraft _draft(
  String id, {
  MailAccountId? account,
  int revision = 0,
  bool uncertain = false,
  bool cleared = false,
  bool legacy = false,
}) => MailDraft(
  id: id,
  account: account ?? _account,
  revision: revision,
  envelope: cleared
      ? MailEnvelope()
      : MailEnvelope(
          subject: 'Frozen subject',
          inReplyTo: '<parent@example.test>',
          references: ['<root@example.test>', '<parent@example.test>'],
        ),
  body: cleared ? const MailBody() : const MailBody(plainText: 'Original body'),
  attachments: cleared
      ? const []
      : [
          MailAttachment(
            partPath: 'file',
            mediaType: 'application/octet-stream',
            displayName: 'original.bin',
            content: MailBytes(Uint8List.fromList([0, 1, 127, 255])),
          ),
        ],
  editorState: legacy
      ? null
      : cleared
      ? MailDraftEditorState(isCleared: true)
      : MailDraftEditorState(
          to: 'recipient@example.test',
          cc: 'copy@example.test',
          bcc: 'hidden@example.test',
          submissionUncertain: uncertain,
        ),
);

MailOutboxEntry _queued({
  String id = 'queue',
  bool inherited = false,
  MailBytes? wire,
  List<String>? recipients,
  int revision = 0,
}) => MailOutboxEntry.queued(
  id: id,
  prepared: MailPreparedMessage(
    account: _account,
    draftId: 'original',
    draftRevision: revision,
    wire:
        wire ??
        MailBytes(utf8.encode('From: sender@example.test\r\n\r\nFrozen MIME')),
    envelope: MailTransportEnvelope(
      sender: 'sender@example.test',
      recipients:
          recipients ??
          [
            'recipient@example.test',
            'copy@example.test',
            'hidden@example.test',
          ],
    ),
  ),
  now: _now,
  priorSubmissionUncertain: inherited,
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

Future<void> _register(SqliteMailRepository store) async => _value(
  await store.createAccount(
    MailStoreAccount(
      id: _account,
      provider: MailProviderKind.imap,
      displayName: 'Synthetic account',
    ),
  ),
);

Future<void> _save(
  SqliteMailRepository store,
  MailOutboxEntry entry, [
  MailOutboxEntry? previous,
]) async => _value(
  await store.saveOutbox(
    entry,
    expectedState: previous?.state,
    expectedAttemptId: previous?.attemptId,
  ),
);

MailOutboxEntry _uncertain(MailOutboxEntry queued) => queued
    .beginAttempt(attemptId: 'first', now: _now)
    .recoverInterrupted(now: _now);

void main() {
  late sqlite.Database database;
  late SqliteMailRepository store;
  MailStoreCheckpoint? failAt;

  setUp(() async {
    failAt = null;
    database = sqlite.sqlite3.openInMemory();
    store = await _open(
      database,
      fault: (checkpoint) {
        if (checkpoint == failAt) {
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
    'edit atomically creates independent draft and retires only its queue',
    () async {
      _value(await store.saveDraft(_draft('original'), expectedRevision: null));
      _value(await store.saveDraft(_draft('sibling'), expectedRevision: null));
      final queued = _queued();
      _value(await store.enqueueDraft(queued, expectedDraftRevision: 0));
      final draft = _draft('edited');
      _value(await store.editOutboxAsDraft(queued, draft, now: _later));
      final old = _value(await store.recoverOutbox(_account)).single;
      expect(old.state, MailOutboxState.cancelled);
      expect(old.prepared.wire.bytes, queued.prepared.wire.bytes);
      expect(
        old.prepared.envelope.recipients,
        queued.prepared.envelope.recipients,
      );
      expect(old.attemptNumber, 0);
      final edited = _value(await store.loadDraft(_account, 'edited'))!;
      expect(edited.revision, 0);
      expect(edited.editorState!.bcc, 'hidden@example.test');
      expect(edited.editorState!.submissionUncertain, isFalse);
      expect(edited.envelope.references, draft.envelope.references);
      expect(edited.attachments.single.content.bytes, [0, 1, 127, 255]);
      final original = _value(await store.loadDraft(_account, 'original'))!;
      expect(original.revision, 1);
      expect(original.editorState!.isCleared, isTrue);
      expect(_value(await store.loadDraft(_account, 'sibling'))!.revision, 0);
      expect(
        _value(
          await store.listDrafts(_account),
        ).drafts.map((entry) => entry.id),
        ['edited', 'sibling'],
      );
      _problem(
        await store.editOutboxAsDraft(queued, _draft('duplicate'), now: _later),
        MailProblemCode.conflict,
      );
      expect(_value(await store.loadDraft(_account, 'duplicate')), isNull);
      _value(
        await store.removeOutbox(
          _account,
          old.id,
          expectedState: old.state,
          expectedAttemptId: old.attemptId,
        ),
      );
      expect(
        _value(
          await store.loadDraft(_account, 'edited'),
        )!.attachments.single.content.bytes,
        [0, 1, 127, 255],
      );
      expect(
        database.select('SELECT hash FROM blobs').single['hash'],
        draft.attachments.single.content.sha256,
      );
    },
  );

  test(
    'editing a definite retryable failure retains the completed attempt',
    () async {
      final queued = _queued();
      await _save(store, queued);
      final pending = queued.beginAttempt(attemptId: 'first', now: _now);
      await _save(store, pending, queued);
      final failed = pending.complete(
        MailSubmissionResult(
          attemptId: 'first',
          outcome: MailSubmissionOutcome.retryableFailure,
        ),
        now: _now,
      );
      await _save(store, failed, pending);
      _value(
        await store.editOutboxAsDraft(failed, _draft('edited'), now: _later),
      );
      final retired = _value(await store.recoverOutbox(_account)).single;
      expect(retired.state, MailOutboxState.cancelled);
      expect(retired.attemptNumber, 1);
      expect(retired.attemptId, 'first');
      expect(retired.result!.outcome, MailSubmissionOutcome.retryableFailure);
      expect(database.select('SELECT * FROM outbox_attempts'), hasLength(1));
    },
  );

  for (final checkpoint in [
    MailStoreCheckpoint.afterOutboxWrite,
    MailStoreCheckpoint.afterDraftBlobs,
    MailStoreCheckpoint.beforeCommit,
  ]) {
    test(
      'edit rollback at ${checkpoint.name} retains original queue and ownership',
      () async {
        final queued = _queued();
        await _save(store, queued);
        failAt = checkpoint;
        _problem(
          await store.editOutboxAsDraft(queued, _draft('edited'), now: _later),
          MailProblemCode.storageFailure,
        );
        failAt = null;
        expect(_value(await store.loadDraft(_account, 'edited')), isNull);
        final retained = _value(await store.recoverOutbox(_account)).single;
        expect(retained.state, MailOutboxState.queued);
        expect(retained.canBeginAttempt, isTrue);
        expect(retained.prepared.wireHash, queued.prepared.wireHash);
        expect(
          database.select('SELECT hash FROM blobs').single['hash'],
          queued.prepared.wireHash,
        );
        expect(
          database
              .select('SELECT owner_kind FROM blob_refs')
              .single['owner_kind'],
          'outbox',
        );
        _value(
          await store.editOutboxAsDraft(
            retained,
            _draft('edited'),
            now: _later,
          ),
        );
      },
    );
  }

  test(
    'full draft catalog rejects edit without cancelling the queue',
    () async {
      final queued = _queued();
      await _save(store, queued);
      _value(await store.saveDraft(_draft('occupied'), expectedRevision: null));
      _problem(
        await store.editOutboxAsDraft(
          queued,
          _draft('edited'),
          now: _later,
          maxActiveDrafts: 1,
        ),
        MailProblemCode.quotaExceeded,
      );
      expect(_value(await store.loadDraft(_account, 'edited')), isNull);
      expect(
        _value(await store.recoverOutbox(_account)).single.state,
        MailOutboxState.queued,
      );
      _value(
        await store.saveDraft(
          _draft('occupied', revision: 1, cleared: true),
          expectedRevision: 0,
        ),
      );
      _value(
        await store.editOutboxAsDraft(
          queued,
          _draft('edited'),
          now: _later,
          maxActiveDrafts: 1,
        ),
      );
      expect(
        _value(await store.listDrafts(_account)).drafts.single.id,
        'edited',
      );
    },
  );

  test(
    'post-write account quota failure rolls back cancellation and new bytes',
    () async {
      final queued = _queued();
      await _save(store, queued);
      await store.close();
      store = await _open(
        database,
        limits: MailStoreLimits(maxAccountBytes: queued.prepared.wire.length),
      );
      _problem(
        await store.editOutboxAsDraft(queued, _draft('edited'), now: _later),
        MailProblemCode.quotaExceeded,
      );
      expect(_value(await store.loadDraft(_account, 'edited')), isNull);
      expect(
        _value(await store.recoverOutbox(_account)).single.state,
        MailOutboxState.queued,
      );
      expect(
        database.select('SELECT hash FROM blobs').single['hash'],
        queued.prepared.wireHash,
      );
    },
  );

  test(
    'edit requires fresh local draft identity and clean initial editor state',
    () async {
      final queued = _queued();
      await _save(store, queued);
      for (final invalid in [
        _draft('wrong-revision', revision: 1),
        _draft('uncertain', uncertain: true),
        _draft('cleared', cleared: true),
        _draft('legacy', legacy: true),
      ]) {
        _problem(
          await store.editOutboxAsDraft(queued, invalid, now: _later),
          MailProblemCode.invalidInput,
        );
      }
      for (final limit in [0, 1001]) {
        _problem(
          await store.editOutboxAsDraft(
            queued,
            _draft('edited'),
            now: _later,
            maxActiveDrafts: limit,
          ),
          MailProblemCode.invalidInput,
        );
      }
      _problem(
        await store.editOutboxAsDraft(queued, _draft('original'), now: _later),
        MailProblemCode.conflict,
      );
      for (final cleared in [false, true]) {
        final id = cleared ? 'tombstone' : 'occupied';
        _value(
          await store.saveDraft(
            _draft(id, cleared: cleared),
            expectedRevision: null,
          ),
        );
        _problem(
          await store.editOutboxAsDraft(queued, _draft(id), now: _later),
          MailProblemCode.conflict,
        );
      }
      for (final account in [
        MailAccountId('other', profile: _profile),
        MailAccountId(
          'account',
          profile: MailProfileId('other', hostId: 'office'),
        ),
      ]) {
        _problem(
          await store.editOutboxAsDraft(
            queued,
            _draft('edited', account: account),
            now: _later,
          ),
          MailProblemCode.permissionDenied,
        );
      }
      expect(
        _value(await store.recoverOutbox(_account)).single.state,
        MailOutboxState.queued,
      );
    },
  );

  test(
    'edit rejects stale snapshots and fabricated failure before completion',
    () async {
      final queued = _queued();
      await _save(store, queued);
      for (final altered in [
        _queued(wire: MailBytes(utf8.encode('different frozen bytes'))),
        _queued(revision: 1),
        _queued(recipients: ['different@example.test']),
      ]) {
        _problem(
          await store.editOutboxAsDraft(altered, _draft('edited'), now: _later),
          MailProblemCode.conflict,
        );
      }
      _problem(
        await store.editOutboxAsDraft(
          queued,
          _draft('edited'),
          now: _now.subtract(const Duration(seconds: 1)),
        ),
        MailProblemCode.conflict,
      );
      final pending = queued.beginAttempt(attemptId: 'first', now: _now);
      await _save(store, pending, queued);
      _problem(
        await store.editOutboxAsDraft(queued, _draft('edited'), now: _later),
        MailProblemCode.conflict,
      );
      final invented = pending.complete(
        MailSubmissionResult(
          attemptId: 'first',
          outcome: MailSubmissionOutcome.retryableFailure,
        ),
        now: _now,
      );
      _problem(
        await store.editOutboxAsDraft(invented, _draft('edited'), now: _later),
        MailProblemCode.conflict,
      );
      expect(
        _value(await store.recoverOutbox(_account)).single.state,
        MailOutboxState.submitting,
      );
      expect(_value(await store.listDrafts(_account)).drafts, isEmpty);
    },
  );

  test('concurrent edits admit only one independent draft', () async {
    final queued = _queued();
    await _save(store, queued);
    final results = await Future.wait([
      store.editOutboxAsDraft(queued, _draft('first-copy'), now: _later),
      store.editOutboxAsDraft(queued, _draft('second-copy'), now: _later),
    ]);
    expect(results.whereType<MailSuccess<MailUnit>>(), hasLength(1));
    expect(
      results.whereType<MailFailure<MailUnit>>().single.problem.code,
      MailProblemCode.conflict,
    );
    expect(_value(await store.listDrafts(_account)).drafts, hasLength(1));
    expect(
      _value(await store.recoverOutbox(_account)).single.state,
      MailOutboxState.cancelled,
    );
  });

  test('racing provider admission and edit cannot both succeed', () async {
    final queued = _queued();
    await _save(store, queued);
    final pending = queued.beginAttempt(attemptId: 'race', now: _later);
    final results = await Future.wait([
      store.saveOutbox(
        pending,
        expectedState: queued.state,
        expectedAttemptId: null,
      ),
      store.editOutboxAsDraft(queued, _draft('edited'), now: _later),
    ]);
    expect(results.whereType<MailSuccess<MailUnit>>(), hasLength(1));
    expect(
      results.whereType<MailFailure<MailUnit>>().single.problem.code,
      MailProblemCode.conflict,
    );
    final finalEntry = _value(await store.recoverOutbox(_account)).single;
    final drafts = _value(await store.listDrafts(_account)).drafts;
    expect(
      finalEntry.state,
      anyOf(MailOutboxState.submitting, MailOutboxState.cancelled),
    );
    expect(
      drafts.length,
      finalEntry.state == MailOutboxState.cancelled ? 1 : 0,
    );
  });

  test(
    'uncertain, inherited, accepted and terminal entries cannot edit',
    () async {
      final queued = _queued();
      final pending = queued.beginAttempt(attemptId: 'first', now: _now);
      final uncertain = pending.recoverInterrupted(now: _now);
      final inherited = _queued(inherited: true);
      for (final original in [
        pending,
        uncertain,
        uncertain.closeUncertain(now: _later),
        queued.cancel(now: _now),
        inherited,
        for (final outcome in [
          MailSubmissionOutcome.accepted,
          MailSubmissionOutcome.rejected,
        ])
          pending.complete(
            MailSubmissionResult(attemptId: 'first', outcome: outcome),
            now: _now,
          ),
        inherited
            .beginAcknowledgedAttempt(attemptId: 'retry', now: _now)
            .complete(
              MailSubmissionResult(
                attemptId: 'retry',
                outcome: MailSubmissionOutcome.retryableFailure,
              ),
              now: _now,
            ),
      ]) {
        _problem(
          await store.editOutboxAsDraft(
            original,
            _draft('edited'),
            now: _later,
          ),
          MailProblemCode.conflict,
        );
      }
      expect(_value(await store.listDrafts(_account)).drafts, isEmpty);
    },
  );

  for (final inherited in [false, true]) {
    test(
      'closing uncertainty $inherited persists genuine outcome and disables every retry',
      () async {
        final queued = _queued(inherited: inherited);
        await _save(store, queued);
        final MailOutboxEntry open;
        if (inherited) {
          open = queued;
        } else {
          final pending = queued.beginAttempt(attemptId: 'first', now: _now);
          await _save(store, pending, queued);
          open = pending.recoverInterrupted(now: _now);
          await _save(store, open, pending);
        }
        final closed = open.closeUncertain(now: _later);
        await _save(store, closed, open);
        await store.close();
        store = await _open(database);
        final restored = _value(await store.recoverOutbox(_account)).single;
        expect(restored.state, MailOutboxState.closedUncertain);
        expect(restored.prepared.wireHash, queued.prepared.wireHash);
        expect(
          restored.result?.outcome,
          inherited ? null : MailSubmissionOutcome.uncertain,
        );
        expect(restored.priorSubmissionUncertain, inherited);
        expect(restored.canBeginAttempt, isFalse);
        expect(restored.canBeginAcknowledgedAttempt, isFalse);
        final forgedRetry = open.beginAcknowledgedAttempt(
          attemptId: 'late',
          now: _later,
        );
        _problem(
          await store.saveOutbox(
            forgedRetry,
            expectedState: restored.state,
            expectedAttemptId: restored.attemptId,
          ),
          MailProblemCode.conflict,
        );
        _problem(
          await store.removeOutbox(
            _account,
            restored.id,
            expectedState: open.state,
            expectedAttemptId: open.attemptId,
          ),
          MailProblemCode.conflict,
        );
        _value(
          await store.removeOutbox(
            _account,
            restored.id,
            expectedState: restored.state,
            expectedAttemptId: restored.attemptId,
          ),
        );
        expect(_value(await store.recoverOutbox(_account)), isEmpty);
        expect(database.select('SELECT * FROM blobs'), isEmpty);
        expect(database.select('SELECT * FROM outbox_attempts'), isEmpty);
      },
    );
  }

  for (final checkpoint in [
    MailStoreCheckpoint.afterOutboxWrite,
    MailStoreCheckpoint.beforeCommit,
  ]) {
    test(
      'closing rollback at ${checkpoint.name} retains unresolved history',
      () async {
        final queued = _queued(inherited: true);
        await _save(store, queued);
        final closed = queued.closeUncertain(now: _later);
        failAt = checkpoint;
        _problem(
          await store.saveOutbox(
            closed,
            expectedState: queued.state,
            expectedAttemptId: queued.attemptId,
          ),
          MailProblemCode.storageFailure,
        );
        failAt = null;
        final retained = _value(await store.recoverOutbox(_account)).single;
        expect(retained.state, MailOutboxState.queued);
        expect(retained.priorSubmissionUncertain, isTrue);
        expect(retained.canBeginAttempt, isFalse);
        expect(retained.prepared.wireHash, queued.prepared.wireHash);
        _problem(
          await store.removeOutbox(
            _account,
            retained.id,
            expectedState: retained.state,
            expectedAttemptId: retained.attemptId,
          ),
          MailProblemCode.conflict,
        );
        await _save(store, closed, retained);
      },
    );
  }

  for (final outcome in [
    MailSubmissionOutcome.rejected,
    MailSubmissionOutcome.retryableFailure,
  ]) {
    test(
      'closing later ${outcome.name} keeps earlier uncertainty after reopen',
      () async {
        final queued = _queued(inherited: true);
        await _save(store, queued);
        final pending = queued.beginAcknowledgedAttempt(
          attemptId: 'retry',
          now: _now,
        );
        await _save(store, pending, queued);
        final failed = pending.complete(
          MailSubmissionResult(
            attemptId: 'retry',
            outcome: outcome,
            recipients: const [
              MailRecipientResponse(
                recipient: 'recipient@example.test',
                acceptance: MailRecipientAcceptance.rejected,
                responseCode: 550,
              ),
            ],
          ),
          now: _now,
        );
        await _save(store, failed, pending);
        await _save(store, failed.closeUncertain(now: _later), failed);
        await store.close();
        store = await _open(database);
        final closed = _value(await store.recoverOutbox(_account)).single;
        expect(closed.state, MailOutboxState.closedUncertain);
        expect(closed.priorSubmissionUncertain, isTrue);
        expect(closed.attemptId, 'retry');
        expect(closed.attemptNumber, 1);
        expect(closed.result!.outcome, outcome);
        expect(closed.result!.recipients.single.responseCode, 550);
        expect(closed.canBeginAttempt, isFalse);
        expect(closed.canBeginAcknowledgedAttempt, isFalse);
        expect(closed.canRemove, isTrue);
      },
    );
  }

  test(
    'codec rejects fabricated closure or changed history without losing old encoding',
    () {
      final queued = _queued();
      final uncertain = _uncertain(queued);
      final closed = uncertain.closeUncertain(now: _later);
      expect(MailStoreCodec.validOutboxTransition(uncertain, closed), isTrue);
      expect(MailStoreCodec.validOutboxTransition(queued, closed), isFalse);
      expect(MailStoreCodec.validOutboxTransition(closed, uncertain), isFalse);
      final payload = MailStoreCodec.encodeOutbox(closed);
      final decoded = MailStoreCodec.decodeOutbox(
        payload.data,
        account: _account,
        id: closed.id,
        blobs: payload.blobs,
      );
      expect(MailStoreCodec.encodeOutbox(decoded).data, payload.data);
      final changed = MailOutboxEntry.restore(
        id: closed.id,
        prepared: closed.prepared,
        state: closed.state,
        createdAt: closed.createdAt,
        updatedAt: closed.updatedAt,
        attemptNumber: closed.attemptNumber,
        attemptId: closed.attemptId,
        result: MailSubmissionResult(
          attemptId: closed.attemptId!,
          outcome: MailSubmissionOutcome.uncertain,
          problem: const MailProblem(MailProblemCode.unavailable),
        ),
      );
      expect(MailStoreCodec.validOutboxTransition(uncertain, changed), isFalse);
      for (final source in [_queued(), _queued(inherited: true)]) {
        final original = MailStoreCodec.encodeOutbox(source);
        final restored = MailStoreCodec.decodeOutbox(
          original.data,
          account: _account,
          id: source.id,
          blobs: original.blobs,
        );
        expect(MailStoreCodec.encodeOutbox(restored).data, original.data);
      }
      final corrupt = jsonDecode(payload.data) as Map<String, dynamic>;
      (corrupt['result'] as Map<String, dynamic>)['outcome'] = 'accepted';
      expect(
        () => MailStoreCodec.decodeOutbox(
          jsonEncode(corrupt),
          account: _account,
          id: closed.id,
          blobs: payload.blobs,
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'file-backed reopen keeps closed record and editable draft independent',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'outbox-management-',
      );
      final path = '${directory.path}/mail.sqlite';
      sqlite.Database? disk;
      SqliteMailRepository? durable;
      try {
        disk = sqlite.sqlite3.open(path);
        durable = await _open(disk);
        await _register(durable);
        final queued = _queued();
        final inherited = _queued(id: 'uncertain', inherited: true);
        await _save(durable, queued);
        await _save(durable, inherited);
        _value(
          await durable.editOutboxAsDraft(
            queued,
            _draft('edited'),
            now: _later,
          ),
        );
        await _save(durable, inherited.closeUncertain(now: _later), inherited);
        await durable.close();
        disk.close();
        disk = sqlite.sqlite3.open(path);
        durable = await _open(disk);
        final reopened = _value(await durable.recoverOutbox(_account));
        expect(reopened.map((entry) => entry.state), [
          MailOutboxState.cancelled,
          MailOutboxState.closedUncertain,
        ]);
        expect(
          reopened.every(
            (entry) =>
                !entry.canBeginAttempt && !entry.canBeginAcknowledgedAttempt,
          ),
          isTrue,
        );
        final edited = _value(await durable.loadDraft(_account, 'edited'))!;
        expect(edited.editorState!.bcc, 'hidden@example.test');
        expect(edited.attachments.single.content.bytes, [0, 1, 127, 255]);
      } finally {
        await durable?.close();
        disk?.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
