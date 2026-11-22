import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:test/test.dart';

MailConversationEntry _row(
  String id, {
  String account = 'account-a',
  String? messageId,
  String? replyTo,
  String? conversationId,
  List<String> refs = const [],
}) => MailConversationEntry(
  id: id,
  accountId: account,
  messageId: messageId,
  inReplyTo: replyTo,
  conversationId: conversationId,
  references: refs,
);

List<List<String>> _groups(List<MailConversationEntry> rows) =>
    groupMailConversations(
      rows,
    ).map((group) => group.entries.map((row) => row.id).toList()).toList();

void main() {
  group('explicit conversation links', () {
    test('keeps loaded order and never infers from subject or sender', () {
      final rows = [
        _row('parent', messageId: '<parent@example.test>'),
        _row('unrelated', messageId: '<other@example.test>'),
        _row(
          'reply',
          messageId: '<reply@example.test>',
          replyTo: '<parent@example.test>',
        ),
        _row(
          'grandchild',
          messageId: '<next@example.test>',
          refs: ['<parent@example.test>', '<reply@example.test>'],
        ),
        _row('same-subject-no-headers'),
      ];
      expect(_groups(rows), [
        ['parent', 'reply', 'grandchild'],
        ['unrelated'],
        ['same-subject-no-headers'],
      ]);
    });

    test('links siblings even when the common parent was not loaded', () {
      expect(
        _groups([
          _row('first', replyTo: '<missing@example.test>'),
          _row('other', replyTo: '<someone-else@example.test>'),
          _row('second', refs: ['<missing@example.test>']),
        ]),
        [
          ['first', 'second'],
          ['other'],
        ],
      );
    });

    test('persistent keys join incomplete cross-folder rows', () {
      expect(
        _groups([
          _row('inbox', conversationId: 'conv:root@example.test'),
          _row('sent', conversationId: 'conv:root@example.test'),
          _row('unrelated', messageId: '<other@example.test>'),
          _row('other', conversationId: 'conv:root@example.test', account: 'b'),
        ]),
        [
          ['inbox', 'sent'],
          ['unrelated'],
          ['other'],
        ],
      );
    });

    test('never merges identical RFC IDs across account namespaces', () {
      expect(
        _groups([
          _row('one', messageId: '<shared@example.test>'),
          _row('two', account: 'account-b', replyTo: '<shared@example.test>'),
          _row('three', account: 'account-a', replyTo: '<shared@example.test>'),
          _row(
            'four',
            account: 'account-b',
            messageId: '<shared@example.test>',
          ),
        ]),
        [
          ['one', 'three'],
          ['two', 'four'],
        ],
      );
    });

    test('groups repeated RFC IDs but preserves distinct mailbox row IDs', () {
      expect(
        _groups([
          _row('inbox-copy', messageId: '<same@example.test>'),
          _row('sent-copy', messageId: '<same@example.test>'),
          _row('reply', replyTo: '<same@example.test>'),
        ]),
        [
          ['inbox-copy', 'sent-copy', 'reply'],
        ],
      );
    });

    test('malformed references cannot connect other valid tokens', () {
      expect(
        _groups([
          _row('parent', messageId: '<parent@example.test>'),
          _row(
            'bad-chain',
            refs: [
              '<parent@example.test>',
              '(comment)',
              '<other@example.test>',
            ],
          ),
          _row('bad-whitespace', replyTo: ' <parent@example.test>'),
          _row('bare', replyTo: 'parent@example.test'),
          _row('quoted', replyTo: '<"bad id"@example.test>'),
        ]),
        [
          ['parent'],
          ['bad-chain'],
          ['bad-whitespace'],
          ['bare'],
          ['quoted'],
        ],
      );
    });

    test(
      'limits excessive reference lists without trusting a partial tail',
      () {
        final refs = List<String>.generate(
          MailConversationEntry.maxReferences + 1,
          (index) => '<id$index@example.test>',
        );
        final candidate = _row('candidate', refs: refs);
        expect(candidate.references, isEmpty);
        expect(_groups([_row('known', messageId: refs.first), candidate]), [
          ['known'],
          ['candidate'],
        ]);
      },
    );

    test('keeps case-sensitive local parts and rejects bad dot atoms', () {
      expect(
        _groups([
          _row('upper', messageId: '<ID@example.test>'),
          _row('lower', replyTo: '<id@example.test>'),
          _row('match', replyTo: '<ID@example.test>'),
          _row('dot', replyTo: '<bad..id@example.test>'),
          _row('domain-literal', replyTo: '<id@[127.0.0.1]>'),
        ]),
        [
          ['upper', 'match'],
          ['lower'],
          ['dot'],
          ['domain-literal'],
        ],
      );
    });

    test('handles self cycles and duplicate ancestor references', () {
      expect(
        _groups([
          _row('a', messageId: '<a@example.test>', replyTo: '<b@example.test>'),
          _row(
            'b',
            messageId: '<b@example.test>',
            refs: ['<a@example.test>', '<a@example.test>'],
          ),
        ]),
        [
          ['a', 'b'],
        ],
      );
    });

    test(
      'retains sort order, returns immutable snapshots, and validates IDs',
      () {
        final references = ['<missing@example.test>'];
        final entry = _row('reply', refs: references);
        references.clear();
        expect(entry.references, ['<missing@example.test>']);
        expect(() => entry.references.add('x'), throwsUnsupportedError);
        final source = [
          entry,
          _row('solo'),
          _row('sibling', replyTo: '<missing@example.test>'),
        ];
        final grouped = groupMailConversations(source);
        expect(grouped.map((g) => g.length).toList(), [2, 1]);
        expect(grouped.first.hasReplies, isTrue);
        expect(grouped.last.hasReplies, isFalse);
        expect(() => grouped.clear(), throwsUnsupportedError);
        expect(() => grouped.first.entries.clear(), throwsUnsupportedError);
        expect(source.map((row) => row.id), ['reply', 'solo', 'sibling']);
        expect(() => _row(''), throwsArgumentError);
        expect(() => _row('x', account: ''), throwsArgumentError);
        expect(
          () => groupMailConversations([_row('x'), _row('x')]),
          throwsArgumentError,
        );
        expect(_groups([_row('x'), _row('x', account: 'other')]), [
          ['x'],
          ['x'],
        ]);
      },
    );

    test(
      'persistent key prefers complete references, then reply, then own ID',
      () {
        expect(
          MailConversationKey.fromParts(
            messageId: '<own@example.test>',
            inReplyTo: '<parent@example.test>',
            references: const ['<root@example.test>', '<parent@example.test>'],
            fallbackId: 'row',
          ),
          '<root@example.test>',
        );
        expect(
          MailConversationKey.fromParts(
            messageId: '<own@example.test>',
            inReplyTo: '<parent@example.test>',
            references: const ['<root@example.test>', 'invalid'],
            fallbackId: 'row',
          ),
          '<parent@example.test>',
        );
        expect(
          MailConversationKey.fromParts(
            messageId: '<own@example.test>',
            fallbackId: 'row',
          ),
          '<own@example.test>',
        );
        expect(
          MailConversationKey.fromParts(
            messageId: 'not-an-id',
            fallbackId: 'row',
          ),
          'local:row',
        );
        expect(
          () => MailConversationKey.fromParts(fallbackId: ''),
          throwsArgumentError,
        );
      },
    );

    test('empty input is safe and unmodifiable', () {
      final result = groupMailConversations([]);
      expect(result, isEmpty);
      expect(
        () => result.add(groupMailConversations([_row('a')]).single),
        throwsUnsupportedError,
      );
    });
  });
}
