import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store_native.dart';

import 'package:quds_office_studio/studio_mail_draft.dart';
import 'package:quds_office_studio/studio_mail_draft_store.dart';
import 'package:quds_office_studio/studio_mail_draft_store_native.dart';
import 'package:quds_office_studio/studio_mail_threading.dart';

void main() {
  late Directory directory;
  final opened = <StudioMailDraftStore>[];

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('studio-mail-draft-');
  });

  tearDown(() async {
    for (final store in opened.reversed) {
      await store.close();
    }
    opened.clear();
    await directory.delete(recursive: true);
  });

  Future<StudioMailDraftStore> open({
    StudioMailDraftAccount? identity,
    MailStoreLimits limits = const MailStoreLimits(),
    MailStoreFaultInjector? fault,
  }) async {
    final store = await openStudioMailDraftStore(
      identity ?? _identity(),
      appDirectory: directory,
      limits: limits,
      faultInjector: fault,
    );
    opened.add(store);
    return store;
  }

  test(
    'file reopen preserves unfinished fields, reply chain and bytes',
    () async {
      final source = Uint8List.fromList([0, 10, 13, 128, 255]);
      final attachment = StudioMailAttachment(
        name: 'résumé.pdf',
        bytes: source,
      );
      final draft = StudioMailDraft(
        to: 'Alice <unfinished',
        cc: 'first@example.test; ',
        bcc: 'hidden@',
        subject: 'Unfinished subject\nwith a newline',
        body: 'مرحبا\nUnfinished body\u0000',
        thread: StudioMailThread.replyTo(
          MailEnvelope(
            messageId: '<parent@example.test>',
            references: ['<root@example.test>', '<middle@example.test>'],
          ),
        ),
        attachments: StudioMailAttachments.from([attachment]),
      );
      source.fillRange(0, source.length, 42);
      final first = await open();
      expect(await first.load(), isNull);
      await first.save(draft, submissionUncertain: false);
      await first.close();

      final restored = (await (await open()).load())!;
      expect(restored.draft.to, draft.to);
      expect(restored.draft.cc, draft.cc);
      expect(restored.draft.bcc, draft.bcc);
      expect(restored.draft.subject, draft.subject);
      expect(restored.draft.body, draft.body);
      expect(restored.draft.problem, StudioMailDraftProblem.recipient);
      expect(restored.draft.thread.inReplyTo, draft.thread.inReplyTo);
      expect(restored.draft.thread.references, draft.thread.references);
      final file = restored.draft.attachments.items.single;
      expect(file.name, 'résumé.pdf');
      expect(file.mediaType, 'application/pdf');
      expect(file.content.copyBytes(), [0, 10, 13, 128, 255]);
      expect(file.content.sha256, attachment.content.sha256);
      expect(restored.submissionUncertain, isFalse);
    },
  );

  test('uncertain send survives restart and ordinary autosave', () async {
    final store = await open();
    await store.load();
    await store.save(_draft('attempt'), submissionUncertain: true);
    await store.save(_draft('edited'), submissionUncertain: false);
    await store.close();
    final snapshot = (await (await open()).load())!;
    expect(snapshot.draft.body, 'edited');
    expect(snapshot.submissionUncertain, isTrue);
  });

  test(
    'verified rejection of a new attempt persists safe ordinary retry',
    () async {
      final store = await open();
      await store.load();
      await store.save(_draft('not submitted'), submissionUncertain: true);
      await store.saveRejectedDraft(
        _draft('not submitted'),
        wasPreviouslyUncertain: false,
      );
      expect((await store.load())!.submissionUncertain, isFalse);
      await store.close();
      final restored = (await (await open()).load())!;
      expect(restored.draft.body, 'not submitted');
      expect(restored.submissionUncertain, isFalse);
    },
  );

  test('rejected retry cannot erase an earlier uncertain submission', () async {
    final store = await open();
    await store.load();
    await store.save(_draft('first attempt'), submissionUncertain: true);
    await store.save(_draft('retry'), submissionUncertain: true);
    await store.saveRejectedDraft(
      _draft('retry'),
      wasPreviouslyUncertain: true,
    );
    await store.close();
    final restored = (await (await open()).load())!;
    expect(restored.draft.body, 'retry');
    expect(restored.submissionUncertain, isTrue);
  });

  test(
    'failed rejection persistence retains the durable uncertainty marker',
    () async {
      var fail = false;
      final store = await open(
        fault: (checkpoint) {
          if (fail && checkpoint == MailStoreCheckpoint.afterDraftBlobs) {
            throw StateError('result persistence failed');
          }
        },
      );
      await store.load();
      await store.save(_draft('attempt'), submissionUncertain: true);
      fail = true;
      await expectLater(
        store.saveRejectedDraft(
          _draft('attempt'),
          wasPreviouslyUncertain: false,
        ),
        throwsA(isA<StudioMailDraftStoreException>()),
      );
      fail = false;
      expect((await store.load())!.submissionUncertain, isTrue);
      await store.close();
      expect((await (await open()).load())!.submissionUncertain, isTrue);
    },
  );

  test(
    'a rejected outcome requires a preceding durable attempt marker',
    () async {
      final store = await open();
      await store.load();
      await store.save(_draft('editing'), submissionUncertain: false);
      await expectLater(
        store.saveRejectedDraft(
          _draft('editing'),
          wasPreviouslyUncertain: false,
        ),
        throwsA(_problem(MailProblemCode.conflict)),
      );
      expect((await store.load())!.submissionUncertain, isFalse);
    },
  );

  test('confirmed clear survives restart and permits a fresh draft', () async {
    final store = await open();
    await store.load();
    await store.save(_draft('accepted'), submissionUncertain: true);
    await store.clear();
    await store.close();
    final next = await open();
    expect(await next.load(), isNull);
    await next.save(_draft('new work'), submissionUncertain: false);
    final snapshot = (await next.load())!;
    expect(snapshot.draft.body, 'new work');
    expect(snapshot.submissionUncertain, isFalse);
  });

  test('identity isolates login, sender, endpoint and provider', () async {
    final identities = [
      _identity(),
      _identity(login: 'other@example.test'),
      _identity(sender: 'alias@example.test'),
      _identity(endpoint: 'imaps://other.example.test:993'),
      _identity(provider: 'ews'),
    ];
    expect(identities.map((item) => item.account.value).toSet().length, 5);
    for (var index = 0; index < identities.length; index++) {
      final store = await open(identity: identities[index]);
      expect(await store.load(), isNull);
      await store.save(_draft('draft-$index'), submissionUncertain: false);
      await store.close();
    }
    for (var index = 0; index < identities.length; index++) {
      final store = await open(identity: identities[index]);
      expect((await store.load())!.draft.body, 'draft-$index');
    }
  });

  test(
    'native owner lease rejects concurrent owner without data loss',
    () async {
      final store = await open();
      await store.load();
      await store.save(_draft('first owner'), submissionUncertain: false);
      await expectLater(open(), throwsA(_problem(MailProblemCode.conflict)));
      expect((await store.load())!.draft.body, 'first owner');
    },
  );

  test('save and clear require an observed revision', () async {
    final store = await open();
    await expectLater(
      store.save(_draft('unobserved'), submissionUncertain: false),
      throwsA(_problem(MailProblemCode.conflict)),
    );
    await expectLater(
      store.clear(),
      throwsA(_problem(MailProblemCode.conflict)),
    );
    expect(await store.load(), isNull);
  });

  test(
    'clear tombstone prevents stale overwrite and ABA resurrection',
    () async {
      final identity = _identity();
      final result = await openNativeMailStore(
        appDirectory: directory,
        profile: identity.profile,
      );
      final repository = (result as MailSuccess<SqliteMailRepository>).value;
      addTearDown(repository.close);
      expect(
        await repository.createAccount(
          MailStoreAccount(
            id: identity.account,
            provider: identity.provider,
            displayName: 'test',
          ),
        ),
        isA<MailSuccess<MailUnit>>(),
      );
      final first = SqliteStudioMailDraftStore(
        repository: repository,
        account: identity.account,
      );
      final stale = SqliteStudioMailDraftStore(
        repository: repository,
        account: identity.account,
      );
      opened.addAll([first, stale]);
      await first.load();
      await stale.load();
      await first.save(_draft('original'), submissionUncertain: false);
      await expectLater(
        stale.save(_draft('overwrite'), submissionUncertain: false),
        throwsA(_problem(MailProblemCode.conflict)),
      );
      await stale.load();
      await first.clear();
      await expectLater(
        stale.save(_draft('resurrected'), submissionUncertain: false),
        throwsA(_problem(MailProblemCode.conflict)),
      );
      await first.save(_draft('replacement'), submissionUncertain: false);
      await expectLater(
        stale.clear(),
        throwsA(_problem(MailProblemCode.conflict)),
      );
      expect((await first.load())!.draft.body, 'replacement');
    },
  );

  test(
    'failed save rolls back bytes and preserves the last durable draft',
    () async {
      var fail = false;
      final store = await open(
        fault: (checkpoint) {
          if (fail && checkpoint == MailStoreCheckpoint.afterDraftBlobs) {
            throw StateError('private-provider-and-message-marker');
          }
        },
      );
      await store.load();
      await store.save(_draft('durable'), submissionUncertain: false);
      fail = true;
      await expectLater(
        store.save(_draft('new-unsaved'), submissionUncertain: true),
        throwsA(
          isA<StudioMailDraftStoreException>().having(
            (error) => error.toString(),
            'redacted error',
            isNot(contains('private-provider')),
          ),
        ),
      );
      fail = false;
      await store.close();
      final restored = (await (await open()).load())!;
      expect(restored.draft.body, 'durable');
      expect(restored.submissionUncertain, isFalse);
    },
  );

  test(
    'failed accepted cleanup retains uncertain recovery instead of resending',
    () async {
      var fail = false;
      final store = await open(
        fault: (checkpoint) {
          if (fail && checkpoint == MailStoreCheckpoint.afterDraftBlobs) {
            throw StateError('cleanup failed');
          }
        },
      );
      await store.load();
      await store.save(_draft('possibly accepted'), submissionUncertain: true);
      fail = true;
      await expectLater(
        store.clear(),
        throwsA(isA<StudioMailDraftStoreException>()),
      );
      fail = false;
      await store.close();
      final restored = (await (await open()).load())!;
      expect(restored.draft.body, 'possibly accepted');
      expect(restored.submissionUncertain, isTrue);
    },
  );

  test(
    'raw editor text participates in quota and does not replace durable work',
    () async {
      final store = await open(
        limits: const MailStoreLimits(maxMetadataCodeUnits: 128),
      );
      await store.load();
      await store.save(_draft('kept'), submissionUncertain: false);
      await expectLater(
        store.save(
          StudioMailDraft(to: 'x' * 256, subject: '', body: ''),
          submissionUncertain: false,
        ),
        throwsA(_problem(MailProblemCode.quotaExceeded)),
      );
      expect((await store.load())!.draft.body, 'kept');
    },
  );

  test('close drains writes and refuses subsequent stale operations', () async {
    final started = Completer<void>();
    final finish = Completer<void>();
    final store = await open(
      fault: (checkpoint) async {
        if (checkpoint == MailStoreCheckpoint.afterDraftBlobs) {
          started.complete();
          await finish.future;
        }
      },
    );
    await store.load();
    final saved = store.save(_draft('pending'), submissionUncertain: false);
    await started.future;
    var closed = false;
    final closing = store.close().then((_) => closed = true);
    await Future<void>.delayed(Duration.zero);
    expect(closed, isFalse);
    await expectLater(
      store.load(),
      throwsA(_problem(MailProblemCode.unavailable)),
    );
    finish.complete();
    await saved;
    await closing;
    expect((await (await open()).load())!.draft.body, 'pending');
  });

  test(
    'identity rejects embedded secrets and preserves case-sensitive logins',
    () {
      for (final endpoint in [
        'https://user:password@example.test/EWS',
        'https://example.test/EWS?token=secret',
        'https://example.test/EWS#secret',
      ]) {
        expect(
          () => _identity(endpoint: endpoint),
          throwsA(_problem(MailProblemCode.invalidInput)),
        );
      }
      expect(_identity().account.value, _identity().account.value);
      expect(
        _identity(login: 'Case@example.test').account,
        isNot(_identity(login: 'case@example.test').account),
      );
    },
  );
}

Matcher _problem(MailProblemCode code) => isA<StudioMailDraftStoreException>()
    .having((error) => error.code, 'code', code);

StudioMailDraftAccount _identity({
  String provider = 'imap',
  String endpoint = 'imaps://mail.example.test:993',
  String login = 'sender@example.test',
  String sender = 'sender@example.test',
}) => StudioMailDraftAccount(
  provider: provider,
  endpoint: endpoint,
  login: login,
  sender: sender,
);

StudioMailDraft _draft(String body) =>
    StudioMailDraft(to: 'recipient@example.test', subject: 'draft', body: body);
