import 'dart:convert';
import 'dart:typed_data';

import 'package:enough_mail/imap.dart';
import 'package:enough_mail/src/private/imap/generic_parser.dart';
import 'package:enough_mail/src/private/imap/imap_response.dart';
import 'package:enough_mail/src/private/imap/imap_response_reader.dart';
import 'package:test/test.dart';

ImapResponse _read(String text) {
  final responses = <ImapResponse>[];
  final reader = ImapResponseReader(responses.add, maxLiteralSize: 1024);
  reader.onData(Uint8List.fromList(utf8.encode('$text\r\n')));
  // ImapClient removes the command tag/untagged prefix before GenericParser.
  return responses.single..parseText = text.substring(text.indexOf(' ') + 1);
}

void main() {
  test('untagged COPYUID survives an unrelated final tagged response code', () {
    final parser = GenericParser(ImapClient(), null);
    expect(
      parser.parseUntagged(_read('* ok [copyuid 77 1 9] copied'), null),
      isTrue,
    );
    final result = parser.parse(
      _read('a1 OK [HIGHESTMODSEQ 44] moved'),
      Response<GenericImapResult>(),
    );
    expect(result.responseCode, 'HIGHESTMODSEQ 44');
    expect(result.copyUidResponseCodes, ['copyuid 77 1 9']);
    expect(result.malformedCopyUidResponse, isFalse);
  });

  test(
    'duplicate evidence remains visible instead of replacing earlier COPYUID',
    () {
      final parser = GenericParser(ImapClient(), null);
      parser.parseUntagged(_read('* OK [COPYUID 77 1 9] copied'), null);
      final result = parser.parse(
        _read('a1 OK [COPYUID 88 1 10] moved'),
        Response<GenericImapResult>(),
      );
      expect(result.copyUidResponseCodes, [
        'COPYUID 77 1 9',
        'COPYUID 88 1 10',
      ]);
    },
  );

  test(
    'bracketed prose and distinct extension names are not COPYUID evidence',
    () {
      for (final text in [
        'a1 OK prose [COPYUID 77 1 9]',
        'a1 OK [COPYUIDPLUS 77 1 9] moved',
      ]) {
        final result = GenericParser(
          ImapClient(),
          null,
        ).parse(_read(text), Response<GenericImapResult>());
        expect(result.copyUidResponseCodes, isEmpty);
        expect(result.malformedCopyUidResponse, isFalse);
      }
    },
  );

  test(
    'unterminated COPYUID is marked malformed after a later tagged success',
    () {
      final parser = GenericParser(ImapClient(), null);
      parser.parseUntagged(_read('* OK [COPYUID 77 1 9'), null);
      final result = parser.parse(
        _read('a1 OK moved'),
        Response<GenericImapResult>(),
      );
      expect(result.malformedCopyUidResponse, isTrue);
      expect(result.copyUidResponseCodes, hasLength(1));
    },
  );
}
