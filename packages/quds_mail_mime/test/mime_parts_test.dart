import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_mime/quds_mail_mime.dart';
import 'package:test/test.dart';

import 'fixtures/messages.dart';

void main() {
  const codec = QudsMimeCodec();
  test('multipart alternatives and RFC2231 attachment filename', () {
    final result = codec.parse(eml(mixedMessage));
    expect(result.status, MailParseStatus.complete);
    expect(result.message!.body.plainText, 'Plain body');
    expect(result.message!.body.html, '<p>HTML body</p>');
    final attachment = result.message!.attachments.single;
    expect(attachment.displayName, 'café.bin');
    expect(attachment.content.bytes, [0, 1, 2, 3, 255]);
    expect(attachment.partPath, '1.2');
  });
  test(
    'alternative selection is deterministic and uses last supported type',
    () {
      final result = codec.parse(
        eml(mixed([withBody('old'), withBody('new')], type: 'alternative')),
      );
      expect(result.message!.body.plainText, 'new');
    },
  );
  test('text attachment does not become a message body', () {
    final result = codec.parse(
      eml(
        mixed([
          'Content-Type: text/plain\r\nContent-Disposition: attachment; filename=note.txt\r\n\r\nAttachment',
          withBody('Real body'),
        ]),
      ),
    );
    expect(result.message!.body.plainText, 'Real body');
    expect(result.message!.attachments.single.displayName, 'note.txt');
  });
  test('related root start parameter and local CID attachment mapping', () {
    const source =
        'Content-Type: multipart/related; boundary=r; start="<body>"\r\n\r\n'
        '--r\r\nContent-Type: image/png\r\nContent-ID: <picture>\r\n'
        'Content-Transfer-Encoding: base64\r\n\r\nAAEC\r\n'
        '--r\r\nContent-Type: text/html\r\nContent-ID: <body>\r\n\r\n'
        '<p>Local <img src="cid:picture"></p>\r\n--r--\r\n';
    final result = codec.parse(eml(source));
    expect(result.message!.body.html, contains('cid:picture'));
    expect(result.message!.attachments.single.contentId, 'picture');
    expect(result.message!.attachments.single.inline, isTrue);
  });
  test('boundary prefixes within content are not recognized as delimiters', () {
    const source =
        'Content-Type: multipart/mixed; boundary=b\r\n\r\n'
        '--b\r\nContent-Type: text/plain\r\n\r\nline\r\n--bExtra\r\nend\r\n--b--\r\n';
    expect(
      codec.parse(eml(source)).message!.body.plainText,
      'line\r\n--bExtra\r\nend',
    );
  });
  test('missing closing boundary is partial rather than silent success', () {
    const source =
        'Content-Type: multipart/mixed; boundary=b\r\n\r\n'
        '--b\r\nContent-Type: text/plain\r\n\r\nrecovered';
    final result = codec.parse(eml(source));
    expect(result.status, MailParseStatus.partial);
    expect(result.message!.body.plainText, 'recovered');
    expect(
      result.diagnostics.map((d) => d.code),
      contains(MailDiagnosticCode.truncatedMessage),
    );
  });
  test('duplicate structural headers and missing boundaries fail closed', () {
    for (final source in [
      'Content-Type: text/plain\r\nContent-Type: text/html\r\n\r\nbody',
      'Content-Type: multipart/mixed\r\n\r\nbody',
    ]) {
      final result = codec.parse(eml(source));
      expect(result.status, MailParseStatus.failed);
      expect(result.message, isNull);
      expect(result.original, isNotNull);
    }
  });
  test('safe display names remove paths and bidi control characters', () {
    final result = codec.parse(
      eml(
        'Content-Type: application/octet-stream\r\n'
        'Content-Disposition: attachment; filename="../../private.txt"\r\n\r\ndata',
      ),
    );
    expect(result.message!.attachments.single.displayName, 'private.txt');
  });
}
