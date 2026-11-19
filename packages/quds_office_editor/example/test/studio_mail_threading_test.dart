import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_mime/quds_mail_mime.dart';
import 'package:quds_office_studio/studio_mail_compose.dart';
import 'package:quds_office_studio/studio_mail_submission.dart';
import 'package:quds_office_studio/studio_mail_threading.dart';

const _parent = '<parent@example.invalid>';
const _root = '<root@example.invalid>';

StudioMailDraft _draft(StudioMailThread thread) => StudioMailDraft(
  to: 'reader@example.invalid',
  subject: 'Re: Threaded reply',
  body: 'Reply body',
  thread: thread,
);

void main() {
  test('empty thread and ordinary const drafts have no reply metadata', () {
    const thread = StudioMailThread.empty();
    const draft = StudioMailDraft(
      to: 'reader@example.invalid',
      subject: 'New conversation',
      body: 'New message',
    );
    expect(thread.inReplyTo, isNull);
    expect(thread.references, isNull);
    expect(draft.thread.inReplyTo, isNull);
    expect(draft.thread.references, isNull);
    final message = buildStudioMailMessage(draft, 'writer@example.invalid');
    expect(message.getHeaderValue('in-reply-to'), isNull);
    expect(message.getHeaderValue('references'), isNull);
  });

  test('a canonical parent starts the references chain without repair', () {
    final thread = StudioMailThread.replyTo(
      MailEnvelope(messageId: _parent),
    );
    expect(thread.inReplyTo, _parent);
    expect(thread.references, _parent);
  });

  test('dot-atom identifiers preserve case and non-DNS atext punctuation', () {
    const ids = [
      '<Local.Part+tag@EXAMPLE.Invalid>',
      r"<a!#$%&'*+-/=?^_{|}~@host!+>",
      '<a@localhost>',
    ];
    for (final id in ids) {
      final thread = StudioMailThread.replyTo(MailEnvelope(messageId: id));
      expect(thread.inReplyTo, id);
      expect(thread.references, id);
    }
    final tick = '<a${String.fromCharCode(96)}@host>';
    expect(
      StudioMailThread.replyTo(MailEnvelope(messageId: tick)).inReplyTo,
      tick,
    );
  });

  test('missing parent cannot infer a reply identity from its ancestors', () {
    final thread = StudioMailThread.replyTo(
      MailEnvelope(inReplyTo: _root, references: const [_root]),
    );
    expect(thread.inReplyTo, isNull);
    expect(thread.references, isNull);
  });

  test('malformed parents omit both headers even with valid ancestors', () {
    final invalid = <String>[
      '',
      'parent@example.invalid',
      ' <parent@example.invalid>',
      '<parent@example.invalid> ',
      '<parent@example.invalid>\n',
      '<parent@example.invalid>\r',
      '<parent@example.invalid>\r\n',
      '<parent@example.invalid',
      'parent@example.invalid>',
      '<<parent@example.invalid>>',
      '<parent@example.invalid> <other@example.invalid>',
      '<parent@example.invalid>\r\nBcc: hidden@example.invalid',
      '<par\nent@example.invalid>',
      '<par\rent@example.invalid>',
      '<par\tent@example.invalid>',
      '<par\u0000ent@example.invalid>',
      '<par\u007fent@example.invalid>',
      '<par\u0085ent@example.invalid>',
      '<p\u202earent@example.invalid>',
      '<مستخدم@example.invalid>',
      '<@example.invalid>',
      '<parent@>',
      '<parent@@example.invalid>',
      '<.parent@example.invalid>',
      '<parent.@example.invalid>',
      '<par..ent@example.invalid>',
      '<parent@.example.invalid>',
      '<parent@example..invalid>',
      '<parent@example.invalid.>',
      '<"quoted"@example.invalid>',
      '<parent@[127.0.0.1]>',
      '<parent(comment)@example.invalid>',
      '<parent@example.invalid>(comment)',
    ];
    for (final id in invalid) {
      final thread = StudioMailThread.replyTo(
        MailEnvelope(
          messageId: id,
          inReplyTo: _root,
          references: const [_root],
        ),
      );
      expect(thread.inReplyTo, isNull, reason: jsonEncode(id));
      expect(thread.references, isNull, reason: jsonEncode(id));
      final mime = buildStudioMailMessage(
        _draft(thread),
        'writer@example.invalid',
      );
      expect(mime.getHeaderValue('in-reply-to'), isNull);
      expect(mime.getHeaderValue('references'), isNull);
      expect(mime.getHeaderValue('bcc'), isNull);
    }
  });

  test('identifier length admits 254 ASCII bytes and rejects 255', () {
    final boundary = '<${'x' * 236}@example.invalid>';
    expect(boundary.length, 254);
    expect(
      StudioMailThread.replyTo(MailEnvelope(messageId: boundary)).inReplyTo,
      boundary,
    );
    final oversized = '<x${'x' * 236}@example.invalid>';
    expect(oversized.length, 255);
    final rejected = StudioMailThread.replyTo(
      MailEnvelope(messageId: oversized, references: const [_root]),
    );
    expect(rejected.inReplyTo, isNull);
    expect(rejected.references, isNull);
  });

  test('valid ancestors are retained in order and the parent is last once', () {
    final thread = StudioMailThread.replyTo(
      MailEnvelope(
        messageId: _parent,
        references: const [
          _root,
          '<middle@example.invalid>',
          _parent,
          _root,
          '<middle@example.invalid>',
          _parent,
        ],
      ),
    );
    expect(thread.inReplyTo, _parent);
    expect(
      thread.references,
      '$_root <middle@example.invalid> $_parent',
    );
  });

  test('message identifiers remain distinct when their case differs', () {
    final thread = StudioMailThread.replyTo(
      MailEnvelope(
        messageId: '<Parent@EXAMPLE.invalid>',
        references: const [
          '<Root@example.invalid>',
          '<root@example.invalid>',
          '<Parent@example.invalid>',
          '<Parent@EXAMPLE.invalid>',
        ],
      ),
    );
    expect(
      thread.references,
      '<Root@example.invalid> <root@example.invalid> '
      '<Parent@example.invalid> <Parent@EXAMPLE.invalid>',
    );
  });

  test('one invalid ancestor discards the complete inherited chain', () {
    final thread = StudioMailThread.replyTo(
      MailEnvelope(
        messageId: _parent,
        references: const [
          '<bad@example.invalid>\r\nX-Injected: yes',
          _root,
          'broken',
          '<middle@example.invalid>',
          '<two@example.invalid> <ids@example.invalid>',
          '<unicode@例.invalid>',
        ],
      ),
    );
    expect(thread.inReplyTo, _parent);
    expect(thread.references, _parent);
    final mime = buildStudioMailMessage(
      _draft(thread),
      'writer@example.invalid',
    );
    expect(mime.getHeaderValue('x-injected'), isNull);
  });

  test('comment fragments cannot donate message IDs to inherited ancestry', () {
    const raw =
        'From: sender@example.invalid\r\n'
        'Subject: Source with commented ancestry\r\n'
        'Message-ID: <parent@example.invalid>\r\n'
        'In-Reply-To: <fallback@example.invalid>\r\n'
        'References: <root@example.invalid> '
        '(comment <unrelated@example.invalid> end)\r\n'
        'Content-Type: text/plain; charset=utf-8\r\n'
        '\r\n'
        'Source body';
    final source = const QudsMimeCodec().parse(
      Uint8List.fromList(utf8.encode(raw)),
    );
    expect(source.message, isNotNull);
    final thread = StudioMailThread.replyTo(source.message!.envelope);
    expect(thread.inReplyTo, _parent);
    expect(thread.references, _parent);
    final mime = buildStudioMailMessage(
      _draft(thread),
      'writer@example.invalid',
    );
    expect(mime.getHeaderValue('references'), _parent);
    expect(
      mime.getHeaderValue('references'),
      isNot(contains('unrelated@example.invalid')),
    );
  });

  test('adjacent IDs in one reference token cannot supply ancestry', () {
    final thread = StudioMailThread.replyTo(
      MailEnvelope(
        messageId: _parent,
        inReplyTo: '<fallback@example.invalid>',
        references: const [
          _root,
          '<a@b><c@d>',
          '<latest@example.invalid>',
        ],
      ),
    );
    expect(thread.inReplyTo, _parent);
    expect(thread.references, _parent);
    final mime = buildStudioMailMessage(
      _draft(thread),
      'writer@example.invalid',
    );
    expect(mime.getHeaderValue('references'), _parent);
  });

  test(
    'an absent References chain falls back to one canonical In-Reply-To',
    () {
      final thread = StudioMailThread.replyTo(
        MailEnvelope(messageId: _parent, inReplyTo: _root),
      );
      expect(thread.inReplyTo, _parent);
      expect(thread.references, '$_root $_parent');
    },
  );

  test('nonempty malformed References never activate In-Reply-To fallback', () {
    final thread = StudioMailThread.replyTo(
      MailEnvelope(
        messageId: _parent,
        inReplyTo: _root,
        references: const ['', 'broken', '<invalid>'],
      ),
    );
    expect(thread.inReplyTo, _parent);
    expect(thread.references, _parent);
  });

  test('a valid References chain takes precedence over In-Reply-To', () {
    final thread = StudioMailThread.replyTo(
      MailEnvelope(
        messageId: _parent,
        inReplyTo: '<other-conversation@example.invalid>',
        references: const [_root],
      ),
    );
    expect(thread.references, '$_root $_parent');
  });

  test('ambiguous or injected In-Reply-To is never copied as fallback', () {
    for (final ancestor in [
      '<one@example.invalid> <two@example.invalid>',
      '<one@example.invalid>\r\nBcc: hidden@example.invalid',
      ' <one@example.invalid>',
      'one@example.invalid',
      '',
    ]) {
      final thread = StudioMailThread.replyTo(
        MailEnvelope(messageId: _parent, inReplyTo: ancestor),
      );
      expect(thread.references, _parent, reason: jsonEncode(ancestor));
    }
  });

  test('a fallback equal to the parent does not duplicate the parent', () {
    final thread = StudioMailThread.replyTo(
      MailEnvelope(messageId: _parent, inReplyTo: _parent),
    );
    expect(thread.references, _parent);
  });

  test('long chains retain the root and newest fitting contiguous tail', () {
    final ancestors = List.generate(
      64,
      (index) => '<r${index.toString().padLeft(3, '0')}@example.invalid>',
    );
    final thread = StudioMailThread.replyTo(
      MailEnvelope(messageId: _parent, references: ancestors),
    );
    expect(
      thread.references?.split(' '),
      [ancestors.first, ...ancestors.sublist(27), _parent],
    );
    expect(thread.references?.length, 898);
    expect(thread.inReplyTo, _parent);
  });

  test(
    'exactly 900 reference bytes fit and an older overflow ID is dropped',
    () {
      final oldest = '<${'a' * 236}@example.invalid>';
      final middle = '<${'b' * 236}@example.invalid>';
      final newest = '<${'c' * 236}@example.invalid>';
      final nearParent = '<${'d' * 69}@example.invalid>';
      final ancestors = [_root, oldest, middle, newest, nearParent];
      final expected = [...ancestors, _parent].join(' ');
      expect(expected.length, 900);
      final exact = StudioMailThread.replyTo(
        MailEnvelope(messageId: _parent, references: ancestors),
      );
      expect(exact.references, expected);
      final overflow = StudioMailThread.replyTo(
        MailEnvelope(
          messageId: _parent,
          references: [
            _root,
            '<older@example.invalid>',
            oldest,
            middle,
            newest,
            nearParent,
          ],
        ),
      );
      expect(overflow.references, expected);
      expect(overflow.references, isNot(contains('<older@example.invalid>')));
      expect(overflow.inReplyTo, _parent);
    },
  );

  test(
    '254-byte identifiers survive MIME without being split or rewritten',
    () {
      final parent = '<${'p' * 236}@example.invalid>';
      final ancestor = '<${'a' * 236}@example.invalid>';
      expect(parent.length, 254);
      expect(ancestor.length, 254);
      final thread = StudioMailThread.replyTo(
        MailEnvelope(messageId: parent, references: [ancestor]),
      );
      final mime = buildStudioMailMessage(
        _draft(thread),
        'writer@example.invalid',
      );
      final rendered = mime.renderMessage();
      expect(rendered, contains(parent));
      expect(rendered, contains(ancestor));
      final decoded = const QudsMimeCodec().parse(
        Uint8List.fromList(utf8.encode(rendered)),
      );
      expect(decoded.message, isNotNull);
      expect(decoded.message!.envelope.inReplyTo, parent);
      expect(decoded.message!.envelope.references, [ancestor, parent]);
      final headerEnd = rendered.indexOf('\r\n\r\n');
      expect(headerEnd, greaterThan(0));
      expect(
        rendered
            .substring(0, headerEnd)
            .split('\r\n')
            .every((line) => line.length <= 998),
        isTrue,
      );
    },
  );

  test('a 1024-entry source keeps bounded root and tail ancestry', () {
    final ancestors = List.generate(
      1024,
      (index) => '<r$index@example.invalid>',
    );
    final thread = StudioMailThread.replyTo(
      MailEnvelope(messageId: _parent, references: ancestors),
    );
    final retained = thread.references!.split(' ');
    expect(retained.first, ancestors.first);
    expect(retained[retained.length - 2], ancestors.last);
    expect(retained.last, _parent);
    expect(thread.references!.length, lessThanOrEqualTo(900));
  });

  test('an oversized source chain preserves only the valid parent', () {
    final thread = StudioMailThread.replyTo(
      MailEnvelope(
        messageId: _parent,
        inReplyTo: _root,
        references: List.filled(1025, _root),
      ),
    );
    expect(thread.inReplyTo, _parent);
    expect(thread.references, _parent);
  });

  test('a reply thread is a stable snapshot of source ancestry', () {
    final references = <String>[_root];
    final thread = StudioMailThread.replyTo(
      MailEnvelope(messageId: _parent, references: references),
    );
    references
      ..clear()
      ..add('<unrelated@example.invalid>');
    expect(thread.references, '$_root $_parent');
  });

  test(
    'thread headers survive MIME serialization with bounded ASCII lines',
    () {
      final ancestors = List.generate(
        64,
        (index) => '<r${index.toString().padLeft(3, '0')}@example.invalid>',
      );
      final thread = StudioMailThread.replyTo(
        MailEnvelope(messageId: _parent, references: ancestors),
      );
      final mime = buildStudioMailMessage(
        _draft(thread),
        'writer@example.invalid',
      );
      final rendered = mime.renderMessage();
      final separator = rendered.indexOf('\r\n\r\n');
      expect(separator, greaterThan(0));
      final headers = rendered.substring(0, separator);
      expect(headers.codeUnits.every((unit) => unit < 128), isTrue);
      expect(
        headers.split('\r\n').every((line) => line.length <= 998),
        isTrue,
      );
      final decoded = const QudsMimeCodec().parse(
        Uint8List.fromList(utf8.encode(rendered)),
      );
      expect(decoded.message, isNotNull);
      expect(decoded.message!.envelope.inReplyTo, _parent);
      expect(
        decoded.message!.envelope.references,
        thread.references!.split(' '),
      );
      expect(decoded.message!.envelope.messageId, isNotNull);
      expect(decoded.message!.envelope.messageId, isNot(_parent));
      expect(decoded.message!.body.plainText, contains('Reply body'));
    },
  );

  test('folded source ancestry survives the decode-reply-encode boundary', () {
    const raw =
        'From: sender@example.invalid\r\n'
        'To: reader@example.invalid\r\n'
        'Subject: Source\r\n'
        'Message-ID: <parent@example.invalid>\r\n'
        'References: <root@example.invalid>\r\n'
        ' <middle@example.invalid>\r\n'
        'Content-Type: text/plain; charset=utf-8\r\n'
        '\r\n'
        'Source body';
    final source = const QudsMimeCodec().parse(
      Uint8List.fromList(utf8.encode(raw)),
    );
    expect(source.message, isNotNull);
    final thread = StudioMailThread.replyTo(source.message!.envelope);
    final mime = buildStudioMailMessage(
      _draft(thread),
      'writer@example.invalid',
    );
    final decoded = const QudsMimeCodec().parse(
      Uint8List.fromList(utf8.encode(mime.renderMessage())),
    );
    expect(decoded.message, isNotNull);
    expect(decoded.message!.envelope.inReplyTo, _parent);
    expect(decoded.message!.envelope.references, const [
      _root,
      '<middle@example.invalid>',
      _parent,
    ]);
  });
}
