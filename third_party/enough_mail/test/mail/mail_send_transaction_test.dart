import 'dart:async';
import 'dart:io';

import 'package:enough_mail/enough_mail.dart';
import 'package:enough_mail/src/private/mail/send_message_transaction.dart';
import 'package:test/test.dart';

MailAccount _account({int smtpPort = 25}) => MailAccount.fromManualSettings(
  name: 'test',
  email: 'sender@example.test',
  password: 'test-only',
  incomingHost: 'imap.invalid',
  outgoingHost: InternetAddress.loopbackIPv4.address,
  outgoingPort: smtpPort,
  outgoingSocketType: SocketType.plainNoStartTls,
);

MimeMessage _message() =>
    (MessageBuilder()
          ..from = const [MailAddress('Sender', 'sender@example.test')]
          ..to = const [MailAddress('Recipient', 'recipient@example.test')]
          ..subject = 'Submission ordering'
          ..addTextPlain('Local test message.'))
        .buildMimeMessage();

Future<MailSendPostSubmissionException> _outcome(Future<void> operation) async {
  try {
    await operation;
  } on MailSendPostSubmissionException catch (error) {
    return error;
  }
  throw StateError('Expected a post-submission warning.');
}

void main() {
  group('submission transaction', () {
    late MailClient client;

    setUp(() => client = MailClient(_account()));

    test(
      'waits for SMTP acceptance before filing and then cleans up',
      () async {
        final accepted = Completer<void>();
        final steps = <String>[];
        final operation = submitMessageAndStoreCopy(
          client,
          submit: () {
            steps.add('submit');
            return accepted.future;
          },
          storeCopy: () async => steps.add('copy'),
          disconnect: () async => steps.add('disconnect'),
        );
        expect(steps, ['submit']);
        accepted.complete();
        await operation;
        expect(steps, ['submit', 'copy', 'disconnect']);
      },
    );

    test('failed submission never files a Sent copy', () async {
      final failure = StateError('SMTP refused the payload');
      final steps = <String>[];
      await expectLater(
        submitMessageAndStoreCopy(
          client,
          submit: () async {
            steps.add('submit');
            throw failure;
          },
          storeCopy: () async => steps.add('copy'),
          disconnect: () async => steps.add('disconnect'),
        ),
        throwsA(same(failure)),
      );
      expect(steps, ['submit', 'disconnect']);
    });

    test(
      'cleanup cannot replace the original submission error or stack',
      () async {
        final failure = StateError('original SMTP failure');
        final stack = StackTrace.fromString('submission-origin');
        var copied = false;
        try {
          await submitMessageAndStoreCopy(
            client,
            submit: () => Future<void>.error(failure, stack),
            storeCopy: () async => copied = true,
            disconnect: () async =>
                throw StateError('secondary cleanup failure'),
          );
          fail('Expected the original submission failure.');
        } catch (error, actualStack) {
          expect(error, same(failure));
          expect(actualStack.toString(), stack.toString());
        }
        expect(copied, isFalse);
      },
    );

    test(
      'a failed Sent append reports confirmed submission and cleans up',
      () async {
        final failure = StateError('Sent append failed');
        final stack = StackTrace.fromString('append-origin');
        var cleanedUp = false;
        final outcome = await _outcome(
          submitMessageAndStoreCopy(
            client,
            submit: () async {},
            storeCopy: () => Future<void>.error(failure, stack),
            disconnect: () async => cleanedUp = true,
          ),
        );
        expect(outcome.mailClient, same(client));
        expect(outcome.sentCopyError, same(failure));
        expect(outcome.sentCopyStackTrace.toString(), stack.toString());
        expect(outcome.cleanupError, isNull);
        expect(cleanedUp, isTrue);
      },
    );

    test(
      'cleanup failure does not turn a submitted message into unsent',
      () async {
        final failure = StateError('disconnect failed');
        final stack = StackTrace.fromString('disconnect-origin');
        var copied = false;
        final outcome = await _outcome(
          submitMessageAndStoreCopy(
            client,
            submit: () async {},
            storeCopy: () async => copied = true,
            disconnect: () => Future<void>.error(failure, stack),
          ),
        );
        expect(copied, isTrue);
        expect(outcome.sentCopyError, isNull);
        expect(outcome.cleanupError, same(failure));
        expect(outcome.cleanupStackTrace.toString(), stack.toString());
      },
    );

    test('both post-submission failures remain separately available', () async {
      final copyFailure = StateError('append failed');
      final cleanupFailure = StateError('disconnect failed');
      final copyStack = StackTrace.fromString('append-origin');
      final cleanupStack = StackTrace.fromString('cleanup-origin');
      final outcome = await _outcome(
        submitMessageAndStoreCopy(
          client,
          submit: () async {},
          storeCopy: () => Future<void>.error(copyFailure, copyStack),
          disconnect: () => Future<void>.error(cleanupFailure, cleanupStack),
        ),
      );
      expect(outcome.sentCopyError, same(copyFailure));
      expect(outcome.sentCopyStackTrace.toString(), copyStack.toString());
      expect(outcome.cleanupError, same(cleanupFailure));
      expect(outcome.cleanupStackTrace.toString(), cleanupStack.toString());
    });

    test('copy opt-out still cleans up after confirmed submission', () async {
      final steps = <String>[];
      await submitMessageAndStoreCopy(
        client,
        submit: () async => steps.add('submit'),
        disconnect: () async => steps.add('disconnect'),
      );
      expect(steps, ['submit', 'disconnect']);
    });

    test(
      'copy opt-out still exposes a post-submission cleanup failure',
      () async {
        final failure = StateError('disconnect failed');
        final outcome = await _outcome(
          submitMessageAndStoreCopy(
            client,
            submit: () async {},
            disconnect: () async => throw failure,
          ),
        );
        expect(outcome.sentCopyError, isNull);
        expect(outcome.cleanupError, same(failure));
      },
    );
  });

  group('MailClient with a local SMTP server', () {
    late _SmtpFixture server;
    late _CopyObservingClient client;

    setUp(() async {
      server = await _SmtpFixture.start();
      client = _CopyObservingClient(server);
    });

    tearDown(() async {
      await client.disconnect();
      await server.close();
    });

    test(
      'successful submission appends only after final SMTP acceptance',
      () async {
        await client.sendMessage(_message());
        expect(server.accepted, 1);
        expect(client.appended, 1);
        expect(client.acceptedWhenAppended, isTrue);
        expect(client.appendedFlags, [MessageFlags.seen]);
        expect(client.lowLevelOutgoingMailClient.isConnected, isFalse);
      },
    );

    test(
      'rejected SMTP payload creates no Sent copy or submitted warning',
      () async {
        server.rejectPayload = true;
        await expectLater(
          client.sendMessage(_message()),
          throwsA(
            isA<MailException>()
                .having(
                  (error) => error is MailSendPostSubmissionException,
                  'post-submission warning',
                  isFalse,
                )
                .having(
                  (error) => (error.details as SmtpResponse).code,
                  'SMTP rejection',
                  550,
                ),
          ),
        );
        expect(server.accepted, 0);
        expect(client.appended, 0);
        expect(client.lowLevelOutgoingMailClient.isConnected, isFalse);
      },
    );

    test('SMTP abort releases pending send and disconnect', () async {
      const limit = Duration(seconds: 2);
      server.holdMailFromResponse = true;
      final smtp = client.lowLevelOutgoingMailClient as SmtpClient;
      final send = client
          .sendMessage(_message())
          .then<(Object?, StackTrace?)>(
            (_) => (null, null),
            onError: (Object error, StackTrace stack) => (error, stack),
          );
      Future<void>? disconnect;
      try {
        await server.mailFromReceived.future.timeout(limit);
        // Disconnect queues behind the send, which is awaiting the held reply.
        disconnect = client.disconnect();
        await smtp.abort().timeout(limit);
        await smtp.abort().timeout(limit);
        final (error, stack) = await send.timeout(limit);
        expect(
          error,
          isA<MailException>()
              .having(
                (error) => error is MailSendPostSubmissionException,
                'post-submission warning',
                isFalse,
              )
              .having(
                (error) => error.details,
                'SMTP abort response',
                isA<SmtpResponse>()
                    .having((response) => response.code, 'code', 500)
                    .having(
                      (response) => response.message,
                      'message',
                      'client aborted',
                    ),
              ),
        );
        expect(stack?.toString(), isNotEmpty);
        await disconnect.timeout(limit);
        expect(server.accepted, 0);
        expect(client.appended, 0);
        expect(smtp.isConnected, isFalse);
        expect(smtp.isLoggedIn, isFalse);
      } finally {
        // Complete even a broken implementation's pending command so a failed
        // regression cannot leave public disconnect hanging during teardown.
        await smtp.disconnect().timeout(limit);
        await send.timeout(limit);
        if (disconnect != null) {
          await disconnect.timeout(limit);
        }
      }
    });

    test(
      'append failure preserves confirmed submission at the public API',
      () async {
        final failure = StateError('cannot file a Sent copy');
        client.appendFailure = failure;
        final outcome = await _outcome(client.sendMessage(_message()));
        expect(server.accepted, 1);
        expect(client.appended, 1);
        expect(client.acceptedWhenAppended, isTrue);
        expect(outcome.sentCopyError, same(failure));
        expect(outcome.cleanupError, isNull);
        expect(client.lowLevelOutgoingMailClient.isConnected, isFalse);
      },
    );

    test(
      'missing Sent mailbox is a warning after confirmed submission',
      () async {
        client.hasSentMailbox = false;
        final outcome = await _outcome(client.sendMessage(_message()));
        expect(server.accepted, 1);
        expect(client.appended, 0);
        expect(outcome.sentCopyError, isA<MailException>());
        expect(outcome.cleanupError, isNull);
        expect(client.lowLevelOutgoingMailClient.isConnected, isFalse);
      },
    );

    test('append opt-out does not require a Sent mailbox', () async {
      client.hasSentMailbox = false;
      await client.sendMessage(_message(), appendToSent: false);
      expect(server.accepted, 1);
      expect(client.appended, 0);
      expect(client.lowLevelOutgoingMailClient.isConnected, isFalse);
    });
  });
}

