@TestOn('vm')
library;

import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:test/test.dart';

final _profile = MailProfileId('move-safety', hostId: 'integration-tests');
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

MailHeaderRecord _header(MailMailboxId mailbox, int uid, {String? subject}) =>
    MailHeaderRecord(
      id: MailMessageId('${mailbox.value}:7:$uid'),
      remote: MailImapIdentity(mailbox: mailbox, uidValidity: 7, uid: uid),
      envelope: MailEnvelope(subject: subject ?? 'Message $uid'),
      flags: const MailMessageFlags(isRead: true, isFlagged: true),
    );

MailBulkFlagPlan _plan({String id = 'move'}) => MailBulkFlagPlan(
  id: id,
  mailbox: _source,
  action: MailBulkFlagAction.move,
  destination: _destination,
  messages: [_header(_source, 2).remote],
);

MailMoveIdentityTransition _transition(MailBulkFlagPlan plan) =>
    MailMoveIdentityTransition(
      operationId: plan.operationAt(0).id,
      source: plan.messages.single,
      sourceMailbox: plan.mailbox,
      destination: _header(plan.destination!, 70).remote,
      destinationMailbox: plan.destination!,
      destinationMessageId: _header(plan.destination!, 70).id,
    );

MailBulkFlagItemResult _result(
  MailBulkFlagPlan plan, {
  MailMoveIdentityTransition? transition,
}) => MailBulkFlagItemResult.restore(
  operation: plan.operationAt(0),
  outcome: MailBulkFlagOutcome.confirmed,
  identityTransition: transition ?? _transition(plan),
);

MailSyncPage _page(
  MailMailboxId mailbox,
  List<MailHeaderRecord> headers,
  String cursor,
) => MailSyncPage(
  mailbox: mailbox,
  upserts: headers,
  tombstones: const [],
  next: MailCursor(mailbox: mailbox, value: cursor),
  hasMore: false,
);

