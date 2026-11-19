@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:enough_mail/imap.dart' as imap;
import 'package:enough_mail/src/private/util/client_base.dart';
import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_mime/quds_mail_mime.dart';
import 'package:quds_mail_transport/quds_mail_transport.dart';
import 'package:quds_mail_transport/src/native/provider.dart';
import 'package:test/test.dart';

import 'support/imap_fixture.dart';
import 'support/tls_server.dart';

final _account = MailAccountId(
  'loopback-account',
  profile: MailProfileId('loopback-profile', hostId: 'loopback-host'),
);

MailOperationLease _lease() => MailAccountSession(_account).begin();

NativeMailImapProvider _provider(
  LocalTlsServer server, {
  bool trustFixture = true,
  String host = '127.0.0.1',
  Duration timeout = const Duration(seconds: 3),
  List<HandshakeException>? handshakeFailures,
  List<imap.ImapClient>? clients,
}) => NativeMailImapProvider(
  configuration: MailImapConfiguration(
    account: _account,
    endpoint: MailServerEndpoint(
      host: host,
      port: server.port,
      tls: server.mode,
    ),
    username: 'loopback-reader',
    credential: MailCredentialReference(
      account: _account,
      key: 'imap-password',
    ),
  ),
  credentialStore: FixtureCredentials(_account),
  codec: const QudsMimeCodec(),
  limits: MailTransportLimits(operationTimeout: timeout),
  clientFactory:
      ({required maxLiteralBytes, required maxResponseBytes, required limits}) {
        final client = _ObservedImapClient(
          handshakeFailures: handshakeFailures ?? [],
          securityContext: trustFixture ? localTlsTrustContext() : null,
          defaultResponseTimeout: limits.operationTimeout,
          defaultWriteTimeout: limits.operationTimeout,
          maxLiteralSize: maxLiteralBytes,
          maxResponseBytes: maxResponseBytes,
          maxProtocolLineBytes: limits.maxProtocolLineBytes,
        );
        clients?.add(client);
        return client;
      },
);

MailProblemCode _code<T>(MailResult<T> result) =>
    (result as MailFailure<T>).problem.code;