class _CopyObservingClient extends MailClient {
  _CopyObservingClient(this.server) : super(_account(smtpPort: server.port));

  final _SmtpFixture server;
  bool hasSentMailbox = true;
  int appended = 0;
  bool acceptedWhenAppended = false;
  List<String>? appendedFlags;
  Error? appendFailure;

  @override
  Mailbox? getMailbox(MailboxFlag flag, [List<Mailbox>? boxes]) =>
      hasSentMailbox
      ? Mailbox(
          encodedName: 'Sent',
          encodedPath: 'Sent',
          flags: [MailboxFlag.sent],
          pathSeparator: '/',
        )
      : null;

  @override
  Future<UidResponseCode?> appendMessage(
    MimeMessage message,
    Mailbox targetMailbox, {
    List<String>? flags,
  }) async {
    appended++;
    acceptedWhenAppended = server.accepted > 0;
    appendedFlags = flags;
    final failure = appendFailure;
    if (failure != null) {
      throw failure;
    }
    return null;
  }
}

class _SmtpFixture {
  _SmtpFixture(this._listener);

  final ServerSocket _listener;
  final _sockets = <Socket>[];
  bool rejectPayload = false;
  bool holdMailFromResponse = false;
  final mailFromReceived = Completer<void>();
  int accepted = 0;

