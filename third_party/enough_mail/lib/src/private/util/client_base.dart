import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

part 'cancellable_socket.dart';

/// Provides connection information
class ConnectionInfo {
  /// Creates a new connection info
  const ConnectionInfo(this.host, this.port, {required this.isSecure});

  /// The host
  final String host;

  /// The port
  final int port;

  /// `true` when a secure socket is used
  final bool isSecure;
}

/// Base class for socket-based clients
abstract class ClientBase {
  /// Creates a new base client
  ///
  /// Set [isLogEnabled] to `true` to see log output.
  ///
  /// Set the [logName] for adding the name to each log entry.
  ///
  /// [onBadCertificate] is an optional handler for unverifiable certificates.
  /// The handler receives the [X509Certificate], and can inspect it and decide
  /// (or let the user decide) whether to accept the connection or not.
  /// The handler should return true to continue the [SecureSocket] connection.
  ///
  /// [securityContext] is an optional security context for mTLS
  /// (mutual TLS / client certificate authentication).
  /// Create a [SecurityContext] with `useCertificateChain()` and
  /// `usePrivateKey()` to enable client certificate authentication.
  ClientBase({
    this.isLogEnabled = false,
    this.logName,
    this.onBadCertificate,
    this.securityContext,
  });

  /// Initial for a client log output
  static const String initialClient = 'C';

  /// Initial for a server log output
  static const String initialServer = 'S';

  /// Initial for an app log output
  static const String initialApp = 'A';

  /// The name shown in log entries to differentiate this server
  String? logName;

  /// `true` when the log is enabled
  bool isLogEnabled;

  late Socket _socket;
  bool _hasSocket = false;
  int _connectionGeneration = 0;
  Completer<void> _connectionAborted = Completer<void>();
  ConnectionTask<RawSocket>? _pendingConnection;
  RawSocket? _pendingRawSocket;

  /// `true` when it is expected that the socket is closed
  bool isSocketClosingExpected = false;

  /// `true` after the user has authenticated
  bool isLoggedIn = false;

  bool _isServerGreetingDone = false;
  final BytesBuilder _greetingBytes = BytesBuilder(copy: false);

  /// IMAP greetings end at one CRLF even when TCP fragments or coalesces data.
  bool get requiresSingleLineGreeting => false;

  /// An optional greeting bound for clients with explicit resource budgets.
  int? get maxGreetingBytes => null;

  /// Latched input-budget failure; not an authentication or retryable failure.
  bool responseLimitExceeded = false;

  /// Information about the connection
  late ConnectionInfo connectionInfo;
  Completer<ConnectionInfo>? _greetingsCompleter;

  bool _isConnected = false;

  /// Ist the client currently connected?
  bool get isConnected => _isConnected;

  /// Handles unverifiable certificates.
  ///
  /// The handler receives the [X509Certificate], and can inspect it and decide
  /// (or let the user decide) whether to accept the connection or not.
  /// The handler should return true to continue the [SecureSocket] connection.
  final bool Function(X509Certificate)? onBadCertificate;

  /// Optional [SecurityContext] for mTLS (mutual TLS).
  ///
  /// When set, it is passed to the TLS handshake to enable client certificate
  /// authentication while preserving the requested hostname verification.
  final SecurityContext? securityContext;

  /// Is called when data is received
  void onDataReceived(Uint8List data);

  /// Is called after the initial connection has been established
  FutureOr<void> onConnectionEstablished(
    ConnectionInfo connectionInfo,
    String serverGreeting,
  );

  /// Is called when the connection encountered an error
  void onConnectionError(dynamic error);

  late StreamSubscription _socketStreamSubscription;

