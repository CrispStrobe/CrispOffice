import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:test/test.dart';

final _time = DateTime.utc(2026, 11, 18, 12);

MailBytes _bytes(List<int> values) => MailBytes(Uint8List.fromList(values));

Future<T> _ok<T>(Future<MailResult<T>> operation) async {
  final result = await operation;
  expect(result, isA<MailSuccess<T>>());
  return (result as MailSuccess<T>).value;
}

Future<void> _fails<T>(
  Future<MailResult<T>> operation,
  MailProblemCode code,
) async {
  final result = await operation;
  expect(result, isA<MailFailure<T>>());
  expect((result as MailFailure<T>).problem.code, code);
}

final class _Fixture {
  _Fixture(this.store, this.account, this.mailbox)
    : session = MailAccountSession(account);

  final SqliteMailRepository store;
  final MailAccountId account;
  final MailMailboxId mailbox;
  final MailAccountSession session;

  MailHeaderRecord header(String id, {int validity = 1, int uid = 1}) =>
      MailHeaderRecord(
        id: MailMessageId(id),
        remote: MailImapIdentity(
          mailbox: mailbox,
          uidValidity: validity,
          uid: uid,
        ),
        envelope: MailEnvelope(subject: 'Synthetic $id'),
      );

  MailSyncPage page(
    String cursor, {
    List<MailHeaderRecord> headers = const [],
    List<MailRemoteIdentity> tombstones = const [],
    bool reset = false,
  }) => MailSyncPage(
    mailbox: mailbox,
    upserts: headers,
    tombstones: tombstones,
    next: MailCursor(mailbox: mailbox, value: cursor),
    hasMore: false,
    resetRequired: reset,
  );

  Future<MailResult<MailUnit>> commit(MailSyncPage page, {String? expected}) =>
      store.commitSyncPage(
        page,
        expectedCursor: expected == null
            ? null
            : MailCursor(mailbox: mailbox, value: expected),
        lease: session.begin(),
      );
}

Future<_Fixture> _fixture({
  MailStoreFaultInjector? fault,
  MailStoreLimits limits = const MailStoreLimits(),
}) async {
  final profile = MailProfileId('test', hostId: 'independent-tests');
  final store = await _ok(
    SqliteMailRepository.open(
      executor: NativeDatabase.memory(),
      profile: profile,
      faultInjector: fault,
      limits: limits,
      clock: () => _time,
    ),
  );
  addTearDown(store.close);
  final account = MailAccountId('account', profile: profile);
  final mailbox = MailMailboxId('inbox', account: account);
  await _ok(
    store.createAccount(
      MailStoreAccount(
        id: account,
        provider: MailProviderKind.imap,
        displayName: 'Synthetic account',
        credentialReference: 'opaque-vault-reference',
      ),
    ),
  );
  return _Fixture(store, account, mailbox);
}

MailDraft _draft(
  MailAccountId account, {
  int revision = 0,
  String text = 'Draft text',
  List<MailAttachment> attachments = const [],
}) => MailDraft(
  id: 'draft',
  account: account,
  revision: revision,
  envelope: MailEnvelope(subject: 'Synthetic draft'),
  body: MailBody(plainText: text),
  attachments: attachments,
);

MailPreparedMessage _prepared(
  MailAccountId account, {
  MailBytes? wire,
  List<String> recipients = const ['recipient@example.invalid'],
}) => MailPreparedMessage(
  account: account,
  draftId: 'draft',
  draftRevision: 0,
  wire: wire ?? _bytes([65, 66, 67]),
  envelope: MailTransportEnvelope(
    sender: 'sender@example.invalid',
    recipients: recipients,
  ),
);

MailOutboxEntry _queued(MailAccountId account, {MailBytes? wire}) =>
    MailOutboxEntry.queued(
      id: 'outbox',
      prepared: _prepared(account, wire: wire),
      now: _time,
    );

