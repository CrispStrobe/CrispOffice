@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:test/test.dart';

final _profile = MailProfileId('moves', hostId: 'identity-tests');
final _account = MailAccountId('account', profile: _profile);
final _source = MailMailboxId('inbox', account: _account);
final _destination = MailMailboxId('archive', account: _account);
final _time = DateTime.utc(2026, 11, 22);

T _value<T>(MailResult<T> result) {
  expect(result, isA<MailSuccess<T>>());
  return (result as MailSuccess<T>).value;
}

void _problem<T>(MailResult<T> result, MailProblemCode code) {
  expect(result, isA<MailFailure<T>>());
  expect((result as MailFailure<T>).problem.code, code);
}

MailImapIdentity _remote(MailMailboxId folder, int uid, {int validity = 7}) =>
    MailImapIdentity(mailbox: folder, uidValidity: validity, uid: uid);

MailHeaderRecord _header(
  MailMailboxId folder,
  int uid, {
  int validity = 7,
  String? id,
  String? subject,
}) => MailHeaderRecord(
  id: MailMessageId(id ?? '${folder.value}:$validity:$uid'),
  remote: _remote(folder, uid, validity: validity),
  envelope: MailEnvelope(subject: subject ?? 'Message $uid'),
  flags: const MailMessageFlags(isRead: true, isFlagged: true),
);

MailBulkFlagPlan _plan({String id = 'move'}) => MailBulkFlagPlan(
  id: id,
  mailbox: _source,
  action: MailBulkFlagAction.move,
  destination: _destination,
  messages: [_remote(_source, 2)],
);

MailMoveIdentityTransition _transition(MailBulkFlagPlan plan, {int uid = 70}) =>
    MailMoveIdentityTransition(
      operationId: plan.operationAt(0).id,
      source: plan.messages.single,
      sourceMailbox: _source,
      destination: _remote(_destination, uid),
      destinationMailbox: _destination,
      destinationMessageId: _header(_destination, uid).id,
    );

MailBulkFlagItemResult _result(
  MailBulkFlagPlan plan, {
  MailMoveIdentityTransition? transition,
}) => MailBulkFlagItemResult.restore(
  operation: plan.operationAt(0),
  outcome: MailBulkFlagOutcome.confirmed,
  identityTransition: transition ?? _transition(plan),
);

MailBulkFlagReport _report(
  MailBulkFlagPlan plan, {
  MailMoveIdentityTransition? transition,
}) => MailBulkFlagReport.restore(
  plan: plan,
  results: [_result(plan, transition: transition)],
);

MailSyncPage _page(
  MailMailboxId folder,
  List<MailHeaderRecord> headers,
  String cursor,
) => MailSyncPage(
  mailbox: folder,
  upserts: headers,
  tombstones: const [],
  next: MailCursor(mailbox: folder, value: cursor),
  hasMore: false,
);