  /// Opens a socket using the configured TLS trust policy. Protocol test
  /// harnesses may override this boundary without binding a network listener.
  Future<Socket> createConnectionSocket(
    String host,
    int port, {
    required bool isSecure,
  }) async {
    final generation = _connectionGeneration;
    final task = await RawSocket.startConnect(host, port);
    if (generation != _connectionGeneration) {
      task.cancel();
    } else {
      _pendingConnection = task;
    }
    RawSocket? raw;
    try {
      raw = await task.socket;
      if (generation != _connectionGeneration) {
        throw createClientError('connection attempt was abandoned');
      }
      _pendingRawSocket = raw;
      final connected = isSecure
          ? await RawSecureSocket.secure(
              raw,
              host: host,
              onBadCertificate: onBadCertificate,
              context: securityContext,
            )
          : raw;
      if (generation != _connectionGeneration) {
        unawaited(connected.close());
        throw createClientError('connection attempt was abandoned');
      }
      return createOwnedRawSocket(connected, transport: raw);
    } catch (_) {
      if (raw != null) {
        unawaited(raw.close());
      }
      rethrow;
    } finally {
      if (identical(_pendingConnection, task)) {
        _pendingConnection = null;
      }
      if (identical(_pendingRawSocket, raw)) {
        _pendingRawSocket = null;
      }
    }
  }

  // SecureSocket.secure detaches the original Socket before its TLS future
  // resolves. Retaining the public RawSocket owner lets abort close a stalled
  // handshake, including one that has not produced a secure socket yet.
  void _cancelPendingConnection() {
    final task = _pendingConnection;
    final raw = _pendingRawSocket;
    _pendingConnection = null;
    _pendingRawSocket = null;
    task?.cancel();
    if (raw != null) {
      unawaited(raw.close());
    }
  }

  void _signalAbort() {
    if (!_connectionAborted.isCompleted) {
      _connectionAborted.complete();
    }
  }

  int _beginConnectionAttempt() {
    _cancelPendingConnection();
    _signalAbort();
    _connectionAborted = Completer<void>();
    return ++_connectionGeneration;
  }

  Future<T> _untilAborted<T>(
    Future<T> pending,
    Completer<void> aborted,
    String reason,
  ) => Future.any([
    pending,
    aborted.future.then<T>((_) => throw createClientError(reason)),
  ]);

  /// Connects to the specified server.
  ///
  /// Specify [isSecure] if you do not want to connect to a secure service.
  ///
  /// Specify [timeout] to specify a different timeout for the connection.
  /// This defaults to 20 seconds.
  Future<ConnectionInfo> connectToServer(
    String host,
    int port, {
    bool isSecure = true,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    logApp(
      'connecting to server $host:$port - '
      'secure: $isSecure, timeout: $timeout',
    );
    connectionInfo = ConnectionInfo(host, port, isSecure: isSecure);
    final generation = _beginConnectionAttempt();
    final aborted = _connectionAborted;
    final opening = createConnectionSocket(host, port, isSecure: isSecure);
    // Observe the original future after cancellation too, so a late socket is
    // destroyed even when the caller has already received the abort error.
    final guarded = opening.then((socket) {
      if (generation != _connectionGeneration) {
        socket.destroy();
        throw createClientError('connection attempt was abandoned');
      }
      return socket;
    });
    final socket =
        await _untilAborted(
          guarded,
          aborted,
          'connection attempt was abandoned',
        ).timeout(
          timeout,
          onTimeout: () {
            if (generation == _connectionGeneration) {
              _connectionGeneration++;
              _cancelPendingConnection();
              _signalAbort();
            }
            throw createClientError('connection attempt timed out');
          },
        );
    if (generation != _connectionGeneration) {
      socket.destroy();
      throw createClientError('connection attempt was abandoned');
    }
    final greetingsCompleter = Completer<ConnectionInfo>();
    _greetingsCompleter = greetingsCompleter;
    _isServerGreetingDone = false;
    _greetingBytes.clear();
    connect(socket);

    // the server greeting has to arrive within the timeout as well,
    // otherwise e.g. a TLS port contacted without TLS would hang forever
    return greetingsCompleter.future.timeout(
      timeout,
      onTimeout: () {
        isSocketClosingExpected = true;
        _isConnected = false;
        socket.destroy();
        throw createClientError(
          'no server greeting received from $host:$port within $timeout',
        );
      },
    );
  }

  /// Fails a pending [connectToServer] call when the connection ends before
  /// the server greeting was received.
  void _failGreeting(String reason) {
    final completer = _greetingsCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.completeError(createClientError(reason));
    }
  }

