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

/// A bounded full-refresh sweep over discovered UIDs. Confirmed closed ranges
/// also reconcile old flags/expunges without enumerating numeric UID holes.
/// Every returned page advances [revision], including empty/completed sweeps,
/// so the same server position cannot reuse a committed compare-and-set token.
final class ImapScanCursor {
  const ImapScanCursor({
    required this.uidValidity,
    required this.nextUid,
    required this.ceiling,
    this.revision = 0,
  });

  /// Largest integer represented exactly by both the VM and JavaScript.
  static const int maxRevision = 0x1fffffffffffff;

  final int uidValidity;
  final int nextUid;
  final int ceiling;
  final int revision;

  MailCursor encode(MailMailboxId mailbox) => MailCursor(
    mailbox: mailbox,
    value: jsonEncode(<Object>[
      'quds-imap-discovery-v3',
      mailboxScope(mailbox),
      uidValidity,
      nextUid,
      ceiling,
      revision,
    ]),
  );

  static ImapScanCursor? decode(MailCursor? cursor, MailMailboxId mailbox) {
    if (cursor == null) return null;
    if (cursor.mailbox != mailbox || cursor.value.length > 256) {
      throw const FormatException('Invalid IMAP cursor scope');
    }
    final Object? value = jsonDecode(cursor.value);
    if (value is! List<Object?>) {
      throw const FormatException('Invalid IMAP cursor');
    }
    final legacy =
        value.length == 5 &&
        (value[0] == 'quds-imap-window-v1' ||
            value[0] == 'quds-imap-discovery-v2');
    final versioned = value.length == 6 && value[0] == 'quds-imap-discovery-v3';
    if ((!legacy && !versioned) || value[1] != mailboxScope(mailbox)) {
      throw const FormatException('Invalid IMAP cursor');
    }
    final validity = value[2];
    final next = value[3];
    final ceiling = value[4];
    final revision = legacy ? 0 : value[5];
    if (validity is! int ||
        validity < 1 ||
        validity > 0xffffffff ||
        next is! int ||
        next < 1 ||
        next > 0xffffffff ||
        ceiling is! int ||
        ceiling < 0 ||
        ceiling > 0xffffffff ||
        revision is! int ||
        revision < 0 ||
        revision > maxRevision ||
        (ceiling == 0 ? next != 1 : next > ceiling)) {
      throw const FormatException('Invalid IMAP cursor position');
    }
    return ImapScanCursor(
      uidValidity: validity,
      nextUid: next,
      ceiling: ceiling,
      revision: revision,
    );
  }
}