void main() {
  for (final mode in MailTlsMode.values) {
    test(
      '${mode.name}: direct pending TLS operation settles when aborted',
      () async {
        final server = await LocalTlsServer.bind(
          mode: mode,
          stallHandshake: true,
        );
        addTearDown(server.close);
        final client = imap.ImapClient();
        addTearDown(client.abort);
        final pending = () async {
          await client.connectToServer(
            '127.0.0.1',
            server.port,
            isSecure: mode == MailTlsMode.implicitTls,
            timeout: const Duration(seconds: 30),
          );
          if (mode == MailTlsMode.startTls) {
            await client.capability();
            await client.startTls();
          }
        }();
        // Observe the original direct API future before aborting. The native
        // provider's independent cancellation race cannot settle this future.
        final failure = pending.then<Object?>(
          (_) => null,
          onError: (Object error, StackTrace _) => error,
        );
        final peer = await server.peer(0);
        await peer.clientHello.future.timeout(const Duration(seconds: 2));
        await client.abort().timeout(const Duration(seconds: 1));
        expect(
          await failure.timeout(const Duration(seconds: 1)),
          anyOf(isA<imap.ImapException>(), isA<SocketException>()),
        );
        await peer.closed.future.timeout(const Duration(seconds: 1));
        expect(client.isConnected, isFalse);
        expect(
          peer.commands.any((entry) => entry.$2.startsWith('LOGIN ')),
          isFalse,
        );
      },
    );

    test(
      '${mode.name}: real stalled handshake closes on cancellation and retries',
      () async {
        final server = await LocalTlsServer.bind(
          mode: mode,
          stallHandshake: true,
        );
        addTearDown(server.close);
        final provider = _provider(server);
        final cancellation = MailCancellationSource();
        final pending = provider.capabilities(
          MailAccountSession(_account).begin(cancellation: cancellation.token),
        );
        final first = await server.peer(0);
        await first.clientHello.future.timeout(const Duration(seconds: 2));
        cancellation.cancel();
        expect(
          _code(await pending.timeout(const Duration(seconds: 1))),
          MailProblemCode.cancelled,
        );
        await first.closed.future.timeout(const Duration(seconds: 1));
        expect(
          first.commands.any((entry) => entry.$2.startsWith('LOGIN ')),
          isFalse,
        );
        expect(
          String.fromCharCodes(first.handshakeBytes),
          isNot(contains('fixture-only-password')),
        );

        server.stallHandshake = false;
        expect(
          await provider.capabilities(_lease()),
          isA<MailSuccess<MailCapabilities>>(),
        );
        final next = await server.peer(1);
        expect(first.closed.isCompleted, isTrue);
        expect(
          next.commands.any(
            (entry) => entry.$1 && entry.$2.startsWith('LOGIN '),
          ),
          isTrue,
        );
        await next.closed.future.timeout(const Duration(seconds: 1));
      },
    );

    test(
      '${mode.name}: operation deadline closes a real stalled handshake',
      () async {
        final server = await LocalTlsServer.bind(
          mode: mode,
          stallHandshake: true,
        );
        addTearDown(server.close);
        final elapsed = Stopwatch()..start();
        final pending = _provider(
          server,
          timeout: const Duration(milliseconds: 600),
        ).capabilities(_lease());
        final peer = await server.peer(0);
        await peer.clientHello.future.timeout(const Duration(seconds: 2));
        expect(
          _code(await pending.timeout(const Duration(seconds: 2))),
          MailProblemCode.unavailable,
        );
        expect(elapsed.elapsed, lessThan(const Duration(seconds: 2)));
        await peer.closed.future.timeout(const Duration(seconds: 1));
        expect(
          peer.commands.any((entry) => entry.$2.startsWith('LOGIN ')),
          isFalse,
        );
      },
    );

    test(
      '${mode.name}: trusted local TLS authenticates and exchanges IMAP bytes',
      () async {
        final server = await LocalTlsServer.bind(mode: mode);
        addTearDown(server.close);
        final clients = <imap.ImapClient>[];
        final result = await _provider(
          server,
          clients: clients,
        ).listMailboxes(_lease());
        expect(
          (result as MailSuccess<List<MailMailbox>>).value.single.id.value,
          'INBOX',
        );
        final peer = await server.peer(0);
        expect(peer.secure, isTrue);
        expect(clients.single.connectionInfo.isSecure, isTrue);
        final logins = peer.commands.where(
          (entry) => entry.$2.startsWith('LOGIN '),
        );
        expect(logins, hasLength(1));
        expect(logins.single.$1, isTrue);
        expect(peer.unexpectedErrors, isEmpty);
        expect(
          peer.commands.any((entry) => entry.$2.startsWith('LIST ')),
          isTrue,
        );
        await peer.closed.future.timeout(const Duration(seconds: 1));
      },
    );

    test(
      '${mode.name}: default trust rejects the local certificate before login',
      () async {
        final server = await LocalTlsServer.bind(mode: mode);
        addTearDown(server.close);
        final handshakeFailures = <HandshakeException>[];
        expect(
          await _provider(
            server,
            trustFixture: false,
            handshakeFailures: handshakeFailures,
          ).capabilities(_lease()),
          isA<MailFailure<MailCapabilities>>(),
        );
        expect(handshakeFailures, hasLength(1));
        final reason = handshakeFailures.single.toString();
        expect(reason, contains('CERTIFICATE_VERIFY_FAILED'));
        expect(
          reason.toLowerCase(),
          matches(RegExp('self[- ]signed|unable to get local issuer')),
        );
        final peer = await server.peer(0);
        expect(peer.unexpectedErrors, isEmpty);
        expect(
          peer.commands.any((entry) => entry.$2.startsWith('LOGIN ')),
          isFalse,
        );
      },
    );

    test(
      '${mode.name}: trusted certificate still rejects a mismatched hostname',
      () async {
        final server = await LocalTlsServer.bind(mode: mode);
        addTearDown(server.close);
        final handshakeFailures = <HandshakeException>[];
        expect(
          await _provider(
            server,
            host: 'localhost',
            handshakeFailures: handshakeFailures,
          ).capabilities(_lease()),
          isA<MailFailure<MailCapabilities>>(),
        );
        expect(handshakeFailures, hasLength(1));
        final reason = handshakeFailures.single.toString();
        expect(reason, contains('CERTIFICATE_VERIFY_FAILED'));
        expect(reason.toLowerCase(), contains('hostname mismatch'));
        final peer = await server.peer(0);
        expect(peer.unexpectedErrors, isEmpty);
        expect(
          peer.commands.any((entry) => entry.$2.startsWith('LOGIN ')),
          isFalse,
        );
      },
    );
  }

  test(
    'manual socket TLS upgrade preserves trust and secure connection metadata',
    () async {
      final server = await LocalTlsServer.bind(mode: MailTlsMode.startTls);
      addTearDown(server.close);
      final socket = await Socket.connect('127.0.0.1', server.port);
      final client = _ManualImapClient(securityContext: localTlsTrustContext())
        ..connect(
          socket,
          connectionInformation: ConnectionInfo(
            '127.0.0.1',
            server.port,
            isSecure: false,
          ),
        );
      addTearDown(client.abort);
      await client.greeting.future.timeout(const Duration(seconds: 1));
      expect(client.connectionInfo.isSecure, isFalse);
      await client.capability();
      await client.startTls().timeout(const Duration(seconds: 2));
      expect(client.connectionInfo.isSecure, isTrue);
      await client.login('manual-reader', 'test-only-password');
      await client.noop();
      final peer = await server.peer(0);
      final logins = peer.commands.where(
        (entry) => entry.$2.startsWith('LOGIN '),
      );
      expect(logins, hasLength(1));
      expect(logins.single.$1, isTrue);
      expect(
        peer.commands.any((entry) => entry.$1 && entry.$2 == 'NOOP'),
        isTrue,
      );
      expect(peer.unexpectedErrors, isEmpty);
    },
  );

  test(
    'already secure manual sockets retain IMAP read and write behavior',
    () async {
      final server = await LocalTlsServer.bind(mode: MailTlsMode.implicitTls);
      addTearDown(server.close);
      final socket = await SecureSocket.connect(
        '127.0.0.1',
        server.port,
        context: localTlsTrustContext(),
      );
      final client = _ManualImapClient()
        ..connect(
          socket,
          connectionInformation: ConnectionInfo(
            '127.0.0.1',
            server.port,
            isSecure: true,
          ),
        );
      addTearDown(client.abort);
      await client.greeting.future.timeout(const Duration(seconds: 1));
      await client.login('manual-reader', 'test-only-password');
      await client.noop();
      final peer = await server.peer(0);
      expect(
        peer.commands.any((entry) => entry.$1 && entry.$2 == 'NOOP'),
        isTrue,
      );
    },
  );

  test(
    'queued partial writes and final readiness complete before write close',
    () async {
      final raw = _PartialRawSocket();
      final connection = createOwnedRawSocket(raw);
      addTearDown(connection.destroy);
      connection.write('first:');
      connection.add(List<int>.generate(16384, (index) => index % 256));
      connection.write(':last');
      final closing = connection.close();
      expect(() => connection.write('too late'), throwsStateError);
      expect(identical(closing, connection.close()), isTrue);
      await closing;
      expect(() => connection.add([1]), throwsStateError);
      expect(raw.bytes, [
        ...utf8.encode('first:'),
        ...List<int>.generate(16384, (index) => index % 256),
        ...utf8.encode(':last'),
      ]);
      expect(raw.writes, greaterThan(1000));
      expect(raw.readinessEvents, raw.writes);
      expect(raw.closedBeforeReady, isFalse);
      expect(raw.writeClosed, isTrue);
    },
  );

  test('aborting a blocked partial write rejects its pending flush', () async {
    final raw = _PartialRawSocket()..releaseReadiness = false;
    final connection = createOwnedRawSocket(raw);
    connection.add(List<int>.filled(100, 42));
    final flushed = expectLater(
      connection.flush(),
      throwsA(isA<SocketException>()),
    );
    await raw.firstWrite.future;
    connection.destroy();
    await flushed.timeout(const Duration(seconds: 1));
    expect(raw.destroyed, isTrue);
  });

  test('hard abort closes retained TCP before a stalled secure close', () {
    final closed = <String>[];
    final transport = _CloseProbeRawSocket('tcp', closed);
    final secure = _CloseProbeRawSocket('tls', closed, stallClose: true);
    final connection = createOwnedRawSocket(secure, transport: transport);
    addTearDown(() {
      secure.releaseClose();
      transport.dispose();
      secure.dispose();
    });

    connection.destroy();
    // No peer drain, timer, or asynchronous secure-close completion is needed
    // before the original TCP owner receives its hard-close request.
    expect(closed, ['tcp', 'tls']);
    expect(secure.closeFinished, isFalse);
    connection.destroy();
    expect(closed, ['tcp', 'tls']);
  });
}

