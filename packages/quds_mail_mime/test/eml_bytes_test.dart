import 'dart:typed_data';

import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_mime/quds_mail_mime.dart';
import 'package:test/test.dart';

import 'fixtures/messages.dart';

void main() {
  const codec = QudsMimeCodec();
  test(
    'original input remains exact and cannot be mutated through aliases',
    () {
      final input = eml(mixedMessage);
      final expected = Uint8List.fromList(input);
      final result = codec.parse(input);
      expect(result.status, MailParseStatus.complete);
      input[0] = 0;
      final export = result.original!.copyBytes();
      expect(export, orderedEquals(expected));
      final hash = result.original!.sha256;
      export[0] = 0;
      expect(result.original!.sha256, hash);
      expect(() => result.original!.bytes[0] = 0, throwsUnsupportedError);
      expect(result.original!.copyBytes(), orderedEquals(expected));
    },
  );
  test('non UTF-8 source and LF line endings survive display decoding', () {
    final input = Uint8List.fromList([
      ...eml(
        'Content-Type: text/plain; charset=iso-8859-1\n'
        'Content-Transfer-Encoding: 8bit\n\nCaf',
      ),
      0xe9,
      10,
    ]);
    final result = codec.parse(input);
    expect(result.status, MailParseStatus.complete);
    expect(result.message!.body.plainText, 'Café\n');
    expect(result.original!.copyBytes(), orderedEquals(input));
  });
  test('identity attachment bytes retain internal CRLF and high bytes', () {
    final input = Uint8List.fromList([
      ...eml(
        'Content-Type: multipart/mixed; boundary=b\r\n\r\n'
        '--b\r\nContent-Type: application/octet-stream\r\n'
        'Content-Disposition: attachment; filename=test.bin\r\n'
        'Content-Transfer-Encoding: binary\r\n\r\n',
      ),
      0,
      255,
      13,
      10,
      65,
      13,
      10,
      ...eml('\r\n--b--\r\n'),
    ]);
    final result = codec.parse(input);
    expect(result.status, MailParseStatus.complete);
    expect(result.message!.attachments.single.content.bytes, [
      0,
      255,
      13,
      10,
      65,
      13,
      10,
    ]);
  });
  test('signed MIME source exports without canonicalizing any octet', () {
    const source =
        'Content-Type: multipart/signed; boundary=s; '
        'protocol="application/pkcs7-signature"\r\n\r\n'
        '--s\r\nContent-Type: text/plain\r\n\r\nSigned  spacing\t\r\n'
        '--s\r\nContent-Type: application/pkcs7-signature\r\n'
        'Content-Transfer-Encoding: base64\r\n\r\nAAEC\r\n--s--\r\n';
    final bytes = eml(source);
    expect(codec.parse(bytes).original!.copyBytes(), orderedEquals(bytes));
  });
}
