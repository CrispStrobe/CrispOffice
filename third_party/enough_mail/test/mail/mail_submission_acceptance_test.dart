// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:async';
import 'dart:io';

import 'package:enough_mail/enough_mail.dart';
import 'package:test/test.dart';

enum _Stage { sender, recipient, dataCommand, payload }

void main() {
  for (final chunking in [false, true]) {
    group(chunking ? 'BDAT acceptance' : 'DATA acceptance', () {
      late _SmtpFixture server;
      late _CopyObservingClient client;

      setUp(() async {
        server = await _SmtpFixture.start(chunking: chunking);
        client = _CopyObservingClient(server);
      });

      tearDown(() async {
        await client.disconnect();
        await server.close();
      });

      for (final stage in [_Stage.sender, _Stage.recipient, _Stage.payload]) {
        test(
          '1xx at ${stage.name} never confirms or files a message',
          () async {
            server
              ..overrideStage = stage
              ..overrideCode = 100;

            await expectLater(client.sendMessage(_message()), _rejected(100));

            expect(server.accepted, 0);
            expect(client.appended, 0);
            expect(client.lowLevelOutgoingMailClient.isConnected, isFalse);
            expect(server.receivedPayloads, stage == _Stage.payload ? 1 : 0);
          },
        );
      }

      test('a final 220 greeting is not message acceptance', () async {
        server
          ..overrideStage = _Stage.payload
          ..overrideCode = 220;

        await expectLater(client.sendMessage(_message()), _rejected(220));

        expect(server.receivedPayloads, 1);
        expect(server.accepted, 0);
        expect(client.appended, 0);
        expect(client.lowLevelOutgoingMailClient.isConnected, isFalse);
      });

      test('final 250 confirms once and then files the Sent copy', () async {
        await client.sendMessage(_message());

        expect(server.receivedPayloads, 1);
        expect(server.accepted, 1);
        expect(client.appended, 1);
        expect(client.acceptedWhenAppended, isTrue);
        expect(client.lowLevelOutgoingMailClient.isConnected, isFalse);
      });

      test(
        'final 550 remains a submission failure without a Sent copy',
        () async {
          server
            ..overrideStage = _Stage.payload
            ..overrideCode = 550;

          await expectLater(client.sendMessage(_message()), _rejected(550));

          expect(server.receivedPayloads, 1);
          expect(server.accepted, 0);
          expect(client.appended, 0);
          expect(client.lowLevelOutgoingMailClient.isConnected, isFalse);
        },
      );

      if (!chunking) {
        test(
          'premature 250 to DATA is a failure even after a successful RSET',
          () async {
            server
              ..overrideStage = _Stage.dataCommand
              ..overrideCode = 250;

            await expectLater(client.sendMessage(_message()), _rejected(250));

            expect(server.commands, contains('RSET'));
            expect(server.receivedPayloads, 0);
            expect(server.accepted, 0);
            expect(client.appended, 0);
            expect(client.lowLevelOutgoingMailClient.isConnected, isFalse);
          },
        );
      }
    });
  }
}

Matcher _rejected(int code) => throwsA(
  isA<MailException>()
      .having(
        (error) => error is MailSendPostSubmissionException,
        'confirmed-submission warning',
        isFalse,
      )
      .having(
        (error) => (error.details as SmtpResponse).code,
        'original SMTP reply',
        code,
      ),
);

MimeMessage _message() =>
    (MessageBuilder()
          ..from = const [MailAddress('Sender', 'sender@example.test')]
          ..to = const [MailAddress('Recipient', 'recipient@example.test')]
          ..subject = 'Controlled submission acceptance'
          ..addTextPlain('Exact acceptance fixture.'))
        .buildMimeMessage();

final class _CopyObservingClient extends MailClient {
  _CopyObservingClient(this.server)
    : super(
        MailAccount.fromManualSettings(
          name: 'Local controlled SMTP fixture',
          email: 'sender@example.test',
          password: 'fixture-only-password',
          incomingHost: 'imap.invalid',
          outgoingHost: InternetAddress.loopbackIPv4.address,
          outgoingPort: server.port,
          outgoingSocketType: SocketType.plainNoStartTls,
        ),
      );