  /// Starts to listen on the given [socket].
  ///
  /// This is mainly useful for testing purposes, ensure to set
  /// [connectionInformation] manually in this  case, e.g.
  /// ```dart
  /// await client.connect(socket, connectionInformation:
  /// ConnectionInfo(host, port, isSecure));
  /// ```
  void connect(Socket socket, {ConnectionInfo? connectionInformation}) {
    if (connectionInformation != null) {
      _beginConnectionAttempt();
      // used for manually created sockets, e.g. in tests: nobody awaits the
      // greeting, so there must be no completer that could fail unhandled
      connectionInfo = connectionInformation;
      _greetingsCompleter = null;
      _isServerGreetingDone = false;
      _greetingBytes.clear();
    }
    _socket = socket;
    _hasSocket = true;
    _writeFuture = null;
    // if (connectionTimeout != null) {
    //   final timeoutStream = socket.timeout(connectionTimeout!);
    //   _socketStreamSubscription = timeoutStream.listen(
    //     _onDataReceived,
    //     onDone: onConnectionDone,
    //     onError: _onConnectionError,
    //   );
    // } else {
    _socketStreamSubscription = socket.listen(
      _onDataReceived,
      onDone: onConnectionDone,
      onError: _onConnectionError,
    );
    // }
    _isConnected = true;
    isSocketClosingExpected = false;
  }

  Future<void> _onConnectionError(Object e, StackTrace s) async {
    logApp('Socket error: $e $s');
    isLoggedIn = false;
    _isConnected = false;
    _writeFuture = null;
    _failGreeting('connection error before server greeting: $e');
    if (!isSocketClosingExpected) {
      isSocketClosingExpected = true;
      try {
        await _socketStreamSubscription.cancel();
      } catch (e, s) {
        logApp('Unable to cancel stream subscription: $e $s');
      }
      try {
        onConnectionError(e);
      } catch (e, s) {
        logApp('Unable to call onConnectionError: $e, $s');
      }
    }
  }

  /// Creates a TLS socket using the requested hostname and trust policy.
  /// Protocol fixtures may override this seam; production never bypasses trust.
  Future<Socket> createSecureConnectionSocket(
    Socket socket, {
    required String host,
  }) async {
    if (socket is! _CancellableSocket) {
      // Caller-supplied socket factories retain their existing upgrade seam.
      // Only the default owned raw transport can cancel before TLS resolves.
      return SecureSocket.secure(
        socket,
        host: host,
        context: securityContext,
        onBadCertificate: onBadCertificate,
      );
    }
    final raw = socket.rawSocket;
    _pendingRawSocket = raw;
    try {
      return await socket.secure(
        host: host,
        context: securityContext,
        onBadCertificate: onBadCertificate,
      );
    } finally {
      if (identical(_pendingRawSocket, raw)) {
        _pendingRawSocket = null;
      }
    }
  }

