import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'file:///workspace/scratch/32e3793609d8/quds_office_suite/packages/quds_office_editor/example/lib/studio_mail_draft.dart';
import 'file:///workspace/scratch/32e3793609d8/quds_office_suite/packages/quds_office_editor/example/lib/studio_mail_threading.dart';

const _parent = '<parent@example.invalid>';
const _root = '<root@example.invalid>';

StudioMailDraft _draft(StudioMailThread thread) => StudioMailDraft(
  to: 'reader@example.invalid',
  subject: 'Re: Threaded reply',
  body: 'Reply body',
  thread: thread,
);

void main() {
  

  test('a canonical parent starts the references chain without repair', () {
    final thread = StudioMailThread.replyTo(MailEnvelope(messageId: _parent));
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
    expect(thread.references, '$_root <middle@example.invalid> $_parent');
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
    expect(thread.references?.split(' '), [
      ancestors.first,
      ...ancestors.sublist(27),
      _parent,
    ]);
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

  

  
}
