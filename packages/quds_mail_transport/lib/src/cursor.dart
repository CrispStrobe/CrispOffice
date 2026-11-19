import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:quds_mail_core/quds_mail_core.dart';

String mailboxScope(MailMailboxId mailbox) => crypto.sha256
    .convert(
      utf8.encode(
        jsonEncode(<String>[
          mailbox.account.profile.hostId,
          mailbox.account.profile.value,
          mailbox.account.value,
          mailbox.value,
        ]),
      ),
    )
    .toString();

MailMessageId imapMessageId(MailImapIdentity identity) => MailMessageId(
  'imap:${mailboxScope(identity.mailbox)}:${identity.uidValidity}:${identity.uid}',
);

/// A bounded full-refresh sweep. UID windows also reconcile old flags/expunges.
final class ImapScanCursor {
  const ImapScanCursor({
    required this.uidValidity,
    required this.nextUid,
    required this.ceiling,
  });

  final int uidValidity;
  final int nextUid;
  final int ceiling;

  MailCursor encode(MailMailboxId mailbox) => MailCursor(
    mailbox: mailbox,
    value: jsonEncode(<Object>[
      'quds-imap-window-v1',
      mailboxScope(mailbox),
      uidValidity,
      nextUid,
      ceiling,
    ]),
  );

  static ImapScanCursor? decode(MailCursor? cursor, MailMailboxId mailbox) {
    if (cursor == null) return null;
    if (cursor.mailbox != mailbox || cursor.value.length > 256) {
      throw const FormatException('Invalid IMAP cursor scope');
    }
    final Object? value = jsonDecode(cursor.value);
    if (value is! List<Object?> ||
        value.length != 5 ||
        value[0] != 'quds-imap-window-v1' ||
        value[1] != mailboxScope(mailbox)) {
      throw const FormatException('Invalid IMAP cursor');
    }
    final validity = value[2];
    final next = value[3];
    final ceiling = value[4];
    if (validity is! int ||
        validity < 1 ||
        validity > 0xffffffff ||
        next is! int ||
        next < 1 ||
        next > 0xffffffff ||
        ceiling is! int ||
        ceiling < 0 ||
        ceiling > 0xffffffff ||
        (ceiling == 0 ? next != 1 : next > ceiling)) {
      throw const FormatException('Invalid IMAP cursor position');
    }
    return ImapScanCursor(
      uidValidity: validity,
      nextUid: next,
      ceiling: ceiling,
    );
  }
}
