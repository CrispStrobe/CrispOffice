// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:enough_mail/mime_core.dart';
import 'package:test/test.dart';

void main() {
  test('public portable entry parses an original RFC fixture', () {
    final bytes = Uint8List.fromList(ascii.encode(_fixture));
    final message = MimeMessage.parseFromData(bytes);
    expect(message.decodeSubject(), 'Portable hello');
    expect(message.from!.single.email, 'sender@example.invalid');
    expect(message.to!.single.email, 'reader@example.invalid');
    expect(message.decodeTextPlainPart(), 'Hello from a portable parser.');
    expect(message.decodeDate()!.toUtc(), DateTime.utc(2026, 11, 18, 12));
  });

  test('malformed input emits redacted codes with no console output', () {
    final printed = <String>[];
    final codes = <MimeDiagnosticCode>[];
    runZoned(
      () => MimeDiagnostics.run(() {
        MailCodec.decodeHeader('=?private-unknown?B?c2VjcmV0?=');
        DateCodec.decodeDate('Wed, PRIVATE Nov 2026 12:00:00 +0000');
        expect(
          () => MailAddress.parse('PRIVATE_WITHOUT_AN_ADDRESS'),
          throwsFormatException,
        );
        MailCodec.decodeBinary('PRIVATE_BODY', 'private-transfer');
      }, onDiagnostic: codes.add),
      zoneSpecification: ZoneSpecification(
        print: (self, parent, zone, line) => printed.add(line),
      ),
    );
    expect(printed, isEmpty);
    expect(codes, contains(MimeDiagnosticCode.unsupportedCharset));
    expect(codes, contains(MimeDiagnosticCode.invalidDate));
    expect(codes, contains(MimeDiagnosticCode.malformedAddress));
    expect(codes, contains(MimeDiagnosticCode.unsupportedTransferEncoding));
  });

  test(
    'diagnostics stay isolated across concurrent async operations',
    () async {
      final first = <MimeDiagnosticCode>[];
      final second = <MimeDiagnosticCode>[];
      await Future.wait<void>([
        MimeDiagnostics.run(() async {
          await Future<void>.delayed(Duration.zero);
          MailCodec.decodeHeader('=?missing-a?Q?one?=');
        }, onDiagnostic: first.add),
        MimeDiagnostics.run(() async {
          await Future<void>.delayed(Duration.zero);
          MailCodec.decodeBinary('two', 'missing-b');
        }, onDiagnostic: second.add),
      ]);
      expect(first, [MimeDiagnosticCode.unsupportedCharset]);
      expect(second, [MimeDiagnosticCode.unsupportedTransferEncoding]);
    },
  );

  test('strict charset decoding does not silently replace malformed bytes', () {
    final codes = <MimeDiagnosticCode>[];
    final result = MimeDiagnostics.run(
      () => MailCodec.decodeCharsetStrict(Uint8List.fromList([0xc3]), 'utf-8'),
      onDiagnostic: codes.add,
    );
    expect(result, isNull);
    expect(codes, [MimeDiagnosticCode.malformedCharacterData]);
    expect(
      MailCodec.decodeCharsetStrict(Uint8List.fromList([0xfc]), 'iso-8859-1'),
      'ü',
    );
    expect(
      MailCodec.decodeCharsetStrict(Uint8List.fromList([0x80]), 'windows-1252'),
      '€',
    );
  });

  test('excluded CJK codecs report unsupported without decoded fallback', () {
    for (final charset in ['gbk', 'gb2312', 'gb18030', 'big5', 'big-5']) {
      final codes = <MimeDiagnosticCode>[];
      final result = MimeDiagnostics.run(
        () => MailCodec.decodeCharsetStrict(
          Uint8List.fromList([0xa4, 0x40]),
          charset,
        ),
        onDiagnostic: codes.add,
      );
      expect(result, isNull, reason: charset);
      expect(codes, [MimeDiagnosticCode.unsupportedCharset], reason: charset);
    }
  });

  test('undefined single-byte charset slots never become question marks', () {
    for (final entry in <String, List<int>>{
      'windows-1252': [0x81, 0x8d, 0x8f, 0x90, 0x9d],
      'cp-1253': [0x81, 0xff],
      'iso-8859-3': [0xa5],
    }.entries) {
      for (final byte in entry.value) {
        final codes = <MimeDiagnosticCode>[];
        final result = MimeDiagnostics.run(
          () => MailCodec.decodeCharsetStrict(
            Uint8List.fromList([byte]),
            entry.key,
          ),
          onDiagnostic: codes.add,
        );
        expect(result, isNull, reason: '${entry.key}: $byte');
        expect(codes, [MimeDiagnosticCode.malformedCharacterData]);
      }
    }
    expect(
      MailCodec.decodeCharsetStrict(Uint8List.fromList([0x3f]), 'windows-1252'),
      '?',
    );
  });

  test('dates reject calendar, clock, zone and weekday normalization', () {
    for (final date in [
      'Tue, 31 Feb 2026 12:00:00 +0000',
      'Wed, 18 Nov 2026 99:00:00 +0000',
      'Wed, 18 Nov 2026 12:99:00 +0000',
      'Wed, 18 Nov 2026 12:00:99 +0000',
      'Wed, 18 Nov 2026 12:00:00 +0060',
      'Wed, 18 Nov 2026 12:00:00 +9900',
      'Wed, 18 Nov 2026 12:00:00 12345',
      'Wed, 18 Nov 2026 12:00:00 --100',
      'Wed, 18 Nov 2026 12:00:00 ++100',
      'Wed, 18 Nov 2026 12:00:00 +00-1',
      'Wed, 18 Nov 2026 12:00:00:00 +0000',
      'Tue, 18 Nov 2026 12:00:00 +0000',
      'Sat, 31 Dec 2016 23:59:60 +0000',
      '18 Nov -1 12:00:00 +0000',
      '18 Nov 0x7EA 12:00:00 +0000',
      '0x12 Nov 2026 12:00:00 +0000',
      '18 Nov 2026 +1:00:00 +0000',
    ]) {
      final codes = <MimeDiagnosticCode>[];
      final result = MimeDiagnostics.run(
        () => DateCodec.decodeDate(date),
        onDiagnostic: codes.add,
      );
      expect(result, isNull, reason: date);
      expect(codes, contains(MimeDiagnosticCode.invalidDate), reason: date);
    }
    expect(
      DateCodec.decodeDate('Thu, 29 Feb 2024 12:00:00 +0130')!.toUtc(),
      DateTime.utc(2024, 2, 29, 10, 30),
    );
  });

  test('RFC 2231 preserves characters split across encoded sections', () {
    final codes = <MimeDiagnosticCode>[];
    final header = MimeDiagnostics.run(
      () => ContentDispositionHeader(
        "attachment; filename*1*=%82%AC.txt; filename*0*=utf-8''%E2",
      ),
      onDiagnostic: codes.add,
    );
    expect(header.parameters['filename'], '€.txt');
    expect(codes, isEmpty);
  });

  test('RFC 2231 reports unknown charsets and malformed parameter bytes', () {
    final codes = <MimeDiagnosticCode>[];
    MimeDiagnostics.run(() {
      ContentDispositionHeader("attachment; filename*=unknown''%E2%82%AC");
      ContentDispositionHeader("attachment; filename*=utf-8''%C3");
      ContentDispositionHeader("attachment; filename*=utf-8''%GG");
      ContentDispositionHeader('attachment; filename*1=gap.txt');
    }, onDiagnostic: codes.add);
    expect(codes, contains(MimeDiagnosticCode.unsupportedCharset));
    expect(codes, contains(MimeDiagnosticCode.malformedCharacterData));
    expect(codes, contains(MimeDiagnosticCode.malformedHeader));
  });
}

// Independently authored fixture; no user mail or host source was copied.
const _fixture =
    'From: Sender <sender@example.invalid>\r\n'
    'To: Reader <reader@example.invalid>\r\n'
    'Date: Wed, 18 Nov 2026 12:00:00 +0000\r\n'
    'Subject: =?utf-8?Q?Portable_hello?=\r\n'
    'MIME-Version: 1.0\r\n'
    'Content-Type: text/plain; charset=utf-8\r\n'
    'Content-Transfer-Encoding: base64\r\n'
    '\r\n'
    'SGVsbG8gZnJvbSBhIHBvcnRhYmxlIHBhcnNlci4=';
