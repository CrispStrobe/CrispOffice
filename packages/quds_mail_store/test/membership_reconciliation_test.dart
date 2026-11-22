@TestOn('vm')
library;

import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:test/test.dart';

final _profile = MailProfileId('membership-check', hostId: 'mail-tests');
final _time = DateTime.utc(2026, 11, 22);
const _uncertain = MailProblem(
  MailProblemCode.providerFailure,
  mutationMayHaveOccurred: true,
  retryAfter: Duration(seconds: 17),
);

MailAccountId _account(MailProviderKind provider) =>
    MailAccountId(provider.name, profile: _profile);

MailBulkFlagPlan _plan({
  String id = 'membership',
  MailProviderKind provider = MailProviderKind.imap,
  MailBulkFlagAction action = MailBulkFlagAction.move,
}) {
  final account = _account(provider);
  final mailbox = MailMailboxId('INBOX', account: account);
  return MailBulkFlagPlan(
    id: id,
    mailbox: mailbox,
    action: action,
    destination: action == MailBulkFlagAction.move
        ? MailMailboxId('destination', account: account)
        : null,
    messages: [
      provider == MailProviderKind.imap
          ? MailImapIdentity(mailbox: mailbox, uidValidity: 7, uid: 19)
          : MailOpaqueIdentity(
              account: account,
              provider: provider,
              value: 'exact-message',
            ),
    ],
  );
}

T _value<T>(MailResult<T> result) {
  expect(result, isA<MailSuccess<T>>());
  return (result as MailSuccess<T>).value;
}

void _problem<T>(MailResult<T> result, MailProblemCode code) {
  expect(result, isA<MailFailure<T>>());
  expect((result as MailFailure<T>).problem.code, code);
}

