import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_office_studio/studio_mail_draft.dart';
import 'package:quds_office_studio/studio_mail_reply.dart';
import 'package:quds_office_studio/studio_mail_submission.dart';

MailMessage _message({
  String subject = 'Decoded source subject',
  String? plain = 'Decoded source body',
  String? html = '<p>HTML fallback must stay out</p>',
  List<MailAddress> from = const [MailAddress('sender@example.invalid')],
  List<MailAddress> replyTo = const [MailAddress('reply@example.invalid')],
  List<MailAddress> to = const [
    MailAddress('original-recipient@example.invalid'),
  ],
  List<MailAddress> cc = const [],
  List<MailAddress> bcc = const [MailAddress('private-bcc@example.invalid')],
  DateTime? sentAt,
  String? messageId,
  String? inReplyTo,
  List<String> references = const [],
}) => MailMessage(
  raw: MailBytes(Uint8List.fromList([1, 2, 3])),
  envelope: MailEnvelope(
    subject: subject,
    from: from,
    replyTo: replyTo,
    to: to,
    cc: cc,
    bcc: bcc,
    sentAt: sentAt,
    messageId: messageId,
    inReplyTo: inReplyTo,
    references: references,
  ),
  body: MailBody(plainText: plain, html: html),
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

  test('HTML-only reply and text forward quote only inert body text', () {
    for (final forward in [false, true]) {
      final draft = buildStudioMailReplyDraft(
        _message(
          plain: null,
          html: '<p>Decoded <b>HTML</b> &amp; café 😀</p>'
              '<script>privateScript()</script>'
              '<style>privateStyle</style>'
              '<form>privateForm</form>'
              '<img src="https://example.invalid/tracker" alt="Image">',
        ),
        forward: forward,
      );
      expect(draft.body, contains('> Decoded HTML & café 😀'));
      expect(draft.body, isNot(contains('privateScript')));
      expect(draft.body, isNot(contains('privateStyle')));
      expect(draft.body, isNot(contains('privateForm')));
      expect(draft.body, isNot(contains('https://')));
      expect(draft.body, isNot(contains('<p>')));
      expect(draft.body, isNot(contains('private-bcc')));
      expect(draft.body, isNot(contains('private-attachment')));
      expect(draft.attachments.isEmpty, isTrue);
    }
  });

  test('missing and malformed HTML bodies produce a typed refusal', () {
    for (final html in <String?>[
      null,
      '<p>Visible prefix</p><a title="unfinished',
      '<p>Visible prefix</p><!-- unfinished',
      '<p>Visible prefix</p><script>unfinished',
    ]) {
      for (final forward in [false, true]) {
        expect(
          () => buildStudioMailReplyDraft(
            _message(plain: null, html: html),
            forward: forward,
          ),
          throwsA(isA<StudioMailReplyUnavailable>()),
        );
      }
    }
    expect(
      const StudioMailReplyUnavailable().toString(),
      'No safely quotable body is available.',
    );
  });

  test('HTML quote cutoff preserves Unicode and reports truncation', () {
    final retained = 'x' * 7999 + '😀';
    final draft = buildStudioMailReplyDraft(
      _message(plain: null, html: '<p>' + retained + 'Omitted</p>'),
      forward: false,
      truncationNotice: '[Quote ended.]',
    );
    expect(draft.body, endsWith(retained + '\n\n[Quote ended.]'));
    expect(draft.body, isNot(contains('Omitted')));
    expect(draft.body, isNot(contains('\uFFFD')));
    expect(utf8.decode(utf8.encode(draft.body)), draft.body);
  });

  test('HTML projection over its input budget refuses the whole quote', () {
    expect(
      () => buildStudioMailReplyDraft(
        _message(plain: null, html: 'x' * (8 * 1024 * 1024 + 1)),
        forward: false,
      ),
      throwsA(isA<StudioMailReplyUnavailable>()),
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
  test('reply attaches only the authoritative decoded parent and ancestry', () {
    final message = _message(
      messageId: '<parent@example.invalid>',
      references: const ['<root@example.invalid>'],
    );
    final draft = buildStudioMailReplyDraft(message, forward: false);
    expect(draft.thread.inReplyTo, '<parent@example.invalid>');
    expect(
      draft.thread.references,
      '<root@example.invalid> <parent@example.invalid>',
    );
    final mime = buildStudioMailMessage(draft, 'writer@example.invalid');
    expect(mime.getHeaderValue('in-reply-to'), '<parent@example.invalid>');
    expect(
      mime.getHeaderValue('references'),
      '<root@example.invalid> <parent@example.invalid>',
    );
    expect(
      mime.getHeaderValue('message-id'),
      isNot('<parent@example.invalid>'),
    );
    expect(message.envelope.references, const ['<root@example.invalid>']);
  });

  test('forwarding starts a new thread even when the source has ancestry', () {
    final forwarded = buildStudioMailReplyDraft(
      _message(
        messageId: '<parent@example.invalid>',
        inReplyTo: '<previous@example.invalid>',
        references: const ['<root@example.invalid>'],
      ),
      forward: true,
    );
    expect(forwarded.thread.inReplyTo, isNull);
    expect(forwarded.thread.references, isNull);
    final addressed = StudioMailDraft(
      to: 'selected@example.invalid',
      subject: forwarded.subject,
      body: forwarded.body,
      thread: forwarded.thread,
    );
    final mime = buildStudioMailMessage(addressed, 'writer@example.invalid');
    expect(mime.getHeaderValue('in-reply-to'), isNull);
    expect(mime.getHeaderValue('references'), isNull);
    expect(mime.to!.single.email, 'selected@example.invalid');
    expect(mime.decodeTextPlainPart(), contains('Decoded source body'));
  });

  test('invalid parent metadata does not block an otherwise valid reply', () {
    final draft = buildStudioMailReplyDraft(
      _message(
        messageId: '<parent@example.invalid>\r\nBcc: hidden@example.invalid',
        references: const ['<root@example.invalid>'],
      ),
      forward: false,
    );
    expect(draft.problem, isNull);
    expect(draft.thread.inReplyTo, isNull);
    expect(draft.thread.references, isNull);
    final mime = buildStudioMailMessage(draft, 'writer@example.invalid');
    expect(mime.getHeaderValue('in-reply-to'), isNull);
    expect(mime.getHeaderValue('references'), isNull);
    expect(mime.getHeaderValue('bcc'), isNull);
    expect(mime.to!.single.email, 'reply@example.invalid');
  });

  test('reply all keeps visible recipient roles and excludes the sender', () {
    final message = _message(
      replyTo: const [
        MailAddress('reply@example.invalid'),
        MailAddress('second-reply@example.invalid'),
      ],
      to: const [
        MailAddress('writer@EXAMPLE.invalid'),
        MailAddress('original-recipient@example.invalid'),
      ],
      cc: const [MailAddress('copied@example.invalid')],
    );
    final draft = buildStudioMailReplyAllDraft(
      message,
      sender: 'writer@example.invalid',
    );
    expect(
      draft.to,
      'reply@example.invalid, second-reply@example.invalid, '
      'original-recipient@example.invalid',
    );
    expect(draft.cc, 'copied@example.invalid');
    expect(draft.bcc, isEmpty);
    expect(draft.problem, isNull);
    expect(draft.body, isNot(contains('private-bcc')));
    expect(draft.body, isNot(contains('copied@example.invalid')));
    expect(message.envelope.to.first.address, 'writer@EXAMPLE.invalid');
    final mime = buildStudioMailMessage(draft, 'writer@example.invalid');
    expect(mime.to!.map((address) => address.email), [
      'reply@example.invalid',
      'second-reply@example.invalid',
      'original-recipient@example.invalid',
    ]);
    expect(mime.cc!.single.email, 'copied@example.invalid');
    expect(mime.getHeaderValue('bcc'), isNull);
  });

  test('reply all uses every From mailbox only when Reply-To is absent', () {
    final draft = buildStudioMailReplyAllDraft(
      _message(
        replyTo: const [],
        from: const [
          MailAddress('first-author@example.invalid'),
          MailAddress('second-author@example.invalid'),
        ],
        to: const [],
      ),
      sender: 'writer@example.invalid',
    );
    expect(
      draft.to,
      'first-author@example.invalid, second-author@example.invalid',
    );
    expect(draft.problem, isNull);
  });

  test(
    'reply all deduplicates with To precedence and exact local-part case',
    () {
      final draft = buildStudioMailReplyAllDraft(
        _message(
          replyTo: const [MailAddress('Author@EXAMPLE.invalid')],
          to: const [
            MailAddress('Author@example.INVALID'),
            MailAddress('author@example.invalid'),
            MailAddress('writer@EXAMPLE.invalid'),
            MailAddress('Writer@example.invalid'),
          ],
          cc: const [
            MailAddress('Author@example.invalid'),
            MailAddress('copied@EXAMPLE.invalid'),
            MailAddress('copied@example.INVALID'),
            MailAddress('writer@example.invalid'),
          ],
        ),
        sender: 'writer@example.invalid',
      );
      expect(
        draft.to,
        'Author@EXAMPLE.invalid, author@example.invalid, Writer@example.invalid',
      );
      expect(draft.cc, 'copied@EXAMPLE.invalid');
      expect(draft.problem, isNull);
    },
  );

  test('reply all from a sent message targets its original participants', () {
    final draft = buildStudioMailReplyAllDraft(
      _message(
        from: const [MailAddress('writer@example.invalid')],
        replyTo: const [],
        to: const [MailAddress('original-recipient@example.invalid')],
        cc: const [MailAddress('copied@example.invalid')],
      ),
      sender: 'writer@example.invalid',
    );
    expect(draft.to, 'original-recipient@example.invalid');
    expect(draft.cc, 'copied@example.invalid');
    expect(draft.problem, isNull);
  });

  test('empty and self-only reply-all targets leave an editable draft', () {
    for (final message in [
      _message(from: const [], replyTo: const [], to: const []),
      _message(
        from: const [MailAddress('writer@example.invalid')],
        replyTo: const [MailAddress('writer@EXAMPLE.invalid')],
        to: const [MailAddress('writer@example.invalid')],
        cc: const [MailAddress('writer@example.invalid')],
      ),
    ]) {
      final draft = buildStudioMailReplyAllDraft(
        message,
        sender: 'writer@example.invalid',
      );
      expect(draft.to, isEmpty);
      expect(draft.cc, isEmpty);
      expect(draft.bcc, isEmpty);
      expect(draft.problem, StudioMailDraftProblem.recipient);
      expect(draft.body, contains('Decoded source body'));
    }
  });

  test('reply all never examines or copies even malformed oversized Bcc', () {
    final draft = buildStudioMailReplyAllDraft(
      _message(
        to: const [],
        bcc: List<MailAddress>.filled(
          1025,
          const MailAddress('private@example.invalid,other@example.invalid'),
        ),
      ),
      sender: 'writer@example.invalid',
    );
    expect(draft.to, 'reply@example.invalid');
    expect(draft.bcc, isEmpty);
    expect(draft.problem, isNull);
    expect(draft.body, isNot(contains('private@example.invalid')));
  });

  test('reply all preserves thread metadata and the bounded plain quote', () {
    final message = _message(
      plain: '${'x' * 7999}😀suffix',
      messageId: '<parent@example.invalid>',
      references: const ['<root@example.invalid>'],
    );
    final draft = buildStudioMailReplyAllDraft(
      message,
      sender: 'writer@example.invalid',
      truncationNotice: '[Quote ended.]',
    );
    expect(draft.thread.inReplyTo, '<parent@example.invalid>');
    expect(
      draft.thread.references,
      '<root@example.invalid> <parent@example.invalid>',
    );
    expect(draft.subject, 'Re: Decoded source subject');
    expect(draft.body, endsWith('😀\n\n[Quote ended.]'));
    expect(draft.body, isNot(contains('suffix')));
    expect(utf8.decode(utf8.encode(draft.body)), draft.body);
    final mime = buildStudioMailMessage(draft, 'writer@example.invalid');
    expect(mime.getHeaderValue('in-reply-to'), '<parent@example.invalid>');
    expect(
      mime.getHeaderValue('references'),
      '<root@example.invalid> <parent@example.invalid>',
    );
  });

  test('HTML-only reply all ignores private metadata and keeps threading', () {
    final draft = buildStudioMailReplyAllDraft(
      _message(
        plain: null,
        html: '<p>Visible body</p><img src="cid:private-part">',
        messageId: '<parent@example.invalid>',
        references: const ['<root@example.invalid>'],
        bcc: List<MailAddress>.filled(
          1025,
          const MailAddress('private@example.invalid,other@example.invalid'),
        ),
      ),
      sender: 'writer@example.invalid',
    );
    expect(draft.body, contains('> Visible body'));
    expect(draft.body, isNot(contains('private@example.invalid')));
    expect(draft.body, isNot(contains('private-attachment-name')));
    expect(draft.body, isNot(contains('private-part')));
    expect(draft.to, 'reply@example.invalid, original-recipient@example.invalid');
    expect(draft.bcc, isEmpty);
    expect(draft.attachments.isEmpty, isTrue);
    expect(draft.thread.inReplyTo, '<parent@example.invalid>');
    expect(
      draft.thread.references,
      '<root@example.invalid> <parent@example.invalid>',
    );
  });

  test(
    'reply all accepts 100 recipients and rejects 101 without truncating',
    () {
      MailMessage messageWith(int count) => _message(
        replyTo: const [],
        from: const [],
        to: List<MailAddress>.generate(
          count,
          (index) => MailAddress('person$index@example.invalid'),
        ),
      );
      final draft = buildStudioMailReplyAllDraft(
        messageWith(100),
        sender: 'writer@example.invalid',
      );
      expect(draft.to.split(', '), hasLength(100));
      expect(draft.problem, isNull);
      expect(
        () => buildStudioMailReplyAllDraft(
          messageWith(101),
          sender: 'writer@example.invalid',
        ),
        throwsA(isA<StudioMailReplyRecipientsUnavailable>()),
      );
    },
  );

  test(
    'reply all bounds source scanning before deduplicating or removing self',
    () {
      MailMessage messageWith(int count) => _message(
        to: List<MailAddress>.filled(
          count,
          const MailAddress('writer@example.invalid'),
        ),
      );
      final draft = buildStudioMailReplyAllDraft(
        messageWith(1023),
        sender: 'writer@example.invalid',
      );
      expect(draft.to, 'reply@example.invalid');
      expect(draft.problem, isNull);
      expect(
        () => buildStudioMailReplyAllDraft(
          messageWith(1024),
          sender: 'writer@example.invalid',
        ),
        throwsA(isA<StudioMailReplyRecipientsUnavailable>()),
      );
    },
  );

  for (final address in [
    'one@example.invalid,two@example.invalid',
    'one@example.invalid;two@example.invalid',
    'one@example.invalid\r\nBcc: hidden@example.invalid',
    'Name <one@example.invalid>',
    'مستخدم@example.invalid',
    'one@',
  ]) {
    test(
      'reply rejects unsupported single source mailbox ${jsonEncode(address)}',
      () {
        expect(
          () => buildStudioMailReplyDraft(
            _message(replyTo: [MailAddress(address)]),
            forward: false,
          ),
          throwsA(isA<StudioMailReplyRecipientsUnavailable>()),
        );
      },
    );
    test(
      'reply all rejects an unsupported participant ${jsonEncode(address)}',
      () {
        for (final message in [
          _message(replyTo: [MailAddress(address)]),
          _message(replyTo: const [], from: [MailAddress(address)]),
          _message(to: [MailAddress(address)]),
          _message(cc: [MailAddress(address)]),
        ]) {
          expect(
            () => buildStudioMailReplyAllDraft(
              message,
              sender: 'writer@example.invalid',
            ),
            throwsA(isA<StudioMailReplyRecipientsUnavailable>()),
          );
        }
      },
    );
  }

  test('invalid Reply-To never falls back to a valid From in reply all', () {
    expect(
      () => buildStudioMailReplyAllDraft(
        _message(replyTo: const [MailAddress('')]),
        sender: 'writer@example.invalid',
      ),
      throwsA(isA<StudioMailReplyRecipientsUnavailable>()),
    );
    expect(
      const StudioMailReplyRecipientsUnavailable().toString(),
      'The source recipient list is unsupported.',
    );
  });

  test('reply all rejects an unsupported connected sender identity', () {
    expect(
      () => buildStudioMailReplyAllDraft(
        _message(),
        sender: 'writer@example.invalid,other@example.invalid',
      ),
      throwsA(isA<StudioMailReplyRecipientsUnavailable>()),
    );
  });

  test(
    'reply all ignores From as a recipient when valid Reply-To is present',
    () {
      final draft = buildStudioMailReplyAllDraft(
        _message(
          from: const [MailAddress('unsupported source author')],
          to: const [],
        ),
        sender: 'writer@example.invalid',
      );
      expect(draft.to, 'reply@example.invalid');
      expect(draft.problem, isNull);
    },
  );

  test('forward never turns a source address into an outgoing recipient', () {
    final draft = buildStudioMailReplyDraft(
      _message(
        from: const [MailAddress('one@example.invalid,two@example.invalid')],
        replyTo: const [MailAddress('one@example.invalid;two@example.invalid')],
      ),
      forward: true,
    );
    expect(draft.to, isEmpty);
    expect(draft.cc, isEmpty);
    expect(draft.bcc, isEmpty);
    expect(draft.problem, StudioMailDraftProblem.recipient);
  });
}
