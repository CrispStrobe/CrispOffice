@TestOn('vm')
library;

import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:test/test.dart';

final _profile = MailProfileId('cleanup', hostId: 'test-office');
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

MailMailbox _box(String id, {MailAccountId? account}) => MailMailbox(
  id: MailMailboxId(id, account: account ?? _account),
  displayName: id,
);

MailHeaderRecord _header(int uid, MailMailbox box) => MailHeaderRecord(
  id: MailMessageId('${box.id.value}-$uid'),
  remote: MailImapIdentity(mailbox: box.id, uidValidity: 1, uid: uid),
  envelope: MailEnvelope(subject: 'Subject $uid'),
);

MailMessage _message(
  MailHeaderRecord header, {
  int rawSize = 64,
  String? text,
}) => MailMessage(
  raw: MailBytes(
    Uint8List.fromList(List.filled(rawSize, header.id.value.length)),
  ),
  envelope: header.envelope,
  body: MailBody(plainText: text ?? 'Cached ${header.id.value}'),
  localId: header.id,
  remoteIdentity: header.remote,
);

void main() {
  late Directory directory;
  late File file;
  late SqliteMailRepository store;
  late MailAccountSession session;
  var failCommit = false;

  Future<SqliteMailRepository> open({
    MailStoreLimits limits = const MailStoreLimits(),
  }) async => _value(
    await SqliteMailRepository.open(
      executor: NativeDatabase(file),
      profile: _profile,
      limits: limits,
      clock: () => _now,
      faultInjector: (point) {
        if (failCommit && point == MailStoreCheckpoint.beforeCommit) {
          throw const MailStoreStorageException(MailProblemCode.storageFailure);
        }
      },
    ),
  );

  Future<void> create(MailAccountId account) async {
    _value(
      await store.createAccount(
        MailStoreAccount(
          id: account,
          provider: MailProviderKind.imap,
          displayName: account.value,
          credentialReference: 'vault-${account.value}',
        ),
      ),
    );
  }

  Future<MailCachedMailboxView> save(
    MailMailbox box,
    List<MailHeaderRecord> headers, {
    int? revision,
  }) async => _value(
    await store.saveMailboxView(
      box,
      headers,
      expectedRevision: revision,
      hasMore: false,
      lease: MailAccountSession(box.id.account).begin(),
    ),
  );

  Future<void> cache(MailHeaderRecord header, {MailMessage? message}) async {
    _value(
      await store.cacheMessage(
        header.remote.account,
        header.id,
        message ?? _message(header),
      ),
    );
  }

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    directory = await Directory.systemTemp.createTemp('quds-cache-cleanup-');
    file = File('${directory.path}/mail.sqlite');
    failCommit = false;
    session = MailAccountSession(_account);
    store = await open();
    await create(_account);
  });
  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });

  test(
    'explicit cleanup frees automatic-cache quota for an exact saved draft',
    () async {
      await store.close();
      store = await open(limits: const MailStoreLimits(maxAccountBytes: 16384));
      final box = _box('inbox');
      final header = _header(1, box);
      await save(box, [header]);
      await cache(
        header,
        message: _message(header, rawSize: 8000, text: 'b' * 1000),
      );
      final draft = MailDraft(
        id: 'work',
        account: _account,
        revision: 0,
        envelope: MailEnvelope(subject: 'Unfinished'),
        body: MailBody(plainText: 'c' * 5000),
      );
      _problem(
        await store.saveDraft(draft, expectedRevision: null),
        MailProblemCode.quotaExceeded,
      );
      final report = _value(await store.clearMailboxCache(_account));
      expect(report.removedViews, 1);
      expect(report.evictedBodies, 1);
      expect(report.removedHeaders, 1);
      expect(report.retainedBodies, 0);
      expect(report.hasMore, isFalse);
      _value(await store.saveDraft(draft, expectedRevision: null));
      await store.close();
      store = await open(limits: const MailStoreLimits(maxAccountBytes: 16384));
      expect(
        _value(await store.loadDraft(_account, 'work'))!.body.plainText,
        draft.body.plainText,
      );
      expect(_value(await store.listMailboxViews(_account)), isEmpty);
      expect(
        _value(await store.loadCachedMessage(_account, header.id)),
        isNull,
      );
    },
  );

  test(
    'cleanup works after reopening below the already stored account quota',
    () async {
      final box = _box('inbox');
      final header = _header(1, box);
      await save(box, [header]);
      await cache(header);
      await store.close();
      store = await open(limits: const MailStoreLimits(maxAccountBytes: 1));
      final report = _value(await store.clearMailboxCache(_account));
      expect(report.evictedBodies, 1);
      expect(report.removedHeaders, 1);
      expect(report.hasMore, isFalse);
    },
  );

  test(
    'bounded batches report remaining eligible work and finish idempotently',
    () async {
      for (var i = 0; i < 3; i++) {
        final box = _box('folder-$i');
        final header = _header(i + 1, box);
        await save(box, [header]);
        await cache(header);
      }
      for (var i = 0; i < 3; i++) {
        final report = _value(
          await store.clearMailboxCache(_account, limit: 1),
        );
        expect(report.removedViews, 1);
        expect(report.evictedBodies, 1);
        expect(report.removedHeaders, 1);
        expect(report.hasMore, i != 2);
      }
      final report = _value(await store.clearMailboxCache(_account, limit: 1));
      expect(
        report.removedViews +
            report.evictedBodies +
            report.removedHeaders +
            report.retainedBodies,
        0,
      );
      expect(report.hasMore, isFalse);
    },
  );

  test(
    'sync, active commands, editor pins, outgoing bytes and other accounts survive',
    () async {
      final box = _box('inbox');
      final headers = [for (var i = 1; i <= 6; i++) _header(i, box)];
      await save(box, headers);
      for (final header in headers) {
        // Distinct bytes ensure a pin protects exactly one cache row.
        await cache(
          header,
          message: _message(header, rawSize: 64 + headers.indexOf(header)),
        );
      }
      final cursor = MailCursor(mailbox: box.id, value: 'retained-cursor');
      _value(
        await store.commitSyncPage(
          MailSyncPage(
            mailbox: box.id,
            upserts: [headers[0]],
            tombstones: const [],
            next: cursor,
            hasMore: false,
          ),
          expectedCursor: null,
          lease: session.begin(),
        ),
      );
      for (var i = 1; i <= 3; i++) {
        _value(
          await store.enqueueOperation(
            MailDelete(id: 'operation-$i', message: headers[i].remote),
            session.begin(),
          ),
        );
        if (i >= 2) {
          _value(
            await store.transitionOperation(
              _account,
              'operation-$i',
              expectedRevision: 0,
              state: MailPendingState.applying,
              lease: session.begin(),
            ),
          );
        }
        if (i == 3) {
          _value(
            await store.transitionOperation(
              _account,
              'operation-$i',
              expectedRevision: 1,
              state: MailPendingState.reconcile,
              lease: session.begin(),
            ),
          );
        }
      }
      final pinnedMessage = _value(
        await store.loadCachedMessage(_account, headers[4].id),
      )!;
      final pin = _value(
        await store.pinBlob(
          _account,
          pinId: 'open-editor',
          bytes: pinnedMessage.raw,
        ),
      );
      final shared = _value(
        await store.loadCachedMessage(_account, headers[5].id),
      )!.raw;
      final draft = MailDraft(
        id: 'draft',
        account: _account,
        revision: 0,
        envelope: MailEnvelope(subject: 'Unsent draft'),
        body: const MailBody(plainText: 'Keep me'),
        attachments: [
          MailAttachment(
            partPath: '2',
            mediaType: 'application/octet-stream',
            displayName: 'shared.bin',
            content: shared,
          ),
        ],
      );
      _value(await store.saveDraft(draft, expectedRevision: null));
      final outbox = MailOutboxEntry.queued(
        id: 'outbox',
        now: _now,
        prepared: MailPreparedMessage(
          account: _account,
          draftId: 'draft',
          draftRevision: 0,
          wire: shared,
          envelope: MailTransportEnvelope(
            sender: 'sender@example.test',
            recipients: ['recipient@example.test'],
          ),
        ),
      );
      _value(
        await store.saveOutbox(
          outbox,
          expectedState: null,
          expectedAttemptId: null,
        ),
      );
      final other = MailAccountId('other', profile: _profile);
      await create(other);
      final otherBox = _box('inbox', account: other);
      final otherHeader = _header(9, otherBox);
      await save(otherBox, [otherHeader]);
      await cache(otherHeader);
      final beforeOperations = _value(await store.pendingOperations(_account));
      final report = _value(await store.clearMailboxCache(_account));
      expect(report.removedViews, 1);
      expect(report.evictedBodies, 5);
      expect(report.removedHeaders, 1);
      expect(report.retainedBodies, 1);
      expect(report.hasMore, isFalse);
      final retainedCursor = _value(await store.readCursor(box.id))!;
      expect(retainedCursor.mailbox, cursor.mailbox);
      expect(retainedCursor.value, cursor.value);
      expect(_value(await store.listHeaders(box.id)).single.id, headers[0].id);
      expect(
        _value(
          await store.pendingOperations(_account),
        ).map((p) => (p.operation.id, p.revision, p.state)),
        beforeOperations.map((p) => (p.operation.id, p.revision, p.state)),
      );
      expect(
        _value(
          await store.loadCachedMessage(_account, headers[4].id),
        )!.raw.sha256,
        pinnedMessage.raw.sha256,
      );
      expect(
        _value(
          await store.loadDraft(_account, 'draft'),
        )!.attachments.single.content.sha256,
        shared.sha256,
      );
      expect(
        _value(await store.recoverOutbox(_account)).single.prepared.wireHash,
        shared.sha256,
      );
      expect(
        _value(
          await store.listAccounts(),
        ).firstWhere((a) => a.id == _account).credentialReference,
        'vault-account',
      );
      expect(_value(await store.listMailboxViews(other)), hasLength(1));
      expect(
        _value(await store.loadCachedMessage(other, otherHeader.id)),
        isNotNull,
      );
      _value(await store.releasePin(pin));
      final finalReport = _value(await store.clearMailboxCache(_account));
      expect(finalReport.evictedBodies, 1);
      expect(finalReport.removedHeaders, 1);
      expect(finalReport.retainedBodies, 0);
      expect(finalReport.hasMore, isFalse);
      expect(_value(await store.search(_account, 'Subject')), hasLength(4));
    },
  );

  test(
    'remaining browse references protect headers until their own batch',
    () async {
      final first = _box('a');
      final later = _box('z');
      await save(first, []);
      final header = _header(1, later);
      await save(later, [header]);
      await cache(header);
      final firstReport = _value(
        await store.clearMailboxCache(_account, limit: 1),
      );
      expect(firstReport.removedViews, 1);
      expect(firstReport.evictedBodies, 1);
      expect(firstReport.removedHeaders, 0);
      expect(firstReport.retainedBodies, 0);
      expect(firstReport.hasMore, isTrue);
      expect(
        _value(await store.loadMailboxView(later.id))!.headers.single.id,
        header.id,
      );
      final last = _value(await store.clearMailboxCache(_account, limit: 1));
      expect(last.removedHeaders, 1);
      expect(last.hasMore, isFalse);
    },
  );

  test(
    'failed cleanup rolls back view, bytes, search and references together',
    () async {
      final box = _box('inbox');
      final header = _header(1, box);
      final view = await save(box, [header]);
      await cache(header);
      final bytes = _value(
        await store.loadCachedMessage(_account, header.id),
      )!.raw;
      failCommit = true;
      _problem(
        await store.clearMailboxCache(_account),
        MailProblemCode.storageFailure,
      );
      failCommit = false;
      await store.close();
      store = await open();
      expect(
        _value(await store.loadMailboxView(box.id))!.revision,
        view.revision,
      );
      expect(
        _value(await store.loadCachedMessage(_account, header.id))!.raw.sha256,
        bytes.sha256,
      );
      expect(_value(await store.search(_account, 'Cached')), hasLength(1));
      expect(_value(await store.clearMailboxCache(_account)).removedHeaders, 1);
    },
  );

  test(
    'cleanup and restart cannot resurrect an old view CAS at the same timestamp',
    () async {
      final box = _box('inbox');
      final first = await save(box, [_header(1, box)]);
      _value(await store.clearMailboxCache(_account));
      await store.close();
      store = await open();
      final replacement = await save(box, [_header(2, box)]);
      expect(replacement.revision, greaterThan(first.revision));
      expect(replacement.capturedAt, first.capturedAt);
      _problem(
        await store.saveMailboxView(
          box,
          [_header(3, box)],
          expectedRevision: first.revision,
          hasMore: false,
          lease: session.begin(),
        ),
        MailProblemCode.conflict,
      );
      expect(
        _value(await store.loadMailboxView(box.id))!.headers.single.id,
        _header(2, box).id,
      );
    },
  );

  test(
    'global revision exhaustion prevents new and cleared folder reuse',
    () async {
      final box = _box('inbox');
      await save(box, []);
      _value(await store.clearMailboxCache(_account));
      await store.close();
      final database = sqlite.sqlite3.open(file.path);
      database.execute(
        'UPDATE store_profile SET mailbox_view_revision=9007199254740991',
      );
      database.close();
      store = await open();
      _problem(
        await store.saveMailboxView(
          box,
          [],
          expectedRevision: null,
          hasMore: false,
          lease: session.begin(),
        ),
        MailProblemCode.quotaExceeded,
      );
      expect(_value(await store.listMailboxViews(_account)), isEmpty);
    },
  );

  test(
    'cleanup accepts logged-out accounts and rejects wrong scope and invalid bounds',
    () async {
      final box = _box('inbox');
      await save(box, [_header(1, box)]);
      for (final limit in [-1, 0, 1001]) {
        _problem(
          await store.clearMailboxCache(_account, limit: limit),
          MailProblemCode.invalidInput,
        );
      }
      _problem(
        await store.clearMailboxCache(
          MailAccountId(
            'account',
            profile: MailProfileId('foreign', hostId: 'test-office'),
          ),
        ),
        MailProblemCode.permissionDenied,
      );
      expect(_value(await store.listMailboxViews(_account)), hasLength(1));
      _value(await store.logout(session));
      expect(_value(await store.clearMailboxCache(_account)).removedViews, 1);
      expect(
        _value(await store.credentialCleanup()).single.reference,
        'vault-account',
      );
    },
  );
}
