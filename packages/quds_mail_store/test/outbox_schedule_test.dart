import 'dart:convert';

import 'package:drift/native.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:quds_mail_store/src/codec.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:test/test.dart';

final _profile = MailProfileId('outbox-schedule', hostId: 'office');
final _account = MailAccountId('account', profile: _profile);
final _now = DateTime.utc(2026, 11, 21, 12);
final _deadline = _now.add(const Duration(hours: 2));

T _value<T>(MailResult<T> result) {
  expect(result, isA<MailSuccess<T>>());
  return (result as MailSuccess<T>).value;
}

void _problem<T>(MailResult<T> result, MailProblemCode code) {
  expect(result, isA<MailFailure<T>>());
  expect((result as MailFailure<T>).problem.code, code);
}

MailOutboxEntry _queued() => MailOutboxEntry.queued(
  id: 'queue',
  prepared: MailPreparedMessage(
    account: _account,
    draftId: 'original',
    draftRevision: 3,
    wire: MailBytes(utf8.encode('From: a@example.test\r\n\r\nFrozen MIME')),
    envelope: MailTransportEnvelope(
      sender: 'a@example.test',
      recipients: ['to@example.test', 'hidden@example.test'],
    ),
  ),
  now: _now,
);

MailDraft _draft(String id) => MailDraft(
  id: id,
  account: _account,
  revision: 0,
  envelope: MailEnvelope(subject: 'Editable copy'),
  body: const MailBody(plainText: 'Frozen MIME'),
  editorState: MailDraftEditorState(to: 'to@example.test'),
);

MailOutboxEntry _copy(
  MailOutboxEntry entry, {
  int? revision,
  DateTime? deadline,
  DateTime? updatedAt,
}) => MailOutboxEntry.restore(
  id: entry.id,
  prepared: entry.prepared,
  state: entry.state,
  createdAt: entry.createdAt,
  updatedAt: updatedAt ?? entry.updatedAt,
  attemptNumber: entry.attemptNumber,
  attemptId: entry.attemptId,
  result: entry.result,
  priorSubmissionUncertain: entry.priorSubmissionUncertain,
  sendNotBefore: deadline ?? entry.sendNotBefore,
  scheduleRevision: revision ?? entry.scheduleRevision,
);

Map<String, Object?> _json(String data) =>
    (jsonDecode(data) as Map<String, Object?>);

MailOutboxEntry _decode(MailStorePayload payload, [String? data]) =>
    MailStoreCodec.decodeOutbox(
      data ?? payload.data,
      account: _account,
      id: 'queue',
      blobs: payload.blobs,
    );

Future<SqliteMailRepository> _open(
  sqlite.Database database, {
  MailStoreFaultInjector? fault,
}) async => _value(
  await SqliteMailRepository.open(
    executor: NativeDatabase.opened(database, closeUnderlyingOnClose: false),
    profile: _profile,
    faultInjector: fault,
    clock: () => _deadline,
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
    expectedScheduleRevision: previous?.scheduleRevision,
  ),
);