/// Observes the original SDK validation failure without changing TLS behavior.
final class _ObservedImapClient extends imap.ImapClient {
  _ObservedImapClient({
    required this.handshakeFailures,
    super.securityContext,
    super.defaultResponseTimeout,
    super.defaultWriteTimeout,
    super.maxLiteralSize,
    super.maxResponseBytes,
    super.maxProtocolLineBytes,
  });

  final List<HandshakeException> handshakeFailures;

  Future<Socket> _observe(Future<Socket> Function() connect) async {
    try {
      return await connect();
    } on HandshakeException catch (error) {
      handshakeFailures.add(error);
      rethrow;
    }
  }

  @override
  Future<Socket> createConnectionSocket(
    String host,
    int port, {
    required bool isSecure,
  }) => _observe(
    () => super.createConnectionSocket(host, port, isSecure: isSecure),
  );

  @override
  Future<Socket> createSecureConnectionSocket(
    Socket socket, {
    required String host,
  }) => _observe(() => super.createSecureConnectionSocket(socket, host: host));
}

final class _ManualImapClient extends imap.ImapClient {
  _ManualImapClient({super.securityContext});

  final Completer<void> greeting = Completer<void>();

  @override
  Future<void> onConnectionEstablished(
    ConnectionInfo connectionInfo,
    String serverGreeting,
  ) async {
    await super.onConnectionEstablished(connectionInfo, serverGreeting);
    greeting.complete();
  }
}

