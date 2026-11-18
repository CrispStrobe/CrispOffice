import 'dart:typed_data';

import 'package:quds_mail_core/quds_mail_core.dart';

void main() {
  final raw = MailBytes(Uint8List.fromList([0, 13, 10, 255, 128]));
  final message = MailMessage(
    raw: raw,
    envelope: MailEnvelope(subject: 'Portable fixture'),
  );
  final result = MailParseResult(
    status: MailParseStatus.complete,
    message: message,
  );
  if (result.original!.bytes[3] != 255 || raw.sha256.length != 64) {
    throw StateError('Immutable byte projection failed.');
  }
  final profile = MailProfileId('personal', hostId: 'quds.office');
  final session = MailAccountSession(
    MailAccountId('fixture', profile: profile),
  );
  final lease = session.begin();
  session.dispose();
  if (lease.isCurrent) throw StateError('Disposed account retained callbacks.');
  print('core portable fixture: ${raw.sha256}');
}
