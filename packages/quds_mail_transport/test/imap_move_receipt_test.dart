@TestOn('vm')
library;

import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_transport/src/cursor.dart';
import 'package:quds_mail_transport/src/native/copy_uid.dart';
import 'package:test/test.dart';

import 'support/imap_fixture.dart';

ImapFixture _fixture() => ImapFixture(
  messages: {
    1: FixtureMessage(
      raw: fixtureBytes(
        'From: sender@example.test\r\nSubject: move\r\n\r\nbody',
      ),
    ),
  },
);

MailMove _move(ImapFixture fixture) => MailMove(
  id: 'move:0',
  message: MailImapIdentity(
    mailbox: fixture.mailbox,
    uidValidity: fixture.uidValidity,
    uid: 1,
  ),
  destination: MailMailboxId('Archive', account: fixture.account),
);

void main() {
  for (final delivery in [
    'tagged',
    'untagged',
    'lowercase',
    'other-tagged-code',
    'singleton-range',
  ]) {
    test(
      '$delivery COPYUID preserves exact destination after one UID MOVE',
      () async {
        final fixture = _fixture();
        switch (delivery) {
          case 'tagged':
            fixture.moveResponseCode = 'COPYUID 77 1 9';
          case 'singleton-range':
            fixture.moveResponseCode = 'COPYUID 77 1:1 9:9';
          case 'lowercase':
            fixture.moveUntaggedResponses.add('* ok [copyuid 77 1 9] moved');
          case 'untagged':
            fixture.moveUntaggedResponses.add('* OK [COPYUID 77 1 9] moved');
          case 'other-tagged-code':
            fixture.moveUntaggedResponses.add('* OK [COPYUID 77 1 9] moved');
            fixture.moveResponseCode = 'HIGHESTMODSEQ 123';
        }
        final command = _move(fixture);
        final result = await fixture.provider().applyWithReceipt(
          command,
          MailAccountSession(fixture.account).begin(),
        );
        expect(result, isA<MailSuccess<MailMutationReceipt>>());
        final transition = (result as MailSuccess<MailMutationReceipt>)
            .value
            .identityTransition!;
        final destination = MailImapIdentity(
          mailbox: command.destination,
          uidValidity: 77,
          uid: 9,
        );
        expect(transition.source, command.message);
        expect(transition.sourceMailbox, fixture.mailbox);
        expect(transition.destination, destination);
        expect(transition.destinationMessageId, imapMessageId(destination));
        expect(
          transition.matches(command, sourceMailbox: fixture.mailbox),
          isTrue,
        );
        expect(
          fixture.commands.where((value) => value.startsWith('UID MOVE ')),
          hasLength(1),
        );
        expect(
          fixture.commands.any(
            (value) =>
                value.contains('BODY[]') ||
                value.contains('COPY ') ||
                value.contains('EXPUNGE'),
          ),
          isFalse,
        );
      },
    );
  }

  test(
    'missing COPYUID retains generic success and legacy apply compatibility',
    () async {
      final fixture = _fixture();
      final result = await fixture.provider().applyWithReceipt(
        _move(fixture),
        MailAccountSession(fixture.account).begin(),
      );
      expect(result, isA<MailSuccess<MailMutationReceipt>>());
      expect(
        (result as MailSuccess<MailMutationReceipt>).value.identityTransition,
        isNull,
      );
      final legacy = _fixture()..moveResponseCode = 'COPYUID 77 1 9';
      expect(
        await legacy.provider().apply(
          _move(legacy),
          MailAccountSession(legacy.account).begin(),
        ),
        isA<MailSuccess<MailUnit>>(),
      );
    },
  );

  for (final evidence in [
    'COPYUID 0 1 9',
    'COPYUID 4294967296 1 9',
    'COPYUID 77 2 9',
    'COPYUID 77 1 0',
    'COPYUID 77 1 4294967296',
    'COPYUID 77 1,2 9,10',
    'COPYUID 77 1 9,10',
    'COPYUID 77 1:2 9:10',
    'COPYUID 77 1 *',
    'COPYUID 77 * 9',
    'COPYUID 77 1 9:4294967295',
    'COPYUID 77 01 9',
    'COPYUID 77 1 9 10',
    'COPYUID 77 1',
    'COPYUID',
    'COPYUID ${'9' * 200} 1 9',
  ]) {
    test(
      'malformed COPYUID ${evidence.length < 70 ? evidence : 'oversize'} stays uncertain',
      () async {
        final fixture = _fixture()..moveResponseCode = evidence;
        final result = await fixture.provider().applyWithReceipt(
          _move(fixture),
          MailAccountSession(fixture.account).begin(),
        );
        expect(result, isA<MailFailure<MailMutationReceipt>>());
        expect(
          (result as MailFailure<MailMutationReceipt>)
              .problem
              .mutationMayHaveOccurred,
          isTrue,
        );
        expect(
          fixture.commands.where((value) => value.startsWith('UID MOVE ')),
          hasLength(1),
        );
      },
    );
  }

  for (final kind in ['duplicate', 'conflicting', 'unterminated']) {
    test(
      '$kind untagged COPYUID cannot be hidden by the tagged acknowledgement',
      () async {
        final fixture = _fixture();
        if (kind == 'unterminated') {
          fixture.moveUntaggedResponses.add('* OK [COPYUID 77 1 9');
        } else {
          fixture.moveUntaggedResponses.add('* OK [COPYUID 77 1 9] moved');
          fixture.moveResponseCode = kind == 'duplicate'
              ? 'COPYUID 77 1 9'
              : 'COPYUID 88 1 10';
        }
        final result = await fixture.provider().applyWithReceipt(
          _move(fixture),
          MailAccountSession(fixture.account).begin(),
        );
        expect(result, isA<MailFailure<MailMutationReceipt>>());
        expect(
          (result as MailFailure<MailMutationReceipt>)
              .problem
              .mutationMayHaveOccurred,
          isTrue,
        );
      },
    );
  }

  test('bracketed prose is not authoritative COPYUID evidence', () async {
    final fixture = _fixture()
      ..moveUntaggedResponses.add('* OK prose [COPYUID 77 1 9]');
    final result = await fixture.provider().applyWithReceipt(
      _move(fixture),
      MailAccountSession(fixture.account).begin(),
    );
    expect(result, isA<MailSuccess<MailMutationReceipt>>());
    expect(
      (result as MailSuccess<MailMutationReceipt>).value.identityTransition,
      isNull,
    );
  });

  test(
    'lost acknowledgement never produces a mapping or replays the command',
    () async {
      final fixture = _fixture()
        ..moveResponseCode = 'COPYUID 77 1 9'
        ..closeAfterMutation = true;
      final result = await fixture.provider().applyWithReceipt(
        _move(fixture),
        MailAccountSession(fixture.account).begin(),
      );
      expect(result, isA<MailFailure<MailMutationReceipt>>());
      expect(
        (result as MailFailure<MailMutationReceipt>)
            .problem
            .mutationMayHaveOccurred,
        isTrue,
      );
      expect(
        fixture.commands.where((value) => value.startsWith('UID MOVE ')),
        hasLength(1),
      );
    },
  );

  test('COPYUID parser bounds grammar before interpreting UID sets', () {
    expect(parseSingleCopyUid(null, sourceUid: 1), isNull);
    expect(parseSingleCopyUid('UIDNOTSTICKY', sourceUid: 1), isNull);
    expect(parseSingleCopyUid('COPYUIDPLUS 77 1 9', sourceUid: 1), isNull);
    expect(
      parseSingleCopyUid('COPYUID 4294967295 1 4294967295', sourceUid: 1),
      (uidValidity: 4294967295, uid: 4294967295),
    );
    expect(
      () => parseSingleCopyUid('COPYUID 77 1 9\n', sourceUid: 1),
      throwsFormatException,
    );
  });
}
