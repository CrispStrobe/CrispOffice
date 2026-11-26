import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_mime/quds_mail_mime.dart';
import 'package:quds_office_studio/studio_mail_compose_tools.dart';
import 'package:quds_office_studio/studio_mail_draft.dart';
import 'package:quds_office_studio/studio_mail_outbox_content.dart';
import 'package:quds_office_studio/studio_mail_submission.dart';

const _sender = 'writer@example.test';
final _account = MailAccountId(
  'writer',
  profile: MailProfileId('rich-mail', hostId: 'studio-test'),
);

MailComposeBody _body() => MailComposeBody(
  paragraphs: [
    MailComposeParagraph(
      runs: [
        MailComposeRun(text: 'Hello & ', bold: true),
        MailComposeRun(text: '<مرحبا>', italic: true, underline: true),
      ],
      alignment: MailComposeAlignment.center,
    ),
    MailComposeParagraph(
      runs: [
        MailComposeRun(
          text: 'Second line',
          link: 'https://example.test/a?b=1&c=2',
          strike: true,
        ),
      ],
      rightToLeft: true,
    ),
  ],
);

StudioMailDraft _draft({MailComposeBody? richBody}) {
  final rich = richBody ?? _body();
  return StudioMailDraft(
    to: 'reader@example.test',
    cc: 'copy@example.test',
    bcc: 'private@example.test',
    subject: 'Formatted message',
    body: rich.plainText,
    richBody: rich,
    sender: const StudioMailSender(
      address: 'alias@example.test',
      displayName: 'A Writer',
      replyTo: 'replies@example.test',
    ),
    attachments: StudioMailAttachments.from([
      StudioMailAttachment(
        name: 'notes.txt',
        bytes: Uint8List.fromList([0, 128, 255, 13, 10]),
        mediaType: 'text/plain',
      ),
    ]),
  );
}

MailOutboxEntry _entry(StudioMailDraft draft, {String? wire}) =>
    MailOutboxEntry.queued(
      id: 'rich-outbox',
      prepared: MailPreparedMessage(
        account: _account,
        draftId: 'rich-draft',
        draftRevision: 1,
        wire: MailBytes(
          utf8.encode(
            wire ?? buildStudioMailMessage(draft, _sender).renderMessage(),
          ),
        ),
        envelope: MailTransportEnvelope(
          sender: draft.sender?.address ?? _sender,
          recipients: draft.recipients.envelope,
        ),
      ),
      now: DateTime.utc(2026, 11, 25),
    );

