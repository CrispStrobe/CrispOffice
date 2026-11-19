import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:quds_mail_core/quds_mail_core.dart';

import 'configuration.dart';
import 'errors.dart';

const ewsMaxRevision = 0x1fffffffffffff;
const ewsMaxCursorLength = 16384;

String ewsScope(MailEwsConfiguration configuration, MailMailboxId mailbox) =>
    crypto.sha256
        .convert(
          utf8.encode(
            jsonEncode(<String>[
              mailbox.account.profile.hostId,
              mailbox.account.profile.value,
              mailbox.account.value,
              configuration.endpoint.toString(),
              configuration.username,
              configuration.domain,
              configuration.mailboxAddress ?? '',
              mailbox.value,
            ]),
          ),
        )
        .toString();

MailMessageId ewsMessageId(MailOpaqueIdentity identity) => MailMessageId(
  'ews:${crypto.sha256.convert(utf8.encode(jsonEncode(<String>[identity.account.profile.hostId, identity.account.profile.value, identity.account.value, identity.value])))}',
);

/// A durable local revision prevents identical server SyncStates from allowing
/// an earlier empty/no-change page through the repository's cursor CAS.
final class EwsSyncCursor {
  const EwsSyncCursor({required this.state, required this.revision});
  final String state;
  final int revision;

  MailCursor encode(
    MailEwsConfiguration configuration,
    MailMailboxId mailbox,
    MailEwsLimits limits,
  ) {
    if (state.isEmpty ||
        state.contains(RegExp(r'[\x00-\x1f\x7f]')) ||
        utf8.encode(state).length > limits.maxSyncStateBytes ||
        revision < 1 ||
        revision > ewsMaxRevision) {
      throw const EwsException(MailProblemCode.quotaExceeded);
    }
    final value = jsonEncode(<Object>[
      'quds-ews-sync-v1',
      ewsScope(configuration, mailbox),
      revision,
      state,
    ]);
    if (value.length > ewsMaxCursorLength) {
      throw const EwsException(MailProblemCode.quotaExceeded);
    }
    return MailCursor(mailbox: mailbox, value: value);
  }

  static EwsSyncCursor? decode(
    MailCursor? cursor,
    MailEwsConfiguration configuration,
    MailMailboxId mailbox,
    MailEwsLimits limits,
  ) {
    if (cursor == null) return null;
    try {
      if (cursor.mailbox != mailbox ||
          cursor.value.length > ewsMaxCursorLength) {
        throw const EwsException(MailProblemCode.invalidInput);
      }
      final Object? value = jsonDecode(cursor.value);
      if (value is! List<Object?> ||
          value.length != 4 ||
          value[0] != 'quds-ews-sync-v1' ||
          value[1] != ewsScope(configuration, mailbox)) {
        throw const EwsException(MailProblemCode.invalidInput);
      }
      final revision = value[2];
      final state = value[3];
      if (revision is! int ||
          revision < 1 ||
          revision >= ewsMaxRevision ||
          state is! String ||
          state.isEmpty ||
          state.contains(RegExp(r'[\x00-\x1f\x7f]')) ||
          utf8.encode(state).length > limits.maxSyncStateBytes) {
        throw const EwsException(MailProblemCode.invalidInput);
      }
      return EwsSyncCursor(state: state, revision: revision);
    } on FormatException {
      throw const EwsException(MailProblemCode.invalidInput);
    }
  }
}

/// FindItem offsets are a browsing aid, not a synchronization checkpoint.
final class EwsHeaderCursor {
  const EwsHeaderCursor(this.offset);
  final int offset;

  MailCursor encode(
    MailEwsConfiguration configuration,
    MailMailboxId mailbox,
  ) => MailCursor(
    mailbox: mailbox,
    value: jsonEncode(<Object>[
      'quds-ews-headers-v1',
      ewsScope(configuration, mailbox),
      offset,
    ]),
  );

  static EwsHeaderCursor decode(
    MailCursor? cursor,
    MailEwsConfiguration configuration,
    MailMailboxId mailbox,
  ) {
    if (cursor == null) return const EwsHeaderCursor(0);
    try {
      if (cursor.mailbox != mailbox || cursor.value.length > 256) {
        throw const EwsException(MailProblemCode.invalidInput);
      }
      final Object? value = jsonDecode(cursor.value);
      if (value is! List<Object?> ||
          value.length != 3 ||
          value[0] != 'quds-ews-headers-v1' ||
          value[1] != ewsScope(configuration, mailbox)) {
        throw const EwsException(MailProblemCode.invalidInput);
      }
      final offset = value[2];
      if (offset is! int || offset < 0 || offset > 0x7fffffff) {
        throw const EwsException(MailProblemCode.invalidInput);
      }
      return EwsHeaderCursor(offset);
    } on FormatException {
      throw const EwsException(MailProblemCode.invalidInput);
    }
  }
}
