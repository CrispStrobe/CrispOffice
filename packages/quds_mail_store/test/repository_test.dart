import 'dart:async';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:sqlite3/common.dart';
import 'package:test/test.dart';

T value<T>(MailResult<T> result) {
  expect(result, isA<MailSuccess<T>>());
  return (result as MailSuccess<T>).value;
}

void problem<T>(MailResult<T> result, MailProblemCode code) {
  expect(result, isA<MailFailure<T>>());
  expect((result as MailFailure<T>).problem.code, code);
}

final profile = MailProfileId('personal', hostId: 'test-office');
final account = MailAccountId('mail', profile: profile);
final mailbox = MailMailboxId('inbox', account: account);
MailImapIdentity remote(int uid, {int validity = 1}) =>
    MailImapIdentity(mailbox: mailbox, uidValidity: validity, uid: uid);
MailBytes bytes(String text) => MailBytes(Uint8List.fromList(text.codeUnits));
MailHeaderRecord header(
  int uid, {
  String subject = 'Project update',
  int validity = 1,
}) => MailHeaderRecord(
  id: MailMessageId('message-$validity-$uid'),
  remote: remote(uid, validity: validity),
  envelope: MailEnvelope(
    subject: subject,
    from: [const MailAddress('sender@example.invalid')],
  ),
);
MailSyncPage page(
  String cursor, {
  List<MailHeaderRecord>? upserts,
  List<MailRemoteIdentity> tombstones = const [],
  bool reset = false,
}) => MailSyncPage(
  mailbox: mailbox,
  upserts: upserts ?? [header(1)],
  tombstones: tombstones,
  next: MailCursor(mailbox: mailbox, value: cursor),
  hasMore: false,
  resetRequired: reset,
);
MailDraft draft(
  int revision, {
  String text = 'Working text',
  MailBytes? attachment,
}) => MailDraft(
  id: 'draft',
  account: account,
  revision: revision,
  envelope: MailEnvelope(
    subject: 'Offline draft',
    from: [const MailAddress('me@example.invalid')],
    to: [const MailAddress('you@example.invalid')],
  ),
  body: MailBody(plainText: text),
  attachments: [
    MailAttachment(
      partPath: '1',
      mediaType: 'application/octet-stream',
      displayName: 'document.bin',
      content: attachment ?? bytes('original attachment'),
    ),
  ],
);
MailOutboxEntry queued({String id = 'outbox'}) => MailOutboxEntry.queued(
  id: id,
  prepared: MailPreparedMessage(
    account: account,
    draftId: 'draft',
    draftRevision: 0,
    wire: bytes('From: me@example.invalid\r\n\r\nFrozen wire'),
    envelope: MailTransportEnvelope(
      sender: 'me@example.invalid',
      recipients: ['you@example.invalid'],
    ),
  ),
  now: DateTime.utc(2026, 11, 18),
);

