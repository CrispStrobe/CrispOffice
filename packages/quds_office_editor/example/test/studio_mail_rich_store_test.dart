import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_store/quds_mail_store_native.dart';
import 'package:quds_office_studio/studio_mail_draft.dart';
import 'package:quds_office_studio/studio_mail_draft_store.dart';
import 'package:quds_office_studio/studio_mail_outbox_content.dart';

const _sender = 'writer@example.test';
final _identity = StudioMailDraftAccount(
  provider: 'imap',
  endpoint: 'imaps://imap.example.test:993',
  login: _sender,
  sender: _sender,
);

T _value<T>(MailResult<T> result) {
  expect(result, isA<MailSuccess<T>>());
  return (result as MailSuccess<T>).value;
}

Matcher _problem(MailProblemCode code) => isA<StudioMailDraftStoreException>()
    .having((error) => error.code, 'code', code);

StudioMailDraft _draft({bool bold = true, String to = 'reader@example.test'}) {
  final rich = MailComposeBody(
    paragraphs: [
      MailComposeParagraph(
        runs: [
          MailComposeRun(text: 'Recover this text', bold: bold, italic: true),
        ],
        alignment: MailComposeAlignment.right,
      ),
      MailComposeParagraph(
        runs: [MailComposeRun(text: 'مرحبا', underline: true)],
        rightToLeft: true,
      ),
    ],
  );
  return StudioMailDraft(
    to: to,
    bcc: 'hidden@example.test',
    subject: 'Rich recovery',
    body: rich.plainText,
    richBody: rich,
  );
}

