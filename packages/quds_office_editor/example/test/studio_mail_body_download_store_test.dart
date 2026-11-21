import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store_native.dart';
import 'package:quds_office_studio/studio_mail_body_download.dart';
import 'package:quds_office_studio/studio_mail_draft.dart';
import 'package:quds_office_studio/studio_mail_draft_store.dart';
import 'package:quds_office_studio/studio_mail_draft_store_native.dart';
import 'package:quds_office_studio/studio_mail_mailbox_store.dart';

T _value<T>(MailResult<T> result) {
  expect(result, isA<MailSuccess<T>>());
  return (result as MailSuccess<T>).value;
}

StudioMailDraftAccount _identity(MailProviderKind kind) =>
    StudioMailDraftAccount(
      provider: kind.name,
      endpoint: kind == MailProviderKind.imap
          ? 'imaps://mail.example.test:993'
          : 'https://mail.example.test/${kind.name}',
      login: 'reader@example.test',
      sender: 'reader@example.test',
    );

MailMessage _message(MailHeaderRecord header, {int? rawBytes}) => MailMessage(
  raw: MailBytes(
    rawBytes == null
        ? Uint8List.fromList([0, 13, 10, 128, 255])
        : Uint8List(rawBytes),
  ),
  envelope: header.envelope,
  body: const MailBody(
    plainText: 'Retained offline ä مرحبا 😀',
    html: '<p>Retained offline</p>',
    plainPartPath: '1.1',
    htmlPartPath: '1.2',
  ),
  attachments: [
    MailAttachment(
      partPath: '2',
      mediaType: 'application/octet-stream',
      displayName: 'original.bin',
      content: MailBytes(Uint8List.fromList([0, 1, 2, 128, 255])),
      contentId: 'retained-attachment',
      declaredSize: 5,
      inline: true,
    ),
  ],
  // A provider owns its transient/local projection ID. The runner must rebind
  // only after validating the exact provider identity against a synced header.
  localId: MailMessageId('provider-local'),
  remoteIdentity: header.remote,
);

final class _Provider extends Fake implements MailProvider {
  _Provider(this.account, List<MailHeaderRecord> headers)
    : messages = {
        for (final header in headers) header.remote: _message(header),
      };

  @override
  final MailAccountId account;
  final Map<MailRemoteIdentity, MailMessage> messages;
  final List<MailRemoteIdentity> requests = [];
  void Function()? afterFetch;

  @override
  Future<MailResult<MailMessage>> fetchMessage(
    MailRemoteIdentity identity, {
    required MailReadBudget budget,
    required MailOperationLease lease,
  }) async {
    lease.checkCurrent();
    requests.add(identity);
    afterFetch?.call();
    return MailSuccess(messages[identity]!);
  }
}

final class _Protected {
  const _Protected(this.outbox, this.draft);
  final MailOutboxEntry outbox;
  final StudioMailDraftSummary draft;
}

Future<_Protected> _protectOutgoing(SqliteStudioMailDraftStore owner) async {
  await owner.load();
  final queued = await owner.enqueueOutbox(
    StudioMailDraft(
      to: 'recipient@example.test',
      bcc: 'private@example.test',
      subject: 'Keep queued MIME',
      body: 'Queued before an offline download.',
    ),
    'reader@example.test',
  );
  await owner.save(
    StudioMailDraft(
      to: 'recipient@example.test',
      subject: 'Keep draft',
      body: 'Independent unsent editor state.',
      attachments: StudioMailAttachments.from([
        StudioMailAttachment(
          name: 'draft.bin',
          bytes: Uint8List.fromList([9, 8, 7]),
        ),
      ]),
    ),
    submissionUncertain: true,
  );
  return _Protected(queued, (await owner.listDrafts()).drafts.single);
}

