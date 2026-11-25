import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_mime/quds_mail_mime.dart';
import 'package:quds_office_studio/studio_mail_compose_tools.dart';
import 'package:quds_office_studio/studio_mail_draft.dart';
import 'package:quds_office_studio/studio_mail_draft_store.dart';
import 'package:quds_office_studio/studio_mail_draft_store_native.dart';
import 'package:quds_office_studio/studio_mail_outbox.dart';
import 'package:quds_office_studio/studio_mail_outbox_content.dart';
import 'package:quds_office_studio/studio_mail_submission.dart';

final _account = MailAccountId(
  'account',
  profile: MailProfileId('profile', hostId: 'studio'),
);
const _identity = MailSenderIdentity(
  id: 'work',
  name: 'Work',
  address: 'alias@example.test',
  displayName: 'Grüße, Writer',
  replyTo: 'replies@example.test',
);
const _template = MailMessageTemplate(
  id: 'status',
  name: 'Status',
  to: 'reader@example.test',
  cc: 'copy@example.test',
  bcc: 'private@example.test',
  subject: 'Weekly update',
  body: 'First\r\nSecond',
  senderIdentityId: 'work',
);
MailComposeSettings _settings() => MailComposeSettings(
  account: _account,
  senderIdentities: const [_identity],
  templates: const [_template],
  defaultSenderIdentityId: 'work',
);
StudioMailDraft _draft() => StudioMailDraft(
  to: 'reader@example.test',
  bcc: 'hidden@example.test',
  subject: 'Hello',
  body: 'Body',
  sender: StudioMailSender.fromIdentity(_identity),
);

void main() {
  test(
    'templates create literal independent messages and snapshot their sender',
    () {
      final settings = _settings();
      final draft = applyStudioMailTemplate(_template, settings);
      expect(draft.to, _template.to);
      expect(draft.cc, _template.cc);
      expect(draft.bcc, _template.bcc);
      expect(draft.subject, _template.subject);
      expect(draft.body, 'First\nSecond');
      expect(draft.sender, StudioMailSender.fromIdentity(_identity));
      expect(draft.attachments.isEmpty, isTrue);
      expect(draft.thread.inReplyTo, isNull);
      final changed = settings.copyWith(
        senderIdentities: [_identity.copyWith(address: 'changed@example.test')],
      );
      expect(changed.isValid, isTrue);
      expect(draft.sender!.address, 'alias@example.test');
      expect(
        () => applyStudioMailTemplate(
          const MailMessageTemplate(id: 'foreign', name: 'Foreign'),
          settings,
        ),
        throwsA(isA<StudioMailComposeToolsException>()),
      );
    },
  );

  test('default identity preserves an existing authored sender', () {
    const existing = StudioMailSender(
      address: 'old@example.test',
      replyTo: 'old-reply@example.test',
    );
    const source = StudioMailDraft(
      to: '',
      subject: '',
      body: '',
      sender: existing,
    );
    expect(
      applyStudioMailDefaultSignature(
        source,
        _settings(),
        replyOrForward: false,
      ).sender,
      existing,
    );
    const empty = StudioMailDraft(to: '', subject: '', body: '');
    expect(
      applyStudioMailDefaultSignature(
        empty,
        _settings(),
        replyOrForward: false,
      ).sender,
      StudioMailSender.fromIdentity(_identity),
    );
  });

  test(
    'MIME and editable Outbox copies preserve From name and Reply-To without exposing Bcc',
    () {
      final draft = _draft();
      final wire = buildStudioMailMessage(
        draft,
        'account@example.test',
      ).renderMessage();
      final parsed = const QudsMimeCodec().parse(utf8.encode(wire)).message!;
      expect(parsed.envelope.from.single.address, _identity.address);
      expect(parsed.envelope.from.single.displayName, _identity.displayName);
      expect(parsed.envelope.replyTo.single.address, _identity.replyTo);
      expect(parsed.envelope.bcc, isEmpty);
      expect(wire.contains('hidden@example.test'), isFalse);
      final entry = MailOutboxEntry.queued(
        id: 'outbox',
        prepared: MailPreparedMessage(
          account: _account,
          draftId: 'draft',
          draftRevision: 1,
          wire: MailBytes(utf8.encode(wire)),
          envelope: MailTransportEnvelope(
            sender: _identity.address,
            recipients: draft.recipients.envelope,
          ),
        ),
        now: DateTime.utc(2026, 11, 25),
      );
      final restored = StudioMailOutboxContent.fromEntry(entry).draft;
      expect(restored.sender, draft.sender);
      expect(restored.bcc, draft.bcc);
    },
  );

  test('invalid sender headers are rejected before MIME construction', () {
    for (final sender in [
      const StudioMailSender(
        address: 'alias@example.test\r\nBcc: stolen@example.test',
      ),
      const StudioMailSender(
        address: 'alias@example.test',
        displayName: 'Writer\nBcc: stolen@example.test',
      ),
      const StudioMailSender(
        address: 'alias@example.test',
        replyTo: 'reply@example.test\r\nX-Extra: no',
      ),
    ]) {
      final draft = StudioMailDraft(
        to: 'reader@example.test',
        subject: '',
        body: '',
        sender: sender,
      );
      expect(draft.problem, StudioMailDraftProblem.sender);
      expect(
        () => buildStudioMailMessage(draft, 'account@example.test'),
        throwsFormatException,
      );
    }
  });

  test(
    'restart retains sender snapshot and Outbox freezes its exact envelope',
    () async {
      final directory = await Directory.systemTemp.createTemp('studio-sender-');
      final opened = <StudioMailDraftStore>[];
      final identity = StudioMailDraftAccount(
        provider: 'imap',
        endpoint: 'imaps://mail.example.test:993',
        login: 'writer',
        sender: 'account@example.test',
      );
      Future<StudioMailDraftStore> open() async {
        final store = await openStudioMailDraftStore(
          identity,
          appDirectory: directory,
        );
        opened.add(store);
        return store;
      }

      try {
        final first = await open();
        await first.load();
        await first.save(_draft(), submissionUncertain: false);
        await first.close();
        final second = await open();
        final restored = (await second.load())!.draft;
        expect(restored.sender, _draft().sender);
        final entry = await (second as StudioMailOutboxStore).enqueueOutbox(
          restored,
          'account@example.test',
        );
        expect(entry.prepared.envelope.sender, 'alias@example.test');
        expect(
          StudioMailOutboxContent.fromEntry(entry).draft.sender,
          _draft().sender,
        );
      } finally {
        for (final store in opened.reversed) {
          await store.close();
        }
        await directory.delete(recursive: true);
      }
    },
  );
}
