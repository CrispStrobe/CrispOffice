import 'dart:convert';

import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_transport/src/cursor.dart';
import 'package:test/test.dart';

final _mailbox = MailMailboxId(
  'INBOX',
  account: MailAccountId(
    'account',
    profile: MailProfileId('cursor-tests', hostId: 'office'),
  ),
);

MailCursor _wire(List<Object?> value) =>
    MailCursor(mailbox: _mailbox, value: jsonEncode(value));

void main() {
  for (final format in ['quds-imap-window-v1', 'quds-imap-discovery-v2']) {
    test('$format keeps its position and migrates from revision zero', () {
      final cursor = ImapScanCursor.decode(
        _wire([format, mailboxScope(_mailbox), 7, 1000000, 4000000000]),
        _mailbox,
      )!;
      expect(cursor.uidValidity, 7);
      expect(cursor.nextUid, 1000000);
      expect(cursor.ceiling, 4000000000);
      expect(cursor.revision, 0);
    });
  }

  test(
    'v3 revisions round-trip exactly at the JavaScript integer boundary',
    () {
      for (final revision in [
        0,
        1,
        ImapScanCursor.maxRevision - 1,
        ImapScanCursor.maxRevision,
      ]) {
        final wire = ImapScanCursor(
          uidValidity: 7,
          nextUid: 1,
          ceiling: 0,
          revision: revision,
        ).encode(_mailbox);
        final parsed = jsonDecode(wire.value) as List<Object?>;
        expect(parsed[0], 'quds-imap-discovery-v3');
        expect(parsed[5], revision);
        expect(ImapScanCursor.decode(wire, _mailbox)!.revision, revision);
      }
    },
  );

  test(
    'v3 rejects invalid revisions instead of rounding or resetting them',
    () {
      for (final revision in <Object?>[
        -1,
        ImapScanCursor.maxRevision + 1,
        0.5,
        '1',
        true,
        null,
      ]) {
        expect(
          () => ImapScanCursor.decode(
            _wire([
              'quds-imap-discovery-v3',
              mailboxScope(_mailbox),
              7,
              1,
              0,
              revision,
            ]),
            _mailbox,
          ),
          throwsFormatException,
        );
      }
    },
  );

  test('cursor versions require their exact shape and mailbox scope', () {
    for (final value in <List<Object?>>[
      [],
      ['quds-imap-discovery-v3'],
      ['quds-imap-discovery-v3', mailboxScope(_mailbox), 7, 1, 0],
      ['quds-imap-discovery-v2', mailboxScope(_mailbox), 7, 1, 0, 1],
      ['quds-imap-discovery-v3', 'another-mailbox', 7, 1, 0, 1],
      ['quds-imap-discovery-v3', mailboxScope(_mailbox), 7, 1, 0, 1, 2],
    ]) {
      expect(
        () => ImapScanCursor.decode(_wire(value), _mailbox),
        throwsFormatException,
      );
    }
  });
}