Future<void> _save(
  SqliteMailRepository store,
  MailOutboxEntry entry, [
  MailOutboxEntry? previous,
]) => _ok(
  store.saveOutbox(
    entry,
    expectedState: previous?.state,
    expectedAttemptId: previous?.attemptId,
  ),
);

Future<(File, MailProfileId, MailAccountId)> _persistentIdentity() async {
  final directory = await Directory.systemTemp.createTemp('mail-adversarial-');
  addTearDown(() => directory.delete(recursive: true));
  final profile = MailProfileId('durable', hostId: 'independent-tests');
  return (
    File('${directory.path}/mail.sqlite3'),
    profile,
    MailAccountId('account', profile: profile),
  );
}

Future<SqliteMailRepository> _open(
  File file,
  MailProfileId profile, {
  MailStoreFaultInjector? fault,
}) async {
  final store = await _ok(
    SqliteMailRepository.open(
      executor: NativeDatabase(file),
      profile: profile,
      clock: () => _time.add(const Duration(minutes: 1)),
      faultInjector: fault,
    ),
  );
  addTearDown(store.close);
  return store;
}

Future<void> _register(SqliteMailRepository store, MailAccountId account) =>
    _ok(
      store.createAccount(
        MailStoreAccount(
          id: account,
          provider: MailProviderKind.imap,
          displayName: 'Synthetic',
          credentialReference: 'opaque-vault-reference',
        ),
      ),
    );