void main() {
  group('schedule codec', () {
    test(
      'v1 and v2 restore as unscheduled without losing older uncertainty',
      () {
        final ordinary = _queued();
        final inherited = MailOutboxEntry.queued(
          id: ordinary.id,
          prepared: ordinary.prepared,
          now: _now,
          priorSubmissionUncertain: true,
        );
        for (final version in [1, 2]) {
          final payload = MailStoreCodec.encodeOutbox(
            version == 1 ? ordinary : inherited,
          );
          final legacy = _json(payload.data)
            ..['version'] = version
            ..remove('sendNotBefore')
            ..remove('scheduleRevision');
          if (version == 1) legacy.remove('priorSubmissionUncertain');
          final restored = _decode(payload, jsonEncode(legacy));
          expect(restored.sendNotBefore, isNull);
          expect(restored.scheduleRevision, 0);
          expect(restored.priorSubmissionUncertain, version == 2);
          expect(restored.prepared.wireHash, ordinary.prepared.wireHash);
        }
      },
    );

    test('v3 preserves UTC deadline and revision through terminal states', () {
      final scheduled = _queued().schedule(
        sendNotBefore: _deadline.toLocal(),
        now: _now,
      );
      final pending = scheduled.beginAttempt(
        attemptId: 'first',
        now: _deadline,
      );
      for (final entry in [
        scheduled,
        scheduled.schedule(sendNotBefore: null, now: _now),
        scheduled.cancel(now: _now),
        pending,
        for (final outcome in MailSubmissionOutcome.values)
          pending.complete(
            MailSubmissionResult(attemptId: 'first', outcome: outcome),
            now: _deadline,
          ),
        pending
            .recoverInterrupted(now: _deadline)
            .closeUncertain(now: _deadline),
      ]) {
        final payload = MailStoreCodec.encodeOutbox(entry);
        expect(_json(payload.data)['version'], 3);
        final restored = _decode(payload);
        expect(restored.sendNotBefore, entry.sendNotBefore);
        if (restored.sendNotBefore != null) {
          expect(restored.sendNotBefore!.isUtc, isTrue);
        }
        expect(restored.scheduleRevision, entry.scheduleRevision);
        expect(restored.state, entry.state);
        expect(MailStoreCodec.encodeOutbox(restored).data, payload.data);
      }
    });

    test('malformed schedules fail closed with redacted errors', () {
      final payload = MailStoreCodec.encodeOutbox(
        _queued().schedule(sendNotBefore: _deadline, now: _now),
      );
      for (final mutate in <void Function(Map<String, Object?>)>[
        (value) => value.remove('scheduleRevision'),
        (value) => value.remove('sendNotBefore'),
        (value) => value['scheduleRevision'] = null,
        (value) => value['scheduleRevision'] = -1,
        (value) => value['scheduleRevision'] = 1.0,
        (value) => value['scheduleRevision'] = 'secret-marker',
        (value) => value['scheduleRevision'] = 0,
        (value) =>
            value['scheduleRevision'] = MailOutboxEntry.maxScheduleRevision + 1,
        (value) => value['version'] = 3.0,
        (value) => value['version'] = 4,
        (value) => value['sendNotBefore'] = 'secret-marker',
        (value) =>
            (value['sendNotBefore'] as Map<String, Object?>)['utc'] = false,
        (value) => (value['sendNotBefore'] as Map<String, Object?>)['instant'] =
            '2026-11-21T15:00:00.000+01:00',
        (value) => (value['sendNotBefore'] as Map<String, Object?>)['instant'] =
            '2026-11-32T14:00:00.000Z',
        (value) => (value['sendNotBefore'] as Map<String, Object?>)['instant'] =
            _now.toIso8601String(),
        (value) => value['priorSubmissionUncertain'] = true,
        (value) => value['extra'] = 'secret-marker',
      ]) {
        final data = _json(payload.data);
        mutate(data);
        expect(
          () => _decode(payload, jsonEncode(data)),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'redacted message',
              'Invalid persisted mail data.',
            ),
          ),
        );
      }
    });

    test(
      'only explicit schedule edits can change the revision or deadline',
      () {
        final queued = _queued();
        final scheduled = queued.schedule(sendNotBefore: _deadline, now: _now);
        expect(MailStoreCodec.validOutboxTransition(queued, scheduled), isTrue);
        expect(MailStoreCodec.validOutboxTransition(null, scheduled), isFalse);
        expect(
          MailStoreCodec.validOutboxTransition(
            queued,
            _copy(scheduled, revision: 2),
          ),
          isFalse,
        );
        expect(
          MailStoreCodec.validOutboxTransition(
            scheduled,
            _copy(scheduled, deadline: _deadline.add(const Duration(hours: 1))),
          ),
          isFalse,
        );
        final pending = scheduled.beginAttempt(
          attemptId: 'first',
          now: _deadline,
        );
        expect(
          MailStoreCodec.validOutboxTransition(scheduled, pending),
          isTrue,
        );
        expect(
          MailStoreCodec.validOutboxTransition(
            scheduled,
            _copy(pending, revision: 2),
          ),
          isFalse,
        );
        expect(
          () => _copy(
            pending,
            updatedAt: _deadline.subtract(const Duration(seconds: 1)),
          ),
          throwsArgumentError,
        );
      },
    );
  });

  group('durable schedule writes', () {
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
            throw const MailStoreStorageException(
              MailProblemCode.storageFailure,
            );
          }
        },
      );
      _value(
        await store.createAccount(
          MailStoreAccount(
            id: _account,
            provider: MailProviderKind.imap,
            displayName: 'Synthetic account',
          ),
        ),
      );
    });

    tearDown(() async {
      await store.close();
      database.close();
    });

    test(
      'restart retains due work, frozen bytes and schedule revision',
      () async {
        final queued = _queued();
        await _save(store, queued);
        final scheduled = queued.schedule(sendNotBefore: _deadline, now: _now);
        await _save(store, scheduled, queued);
        await store.close();
        store = await _open(database);
        final restored = _value(await store.recoverOutbox(_account)).single;
        expect(restored.state, MailOutboxState.queued);
        expect(restored.sendNotBefore, _deadline);
        expect(restored.scheduleRevision, 1);
        expect(restored.isDueAt(_deadline), isTrue);
        expect(restored.attemptNumber, 0);
        expect(restored.prepared.wire.bytes, queued.prepared.wire.bytes);
        expect(
          restored.prepared.envelope.recipients,
          queued.prepared.envelope.recipients,
        );
        expect(database.select('SELECT * FROM outbox_attempts'), isEmpty);

        final pending = restored.beginAttempt(
          attemptId: 'first',
          now: _deadline,
        );
        await _save(store, pending, restored);
        await store.close();
        store = await _open(database);
        final interrupted = _value(await store.recoverOutbox(_account)).single;
        expect(interrupted.state, MailOutboxState.uncertain);
        expect(interrupted.sendNotBefore, _deadline);
        expect(interrupted.scheduleRevision, 1);
        expect(interrupted.canSchedule, isFalse);
        expect(interrupted.isDueAt(_deadline), isFalse);
        expect(database.select('SELECT * FROM outbox_attempts'), hasLength(1));
      },
    );

    test(
      'schedule writes require explicit revision before first scheduling',
      () async {
        final queued = _queued();
        await _save(store, queued);
        final scheduled = queued.schedule(sendNotBefore: _deadline, now: _now);
        _problem(
          await store.saveOutbox(
            scheduled,
            expectedState: queued.state,
            expectedAttemptId: queued.attemptId,
          ),
          MailProblemCode.conflict,
        );
        await _save(store, scheduled, queued);
        final cancelled = scheduled.cancel(now: _now);
        _problem(
          await store.saveOutbox(
            cancelled,
            expectedState: scheduled.state,
            expectedAttemptId: scheduled.attemptId,
          ),
          MailProblemCode.conflict,
        );
        await _save(store, cancelled, scheduled);
        expect(
          _value(await store.recoverOutbox(_account)).single.state,
          MailOutboxState.cancelled,
        );
      },
    );

    test(
      'ABA reschedule rejects stale cancel, send, edit and schedule decisions',
      () async {
        final queued = _queued();
        await _save(store, queued);
        final first = queued.schedule(sendNotBefore: _deadline, now: _now);
        await _save(store, first, queued);
        final cleared = first.schedule(sendNotBefore: null, now: _now);
        await _save(store, cleared, first);
        final repeated = cleared.schedule(sendNotBefore: _deadline, now: _now);
        await _save(store, repeated, cleared);
        expect(repeated.sendNotBefore, first.sendNotBefore);
        expect(repeated.updatedAt, first.updatedAt);
        expect(repeated.scheduleRevision, 3);
        for (final stale in [
          first.cancel(now: _deadline),
          first.beginAttempt(attemptId: 'stale-send', now: _deadline),
          first.schedule(sendNotBefore: null, now: _now),
        ]) {
          _problem(
            await store.saveOutbox(
              stale,
              expectedState: first.state,
              expectedAttemptId: first.attemptId,
              expectedScheduleRevision: first.scheduleRevision,
            ),
            MailProblemCode.conflict,
          );
        }
        _problem(
          await store.editOutboxAsDraft(first, _draft('stale-edit'), now: _now),
          MailProblemCode.conflict,
        );
        // A caller cannot submit an unpersisted +1 schedule as the edit snapshot.
        _problem(
          await store.editOutboxAsDraft(
            repeated.schedule(sendNotBefore: null, now: _now),
            _draft('invented-edit'),
            now: _now,
          ),
          MailProblemCode.conflict,
        );
        expect(_value(await store.loadDraft(_account, 'stale-edit')), isNull);
        expect(database.select('SELECT * FROM outbox_attempts'), isEmpty);
        final retained = _value(await store.recoverOutbox(_account)).single;
        expect(retained.scheduleRevision, 3);
        expect(retained.state, MailOutboxState.queued);
        _value(
          await store.editOutboxAsDraft(
            retained,
            _draft('current-edit'),
            now: _now,
          ),
        );
        final retired = _value(await store.recoverOutbox(_account)).single;
        expect(retired.scheduleRevision, 3);
        expect(retired.sendNotBefore, _deadline);
        expect(retired.state, MailOutboxState.cancelled);
      },
    );

    for (final checkpoint in [
      MailStoreCheckpoint.afterOutboxWrite,
      MailStoreCheckpoint.beforeCommit,
    ]) {
      test(
        'schedule rollback at ${checkpoint.name} preserves queue and bytes',
        () async {
          final queued = _queued();
          await _save(store, queued);
          final scheduled = queued.schedule(
            sendNotBefore: _deadline,
            now: _now,
          );
          failAt = checkpoint;
          _problem(
            await store.saveOutbox(
              scheduled,
              expectedState: queued.state,
              expectedAttemptId: queued.attemptId,
              expectedScheduleRevision: queued.scheduleRevision,
            ),
            MailProblemCode.storageFailure,
          );
          failAt = null;
          final retained = _value(await store.recoverOutbox(_account)).single;
          expect(retained.scheduleRevision, 0);
          expect(retained.sendNotBefore, isNull);
          expect(retained.prepared.wireHash, queued.prepared.wireHash);
          expect(database.select('SELECT * FROM blobs'), hasLength(1));
          expect(database.select('SELECT * FROM outbox_attempts'), isEmpty);
          await _save(store, scheduled, retained);
        },
      );
    }

    test(
      'clearing the deadline still fences stale unscheduled callers',
      () async {
        final queued = _queued();
        await _save(store, queued);
        final scheduled = queued.schedule(sendNotBefore: _deadline, now: _now);
        await _save(store, scheduled, queued);
        final cleared = scheduled.schedule(sendNotBefore: null, now: _now);
        await _save(store, cleared, scheduled);
        _problem(
          await store.saveOutbox(
            queued.beginAttempt(attemptId: 'old', now: _now),
            expectedState: queued.state,
            expectedAttemptId: queued.attemptId,
          ),
          MailProblemCode.conflict,
        );
        final pending = cleared.beginAttempt(attemptId: 'current', now: _now);
        await _save(store, pending, cleared);
        final accepted = pending.complete(
          MailSubmissionResult(
            attemptId: 'current',
            outcome: MailSubmissionOutcome.accepted,
          ),
          now: _now,
        );
        await _save(store, accepted, pending);
        final retained = _value(await store.recoverOutbox(_account)).single;
        expect(retained.scheduleRevision, 2);
        expect(retained.sendNotBefore, isNull);
        expect(retained.state, MailOutboxState.submitted);
      },
    );
  });
}
