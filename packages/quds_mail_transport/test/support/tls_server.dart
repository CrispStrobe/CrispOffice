import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:quds_mail_transport/quds_mail_transport.dart';

SecurityContext localTlsServerContext() => SecurityContext()
  ..useCertificateChain(_fixture('loopback-cert.pem').path)
  ..usePrivateKey(_fixture('loopback-key.pem').path);

SecurityContext localTlsTrustContext() =>
    SecurityContext(withTrustedRoots: false)
      ..setTrustedCertificates(_fixture('loopback-cert.pem').path);

File _fixture(String name) {
  for (final directory in [
    'test/fixtures/tls',
    'packages/quds_mail_transport/test/fixtures/tls',
  ]) {
    final file = File('$directory/$name');
    if (file.existsSync()) return file;
  }
  throw FileSystemException('Public loopback TLS fixture was not found.', name);
}

/// A real loopback peer. Stalled mode accepts ClientHello and sends no TLS reply.
final class LocalTlsServer {
  LocalTlsServer._(this.listener, this.mode, this.stallHandshake) {
    _subscription = listener.listen(_accept);
  }

  static Future<LocalTlsServer> bind({
    required MailTlsMode mode,
    bool stallHandshake = false,
  }) async => LocalTlsServer._(
    await ServerSocket.bind(InternetAddress.loopbackIPv4, 0),
    mode,
    stallHandshake,
  );

  final ServerSocket listener;
  final MailTlsMode mode;
  bool stallHandshake;
  final List<LocalTlsPeer> peers = [];
  final StreamController<LocalTlsPeer> _arrivals =
      StreamController<LocalTlsPeer>.broadcast(sync: true);
  late final StreamSubscription<Socket> _subscription;

  int get port => listener.port;

  Future<LocalTlsPeer> peer(int index) => index < peers.length
      ? Future.value(peers[index])
      : _arrivals.stream.firstWhere((peer) => peers.indexOf(peer) == index);

  void _accept(Socket socket) {
    final peer = LocalTlsPeer(socket, stallHandshake: stallHandshake);
    peers.add(peer);
    _arrivals.add(peer);
    if (mode == MailTlsMode.implicitTls) {
      if (peer.stallHandshake) {
        peer.waitForClientHello();
      } else {
        unawaited(peer.upgrade(sendGreeting: true));
      }
    } else {
      peer.listenForCommands();
      peer.socket.write('* OK loopback fixture ready\r\n');
    }
  }

  Future<void> close() async {
    for (final peer in peers) {
      peer.destroy();
    }
    await _subscription.cancel();
    await listener.close();
    await _arrivals.close();
  }
}

final class LocalTlsPeer {
  LocalTlsPeer(this.tcp, {required this.stallHandshake}) : socket = tcp {
    _observeWriteErrors();
  }

  final Socket tcp;
  Socket socket;
  final bool stallHandshake;
  bool secure = false;
  bool _awaitingHandshake = false;
  StreamSubscription<Uint8List>? _subscription;
  final List<int> _lineBytes = [];
  final List<(bool, String)> commands = [];
  final Completer<void> clientHello = Completer<void>();
  final Completer<void> closed = Completer<void>();
  final List<int> handshakeBytes = [];
  final List<Object> unexpectedErrors = [];

  void _observeWriteErrors() {
    unawaited(socket.done.then<void>((_) {}, onError: _error));
  }

  void _done() {
    if (!closed.isCompleted) closed.complete();
  }

  void _error(Object error, StackTrace stack) {
    if (error is! SocketException && error is! HandshakeException) {
      unexpectedErrors.add(error);
    }
    destroy();
  }

  void destroy() {
    socket.destroy();
    if (!identical(socket, tcp)) tcp.destroy();
    _done();
  }

  void waitForClientHello() {
    _awaitingHandshake = true;
    _subscription = socket.listen(_data, onError: _error, onDone: _done);
  }

  void listenForCommands() {
    _subscription = socket.listen(_data, onError: _error, onDone: _done);
  }

  void _data(Uint8List bytes) {
    if (_awaitingHandshake) {
      if (handshakeBytes.length + bytes.length > 64 * 1024) {
        throw StateError('Unexpectedly large stalled TLS handshake');
      }
      handshakeBytes.addAll(bytes);
      if (!clientHello.isCompleted &&
          handshakeBytes.length >= 6 &&
          handshakeBytes.first == 22 &&
          handshakeBytes[1] == 3 &&
          handshakeBytes[5] == 1) {
        clientHello.complete();
      }
      return;
    }
    _lineBytes.addAll(bytes);
    while (true) {
      final end = _lineBytes.indexOf(10);
      if (end < 0) return;
      final line = utf8.decode(_lineBytes.sublist(0, end)).trimRight();
      _lineBytes.removeRange(0, end + 1);
      final space = line.indexOf(' ');
      if (space < 1) throw StateError('Expected a tagged fixture command');
      final tag = line.substring(0, space);
      final command = line.substring(space + 1);
      commands.add((secure, command));
      if (command == 'STARTTLS') {
        socket.write('$tag OK begin TLS\r\n');
        if (stallHandshake) {
          _awaitingHandshake = true;
        } else {
          _subscription?.pause();
          unawaited(upgrade(sendGreeting: false));
        }
        return;
      }
      if (command == 'CAPABILITY') {
        socket.write(
          '* CAPABILITY IMAP4rev1${secure ? '' : ' STARTTLS'}\r\n'
          '$tag OK capabilities\r\n',
        );
      } else if (command.startsWith('LOGIN ')) {
        socket.write('$tag OK authenticated\r\n');
      } else if (command.startsWith('LIST ')) {
        socket.write('* LIST () "/" "INBOX"\r\n$tag OK folders\r\n');
      } else if (command == 'NOOP') {
        socket.write('$tag OK done\r\n');
      } else {
        socket.write('$tag BAD unexpected fixture command\r\n');
      }
    }
  }

  Future<void> upgrade({required bool sendGreeting}) async {
    try {
      await socket.flush();
      final oldSubscription = _subscription;
      final secured = await SecureSocket.secureServer(
        socket,
        localTlsServerContext(),
      );
      await oldSubscription?.cancel();
      socket = secured;
      _observeWriteErrors();
      secure = true;
      listenForCommands();
      if (sendGreeting) socket.write('* OK loopback fixture ready\r\n');
    } on HandshakeException {
      destroy();
    } on SocketException {
      destroy();
    } on Object catch (error) {
      unexpectedErrors.add(error);
      destroy();
    }
  }
}
