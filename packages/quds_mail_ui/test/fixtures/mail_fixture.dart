import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_mail_core/quds_mail_core.dart';

const hostileHtml = '''
<h1>Meeting agenda</h1><p>Hello <b>world</b> &amp; مرحبًا.</p>
<script>fetch('https://script.invalid/private')</script>
<style>@import url(https://css.invalid/a); @font-face {src:url(https://font.invalid/a)}</style>
<form action="https://form.invalid/send"><input name="private" value="hidden"></form>
<iframe src="https://frame.invalid/"><p>Hidden frame text</p></iframe>
<object data="https://object.invalid/"><p>Hidden object text</p></object>
<svg><image href="https://svg.invalid/a"/><script>secret</script></svg>
<math><mtext><img src="https://math.invalid/a"></mtext></math>
<img src="https://image.invalid/a" srcset="https://set.invalid/a 2x">
<img src="//relative.invalid/a"><img src="&#104;ttps://encoded.invalid/a">
<div style="background:url(https://background.invalid/a)">Visible after CSS</div>
<a href="javascript:alert(1)">bad one</a><a href="&#106;avascript:alert(2)">bad two</a>
<a href="data:text/html,active">bad three</a><a href="//redirect.invalid/a">bad four</a>
<a href="https://approved.invalid/start?redirect=https://next.invalid/">Approved route</a>
<p>End of visible message.</p>
''';

MailParseResult mailFixture({
  String? html,
  String? plainText,
  List<MailAttachment> attachments = const [],
  Uint8List? raw,
  MailParseStatus status = MailParseStatus.complete,
  List<MailDiagnostic> diagnostics = const [],
}) {
  final bytes = MailBytes(raw ?? Uint8List.fromList([0xff, 0x00, 13, 10, 65]));
  return MailParseResult(
    status: status,
    diagnostics: diagnostics,
    message: MailMessage(
      raw: bytes,
      envelope: MailEnvelope(
        subject: 'Fixture subject',
        from: const [
          MailAddress('sender@example.invalid', displayName: 'مُرسل'),
        ],
        to: const [MailAddress('reader@example.invalid')],
      ),
      body: MailBody(
        html: html,
        plainText: plainText ?? (html == null ? 'Decoded body.' : null),
      ),
      attachments: attachments,
    ),
  );
}

MailAttachment byteAttachment({
  String partPath = '1.2',
  String? cid,
  String mediaType = 'application/octet-stream',
  Uint8List? bytes,
}) => MailAttachment(
  partPath: partPath,
  mediaType: mediaType,
  displayName: 'original.bin',
  contentId: cid,
  content: MailBytes(bytes ?? Uint8List.fromList([0, 1, 128, 255])),
);

Uint8List onePixelPng() => base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGMwaDjwHwAExAJwNooHGQAAAABJRU5ErkJggg==',
);
