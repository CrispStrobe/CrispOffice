import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:quds_mail_core/quds_mail_core.dart';

import 'configuration.dart';
import 'http.dart';

const cloudMaxRevision = 0x1fffffffffffff;

String _scope(MailCloudConfiguration configuration, MailMailboxId mailbox) =>
    crypto.sha256
        .convert(
          utf8.encode(
            jsonEncode(<String>[
              configuration.service.name,
              configuration.mailboxAddress.toLowerCase(),
              mailbox.account.profile.hostId,
              mailbox.account.profile.value,
              mailbox.account.value,
              mailbox.value,
            ]),
          ),
        )
        .toString();

MailMessageId cloudMessageId(MailOpaqueIdentity identity) => MailMessageId(
  '${identity.provider.name}:${crypto.sha256.convert(utf8.encode(jsonEncode([identity.account.profile.hostId, identity.account.profile.value, identity.account.value, identity.value])))}',
);

/// Cursors bind both provider credentials' intended mailbox and local ownership.
/// A monotonically increasing revision makes unchanged remote state CAS-safe.
final class CloudCursor {
  const CloudCursor(this.data, {this.revision = 0});

  final Map<String, Object?> data;
  final int revision;

  String string(String key, {bool empty = false}) {
    final value = data[key];
    if (value is! String ||
        (!empty && value.isEmpty) ||
        value.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
      throw const MailCloudException(MailProblem(MailProblemCode.invalidInput));
    }
    return value;
  }

  List<String> strings(String key) {
    final value = data[key];
    if (value is! List<Object?> ||
        value.any(
          (item) =>
              item is! String ||
              item.isEmpty ||
              item.length > 2048 ||
              item.contains(RegExp(r'[\x00-\x1f\x7f]')),
        )) {
      throw const MailCloudException(MailProblem(MailProblemCode.invalidInput));
    }
    return value.cast<String>();
  }

  MailCursor encode(
    MailCloudConfiguration configuration,
    MailMailboxId mailbox,
    MailCloudLimits limits,
    String purpose,
  ) {
    if (revision < 0 || revision >= cloudMaxRevision) {
      throw const MailCloudException(
        MailProblem(MailProblemCode.quotaExceeded),
      );
    }
    final value = jsonEncode({
      'version': 'quds-cloud-v1',
      'scope': _scope(configuration, mailbox),
      'purpose': purpose,
      'revision': revision + 1,
      'data': data,
    });
    if (utf8.encode(value).length > limits.maxCursorBytes) {
      throw const MailCloudException(
        MailProblem(MailProblemCode.quotaExceeded),
      );
    }
    return MailCursor(mailbox: mailbox, value: value);
  }

  static CloudCursor? decode(
    MailCursor? cursor,
    MailCloudConfiguration configuration,
    MailMailboxId mailbox,
    MailCloudLimits limits,
    String purpose,
  ) {
    if (cursor == null) return null;
    try {
      if (cursor.mailbox != mailbox ||
          cursor.value.length > limits.maxCursorBytes ||
          utf8.encode(cursor.value).length > limits.maxCursorBytes) {
        throw const FormatException();
      }
      final Object? value = jsonDecode(cursor.value);
      if (value is! Map<String, Object?> ||
          value['version'] != 'quds-cloud-v1' ||
          value['scope'] != _scope(configuration, mailbox) ||
          value['purpose'] != purpose ||
          value['revision'] is! int ||
          (value['revision'] as int) < 1 ||
          (value['revision'] as int) >= cloudMaxRevision ||
          value['data'] is! Map<String, Object?>) {
        throw const FormatException();
      }
      return CloudCursor(
        value['data']! as Map<String, Object?>,
        revision: value['revision'] as int,
      );
    } on Object {
      throw const MailCloudException(MailProblem(MailProblemCode.invalidInput));
    }
  }
}