Future<void> _expectProtected(
  SqliteStudioMailDraftStore owner,
  _Protected expected,
) async {
  final draft = (await owner.load())!;
  expect(draft.draft.subject, 'Keep draft');
  expect(draft.draft.body, 'Independent unsent editor state.');
  expect(draft.submissionUncertain, isTrue);
  expect(draft.draft.attachments.items.single.content.bytes, [9, 8, 7]);
  final summary = (await owner.listDrafts()).drafts.single;
  expect(summary.id, expected.draft.id);
  expect(summary.revision, expected.draft.revision);
  final queued = (await owner.loadOutbox()).single;
  expect(queued.id, expected.outbox.id);
  expect(queued.state, MailOutboxState.queued);
  expect(queued.attemptNumber, 0);
  expect(queued.prepared.wireHash, expected.outbox.prepared.wireHash);
  expect(queued.prepared.wire.bytes, expected.outbox.prepared.wire.bytes);
  expect(
    queued.prepared.envelope.recipients,
    expected.outbox.prepared.envelope.recipients,
  );
}

void _expectMessage(
  MailMessage actual,
  MailMessage original,
  MailHeaderRecord header,
) {
  expect(actual.localId, header.id);
  expect(actual.remoteIdentity, header.remote);
  expect(actual.raw.bytes, original.raw.bytes);
  expect(actual.raw.sha256, original.raw.sha256);
  expect(actual.body.plainText, original.body.plainText);
  expect(actual.body.html, original.body.html);
  expect(actual.body.plainPartPath, original.body.plainPartPath);
  expect(actual.body.htmlPartPath, original.body.htmlPartPath);
  final attachment = actual.attachments.single;
  final originalAttachment = original.attachments.single;
  expect(attachment.content.bytes, originalAttachment.content.bytes);
  expect(attachment.content.sha256, originalAttachment.content.sha256);
  expect(attachment.partPath, originalAttachment.partPath);
  expect(attachment.mediaType, originalAttachment.mediaType);
  expect(attachment.displayName, originalAttachment.displayName);
  expect(attachment.contentId, originalAttachment.contentId);
  expect(attachment.declaredSize, originalAttachment.declaredSize);
  expect(attachment.inline, originalAttachment.inline);
}

