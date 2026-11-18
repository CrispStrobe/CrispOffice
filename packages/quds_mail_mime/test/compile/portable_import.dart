import 'dart:convert';

import 'package:quds_mail_mime/quds_mail_mime.dart';

import '../fixtures/messages.dart';

void main() {
  final result = const QudsMimeCodec().parse(eml(mixedMessage));
  final message = result.message!;
  print(
    jsonEncode(<String, Object?>{
      'status': result.status.name,
      'subject': message.envelope.subject,
      'plain': message.body.plainText,
      'html': message.body.html,
      'rawSha256': message.raw.sha256,
      'attachments': [
        for (final item in message.attachments)
          <String, Object?>{
            'part': item.partPath,
            'name': item.displayName,
            'sha256': item.content.sha256,
            'size': item.observedSize,
          },
      ],
    }),
  );
}