void main() {
  late Directory directory;
  late SqliteMailRepository repository;
  late SqliteStudioMailDraftStore store;

  Future<void> open({bool createAccount = true}) async {
    repository = _value(
      await openNativeMailStore(
        appDirectory: directory,
        profile: _identity.profile,
      ),
    );
    if (createAccount) {
      _value(
        await repository.createAccount(
          MailStoreAccount(
            id: _identity.account,
            provider: _identity.provider,
            displayName: 'Rich composition fixture',
          ),
        ),
      );
    }
    store = SqliteStudioMailDraftStore(
      repository: repository,
      account: _identity.account,
      ownsRepository: true,
    );
    await store.load();
  }

  Future<MailDraft> rawDraft() async => _value<MailDraft?>(
    await repository.loadDraft(_identity.account, store.selectedDraftId),
  )!;

  Future<void> corrupt({String? plainText, String? html}) async {
    final old = await rawDraft();
    _value(
      await repository.saveDraft(
        MailDraft(
          id: old.id,
          account: old.account,
          revision: old.revision + 1,
          envelope: old.envelope,
          body: MailBody(
            plainText: plainText ?? old.body.plainText,
            html: html ?? old.body.html,
          ),
          attachments: old.attachments,
          editorState: old.editorState,
        ),
        expectedRevision: old.revision,
      ),
    );
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('studio-mail-rich-');
    await open();
  });
  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });

  test('rich draft survives real database close and reopen', () async {
    final draft = _draft(to: 'unfinished recipient');
    await store.save(draft, submissionUncertain: true);
    final stored = await rawDraft();
    expect(stored.body.html, draft.richBody!.html);
    expect(stored.body.plainText, draft.body);
    await store.close();
    await open(createAccount: false);
    final restored = (await store.load())!;
    expect(restored.draft.richBody!.html, draft.richBody!.html);
    expect(restored.draft.body, draft.body);
    expect(restored.draft.to, 'unfinished recipient');
    expect(restored.submissionUncertain, isTrue);
    expect(restored.draft.problem, StudioMailDraftProblem.recipient);
  });

  test('formatting-only saves advance revision and keep uncertainty', () async {
    final first = _draft();
    await store.save(first, submissionUncertain: true);
    final before = await rawDraft();
    final changed = _draft(bold: false);
    expect(changed.body, first.body);
    expect(changed.richBody!.html, isNot(first.richBody!.html));
    await store.save(changed, submissionUncertain: false);
    final after = await rawDraft();
    expect(after.revision, before.revision + 1);
    expect(after.body.html, changed.richBody!.html);
    expect((await store.load())!.submissionUncertain, isTrue);
  });

  test(
    'divergent alternatives are refused without replacing saved work',
    () async {
      final saved = _draft();
      await store.save(saved, submissionUncertain: false);
      final before = await rawDraft();
      await expectLater(
        store.save(
          StudioMailDraft(
            to: '',
            subject: '',
            body: 'Unrelated text',
            richBody: saved.richBody,
          ),
          submissionUncertain: false,
        ),
        throwsA(_problem(MailProblemCode.invalidInput)),
      );
      final after = await rawDraft();
      expect(after.revision, before.revision);
      expect(after.body.html, before.body.html);
      expect(after.body.plainText, before.body.plainText);
    },
  );

  test(
    'rich queue and atomic edit copy preserve frozen MIME and private Bcc',
    () async {
      final draft = _draft();
      final queued = await store.enqueueOutbox(draft, _sender);
      final frozenHash = queued.prepared.wireHash;
      final frozenBytes = queued.prepared.wire.copyBytes();
      expect(await store.load(), isNull);
      await store.close();
      await open(createAccount: false);
      final restored = (await store.loadOutbox()).single;
      expect(restored.prepared.wireHash, frozenHash);
      final projection = StudioMailOutboxContent.fromEntry(restored);
      expect(projection.draft.richBody!.html, draft.richBody!.html);
      expect(projection.draft.bcc, draft.bcc);
      final copied = await store.editOutboxAsDraft(restored);
      expect(copied.richBody!.html, draft.richBody!.html);
      expect((await store.load())!.draft.richBody!.html, draft.richBody!.html);
      expect(
        (await store.loadOutbox()).single.state,
        MailOutboxState.cancelled,
      );
      expect(queued.prepared.wire.bytes, frozenBytes);
    },
  );

  test(
    'invalid recipients leave rich work durable when queue admission fails',
    () async {
      final draft = _draft(to: 'unfinished');
      await expectLater(
        store.enqueueOutbox(draft, _sender),
        throwsA(_problem(MailProblemCode.invalidInput)),
      );
      expect((await store.load())!.draft.richBody!.html, draft.richBody!.html);
      expect(await store.loadOutbox(), isEmpty);
    },
  );

  for (final kind in ['unknown-html', 'different-text', 'truncated-html']) {
    test('corrupt $kind recovery fails without silently flattening', () async {
      final draft = _draft();
      await store.save(draft, submissionUncertain: false);
      switch (kind) {
        case 'unknown-html':
          await corrupt(html: '<p onclick="bad()">Recover this text</p>');
        case 'different-text':
          await corrupt(plainText: 'Different persisted body');
        case 'truncated-html':
          await corrupt(html: draft.richBody!.html.substring(0, 20));
      }
      final damaged = await rawDraft();
      await expectLater(
        store.load(),
        throwsA(_problem(MailProblemCode.storageFailure)),
      );
      final retained = await rawDraft();
      expect(retained.revision, damaged.revision);
      expect(retained.body.html, damaged.body.html);
      expect(retained.body.plainText, damaged.body.plainText);
    });
  }

  test(
    'legacy plain drafts retain exact text and do not acquire rich state',
    () async {
      const draft = StudioMailDraft(
        to: '',
        subject: '',
        body: 'Original\r\ntext & <literal>',
      );
      await store.save(draft, submissionUncertain: false);
      await store.close();
      await open(createAccount: false);
      final restored = (await store.load())!.draft;
      expect(restored.body, draft.body);
      expect(restored.richBody, isNull);
      expect((await rawDraft()).body.html, isNull);
    },
  );

  test(
    'unfinished plain work above the send limit remains recoverable',
    () async {
      final draft = StudioMailDraft(
        to: 'reader@example.test',
        subject: '',
        body: 'x' * (StudioMailDraft.maxBodyBytes + 1),
      );
      expect(draft.problem, StudioMailDraftProblem.body);
      expect(draft.hasConsistentBody, isTrue);
      await store.save(draft, submissionUncertain: false);
      await store.close();
      await open(createAccount: false);
      expect((await store.load())!.draft.body, draft.body);
      await expectLater(
        store.enqueueOutbox(draft, _sender),
        throwsA(_problem(MailProblemCode.invalidInput)),
      );
      expect((await store.load())!.draft.body, draft.body);
      expect(await store.loadOutbox(), isEmpty);
    },
  );

  test(
    'rich HTML counts toward storage quota without replacing saved work',
    () async {
      final kept = _draft();
      await store.save(kept, submissionUncertain: false);
      final rich = MailComposeBody(
        paragraphs: [
          MailComposeParagraph(
            runs: [MailComposeRun(text: '&' * 360000, bold: true)],
          ),
        ],
      );
      final large = StudioMailDraft(
        to: 'reader@example.test',
        subject: '',
        body: rich.plainText,
        richBody: rich,
      );
      expect(large.problem, isNull);
      await expectLater(
        store.save(large, submissionUncertain: false),
        throwsA(_problem(MailProblemCode.quotaExceeded)),
      );
      expect((await store.load())!.draft.richBody!.html, kept.richBody!.html);
    },
  );
}
