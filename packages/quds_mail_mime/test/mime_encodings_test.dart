import 'dart:async';
import 'dart:typed_data';

import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_mime/quds_mail_mime.dart';
import 'package:test/test.dart';

import 'fixtures/messages.dart';

void main() {
  const codec = QudsMimeCodec();
  test(
    'encoded subject, display name, date and text project through public MIME',
    () {
      final result = codec.parse(eml(simpleMessage));
      expect(result.status, MailParseStatus.complete);
      expect(result.message!.envelope.subject, 'Hello €');
      expect(result.message!.envelope.from.single.displayName, 'Müller');
      expect(
        result.message!.envelope.sentAt!.toUtc(),
        DateTime.utc(2026, 11, 18, 12, 30),
      );
      expect(result.message!.body.plainText, 'Hello €.\r\n');
    },
  );
  test('strict UTF8, ASCII, Latin1 and Windows1252 bodies', () {
    for (final entry in <String, String>{
      'utf-8': '=E2=82=AC',
      'windows-1252': '=80',
      'iso-8859-1': '=E9',
      'us-ascii': 'ASCII',
    }.entries) {
      final result = codec.parse(
        eml(
          withBody(
            entry.value,
            charset: entry.key,
            encoding: 'quoted-printable',
          ),
        ),
      );
      expect(result.status, MailParseStatus.complete, reason: entry.key);
      expect(
        result.message!.body.plainText,
        entry.key == 'iso-8859-1'
            ? 'é'
            : entry.key == 'us-ascii'
            ? 'ASCII'
            : '€',
      );
    }
  });
  test('unknown header/body charset has diagnostics and source fallback', () {
    final header = codec.parse(
      eml('Subject: =?unknown-private?B?c2VjcmV0?=\r\n\r\nbody'),
    );
    expect(header.status, MailParseStatus.partial);
    expect(header.message!.envelope.subject, isEmpty);
    expect(
      header.diagnostics.map((d) => d.code),
      contains(MailDiagnosticCode.unsupportedCharset),
    );
    final body = codec.parse(
      eml(withBody('secret', charset: 'unknown-private')),
    );
    expect(body.status, MailParseStatus.unsupported);
    expect(body.message!.body.plainText, isNull);
    expect(body.original, isNotNull);
  });
  test('malformed UTF8 is never silently replaced', () {
    final bytes = Uint8List.fromList([
      ...eml(
        'Content-Type: text/plain; charset=utf-8\r\n'
        'Content-Transfer-Encoding: 8bit\r\n\r\n',
      ),
      0xc3,
      0x28,
    ]);
    final result = codec.parse(bytes);
    expect(result.status, MailParseStatus.partial);
    expect(result.message!.body.plainText, isNull);
    expect(
      result.diagnostics.map((d) => d.code),
      contains(MailDiagnosticCode.malformedEncoding),
    );
  });
  test(
    'malformed transfer alphabets, padding and QP escapes fail explicitly',
    () {
      for (final value in ['%%%=', 'YQ=', 'YQ==AA==', 'YR==', '=A=', 'A===']) {
        final result = codec.parse(eml(withBody(value, encoding: 'base64')));
        expect(result.status, isNot(MailParseStatus.complete), reason: value);
        expect(result.message!.body.plainText, isNull);
      }
      for (final value in ['hello=', '=XZ', '=1', '=\rX']) {
        final result = codec.parse(
          eml(withBody(value, encoding: 'quoted-printable')),
        );
        expect(result.status, MailParseStatus.partial, reason: value);
        expect(result.message!.body.plainText, isNull);
      }
    },
  );
  test('malformed words and dates do not leak private source to print', () {
    final printed = <String>[];
    runZoned(
      () {
        for (final subject in [
          '=?utf-8?B?%%%%?=',
          '=?utf-8?Q?=XX?=',
          '=?broken',
        ]) {
          final result = codec.parse(
            eml(
              'Subject: $subject private-secret\r\n'
              'Date: private-secret\r\n\r\nbody',
            ),
          );
          expect(result.status, MailParseStatus.partial);
          expect(
            result.diagnostics.every(
              (d) => !d.message.contains('private-secret'),
            ),
            isTrue,
          );
        }
      },
      zoneSpecification: ZoneSpecification(
        print: (self, parent, zone, line) => printed.add(line),
      ),
    );
    expect(printed, isEmpty);
  });
  test('unknown transfer encoding is not passed through as exact content', () {
    final result = codec.parse(eml(withBody('opaque', encoding: 'x-unknown')));
    expect(result.status, MailParseStatus.unsupported);
    expect(result.message!.body.plainText, isNull);
  });
}
