import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_office_studio/studio_mail_compose.dart';
import 'package:quds_office_studio/studio_mail_reply.dart';
import 'package:quds_office_studio/studio_mail_submission.dart';

MailMessage _message({
  String subject = 'Decoded source subject',
  String? plain = 'Decoded source body',
  List<MailAddress> from = const [MailAddress('sender@example.invalid')],
  List<MailAddress> replyTo = const [MailAddress('reply@example.invalid')],
  DateTime? sentAt,
}) => MailMessage(
  raw: MailBytes(Uint8List.fromList([1, 2, 3])),
  envelope: MailEnvelope(
    subject: subject,
    from: from,
    replyTo: replyTo,
    to: const [MailAddress('original-recipient@example.invalid')],
    bcc: const [MailAddress('private-bcc@example.invalid')],
    sentAt: sentAt,
  ),
  body: MailBody(plainText: plain, html: '<p>HTML fallback must stay out</p>'),
  attachments: [
    MailAttachment(
      partPath: '2',
      mediaType: 'text/plain',
      displayName: 'private-attachment-name.txt',
      content: MailBytes(Uint8List.fromList([42])),
    ),
  ],
);

void main() {
  test(
    'reply uses authoritative Reply-To and quotes only decoded plain body',
    () {
      final message = _message(
        plain: 'Café مرحبًا 😀\r\n  Preserve indentation\rFinal line',
        sentAt: DateTime.parse('2026-11-19T10:15:00+02:00'),
      );
      final draft = buildStudioMailReplyDraft(message, forward: false);
      expect(draft.to, 'reply@example.invalid');
      expect(draft.subject, 'Re: Decoded source subject');
      expect(
        draft.body,
        '\n\nOn 2026-11-19T08:15:00.000Z, sender@example.invalid wrote:\n'
        '> Café مرحبًا 😀\n>   Preserve indentation\n> Final line',
      );
      expect(draft.problem, isNull);
      expect(draft.body, isNot(contains('private-bcc')));
      expect(draft.body, isNot(contains('private-attachment')));
      expect(draft.body, isNot(contains('original-recipient')));
      expect(draft.body, isNot(contains('HTML fallback')));
      expect(message.body.plainText, contains('\r\n'));
    },
  );

  test('reply falls back to From when no Reply-To exists', () {
    final draft = buildStudioMailReplyDraft(
      _message(replyTo: const []),
      forward: false,
    );
    expect(draft.to, 'sender@example.invalid');
    expect(draft.body, startsWith('\n\nsender@example.invalid wrote:\n'));
  });

  test(
    'missing source addresses require an explicit recipient before send',
    () {
      final draft = buildStudioMailReplyDraft(
        _message(from: const [], replyTo: const []),
        forward: false,
      );
      expect(draft.to, isEmpty);
      expect(draft.problem, StudioMailDraftProblem.recipient);
    },
  );

  test('forward requires a recipient and declares the text-only boundary', () {
    final draft = buildStudioMailReplyDraft(
      _message(),
      forward: true,
      forwardNotice: '[Nur Text; keine Anhänge.]',
    );
    expect(draft.to, isEmpty);
    expect(draft.subject, 'Fwd: Decoded source subject');
    expect(draft.problem, StudioMailDraftProblem.recipient);
    expect(draft.body, contains('[Nur Text; keine Anhänge.]'));
    expect(draft.body, contains('From: sender@example.invalid'));
    expect(draft.body, endsWith('> Decoded source body'));
    expect(draft.body, isNot(contains('private-bcc')));
    expect(draft.body, isNot(contains('private-attachment')));
    expect(draft.body, isNot(contains('HTML fallback')));
  });

  for (final (forward, subject) in [
    (false, 'rE: Existing'),
    (true, 'FwD: Existing'),
  ]) {
    test(
      'existing ${forward ? 'forward' : 'reply'} prefix is not duplicated',
      () {
        final draft = buildStudioMailReplyDraft(
          _message(subject: subject),
          forward: forward,
        );
        expect(draft.subject, subject);
      },
    );
  }

  test(
    'quote cutoff preserves an emoji and explicitly identifies truncation',
    () {
      final retained = '${''.padRight(7999, 'a')}😀';
      final draft = buildStudioMailReplyDraft(
        _message(plain: '${retained}Omitted suffix'),
        forward: false,
        truncationNotice: '[Zitat gekürzt.]',
      );
      expect(draft.body, endsWith('> $retained\n\n[Zitat gekürzt.]'));
      expect(draft.body, isNot(contains('Omitted suffix')));
      expect(draft.body, isNot(contains('\uFFFD')));
      expect(utf8.decode(utf8.encode(draft.body)), draft.body);
      expect(
        buildStudioMailMessage(
          draft,
          'writer@example.invalid',
        ).decodeTextPlainPart(),
        draft.body.replaceAll('\n', '\r\n'),
      );
    },
  );

  test('an exact-boundary quote is preserved without a truncation notice', () {
    final body = ''.padRight(8000, 'x');
    final draft = buildStudioMailReplyDraft(
      _message(plain: body),
      forward: false,
    );
    expect(draft.body, endsWith('> $body'));
    expect(draft.body, isNot(contains('[Quoted text truncated.]')));
  });

  test('HTML-only bodies produce a fixed typed unavailable outcome', () {
    for (final forward in [false, true]) {
      expect(
        () =>
            buildStudioMailReplyDraft(_message(plain: null), forward: forward),
        throwsA(isA<StudioMailReplyUnavailable>()),
      );
    }
    expect(
      const StudioMailReplyUnavailable().toString(),
      'No decoded plain-text body is available.',
    );
  });

  test('an explicitly empty plain body never falls back to HTML', () {
    final draft = buildStudioMailReplyDraft(
      _message(plain: ''),
      forward: false,
    );
    expect(draft.body, endsWith('> '));
    expect(draft.body, isNot(contains('HTML fallback')));
  });
}
