@TestOn('vm')
library;

import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:test/test.dart';

final _profile = MailProfileId('views', hostId: 'test-office');
final _account = MailAccountId('account', profile: _profile);
final _box = MailMailbox(
  id: MailMailboxId('inbox', account: _account),
  displayName: 'Posteingang · البريد الوارد',
);
final _now = DateTime.utc(2026, 11, 20, 18);

T _value<T>(MailResult<T> result) {
  expect(result, isA<MailSuccess<T>>());
  return (result as MailSuccess<T>).value;
}

void _problem<T>(MailResult<T> result, MailProblemCode code) {
  expect(result, isA<MailFailure<T>>());
  expect((result as MailFailure<T>).problem.code, code);
}

MailHeaderRecord _header(
  int uid, {
  MailMailbox? mailbox,
  int validity = 7,
  String? id,
  String? subject,
  MailMessageFlags? flags,
}) => MailHeaderRecord(
  id: MailMessageId(id ?? 'message-$validity-$uid'),
  remote: MailImapIdentity(
    mailbox: (mailbox ?? _box).id,
    uidValidity: validity,
    uid: uid,
  ),
  envelope: MailEnvelope(subject: subject ?? 'Subject $uid'),
  flags: flags,
);

MailMessage _message(
  MailHeaderRecord header, {
  String body = 'retained body',
}) => MailMessage(
  raw: MailBytes(Uint8List.fromList('Subject: source\r\n\r\n$body'.codeUnits)),
  envelope: header.envelope,
  body: MailBody(plainText: body),
  localId: header.id,
  remoteIdentity: header.remote,
  attachments: [
    MailAttachment(
      partPath: '2',
      mediaType: 'application/octet-stream',
      displayName: 'retained.bin',
      content: MailBytes(Uint8List.fromList([0, 255, 1, 254])),
    ),
  ],
);

final class _ReadProbe extends QueryInterceptor {
  bool bodyRead = false;
  bool oversizedTextTransferred = false;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    bodyRead |=
        statement.contains('SELECT b.hash,b.data') ||
        statement.contains('SELECT data FROM cached_messages');
    final result = await super.runSelect(executor, statement, args);
    oversizedTextTransferred |= result.any(
      (row) =>
          row.values.any((value) => value is String && value.length > 32768),
    );
    return result;
  }
}