  final _SmtpFixture server;
  int appended = 0;
  bool acceptedWhenAppended = false;

  @override
  Mailbox? getMailbox(MailboxFlag flag, [List<Mailbox>? boxes]) => Mailbox(
    encodedName: 'Sent',
    encodedPath: 'Sent',
    flags: [MailboxFlag.sent],
    pathSeparator: '/',
  );

  @override
  Future<UidResponseCode?> appendMessage(
    MimeMessage message,
    Mailbox targetMailbox, {
    List<String>? flags,
  }) async {
    appended++;
    acceptedWhenAppended = server.accepted == 1;
    return null;
  }
}

/// A real loopback socket feeds the public MailClient and actual SMTP parser.
/// No external server, DNS lookup, TLS bypass in production, or mock-success
/// transport is involved. Only this local fixture selects plaintext SMTP.
final class _SmtpFixture {
  _SmtpFixture(this._server, {required this.chunking});

  final ServerSocket _server;
  final bool chunking;
  final _sockets = <Socket>[];
  final commands = <String>[];
  _Stage? overrideStage;
  int overrideCode = 250;
  int receivedPayloads = 0;
  int accepted = 0;

  int get port => _server.port;

  static Future<_SmtpFixture> start({required bool chunking}) async {
    final fixture = _SmtpFixture(
      await ServerSocket.bind(InternetAddress.loopbackIPv4, 0),
      chunking: chunking,
    );
    fixture._server.listen(fixture._connect);
    return fixture;
  }

  int _code(_Stage stage) => stage == overrideStage
      ? overrideCode
      : stage == _Stage.dataCommand
      ? 354
      : 250;

  void _connect(Socket socket) {
    _sockets.add(socket);
    socket.write('220 controlled ESMTP\r\n');
    var buffer = '';
    var dataMode = false;
    int? bdatBytes;
    var lastChunk = false;
    void completePayload() {
      receivedPayloads++;
      final code = _code(_Stage.payload);
      if (code == 250) {
        accepted++;
      }
      socket.write('$code controlled payload response\r\n');
    }

    socket.listen((bytes) {
      // Preserve one code unit per byte so BDAT byte lengths remain exact.
      buffer += String.fromCharCodes(bytes);
      while (true) {
        final expected = bdatBytes;
        if (expected != null) {
          if (buffer.length < expected) {
            return;
          }
          buffer = buffer.substring(expected);
          bdatBytes = null;
          if (lastChunk) {
            completePayload();
          } else {
            socket.write('250 controlled intermediate chunk\r\n');
          }
          continue;
        }
        final end = buffer.indexOf('\r\n');
        if (end < 0) {
          return;
        }
        final line = buffer.substring(0, end);
        buffer = buffer.substring(end + 2);
        if (dataMode) {
          if (line == '.') {
            dataMode = false;
            completePayload();
          }
          continue;
        }
        commands.add(line);
        if (line.startsWith('EHLO')) {
          socket.write(
            '250-controlled\r\n'
            '${chunking ? '250-CHUNKING\r\n' : ''}'
            '250 AUTH PLAIN\r\n',
          );
        } else if (line.startsWith('AUTH')) {
          socket.write('235 controlled authentication\r\n');
        } else if (line.startsWith('MAIL FROM:')) {
          socket.write('${_code(_Stage.sender)} controlled sender\r\n');
        } else if (line.startsWith('RCPT TO:')) {
          socket.write('${_code(_Stage.recipient)} controlled recipient\r\n');
        } else if (line == 'DATA') {
          final code = _code(_Stage.dataCommand);
          dataMode = code == 354;
          socket.write('$code controlled DATA response\r\n');
        } else if (line.startsWith('BDAT ')) {
          final fields = line.split(' ');
          bdatBytes = int.parse(fields[1]);
          lastChunk = fields.length == 3 && fields[2] == 'LAST';
        } else {
          socket.write('250 controlled reset\r\n');
        }
      }
    });
  }

  Future<void> close() async {
    for (final socket in _sockets) {
      socket.destroy();
    }
    await _server.close();
  }
}
