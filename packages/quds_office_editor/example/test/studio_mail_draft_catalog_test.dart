import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store_native.dart';
import 'package:quds_office_studio/studio_mail_draft.dart';
import 'package:quds_office_studio/studio_mail_draft_store.dart';
import 'package:quds_office_studio/studio_mail_draft_store_native.dart';

const _sender = 'writer@example.test';

StudioMailDraftAccount _identity([String sender = _sender]) =>
    StudioMailDraftAccount(
      provider: 'imap',
      endpoint: 'imaps://imap.example.test:993',
      login: sender,
      sender: sender,
    );

StudioMailDraft _draft(String subject, {StudioMailAttachments? attachments}) =>
    StudioMailDraft(
      to: 'recipient@example.test',
      cc: 'visible@example.test',
      bcc: 'hidden@example.test',
      subject: subject,
      body: 'Body $subject',
      attachments: attachments ?? const StudioMailAttachments.empty(),
    );

Matcher _problem(MailProblemCode code) => isA<StudioMailDraftStoreException>()
    .having((error) => error.code, 'code', code);

T _value<T>(MailResult<T> result) {
  expect(result, isA<MailSuccess<T>>());
  return (result as MailSuccess<T>).value;
}

void main() {
  late Directory directory;
  final opened = <StudioMailDraftStore>[];

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('studio-mail-catalog-');
  });

  tearDown(() async {
    for (final store in opened.reversed) {
      await store.close();
    }
    opened.clear();
    await directory.delete(recursive: true);
  });

  Future<SqliteStudioMailDraftStore> open({
    StudioMailDraftAccount? identity,
    MailStoreFaultInjector? fault,
  }) async {
    final store = await openStudioMailDraftStore(
      identity ?? _identity(),
      appDirectory: directory,
      faultInjector: fault,
    );
    opened.add(store);
    await store.load();
    return store as SqliteStudioMailDraftStore;
  }

  Future<({SqliteStudioMailDraftStore store, SqliteMailRepository repository})>
  openRepository() async {
    final identity = _identity();
    final repository = _value(
      await openNativeMailStore(
        appDirectory: directory,
        profile: identity.profile,
      ),
    );
    _value(
      await repository.createAccount(
        MailStoreAccount(
          id: identity.account,
          provider: identity.provider,
          displayName: 'Catalog fixture',
        ),
      ),
    );
    addTearDown(repository.close);
    final store = SqliteStudioMailDraftStore(
      repository: repository,
      account: identity.account,
    );
    opened.add(store);
    await store.load();
    return (store: store, repository: repository);
  }

  test(
    'legacy and multiple new drafts survive file reopen independently',
    () async {
      final first = await open();
      await first.save(_draft('legacy'), submissionUncertain: true);
      final legacyId = first.selectedDraftId;
      expect(legacyId, SqliteStudioMailDraftStore.draftId);
      await first.createDraft(_draft('second'));
      final secondId = first.selectedDraftId;
      await first.createDraft(_draft('third'));
      expect(first.selectedDraftId, isNot(secondId));
      await first.close();
      final restored = await open();
      expect((await restored.load())!.draft.subject, 'legacy');
      final page = await restored.listDrafts();
      expect(page.drafts, hasLength(3));
      expect(page.nextAfterId, isNull);
      final selected = await restored.selectDraft(
        page.drafts.singleWhere((item) => item.id == secondId),
      );
      expect(selected.draft.subject, 'second');
      expect(selected.submissionUncertain, isFalse);
      expect(restored.selectedDraftId, secondId);
      final legacy = await restored.selectDraft(
        page.drafts.singleWhere((item) => item.id == legacyId),
      );
      expect(legacy.submissionUncertain, isTrue);
    },
  );

  test('an explicitly created blank draft remains a visible draft', () async {
    final store = await open();
    const blank = StudioMailDraft(to: '', subject: '', body: '');
    final snapshot = await store.createDraft(blank);
    expect(snapshot.draft.to, isEmpty);
    final summary = (await store.listDrafts()).drafts.single;
    expect(summary.subject, isEmpty);
    expect(summary.to, isEmpty);
    expect((await store.selectDraft(summary)).draft.body, isEmpty);
    expect(await store.load(), isNotNull);
  });

  test(
    'attachment snapshots and uncertain markers belong to each draft',
    () async {
      final store = await open();
      final bytes = Uint8List.fromList([0, 13, 128, 255]);
      final attached = _draft(
        'files',
        attachments: StudioMailAttachments.from([
          StudioMailAttachment(name: 'copy.pdf', bytes: bytes),
        ]),
      );
      await store.createDraft(attached);
      final filesId = store.selectedDraftId;
      await store.save(attached, submissionUncertain: true);
      bytes.fillRange(0, bytes.length, 42);
      await store.createDraft(_draft('safe'));
      await store.save(_draft('safe edited'), submissionUncertain: false);
      final page = await store.listDrafts();
      expect(
        page.drafts
            .singleWhere((item) => item.id != filesId)
            .submissionUncertain,
        isFalse,
      );
      final summary = page.drafts.singleWhere((item) => item.id == filesId);
      expect(summary.attachmentCount, 1);
      expect(summary.bcc, 'hidden@example.test');
      final restored = await store.selectDraft(summary);
      expect(restored.submissionUncertain, isTrue);
      expect(restored.draft.attachments.items.single.content.copyBytes(), [
        0,
        13,
        128,
        255,
      ]);
      await store.save(restored.draft, submissionUncertain: false);
      expect((await store.load())!.submissionUncertain, isTrue);
    },
  );

  test(
    'discarding an unselected draft preserves selected uncertainty',
    () async {
      final store = await open();
      await store.createDraft(_draft('remove'));
      final removed = (await store.listDrafts()).drafts.single;
      await store.createDraft(_draft('keep'));
      await store.save(_draft('keep'), submissionUncertain: true);
      final keepId = store.selectedDraftId;
      final epoch = store.selectionEpoch;
      await store.discardDraft(removed);
      expect(store.selectedDraftId, keepId);
      expect(store.selectionEpoch, epoch);
      expect((await store.load())!.submissionUncertain, isTrue);
      expect((await store.listDrafts()).drafts.single.id, keepId);
      await expectLater(
        store.selectDraft(removed),
        throwsA(_problem(MailProblemCode.conflict)),
      );
    },
  );

  test(
    'listed revisions protect selection and discard from newer edits',
    () async {
      final store = await open();
      await store.createDraft(_draft('old'));
      final stale = (await store.listDrafts()).drafts.single;
      await store.save(_draft('new'), submissionUncertain: false);
      final epoch = store.selectionEpoch;
      await expectLater(
        store.selectDraft(stale),
        throwsA(_problem(MailProblemCode.conflict)),
      );
      await expectLater(
        store.discardDraft(stale),
        throwsA(_problem(MailProblemCode.conflict)),
      );
      expect(store.selectionEpoch, epoch);
      expect((await store.load())!.draft.subject, 'new');
    },
  );

  test(
    'a foreign account summary cannot select or discard matching legacy ID',
    () async {
      final first = await open();
      await first.save(_draft('first'), submissionUncertain: false);
      final foreign = (await first.listDrafts()).drafts.single;
      final other = await open(identity: _identity('other@example.test'));
      await other.save(_draft('second'), submissionUncertain: false);
      expect(other.selectedDraftId, foreign.id);
      await expectLater(
        other.selectDraft(foreign),
        throwsA(_problem(MailProblemCode.permissionDenied)),
      );
      await expectLater(
        other.discardDraft(foreign),
        throwsA(_problem(MailProblemCode.permissionDenied)),
      );
      expect((await other.load())!.draft.subject, 'second');
    },
  );

  test(
    'writes queued behind selection never land in the newly selected draft',
    () async {
      final store = await open();
      await store.createDraft(_draft('A'));
      final a = (await store.listDrafts()).drafts.single;
      await store.createDraft(_draft('B'));
      final b = (await store.listDrafts()).drafts.singleWhere(
        (item) => item.id != a.id,
      );
      await store.selectDraft(a);
      final change = store.selectDraft(b);
      final stale = expectLater(
        store.save(_draft('late A'), submissionUncertain: false),
        throwsA(_problem(MailProblemCode.staleOperation)),
      );
      await change;
      await stale;
      expect((await store.load())!.draft.subject, 'B');
      expect((await store.selectDraft(a)).draft.subject, 'A');
    },
  );

  test('A to B to A still invalidates an old queued operation epoch', () async {
    final store = await open();
    await store.createDraft(_draft('A'));
    final a = (await store.listDrafts()).drafts.single;
    await store.createDraft(_draft('B'));
    final b = (await store.listDrafts()).drafts.singleWhere(
      (item) => item.id != a.id,
    );
    await store.selectDraft(a);
    final first = store.selectDraft(b);
    final second = store.selectDraft(a);
    final stale = expectLater(
      store.clear(),
      throwsA(_problem(MailProblemCode.staleOperation)),
    );
    await first;
    await second;
    await stale;
    expect(store.selectedDraftId, a.id);
    expect((await store.load())!.draft.subject, 'A');
  });

  test(
    'failed create and discard leave the previous selected revision intact',
    () async {
      var fail = false;
      final store = await open(
        fault: (point) {
          if (fail && point == MailStoreCheckpoint.afterDraftBlobs) {
            throw StateError('injected failure');
          }
        },
      );
      await store.createDraft(_draft('keep'));
      await store.save(_draft('keep'), submissionUncertain: true);
      final summary = (await store.listDrafts()).drafts.single;
      final epoch = store.selectionEpoch;
      fail = true;
      await expectLater(
        store.createDraft(_draft('failed')),
        throwsA(isA<StudioMailDraftStoreException>()),
      );
      await expectLater(
        store.discardDraft(summary),
        throwsA(isA<StudioMailDraftStoreException>()),
      );
      fail = false;
      expect(store.selectedDraftId, summary.id);
      expect(store.selectionEpoch, epoch);
      expect(
        (await store.listDrafts()).drafts.single.revision,
        summary.revision,
      );
      expect((await store.load())!.submissionUncertain, isTrue);
    },
  );

  test(
    'selected draft queue transfer retains another draft and frozen identity',
    () async {
      final store = await open();
      await store.createDraft(_draft('keep'));
      await store.save(_draft('keep'), submissionUncertain: true);
      final keep = (await store.listDrafts()).drafts.single;
      await store.createDraft(_draft('queue'));
      final sourceId = store.selectedDraftId;
      final sourceRevision = (await store.listDrafts()).drafts
          .singleWhere((item) => item.id == sourceId)
          .revision;
      final queued = await store.enqueueOutbox(_draft('queue'), _sender);
      expect(queued.prepared.draftId, sourceId);
      expect(queued.prepared.draftRevision, sourceRevision + 1);
      expect(queued.priorSubmissionUncertain, isFalse);
      expect(await store.load(), isNull);
      expect((await store.listDrafts()).drafts.single.id, keep.id);
      expect((await store.selectDraft(keep)).submissionUncertain, isTrue);
      final wire = queued.prepared.wire.sha256;
      await store.save(_draft('keep edited'), submissionUncertain: false);
      expect((await store.loadOutbox()).single.prepared.wire.sha256, wire);
      expect((await store.loadOutbox()).single.prepared.draftId, sourceId);
    },
  );

  test(
    'uncertain selected draft transfers only its own guard to outbox',
    () async {
      final store = await open();
      await store.createDraft(_draft('uncertain'));
      await store.save(_draft('uncertain'), submissionUncertain: true);
      final uncertain = (await store.listDrafts()).drafts.single;
      await store.createDraft(_draft('safe'));
      await store.selectDraft(uncertain);
      final queued = await store.enqueueOutbox(_draft('uncertain'), _sender);
      expect(queued.priorSubmissionUncertain, isTrue);
      expect(queued.canBeginAttempt, isFalse);
      final remaining = (await store.listDrafts()).drafts.single;
      expect(remaining.subject, 'safe');
      expect(remaining.submissionUncertain, isFalse);
    },
  );

  test(
    'catalog discard tombstone rejects a stale independent adapter save',
    () async {
      final pair = await openRepository();
      final first = pair.store;
      await first.createDraft(_draft('original'));
      final summary = (await first.listDrafts()).drafts.single;
      final second = SqliteStudioMailDraftStore(
        repository: pair.repository,
        account: first.account,
      );
      opened.add(second);
      await second.selectDraft(summary);
      await first.discardDraft(summary);
      await expectLater(
        second.save(_draft('stale'), submissionUncertain: false),
        throwsA(_problem(MailProblemCode.conflict)),
      );
      expect((await first.listDrafts()).drafts, isEmpty);
      expect(await first.load(), isNull);
      expect(await second.load(), isNull);
    },
  );

  test('100 draft limit also applies to a legacy empty selection', () async {
    final pair = await openRepository();
    final store = pair.store;
    for (var index = 0; index < SqliteStudioMailDraftStore.maxDrafts; index++) {
      _value(
        await pair.repository.saveDraft(
          MailDraft(
            id: 'existing-${index.toString().padLeft(3, '0')}',
            account: store.account,
            revision: 0,
            envelope: MailEnvelope(subject: 'Existing $index'),
            body: const MailBody(plainText: ''),
            editorState: MailDraftEditorState(),
          ),
          expectedRevision: null,
        ),
      );
    }
    await expectLater(
      store.save(_draft('101'), submissionUncertain: false),
      throwsA(_problem(MailProblemCode.quotaExceeded)),
    );
    await expectLater(
      store.createDraft(_draft('101')),
      throwsA(_problem(MailProblemCode.quotaExceeded)),
    );
    expect(await store.load(), isNull);
    final page = await store.listDrafts();
    expect(page.drafts, hasLength(100));
    await store.discardDraft(page.drafts.first);
    await store.save(_draft('replacement'), submissionUncertain: false);
    expect((await store.listDrafts()).drafts, hasLength(100));
    expect((await store.load())!.draft.subject, 'replacement');
  });

  test(
    'queueing a selected draft does not reopen a cleared stale epoch',
    () async {
      final store = await open();
      await store.createDraft(_draft('queued'));
      final transfer = store.enqueueOutbox(_draft('queued'), _sender);
      final stale = expectLater(
        store.save(_draft('late autosave'), submissionUncertain: false),
        throwsA(_problem(MailProblemCode.staleOperation)),
      );
      await transfer;
      await stale;
      expect(await store.load(), isNull);
      expect((await store.listDrafts()).drafts, isEmpty);
      expect(await store.loadOutbox(), hasLength(1));
    },
  );
}