void main() {
  test(
    'competing pages cannot overwrite a concurrently advanced cursor',
    () async {
      final f = await _fixture();
      final results = await Future.wait([
        f.commit(f.page('one', headers: [f.header('one')])),
        f.commit(f.page('two', headers: [f.header('two', uid: 2)])),
      ]);
      expect(results.whereType<MailSuccess<MailUnit>>(), hasLength(1));
      final failure = results.whereType<MailFailure<MailUnit>>().single;
      expect(failure.problem.code, MailProblemCode.conflict);
      final cursor = (await _ok(f.store.readCursor(f.mailbox)))!;
      final headers = await _ok(f.store.listHeaders(f.mailbox));
      expect(headers.map((h) => h.id.value), [cursor.value]);
    },
  );

  test(
    'lease invalidated after cursor write rolls back the complete page',
    () async {
      var armed = false;
      late MailAccountSession session;
      final f = await _fixture(
        fault: (point) {
          if (armed && point == MailStoreCheckpoint.beforeCommit) {
            session.invalidate();
          }
        },
      );
      session = f.session;
      armed = true;
      await _fails(
        f.commit(f.page('one', headers: [f.header('one')])),
        MailProblemCode.staleOperation,
      );
      expect(await _ok(f.store.readCursor(f.mailbox)), isNull);
      expect(await _ok(f.store.listHeaders(f.mailbox)), isEmpty);
      expect(await _ok(f.store.search(f.account, 'Synthetic')), isEmpty);
    },
  );

  test('rolled back notifications never reach repository observers', () async {
    var rejectCommit = false;
    final f = await _fixture(
      fault: (point) {
        if (rejectCommit && point == MailStoreCheckpoint.beforeCommit) {
          throw const MailStoreStorageException(MailProblemCode.quotaExceeded);
        }
      },
    );
    final snapshots = <List<String>>[];
    final first = Completer<void>();
    final published = Completer<void>();
    final subscription = f.store.watchHeaders(f.mailbox).listen((event) {
      expect(event, isA<MailSuccess<List<MailHeaderRecord>>>());
      final ids = (event as MailSuccess<List<MailHeaderRecord>>).value
          .map((header) => header.id.value)
          .toList();
      snapshots.add(ids);
      if (!first.isCompleted) first.complete();
      if (ids.isNotEmpty && !published.isCompleted) published.complete();
    });
    addTearDown(subscription.cancel);
    await first.future.timeout(const Duration(seconds: 5));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final beforeFailure = snapshots.length;
    expect(snapshots.every((snapshot) => snapshot.isEmpty), isTrue);
    rejectCommit = true;
    await _fails(
      f.commit(f.page('rejected', headers: [f.header('rejected')])),
      MailProblemCode.quotaExceeded,
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(snapshots.length, beforeFailure);
    expect(snapshots.every((snapshot) => snapshot.isEmpty), isTrue);
    rejectCommit = false;
    await _ok(f.commit(f.page('accepted', headers: [f.header('accepted')])));
    await published.future.timeout(const Duration(seconds: 5));
    expect(snapshots, [
      <String>[],
      ['accepted'],
    ]);
  });

  test(
    'UID validity reset preserves pending intent and its cached evidence',
    () async {
      final f = await _fixture();
      final old = f.header('old');
      await _ok(f.commit(f.page('old-cursor', headers: [old])));
      final bytes = _bytes([1, 2, 3, 4]);
      await _ok(
        f.store.cacheMessage(
          f.account,
          old.id,
          MailMessage(
            raw: bytes,
            localId: old.id,
            remoteIdentity: old.remote,
            envelope: old.envelope,
            body: const MailBody(plainText: 'Old generation evidence'),
          ),
        ),
      );
      await _ok(
        f.store.enqueueOperation(
          MailSetRead(id: 'read-old', message: old.remote, read: true),
          f.session.begin(),
        ),
      );
      final replacement = f.header('new', validity: 2);
      await _ok(
        f.commit(
          f.page('new-cursor', headers: [replacement], reset: true),
          expected: 'old-cursor',
        ),
      );
      final pending = (await _ok(f.store.pendingOperations(f.account))).single;
      expect(pending.operation.message, old.remote);
      expect(pending.state, MailPendingState.reconcile);
      expect(pending.revision, 1);
      expect(
        (await _ok(f.store.listHeaders(f.mailbox))).single.id,
        replacement.id,
      );
      expect(
        (await _ok(f.store.loadCachedMessage(f.account, old.id)))!.raw.sha256,
        bytes.sha256,
      );
      await _fails(
        f.store.transitionOperation(
          f.account,
          'read-old',
          expectedRevision: 0,
          state: MailPendingState.applying,
          lease: f.session.begin(),
        ),
        MailProblemCode.conflict,
      );
      await _fails(
        f.store.transitionOperation(
          f.account,
          'read-old',
          expectedRevision: 1,
          state: MailPendingState.queued,
          lease: f.session.begin(),
        ),
        MailProblemCode.conflict,
      );
    },
  );

  test('a tombstone removes only its label membership', () async {
    final profile = MailProfileId('labels', hostId: 'independent-tests');
    final store = await _ok(
      SqliteMailRepository.open(
        executor: NativeDatabase.memory(),
        profile: profile,
      ),
    );
    addTearDown(store.close);
    final account = MailAccountId('account', profile: profile);
    await _ok(
      store.createAccount(
        MailStoreAccount(
          id: account,
          provider: MailProviderKind.gmail,
          displayName: 'Synthetic',
        ),
      ),
    );
    final inbox = MailMailboxId('INBOX', account: account);
    final retained = MailMailboxId('retained', account: account);
    final remote = MailOpaqueIdentity(
      account: account,
      provider: MailProviderKind.gmail,
      value: 'provider-id',
    );
    final header = MailHeaderRecord(
      id: MailMessageId('local'),
      remote: remote,
      envelope: MailEnvelope(subject: 'Shared membership'),
    );
    final session = MailAccountSession(account);
    for (final box in [inbox, retained]) {
      await _ok(
        store.commitSyncPage(
          MailSyncPage(
            mailbox: box,
            upserts: [header],
            tombstones: const [],
            next: MailCursor(mailbox: box, value: 'one'),
            hasMore: false,
          ),
          expectedCursor: null,
          lease: session.begin(),
        ),
      );
    }
    await _ok(
      store.commitSyncPage(
        MailSyncPage(
          mailbox: inbox,
          upserts: const [],
          tombstones: [remote],
          next: MailCursor(mailbox: inbox, value: 'two'),
          hasMore: false,
        ),
        expectedCursor: MailCursor(mailbox: inbox, value: 'one'),
        lease: session.begin(),
      ),
    );
    expect(await _ok(store.listHeaders(inbox)), isEmpty);
    expect((await _ok(store.listHeaders(retained))).single.id, header.id);
  });

  test(
    'cache eviction preserves draft, outbox and active-editor byte owners',
    () async {
      final f = await _fixture();
      final header = f.header('cached');
      await _ok(f.commit(f.page('one', headers: [header])));
      final attachment = MailAttachment(
        partPath: '1.2',
        mediaType: 'application/octet-stream',
        displayName: 'synthetic.bin',
        content: _bytes([0, 254, 255]),
      );
      final raw = _bytes([65, 0, 66, 255]);
      await _ok(
        f.store.cacheMessage(
          f.account,
          header.id,
          MailMessage(
            raw: raw,
            envelope: header.envelope,
            remoteIdentity: header.remote,
            localId: header.id,
            attachments: [attachment],
            body: const MailBody(plainText: 'Cached local text'),
          ),
        ),
      );
      await _ok(
        f.store.saveDraft(
          _draft(f.account, attachments: [attachment]),
          expectedRevision: null,
        ),
      );
      await _save(f.store, _queued(f.account, wire: raw));
      final pin = await _ok(
        f.store.pinBlob(
          f.account,
          pinId: 'editor-copy',
          bytes: attachment.content,
        ),
      );
      expect(await _ok(f.store.evictCache(f.account)), 0);
      await _ok(f.store.releasePin(pin));
      expect(await _ok(f.store.evictCache(f.account)), 1);
      expect(
        await _ok(f.store.loadCachedMessage(f.account, header.id)),
        isNull,
      );
      expect(
        (await _ok(
          f.store.loadDraft(f.account, 'draft'),
        ))!.attachments.single.content.sha256,
        attachment.content.sha256,
      );
      expect(
        (await _ok(f.store.recoverOutbox(f.account))).single.prepared.wireHash,
        raw.sha256,
      );
    },
  );

  test(
    'frozen outbox payload and uncertain state cannot be replaced through restore',
    () async {
      final f = await _fixture();
      final queued = _queued(f.account);
      await _save(f.store, queued);
      final substituted = MailOutboxEntry.queued(
        id: queued.id,
        prepared: _prepared(f.account, wire: _bytes([9, 9, 9])),
        now: queued.createdAt,
      );
      await _fails(
        f.store.saveOutbox(
          substituted,
          expectedState: queued.state,
          expectedAttemptId: null,
        ),
        MailProblemCode.conflict,
      );
      final active = queued.beginAttempt(
        attemptId: 'attempt-one',
        now: _time.add(const Duration(seconds: 1)),
      );
      await _save(f.store, active, queued);
      expect(
        (await _ok(f.store.recoverOutbox(f.account))).single.state,
        MailOutboxState.submitting,
      );
      final uncertain = active.complete(
        MailSubmissionResult(
          attemptId: active.attemptId!,
          outcome: MailSubmissionOutcome.uncertain,
        ),
        now: _time.add(const Duration(seconds: 2)),
      );
      await _save(f.store, uncertain, active);
      await _fails(
        f.store.saveOutbox(
          queued,
          expectedState: uncertain.state,
          expectedAttemptId: uncertain.attemptId,
        ),
        MailProblemCode.conflict,
      );
      final forgedTime = MailOutboxEntry.restore(
        id: uncertain.id,
        prepared: uncertain.prepared,
        state: uncertain.state,
        createdAt: uncertain.createdAt,
        updatedAt: uncertain.updatedAt.add(const Duration(seconds: 1)),
        attemptNumber: uncertain.attemptNumber,
        attemptId: uncertain.attemptId,
        result: uncertain.result,
      );
      await _fails(
        f.store.saveOutbox(
          forgedTime,
          expectedState: uncertain.state,
          expectedAttemptId: uncertain.attemptId,
        ),
        MailProblemCode.conflict,
      );
    },
  );

  test(
    'an older attempt identity cannot be reused after a newer retry',
    () async {
      final f = await _fixture();
      var entry = _queued(f.account);
      await _save(f.store, entry);
      for (var attempt = 1; attempt <= 2; attempt++) {
        final active = entry.beginAttempt(
          attemptId: 'attempt-$attempt',
          now: _time.add(Duration(seconds: attempt * 2)),
        );
        await _save(f.store, active, entry);
        entry = active.complete(
          MailSubmissionResult(
            attemptId: active.attemptId!,
            outcome: MailSubmissionOutcome.retryableFailure,
          ),
          now: _time.add(Duration(seconds: attempt * 2 + 1)),
        );
        await _save(f.store, entry, active);
      }
      final reused = entry.beginAttempt(
        attemptId: 'attempt-1',
        now: _time.add(const Duration(seconds: 6)),
      );
      await _fails(
        f.store.saveOutbox(
          reused,
          expectedState: entry.state,
          expectedAttemptId: entry.attemptId,
        ),
        MailProblemCode.conflict,
      );
      final stored = (await _ok(f.store.recoverOutbox(f.account))).single;
      expect(stored.state, MailOutboxState.retryableFailure);
      expect(stored.attemptId, 'attempt-2');
      expect(stored.attemptNumber, 2);
    },
  );

  test(
    'failed draft replacement retains its old revision and every old blob',
    () async {
      var failAfterBlobs = false;
      final f = await _fixture(
        fault: (point) {
          if (failAfterBlobs && point == MailStoreCheckpoint.afterDraftBlobs) {
            throw const MailStoreStorageException(
              MailProblemCode.quotaExceeded,
            );
          }
        },
      );
      final attachment = MailAttachment(
        partPath: '1',
        mediaType: 'text/plain',
        displayName: 'original',
        content: _bytes([1, 2, 3]),
      );
      await _ok(
        f.store.saveDraft(
          _draft(f.account, attachments: [attachment]),
          expectedRevision: null,
        ),
      );
      failAfterBlobs = true;
      await _fails(
        f.store.saveDraft(
          _draft(f.account, revision: 1, text: 'Changed'),
          expectedRevision: 0,
        ),
        MailProblemCode.quotaExceeded,
      );
      final stored = (await _ok(f.store.loadDraft(f.account, 'draft')))!;
      expect(stored.revision, 0);
      expect(stored.body.plainText, 'Draft text');
      expect(
        stored.attachments.single.content.sha256,
        attachment.content.sha256,
      );
    },
  );

  test(
    'durable recovery rolls back on failure and remains uncertain after reopening',
    () async {
      final (file, profile, account) = await _persistentIdentity();
      var store = await _open(file, profile);
      await _register(store, account);
      final queued = _queued(account);
      await _save(store, queued);
      final active = queued.beginAttempt(
        attemptId: 'interrupted',
        now: _time.add(const Duration(seconds: 1)),
      );
      await _save(store, active, queued);
      await store.close();
      store = await _open(
        file,
        profile,
        fault: (point) {
          if (point == MailStoreCheckpoint.beforeCommit) {
            throw const MailStoreStorageException(
              MailProblemCode.quotaExceeded,
            );
          }
        },
      );
      await _fails(store.recoverOutbox(account), MailProblemCode.quotaExceeded);
      await store.close();
      final inspection = sqlite.sqlite3.open(file.path);
      try {
        expect(
          inspection.select('SELECT state FROM outbox').single['state'],
          'submitting',
        );
      } finally {
        inspection.close();
      }
      store = await _open(file, profile);
      final recovered = (await _ok(store.recoverOutbox(account))).single;
      expect(recovered.state, MailOutboxState.uncertain);
      expect(recovered.canBeginAttempt, isFalse);
      await store.close();
      store = await _open(file, profile);
      expect(
        (await _ok(store.recoverOutbox(account))).single.state,
        MailOutboxState.uncertain,
      );
    },
  );

  test(
    'a corrupt persisted blob is rejected instead of silently served',
    () async {
      final (file, profile, account) = await _persistentIdentity();
      var store = await _open(file, profile);
      await _register(store, account);
      final attachment = MailAttachment(
        partPath: '1',
        mediaType: 'application/octet-stream',
        displayName: 'synthetic.bin',
        content: _bytes([1, 2, 3]),
      );
      await _ok(
        store.saveDraft(
          _draft(account, attachments: [attachment]),
          expectedRevision: null,
        ),
      );
      await store.close();
      final corruption = sqlite.sqlite3.open(file.path);
      try {
        corruption.execute('UPDATE blobs SET data=? WHERE hash=?', [
          Uint8List.fromList([4, 5, 6]),
          attachment.content.sha256,
        ]);
      } finally {
        corruption.close();
      }
      store = await _open(file, profile);
      await _fails(
        store.loadDraft(account, 'draft'),
        MailProblemCode.storageFailure,
      );
    },
  );

  test('identical profile labels cannot open another host database', () async {
    final (file, profile, account) = await _persistentIdentity();
    final store = await _open(file, profile);
    await _register(store, account);
    await _ok(store.saveDraft(_draft(account), expectedRevision: null));
    final foreign = MailProfileId(profile.value, hostId: 'another-host');
    await _fails(
      store.loadDraft(MailAccountId(account.value, profile: foreign), 'draft'),
      MailProblemCode.permissionDenied,
    );
    await store.close();
    await _fails(
      SqliteMailRepository.open(
        executor: NativeDatabase(file),
        profile: foreign,
      ),
      MailProblemCode.permissionDenied,
    );
    final reopened = await _open(file, profile);
    expect(
      (await _ok(reopened.loadDraft(account, 'draft')))!.body.plainText,
      'Draft text',
    );
  });

  test(
    'profile removal can resume outstanding vault cleanup after reopening',
    () async {
      final (file, profile, account) = await _persistentIdentity();
      var store = await _open(file, profile);
      await _register(store, account);
      await _ok(store.saveDraft(_draft(account), expectedRevision: null));
      await _ok(store.removeProfile());
      await store.close();
      store = await _open(file, profile);
      final cleanup = (await _ok(store.credentialCleanup())).single;
      expect(cleanup.account, account);
      expect(cleanup.reference, 'opaque-vault-reference');
      expect(await _ok(store.listAccounts()), isEmpty);
      await _fails(
        store.loadDraft(account, 'draft'),
        MailProblemCode.unavailable,
      );
      await _fails(
        store.createAccount(
          MailStoreAccount(
            id: MailAccountId('new', profile: profile),
            provider: MailProviderKind.imap,
            displayName: 'Retired profile cannot be reactivated',
          ),
        ),
        MailProblemCode.unavailable,
      );
      await _ok(store.acknowledgeCredentialCleanup(cleanup));
      await store.close();
      store = await _open(file, profile);
      expect(await _ok(store.credentialCleanup()), isEmpty);
    },
  );

  test(
    'oversized provider identity is rejected before writing its cursor',
    () async {
      final profile = MailProfileId('identity', hostId: 'independent-tests');
      final store = await _ok(
        SqliteMailRepository.open(
          executor: NativeDatabase.memory(),
          profile: profile,
        ),
      );
      addTearDown(store.close);
      final account = MailAccountId('account', profile: profile);
      await _ok(
        store.createAccount(
          MailStoreAccount(
            id: account,
            provider: MailProviderKind.gmail,
            displayName: 'Synthetic',
          ),
        ),
      );
      final mailbox = MailMailboxId('inbox', account: account);
      await _fails(
        store.commitSyncPage(
          MailSyncPage(
            mailbox: mailbox,
            upserts: [
              MailHeaderRecord(
                id: MailMessageId('local'),
                remote: MailOpaqueIdentity(
                  account: account,
                  provider: MailProviderKind.gmail,
                  value: 'x' * 1025,
                ),
                envelope: MailEnvelope(subject: 'Small envelope'),
              ),
            ],
            tombstones: const [],
            hasMore: false,
            next: MailCursor(mailbox: mailbox, value: 'must-not-persist'),
          ),
          expectedCursor: null,
          lease: MailAccountSession(account).begin(),
        ),
        MailProblemCode.invalidInput,
      );
      expect(await _ok(store.readCursor(mailbox)), isNull);
      expect(await _ok(store.listHeaders(mailbox)), isEmpty);
    },
  );

  test(
    'tombstone-only pages consume account quota and roll back their cursor',
    () async {
      final profile = MailProfileId(
        'bounded-journal',
        hostId: 'independent-tests',
      );
      final store = await _ok(
        SqliteMailRepository.open(
          executor: NativeDatabase.memory(),
          profile: profile,
          limits: const MailStoreLimits(maxAccountBytes: 4096),
        ),
      );
      addTearDown(store.close);
      final account = MailAccountId('account', profile: profile);
      await _ok(
        store.createAccount(
          MailStoreAccount(
            id: account,
            provider: MailProviderKind.gmail,
            displayName: 'Synthetic',
          ),
        ),
      );
      final mailbox = MailMailboxId('inbox', account: account);
      final session = MailAccountSession(account);
      MailCursor? previous;
      var rejected = false;
      for (var i = 0; i < 40; i++) {
        final next = MailCursor(mailbox: mailbox, value: 'cursor-$i');
        final result = await store.commitSyncPage(
          MailSyncPage(
            mailbox: mailbox,
            upserts: const [],
            tombstones: [
              MailOpaqueIdentity(
                account: account,
                provider: MailProviderKind.gmail,
                value: 'remote-$i-${'x' * 128}',
              ),
            ],
            next: next,
            hasMore: false,
          ),
          expectedCursor: previous,
          lease: session.begin(),
        );
        if (result case MailFailure<MailUnit>(:final problem)) {
          expect(problem.code, MailProblemCode.quotaExceeded);
          rejected = true;
          break;
        }
        expect(result, isA<MailSuccess<MailUnit>>());
        previous = next;
      }
      expect(rejected, isTrue);
      expect(previous, isNotNull);
      expect((await _ok(store.readCursor(mailbox)))?.value, previous!.value);
      expect(await _ok(store.listHeaders(mailbox)), isEmpty);
    },
  );

  test(
    'foreign-profile logout is a typed rejection without invalidating either session',
    () async {
      final f = await _fixture();
      final foreignProfile = MailProfileId(
        f.account.profile.value,
        hostId: 'foreign-host',
      );
      final foreignSession = MailAccountSession(
        MailAccountId(f.account.value, profile: foreignProfile),
      );
      final foreignLease = foreignSession.begin();
      final localLease = f.session.begin();
      await _fails(
        f.store.logout(foreignSession),
        MailProblemCode.permissionDenied,
      );
      expect(foreignLease.isCurrent, isTrue);
      expect(localLease.isCurrent, isTrue);
      expect(
        (await _ok(f.store.listAccounts())).single.state,
        MailStoredAccountState.active,
      );
      await _ok(f.commit(f.page('one', headers: [f.header('one')])));
    },
  );
}