  int get port => _listener.port;

  static Future<_SmtpFixture> start() async {
    final fixture = _SmtpFixture(
      await ServerSocket.bind(InternetAddress.loopbackIPv4, 0),
    );
    fixture._listener.listen(fixture._connect);
    return fixture;
  }

  void _connect(Socket socket) {
    _sockets.add(socket);
    socket.write('220 test ESMTP\r\n');
    var buffer = '';
    var dataMode = false;
    socket.listen((bytes) {
      buffer += String.fromCharCodes(bytes);
      while (buffer.contains('\r\n')) {
        final end = buffer.indexOf('\r\n');
        final line = buffer.substring(0, end);
        buffer = buffer.substring(end + 2);
        if (dataMode) {
          if (line == '.') {
            dataMode = false;
            if (rejectPayload) {
              socket.write('550 5.7.1 payload rejected\r\n');
            } else {
              accepted++;
              socket.write('250 2.0.0 queued\r\n');
            }
          }
        } else if (line.startsWith('EHLO')) {
          socket.write('250-test\r\n250 AUTH PLAIN\r\n');
        } else if (line.startsWith('AUTH')) {
          socket.write('235 authenticated\r\n');
        } else if (line.startsWith('MAIL FROM') && holdMailFromResponse) {
          if (!mailFromReceived.isCompleted) {
            mailFromReceived.complete();
          }
        } else if (line == 'DATA') {
          dataMode = true;
          socket.write('354 send payload\r\n');
        } else {
          socket.write('250 ok\r\n');
        }
      }
    });
  }

  Future<void> close() async {
    for (final socket in _sockets) {
      socket.destroy();
    }
    await _listener.close();
  }
}