/// Separates the TCP hard-close request from a secure wrapper whose close
/// cannot finish until pending encrypted output drains.
final class _CloseProbeRawSocket extends Stream<RawSocketEvent>
    implements RawSocket {
  _CloseProbeRawSocket(this.name, this.closed, {this.stallClose = false});

  final String name;
  final List<String> closed;
  final bool stallClose;
  final _events = StreamController<RawSocketEvent>();
  final _close = Completer<RawSocket>();

  bool get closeFinished => _close.isCompleted;

  @override
  bool readEventsEnabled = false;
  @override
  bool writeEventsEnabled = false;

  @override
  Future<RawSocket> close() {
    closed.add(name);
    if (!stallClose) releaseClose();
    return _close.future;
  }

  void releaseClose() {
    if (!_close.isCompleted) _close.complete(this);
  }

  void dispose() {
    unawaited(_events.close());
  }

  @override
  StreamSubscription<RawSocketEvent> listen(
    void Function(RawSocketEvent)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _events.stream.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Not used by the distinct-owner close fixture');
}

/// A bounded writer that accepts three bytes per event, including an asynchronous
/// final write. It exercises ordering independently from OS buffer availability.
final class _PartialRawSocket extends Stream<RawSocketEvent>
    implements RawSocket {
  final _events = StreamController<RawSocketEvent>();
  final List<int> bytes = [];
  final Completer<void> firstWrite = Completer<void>();
  int writes = 0;
  int readinessEvents = 0;
  bool releaseReadiness = true;
  bool writeClosed = false;
  bool closedBeforeReady = false;
  bool destroyed = false;
  bool _pendingWrite = false;

  @override
  bool readEventsEnabled = false;
  @override
  bool get writeEventsEnabled => false;
  @override
  set writeEventsEnabled(bool value) {
    if (value && releaseReadiness) {
      scheduleMicrotask(() {
        if (!destroyed) {
          _pendingWrite = false;
          readinessEvents++;
          _events.add(RawSocketEvent.write);
        }
      });
    }
  }

  @override
  int write(List<int> buffer, [int offset = 0, int? count]) {
    writes++;
    _pendingWrite = true;
    final available = count ?? buffer.length - offset;
    final length = available < 3 ? available : 3;
    bytes.addAll(buffer.sublist(offset, offset + length));
    if (!firstWrite.isCompleted) firstWrite.complete();
    return length;
  }

  @override
  Uint8List? read([int? length]) => null;
  @override
  void shutdown(SocketDirection direction) {
    if (direction == SocketDirection.send ||
        direction == SocketDirection.both) {
      writeClosed = true;
      closedBeforeReady = _pendingWrite;
    }
  }

  @override
  Future<RawSocket> close() async {
    destroyed = true;
    await _events.close();
    return this;
  }

  @override
  StreamSubscription<RawSocketEvent> listen(
    void Function(RawSocketEvent)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _events.stream.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Not used by the partial-write fixture');
}
