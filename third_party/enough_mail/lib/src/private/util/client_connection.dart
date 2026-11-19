// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// The byte-stream operations used by the protocol clients.
///
/// This deliberately does not implement the SDK's private Socket handoff API.
abstract class ClientConnection extends Stream<Uint8List> {
  /// Queues bytes for transmission.
  void add(List<int> data);

  /// Queues UTF-8 text for transmission.
  void write(String text);

  /// Sends a stream in order and cancels its producer if transport is aborted.
  Future<void> addStream(Stream<List<int>> stream);

  /// Completes when queued bytes have been accepted by the socket.
  Future<void> flush();

  /// Closes the write direction after queued bytes have been accepted.
  Future<void> close();

  /// Immediately closes the owned transport, including pending TLS work.
  void destroy();
}

/// Adapts an externally supplied socket for the manual/test connection path.
///
/// TLS upgrades use [RawClientConnection], whose TCP owner remains accessible.
class SocketClientConnection extends ClientConnection {
  /// Wraps [socket] without changing its byte-stream behavior.
  SocketClientConnection(this.socket);

  /// The externally supplied socket.
  final Socket socket;

  @override
  void add(List<int> data) => socket.add(data);
  @override
  void write(String text) => socket.write(text);
  @override
  Future<void> addStream(Stream<List<int>> stream) => socket.addStream(stream);
  @override
  Future<void> flush() async => socket.flush();
  @override
  Future<void> close() async => socket.close();
  @override
  void destroy() => socket.destroy();

  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => socket.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
}

/// Owns the TCP socket across a TLS handshake and its replacement stream.
///
/// [SecureSocket.secure] detaches its input Socket before its future completes.
/// Keeping the TCP [RawSocket] instead allows an abort to close a stalled
/// handshake and an established TLS connection without waiting for TLS output.
class RawClientConnection extends ClientConnection {
  /// Wraps [socket], retaining [transport] for hard abort.
  RawClientConnection(RawSocket socket, {RawSocket? transport})
    : _socket = socket,
      _transport = transport ?? socket {
    _input = StreamController<Uint8List>(
      sync: true,
      onListen: _resumeReads,
      onPause: _pauseReads,
      onResume: _resumeReads,
      onCancel: _cancelReads,
    );
    _socket
      ..readEventsEnabled = false
      ..writeEventsEnabled = false;
    _subscription = _socket.listen(
      _onEvent,
      onError: _onError,
      onDone: destroy,
    );
  }

  final RawSocket _socket;
  final RawSocket _transport;
  late final StreamController<Uint8List> _input;
  late final StreamSubscription<RawSocketEvent> _subscription;
  final Completer<void> _aborted = Completer<void>();
  Future<void> _writes = Future<void>.value();
  StreamIterator<List<int>>? _writeStream;
  Future<void>? _closing;
  Completer<void>? _writable;
  bool _closed = false;
  bool _tlsPending = false;
  bool _transferred = false;

  bool get _ownsEvents => !_closed && !_tlsPending && !_transferred;

  void _checkOpen() {
    if (_closed || _transferred) {
      throw const SocketException.closed();
    }
  }

  void _resumeReads() {
    if (_ownsEvents) {
      _socket.readEventsEnabled = true;
    }
  }

  void _pauseReads() {
    if (_ownsEvents) {
      _socket.readEventsEnabled = false;
    }
  }

  void _cancelReads() {
    if (_ownsEvents) {
      _socket.shutdown(SocketDirection.receive);
    }
  }

  void _finishInput() {
    if (!_input.isClosed) {
      unawaited(_input.close());
    }
  }

  void _wakeWriter() {
    final writable = _writable;
    if (writable != null && !writable.isCompleted) {
      writable.complete();
    }
  }

  void _onEvent(RawSocketEvent event) {
    if (!_ownsEvents) {
      return;
    }
    if (event == RawSocketEvent.read) {
      while (_ownsEvents && !_input.isPaused) {
        final bytes = _socket.read(64 * 1024);
        if (bytes == null || bytes.isEmpty) {
          break;
        }
        _input.add(bytes);
      }
    } else if (event == RawSocketEvent.write) {
      _socket.writeEventsEnabled = false;
      _wakeWriter();
    } else if (event == RawSocketEvent.readClosed) {
      _finishInput();
    } else if (event == RawSocketEvent.closed) {
      destroy();
    }
  }

  void _onError(Object error, StackTrace stack) {
    if (!_input.isClosed) {
      _input.addError(error, stack);
    }
    destroy();
  }

