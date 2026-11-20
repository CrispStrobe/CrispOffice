import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_mime/quds_mail_mime.dart';
import 'package:quds_office_studio/studio_mail_draft.dart';
import 'package:quds_office_studio/studio_mail_reply.dart';
import 'package:quds_office_studio/studio_mail_submission.dart';

MailAttachment _attachment(
  String name,
  List<int> bytes, {
  String type = 'application/octet-stream',
  bool inline = false,
}) => MailAttachment(
  partPath: '2',
  displayName: name,
  mediaType: type,
  content: MailBytes(Uint8List.fromList(bytes)),
  contentId: inline ? 'source-inline-id' : null,
  inline: inline,
);

MailParseResult _source({
  List<MailAttachment> attachments = const [],
  String? plain = 'Original body',
  String? html,
  MailParseStatus status = MailParseStatus.complete,
}) => MailParseResult(
  status: status,
  message: MailMessage(
    raw: MailBytes(Uint8List.fromList([1, 2, 3])),
    envelope: MailEnvelope(
      subject: 'Original subject',
      from: const [MailAddress('author@example.invalid')],
      to: const [MailAddress('original-to@example.invalid')],
      cc: const [MailAddress('original-cc@example.invalid')],
      bcc: const [MailAddress('private-bcc@example.invalid')],
      messageId: '<parent@example.invalid>',
      inReplyTo: '<previous@example.invalid>',
      references: const ['<root@example.invalid>'],
    ),
    body: MailBody(plainText: plain, html: html),
    attachments: attachments,
  ),
);

Matcher get _forwardUnavailable =>
    throwsA(isA<StudioMailForwardAttachmentsUnavailable>());

