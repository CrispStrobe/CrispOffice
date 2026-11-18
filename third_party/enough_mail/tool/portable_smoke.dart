// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:convert';
import 'dart:typed_data';

import 'package:enough_mail/mime_core.dart';

/// A native and JavaScript executable exercising only the portable entry.
void main() {
  const fixture =
      'From: Sender <sender@example.invalid>\r\n'
      'To: Reader <reader@example.invalid>\r\n'
      'Date: Wed, 18 Nov 2026 12:00:00 +0000\r\n'
      'Subject: =?utf-8?Q?Portable_hello?=\r\n'
      'MIME-Version: 1.0\r\n'
      'Content-Type: text/plain; charset=utf-8\r\n'
      'Content-Transfer-Encoding: base64\r\n'
      '\r\n'
      'SGVsbG8gZnJvbSBhIHBvcnRhYmxlIHBhcnNlci4=';
  final message = MimeMessage.parseFromData(
    Uint8List.fromList(ascii.encode(fixture)),
  );
  final projection = <String, String>{
    'subject': message.decodeSubject()!,
    'from': message.from!.single.email,
    'to': message.to!.single.email,
    'body': message.decodeTextPlainPart()!,
    'date': message.decodeDate()!.toUtc().toIso8601String(),
  };
  if (projection['subject'] != 'Portable hello' ||
      projection['body'] != 'Hello from a portable parser.') {
    throw StateError('Portable MIME fixture projection did not match.');
  }
  print(jsonEncode(projection));
}