  void _checkWritable() {
    _checkOpen();
    if (_closing != null) {
      throw StateError('Connection write direction is closed');
    }
    if (_tlsPending) {
      throw StateError('TLS handoff is in progress');
    }
    if (_writeStream != null) {
      throw StateError('Connection stream write is in progress');
    }
  }

  @override
  void add(List<int> data) {
    _checkWritable();
    _writes = _writes.then((_) => _writeBytes(data));
    // Preserve the failed flush result, while also observing failures if a
    // caller destroys the connection before awaiting that result.
    unawaited(_writes.then<void>((_) {}, onError: (Object _, StackTrace _) {}));
  }

  @override
  Future<void> addStream(Stream<List<int>> stream) {
    _checkWritable();
    final iterator = StreamIterator<List<int>>(stream);
    _writeStream = iterator;
    _writes = _writes
        .then((_) async {
          _checkOpen();
          while (await iterator.moveNext()) {
            _checkOpen();
            await _writeBytes(iterator.current);
          }
          // Cancelling an idle iterator completes moveNext with false. Preserve
          // abort as a failed write rather than mistaking it for producer EOF.
          _checkOpen();
        })
        .whenComplete(() async {
          if (identical(_writeStream, iterator)) {
            _writeStream = null;
          }
          await iterator.cancel();
        });
    unawaited(_writes.then<void>((_) {}, onError: (Object _, StackTrace _) {}));
    return _writes;
  }

  Future<void> _writeBytes(List<int> data) async {
    var offset = 0;
    while (offset < data.length) {
      _checkOpen();
      final written = _socket.write(data, offset);
      offset += written;
      // On some platforms even a full write completes asynchronously. Waiting
      // for readiness also keeps flush/close ordered after that final write.
      final writable = Completer<void>();
      _writable = writable;
      _socket.writeEventsEnabled = true;
      await writable.future;
      _writable = null;
      _checkOpen();
    }
  }

  @override
  void write(String text) => add(utf8.encode(text));

  @override
  Future<void> flush() => _writes;

  @override
  Future<void> close() => _closing ??= _closeWrites();

  Future<void> _closeWrites() async {
    if (_transferred) {
      return;
    }
    await flush();
    if (!_closed) {
      _socket.shutdown(SocketDirection.send);
    }
  }

  static void _closeRaw(RawSocket socket) {
    unawaited(socket.close().then<void>((_) {}, onError: (Object _) {}));
  }

  @override
  void destroy() {
    if (_closed) {
      return;
    }
    _closed = true;
    if (!_aborted.isCompleted) {
      _aborted.complete();
    }
    _wakeWriter();
    final iterator = _writeStream;
    if (iterator != null) {
      // StreamIterator cancellation settles an idle moveNext immediately, even
      // while the producer performs asynchronous cancellation cleanup.
      unawaited(
        iterator.cancel().then<void>(
          (_) {},
          onError: (Object _, StackTrace _) {},
        ),
      );
    }
    if (!_transferred) {
      // Close TCP first: TLS close alone can wait for buffered encrypted data.
      _closeRaw(_transport);
      if (!identical(_socket, _transport)) {
        _closeRaw(_socket);
      }
      // During TLS the SDK owns this subscription and must observe TCP close.
      if (!_tlsPending) {
        unawaited(_subscription.cancel());
      }
    }
    _finishInput();
  }

  /// Performs TLS while retaining an abort handle to the original TCP socket.
  Future<RawClientConnection> secure({
    required String host,
    SecurityContext? context,
    bool Function(X509Certificate)? onBadCertificate,
  }) async {
    await flush();
    _checkOpen();
    if (_closing != null) {
      throw StateError('Connection write direction is closed');
    }
    _tlsPending = true;
    try {
      final handshake =
          RawSecureSocket.secure(
            _socket,
            subscription: _subscription,
            host: host,
            context: context,
            onBadCertificate: onBadCertificate,
          ).then((secured) {
            if (_closed) {
              _closeRaw(secured);
              throw const SocketException.closed();
            }
            return secured;
          });
      final interrupted = _aborted.future.then<RawSecureSocket>(
        (_) => throw const SocketException.closed(),
      );
      final secured = await Future.any([handshake, interrupted]);
      _checkOpen();
      final replacement = RawClientConnection(secured, transport: _transport);
      // The old connection must become inert only after the replacement owns
      // TCP. ClientBase still verifies its account/connection generation.
      _transferred = true;
      _tlsPending = false;
      _finishInput();
      return replacement;
    } on Object {
      destroy();
      rethrow;
    }
  }

  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => _input.stream.listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
}
