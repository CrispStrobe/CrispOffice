// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:async';

import 'package:enough_mail/imap.dart';
import 'package:enough_mail/src/private/util/client_base.dart';
import 'package:test/test.dart';

import '../mock_socket.dart';
import 'mock_imap_server.dart';

void main() {
  late ImapClient client;
  late MockConnection connection;
  late MockImapServer server;

  setUp(() async {
    client = ImapClient(
      isLogEnabled: false,
      defaultResponseTimeout: const Duration(seconds: 2),
      maxProtocolLineBytes: 256,
      maxResponseBytes: 4096,
    );
    connection = MockConnection();
    client.connect(
      connection.socketClient,
      connectionInformation: const ConnectionInfo(
        'mail.example.test',
        993,
        isSecure: true,
      ),
    );
    server = MockImapServer(connection.socketServer);
    connection.socketServer.write('* OK controlled discovery fixture\r\n');
    await Future<void>.delayed(const Duration(milliseconds: 15));
  });

  tearDown(() async {
    await client.abort();
  });

  test('public API emits a closed UID command and returns sorted high IDs', () {
    server.response =
        '* SEARCH 4294967295 1000001\r\n<tag> OK discovery complete';
    return client
        .uidSearchRaw(firstUid: 1000001, lastUid: 0xffffffff, maxUids: 2)
        .then((ids) {
          expect(ids, [1000001, 4294967295]);
          expect(() => ids.add(3), throwsUnsupportedError);
          expect(
            server.requests.single,
            contains(' UID SEARCH UID 1000001:4294967295\r\n'),
          );
        });
  });

  test('an explicit empty result and status prose are accepted', () async {
    server.response =
        '* OK [ALERT] SEARCH index available\r\n'
        '* search\r\n'
        '<tag> OK discovery complete';
    expect(
      await client.uidSearchRaw(firstUid: 1, lastUid: 9, maxUids: 1),
      isEmpty,
    );
  });

  test('invalid request bounds fail before any command is sent', () {
    for (final request in [
      (0, 5, 1),
      (3, 2, 1),
      (1, 0x100000000, 1),
      (1, 5, 0),
    ]) {
      expect(
        () => client.uidSearchRaw(
          firstUid: request.$1,
          lastUid: request.$2,
          maxUids: request.$3,
        ),
        throwsArgumentError,
      );
    }
    expect(server.requests, isEmpty);
  });

  for (final wire in [
    '<tag> OK missing discovery',
    '* SEARCH 1 invalid\r\n<tag> OK malformed suffix',
    '* SEARCH 1 1\r\n<tag> OK duplicate UID',
    '* SEARCH 1\r\n* SEARCH 2\r\n<tag> OK repeated result',
    '* SEARCH 1\r\n*\tSEARCH 2\r\n<tag> OK malformed prefix',
    '* SEARCH 1\r\n* SEARCH\t2\r\n<tag> OK malformed separator',
    '* SEARCH 1\r\n* SEARCH\x7f2\r\n<tag> OK attached DEL',
    '* SEARCH 1\r\n* SEARCH\u00802\r\n<tag> OK attached non-ASCII',
    '* ESEARCH UID ALL 1:4294967295\r\n<tag> OK unrequested extension',
    '* SEARCH 1\r\n<tag> NO discovery rejected',
  ]) {
    test(
      'client rejects incomplete or malformed wire ${wire.split('\r\n').last}',
      () async {
        server.response = wire;
        await expectLater(
          client.uidSearchRaw(firstUid: 1, lastUid: 9, maxUids: 2),
          throwsA(isA<ImapException>()),
        );
        expect(client.responseLimitExceeded, isFalse);
      },
    );
  }

  test('UID count exhaustion is exposed as a resource limit', () async {
    server.response = '* SEARCH 1 2 3\r\n<tag> OK excessive discovery';
    await expectLater(
      client.uidSearchRaw(firstUid: 1, lastUid: 9, maxUids: 2),
      throwsA(isA<ImapException>()),
    );
    expect(client.responseLimitExceeded, isTrue);
    expect(client.isConnected, isFalse);
  });

  test('existing protocol-line limits apply during discovery', () async {
    server.response = '* SEARCH ${'1' * 300}\r\n<tag> OK excessive line';
    await expectLater(
      client.uidSearchRaw(firstUid: 1, lastUid: 9, maxUids: 2),
      throwsA(isA<ImapException>()),
    );
    expect(client.responseLimitExceeded, isTrue);
  });

  test(
    'stream closure after SEARCH cannot become a successful prefix',
    () async {
      server.response = '* SEARCH 1';
      final result = client.uidSearchRaw(firstUid: 1, lastUid: 9, maxUids: 2);
      final failed = expectLater(result, throwsA(isA<ImapException>()));
      await Future<void>.delayed(const Duration(milliseconds: 15));
      await connection.socketClient.close();
      await failed;
    },
  );

  test(
    'abort settles discovery before tagged completion without a prefix',
    () async {
      server.response = '* SEARCH 1';
      final result = client.uidSearchRaw(firstUid: 1, lastUid: 9, maxUids: 2);
      final failed = expectLater(result, throwsA(isA<ImapException>()));
      await Future<void>.delayed(const Duration(milliseconds: 15));
      await client.abort();
      await failed;
    },
  );
}
