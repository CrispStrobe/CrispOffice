import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:enough_mail/enough_mail.dart';
import 'package:test/test.dart';

import 'support/tls_server.dart';

const _deadline = Duration(seconds: 10);
const _payloadLength = 1024 * 1024;

void main() {
  for (final implicitTls in [true, false]) {
    final name = implicitTls ? 'implicit TLS' : 'STARTTLS';
    test(
      '$name trusted TLS preserves delayed large writes and replies',
      () async {
        final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        final accepted = Completer<_TlsPeer>();
        final peers = <_TlsPeer>[];
        final listener = server.listen((socket) {
          final peer = _TlsPeer(
            socket,
            localTlsServerContext(),
            implicitTls: implicitTls,
          );
          peers.add(peer);
          accepted.complete(peer);
        });
        final client = ImapClient(securityContext: localTlsTrustContext());
        try {
          await client
              .connectToServer(
                InternetAddress.loopbackIPv4.address,
                server.port,
                isSecure: implicitTls,
                timeout: _deadline,
              )
              .timeout(_deadline);
          await client.capability().timeout(_deadline);
          if (!implicitTls) await client.startTls().timeout(_deadline);
          final peer = await accepted.future.timeout(_deadline);
          await peer.handshakeFinished.future.timeout(_deadline);
          expect(peer.handshakeError, isNull);
          expect(peer.secureSocket, isNotNull);
          expect(client.isConnected, isTrue);

          final payload = Uint8List.fromList(
            List<int>.generate(
              _payloadLength,
              (index) => (index * 31 + 7) & 255,
            ),
          );
          peer.prepareDelayedPayloadRead(_payloadLength);
          await client.writeData(payload).timeout(_deadline);
          await peer.payloadReceived.future.timeout(_deadline);
          expect(peer.payloadLength, payload.length);
          expect(peer.payloadDigest, sha256.convert(payload).toString());
          // The peer replies only after consuming the entire expected payload.
          // A subsequent command checks that both directions remain usable.
          final before = peer.capabilityCommands;
          await client.capability().timeout(_deadline);
          expect(peer.capabilityCommands, before + 1);
          expect(peer.unexpectedCommands, isEmpty);
        } finally {
          await client.abort().timeout(_deadline);
          for (final peer in peers) {
            peer.dispose();
          }
          await listener.cancel();
          await server.close();
        }
      },
    );

    test(
      '$name default trust refuses the same public test certificate',
      () async {
        final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        final accepted = Completer<_TlsPeer>();
        final peers = <_TlsPeer>[];
        final listener = server.listen((socket) {
          final peer = _TlsPeer(
            socket,
            localTlsServerContext(),
            implicitTls: implicitTls,
          );
          peers.add(peer);
          accepted.complete(peer);
        });
        final client = ImapClient();
        try {
          if (implicitTls) {
            await expectLater(
              client
                  .connectToServer(
                    InternetAddress.loopbackIPv4.address,
                    server.port,
                    timeout: _deadline,
                  )
                  .timeout(_deadline),
              throwsA(isA<HandshakeException>()),
            );
          } else {
            await client
                .connectToServer(
                  InternetAddress.loopbackIPv4.address,
                  server.port,
                  isSecure: false,
                  timeout: _deadline,
                )
                .timeout(_deadline);
            await client.capability().timeout(_deadline);
            await expectLater(
              client.startTls().timeout(_deadline),
              throwsA(isA<HandshakeException>()),
            );
          }
          final peer = await accepted.future.timeout(_deadline);
          await peer.handshakeFinished.future.timeout(_deadline);
          expect(peer.secureSocket, isNull);
          expect(peer.handshakeError, isA<HandshakeException>());
          // Check rejection cleanup before finally calls abort itself.
          expect(client.isConnected, isFalse);
          expect(client.isLoggedIn, isFalse);
          expect(peer.unexpectedCommands, isEmpty);
        } finally {
          await client.abort().timeout(_deadline);
          for (final peer in peers) {
            peer.dispose();
          }
          await listener.cancel();
          await server.close();
        }
      },
    );
  }

  test(
    'aborting trusted TLS fails and cancels an idle write producer',
    () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final peers = <_TlsPeer>[];
      final listener = server.listen((socket) {
        peers.add(_TlsPeer(socket, localTlsServerContext(), implicitTls: true));
      });
      final client = _CapturingImapClient(localTlsTrustContext());
      StreamController<List<int>>? producer;
      try {
        await client
            .connectToServer(
              InternetAddress.loopbackIPv4.address,
              server.port,
              timeout: _deadline,
            )
            .timeout(_deadline);
        await client.capability().timeout(_deadline);

        final listening = Completer<void>();
        final cancelled = Completer<void>();
        producer = StreamController<List<int>>(
          onListen: listening.complete,
          onCancel: cancelled.complete,
        );
        final pending = client.transport!.addStream(producer.stream);
        // Attach the rejection observer before abort can fail the sink. Waiting
        // for onListen proves the consumer is awaiting an open producer stream.
        final rejection = expectLater(
          pending.timeout(_deadline),
          throwsA(isA<SocketException>()),
        );
        await listening.future.timeout(_deadline);
        await client.abort().timeout(_deadline);
        await rejection;
        await cancelled.future.timeout(_deadline);
      } finally {
        await client.abort().timeout(_deadline);
        if (producer != null) await producer.close().timeout(_deadline);
        for (final peer in peers) {
          peer.dispose();
        }
        await listener.cancel();
        await server.close();
      }
    },
  );
}