  /// Upgrades the current connection without reviving an aborted generation.
  Future<void> upgradeToSslSocket() async {
    final generation = _connectionGeneration;
    final aborted = _connectionAborted;
    final originalSocket = _socket;
    final originalSubscription = _socketStreamSubscription..pause();
    try {
      final upgrading =
          createSecureConnectionSocket(
            originalSocket,
            host: connectionInfo.host,
          ).then((socket) {
            if (generation != _connectionGeneration) {
              socket.destroy();
              throw createClientError('TLS upgrade was abandoned');
            }
            return socket;
          });
      // Closing the TCP owner can end the SDK stream without settling its TLS
      // handshake future. Resolve the abandoned operation independently of it.
      final secureSocket = await _untilAborted(
        upgrading,
        aborted,
        'TLS upgrade was abandoned',
      );
      if (generation != _connectionGeneration) {
        secureSocket.destroy();
        throw createClientError('TLS upgrade was abandoned');
      }
      await originalSubscription.cancel();
      if (generation != _connectionGeneration) {
        secureSocket.destroy();
        throw createClientError('TLS upgrade was abandoned');
      }
      isSocketClosingExpected = true;
      originalSocket.destroy();
      isSocketClosingExpected = false;
      connectionInfo = ConnectionInfo(
        connectionInfo.host,
        connectionInfo.port,
        isSecure: true,
      );
      connect(secureSocket);
    } on Object {
      if (generation == _connectionGeneration) {
        await abort();
      }
      rethrow;
    }
  }

  Future<void> _onDataReceived(Uint8List data) async {
    if (_isServerGreetingDone) {
      onDataReceived(data);
      return;
    }
    var greeting = data;
    Uint8List? remaining;
    if (requiresSingleLineGreeting) {
      _greetingBytes.add(data);
      final bytes = _greetingBytes.toBytes();
      var lineEnd = -1;
      for (var index = 1; index < bytes.length; index++) {
        if (bytes[index - 1] == 13 && bytes[index] == 10) {
          lineEnd = index + 1;
          break;
        }
      }
      final maximum = maxGreetingBytes;
      if (maximum != null && (lineEnd < 0 ? bytes.length : lineEnd) > maximum) {
        _greetingBytes.clear();
        responseLimitExceeded = true;
        _failGreeting('server greeting limit exceeded');
        await abort();
        return;
      }
      if (lineEnd < 0) {
        return;
      }
      greeting = Uint8List.sublistView(bytes, 0, lineEnd);
      if (lineEnd < bytes.length) {
        remaining = Uint8List.sublistView(bytes, lineEnd);
      }
      _greetingBytes.clear();
    }
    _isServerGreetingDone = true;
    final serverGreeting = String.fromCharCodes(greeting);
    log(serverGreeting, isClient: false);
    try {
      await onConnectionEstablished(connectionInfo, serverGreeting);
      final completer = _greetingsCompleter;
      if (completer != null && !completer.isCompleted) {
        completer.complete(connectionInfo);
      }
      if (remaining != null) {
        onDataReceived(remaining);
      }
    } catch (error, stack) {
      await _onConnectionError(error, stack);
    }
  }

  /// Informs about a closed connection
  void onConnectionDone() {
    logApp('Done, connection closed');
    isLoggedIn = false;
    _isConnected = false;
    _failGreeting('connection closed before server greeting');
    if (!isSocketClosingExpected) {
      isSocketClosingExpected = true;
      onConnectionError('onDone not expected');
    }
  }

  /// Aborts pending connection attempts and destroys any established socket.
  /// Late connect completions are discarded by their generation guard.
  Future<void> abort() async {
    _connectionGeneration++;
    _cancelPendingConnection();
    _signalAbort();
    _failGreeting('connection aborted');
    _greetingBytes.clear();
    isLoggedIn = false;
    _isConnected = false;
    isSocketClosingExpected = true;
    if (_hasSocket) {
      _hasSocket = false;
      _socket.destroy();
      await _socketStreamSubscription.cancel();
    }
  }

  /// Disconnects from the service
  Future<void> disconnect() async {
    if (_pendingConnection != null || _pendingRawSocket != null) {
      await abort();
      return;
    }
    if (_isConnected) {
      isLoggedIn = false;
      _isConnected = false;
      isSocketClosingExpected = true;
      try {
        await _socketStreamSubscription.cancel();
      } catch (e) {
        print('unable to cancel subscription $e');
      }
      try {
        await _socket.close();
      } catch (e) {
        print('unable to close socket $e');
      }
    }
  }

