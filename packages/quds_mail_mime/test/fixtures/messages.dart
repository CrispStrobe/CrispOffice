import 'dart:convert';
import 'dart:typed_data';

/// Independently authored synthetic RFC messages, containing no real mail.
Uint8List eml(String source) => Uint8List.fromList(utf8.encode(source));

const simpleMessage =
    'From: =?UTF-8?Q?M=C3=BCller?= <writer@example.invalid>\r\n'
    'To: Reader <reader@example.invalid>\r\n'
    'Subject: =?UTF-8?B?SGVsbG8g4oKs?=\r\n'
    'Date: Wed, 18 Nov 2026 13:30:00 +0100\r\n'
    'Message-ID: <synthetic-1@example.invalid>\r\n'
    'Content-Type: text/plain; charset=utf-8\r\n'
    'Content-Transfer-Encoding: quoted-printable\r\n'
    '\r\nHello =E2=82=AC.\r\n';

const mixedMessage =
    'From: Example <writer@example.invalid>\r\n'
    'Subject: Original attachment fixture\r\n'
    'Content-Type: multipart/mixed; boundary="outer"\r\n\r\n'
    'This preamble is not the displayed body.\r\n'
    '--outer\r\nContent-Type: multipart/alternative; boundary=alt\r\n\r\n'
    '--alt\r\nContent-Type: text/plain; charset=utf-8\r\n\r\nPlain body\r\n'
    '--alt\r\nContent-Type: text/html; charset=utf-8\r\n\r\n<p>HTML body</p>\r\n'
    '--alt--\r\n'
    '--outer\r\nContent-Type: application/octet-stream\r\n'
    "Content-Disposition: attachment; filename*=utf-8''caf%C3%A9.bin\r\n"
    'Content-Transfer-Encoding: base64\r\n\r\nAAECA/8=\r\n'
    '--outer--\r\nThe epilogue is retained only in original source.\r\n';

String withBody(
  String body, {
  String encoding = '7bit',
  String charset = 'utf-8',
}) =>
    'Content-Type: text/plain; charset=$charset\r\n'
    'Content-Transfer-Encoding: $encoding\r\n\r\n$body';

String mixed(List<String> children, {String type = 'mixed'}) =>
    'Content-Type: multipart/$type; boundary=fixture\r\n\r\n'
    '${children.map((child) => '--fixture\r\n$child\r\n').join()}'
    '--fixture--\r\n';