final class _CapturingImapClient extends ImapClient {
  _CapturingImapClient(SecurityContext context)
    : super(securityContext: context);

  Socket? transport;

  @override
  Future<Socket> createConnectionSocket(
    String host,
    int port, {
    required bool isSecure,
  }) async {
    final socket = await super.createConnectionSocket(
      host,
      port,
      isSecure: isSecure,
    );
    transport = socket;
    return socket;
  }

  @override
  Future<Socket> createSecureConnectionSocket(
    Socket socket, {
    required String host,
  }) async {
    final secured = await super.createSecureConnectionSocket(
      socket,
      host: host,
    );
    transport = secured;
    return secured;
  }
}

final class _TlsPeer {
  _TlsPeer(this.socket, this.context, {required bool implicitTls}) {
    if (implicitTls) {
      unawaited(_upgrade(sendGreeting: true));
    } else {
      _listen(socket);
      socket.write('* OK loopback TLS fixture\r\n');
    }
  }

  final Socket socket;
  final SecurityContext context;
  final handshakeFinished = Completer<void>();
  final payloadReceived = Completer<void>();
  final unexpectedCommands = <String>[];
  final _line = <int>[];
  final _payload = BytesBuilder(copy: false);
  StreamSubscription<Uint8List>? _input;
  Timer? _readDelay;
  SecureSocket? secureSocket;
  Object? handshakeError;
  int capabilityCommands = 0;
  int payloadLength = 0;
  String? payloadDigest;
  int _payloadRemaining = 0;
  bool _upgrading = false;

  Socket get _current => secureSocket ?? socket;

  void _listen(Socket transport) {
    unawaited(
      transport.done.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
    );
    _input = transport.listen(_receive, onError: (Object _, StackTrace _) {});
  }

  Future<void> _upgrade({bool sendGreeting = false}) async {
    _upgrading = true;
    _input?.pause();
    try {
      await socket.flush();
      final upgraded = await SecureSocket.secureServer(socket, context);
      final previousInput = _input;
      if (previousInput != null) await previousInput.cancel();
      secureSocket = upgraded;
      _upgrading = false;
      _listen(upgraded);
      if (sendGreeting) upgraded.write('* OK loopback TLS fixture\r\n');
    } on Object catch (error) {
      handshakeError = error;
    } finally {
      handshakeFinished.complete();
    }
  }

  void prepareDelayedPayloadRead(int length) {
    _payloadRemaining = length;
    _input!.pause();
    _readDelay = Timer(const Duration(milliseconds: 250), () {
      _input!.resume();
    });
  }

  void _receive(Uint8List bytes) {
    var offset = 0;
    if (_payloadRemaining > 0) {
      final length = bytes.length < _payloadRemaining
          ? bytes.length
          : _payloadRemaining;
      _payload.add(Uint8List.sublistView(bytes, 0, length));
      payloadLength += length;
      _payloadRemaining -= length;
      offset = length;
      if (_payloadRemaining == 0) {
        payloadDigest = sha256.convert(_payload.takeBytes()).toString();
        _current.write('* OK TLS payload accepted\r\n');
        payloadReceived.complete();
      }
    }
    for (; offset < bytes.length; offset++) {
      _line.add(bytes[offset]);
      if (_line.length < 2 ||
          _line[_line.length - 2] != 13 ||
          _line.last != 10) {
        continue;
      }
      final line = ascii.decode(_line.sublist(0, _line.length - 2));
      _line.clear();
      final separator = line.indexOf(' ');
      final tag = separator < 1 ? '' : line.substring(0, separator);
      final command = separator < 1 ? line : line.substring(separator + 1);
      switch (command) {
        case 'CAPABILITY':
          capabilityCommands++;
          _current.write(
            '* CAPABILITY IMAP4rev1 STARTTLS\r\n$tag OK capabilities\r\n',
          );
        case 'STARTTLS':
          _current.write('$tag OK begin TLS\r\n');
          unawaited(_upgrade());
        default:
          unexpectedCommands.add(line);
      }
      if (_upgrading) return;
    }
  }

  void dispose() {
    _readDelay?.cancel();
    secureSocket?.destroy();
    socket.destroy();
  }
}