void main() {
  late SqliteMailRepository store;
  late MailAccountSession session;
  MailStoreCheckpoint? failAt;
  Object? injectedFailure;
  Future<void> Function(MailStoreCheckpoint)? callback;

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    failAt = null;
    injectedFailure = null;
    callback = null;
    session = MailAccountSession(account);
    store = value(
      await SqliteMailRepository.open(
        executor: NativeDatabase.memory(),
        profile: profile,
        faultInjector: (point) async {
          await callback?.call(point);
          if (failAt == point)
            throw injectedFailure ??
                const MailStoreStorageException(MailProblemCode.storageFailure);
        },
      ),
    );
    value(
      await store.createAccount(
        MailStoreAccount(
          id: account,
          provider: MailProviderKind.imap,
          displayName: 'Personal',
          credentialReference: 'vault-key',
        ),
      ),
    );
    value(
      await store.saveMailbox(MailMailbox(id: mailbox, displayName: 'Inbox')),
    );
  });
  tearDown(() async => store.close());

  test(
    'commits headers and cursor with a compare-and-set precondition',
    () async {
      value(
        await store.commitSyncPage(
          page('c1'),
          expectedCursor: null,
          lease: session.begin(),
        ),
      );
      expect(value(await store.readCursor(mailbox))!.value, 'c1');
      expect(
        value(await store.listHeaders(mailbox)).single.envelope.subject,
        'Project update',
      );
      problem(
        await store.commitSyncPage(
          page('stale', upserts: [header(2)]),
          expectedCursor: null,
          lease: session.begin(),
        ),
        MailProblemCode.conflict,
      );
      expect(value(await store.listHeaders(mailbox)).map((m) => m.id.value), [
        'message-1-1',
      ]);
      expect(value(await store.readCursor(mailbox))!.value, 'c1');
    },
  );

  test('failure after records rolls back rows and cursor together', () async {
    failAt = MailStoreCheckpoint.afterSyncRecords;
    problem(
      await store.commitSyncPage(
        page('c1'),
        expectedCursor: null,
        lease: session.begin(),
      ),
      MailProblemCode.storageFailure,
    );
    expect(value(await store.readCursor(mailbox)), isNull);
    expect(value(await store.listHeaders(mailbox)), isEmpty);
    expect(value(await store.search(account, 'Project')), isEmpty);
  });

  test('lease invalidation at the final commit boundary rolls back', () async {
    callback = (point) async {
      if (point == MailStoreCheckpoint.beforeCommit) session.invalidate();
    };
    problem(
      await store.commitSyncPage(
        page('c1'),
        expectedCursor: null,
        lease: session.begin(),
      ),
      MailProblemCode.staleOperation,
    );
    expect(value(await store.readCursor(mailbox)), isNull);
    expect(value(await store.listHeaders(mailbox)), isEmpty);
  });

  test(
    'header stream never exposes rolled-back or half-applied pages',
    () async {
      final snapshots = <List<String>>[];
      final initial = Completer<void>();
      final committed = Completer<void>();
      final subscription = store.watchHeaders(mailbox).listen((event) {
        final ids = value(event).map((m) => m.id.value).toList();
        snapshots.add(ids);
        if (!initial.isCompleted) initial.complete();
        if (ids.length == 2 && !committed.isCompleted) committed.complete();
      });
      await initial.future;
      failAt = MailStoreCheckpoint.beforeCommit;
      problem(
        await store.commitSyncPage(
          page('bad'),
          expectedCursor: null,
          lease: session.begin(),
        ),
        MailProblemCode.storageFailure,
      );
      failAt = null;
      value(
        await store.commitSyncPage(
          page('good', upserts: [header(1), header(2)]),
          expectedCursor: null,
          lease: session.begin(),
        ),
      );
      await committed.future.timeout(const Duration(seconds: 5));
      await subscription.cancel();
      expect(snapshots.every((v) => v.isEmpty || v.length == 2), isTrue);
    },
  );

  test('draft revisions reject lost updates and attachment rollback', () async {
    value(await store.saveDraft(draft(0), expectedRevision: null));
    final results = await Future.wait([
      store.saveDraft(draft(1, text: 'one'), expectedRevision: 0),
      store.saveDraft(draft(1, text: 'two'), expectedRevision: 0),
    ]);
    expect(results.whereType<MailSuccess<MailUnit>>().length, 1);
    expect(
      results.whereType<MailFailure<MailUnit>>().single.problem.code,
      MailProblemCode.conflict,
    );
    failAt = MailStoreCheckpoint.afterDraftBlobs;
    problem(
      await store.saveDraft(
        draft(2, attachment: bytes('replacement')),
        expectedRevision: 1,
      ),
      MailProblemCode.storageFailure,
    );
    final saved = value(await store.loadDraft(account, 'draft'))!;
    expect(saved.revision, 1);
    expect(
      saved.attachments.single.content.sha256,
      bytes('original attachment').sha256,
    );
  });

  test('new and terminal outbox states cannot be forged', () async {
    final original = queued();
    final sending = original.beginAttempt(
      attemptId: 'first',
      now: DateTime.utc(2026, 11, 18, 1),
    );
    problem(
      await store.saveOutbox(
        sending,
        expectedState: null,
        expectedAttemptId: null,
      ),
      MailProblemCode.conflict,
    );
    value(
      await store.saveOutbox(
        original,
        expectedState: null,
        expectedAttemptId: null,
      ),
    );
    value(
      await store.saveOutbox(
        sending,
        expectedState: MailOutboxState.queued,
        expectedAttemptId: null,
      ),
    );
    final uncertain = sending.complete(
      MailSubmissionResult(
        attemptId: 'first',
        outcome: MailSubmissionOutcome.uncertain,
      ),
      now: DateTime.utc(2026, 11, 18, 2),
    );
    value(
      await store.saveOutbox(
        uncertain,
        expectedState: MailOutboxState.submitting,
        expectedAttemptId: 'first',
      ),
    );
    problem(
      await store.saveOutbox(
        original,
        expectedState: MailOutboxState.uncertain,
        expectedAttemptId: 'first',
      ),
      MailProblemCode.conflict,
    );
    expect(
      value(await store.recoverOutbox(account)).single.state,
      MailOutboxState.uncertain,
    );
  });

  test(
    'recovery does not relabel an attempt started by this live owner',
    () async {
      final original = queued();
      value(
        await store.saveOutbox(
          original,
          expectedState: null,
          expectedAttemptId: null,
        ),
      );
      final sending = original.beginAttempt(
        attemptId: 'live',
        now: DateTime.utc(2026, 11, 18, 1),
      );
      value(
        await store.saveOutbox(
          sending,
          expectedState: MailOutboxState.queued,
          expectedAttemptId: null,
        ),
      );
      expect(
        value(await store.recoverOutbox(account)).single.state,
        MailOutboxState.submitting,
      );
    },
  );

  test(
    'older attempt identifiers cannot be reused after multiple retries',
    () async {
      var entry = queued();
      value(
        await store.saveOutbox(
          entry,
          expectedState: null,
          expectedAttemptId: null,
        ),
      );
      for (final id in ['first', 'second']) {
        final old = entry;
        entry = entry.beginAttempt(
          attemptId: id,
          now: DateTime.utc(2026, 11, 18, 1),
        );
        value(
          await store.saveOutbox(
            entry,
            expectedState: old.state,
            expectedAttemptId: old.attemptId,
          ),
        );
        final failed = entry.complete(
          MailSubmissionResult(
            attemptId: id,
            outcome: MailSubmissionOutcome.retryableFailure,
          ),
          now: DateTime.utc(2026, 11, 18, 1),
        );
        value(
          await store.saveOutbox(
            failed,
            expectedState: entry.state,
            expectedAttemptId: entry.attemptId,
          ),
        );
        entry = failed;
      }
      problem(
        await store.saveOutbox(
          entry.beginAttempt(
            attemptId: 'first',
            now: DateTime.utc(2026, 11, 18, 2),
          ),
          expectedState: entry.state,
          expectedAttemptId: entry.attemptId,
        ),
        MailProblemCode.conflict,
      );
      expect(
        value(await store.recoverOutbox(account)).single.attemptId,
        'second',
      );
    },
  );

  test(
    'cache eviction preserves shared draft attachments and editor pins',
    () async {
      value(
        await store.commitSyncPage(
          page('c1'),
          expectedCursor: null,
          lease: session.begin(),
        ),
      );
      final shared = bytes('shared file');
      value(
        await store.saveDraft(
          draft(0, attachment: shared),
          expectedRevision: null,
        ),
      );
      final message = MailMessage(
        raw: bytes('original source'),
        envelope: header(1).envelope,
        localId: header(1).id,
        remoteIdentity: remote(1),
        body: const MailBody(plainText: 'searchable nebulous'),
        attachments: [
          MailAttachment(
            partPath: '1',
            mediaType: 'application/octet-stream',
            displayName: 'file',
            content: shared,
          ),
        ],
      );
      value(await store.cacheMessage(account, header(1).id, message));
      expect(value(await store.search(account, 'nebulous')).length, 1);
      final pin = value(
        await store.pinBlob(account, pinId: 'editor', bytes: shared),
      );
      expect(value(await store.evictCache(account)), 0);
      value(await store.releasePin(pin));
      expect(value(await store.evictCache(account)), 1);
      expect(
        value(await store.loadCachedMessage(account, header(1).id)),
        isNull,
      );
      expect(value(await store.search(account, 'nebulous')), isEmpty);
      expect(value(await store.search(account, 'Project')).length, 1);
      expect(
        value(
          await store.loadDraft(account, 'draft'),
        )!.attachments.single.content.sha256,
        shared.sha256,
      );
    },
  );

  test('local FTS uses literal tokens and never indexes active HTML', () async {
    value(
      await store.commitSyncPage(
        page('c1'),
        expectedCursor: null,
        lease: session.begin(),
      ),
    );
    value(
      await store.cacheMessage(
        account,
        header(1).id,
        MailMessage(
          raw: bytes('raw'),
          envelope: header(1).envelope,
          remoteIdentity: remote(1),
          body: const MailBody(html: '<script>secretmarker</script>'),
        ),
      ),
    );
    expect(value(await store.search(account, 'secretmarker')), isEmpty);
    expect(value(await store.search(account, 'Project OR unrelated')), isEmpty);
    expect(value(await store.search(account, '"Project"')).length, 1);
    expect(
      value(await store.search(account, "'); DROP TABLE messages; --")),
      isEmpty,
    );
    expect(value(await store.listHeaders(mailbox)).length, 1);
    problem(
      await store.search(account, 'x' * 257),
      MailProblemCode.invalidInput,
    );
  });

  test(
    'tombstone preserves a pending intent for explicit reconciliation',
    () async {
      value(
        await store.commitSyncPage(
          page('c1'),
          expectedCursor: null,
          lease: session.begin(),
        ),
      );
      value(
        await store.enqueueOperation(
          MailSetRead(id: 'read', message: remote(1), read: true),
          session.begin(),
        ),
      );
      value(
        await store.commitSyncPage(
          page('c2', upserts: [], tombstones: [remote(1)]),
          expectedCursor: MailCursor(mailbox: mailbox, value: 'c1'),
          lease: session.begin(),
        ),
      );
      expect(value(await store.listHeaders(mailbox)), isEmpty);
      final pending = value(await store.pendingOperations(account)).single;
      expect(pending.state, MailPendingState.reconcile);
      expect(pending.operation, isA<MailSetRead>());
      problem(
        await store.transitionOperation(
          account,
          'read',
          expectedRevision: pending.revision,
          state: MailPendingState.queued,
          lease: session.begin(),
        ),
        MailProblemCode.conflict,
      );
      value(
        await store.transitionOperation(
          account,
          'read',
          expectedRevision: pending.revision,
          state: MailPendingState.cancelled,
          lease: session.begin(),
        ),
      );
      expect(value(await store.pendingOperations(account)), isEmpty);
    },
  );

  test(
    'UIDVALIDITY reset keeps local work and rejects stale cursor pages',
    () async {
      value(await store.saveDraft(draft(0), expectedRevision: null));
      value(
        await store.commitSyncPage(
          page('v1'),
          expectedCursor: null,
          lease: session.begin(),
        ),
      );
      value(
        await store.enqueueOperation(
          MailDelete(id: 'delete', message: remote(1)),
          session.begin(),
        ),
      );
      value(
        await store.commitSyncPage(
          page('v2', upserts: [header(1, validity: 2)], reset: true),
          expectedCursor: MailCursor(mailbox: mailbox, value: 'v1'),
          lease: session.begin(),
        ),
      );
      expect(
        value(await store.listHeaders(mailbox)).single.id.value,
        'message-2-1',
      );
      expect(
        value(await store.pendingOperations(account)).single.state,
        MailPendingState.reconcile,
      );
      expect(value(await store.loadDraft(account, 'draft'))!.revision, 0);
      problem(
        await store.commitSyncPage(
          page('late'),
          expectedCursor: MailCursor(mailbox: mailbox, value: 'v1'),
          lease: session.begin(),
        ),
        MailProblemCode.conflict,
      );
    },
  );

  test(
    'logout preserves local drafts and queues durable vault cleanup',
    () async {
      value(await store.saveDraft(draft(0), expectedRevision: null));
      value(
        await store.saveOutbox(
          queued(),
          expectedState: null,
          expectedAttemptId: null,
        ),
      );
      final lease = session.begin();
      value(await store.logout(session));
      expect(lease.isCurrent, isFalse);
      expect(value(await store.loadDraft(account, 'draft'))!.revision, 0);
      expect(
        value(await store.recoverOutbox(account)).single.state,
        MailOutboxState.queued,
      );
      problem(
        await store.commitSyncPage(
          page('c1'),
          expectedCursor: null,
          lease: session.begin(),
        ),
        MailProblemCode.authenticationRequired,
      );
      expect(
        value(await store.credentialCleanup()).single.reference,
        'vault-key',
      );
      problem(
        await store.resumeAccount(account, credentialReference: 'vault-key'),
        MailProblemCode.conflict,
      );
      value(
        await store.acknowledgeCredentialCleanup(
          value(await store.credentialCleanup()).single,
        ),
      );
      value(
        await store.resumeAccount(account, credentialReference: 'fresh-key'),
      );
      value(
        await store.commitSyncPage(
          page('c1'),
          expectedCursor: null,
          lease: session.begin(),
        ),
      );
    },
  );

  test('account removal retires identity and rejects late writes', () async {
    value(await store.saveDraft(draft(0), expectedRevision: null));
    value(await store.removeAccount(account));
    expect(value(await store.listAccounts()), isEmpty);
    problem(
      await store.loadDraft(account, 'draft'),
      MailProblemCode.unavailable,
    );
    problem(
      await store.commitSyncPage(
        page('late'),
        expectedCursor: null,
        lease: session.begin(),
      ),
      MailProblemCode.unavailable,
    );
    problem(
      await store.createAccount(
        MailStoreAccount(
          id: account,
          provider: MailProviderKind.imap,
          displayName: 'Recreated',
        ),
      ),
      MailProblemCode.conflict,
    );
    expect(
      value(await store.credentialCleanup()).single.reference,
      'vault-key',
    );
  });

  test(
    'profile and account scope reject matching foreign identifiers',
    () async {
      final other = MailAccountId(
        account.value,
        profile: MailProfileId(profile.value, hostId: 'different-host'),
      );
      problem(
        await store.loadDraft(other, 'draft'),
        MailProblemCode.permissionDenied,
      );
      problem(
        await store.createAccount(
          MailStoreAccount(
            id: other,
            provider: MailProviderKind.imap,
            displayName: 'Other',
          ),
        ),
        MailProblemCode.permissionDenied,
      );
    },
  );

  test(
    'SQLite full has a typed redacted failure and leaves no partial write',
    () async {
      injectedFailure = SqliteException(
        extendedResultCode: 13,
        message: 'DO NOT LEAK subject password body',
        causingStatement: 'SQL private',
      );
      failAt = MailStoreCheckpoint.afterDraftBlobs;
      final result = await store.saveDraft(draft(0), expectedRevision: null);
      problem(result, MailProblemCode.quotaExceeded);
      expect(
        (result as MailFailure<MailUnit>).problem.toString(),
        isNot(contains('DO NOT LEAK')),
      );
      expect(value(await store.loadDraft(account, 'draft')), isNull);
    },
  );
}