void main() {
  late Directory directory;
  late File file;
  late SqliteMailRepository store;
  late MailAccountSession session;
  var failCommit = false;

  Future<SqliteMailRepository> open({
    File? database,
    MailStoreLimits limits = const MailStoreLimits(),
  }) async => _value(
    await SqliteMailRepository.open(
      executor: NativeDatabase(database ?? file),
      profile: _profile,
      limits: limits,
      clock: () => _time,
      faultInjector: (point) {
        if (point == MailStoreCheckpoint.beforeCommit && failCommit) {
          throw const MailStoreStorageException(MailProblemCode.storageFailure);
        }
      },
    ),
  );

  Future<void> reopen({
    MailStoreLimits limits = const MailStoreLimits(),
  }) async {
    await store.close();
    store = await open(limits: limits);
  }

  Future<MailCachedMailboxView> saveView(
    MailMailboxId mailbox,
    List<MailHeaderRecord> headers, {
    int? revision,
    String? displayName,
  }) async => _value(
    await store.saveMailboxView(
      MailMailbox(id: mailbox, displayName: displayName ?? mailbox.value),
      headers,
      expectedRevision: revision,
      hasMore: true,
      lease: session.begin(),
    ),
  );

  Future<void> saveSync(
    MailMailboxId mailbox,
    List<MailHeaderRecord> headers,
  ) async {
    final snapshot = _value(await store.readSyncSnapshot(mailbox));
    _value(
      await store.commitSyncPageWithSnapshot(
        _page(mailbox, headers, '${mailbox.value}-cursor'),
        expectedSnapshot: snapshot,
        lease: session.begin(),
      ),
    );
  }

  Future<MailFlagBatchHandle> begin(MailBulkFlagPlan plan) async {
    final handle = _value(
      await store.createFlagBatch(
        plan,
        subjects: const ['Moved message'],
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
    final result = _result(plan);
    _value(await store.recordFlagResult(handle, 0, result));
    _value(
      await store.finishFlagBatch(
        handle,
        MailBulkFlagReport.restore(plan: plan, results: [result]),
      ),
    );
    return _value<MailStoredFlagBatch?>(
      await store.loadFlagBatch(_account, plan.id),
    )!;
  }

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    directory = await Directory.systemTemp.createTemp('move-safety-');
    file = File('${directory.path}/mail.sqlite3');
    session = MailAccountSession(_account);
    failCommit = false;
    store = await open();
    _value(
      await store.createAccount(
        MailStoreAccount(
          id: _account,
          provider: MailProviderKind.imap,
          displayName: 'Synthetic',
        ),
      ),
    );
  });
  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });

  for (final missing in ['source', 'destination', 'both']) {
    test(
      'an absent $missing browse view retains receipt without projection',
      () async {
        final header = _header(_source, 2);
        await saveSync(_source, [header]);
        await saveSync(_destination, const []);
        final sourceView = missing == 'destination'
            ? await saveView(_source, [header])
            : null;
        final destinationView = missing == 'source'
            ? await saveView(_destination, const [])
            : null;
        final beforeSource = _value(await store.readSyncSnapshot(_source));
        final beforeDestination = _value(
          await store.readSyncSnapshot(_destination),
        );
        final plan = _plan();
        final receipt = await finish(plan, await begin(plan));

        expect(receipt.report.confirmedCount, 1);
        expect(
          receipt.identityTransitions.single.transition,
          _transition(plan),
        );
        expect(receipt.identityTransitions.single.cacheProjected, isFalse);
        expect(_value(await store.listHeaders(_source)).single.id, header.id);
        expect(_value(await store.listHeaders(_destination)), isEmpty);
        expect(
          _value(await store.readSyncSnapshot(_source)).revision,
          beforeSource.revision,
        );
        expect(
          _value(await store.readSyncSnapshot(_destination)).revision,
          beforeDestination.revision,
        );
        expect(
          _value(await store.loadMailboxView(_source))?.revision,
          sourceView?.revision,
        );
        expect(
          _value(await store.loadMailboxView(_destination))?.revision,
          destinationView?.revision,
        );

        // A request holding null still may publish a dated observation. Skipping
        // projection means that write cannot contradict an applied cache move.
        if (sourceView == null) {
          expect(
            (await saveView(_source, [header])).headers.single.id,
            header.id,
          );
        }
        if (destinationView == null) {
          expect((await saveView(_destination, const [])).headers, isEmpty);
        }
        await reopen();
        expect(
          _value(
            await store.loadFlagBatch(_account, plan.id),
          )!.identityTransitions.single.cacheProjected,
          isFalse,
        );
      },
    );
  }

  test(
    'a synchronized source omitted from its window still fences stale browse writers',
    () async {
      final moved = _header(_source, 2);
      final retained = _header(_source, 3);
      await saveSync(_source, [moved, retained]);
      await saveSync(_destination, const []);
      final sourceView = await saveView(_source, [retained]);
      final destinationView = await saveView(_destination, const []);
      final oldSnapshot = _value(await store.readSyncSnapshot(_source));
      final plan = _plan();
      final receipt = await finish(plan, await begin(plan));

      expect(receipt.identityTransitions.single.cacheProjected, isTrue);
      final after = _value(await store.loadMailboxView(_source))!;
      expect(after.headers.single.id, retained.id);
      expect(after.revision, greaterThan(sourceView.revision));
      expect(after.capturedAt, sourceView.capturedAt);
      expect(after.hasMore, sourceView.hasMore);
      expect(
        _value(await store.loadMailboxView(_destination))!.revision,
        greaterThan(destinationView.revision),
      );
      expect(_value(await store.listHeaders(_source)).single.id, retained.id);
      expect(
        _value(await store.listHeaders(_destination)).single.id,
        _header(_destination, 70).id,
      );
      _problem(
        await store.saveMailboxView(
          sourceView.mailbox,
          [moved, retained],
          expectedRevision: sourceView.revision,
          hasMore: sourceView.hasMore,
          lease: session.begin(),
        ),
        MailProblemCode.conflict,
      );
      _problem(
        await store.commitSyncPageWithSnapshot(
          _page(_source, [moved, retained], 'stale'),
          expectedSnapshot: oldSnapshot,
          lease: session.begin(),
        ),
        MailProblemCode.conflict,
      );
      expect(
        _value(await store.loadMailboxView(_source))!.headers.single.id,
        retained.id,
      );
    },
  );

  test(
    'projection budgets the existing destination row outside its browse window',
    () async {
      await reopen(limits: const MailStoreLimits(maxMetadataCodeUnits: 900));
      final sourceView = await saveView(_source, [_header(_source, 2)]);
      final destinationView = await saveView(_destination, [
        _header(_destination, 60, subject: 'd' * 300),
      ]);
      final target = _header(_destination, 70, subject: 't' * 500);
      await saveSync(_destination, [target]);
      final plan = _plan();
      final receipt = await finish(plan, await begin(plan));

      expect(receipt.report.confirmedCount, 1);
      expect(receipt.identityTransitions.single.cacheProjected, isFalse);
      expect(
        _value(await store.loadMailboxView(_source))!.revision,
        sourceView.revision,
      );
      final after = _value(await store.loadMailboxView(_destination))!;
      expect(after.revision, destinationView.revision);
      expect(after.headers.single.envelope.subject, 'd' * 300);
      expect(
        _value(await store.listHeaders(_destination)).single.envelope.subject,
        't' * 500,
      );
    },
  );

  test(
    'synchronized destination metadata includes its retained folder label',
    () async {
      await reopen(limits: const MailStoreLimits(maxMetadataCodeUnits: 900));
      final sourceView = await saveView(_source, [_header(_source, 2)]);
      final destinationView = await saveView(
        _destination,
        const [],
        displayName: 'L' * 250,
      );
      final retained = _header(_destination, 60, subject: 'd' * 300);
      await saveSync(_destination, [retained]);
      final before = _value(await store.loadSyncMailbox(_destination))!;
      expect(before.headers.single.id, retained.id);
      final plan = _plan();
      final receipt = await finish(plan, await begin(plan));

      expect(receipt.report.confirmedCount, 1);
      expect(receipt.identityTransitions.single.cacheProjected, isFalse);
      final after = _value(await store.loadSyncMailbox(_destination))!;
      expect(after.headers.single.id, retained.id);
      expect(after.mailbox.displayName, 'L' * 250);
      expect(after.revision, before.revision);
      expect(
        _value(await store.loadMailboxView(_source))!.revision,
        sourceView.revision,
      );
      expect(
        _value(await store.loadMailboxView(_destination))!.revision,
        destinationView.revision,
      );
    },
  );

  for (final quota in [4500, 100000]) {
    test(
      'optional projection respects account quota $quota while preserving acknowledgement',
      () async {
        await reopen(limits: MailStoreLimits(maxAccountBytes: quota));
        final sourceView = await saveView(_source, [
          _header(_source, 2, subject: 's' * 1000),
        ]);
        final destinationView = await saveView(_destination, const []);
        final plan = _plan();
        final receipt = await finish(plan, await begin(plan));
        final projected = quota == 100000;
        expect(receipt.report.confirmedCount, 1);
        expect(receipt.summary.complete, isTrue);
        expect(receipt.identityTransitions.single.cacheProjected, projected);
        final sourceAfter = _value(await store.loadMailboxView(_source))!;
        final destinationAfter = _value(
          await store.loadMailboxView(_destination),
        )!;
        expect(sourceAfter.headers.length, projected ? 0 : 1);
        expect(destinationAfter.headers.length, projected ? 1 : 0);
        if (!projected) {
          expect(sourceAfter.revision, sourceView.revision);
          expect(destinationAfter.revision, destinationView.revision);
          expect(_value(await store.readSyncSnapshot(_source)).revision, 0);
          expect(
            _value(await store.readSyncSnapshot(_destination)).revision,
            0,
          );
        }
        await reopen(limits: MailStoreLimits(maxAccountBytes: quota));
        final restored = _value(await store.loadFlagBatch(_account, plan.id))!;
        expect(restored.identityTransitions.single.cacheProjected, projected);
        expect(restored.report.confirmedCount, 1);
      },
    );
  }

  test(
    'outer storage failure rolls back successful projection and permits one settlement',
    () async {
      final sourceView = await saveView(_source, [_header(_source, 2)]);
      final destinationView = await saveView(_destination, const []);
      final plan = _plan();
      final handle = await begin(plan);
      failCommit = true;
      _problem(
        await store.recordFlagResult(handle, 0, _result(plan)),
        MailProblemCode.storageFailure,
      );
      failCommit = false;
      final failed = _value(await store.loadFlagBatch(_account, plan.id))!;
      expect(failed.identityTransitions, isEmpty);
      expect(failed.report.confirmedCount, 0);
      expect(
        _value(await store.loadMailboxView(_source))!.revision,
        sourceView.revision,
      );
      expect(
        _value(await store.loadMailboxView(_destination))!.revision,
        destinationView.revision,
      );
      expect(_value(await store.readSyncSnapshot(_source)).revision, 0);

      _value(await store.recordFlagResult(handle, 0, _result(plan)));
      final applied = _value(await store.loadMailboxView(_destination))!;
      _problem(
        await store.recordFlagResult(handle, 0, _result(plan)),
        MailProblemCode.conflict,
      );
      _value(
        await store.finishFlagBatch(
          handle,
          MailBulkFlagReport.restore(plan: plan, results: [_result(plan)]),
        ),
      );
      expect(
        _value(await store.loadMailboxView(_destination))!.revision,
        applied.revision,
      );
      expect(
        _value(
          await store.loadFlagBatch(_account, plan.id),
        )!.identityTransitions.length,
        1,
      );
    },
  );

  for (final substitute in ['operation', 'source', 'destination']) {
    test(
      'a different $substitute cannot substitute its valid receipt into the frozen owner',
      () async {
        await saveView(_source, [_header(_source, 2)]);
        await saveView(_destination, const []);
        final plan = _plan();
        final handle = await begin(plan);
        final other = MailBulkFlagPlan(
          id: substitute == 'operation' ? 'other' : plan.id,
          mailbox: _source,
          action: MailBulkFlagAction.move,
          destination: substitute == 'destination'
              ? MailMailboxId('Other', account: _account)
              : _destination,
          messages: [_header(_source, substitute == 'source' ? 3 : 2).remote],
        );
        _problem(
          await store.recordFlagResult(handle, 0, _result(other)),
          MailProblemCode.conflict,
        );
        expect(
          _value(
            await store.loadFlagBatch(_account, plan.id),
          )!.identityTransitions,
          isEmpty,
        );
        expect(
          (await finish(
            plan,
            handle,
          )).identityTransitions.single.cacheProjected,
          isTrue,
        );
      },
    );
  }

  test(
    'an opaque identity receipt must retain the frozen source folder',
    () async {
      final account = MailAccountId('ews', profile: _profile);
      final source = MailMailboxId('Source', account: account);
      final destination = MailMailboxId('Target', account: account);
      final accountSession = MailAccountSession(account);
      _value(
        await store.createAccount(
          MailStoreAccount(
            id: account,
            provider: MailProviderKind.ews,
            displayName: 'EWS',
          ),
        ),
      );
      final sourceIdentity = MailOpaqueIdentity(
        account: account,
        provider: MailProviderKind.ews,
        value: 'source-id',
      );
      final plan = MailBulkFlagPlan(
        id: 'opaque-move',
        mailbox: source,
        action: MailBulkFlagAction.move,
        destination: destination,
        messages: [sourceIdentity],
      );
      final handle = _value(
        await store.createFlagBatch(
          plan,
          subjects: const ['Source'],
          lease: accountSession.begin(),
        ),
      );
      _value(
        await store.beginFlagAttempt(handle, 0, lease: accountSession.begin()),
      );
      final transition = MailMoveIdentityTransition(
        operationId: plan.operationAt(0).id,
        source: sourceIdentity,
        sourceMailbox: MailMailboxId('Wrong', account: account),
        destination: MailOpaqueIdentity(
          account: account,
          provider: MailProviderKind.ews,
          value: 'target-id',
        ),
        destinationMailbox: destination,
        destinationMessageId: MailMessageId('target-local'),
      );
      _problem(
        await store.recordFlagResult(
          handle,
          0,
          _result(plan, transition: transition),
        ),
        MailProblemCode.conflict,
      );
      expect(
        _value(
          await store.loadFlagBatch(account, plan.id),
        )!.identityTransitions,
        isEmpty,
      );
    },
  );

  test(
    'another repository cannot use the dispatch owner to record a receipt',
    () async {
      await saveView(_source, [_header(_source, 2)]);
      await saveView(_destination, const []);
      final plan = _plan();
      final handle = await begin(plan);
      final other = await open(
        database: File('${directory.path}/other.sqlite3'),
      );
      try {
        _problem(
          await other.recordFlagResult(handle, 0, _result(plan)),
          MailProblemCode.conflict,
        );
        expect(
          _value(
            await store.loadFlagBatch(_account, plan.id),
          )!.identityTransitions,
          isEmpty,
        );
      } finally {
        await other.close();
      }
      expect(
        (await finish(plan, handle)).identityTransitions.single.cacheProjected,
        isTrue,
      );
    },
  );
}