void main() {
  late Directory directory;
  late File file;
  late SqliteMailRepository store;
  final sessions = <MailAccountId, MailAccountSession>{};
  final registered = <MailAccountId>{};
  var now = _time;
  var failCommit = false;
  void Function()? beforeCommit;

  MailAccountSession session(MailAccountId account) =>
      sessions.putIfAbsent(account, () => MailAccountSession(account));

  Future<MailResult<SqliteMailRepository>> open({
    MailStoreLimits limits = const MailStoreLimits(),
  }) => SqliteMailRepository.open(
    executor: NativeDatabase(file),
    profile: _profile,
    clock: () => now,
    limits: limits,
    faultInjector: (point) {
      if (point != MailStoreCheckpoint.beforeCommit) return;
      beforeCommit?.call();
      if (failCommit) {
        throw const MailStoreStorageException(MailProblemCode.storageFailure);
      }
    },
  );

  Future<void> reopen({
    MailStoreLimits limits = const MailStoreLimits(),
  }) async {
    await store.close();
    store = _value(await open(limits: limits));
  }

  Future<MailStoredFlagBatch> load(MailBulkFlagPlan plan) async =>
      _value<MailStoredFlagBatch?>(
        await store.loadFlagBatch(plan.mailbox.account, plan.id),
      )!;

  Future<MailStoredFlagBatch> prepare(
    MailBulkFlagPlan plan, {
    MailBulkFlagOutcome outcome = MailBulkFlagOutcome.uncertain,
  }) async {
    final account = plan.mailbox.account;
    if (registered.add(account)) {
      _value(
        await store.createAccount(
          MailStoreAccount(
            id: account,
            provider: plan.provider,
            displayName: 'Account',
          ),
        ),
      );
    }
    final handle = _value(
      await store.createFlagBatch(
        plan,
        subjects: const ['Original subject'],
        lease: session(account).begin(),
      ),
    );
    if (outcome != MailBulkFlagOutcome.unattempted) {
      _value(
        await store.beginFlagAttempt(
          handle,
          0,
          lease: session(account).begin(),
        ),
      );
    }
    final result = MailBulkFlagItemResult.restore(
      operation: plan.operationAt(0),
      outcome: outcome,
      problem: outcome == MailBulkFlagOutcome.uncertain ? _uncertain : null,
    );
    if (outcome != MailBulkFlagOutcome.unattempted) {
      _value(await store.recordFlagResult(handle, 0, result));
    }
    _value(
      await store.finishFlagBatch(
        handle,
        MailBulkFlagReport.restore(
          plan: plan,
          results: [result],
          stopReason: outcome == MailBulkFlagOutcome.uncertain
              ? MailBulkFlagStopReason.uncertain
              : null,
          stopProblem: outcome == MailBulkFlagOutcome.uncertain
              ? _uncertain
              : null,
        ),
      ),
    );
    return load(plan);
  }

  Future<MailMembershipReconciliationHandle> begin(
    MailBulkFlagPlan plan,
    MailOperationLease lease, {
    bool Function()? isCurrent,
  }) async => _value<MailMembershipReconciliationHandle>(
    await store.beginMembershipReconciliation(
      plan.mailbox.account,
      plan.id,
      0,
      expectedRevision: (await load(plan)).summary.revision,
      lease: lease,
      isCurrent: isCurrent,
    ),
  );

  Future<MailStoredFlagBatch> record(
    MailBulkFlagPlan plan,
    MailMembershipObservation observation,
  ) async {
    final lease = session(plan.mailbox.account).begin();
    final handle = await begin(plan, lease);
    _value(
      await store.recordMembershipObservation(
        handle,
        observation,
        lease: lease,
      ),
    );
    return load(plan);
  }

  void unchangedReceipt(MailStoredFlagBatch before, MailStoredFlagBatch after) {
    expect(after.report.results.single.outcome, MailBulkFlagOutcome.uncertain);
    expect(after.report.results.single.problem!.code, _uncertain.code);
    expect(
      after.report.results.single.problem!.retryAfter,
      _uncertain.retryAfter,
    );
    expect(
      after.report.results.single.problem!.mutationMayHaveOccurred,
      isTrue,
    );
    expect(after.report.stopReason, before.report.stopReason);
    expect(after.subjects, before.subjects);
    expect(after.summary.uncertainCount, 1);
    expect(after.summary.unresolvedCount, 1);
    expect(after.summary.reconciledCount, 0);
    expect(after.resolutions, isEmpty);
    expect(after.summary.confirmedCount, 0);
    expect(after.summary.requiresRefresh, isTrue);
  }

  setUp(() async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    directory = await Directory.systemTemp.createTemp('mail-membership-check-');
    file = File('${directory.path}/mail.sqlite3');
    registered.clear();
    sessions.clear();
    now = _time;
    failCommit = false;
    beforeCommit = null;
    store = _value(await open());
  });
  tearDown(() async {
    for (final session in sessions.values) {
      session.dispose();
    }
    await store.close();
    await directory.delete(recursive: true);
  });

  for (final action in [MailBulkFlagAction.move, MailBulkFlagAction.delete]) {
    for (final state in ['present', 'deleted', 'missing', 'identityChanged']) {
      test(
        'IMAP $action $state evidence survives reopen without resolving history',
        () async {
          final plan = _plan(action: action);
          final before = await prepare(plan);
          final identity = plan.messages.single as MailImapIdentity;
          final observed = switch (state) {
            'present' || 'deleted' => MailMembershipObservation.imap(
              identity: identity,
              isDeleted: state == 'deleted',
            ),
            'missing' => MailMembershipObservation.missing(identity: identity),
            _ => MailMembershipObservation.identityChanged(identity: identity),
          };
          now = now.add(const Duration(seconds: 1));
          await record(plan, observed);
          await reopen();
          final after = await load(plan);
          unchangedReceipt(before, after);
          expect(after.summary.revision, before.summary.revision + 1);
          final evidence = after.membershipObservations.single;
          expect(evidence.index, 0);
          expect(evidence.checkedAt, now);
          expect(evidence.observation.identity, identity);
          expect(evidence.observation.kind, observed.kind);
          expect(evidence.observation.mailboxes, observed.mailboxes);
          expect(evidence.observation.isDeleted, observed.isDeleted);
          expect(
            _value(await store.clearCompletedFlagBatches(plan.mailbox.account)),
            0,
          );
          expect((await load(plan)).membershipObservations, hasLength(1));
        },
      );
    }
  }

  for (final provider in [
    MailProviderKind.gmail,
    MailProviderKind.graph,
    MailProviderKind.ews,
  ]) {
    for (final kind in ['present', 'deleted', 'missing']) {
      test(
        '$provider $kind exact folders persist with provider deletion semantics',
        () async {
          final plan = _plan(
            provider: provider,
            action: MailBulkFlagAction.delete,
          );
          final before = await prepare(plan);
          final identity = plan.messages.single as MailOpaqueIdentity;
          final deletion = MailMailboxId(
            provider == MailProviderKind.gmail
                ? 'TRASH'
                : 'resolved-deleted-folder',
            account: identity.account,
          );
          final observation = kind == 'missing'
              ? MailMembershipObservation.missing(identity: identity)
              : MailMembershipObservation.folders(
                  identity: identity,
                  mailboxes: [kind == 'deleted' ? deletion : plan.mailbox],
                  deletionMailbox: deletion,
                );
          await record(plan, observation);
          await reopen();
          final after = await load(plan);
          unchangedReceipt(before, after);
          final actual = after.membershipObservations.single.observation;
          expect(actual.kind, observation.kind);
          expect(actual.mailboxes, observation.mailboxes);
          expect(actual.deletionMailbox, observation.deletionMailbox);
          expect(actual.isDeleted, observation.isDeleted);
        },
      );
    }
  }

  test(
    'Unicode parent and deletion IDs retain exact units through SQLite reopen',
    () async {
      final plan = _plan(
        provider: MailProviderKind.graph,
        action: MailBulkFlagAction.delete,
      );
      await prepare(plan);
      final folder = MailMailboxId(
        '  📨 / e\u0301  ',
        account: plan.mailbox.account,
      );
      await record(
        plan,
        MailMembershipObservation.folders(
          identity: plan.messages.single as MailOpaqueIdentity,
          mailboxes: [folder],
          deletionMailbox: folder,
        ),
      );
      await reopen();
      final saved = (await load(
        plan,
      )).membershipObservations.single.observation;
      expect(saved.mailboxes.single.value.codeUnits, folder.value.codeUnits);
      expect(saved.deletionMailbox!.value.codeUnits, folder.value.codeUnits);
      expect(saved.isDeleted, isTrue);
    },
  );

  test(
    'repeat check replaces latest evidence and retires prior handle',
    () async {
      final plan = _plan();
      final original = await prepare(plan);
      final lease = session(plan.mailbox.account).begin();
      final oldHandle = await begin(plan, lease);
      final missing = MailMembershipObservation.missing(
        identity: plan.messages.single,
      );
      _value(
        await store.recordMembershipObservation(
          oldHandle,
          missing,
          lease: lease,
        ),
      );
      _problem(
        await store.recordMembershipObservation(
          oldHandle,
          missing,
          lease: lease,
        ),
        MailProblemCode.conflict,
      );
      now = now.add(const Duration(minutes: 1));
      final after = await record(
        plan,
        MailMembershipObservation.imap(
          identity: plan.messages.single as MailImapIdentity,
          isDeleted: true,
        ),
      );
      unchangedReceipt(original, after);
      expect(after.summary.revision, original.summary.revision + 2);
      expect(after.membershipObservations, hasLength(1));
      expect(after.membershipObservations.single.checkedAt, now);
      expect(after.membershipObservations.single.observation.isDeleted, isTrue);
    },
  );

  for (final substitute in ['uid', 'generation', 'account', 'lease', 'owner']) {
    test('rejects substituted $substitute authority', () async {
      final plan = _plan();
      final before = await prepare(plan);
      final lease = session(plan.mailbox.account).begin();
      final handle = await begin(plan, lease);
      final original = plan.messages.single as MailImapIdentity;
      final identity = switch (substitute) {
        'uid' => MailImapIdentity(
          mailbox: original.mailbox,
          uidValidity: 7,
          uid: 20,
        ),
        'generation' => MailImapIdentity(
          mailbox: original.mailbox,
          uidValidity: 8,
          uid: 19,
        ),
        'account' => MailImapIdentity(
          mailbox: MailMailboxId(
            'INBOX',
            account: _account(MailProviderKind.graph),
          ),
          uidValidity: 7,
          uid: 19,
        ),
        _ => original,
      };
      if (substitute == 'owner') await reopen();
      _problem(
        await store.recordMembershipObservation(
          handle,
          MailMembershipObservation.missing(identity: identity),
          lease: substitute == 'lease'
              ? session(plan.mailbox.account).begin()
              : lease,
        ),
        MailProblemCode.conflict,
      );
      final after = await load(plan);
      expect(after.summary.revision, before.summary.revision);
      expect(after.membershipObservations, isEmpty);
    });
  }

  for (final stale in [
    'session',
    'cancel',
    'view',
    'commit view',
    'commit cancellation',
  ]) {
    test('$stale invalidation cannot persist late evidence', () async {
      final plan = _plan();
      final before = await prepare(plan);
      final cancellation = MailCancellationSource();
      var current = true;
      final lease = session(
        plan.mailbox.account,
      ).begin(cancellation: cancellation.token);
      final handle = await begin(plan, lease, isCurrent: () => current);
      switch (stale) {
        case 'session':
          session(plan.mailbox.account).invalidate();
        case 'cancel':
          cancellation.cancel();
        case 'view':
          current = false;
        case 'commit view':
          beforeCommit = () => current = false;
        case 'commit cancellation':
          beforeCommit = () => cancellation.cancel();
      }
      _problem(
        await store.recordMembershipObservation(
          handle,
          MailMembershipObservation.missing(identity: plan.messages.single),
          lease: lease,
        ),
        stale.contains('cancel')
            ? MailProblemCode.cancelled
            : MailProblemCode.staleOperation,
      );
      beforeCommit = null;
      final after = await load(plan);
      expect(after.summary.revision, before.summary.revision);
      expect(after.membershipObservations, isEmpty);
    });
  }

  for (final transition in ['cache', 'empty sync', 'other account']) {
    test('$transition commit fences an earlier observation', () async {
      final plan = _plan();
      await prepare(plan);
      final lease = session(plan.mailbox.account).begin();
      final handle = await begin(plan, lease);
      switch (transition) {
        case 'cache':
          _value(
            await store.saveMailboxView(
              MailMailbox(id: plan.mailbox, displayName: 'Inbox'),
              const [],
              expectedRevision: null,
              hasMore: false,
              lease: lease,
            ),
          );
        case 'empty sync':
          _value(
            await store.commitSyncPage(
              MailSyncPage(
                mailbox: plan.mailbox,
                upserts: const [],
                tombstones: const [],
                next: MailCursor(mailbox: plan.mailbox, value: 'next'),
                hasMore: false,
              ),
              expectedCursor: null,
              lease: lease,
            ),
          );
        case 'other account':
          _value(
            await store.createAccount(
              MailStoreAccount(
                id: _account(MailProviderKind.graph),
                provider: MailProviderKind.graph,
                displayName: 'Other',
              ),
            ),
          );
      }
      _problem(
        await store.recordMembershipObservation(
          handle,
          MailMembershipObservation.missing(identity: plan.messages.single),
          lease: lease,
        ),
        MailProblemCode.conflict,
      );
      expect((await load(plan)).membershipObservations, isEmpty);
    });
  }

  test(
    'observation preserves cached headers, sync membership, body and draft',
    () async {
      final plan = _plan(action: MailBulkFlagAction.delete);
      await prepare(plan);
      final lease = session(plan.mailbox.account).begin();
      final header = MailHeaderRecord(
        id: MailMessageId('retained'),
        remote: plan.messages.single,
        envelope: MailEnvelope(subject: 'Cached subject'),
        flags: const MailMessageFlags(isRead: true),
      );
      final view = _value(
        await store.saveMailboxView(
          MailMailbox(id: plan.mailbox, displayName: 'Inbox'),
          [header],
          expectedRevision: null,
          hasMore: true,
          lease: lease,
        ),
      );
      _value(
        await store.commitSyncPage(
          MailSyncPage(
            mailbox: plan.mailbox,
            upserts: [header],
            tombstones: const [],
            next: MailCursor(mailbox: plan.mailbox, value: 'retained-cursor'),
            hasMore: true,
          ),
          expectedCursor: null,
          lease: lease,
        ),
      );
      _value(
        await store.cacheMessage(
          plan.mailbox.account,
          header.id,
          MailMessage(
            raw: MailBytes(Uint8List.fromList([70, 114, 111, 109, 58, 13, 10])),
            envelope: header.envelope,
            body: const MailBody(plainText: 'Retained body text'),
            localId: header.id,
            remoteIdentity: header.remote,
          ),
          lease: lease,
        ),
      );
      _value(
        await store.saveDraft(
          MailDraft(
            id: 'draft',
            account: plan.mailbox.account,
            revision: 1,
            envelope: MailEnvelope(subject: 'Draft subject'),
            body: const MailBody(plainText: 'Draft text'),
          ),
          expectedRevision: null,
        ),
      );
      final beforeDb = sqlite.sqlite3.open(file.path);
      final before = <String, Object?>{
        for (final table in [
          'messages',
          'mailbox_views',
          'mailbox_view_members',
          'memberships',
          'mailbox_sync_state',
          'cursors',
          'drafts',
          'cached_messages',
          'blobs',
          'blob_refs',
        ])
          table: beforeDb
              .select('SELECT * FROM $table')
              .map((row) => Map<String, Object?>.from(row))
              .toList(),
      };
      beforeDb.close();
      await record(
        plan,
        MailMembershipObservation.imap(
          identity: plan.messages.single as MailImapIdentity,
          isDeleted: true,
        ),
      );
      final afterDb = sqlite.sqlite3.open(file.path);
      for (final table in before.keys) {
        expect(
          afterDb
              .select('SELECT * FROM $table')
              .map((row) => Map<String, Object?>.from(row))
              .toList(),
          before[table],
        );
      }
      afterDb.close();
      expect(
        _value(await store.loadMailboxView(plan.mailbox))!.summary.capturedAt,
        view.summary.capturedAt,
      );
    },
  );

  for (final phase in ['begin', 'record']) {
    test('backward clock at $phase cannot backdate evidence', () async {
      final plan = _plan();
      final before = await prepare(plan);
      final lease = session(plan.mailbox.account).begin();
      final handle = phase == 'record' ? await begin(plan, lease) : null;
      now = now.subtract(const Duration(seconds: 1));
      if (handle == null) {
        _problem(
          await store.beginMembershipReconciliation(
            plan.mailbox.account,
            plan.id,
            0,
            expectedRevision: before.summary.revision,
            lease: lease,
          ),
          MailProblemCode.conflict,
        );
      } else {
        _problem(
          await store.recordMembershipObservation(
            handle,
            MailMembershipObservation.missing(identity: plan.messages.single),
            lease: lease,
          ),
          MailProblemCode.conflict,
        );
      }
      expect((await load(plan)).membershipObservations, isEmpty);
    });
  }

  test(
    'failed replacement rolls back evidence, timestamp and revision',
    () async {
      final plan = _plan();
      await prepare(plan);
      final prior = await record(
        plan,
        MailMembershipObservation.missing(identity: plan.messages.single),
      );
      final lease = session(plan.mailbox.account).begin();
      final handle = await begin(plan, lease);
      now = now.add(const Duration(minutes: 1));
      failCommit = true;
      _problem(
        await store.recordMembershipObservation(
          handle,
          MailMembershipObservation.imap(
            identity: plan.messages.single as MailImapIdentity,
            isDeleted: false,
          ),
          lease: lease,
        ),
        MailProblemCode.storageFailure,
      );
      failCommit = false;
      await reopen();
      final after = await load(plan);
      expect(after.summary.revision, prior.summary.revision);
      expect(
        after.membershipObservations.single.checkedAt,
        prior.membershipObservations.single.checkedAt,
      );
      expect(
        after.membershipObservations.single.observation.kind,
        MailMembershipObservationKind.missing,
      );
    },
  );

  for (final action in MailBulkFlagAction.values.where(
    (value) => value.isFlagAction,
  )) {
    test('$action cannot use membership observation authority', () async {
      final plan = _plan(action: action);
      final receipt = await prepare(plan);
      _problem(
        await store.beginMembershipReconciliation(
          plan.mailbox.account,
          plan.id,
          0,
          expectedRevision: receipt.summary.revision,
          lease: session(plan.mailbox.account).begin(),
        ),
        MailProblemCode.unsupported,
      );
    });
  }

  for (final outcome in [
    MailBulkFlagOutcome.confirmed,
    MailBulkFlagOutcome.unattempted,
  ]) {
    test('$outcome item cannot acquire uncertain-membership check', () async {
      final plan = _plan();
      final receipt = await prepare(plan, outcome: outcome);
      _problem(
        await store.beginMembershipReconciliation(
          plan.mailbox.account,
          plan.id,
          0,
          expectedRevision: receipt.summary.revision,
          lease: session(plan.mailbox.account).begin(),
        ),
        MailProblemCode.conflict,
      );
    });
  }

  test(
    'metadata quota refuses a new observation without changing receipt',
    () async {
      final plan = _plan(
        provider: MailProviderKind.gmail,
        action: MailBulkFlagAction.delete,
      );
      final before = await prepare(plan);
      await reopen(limits: const MailStoreLimits(maxMetadataCodeUnits: 128));
      final lease = session(plan.mailbox.account).begin();
      final handle = await begin(plan, lease);
      _problem(
        await store.recordMembershipObservation(
          handle,
          MailMembershipObservation.folders(
            identity: plan.messages.single as MailOpaqueIdentity,
            mailboxes: [
              MailMailboxId('a' * 200, account: plan.mailbox.account),
            ],
          ),
          lease: lease,
        ),
        MailProblemCode.quotaExceeded,
      );
      final after = await load(plan);
      expect(after.summary.revision, before.summary.revision);
      expect(after.membershipObservations, isEmpty);
    },
  );

  test(
    'account removal cascades observation data without affecting another account',
    () async {
      final first = _plan();
      final second = _plan(provider: MailProviderKind.graph);
      await prepare(first);
      await prepare(second);
      await record(
        first,
        MailMembershipObservation.missing(identity: first.messages.single),
      );
      await record(
        second,
        MailMembershipObservation.missing(identity: second.messages.single),
      );
      _value(await store.removeLocalAccount(first.mailbox.account));
      final db = sqlite.sqlite3.open(file.path);
      expect(
        db
            .select('SELECT account FROM membership_item_observations')
            .map((row) => row['account']),
        [second.mailbox.account.value],
      );
      expect(db.select('PRAGMA foreign_key_check'), isEmpty);
      db.close();
      expect((await load(second)).membershipObservations, hasLength(1));
    },
  );

  for (final corruption in [
    'wrong mailbox',
    'duplicate label',
    'deleted mismatch',
    'invalid json',
  ]) {
    test('$corruption retained evidence is refused without mutation', () async {
      final gmail = corruption == 'duplicate label';
      final plan = _plan(
        provider: gmail ? MailProviderKind.gmail : MailProviderKind.imap,
        action: MailBulkFlagAction.delete,
      );
      await prepare(plan);
      await record(
        plan,
        gmail
            ? MailMembershipObservation.folders(
                identity: plan.messages.single as MailOpaqueIdentity,
                mailboxes: [plan.mailbox],
              )
            : MailMembershipObservation.imap(
                identity: plan.messages.single as MailImapIdentity,
                isDeleted: false,
              ),
      );
      final db = sqlite.sqlite3.open(file.path);
      switch (corruption) {
        case 'wrong mailbox':
          db.execute('UPDATE membership_item_observations SET mailboxes=?', [
            '["other"]',
          ]);
        case 'duplicate label':
          db.execute('UPDATE membership_item_observations SET mailboxes=?', [
            '["INBOX","INBOX"]',
          ]);
        case 'deleted mismatch':
          db.execute('UPDATE membership_item_observations SET is_deleted=NULL');
        case 'invalid json':
          db.execute('UPDATE membership_item_observations SET mailboxes=?', [
            'bad json',
          ]);
      }
      db.close();
      _problem(
        await store.loadFlagBatch(plan.mailbox.account, plan.id),
        MailProblemCode.storageFailure,
      );
    });
  }
}
