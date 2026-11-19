// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:convert';
import 'dart:typed_data';

import 'package:enough_mail/src/imap/raw_fetch.dart';
import 'package:enough_mail/src/imap/response.dart';
import 'package:enough_mail/src/private/imap/imap_response.dart';
import 'package:enough_mail/src/private/imap/imap_response_line.dart';
import 'package:enough_mail/src/private/imap/imap_response_reader.dart';
import 'package:enough_mail/src/private/imap/raw_fetch_parser.dart';
import 'package:test/test.dart';

RawFetchParser _parser({bool headersOnly = false}) => RawFetchParser(
  firstUid: 1,
  lastUid: 3,
  headersOnly: headersOnly,
  maxMessages: 3,
  maxLiteralBytes: 4096,
);

ImapResponse _read(Uint8List wire) {
  final responses = <ImapResponse>[];
  final reader = ImapResponseReader(responses.add, maxLiteralSize: 4096);
  // Feed real framing one byte at a time, including literal boundaries.
  for (final byte in wire) {
    reader.onData(Uint8List.fromList([byte]));
  }
  expect(responses, hasLength(1));
  return responses.single;
}

Uint8List _single(
  String item,
  Uint8List literal, {
  int uid = 1,
  String? uidLexeme,
  String suffix = '',
}) =>
    (BytesBuilder()
          ..add(
            ascii.encode(
              '* $uid FETCH (UID ${uidLexeme ?? uid} FLAGS (\\Seen) '
              '$item {${literal.length}}\r\n',
            ),
          )
          ..add(literal)
          ..add(ascii.encode(')$suffix\r\n')))
        .takeBytes();

Uint8List _twoFetches(String item, Uint8List first, Uint8List second) =>
    (BytesBuilder()
          ..add(ascii.encode('* 1 FETCH (UID 1 $item {${first.length}}\r\n'))
          ..add(first)
          ..add(ascii.encode(') FETCH (UID 2 $item {${second.length}}\r\n'))
          ..add(second)
          ..add(ascii.encode(')\r\n')))
        .takeBytes();

RawImapFetchResult? _taggedOk(RawFetchParser parser) => parser.parse(
  ImapResponse()..add(ImapResponseLine('a1 OK fetched')),
  Response<RawImapFetchResult>()..status = ResponseStatus.ok,
);

void main() {
  test('strict repeated-list checks preserve legacy iteration behavior', () {
    for (final wire in [
      '* 1 FETCH (UID 1) ()',
      '* 1 FETCH () ()',
      '* 1 FETCH (FLAGS () ())',
    ]) {
      final response = ImapResponse()..add(ImapResponseLine(wire));
      expect(response.iterate, returnsNormally);
      expect(() => response.iterate(strict: true), throwsFormatException);
    }
  });

  test('canonical raw FETCH preserves exact fragmented literal octets', () {
    final literal = Uint8List.fromList([65, 10, 255, 0, 66]);
    final parser = _parser();
    expect(
      parser.parseUntagged(_read(_single('BODY[]', literal)), null),
      isTrue,
    );
    final result = _taggedOk(parser)!;
    expect(result.messages, hasLength(1));
    expect(result.messages.single.uid, 1);
    expect(result.messages.single.bytes, orderedEquals(literal));
    expect(result.messages.single.flags, [r'\Seen']);
  });

  test('separate canonical header FETCH responses preserve both UIDs', () {
    final parser = _parser(headersOnly: true);
    final first = Uint8List.fromList(ascii.encode('Subject: First\r\n\r\n'));
    final second = Uint8List.fromList(ascii.encode('Subject: Second\r\n\r\n'));
    expect(
      parser.parseUntagged(_read(_single(rawImapHeaderItem, first)), null),
      isTrue,
    );
    expect(
      parser.parseUntagged(
        _read(_single(rawImapHeaderItem, second, uid: 2)),
        null,
      ),
      isTrue,
    );
    final result = _taggedOk(parser)!;
    expect(result.messages.map((message) => message.uid), [1, 2]);
    expect(result.messages[0].bytes, orderedEquals(first));
    expect(result.messages[1].bytes, orderedEquals(second));
  });

  for (final entry in <String, String>{
    'trailing atom': ' UNEXPECTED',
    'trailing anonymous list': ' (UNEXPECTED)',
    'trailing empty list': ' ()',
  }.entries) {
    test('raw FETCH rejects ${entry.key} and cannot accept a tagged OK', () {
      final parser = _parser();
      final malformed = _read(
        _single('BODY[]', Uint8List.fromList([65]), suffix: entry.value),
      );
      expect(
        () => parser.parseUntagged(malformed, null),
        throwsFormatException,
      );
      expect(() => _taggedOk(parser), throwsFormatException);
    });
  }

  test('two top-level FETCH bodies cannot silently select the last UID', () {
    final parser = _parser();
    final malformed = _read(
      _twoFetches('BODY[]', Uint8List.fromList([65]), Uint8List.fromList([66])),
    );
    expect(() => parser.parseUntagged(malformed, null), throwsFormatException);
    expect(() => _taggedOk(parser), throwsFormatException);
  });

  test(
    'ambiguous header FETCH cannot yield a partial sync or false tombstones',
    () {
      final parser = _parser(headersOnly: true);
      final header = Uint8List.fromList(
        ascii.encode('Subject: Fixture\r\n\r\n'),
      );
      // A valid earlier record must not turn a later malformed response into a
      // successful prefix, which a synchronizer could mistake for UID absence.
      expect(
        parser.parseUntagged(
          _read(_single(rawImapHeaderItem, header, uid: 3)),
          null,
        ),
        isTrue,
      );
      final malformed = _read(_twoFetches(rawImapHeaderItem, header, header));
      expect(
        () => parser.parseUntagged(malformed, null),
        throwsFormatException,
      );
      expect(() => _taggedOk(parser), throwsFormatException);
      expect(
        () => parser.parseUntagged(
          _read(_single(rawImapHeaderItem, header)),
          null,
        ),
        throwsFormatException,
      );
    },
  );
  for (final lexeme in ['0x1', '+1', '01']) {
    test('full raw FETCH rejects non-decimal UID lexeme $lexeme', () {
      final parser = _parser();
      final malformed = _read(
        _single('BODY[]', Uint8List.fromList([65]), uidLexeme: lexeme),
      );
      expect(
        () => parser.parseUntagged(malformed, null),
        throwsFormatException,
      );
      expect(() => _taggedOk(parser), throwsFormatException);
    });

    test('flag notification rejects non-decimal UID lexeme $lexeme', () {
      final parser = _parser();
      expect(
        parser.parseUntagged(
          _read(_single('BODY[]', Uint8List.fromList([65]))),
          null,
        ),
        isTrue,
      );
      final malformed = _read(
        Uint8List.fromList(
          ascii.encode('* 1 FETCH (UID $lexeme FLAGS (\\Seen))\r\n'),
        ),
      );
      expect(
        () => parser.parseUntagged(malformed, null),
        throwsFormatException,
      );
      expect(() => _taggedOk(parser), throwsFormatException);
    });
  }
}