void main() {
  late Directory directory;
  late File file;
  late SqliteMailRepository store;
  late MailAccountSession session;
  late _ReadProbe probe;
  var failCommit = false;
  var invalidateCommit = false;
  var now = _now;

  Future<SqliteMailRepository> open({
    MailStoreLimits limits = const MailStoreLimits(),
  }) async => _value(
    await SqliteMailRepository.open(
      executor: NativeDatabase(file).interceptWith(probe),
      profile: _profile,
      limits: limits,
      clock: () => now,
      faultInjector: (point) {
        if (point == MailStoreCheckpoint.beforeCommit) {
          if (invalidateCommit) session.invalidate();
          if (failCommit) {
            throw const MailStoreStorageException(
              MailProblemCode.storageFailure,
            );
          }
        }
      },
    ),
  );

  Future<MailResult<MailCachedMailboxView>> save(
    List<MailHeaderRecord> headers, {
    MailMailbox? mailbox,
    int? revision,
    bool more = false,
    MailOperationLease? lease,
  }) => store.saveMailboxView(
    mailbox ?? _box,
    headers,
    expectedRevision: revision,
    hasMore: more,
    lease: lease ?? session.begin(),
  );

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    directory = await Directory.systemTemp.createTemp('quds-mail-views-');
    file = File('${directory.path}/mail.sqlite3');
    session = MailAccountSession(_account);
    probe = _ReadProbe();
    failCommit = false;
    invalidateCommit = false;
    now = _now;
    store = await open();
    _value(
      await store.createAccount(
        MailStoreAccount(
          id: _account,
          provider: MailProviderKind.imap,
          displayName: 'View account',
        ),
      ),
    );
  });
  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });

  test(
    'ordered window, scope, timestamp and exact cached bytes survive reopen',
    () async {
      final input = [_header(9), _header(3), _header(8)];
      final saving = save(input, more: true);
      input.clear();
      final view = _value(await saving);
      expect(view.headers.map((header) => header.id.value), [
        'message-7-9',
        'message-7-3',
        'message-7-8',
      ]);
      expect(view.mailbox.displayName, _box.displayName);
      expect(view.capturedAt, _now);
      expect(view.revision, 1);
      expect(view.hasMore, isTrue);
      expect(() => view.headers.clear(), throwsUnsupportedError);
      final message = _message(view.headers.first);
      _value(
        await store.cacheMessage(
          _account,
          view.headers.first.id,
          message,
          lease: session.begin(),
        ),
      );
      await store.close();
      store = await open();
      final restored = _value(await store.loadMailboxView(_box.id))!;
      expect(
        restored.headers.map((header) => header.remote),
        view.headers.map((header) => header.remote),
      );
      expect(restored.capturedAt, _now);
      expect(restored.hasMore, isTrue);
      final cached = _value(
        await store.loadCachedMessage(_account, view.headers.first.id),
      )!;
      expect(cached.raw.bytes, message.raw.bytes);
      expect(
        cached.attachments.single.content.bytes,
        message.attachments.single.content.bytes,
      );
      expect(
        _value(await store.loadCachedMessage(_account, view.headers.last.id)),
        isNull,
      );
    },
  );

  test(
    'absent view differs from saved empty folder and empty saves advance revision',
    () async {
      expect(_value(await store.loadMailboxView(_box.id)), isNull);
      expect(_value(await store.listMailboxViews(_account)), isEmpty);
      final first = _value(await save([]));
      final second = _value(await save([], revision: first.revision));
      expect(second.revision, 2);
      expect(second.headers, isEmpty);
      expect(second.hasMore, isFalse);
      expect(
        _value(await store.listMailboxViews(_account)).single.headerCount,
        0,
      );
      _problem(
        await save([], revision: first.revision),
        MailProblemCode.conflict,
      );
    },
  );

  test(
    'folder summaries are bounded and do not read headers or bodies',
    () async {
      final first = _value(await save([_header(1)]));
      _value(
        await store.cacheMessage(
          _account,
          first.headers.single.id,
          _message(first.headers.single),
        ),
      );
      now = _now.add(const Duration(minutes: 1));
      final other = MailMailbox(
        id: MailMailboxId('archive', account: _account),
        displayName: 'Archive',
      );
      _value(await save([], mailbox: other));
      probe.bodyRead = false;
      final summaries = _value(await store.listMailboxViews(_account));
      expect(summaries.map((row) => row.mailbox.id), [other.id, _box.id]);
      expect(summaries.map((row) => row.headerCount), [0, 1]);
      expect(probe.bodyRead, isFalse);
      expect(() => summaries.clear(), throwsUnsupportedError);
      _problem(
        await store.listMailboxViews(_account, limit: 1),
        MailProblemCode.quotaExceeded,
      );
      for (final limit in [0, 1001]) {
        _problem(
          await store.listMailboxViews(_account, limit: limit),
          MailProblemCode.invalidInput,
        );
      }
    },
  );

  test(
    'browse windows never advance sync cursors or erase authoritative membership',
    () async {
      final page = MailSyncPage(
        mailbox: _box.id,
        upserts: [_header(1), _header(2)],
        tombstones: [],
        next: MailCursor(mailbox: _box.id, value: 'provider-sync-cursor'),
        hasMore: true,
      );
      _value(
        await store.commitSyncPage(
          page,
          expectedCursor: null,
          lease: session.begin(),
        ),
      );
      final saved = _value(await save([_header(3)]));
      expect(
        _value(
          await store.listHeaders(_box.id),
        ).map((header) => header.id.value),
        ['message-7-1', 'message-7-2'],
      );
      expect(
        _value(await store.readCursor(_box.id))!.value,
        'provider-sync-cursor',
      );
      _value(await save([], revision: saved.revision));
      expect(_value(await store.listHeaders(_box.id)), hasLength(2));
      expect(
        _value(await store.readCursor(_box.id))!.value,
        'provider-sync-cursor',
      );
    },
  );

  test(
    'live browse references retain cache when sync prunes missing membership',
    () async {
      final view = _value(await save([_header(1)]));
      final message = _message(view.headers.single);
      _value(
        await store.cacheMessage(_account, view.headers.single.id, message),
      );
      _value(
        await store.commitSyncPage(
          MailSyncPage(
            mailbox: _box.id,
            upserts: [],
            tombstones: [view.headers.single.remote],
            next: MailCursor(mailbox: _box.id, value: 'deleted-on-server'),
            hasMore: false,
          ),
          expectedCursor: null,
          lease: session.begin(),
        ),
      );
      expect(_value(await store.listHeaders(_box.id)), isEmpty);
      expect(
        _value(await store.loadMailboxView(_box.id))!.headers.single.remote,
        view.headers.single.remote,
      );
      expect(
        _value(
          await store.loadCachedMessage(_account, view.headers.single.id),
        )!.raw.sha256,
        message.raw.sha256,
      );
    },
  );

  test(
    'unknown flags preserve the last complete observation without inventing flags',
    () async {
      const flags = MailMessageFlags(isRead: true, isFlagged: true);
      final first = _value(await save([_header(1, flags: flags), _header(2)]));
      final second = _value(
        await save([_header(1), _header(2)], revision: first.revision),
      );
      expect(second.headers.first.flags, flags);
      expect(second.headers.last.flags, isNull);
      final third = _value(
        await save([
          _header(1, flags: const MailMessageFlags()),
        ], revision: second.revision),
      );
      expect(third.headers.single.flags, const MailMessageFlags());
    },
  );

  test(
    'stale or unversioned replacements fail without changing the view',
    () async {
      final first = _value(await save([_header(1)]));
      _problem(await save([_header(2)]), MailProblemCode.conflict);
      _problem(await save([_header(2)], revision: 2), MailProblemCode.conflict);
      for (final revision in [0, -1, 9007199254740992]) {
        _problem(
          await save([_header(2)], revision: revision),
          MailProblemCode.invalidInput,
        );
      }
      final current = _value(await store.loadMailboxView(_box.id))!;
      expect(current.revision, first.revision);
      expect(current.headers.single.id, first.headers.single.id);
    },
  );

  test(
    'storage failure rolls back headers, order, revision and folder name',
    () async {
      final first = _value(await save([_header(1)]));
      failCommit = true;
      _problem(
        await save(
          [_header(2)],
          revision: first.revision,
          mailbox: MailMailbox(id: _box.id, displayName: 'Changed'),
        ),
        MailProblemCode.storageFailure,
      );
      failCommit = false;
      final retained = _value(await store.loadMailboxView(_box.id))!;
      expect(retained.mailbox.displayName, _box.displayName);
      expect(retained.revision, first.revision);
      expect(retained.headers.single.id, first.headers.single.id);
      expect(_value(await store.search(_account, 'Subject 2')), isEmpty);
    },
  );

  test(
    'session invalidation at final commit checkpoint rolls back the whole window',
    () async {
      final first = _value(await save([_header(1)]));
      invalidateCommit = true;
      _problem(
        await save([_header(2)], revision: first.revision),
        MailProblemCode.staleOperation,
      );
      invalidateCommit = false;
      final retained = _value(await store.loadMailboxView(_box.id))!;
      expect(retained.revision, first.revision);
      expect(retained.headers.single.id, first.headers.single.id);
    },
  );

  test('cancelled lease cannot write even an empty view', () async {
    final source = MailCancellationSource();
    final lease = session.begin(cancellation: source.token);
    source.cancel();
    _problem(await save([], lease: lease), MailProblemCode.cancelled);
    expect(_value(await store.loadMailboxView(_box.id)), isNull);
  });

  test('another account lease cannot write a view', () async {
    final other = MailAccountId('other', profile: _profile);
    _problem(
      await save([], lease: MailAccountSession(other).begin()),
      MailProblemCode.invalidInput,
    );
  });

  for (final (name, headers) in <(String, List<MailHeaderRecord>)>[
    ('duplicate id', [_header(1), _header(2, id: 'message-7-1')]),
    ('duplicate remote', [_header(1), _header(1, id: 'different')]),
    ('mixed generations', [_header(1), _header(2, validity: 8)]),
    (
      'different mailbox',
      [
        _header(
          1,
          mailbox: MailMailbox(
            id: MailMailboxId('elsewhere', account: _account),
            displayName: 'Elsewhere',
          ),
        ),
      ],
    ),
  ]) {
    test('invalid $name is refused atomically', () async {
      _problem(await save(headers), MailProblemCode.invalidInput);
      expect(_value(await store.listMailboxViews(_account)), isEmpty);
    });
  }

  test('existing local IDs and remote IDs cannot be retargeted', () async {
    final first = _value(await save([_header(1)]));
    _problem(
      await save([_header(2, id: 'message-7-1')], revision: first.revision),
      MailProblemCode.conflict,
    );
    _problem(
      await save([_header(1, id: 'replacement')], revision: first.revision),
      MailProblemCode.conflict,
    );
    expect(
      _value(await store.loadMailboxView(_box.id))!.headers.single.remote,
      _header(1).remote,
    );
  });

  test(
    'new IMAP generation retains distinct bodies and never rebinds an old body',
    () async {
      final old = _value(await save([_header(1)]));
      _value(
        await store.cacheMessage(
          _account,
          old.headers.single.id,
          _message(old.headers.single),
        ),
      );
      final newer = _value(
        await save([_header(1, validity: 8)], revision: old.revision),
      );
      expect(newer.headers.single.remote, _header(1, validity: 8).remote);
      expect(
        _value(
          await store.loadCachedMessage(_account, newer.headers.single.id),
        ),
        isNull,
      );
      expect(
        _value(await store.loadCachedMessage(_account, old.headers.single.id)),
        isNotNull,
      );
    },
  );

  test('headers and account profiles remain isolated', () async {
    final otherAccount = MailAccountId('other', profile: _profile);
    _value(
      await store.createAccount(
        MailStoreAccount(
          id: otherAccount,
          provider: MailProviderKind.imap,
          displayName: 'Other',
        ),
      ),
    );
    final otherBox = MailMailbox(
      id: MailMailboxId('inbox', account: otherAccount),
      displayName: 'Other inbox',
    );
    _value(await save([_header(1)]));
    _value(
      await save(
        [_header(1, mailbox: otherBox, subject: 'Other subject')],
        mailbox: otherBox,
        lease: MailAccountSession(otherAccount).begin(),
      ),
    );
    expect(
      _value(
        await store.loadMailboxView(_box.id),
      )!.headers.single.envelope.subject,
      'Subject 1',
    );
    expect(
      _value(
        await store.loadMailboxView(otherBox.id),
      )!.headers.single.envelope.subject,
      'Other subject',
    );
    _problem(
      await save([_header(1, mailbox: otherBox)], revision: 1),
      MailProblemCode.invalidInput,
    );
    final foreign = MailAccountId(
      'account',
      profile: MailProfileId('views', hostId: 'another-host'),
    );
    _problem(
      await store.listMailboxViews(foreign),
      MailProblemCode.permissionDenied,
    );
  });

  for (final provider in [
    MailProviderKind.ews,
    MailProviderKind.gmail,
    MailProviderKind.graph,
  ]) {
    test(
      '$provider opaque identity, folder labels and cache survive reopen',
      () async {
        final account = MailAccountId(provider.name, profile: _profile);
        _value(
          await store.createAccount(
            MailStoreAccount(
              id: account,
              provider: provider,
              displayName: provider.name,
            ),
          ),
        );
        final box = MailMailbox(
          id: MailMailboxId('opaque-folder', account: account),
          displayName: 'Folder',
          isLabel: provider == MailProviderKind.gmail,
        );
        final record = MailHeaderRecord(
          id: MailMessageId('stable-message'),
          remote: MailOpaqueIdentity(
            account: account,
            provider: provider,
            value: 'provider-message',
          ),
          envelope: MailEnvelope(subject: 'Cloud message'),
        );
        final first = _value(
          await save(
            [record],
            mailbox: box,
            lease: MailAccountSession(account).begin(),
          ),
        );
        _value(await store.cacheMessage(account, record.id, _message(record)));
        await store.close();
        store = await open();
        final restored = _value(await store.loadMailboxView(box.id))!;
        expect(restored.headers.single.remote, record.remote);
        expect(restored.mailbox.isLabel, first.mailbox.isLabel);
        expect(
          _value(
            await store.loadCachedMessage(account, record.id),
          )!.body.plainText,
          'retained body',
        );
      },
    );
  }

  test('wrong provider identity is refused', () async {
    _problem(
      await save([
        MailHeaderRecord(
          id: MailMessageId('wrong'),
          remote: MailOpaqueIdentity(
            account: _account,
            provider: MailProviderKind.ews,
            value: 'remote',
          ),
          envelope: MailEnvelope(),
        ),
      ]),
      MailProblemCode.invalidInput,
    );
  });

  test('header and metadata limits reject the whole new view', () async {
    _problem(
      await save(List.generate(1001, (index) => _header(index + 1))),
      MailProblemCode.quotaExceeded,
    );
    _problem(
      await save([_header(1, subject: 'x' * (2 * 1024 * 1024 + 1))]),
      MailProblemCode.quotaExceeded,
    );
    expect(_value(await store.listMailboxViews(_account)), isEmpty);
  });

  test(
    'the complete 1000-header boundary preserves every row in order',
    () async {
      final headers = List.generate(1000, (index) => _header(1000 - index));
      final view = _value(await save(headers, more: true));
      expect(
        view.headers.map((header) => header.id),
        headers.map((header) => header.id),
      );
      expect(
        _value(await store.listMailboxViews(_account)).single.headerCount,
        1000,
      );
      final restored = _value(await store.loadMailboxView(_box.id))!;
      expect(
        restored.headers.map((header) => header.id),
        headers.map((header) => header.id),
      );
    },
  );

  test(
    'folder capacity refuses new entries but permits existing refresh',
    () async {
      await store.close();
      final database = sqlite.sqlite3.open(file.path);
      database.execute('BEGIN');
      for (var i = 0; i < 1000; i++) {
        database.execute(
          'INSERT INTO mailboxes(account,id,display_name) VALUES(?,?,?)',
          [_account.value, 'folder-$i', 'Folder $i'],
        );
        database.execute(
          'INSERT INTO mailbox_views(account,mailbox,revision,captured_at,header_count,has_more) '
          'VALUES(?,?,1,0,0,0)',
          [_account.value, 'folder-$i'],
        );
      }
      database.execute('COMMIT');
      database.close();
      store = await open();
      expect(_value(await store.listMailboxViews(_account)), hasLength(1000));
      _problem(await save([]), MailProblemCode.quotaExceeded);
      final updated = _value(
        await save(
          [],
          revision: 1,
          mailbox: MailMailbox(
            id: MailMailboxId('folder-0', account: _account),
            displayName: 'Refreshed',
          ),
        ),
      );
      expect(updated.revision, 2);
      expect(updated.mailbox.displayName, 'Refreshed');
      expect(_value(await store.listMailboxViews(_account)), hasLength(1000));
    },
  );

  test(
    'refreshing and clearing a browse window preserve drafts and frozen Outbox bytes',
    () async {
      final draft = MailDraft(
        id: 'retained-draft',
        account: _account,
        revision: 0,
        envelope: MailEnvelope(subject: 'Unsent work'),
        body: const MailBody(plainText: 'Do not lose'),
      );
      _value(await store.saveDraft(draft, expectedRevision: null));
      final queued = MailOutboxEntry.queued(
        id: 'retained-outbox',
        prepared: MailPreparedMessage(
          account: _account,
          draftId: draft.id,
          draftRevision: 0,
          wire: MailBytes(Uint8List.fromList([0, 255, 2, 254])),
          envelope: MailTransportEnvelope(
            sender: 'a@example.test',
            recipients: ['b@example.test'],
          ),
        ),
        now: _now,
      );
      _value(
        await store.saveOutbox(
          queued,
          expectedState: null,
          expectedAttemptId: null,
        ),
      );
      final view = _value(await save([_header(1)]));
      _value(await save([], revision: view.revision));
      expect(
        _value(await store.loadDraft(_account, draft.id))!.body.plainText,
        'Do not lose',
      );
      expect(
        _value(await store.recoverOutbox(_account)).single.prepared.wire.bytes,
        queued.prepared.wire.bytes,
      );
    },
  );

  test(
    'concurrent saves with the same revision admit only one replacement',
    () async {
      final first = _value(await save([_header(1)]));
      final results = await Future.wait([
        save([_header(2)], revision: first.revision),
        save([_header(3)], revision: first.revision),
      ]);
      expect(
        results.whereType<MailSuccess<MailCachedMailboxView>>(),
        hasLength(1),
      );
      final failure = results
          .whereType<MailFailure<MailCachedMailboxView>>()
          .single;
      expect(failure.problem.code, MailProblemCode.conflict);
      expect(
        _value(await store.loadMailboxView(_box.id))!.revision,
        first.revision + 1,
      );
    },
  );

  test(
    'a lower reopened page limit rejects old view without truncating or losing it',
    () async {
      _value(await save([_header(1), _header(2)]));
      await store.close();
      store = await open(limits: const MailStoreLimits(maxPageSize: 1));
      _problem(
        await store.loadMailboxView(_box.id),
        MailProblemCode.quotaExceeded,
      );
      _problem(
        await save([_header(1), _header(2)], revision: 1),
        MailProblemCode.quotaExceeded,
      );
      expect(
        _value(await store.listMailboxViews(_account)).single.headerCount,
        2,
      );
      await store.close();
      store = await open();
      expect(
        _value(await store.loadMailboxView(_box.id))!.headers,
        hasLength(2),
      );
    },
  );

  test('lowered account quota rolls back an attempted replacement', () async {
    final first = _value(await save([_header(1)]));
    await store.close();
    store = await open(limits: const MailStoreLimits(maxAccountBytes: 300));
    _problem(
      await save([_header(2)], revision: first.revision),
      MailProblemCode.quotaExceeded,
    );
    expect(
      _value(await store.loadMailboxView(_box.id))!.headers.single.id,
      first.headers.single.id,
    );
  });

  test(
    'lowered metadata budget rejects even an empty saved folder explicitly',
    () async {
      _value(await save([]));
      await store.close();
      store = await open(
        limits: const MailStoreLimits(maxMetadataCodeUnits: 1),
      );
      _problem(
        await store.loadMailboxView(_box.id),
        MailProblemCode.quotaExceeded,
      );
      _problem(
        await store.listMailboxViews(_account),
        MailProblemCode.quotaExceeded,
      );
    },
  );

  test(
    'cached body save invalidated at commit preserves prior bytes',
    () async {
      final view = _value(await save([_header(1)]));
      final header = view.headers.single;
      final original = _message(header);
      _value(await store.cacheMessage(_account, header.id, original));
      invalidateCommit = true;
      _problem(
        await store.cacheMessage(
          _account,
          header.id,
          _message(header, body: 'replacement'),
          lease: session.begin(),
        ),
        MailProblemCode.staleOperation,
      );
      invalidateCommit = false;
      expect(
        _value(await store.loadCachedMessage(_account, header.id))!.raw.sha256,
        original.raw.sha256,
      );
    },
  );

  test(
    'cached body save rejects a foreign lease and mismatched message identity',
    () async {
      final view = _value(await save([_header(1)]));
      _problem(
        await store.cacheMessage(
          _account,
          view.headers.single.id,
          _message(view.headers.single),
          lease: MailAccountSession(
            MailAccountId('other', profile: _profile),
          ).begin(),
        ),
        MailProblemCode.invalidInput,
      );
      _problem(
        await store.cacheMessage(
          _account,
          view.headers.single.id,
          _message(_header(2)),
          lease: session.begin(),
        ),
        MailProblemCode.invalidInput,
      );
      expect(
        _value(await store.loadCachedMessage(_account, view.headers.single.id)),
        isNull,
      );
    },
  );

  test(
    'account removal releases view references and retains retired identity',
    () async {
      final view = _value(await save([_header(1)]));
      _value(
        await store.cacheMessage(
          _account,
          view.headers.single.id,
          _message(view.headers.single),
        ),
      );
      _value(await store.removeLocalAccount(_account));
      _problem(
        await store.listMailboxViews(_account),
        MailProblemCode.unavailable,
      );
      _problem(
        await store.createAccount(
          MailStoreAccount(
            id: _account,
            provider: MailProviderKind.imap,
            displayName: 'Cannot reuse',
          ),
        ),
        MailProblemCode.conflict,
      );
      await store.close();
      final database = sqlite.sqlite3.open(file.path);
      try {
        expect(database.select('SELECT * FROM mailbox_views'), isEmpty);
        expect(database.select('SELECT * FROM mailbox_view_members'), isEmpty);
        expect(database.select('SELECT * FROM blobs'), isEmpty);
        expect(database.select('PRAGMA foreign_key_check'), isEmpty);
      } finally {
        database.close();
      }
      store = await open();
    },
  );

  for (final (name, mutation, code)
      in <(String, void Function(sqlite.Database), MailProblemCode)>[
        (
          'oversized folder name',
          (database) => database.execute(
            'UPDATE mailboxes SET display_name=?',
            ['x' * 100000],
          ),
          MailProblemCode.storageFailure,
        ),
        (
          'oversized header',
          (database) => database.execute('UPDATE messages SET envelope=?', [
            'x' * (9 * 1024 * 1024),
          ]),
          MailProblemCode.quotaExceeded,
        ),
        (
          'missing ordered row',
          (database) => database.execute('DELETE FROM mailbox_view_members'),
          MailProblemCode.storageFailure,
        ),
        (
          'noncontiguous order',
          (database) =>
              database.execute('UPDATE mailbox_view_members SET position=2'),
          MailProblemCode.storageFailure,
        ),
      ]) {
    test('corrupt $name fails before oversized text transfer', () async {
      _value(await save([_header(1)]));
      await store.close();
      final database = sqlite.sqlite3.open(file.path);
      mutation(database);
      database.close();
      store = await open();
      probe.oversizedTextTransferred = false;
      _problem(await store.loadMailboxView(_box.id), code);
      expect(probe.oversizedTextTransferred, isFalse);
    });
  }

  test(
    'revision exhaustion never wraps a stale confirmation into validity',
    () async {
      _value(await save([]));
      await store.close();
      final database = sqlite.sqlite3.open(file.path);
      database.execute('UPDATE mailbox_views SET revision=9007199254740991');
      database.close();
      store = await open();
      _problem(
        await save([], revision: 9007199254740991),
        MailProblemCode.quotaExceeded,
      );
      expect(
        _value(await store.loadMailboxView(_box.id))!.revision,
        9007199254740991,
      );
    },
  );
}