void main() {
  late Directory directory;
  late File file;
  late SqliteMailRepository store;
  late MailAccountSession session;
  var failNextCommit = false;

  Future<SqliteMailRepository> open({
    MailStoreFaultInjector? faultInjector,
    MailStoreLimits limits = const MailStoreLimits(),
    DateTime Function()? clock,
  }) async => _value(
    await SqliteMailRepository.open(
      executor: NativeDatabase(file),
      profile: _profile,
      clock: clock ?? () => _time,
      limits: limits,
      faultInjector:
          faultInjector ??
          (point) {
            if (point == MailStoreCheckpoint.beforeCommit && failNextCommit) {
              failNextCommit = false;
              throw const MailStoreStorageException(
                MailProblemCode.storageFailure,
              );
            }
          },
    ),
  );

  Future<void> reopen() async {
    await store.close();
    store = await open();
  }

  Future<MailCachedMailboxView> saveView(
    MailMailboxId folder,
    List<MailHeaderRecord> headers, {
    bool hasMore = false,
  }) async {
    final previous = _value(await store.loadMailboxView(folder));
    return _value(
      await store.saveMailboxView(
        MailMailbox(id: folder, displayName: folder.value),
        headers,
        expectedRevision: previous?.revision,
        hasMore: hasMore,
        lease: session.begin(),
      ),
    );
  }

  Future<void> saveSync(
    MailMailboxId folder,
    List<MailHeaderRecord> headers,
    String cursor,
  ) async {
    final snapshot = _value(await store.readSyncSnapshot(folder));
    _value(
      await store.commitSyncPageWithSnapshot(
        _page(folder, headers, cursor),
        expectedSnapshot: snapshot,
        lease: session.begin(),
      ),
    );
  }

  Future<MailFlagBatchHandle> begin(MailBulkFlagPlan plan) async {
    final handle = _value(
      await store.createFlagBatch(
        plan,
        subjects: ['Moved subject'],
        lease: session.begin(),
      ),
    );
    _value(await store.beginFlagAttempt(handle, 0, lease: session.begin()));
    return handle;
  }

  Future<MailStoredFlagBatch> finish(
    MailBulkFlagPlan plan,
    MailFlagBatchHandle handle,
  ) async {
    _value(await store.recordFlagResult(handle, 0, _result(plan)));
    _value(await store.finishFlagBatch(handle, _report(plan)));
    return _value<MailStoredFlagBatch?>(
      await store.loadFlagBatch(_account, plan.id),
    )!;
  }

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    directory = await Directory.systemTemp.createTemp('move-identity-');
    file = File('${directory.path}/mail.sqlite3');
    failNextCommit = false;
    session = MailAccountSession(_account);
    store = await open();
    _value(
      await store.createAccount(
        MailStoreAccount(
          id: _account,
          provider: MailProviderKind.imap,
          displayName: 'Test',
        ),
      ),
    );
  });

  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });

  test(
    'confirmed replacement identity survives restart without inventing cache coverage',
    () async {
      final plan = _plan();
      final receipt = await finish(plan, await begin(plan));
      expect(receipt.identityTransitions.single.transition, _transition(plan));
      expect(receipt.identityTransitions.single.cacheProjected, isFalse);
      expect(receipt.identityTransitions.single.recordedAt, _time);
      expect(receipt.report.items.single.identityTransition, _transition(plan));
      await reopen();
      final restored = _value(await store.loadFlagBatch(_account, plan.id))!;
      expect(restored.report.confirmedCount, 1);
      expect(
        restored.report.items.single.identityTransition,
        _transition(plan),
      );
      expect(restored.membershipObservations, isEmpty);
      expect(_value(await store.listMailboxViews(_account)), isEmpty);
      expect(_value(await store.listSyncMailboxes(_account)), isEmpty);
      expect(_value(await store.clearCompletedFlagBatches(_account)), 1);
      final db = sqlite.sqlite3.open(file.path);
      expect(db.select('SELECT * FROM move_identity_transitions'), isEmpty);
      db.close();
    },
  );

  test(
    'exact cached move compacts source, appends destination and preserves dated coverage',
    () async {
      final beforeSource = await saveView(_source, [
        _header(_source, 1),
        _header(_source, 2),
        _header(_source, 3),
      ], hasMore: true);
      final beforeDestination = await saveView(_destination, [
        _header(_destination, 60),
      ], hasMore: true);
      final plan = _plan();
      final receipt = await finish(plan, await begin(plan));
      expect(receipt.identityTransitions.single.cacheProjected, isTrue);
      final source = _value(await store.loadMailboxView(_source))!;
      final destination = _value(await store.loadMailboxView(_destination))!;
      expect(source.headers.map((x) => (x.remote as MailImapIdentity).uid), [
        1,
        3,
      ]);
      expect(
        destination.headers.map((x) => (x.remote as MailImapIdentity).uid),
        [60, 70],
      );
      expect(destination.headers.last.envelope.subject, 'Message 2');
      expect(source.revision, greaterThan(beforeSource.revision));
      expect(destination.revision, greaterThan(beforeDestination.revision));
      expect(source.capturedAt, beforeSource.capturedAt);
      expect(destination.capturedAt, beforeDestination.capturedAt);
      expect(source.hasMore, isTrue);
      expect(destination.hasMore, isTrue);
      _problem(
        await store.saveMailboxView(
          MailMailbox(id: _source, displayName: 'Old'),
          beforeSource.headers,
          expectedRevision: beforeSource.revision,
          hasMore: true,
          lease: session.begin(),
        ),
        MailProblemCode.conflict,
      );
      await reopen();
      expect(_value(await store.loadMailboxView(_source))!.headers.length, 2);
      expect(
        _value(await store.loadMailboxView(_destination))!.headers.length,
        2,
      );
    },
  );

  test(
    'synchronized memberships move atomically and stale provider cursors are fenced',
    () async {
      await saveView(_source, [_header(_source, 2)]);
      await saveView(_destination, [_header(_destination, 60)]);
      await saveSync(_source, [_header(_source, 2)], 'source-cursor');
      await saveSync(_destination, [
        _header(_destination, 60),
      ], 'destination-cursor');
      final oldSource = _value(await store.readCursor(_source));
      final oldDestination = _value(await store.readSyncSnapshot(_destination));
      final before = _value(await store.listSyncMailboxes(_account));
      final plan = _plan();
      final receipt = await finish(plan, await begin(plan));
      expect(receipt.identityTransitions.single.cacheProjected, isTrue);
      expect(_value(await store.listHeaders(_source)), isEmpty);
      expect(
        _value(await store.listHeaders(_destination)).map((x) => x.id.value),
        contains('archive:7:70'),
      );
      final after = _value(await store.listSyncMailboxes(_account));
      for (final previous in before) {
        final current = after.singleWhere(
          (x) => x.mailbox.id == previous.mailbox.id,
        );
        expect(current.updatedAt, previous.updatedAt);
        expect(current.hasMore, previous.hasMore);
        expect(current.revision, greaterThan(previous.revision));
      }
      expect(_value(await store.readCursor(_source))!.value, 'source-cursor');
      expect(
        _value(await store.readCursor(_destination))!.value,
        'destination-cursor',
      );
      _problem(
        await store.commitSyncPage(
          _page(_source, [_header(_source, 2)], 'old-page'),
          expectedCursor: oldSource,
          lease: session.begin(),
        ),
        MailProblemCode.conflict,
      );
      _problem(
        await store.commitSyncPageWithSnapshot(
          _page(_destination, [], 'old-destination'),
          expectedSnapshot: oldDestination,
          lease: session.begin(),
        ),
        MailProblemCode.conflict,
      );
      await reopen();
      _problem(
        await store.commitSyncPage(
          _page(_source, [_header(_source, 2)], 'old-page'),
          expectedCursor: oldSource,
          lease: session.begin(),
        ),
        MailProblemCode.conflict,
      );
      final fresh = _value(await store.readSyncSnapshot(_source));
      _value(
        await store.commitSyncPageWithSnapshot(
          _page(_source, [], 'new-page'),
          expectedSnapshot: fresh,
          lease: session.begin(),
        ),
      );
    },
  );

  for (final views in ['neither', 'source', 'destination']) {
    test(
      'synchronized membership awaits both browse CAS revisions; retained=$views',
      () async {
        await saveSync(_source, [_header(_source, 2)], 'source');
        await saveSync(_destination, [], 'destination');
        if (views == 'source') await saveView(_source, [_header(_source, 2)]);
        if (views == 'destination') await saveView(_destination, []);
        final sourceSnapshot = _value(await store.readSyncSnapshot(_source));
        final destinationSnapshot = _value(
          await store.readSyncSnapshot(_destination),
        );
        final plan = _plan();
        final receipt = await finish(plan, await begin(plan));
        expect(receipt.report.confirmedCount, 1);
        expect(receipt.identityTransitions.single.cacheProjected, isFalse);
        expect(
          _value(await store.listHeaders(_source)).single.id,
          _header(_source, 2).id,
        );
        expect(_value(await store.listHeaders(_destination)), isEmpty);
        expect(
          _value(await store.readSyncSnapshot(_source)).revision,
          sourceSnapshot.revision,
        );
        expect(
          _value(await store.readSyncSnapshot(_destination)).revision,
          destinationSnapshot.revision,
        );
        await reopen();
        expect(
          _value(
            await store.loadFlagBatch(_account, plan.id),
          )!.identityTransitions.single.cacheProjected,
          isFalse,
        );
        expect(
          _value(await store.listMailboxViews(_account)).length,
          views == 'neither' ? 0 : 1,
        );
      },
    );
  }

  test(
    'source browse revision advances even when its window omits the moved member',
    () async {
      await saveSync(_source, [_header(_source, 2)], 'source');
      await saveSync(_destination, [], 'destination');
      final source = await saveView(_source, [
        _header(_source, 1),
      ], hasMore: true);
      await saveView(_destination, []);
      final plan = _plan();
      final receipt = await finish(plan, await begin(plan));
      expect(receipt.identityTransitions.single.cacheProjected, isTrue);
      final current = _value(await store.loadMailboxView(_source))!;
      expect(current.headers.single.id, _header(_source, 1).id);
      expect(current.revision, greaterThan(source.revision));
      expect(current.capturedAt, source.capturedAt);
      expect(current.hasMore, source.hasMore);
      expect(_value(await store.listHeaders(_source)), isEmpty);
      await reopen();
      _problem(
        await store.saveMailboxView(
          source.mailbox,
          [_header(_source, 1), _header(_source, 2)],
          expectedRevision: source.revision,
          hasMore: true,
          lease: session.begin(),
        ),
        MailProblemCode.conflict,
      );
    },
  );

  test(
    'first synchronization snapshot is fenced even when no provider cursor exists',
    () async {
      await saveView(_source, [_header(_source, 2)]);
      await saveView(_destination, []);
      final oldSource = _value(await store.readSyncSnapshot(_source));
      final oldDestination = _value(await store.readSyncSnapshot(_destination));
      expect(oldSource.cursor, isNull);
      final plan = _plan();
      await finish(plan, await begin(plan));
      _problem(
        await store.commitSyncPageWithSnapshot(
          _page(_source, [_header(_source, 2)], 'stale'),
          expectedSnapshot: oldSource,
          lease: session.begin(),
        ),
        MailProblemCode.conflict,
      );
      _problem(
        await store.commitSyncPageWithSnapshot(
          _page(_destination, [], 'stale'),
          expectedSnapshot: oldDestination,
          lease: session.begin(),
        ),
        MailProblemCode.conflict,
      );
      _problem(
        await store.commitSyncPage(
          _page(_source, [_header(_source, 2)], 'legacy'),
          expectedCursor: null,
          lease: session.begin(),
        ),
        MailProblemCode.conflict,
      );
      await reopen();
      final fresh = _value(await store.readSyncSnapshot(_source));
      expect(fresh.cursor, isNull);
      expect(fresh.revision, greaterThan(oldSource.revision));
      _value(
        await store.commitSyncPageWithSnapshot(
          _page(_source, [], 'fresh'),
          expectedSnapshot: fresh,
          lease: session.begin(),
        ),
      );
    },
  );

  test('cache cleanup cannot revive old null-cursor snapshots', () async {
    await saveView(_source, [_header(_source, 2)]);
    await saveView(_destination, []);
    final stale = _value(await store.readSyncSnapshot(_source));
    final plan = _plan();
    await finish(plan, await begin(plan));
    _value(await store.clearMailboxCache(_account));
    await reopen();
    _problem(
      await store.commitSyncPageWithSnapshot(
        _page(_source, [_header(_source, 2)], 'old'),
        expectedSnapshot: stale,
        lease: session.begin(),
      ),
      MailProblemCode.conflict,
    );
    final fresh = _value(await store.readSyncSnapshot(_source));
    _value(
      await store.commitSyncPageWithSnapshot(
        _page(_source, [], 'fresh'),
        expectedSnapshot: fresh,
        lease: session.begin(),
      ),
    );
  });

  test(
    'new source observation after dispatch retains reply and skips stale projection',
    () async {
      await saveView(_source, [_header(_source, 2)]);
      await saveView(_destination, []);
      final plan = _plan();
      final handle = await begin(plan);
      final changed = await saveView(_source, [
        _header(_source, 2, subject: 'New observation'),
      ]);
      final receipt = await finish(plan, handle);
      expect(receipt.identityTransitions.single.cacheProjected, isFalse);
      expect(receipt.report.confirmedCount, 1);
      expect(
        _value(await store.loadMailboxView(_source))!.revision,
        changed.revision,
      );
      expect(
        _value(
          await store.loadMailboxView(_source),
        )!.headers.single.envelope.subject,
        'New observation',
      );
      expect(
        _value(await store.loadMailboxView(_destination))!.headers,
        isEmpty,
      );
    },
  );

  test(
    'new destination observation after dispatch is not overwritten',
    () async {
      await saveView(_source, [_header(_source, 2)]);
      await saveView(_destination, []);
      final plan = _plan();
      final handle = await begin(plan);
      final changed = await saveView(_destination, [
        _header(_destination, 70, subject: 'Newer destination'),
      ]);
      final receipt = await finish(plan, handle);
      expect(receipt.identityTransitions.single.cacheProjected, isFalse);
      expect(
        _value(await store.loadMailboxView(_destination))!.revision,
        changed.revision,
      );
      expect(
        _value(
          await store.loadMailboxView(_destination),
        )!.headers.single.envelope.subject,
        'Newer destination',
      );
    },
  );

  test(
    'known destination identity keeps its existing metadata and does not duplicate',
    () async {
      await saveView(_source, [_header(_source, 2)]);
      await saveView(_destination, [
        _header(_destination, 70, subject: 'Already observed'),
      ]);
      final plan = _plan();
      final receipt = await finish(plan, await begin(plan));
      expect(receipt.identityTransitions.single.cacheProjected, isTrue);
      final target = _value(await store.loadMailboxView(_destination))!;
      expect(target.headers.length, 1);
      expect(target.headers.single.envelope.subject, 'Already observed');
    },
  );

  test(
    'source retained bytes are preserved and no destination body is fabricated',
    () async {
      final header = _header(_source, 2);
      await saveView(_source, [header]);
      await saveView(_destination, []);
      _value(
        await store.cacheMessage(
          _account,
          header.id,
          MailMessage(
            raw: MailBytes(
              utf8.encode('Subject: Message 2\r\n\r\nOriginal body'),
            ),
            envelope: header.envelope,
            localId: header.id,
            remoteIdentity: header.remote,
            body: const MailBody(plainText: 'Original body'),
          ),
        ),
      );
      final plan = _plan();
      await finish(plan, await begin(plan));
      expect(
        _value(
          await store.loadCachedMessage(_account, header.id),
        )!.body.plainText,
        'Original body',
      );
      expect(
        _value(
          await store.loadCachedMessage(
            _account,
            _transition(plan).destinationMessageId,
          ),
        ),
        isNull,
      );
      expect(
        _value(
          await store.search(_account, 'Message'),
        ).map((row) => row.header.id.value),
        contains('archive:7:70'),
      );
    },
  );

  test(
    'rollback retains applying marker and final settlement projects only once',
    () async {
      final sourceBefore = await saveView(_source, [
        _header(_source, 1),
        _header(_source, 2),
      ]);
      final destinationBefore = await saveView(_destination, []);
      final plan = _plan();
      final handle = await begin(plan);
      failNextCommit = true;
      _problem(
        await store.recordFlagResult(handle, 0, _result(plan)),
        MailProblemCode.storageFailure,
      );
      expect(
        _value(
          await store.loadFlagBatch(_account, plan.id),
        )!.identityTransitions,
        isEmpty,
      );
      expect(
        _value(await store.loadMailboxView(_source))!.revision,
        sourceBefore.revision,
      );
      expect(
        _value(await store.loadMailboxView(_destination))!.revision,
        destinationBefore.revision,
      );
      _value(await store.finishFlagBatch(handle, _report(plan)));
      final target = _value(await store.loadMailboxView(_destination))!;
      expect(target.headers.length, 1);
      expect(
        _value(
          await store.loadFlagBatch(_account, plan.id),
        )!.identityTransitions.single.cacheProjected,
        isTrue,
      );
      _problem(
        await store.finishFlagBatch(handle, _report(plan)),
        MailProblemCode.conflict,
      );
      expect(
        _value(await store.loadMailboxView(_destination))!.revision,
        target.revision,
      );
    },
  );

  test(
    'finishing a recorded result requires identical replacement evidence',
    () async {
      await saveView(_source, [_header(_source, 2)]);
      await saveView(_destination, []);
      final plan = _plan();
      final handle = await begin(plan);
      _value(await store.recordFlagResult(handle, 0, _result(plan)));
      final target = _value(await store.loadMailboxView(_destination))!;
      _problem(
        await store.finishFlagBatch(
          handle,
          _report(plan, transition: _transition(plan, uid: 71)),
        ),
        MailProblemCode.conflict,
      );
      expect(
        _value(await store.loadMailboxView(_destination))!.revision,
        target.revision,
      );
      _value(await store.finishFlagBatch(handle, _report(plan)));
      expect(
        _value(await store.loadMailboxView(_destination))!.revision,
        target.revision,
      );
    },
  );

  test(
    'interrupted applying receipt never obtains an invented mapping',
    () async {
      final plan = _plan();
      await begin(plan);
      await reopen();
      final receipt = _value(await store.loadFlagBatch(_account, plan.id))!;
      expect(receipt.summary.uncertainCount, 1);
      expect(receipt.identityTransitions, isEmpty);
      expect(receipt.report.items.single.identityTransition, isNull);
      expect(_value(await store.clearCompletedFlagBatches(_account)), 0);
    },
  );

  test(
    'retired transport lease cannot erase an acknowledged identity',
    () async {
      final plan = _plan();
      final handle = await begin(plan);
      session.dispose();
      final receipt = await finish(plan, handle);
      expect(receipt.report.confirmedCount, 1);
      expect(receipt.identityTransitions.single.transition, _transition(plan));
    },
  );

  test(
    'different IMAP destination generation skips projection without changing evidence',
    () async {
      await saveView(_source, [_header(_source, 2)]);
      final target = await saveView(_destination, [
        _header(_destination, 60, validity: 8),
      ]);
      final plan = _plan();
      final receipt = await finish(plan, await begin(plan));
      expect(receipt.identityTransitions.single.cacheProjected, isFalse);
      expect(_value(await store.loadMailboxView(_source))!.headers.length, 1);
      expect(
        _value(await store.loadMailboxView(_destination))!.revision,
        target.revision,
      );
    },
  );

  test(
    'destination local ID collision skips projection without overwriting mail',
    () async {
      await saveView(_source, [_header(_source, 2)]);
      final target = await saveView(_destination, [
        _header(_destination, 99, id: 'archive:7:70'),
      ]);
      final plan = _plan();
      final receipt = await finish(plan, await begin(plan));
      expect(receipt.identityTransitions.single.cacheProjected, isFalse);
      expect(
        _value(await store.loadMailboxView(_destination))!.revision,
        target.revision,
      );
      expect(
        (_value(
                  await store.loadMailboxView(_destination),
                )!.headers.single.remote
                as MailImapIdentity)
            .uid,
        99,
      );
    },
  );

  test(
    'unknown destination coverage retains dated source and mapping only',
    () async {
      final source = await saveView(_source, [_header(_source, 2)]);
      final plan = _plan();
      final receipt = await finish(plan, await begin(plan));
      expect(receipt.identityTransitions.single.cacheProjected, isFalse);
      expect(
        _value(await store.loadMailboxView(_source))!.revision,
        source.revision,
      );
      expect(_value(await store.loadMailboxView(_destination)), isNull);
    },
  );

  test(
    'account cleanup removes transitions and persisted move fences',
    () async {
      await saveView(_source, [_header(_source, 2)]);
      await saveView(_destination, []);
      final plan = _plan();
      await finish(plan, await begin(plan));
      _value(await store.removeAccount(_account));
      final db = sqlite.sqlite3.open(file.path);
      expect(db.select('SELECT * FROM move_identity_transitions'), isEmpty);
      expect(db.select('SELECT * FROM mailbox_move_revisions'), isEmpty);
      expect(db.select('PRAGMA foreign_key_check'), isEmpty);
      db.close();
    },
  );

  for (final provider in [MailProviderKind.ews, MailProviderKind.graph]) {
    test(
      '${provider.name} exact parent move uses canonical target ID and keeps known metadata',
      () async {
        final account = MailAccountId(provider.name, profile: _profile);
        final sourceFolder = MailMailboxId('Source', account: account);
        final destinationFolder = MailMailboxId('Target', account: account);
        final providerSession = MailAccountSession(account);
        _value(
          await store.createAccount(
            MailStoreAccount(
              id: account,
              provider: provider,
              displayName: provider.name,
            ),
          ),
        );
        final sourceIdentity = MailOpaqueIdentity(
          account: account,
          provider: provider,
          value: 'old-id',
        );
        final destinationIdentity = MailOpaqueIdentity(
          account: account,
          provider: provider,
          value: provider == MailProviderKind.graph ? 'old-id' : 'new-id',
        );
        final sourceId = MailMessageId('source-local');
        final destinationId = provider == MailProviderKind.graph
            ? sourceId
            : MailMessageId('target-local');
        _value(
          await store.saveMailboxView(
            MailMailbox(id: sourceFolder, displayName: 'Source'),
            [
              MailHeaderRecord(
                id: sourceId,
                remote: sourceIdentity,
                envelope: MailEnvelope(subject: 'Keep my content'),
              ),
            ],
            expectedRevision: null,
            hasMore: false,
            lease: providerSession.begin(),
          ),
        );
        _value(
          await store.saveMailboxView(
            MailMailbox(id: destinationFolder, displayName: 'Target'),
            [],
            expectedRevision: null,
            hasMore: false,
            lease: providerSession.begin(),
          ),
        );
        final plan = MailBulkFlagPlan(
          id: 'opaque-move',
          mailbox: sourceFolder,
          action: MailBulkFlagAction.move,
          destination: destinationFolder,
          messages: [sourceIdentity],
        );
        final transition = MailMoveIdentityTransition(
          operationId: plan.operationAt(0).id,
          source: sourceIdentity,
          sourceMailbox: sourceFolder,
          destination: destinationIdentity,
          destinationMailbox: destinationFolder,
          destinationMessageId: destinationId,
        );
        final handle = _value(
          await store.createFlagBatch(
            plan,
            subjects: ['Keep my content'],
            lease: providerSession.begin(),
          ),
        );
        _value(
          await store.beginFlagAttempt(
            handle,
            0,
            lease: providerSession.begin(),
          ),
        );
        final result = MailBulkFlagItemResult.restore(
          operation: plan.operationAt(0),
          outcome: MailBulkFlagOutcome.confirmed,
          identityTransition: transition,
        );
        _value(await store.recordFlagResult(handle, 0, result));
        _value(
          await store.finishFlagBatch(
            handle,
            MailBulkFlagReport.restore(plan: plan, results: [result]),
          ),
        );
        expect(
          _value(await store.loadMailboxView(sourceFolder))!.headers,
          isEmpty,
        );
        final destination = _value(
          await store.loadMailboxView(destinationFolder),
        )!;
        expect(destination.headers.single.id, destinationId);
        expect(destination.headers.single.remote, destinationIdentity);
        expect(destination.headers.single.envelope.subject, 'Keep my content');
        final saved = _value(await store.loadFlagBatch(account, plan.id))!;
        expect(saved.identityTransitions.single.transition, transition);
        expect(saved.identityTransitions.single.cacheProjected, isTrue);
        await reopen();
        expect(
          _value(
            await store.loadFlagBatch(account, plan.id),
          )!.report.items.single.identityTransition,
          transition,
        );
      },
    );
  }

  test(
    'transition metadata quota rolls back acknowledgement and permits no partial mapping',
    () async {
      await store.close();
      store = await open(
        limits: const MailStoreLimits(maxMetadataCodeUnits: 128),
      );
      final plan = _plan();
      final handle = await begin(plan);
      final transition = MailMoveIdentityTransition(
        operationId: plan.operationAt(0).id,
        source: plan.messages.single,
        sourceMailbox: _source,
        destination: _remote(_destination, 70),
        destinationMailbox: _destination,
        destinationMessageId: MailMessageId('x' * 200),
      );
      _problem(
        await store.recordFlagResult(
          handle,
          0,
          _result(plan, transition: transition),
        ),
        MailProblemCode.quotaExceeded,
      );
      final receipt = _value(await store.loadFlagBatch(_account, plan.id))!;
      expect(receipt.identityTransitions, isEmpty);
      expect(receipt.report.uncertainCount, 1);
      expect(receipt.summary.complete, isFalse);
      final db = sqlite.sqlite3.open(file.path);
      expect(db.select('SELECT * FROM move_identity_transitions'), isEmpty);
      expect(db.select('SELECT * FROM mailbox_move_revisions'), isEmpty);
      db.close();
    },
  );

  test(
    'full bounded destination retains acknowledgment without changing either view',
    () async {
      await store.close();
      store = await open(limits: const MailStoreLimits(maxPageSize: 1));
      final source = await saveView(_source, [_header(_source, 2)]);
      final target = await saveView(_destination, [_header(_destination, 60)]);
      final plan = _plan();
      final receipt = await finish(plan, await begin(plan));
      expect(receipt.identityTransitions.single.cacheProjected, isFalse);
      expect(
        _value(await store.loadMailboxView(_source))!.revision,
        source.revision,
      );
      expect(
        _value(await store.loadMailboxView(_destination))!.revision,
        target.revision,
      );
    },
  );

  for (final synchronized in [false, true]) {
    test(
      'combined destination metadata bound skips projection; synchronized=$synchronized',
      () async {
        await store.close();
        store = await open(
          limits: const MailStoreLimits(maxMetadataCodeUnits: 700),
        );
        final sourceHeader = _header(_source, 2, subject: 's' * 220);
        final targetHeader = _header(_destination, 60, subject: 't' * 250);
        final source = await saveView(_source, [sourceHeader]);
        final target = await saveView(_destination, [targetHeader]);
        if (synchronized) {
          await saveSync(_source, [sourceHeader], 'source');
          await saveSync(_destination, [targetHeader], 'target');
        }
        final plan = _plan();
        final receipt = await finish(plan, await begin(plan));
        expect(receipt.identityTransitions.single.cacheProjected, isFalse);
        expect(receipt.report.confirmedCount, 1);
        expect(
          _value(await store.loadMailboxView(_source))!.revision,
          source.revision,
        );
        expect(
          _value(await store.loadMailboxView(_destination))!.revision,
          target.revision,
        );
        expect(
          _value(
            await store.loadMailboxView(_destination),
          )!.headers.single.envelope.subject,
          't' * 250,
        );
        if (synchronized) {
          expect(
            _value(await store.listHeaders(_source)).single.id,
            sourceHeader.id,
          );
          expect(
            _value(await store.listHeaders(_destination)).single.id,
            targetHeader.id,
          );
        }
      },
    );
  }

  test(
    'optional cache growth rolls back on account quota while receipt survives',
    () async {
      await store.close();
      store = await open(limits: const MailStoreLimits(maxAccountBytes: 5000));
      final source = await saveView(_source, [
        _header(_source, 2, subject: 's' * 1000),
      ]);
      final destination = await saveView(_destination, []);
      final plan = _plan();
      final handle = await begin(plan);
      final receipt = await finish(plan, handle);
      expect(receipt.report.confirmedCount, 1);
      expect(receipt.identityTransitions.single.cacheProjected, isFalse);
      expect(
        _value(await store.loadMailboxView(_source))!.revision,
        source.revision,
      );
      expect(
        _value(await store.loadMailboxView(_destination))!.revision,
        destination.revision,
      );
      expect(
        _value(await store.loadMailboxView(_destination))!.headers,
        isEmpty,
      );
      expect(_value(await store.readSyncSnapshot(_source)).revision, 0);
      expect(_value(await store.readSyncSnapshot(_destination)).revision, 0);
      final db = sqlite.sqlite3.open(file.path);
      expect(
        db.select('SELECT id FROM messages').single['id'],
        _header(_source, 2).id.value,
      );
      expect(db.select('SELECT * FROM mailbox_move_revisions'), isEmpty);
      expect(db.select('SELECT * FROM tombstones'), isEmpty);
      expect(
        db.select('SELECT message FROM mail_fts').single['message'],
        _header(_source, 2).id.value,
      );
      db.close();
      await reopen();
      final restored = _value(await store.loadFlagBatch(_account, plan.id))!;
      expect(restored.summary.complete, isTrue);
      expect(restored.identityTransitions.single.cacheProjected, isFalse);
      expect(restored.identityTransitions.single.transition, _transition(plan));
    },
  );

  test(
    'account byte quota includes authoritative replacement metadata',
    () async {
      await store.close();
      store = await open(limits: const MailStoreLimits(maxAccountBytes: 1800));
      final plan = _plan();
      final handle = await begin(plan);
      final transition = MailMoveIdentityTransition(
        operationId: plan.operationAt(0).id,
        source: plan.messages.single,
        sourceMailbox: _source,
        destination: _remote(_destination, 70),
        destinationMailbox: _destination,
        destinationMessageId: MailMessageId('x' * 1500),
      );
      _problem(
        await store.recordFlagResult(
          handle,
          0,
          _result(plan, transition: transition),
        ),
        MailProblemCode.quotaExceeded,
      );
      expect(
        _value(
          await store.loadFlagBatch(_account, plan.id),
        )!.identityTransitions,
        isEmpty,
      );
      expect(
        _value(await store.loadFlagBatch(_account, plan.id))!.summary.complete,
        isFalse,
      );
    },
  );

  test(
    'clock reversal during mapping settlement rolls back receipt and both views',
    () async {
      await store.close();
      var clockReads = 100;
      store = await open(
        clock: () => ++clockReads >= 2 && clockReads < 100
            ? _time.subtract(const Duration(milliseconds: 1))
            : _time,
      );
      final source = await saveView(_source, [_header(_source, 2)]);
      final destination = await saveView(_destination, []);
      final plan = _plan();
      final handle = await begin(plan);
      clockReads = 0;
      _problem(
        await store.recordFlagResult(handle, 0, _result(plan)),
        MailProblemCode.conflict,
      );
      final beforeFinish = _value(
        await store.loadFlagBatch(_account, plan.id),
      )!;
      expect(beforeFinish.identityTransitions, isEmpty);
      expect(beforeFinish.summary.complete, isFalse);
      expect(
        _value(await store.loadMailboxView(_source))!.revision,
        source.revision,
      );
      expect(
        _value(await store.loadMailboxView(_destination))!.revision,
        destination.revision,
      );
      clockReads = 100;
      _value(await store.finishFlagBatch(handle, _report(plan)));
      final finished = _value(await store.loadFlagBatch(_account, plan.id))!;
      expect(finished.report.confirmedCount, 1);
      expect(finished.identityTransitions.single.recordedAt, _time);
      expect(finished.summary.updatedAt, _time);
      expect(finished.identityTransitions.single.cacheProjected, isTrue);
    },
  );

  test(
    'clock reversal during finish preserves already recorded mapping without applying twice',
    () async {
      await store.close();
      var time = _time;
      store = await open(clock: () => time);
      await saveView(_source, [_header(_source, 2)]);
      await saveView(_destination, []);
      final plan = _plan();
      final handle = await begin(plan);
      _value(await store.recordFlagResult(handle, 0, _result(plan)));
      final destination = _value(await store.loadMailboxView(_destination))!;
      time = _time.subtract(const Duration(milliseconds: 1));
      _problem(
        await store.finishFlagBatch(handle, _report(plan)),
        MailProblemCode.conflict,
      );
      final unfinished = _value(await store.loadFlagBatch(_account, plan.id))!;
      expect(unfinished.report.confirmedCount, 1);
      expect(unfinished.summary.complete, isFalse);
      expect(unfinished.summary.updatedAt, _time);
      expect(
        _value(await store.loadMailboxView(_destination))!.revision,
        destination.revision,
      );
      time = _time;
      _value(await store.finishFlagBatch(handle, _report(plan)));
      expect(
        _value(await store.loadMailboxView(_destination))!.revision,
        destination.revision,
      );
    },
  );

  for (final action in [
    MailBulkFlagAction.markUnread,
    MailBulkFlagAction.move,
    MailBulkFlagAction.delete,
  ]) {
    test(
      'clock reversal rolls back legacy ${action.name} result and keeps a valid receipt',
      () async {
        await store.close();
        var time = _time;
        store = await open(clock: () => time);
        final original = await saveView(_source, [_header(_source, 2)]);
        final plan = MailBulkFlagPlan(
          id: 'clock-${action.name}',
          mailbox: _source,
          action: action,
          messages: [_remote(_source, 2)],
          destination: action == MailBulkFlagAction.move ? _destination : null,
        );
        final handle = await begin(plan);
        final result = MailBulkFlagItemResult.restore(
          operation: plan.operationAt(0),
          outcome: MailBulkFlagOutcome.confirmed,
        );
        time = _time.subtract(const Duration(milliseconds: 1));
        _problem(
          await store.recordFlagResult(handle, 0, result),
          MailProblemCode.conflict,
        );
        final retained = _value(await store.loadMailboxView(_source))!;
        expect(retained.revision, original.revision);
        expect(retained.headers.single.flags!.isRead, isTrue);
        expect(
          _value(
            await store.loadFlagBatch(_account, plan.id),
          )!.summary.updatedAt,
          _time,
        );
        time = _time;
        _value(
          await store.finishFlagBatch(
            handle,
            MailBulkFlagReport.restore(plan: plan, results: [result]),
          ),
        );
        expect(
          _value(
            await store.loadFlagBatch(_account, plan.id),
          )!.report.confirmedCount,
          1,
        );
      },
    );
  }

  for (final corruption in [
    "UPDATE mailbox_move_revisions SET mailbox=char(10)",
    "UPDATE mailbox_move_revisions SET revision='invalid'",
    "UPDATE mailbox_move_revisions SET mailbox=zeroblob(5000)",
  ]) {
    test(
      'corrupt move fence fails bounded history validation: $corruption',
      () async {
        await saveView(_source, [_header(_source, 2)]);
        await saveView(_destination, []);
        final plan = _plan();
        await finish(plan, await begin(plan));
        await store.close();
        final db = sqlite.sqlite3.open(file.path);
        db.execute('PRAGMA ignore_check_constraints=ON');
        db.execute("$corruption WHERE mailbox='inbox'");
        db.close();
        store = await open();
        _problem(
          await store.listFlagBatches(_account),
          MailProblemCode.storageFailure,
        );
      },
    );
  }

  for (final corruption in [
    "UPDATE move_identity_transitions SET destination_remote='{}'",
    "UPDATE move_identity_transitions SET destination_message=char(10)",
    "UPDATE flag_batch_items SET state='uncertain'",
    "UPDATE move_identity_transitions SET recorded_at=0",
  ]) {
    test('corrupt receipt fails bounded history read: $corruption', () async {
      final plan = _plan();
      await finish(plan, await begin(plan));
      await store.close();
      final db = sqlite.sqlite3.open(file.path);
      db.execute(corruption);
      db.close();
      store = await open();
      _problem(
        await store.listFlagBatches(_account),
        MailProblemCode.storageFailure,
      );
      _problem(
        await store.loadFlagBatch(_account, plan.id),
        MailProblemCode.storageFailure,
      );
    });
  }
}