void main() {
  late Directory directory;
  final owners = <SqliteStudioMailDraftStore>[];
  final sessions = <MailAccountSession>[];

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('mail-body-retention-');
  });

  tearDown(() async {
    for (final session in sessions) {
      session.dispose();
    }
    sessions.clear();
    for (final owner in owners.reversed) {
      await owner.close();
    }
    owners.clear();
    await directory.delete(recursive: true);
  });

  Future<SqliteStudioMailDraftStore> open(
    MailProviderKind kind, {
    MailStoreFaultInjector? fault,
    MailStoreLimits limits = const MailStoreLimits(),
  }) async {
    final owner =
        await openStudioMailDraftStore(
              _identity(kind),
              appDirectory: directory,
              faultInjector: fault,
              limits: limits,
            )
            as SqliteStudioMailDraftStore;
    owners.add(owner);
    return owner;
  }

  MailAccountSession sessionFor(MailAccountId account) {
    final session = MailAccountSession(account);
    sessions.add(session);
    return session;
  }

  Future<MailMailboxSyncSnapshot> seed(
    SqliteStudioMailDraftStore owner,
    MailProviderKind kind, {
    int count = 3,
  }) async {
    final store = owner.mailboxStore as StudioMailSyncStore;
    final mailbox = MailMailbox(
      id: MailMailboxId('inbox', account: owner.account),
      displayName: 'Inbox',
      isLabel: kind == MailProviderKind.gmail,
    );
    _value(await store.saveSyncMailbox(mailbox));
    final session = sessionFor(owner.account);
    _value(
      await store.commitSyncPage(
        MailSyncPage(
          mailbox: mailbox.id,
          upserts: [
            for (var number = 1; number <= count; number++)
              MailHeaderRecord(
                id: MailMessageId('provider-header-$number'),
                remote: kind == MailProviderKind.imap
                    ? MailImapIdentity(
                        mailbox: mailbox.id,
                        uidValidity: 7,
                        uid: number,
                      )
                    : MailOpaqueIdentity(
                        account: owner.account,
                        provider: kind,
                        value: 'remote-$number',
                      ),
                envelope: MailEnvelope(subject: 'Retained $number'),
                flags: MailMessageFlags(
                  isRead: number.isEven,
                  isFlagged: number.isOdd,
                ),
              ),
          ],
          tombstones: [],
          next: MailCursor(mailbox: mailbox.id, value: 'durable-checkpoint'),
          hasMore: true,
        ),
        expectedCursor: null,
        lease: session.begin(),
      ),
    );
    return _value<MailMailboxSyncSnapshot?>(
      await store.loadSyncMailbox(mailbox.id),
    )!;
  }

  Future<void> expectSyncUnchanged(
    SqliteStudioMailDraftStore owner,
    MailMailboxSyncSnapshot before,
  ) async {
    final store = owner.mailboxStore as StudioMailSyncStore;
    final after = _value(await store.loadSyncMailbox(before.mailbox.id))!;
    expect(after.revision, before.revision);
    expect(after.hasMore, before.hasMore);
    expect(after.headerCount, before.headerCount);
    expect(
      after.headers.map((header) => header.id),
      before.headers.map((header) => header.id),
    );
    expect(
      after.headers.map((header) => header.flags),
      before.headers.map((header) => header.flags),
    );
    expect(
      _value(await store.readCursor(before.mailbox.id))!.value,
      'durable-checkpoint',
    );
  }

  for (final kind in [
    MailProviderKind.imap,
    MailProviderKind.ews,
    MailProviderKind.gmail,
    MailProviderKind.graph,
  ]) {
    test(
      '${kind.name}: download survives restart with exact offline content and untouched outgoing state',
      () async {
        final owner = await open(kind);
        final outgoing = await _protectOutgoing(owner);
        final before = await seed(owner, kind);
        final provider = _Provider(owner.account, before.headers);
        final report = await MailBodyDownloadRunner(
          provider: provider,
          cache: StudioMailBodyDownloadCache(owner.mailboxStore),
          session: sessionFor(owner.account),
        ).run(mailbox: before.mailbox.id, headers: before.headers);
        expect(report.status, MailBodyDownloadStatus.completed);
        expect(report.downloaded, before.headers.length);
        expect(report.retainedBytes, greaterThan(0));
        expect(
          provider.requests,
          before.headers.map((header) => header.remote),
        );
        await expectSyncUnchanged(owner, before);
        await _expectProtected(owner, outgoing);
        await owner.close();

        final reopened = await open(kind);
        final offline = StudioMailBodyDownloadCache(reopened.mailboxStore);
        // Reading every retained part uses only the native store after reopen.
        // No provider is constructed for these offline reads.
        for (final header in before.headers) {
          final message = _value(await offline.load(header))!;
          _expectMessage(message, provider.messages[header.remote]!, header);
        }
        await expectSyncUnchanged(reopened, before);
        await _expectProtected(reopened, outgoing);

        final resumeProvider = _Provider(reopened.account, before.headers);
        final repeated = await MailBodyDownloadRunner(
          provider: resumeProvider,
          cache: offline,
          session: sessionFor(reopened.account),
        ).run(mailbox: before.mailbox.id, headers: before.headers);
        expect(repeated.status, MailBodyDownloadStatus.completed);
        expect(repeated.downloaded, 0);
        expect(repeated.alreadyCached, before.headers.length);
        expect(repeated.retainedBytes, 0);
        expect(resumeProvider.requests, isEmpty);
      },
    );
  }

  for (final interruption in ['cancel', 'retire', 'rollback']) {
    test(
      '$interruption during a later cache transaction preserves only the acknowledged prefix',
      () async {
        const kind = MailProviderKind.ews;
        final reached = Completer<void>();
        final release = Completer<void>();
        var armed = false;
        var commits = 0;
        final owner = await open(
          kind,
          fault: (point) async {
            if (!armed || point != MailStoreCheckpoint.beforeCommit) return;
            commits++;
            if (commits != 2) return;
            if (interruption == 'rollback') {
              throw StateError('private storage detail');
            }
            reached.complete();
            await release.future;
          },
        );
        final outgoing = await _protectOutgoing(owner);
        final before = await seed(owner, kind);
        final provider = _Provider(owner.account, before.headers);
        final session = sessionFor(owner.account);
        final cancellation = MailCancellationSource();
        armed = true;
        final pending =
            MailBodyDownloadRunner(
              provider: provider,
              cache: StudioMailBodyDownloadCache(owner.mailboxStore),
              session: session,
            ).run(
              mailbox: before.mailbox.id,
              headers: before.headers,
              cancellation: cancellation.token,
            );
        if (interruption != 'rollback') {
          await reached.future;
          if (interruption == 'cancel') {
            cancellation.cancel();
          } else {
            session.invalidate();
          }
          release.complete();
        }
        final report = await pending;
        armed = false;
        expect(
          report.status,
          interruption == 'rollback'
              ? MailBodyDownloadStatus.failed
              : MailBodyDownloadStatus.cancelled,
        );
        expect(report.problem!.code, switch (interruption) {
          'cancel' => MailProblemCode.cancelled,
          'retire' => MailProblemCode.staleOperation,
          _ => MailProblemCode.storageFailure,
        });
        expect(report.downloaded, 1);
        expect(
          provider.requests,
          before.headers.take(2).map((header) => header.remote),
        );
        expect(
          await owner.mailboxStore.loadMessage(before.headers.first),
          isNotNull,
        );
        for (final header in before.headers.skip(1)) {
          expect(await owner.mailboxStore.loadMessage(header), isNull);
        }
        await expectSyncUnchanged(owner, before);
        await _expectProtected(owner, outgoing);
        await owner.close();

        final reopened = await open(kind);
        final resumedProvider = _Provider(reopened.account, before.headers);
        final resumed = await MailBodyDownloadRunner(
          provider: resumedProvider,
          cache: StudioMailBodyDownloadCache(reopened.mailboxStore),
          session: sessionFor(reopened.account),
        ).run(mailbox: before.mailbox.id, headers: before.headers);
        expect(resumed.status, MailBodyDownloadStatus.completed);
        expect(resumed.alreadyCached, 1);
        expect(resumed.downloaded, 2);
        expect(
          resumedProvider.requests,
          before.headers.skip(1).map((header) => header.remote),
        );
        await expectSyncUnchanged(reopened, before);
        await _expectProtected(reopened, outgoing);
      },
    );
  }

  test(
    'native blob quota keeps earlier bodies and all outgoing data intact',
    () async {
      const kind = MailProviderKind.graph;
      final owner = await open(
        kind,
        limits: const MailStoreLimits(maxBlobBytes: 2048),
      );
      final outgoing = await _protectOutgoing(owner);
      final before = await seed(owner, kind);
      final provider = _Provider(owner.account, before.headers);
      provider.messages[before.headers[1].remote] = _message(
        before.headers[1],
        rawBytes: 4096,
      );
      final report = await MailBodyDownloadRunner(
        provider: provider,
        cache: StudioMailBodyDownloadCache(owner.mailboxStore),
        session: sessionFor(owner.account),
      ).run(mailbox: before.mailbox.id, headers: before.headers);
      expect(report.status, MailBodyDownloadStatus.failed);
      expect(report.problem!.code, MailProblemCode.quotaExceeded);
      expect(report.downloaded, 1);
      expect(
        provider.requests,
        before.headers.take(2).map((header) => header.remote),
      );
      expect(
        await owner.mailboxStore.loadMessage(before.headers.first),
        isNotNull,
      );
      expect(await owner.mailboxStore.loadMessage(before.headers[1]), isNull);
      expect(await owner.mailboxStore.loadMessage(before.headers[2]), isNull);
      await expectSyncUnchanged(owner, before);
      await _expectProtected(owner, outgoing);
      await owner.close();

      final reopened = await open(kind);
      expect(
        await reopened.mailboxStore.loadMessage(before.headers.first),
        isNotNull,
      );
      expect(
        await reopened.mailboxStore.loadMessage(before.headers[1]),
        isNull,
      );
      expect(
        await reopened.mailboxStore.loadMessage(before.headers[2]),
        isNull,
      );
      await expectSyncUnchanged(reopened, before);
      await _expectProtected(reopened, outgoing);
    },
  );
}