void main() {
  test('rich MIME preserves both alternatives and keeps Bcc private', () {
    final draft = _draft();
    final wire = buildStudioMailMessage(draft, _sender).renderMessage();
    expect(wire.codeUnits.every((value) => value < 128), isTrue);
    expect(wire.toLowerCase(), isNot(contains('bcc:')));
    expect(wire, isNot(contains('private@example.test')));
    final parsed = const QudsMimeCodec().parse(utf8.encode(wire));
    expect(parsed.status, MailParseStatus.complete);
    expect(parsed.diagnostics, isEmpty);
    expect(parsed.message!.body.html, draft.richBody!.html);
    expect(
      parsed.message!.body.plainText!.replaceAll('\r\n', '\n'),
      draft.body,
    );
    expect(parsed.message!.envelope.from.single.address, 'alias@example.test');
    expect(parsed.message!.envelope.bcc, isEmpty);
    expect(parsed.message!.attachments.single.content.bytes, [
      0,
      128,
      255,
      13,
      10,
    ]);
  });

  test(
    'Outbox edit projection retains formatting, aliases and attachments',
    () {
      final original = _draft();
      final entry = _entry(original);
      final hash = entry.prepared.wireHash;
      final content = StudioMailOutboxContent.fromEntry(entry);
      expect(content.draft.richBody!.html, original.richBody!.html);
      expect(content.draft.body, original.body);
      expect(content.draft.sender, original.sender);
      expect(content.draft.bcc, original.bcc);
      expect(content.draft.attachments.items.single.name, 'notes.txt');
      expect(content.message.raw.bytes, entry.prepared.wire.bytes);
      expect(entry.prepared.wireHash, hash);
      expect(entry.state, MailOutboxState.queued);
    },
  );

  test('different plain and formatted text cannot be submitted', () {
    final draft = StudioMailDraft(
      to: 'reader@example.test',
      subject: '',
      body: 'Different text',
      richBody: _body(),
    );
    expect(draft.hasValidBody, isFalse);
    expect(draft.problem, StudioMailDraftProblem.body);
    expect(() => buildStudioMailMessage(draft, _sender), throwsFormatException);
  });

  test('rich body validation is independent of unfinished recipients', () {
    final rich = _body();
    final draft = StudioMailDraft(
      to: 'unfinished',
      subject: '',
      body: rich.plainText,
      richBody: rich,
    );
    expect(draft.hasValidBody, isTrue);
    expect(draft.problem, StudioMailDraftProblem.recipient);
  });

  for (final mode in ['different-text', 'active-html', 'unknown-format']) {
    test('Outbox refuses $mode without rewriting its original bytes', () {
      final rich = _body();
      final draft = StudioMailDraft(
        to: 'reader@example.test',
        subject: 'Body',
        body: rich.plainText,
        richBody: rich,
      );
      final plain = mode == 'different-text' ? 'Changed' : rich.plainText;
      final html = switch (mode) {
        'active-html' => '${rich.html}<script>alert(1)</script>',
        'unknown-format' => '<p><b>${rich.plainText}</b></p>',
        _ => rich.html,
      };
      final wire =
          'From: $_sender\r\n'
          'To: reader@example.test\r\n'
          'Subject: Body\r\n'
          'MIME-Version: 1.0\r\n'
          'Content-Type: multipart/alternative; boundary="rich-test"\r\n\r\n'
          '--rich-test\r\nContent-Type: text/plain; charset=utf-8\r\n'
          'Content-Transfer-Encoding: base64\r\n\r\n'
          '${base64.encode(utf8.encode(plain))}\r\n'
          '--rich-test\r\nContent-Type: text/html; charset=utf-8\r\n'
          'Content-Transfer-Encoding: base64\r\n\r\n'
          '${base64.encode(utf8.encode(html))}\r\n--rich-test--\r\n';
      final entry = _entry(draft, wire: wire);
      final originalHash = entry.prepared.wireHash;
      expect(
        () => StudioMailOutboxContent.fromEntry(entry),
        throwsA(isA<StudioMailOutboxContentException>()),
      );
      expect(entry.prepared.wireHash, originalHash);
      expect(utf8.decode(entry.prepared.wire.bytes), wire);
    });
  }

  for (final reply in [false, true]) {
    test('default signature preserves rich runs for reply=$reply', () {
      final original = _draft();
      final result = applyStudioMailDefaultSignature(
        original,
        MailComposeSettings(
          account: _account,
          revision: 0,
          signature: 'Regards\r\nWriter',
          signatureForNewMessages: true,
          signatureForReplies: true,
        ),
        replyOrForward: reply,
      );
      expect(result.richBody, isNotNull);
      expect(result.richBody!.plainText, result.body);
      expect(result.body, contains('Regards\nWriter'));
      expect(
        result.richBody!.paragraphs
            .expand((p) => p.runs)
            .any((run) => run.bold && run.text.contains('Hello')),
        isTrue,
      );
      expect(result.sender, original.sender);
      expect(result.attachments, original.attachments);
      expect(
        StudioMailOutboxContent.fromEntry(_entry(result)).draft.body,
        result.body,
      );
    });
  }

  test('identity-only default preserves the original rich snapshot', () {
    final rich = _body();
    final original = StudioMailDraft(
      to: 'reader@example.test',
      subject: '',
      body: rich.plainText,
      richBody: rich,
    );
    final result = applyStudioMailDefaultSignature(
      original,
      MailComposeSettings(
        account: _account,
        revision: 0,
        senderIdentities: [
          MailSenderIdentity(id: 'primary', name: 'Primary', address: _sender),
        ],
        defaultSenderIdentityId: 'primary',
      ),
      replyOrForward: false,
    );
    expect(result.richBody, same(rich));
    expect(result.sender!.address, _sender);
  });
}