void main() {
  test('attached forwarding preserves every part in order as owned files', () {
    final parts = [
      _attachment('研究😀.bin', [0, 127, 128, 255]),
      _attachment('same.txt', [], type: 'text/plain'),
      _attachment('same.txt', [42], type: 'TEXT/PLAIN', inline: true),
    ];
    final result = _source(attachments: parts);
    final forward = buildStudioMailForwardWithAttachmentsDraft(
      result,
      forwardNotice: '[Mit Anhängen weitergeleitet.]',
    );
    parts.clear();

    expect(forward.to, isEmpty);
    expect(forward.cc, isEmpty);
    expect(forward.bcc, isEmpty);
    expect(forward.subject, 'Fwd: Original subject');
    expect(forward.problem, StudioMailDraftProblem.recipient);
    expect(forward.thread.inReplyTo, isNull);
    expect(forward.thread.references, isNull);
    expect(forward.body, contains('[Mit Anhängen weitergeleitet.]'));
    expect(forward.body, contains('> Original body'));
    expect(forward.body, isNot(contains('private-bcc')));
    expect(forward.body, isNot(contains('研究')));
    expect(forward.body, isNot(contains('same.txt')));
    expect(forward.attachments.totalBytes, 5);
    expect(
      forward.attachments.items.map((part) => part.name),
      ['研究😀.bin', 'same.txt', 'same.txt'],
    );
    expect(forward.attachments.items[0].content.bytes, [0, 127, 128, 255]);
    expect(forward.attachments.items[1].content.bytes, isEmpty);
    expect(forward.attachments.items[2].content.bytes, [42]);
    expect(forward.attachments.items[2].mediaType, 'text/plain');
    expect(
      identical(
        forward.attachments.items.first.content,
        result.message!.attachments.first.content,
      ),
      isFalse,
    );
    expect(
      () => forward.attachments.items.first.content.bytes[0] = 99,
      throwsUnsupportedError,
    );
    expect(() => forward.attachments.items.clear(), throwsUnsupportedError);
    expect(result.message!.attachments, hasLength(3));
    expect(result.message!.attachments.last.inline, isTrue);
    expect(result.message!.attachments.first.content.bytes, [0, 127, 128, 255]);
    expect(result.original!.bytes, [1, 2, 3]);
  });

  test('attached forward MIME retains bytes and starts an independent thread', () {
    final binary = List<int>.generate(4097, (index) => index % 256);
    final source = _source(
      plain: null,
      html: '<p>Original <b>HTML</b> &amp; text</p>'
          '<img src="cid:source-inline-id">',
      attachments: [
        _attachment('صورة😀.png', binary, type: 'image/png', inline: true),
        _attachment('empty.bin', []),
      ],
    );
    final forward = buildStudioMailForwardWithAttachmentsDraft(source);
    final addressed = StudioMailDraft(
      to: 'chosen@example.invalid',
      subject: forward.subject,
      body: forward.body,
      thread: forward.thread,
      attachments: forward.attachments,
    );
    final wire = buildStudioMailMessage(
      addressed,
      'writer@example.invalid',
    ).renderMessage();
    final parsed = const QudsMimeCodec().parse(ascii.encode(wire));
    expect(parsed.status, MailParseStatus.complete, reason: parsed.diagnostics.toString());
    final message = parsed.message!;
    expect(message.attachments, hasLength(2));
    expect(message.attachments.first.displayName, 'صورة😀.png');
    expect(message.attachments.first.content.bytes, binary);
    expect(message.attachments.first.inline, isFalse);
    expect(message.attachments.first.contentId, isNull);
    expect(message.attachments.last.content.bytes, isEmpty);
    expect(message.envelope.to.single.address, 'chosen@example.invalid');
    expect(message.envelope.cc, isEmpty);
    expect(message.envelope.bcc, isEmpty);
    expect(message.envelope.inReplyTo, isNull);
    expect(message.envelope.references, isEmpty);
    expect(message.body.plainText, contains('> Original HTML & text'));
    expect(message.body.plainText, isNot(contains('صورة')));
    expect(message.body.plainText, isNot(contains('source-inline-id')));
    expect(wire, isNot(contains('private-bcc@example.invalid')));
    expect(wire, isNot(contains('<parent@example.invalid>')));
  });

  test('replies and text-only forward never inspect or copy source parts', () {
    final source = _source(
      attachments: List<MailAttachment>.filled(
        11,
        _attachment('../unsupported.eml', [1], type: 'message/rfc822'),
      ),
    ).message!;
    final drafts = [
      buildStudioMailReplyDraft(source, forward: false),
      buildStudioMailReplyDraft(source, forward: true),
      buildStudioMailReplyAllDraft(source, sender: 'writer@example.invalid'),
    ];
    for (final draft in drafts) {
      expect(draft.attachments.isEmpty, isTrue);
      expect(draft.body, contains('Original body'));
      expect(draft.body, isNot(contains('unsupported.eml')));
    }
  });

  test('complete empty attachment set and explicit empty plain body are valid', () {
    final draft = buildStudioMailForwardWithAttachmentsDraft(
      _source(plain: '', html: '<p>Unselected alternate</p>'),
    );
    expect(draft.attachments.isEmpty, isTrue);
    expect(draft.body, endsWith('> '));
    expect(draft.body, isNot(contains('Unselected alternate')));
  });

  test('complete attachment-only messages forward their files with attribution', () {
    final draft = buildStudioMailForwardWithAttachmentsDraft(
      _source(plain: null, attachments: [_attachment('file.bin', [1])]),
    );
    expect(draft.body, contains('From: author@example.invalid'));
    expect(draft.body, endsWith('> '));
    expect(draft.attachments.items.single.name, 'file.bin');
    expect(draft.attachments.items.single.content.bytes, [1]);
    expect(draft.to, isEmpty);
  });

  test('missing body without files and malformed HTML still refuse', () {
    for (final source in [
      _source(plain: null),
      _source(
        plain: null,
        html: '<p>Incomplete source</p><script>',
        attachments: [_attachment('file.bin', [1])],
      ),
    ]) {
      expect(
        () => buildStudioMailForwardWithAttachmentsDraft(source),
        throwsA(isA<StudioMailReplyUnavailable>()),
      );
    }
  });

  test('every noncomplete parse is refused even with apparently valid parts', () {
    for (final status in MailParseStatus.values) {
      if (status == MailParseStatus.complete) continue;
      final source = _source(
        status: status,
        attachments: [_attachment('visible.bin', [42])],
      );
      expect(
        () => buildStudioMailForwardWithAttachmentsDraft(source),
        _forwardUnavailable,
        reason: status.name,
      );
      expect(source.message!.attachments.single.content.bytes, [42]);
    }
    expect(
      () => buildStudioMailForwardWithAttachmentsDraft(
        MailParseResult(status: MailParseStatus.rejected),
      ),
      _forwardUnavailable,
    );
  });

  test('ten parts including zero-byte inline parts pass, eleven refuse', () {
    final part = _attachment('empty.bin', [], inline: true);
    final accepted = buildStudioMailForwardWithAttachmentsDraft(
      _source(attachments: List<MailAttachment>.filled(10, part)),
    );
    expect(accepted.attachments.items, hasLength(10));
    expect(accepted.attachments.totalBytes, 0);
    expect(
      () => buildStudioMailForwardWithAttachmentsDraft(
        _source(attachments: List<MailAttachment>.filled(11, part)),
      ),
      _forwardUnavailable,
    );
  });

  test('ten MiB total is accepted and one extra byte refuses the whole set', () {
    final maximum = MailAttachment(
      partPath: '2',
      mediaType: 'application/octet-stream',
      displayName: 'maximum.bin',
      content: MailBytes(Uint8List(StudioMailAttachments.maxTotalBytes)),
    );
    final accepted = buildStudioMailForwardWithAttachmentsDraft(
      _source(attachments: [maximum]),
    );
    expect(accepted.attachments.totalBytes, StudioMailAttachments.maxTotalBytes);
    expect(
      () => buildStudioMailForwardWithAttachmentsDraft(
        _source(attachments: [maximum, _attachment('extra.bin', [1])]),
      ),
      _forwardUnavailable,
    );
    expect(accepted.attachments.items.single.length, maximum.content.length);
    expect(maximum.content.bytes.first, 0);
  });

  test('unsafe names and unsupported media types never produce partial drafts', () {
    final valid = _attachment('safe.bin', [1, 2]);
    for (final invalid in [
      _attachment('../private.bin', [3]),
      _attachment('private\r\nBcc: hidden', [3]),
      _attachment('attached.eml', [3], type: 'message/rfc822'),
      _attachment('parts.bin', [3], type: 'multipart/mixed'),
      _attachment('text.txt', [3], type: 'text/plain; charset=utf-8'),
    ]) {
      final result = _source(attachments: [valid, invalid]);
      expect(
        () => buildStudioMailForwardWithAttachmentsDraft(result),
        _forwardUnavailable,
      );
      expect(result.message!.attachments, [valid, invalid]);
      expect(valid.content.bytes, [1, 2]);
    }
    expect(
      const StudioMailForwardAttachmentsUnavailable().toString(),
      'The complete attachment set cannot be forwarded.',
    );
  });
}
