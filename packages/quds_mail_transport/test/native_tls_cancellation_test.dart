import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_transport/quds_mail_transport.dart';
import 'package:test/test.dart';

const _secret = 'tls-fixture-only-secret';
const _operationTimeout = Duration(seconds: 2);
const _observationTimeout = Duration(seconds: 3);

void main() {
  for (final mode in MailTlsMode.values) {
    for (final cancel in [true, false]) {
      test(
        '${mode.name} stalled handshake ${cancel ? 'cancellation' : 'timeout'} '
        'closes the real peer and permits a fresh connection',
        () => _exerciseStalledHandshake(mode, cancel: cancel),
      );
    }
  }
}

Future<void> _exerciseStalledHandshake(
  MailTlsMode mode, {
  required bool cancel,
}) async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final peers = <_StalledTlsPeer>[];
  final accepted = [Completer<_StalledTlsPeer>(), Completer<_StalledTlsPeer>()];
  final listener = server.listen((socket) {
    final peer = _StalledTlsPeer(socket, mode);
    peers.add(peer);
    if (peers.length <= accepted.length) {
      accepted[peers.length - 1].complete(peer);
    }
  });
  final account = MailAccountId(
    'tls-fixture',
    profile: MailProfileId('tls-fixture', hostId: 'loopback-test'),
  );
  final credentials = _Credentials();
  final provider = createMailImapProvider(
    configuration: MailImapConfiguration(
      account: account,
      endpoint: MailServerEndpoint(
        host: InternetAddress.loopbackIPv4.address,
        port: server.port,
        tls: mode,
      ),
      username: 'tls-fixture-user',
      credential: MailCredentialReference(account: account, key: 'tls-fixture'),
    ),
    credentialStore: credentials,
    limits: const MailTransportLimits(
      operationTimeout: _operationTimeout,
      cancellationPollInterval: Duration(milliseconds: 5),
    ),
  );
  final session = MailAccountSession(account);

  try {
    for (var attempt = 0; attempt < accepted.length; attempt++) {
      final cancellation = MailCancellationSource();
      final pending = provider.capabilities(
        session.begin(cancellation: cancellation.token),
      );
      final peer = await accepted[attempt].future.timeout(_observationTimeout);
      // TCP acceptance alone is insufficient: prove that the SDK has begun its
      // TLS handshake and ownership has moved beyond connection establishment.
      await peer.clientHello.future.timeout(_observationTimeout);
      expect(peer.closed.isCompleted, isFalse);

      final shouldCancel = cancel || attempt > 0;
      if (shouldCancel) cancellation.cancel();
      final result = await pending.timeout(_observationTimeout);
      expect(result, isA<MailFailure<MailCapabilities>>());
      expect(
        (result as MailFailure<MailCapabilities>).problem.code,
        shouldCancel ? MailProblemCode.cancelled : MailProblemCode.unavailable,
      );
      // This is observed before test teardown, without releasing the stalled
      // handshake or making the peer close its own connection.
      await peer.closed.future.timeout(const Duration(seconds: 1));
      expect(peer.unexpectedCommands, isEmpty);
      expect(latin1.decode(peer.receivedBytes), isNot(contains(_secret)));
      expect(
        peer.commands.where(
          (line) => RegExp(r'^\S+ (?:LOGIN|AUTHENTICATE)\b').hasMatch(line),
        ),
        isEmpty,
      );
      if (mode == MailTlsMode.startTls) {
        expect(
          peer.commands.where((line) => line.endsWith(' STARTTLS')),
          hasLength(1),
        );
      } else {
        expect(peer.commands, isEmpty);
      }
    }
    // A second actual ClientHello on another accepted socket proves that the
    // same provider released its busy state and did not reuse the stale socket.
    expect(peers, hasLength(2));
    expect(identical(peers[0].socket, peers[1].socket), isFalse);
    expect(credentials.loads, 2);
  } finally {
    for (final peer in peers) {
      peer.socket.destroy();
    }
    await listener.cancel();
    await server.close();
  }
}

final class _StalledTlsPeer {
  _StalledTlsPeer(this.socket, MailTlsMode mode)
    : _inTls = mode == MailTlsMode.implicitTls {
    // Handle socket sink errors as well as input errors during expected aborts.
    unawaited(
      socket.done.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
    );
    socket.listen(
      _receive,
      onError: (Object _, StackTrace _) {},
      onDone: () {
        if (!closed.isCompleted) closed.complete();
      },
    );
    if (!_inTls) socket.write('* OK loopback TLS cancellation fixture\r\n');
  }

  final Socket socket;
  final clientHello = Completer<void>();
  final closed = Completer<void>();
  final receivedBytes = <int>[];
  final commands = <String>[];
  final unexpectedCommands = <String>[];
  final _plain = <int>[];
  final _tlsPrefix = <int>[];
  bool _inTls;

  void _receive(List<int> bytes) {
    if (receivedBytes.length + bytes.length > 64 * 1024) {
      fail('The stalled TLS peer received an unexpected amount of data.');
    }
    receivedBytes.addAll(bytes);
    for (final byte in bytes) {
      if (_inTls) {
        if (_tlsPrefix.length < 6) _tlsPrefix.add(byte);
        if (_tlsPrefix.length == 6 && !clientHello.isCompleted) {
          // TLS record handshake(22), legacy major version(3), ClientHello(1).
          expect(_tlsPrefix[0], 22);
          expect(_tlsPrefix[1], 3);
          expect(_tlsPrefix[5], 1);
          clientHello.complete();
        }
        continue;
      }
      _plain.add(byte);
      if (_plain.length < 2 ||
          _plain[_plain.length - 2] != 13 ||
          _plain.last != 10) {
        continue;
      }
      final line = ascii.decode(_plain.sublist(0, _plain.length - 2));
      _plain.clear();
      commands.add(line);
      final separator = line.indexOf(' ');
      if (separator < 1) {
        unexpectedCommands.add(line);
        continue;
      }
      final tag = line.substring(0, separator);
      final command = line.substring(separator + 1);
      switch (command) {
        case 'CAPABILITY':
          socket.write(
            '* CAPABILITY IMAP4rev1 STARTTLS AUTH=PLAIN\r\n'
            '$tag OK capabilities\r\n',
          );
        case 'STARTTLS':
          _inTls = true;
          socket.write('$tag OK begin TLS\r\n');
        default:
          unexpectedCommands.add(line);
      }
    }
  }
}

final class _Credentials implements MailCredentialStore {
  int loads = 0;

  @override
  Future<MailResult<MailCredentialRecord?>> load(
    MailCredentialReference reference,
  ) async {
    loads++;
    return MailSuccess(
      MailCredentialRecord(
        reference: reference,
        opaqueData: MailBytes(ascii.encode(_secret)),
      ),
    );
  }

  @override
  Future<MailResult<MailUnit>> store(MailCredentialRecord record) async =>
      const MailSuccess(MailUnit.value);

  @override
  Future<MailResult<MailUnit>> delete(
    MailCredentialReference reference,
  ) async => const MailSuccess(MailUnit.value);

  @override
  Future<MailResult<MailUnit>> deleteAccount(MailAccountId account) async =>
      const MailSuccess(MailUnit.value);
}