  Future? _writeFuture;

  /// Writes the specified [text].
  ///
  /// When the log is enabled it will either log the specified [logObject]
  /// or just the [text].
  ///
  /// When a [timeout] is specified and occurs, it will
  /// throw a [TimeoutException] after the specified time.
  Future writeText(String text, [dynamic logObject, Duration? timeout]) async {
    final previousWriteFuture = _writeFuture;
    if (previousWriteFuture != null) {
      try {
        await previousWriteFuture;
      } catch (e, s) {
        print(
          'Unable to await previous write '
          // ignore: unawaited_futures
          'future $previousWriteFuture: $e $s',
        );
        _writeFuture = null;
        rethrow;
      }
    }
    if (isLogEnabled) {
      logObject ??= text;
      log(logObject);
    }
    _socket.write('$text\r\n');

    final future = timeout == null
        ? _socket.flush()
        : _socket.flush().timeout(timeout);
    _writeFuture = future;
    await future;
    _writeFuture = null;
  }

  /// Writes the specified [data].
  ///
  /// When the log is enabled it will either log the specified
  /// [logObject] or just the length of the data.
  Future writeData(List<int> data, [dynamic logObject]) async {
    final previousWriteFuture = _writeFuture;
    if (previousWriteFuture != null) {
      try {
        await previousWriteFuture;
      } catch (e, s) {
        print('Unable to await previous write future: $e $s');
        _writeFuture = null;
      }
    }
    if (isLogEnabled) {
      logObject ??= '<${data.length} bytes>';
      log(logObject);
    }
    _socket.add(data);
    final future = _socket.flush();
    _writeFuture = future;
    await future;
    _writeFuture = null;
  }

  /// Writes to the socket via [write] and fails the [completer] with a
  /// client error when the write fails, instead of leaving the completer
  /// pending with an unhandled asynchronous error.
  ///
  /// [onWriteError] is called before the completer is failed, e.g. to forget
  /// the command that the completer belongs to.
  void writeOrFail(
    Future<void> Function() write,
    Completer<dynamic> completer, {
    void Function()? onWriteError,
  }) {
    unawaited(
      write().catchError((Object e, StackTrace s) {
        onWriteError?.call();
        if (!completer.isCompleted) {
          completer.completeError(
            createClientError('unable to send command: $e'),
            s,
          );
        }
      }),
    );
  }

  /// Logs the data from the app-side
  void logApp(dynamic logObject) => log(logObject, initial: initialApp);

  /// Logs the data from the client-side
  void logClient(dynamic logObject) => log(logObject, initial: initialClient);

  /// Logs the data from the server-side
  void logServer(dynamic logObject) => log(logObject, initial: initialServer);

  /// Logs the data
  void log(dynamic logObject, {bool isClient = true, String? initial}) {
    if (isLogEnabled) {
      initial ??= isClient ? initialClient : initialServer;
      if (logName != null) {
        print('$logName $initial: $logObject');
      } else {
        print('$initial: $logObject');
      }
    }
  }

  void _onTimeout(Completer completer, Duration duration) {
    // print(
    //     '$completer triggers timeout after $duration on
    //      $this at ${DateTime.now()}');
    completer.completeError(createClientError('timeout'));
  }

  /// Subclasses need to be able to create client specific exceptions
  Exception createClientError(String message);
}

/// Extends Completer instances
extension ExtensionCompleter on Completer {
  /// Adds a timeout to a completer
  void timeout(Duration? duration, ClientBase client) {
    if (duration != null) {
      Future.delayed(duration).then((value) {
        if (!isCompleted) {
          client._onTimeout(this, duration);
        }
      });
    }
  }
}

// class _QueuedText {
//   final String text;
//   final dynamic logObject;
//   _QueuedText(this.text, this.logObject);
// }
