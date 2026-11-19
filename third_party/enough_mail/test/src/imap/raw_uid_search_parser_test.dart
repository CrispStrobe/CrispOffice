// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:convert';
import 'dart:typed_data';

import 'package:enough_mail/src/imap/response.dart';
import 'package:enough_mail/src/private/imap/imap_response.dart';
import 'package:enough_mail/src/private/imap/imap_response_line.dart';
import 'package:enough_mail/src/private/imap/imap_response_reader.dart';
import 'package:enough_mail/src/private/imap/raw_uid_search_parser.dart';
import 'package:enough_mail/src/private/util/protocol_resource_limit.dart';
import 'package:test/test.dart';

RawUidSearchParser _parser({
  int first = 1,
  int last = 0xffffffff,
  int max = 10,
}) => RawUidSearchParser(firstUid: first, lastUid: last, maxUids: max);

ImapResponse _read(String text) {
  final responses = <ImapResponse>[];
  final reader = ImapResponseReader(responses.add, maxLiteralSize: 1024);
  for (final byte in utf8.encode('$text\r\n')) {
    reader.onData(Uint8List.fromList([byte]));
  }
  expect(responses, hasLength(1));
  return responses.single;
}

List<int>? _finish(
  RawUidSearchParser parser, {
  ResponseStatus status = ResponseStatus.ok,
}) => parser.parse(
  ImapResponse()..add(ImapResponseLine('a1 OK discovery complete')),
  Response<List<int>>()..status = status,
);

void main() {
  test('fragmented high unordered UIDs become a sorted immutable result', () {
    final parser = _parser(max: 4);
    expect(
      parser.parseUntagged(_read('* SEARCH 4294967295 42 1000001 1'), null),
      isTrue,
    );
    final result = _finish(parser)!;
    expect(result, [1, 42, 1000001, 4294967295]);
    expect(() => result.add(9), throwsUnsupportedError);
    expect(() => result[0] = 9, throwsUnsupportedError);
    expect(_finish(parser), [1, 42, 1000001, 4294967295]);
  });

  test('explicit empty and mixed-case SEARCH responses are complete', () {
    final empty = _parser();
    expect(empty.parseUntagged(_read('* sEaRcH'), null), isTrue);
    expect(_finish(empty), isEmpty);
    final populated = _parser(first: 1000001, last: 1000002, max: 2);
    expect(
      populated.parseUntagged(_read('* search 1000002 1000001'), null),
      isTrue,
    );
    expect(_finish(populated), [1000001, 1000002]);
  });

  test('missing SEARCH fails and cannot become a later successful prefix', () {
    final parser = _parser();
    expect(() => _finish(parser), throwsFormatException);
    expect(
      () => parser.parseUntagged(_read('* SEARCH'), null),
      throwsFormatException,
    );
  });

  test('tagged failure does not turn a complete discovery into success', () {
    for (final status in [ResponseStatus.no, ResponseStatus.bad]) {
      final parser = _parser();
      expect(parser.parseUntagged(_read('* SEARCH 1'), null), isTrue);
      expect(_finish(parser, status: status), isNull);
    }
  });

  test('status prose and distinct response atoms remain separate', () {
    final parser = _parser();
    for (final line in [
      '* OK [ALERT] SEARCH is rebuilding',
      '* no temporary ESEARCH problem',
      '* BAD diagnostic SEARCH( is not data',
      '* FLAGS (SEARCH)',
      '* 5 EXISTS',
      '* SEARCHX 9',
    ]) {
      expect(parser.parseUntagged(_read(line), null), isFalse);
    }
    expect(parser.parseUntagged(_read('* SEARCH 2 1'), null), isTrue);
    expect(_finish(parser), [1, 2]);
  });

  for (final entry in <String, String>{
    'zero': '0',
    'negative': '-1',
    'positive sign': '+1',
    'leading zero': '01',
    'hexadecimal': '0x10',
    'fraction': '1.0',
    'exponent': '1e3',
    'overflow': '4294967296',
    'excess decimal digits': '999999999999999999999999',
    'wildcard': '*',
    'sequence range': '1:2',
    'quoted number': '"1"',
    'nested list': '(1)',
    'extension data': '1 (MODSEQ 9)',
    'tab separator': '1\t2',
    'repeated space': '1  2',
    'trailing space': '1 ',
    'ordinary text': 'not-a-uid',
    'control byte': '1\x00',
  }.entries) {
    test('${entry.key} fails the entire discovery', () {
      final parser = _parser();
      expect(
        () => parser.parseUntagged(_read('* SEARCH ${entry.value}'), null),
        throwsFormatException,
      );
      expect(() => _finish(parser), throwsFormatException);
    });
  }

  for (final line in [
    '* ESEARCH UID ALL 1:4294967295',
    '* esearch',
    '*  SEARCH 1',
    '*\tSEARCH 1',
    '*SEARCH 1',
    '* SEARCH\t1',
    '* SEARCH\x7f1',
    '* SEARCH\u00801',
    '*\x7fSEARCH 1',
    '*\u0080SEARCH 1',
    '* SEARCH(1)',
    '* SEARCH"1"',
    '* SEARCH{1}\r\n1',
    '* SEARCH {1}\r\n1',
  ]) {
    test('rejects malformed or extended shape ${jsonEncode(line)}', () {
      final parser = _parser();
      expect(
        () => parser.parseUntagged(_read(line), null),
        throwsFormatException,
      );
      expect(() => _finish(parser), throwsFormatException);
    });
  }

  for (final suffix in ['\t2', '\x7f2', '\u00802', '(2)', '"2"', ']2']) {
    test('malformed attached suffix ${jsonEncode(suffix)} rejects an earlier '
        'complete result', () {
      final parser = _parser();
      expect(parser.parseUntagged(_read('* SEARCH 1'), null), isTrue);
      expect(
        () => parser.parseUntagged(_read('* SEARCH$suffix'), null),
        throwsFormatException,
      );
      expect(() => _finish(parser), throwsFormatException);
    });
  }

  for (final uid in [1, 4]) {
    test('UID $uid outside the requested closed interval fails', () {
      final parser = _parser(first: 2, last: 3);
      expect(
        () => parser.parseUntagged(_read('* SEARCH $uid'), null),
        throwsFormatException,
      );
      expect(() => _finish(parser), throwsFormatException);
    });
  }

  test('duplicate UID fails without deduplicating malformed discovery', () {
    final parser = _parser();
    expect(
      () => parser.parseUntagged(_read('* SEARCH 1 3 1'), null),
      throwsFormatException,
    );
    expect(() => _finish(parser), throwsFormatException);
  });

  test('count exhaustion has a typed resource failure and no prefix', () {
    final parser = _parser(max: 2);
    expect(
      () => parser.parseUntagged(_read('* SEARCH 1 3 5'), null),
      throwsA(isA<ProtocolResourceLimit>()),
    );
    expect(() => _finish(parser), throwsFormatException);
  });

  for (final second in ['* SEARCH', '* SEARCH 2', '* ESEARCH UID ALL 2']) {
    test('a second result ${jsonEncode(second)} invalidates the first', () {
      final parser = _parser();
      expect(parser.parseUntagged(_read('* SEARCH 1'), null), isTrue);
      expect(
        () => parser.parseUntagged(_read(second), null),
        throwsFormatException,
      );
      expect(() => _finish(parser), throwsFormatException);
    });
  }
}
