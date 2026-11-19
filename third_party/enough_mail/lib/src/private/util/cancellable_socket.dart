// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

part of 'client_base.dart';

/// Adapts public raw sockets without hiding the owner during a TLS handshake.
/// The raw subscription stays unpaused: STARTTLS transfers it to the SDK, which
/// takes over its handlers. Pausing protocol input only disables raw reads.
final class _CancellableSocket extends Stream<Uint8List> implements Socket {
  _CancellableSocket(RawSocket raw) : _raw = raw {
    raw
      ..readEventsEnabled = false
      ..writeEventsEnabled = false;
    _input
      ..onListen = _updateReadEvents
      ..onPause = _updateReadEvents
      ..onResume = _updateReadEvents
      ..onCancel = _cancelInput;
    _consumer = _RawSocketConsumer(this);
    _sink = IOSink(_consumer);
    // Write/flush callers still receive errors. Observe the separate sink-done
    // future too: abort can close a socket without a pending write caller.
    _sink.done.ignore();
    _rawSubscription = raw.listen(
      _onRawEvent,
      onError: _onRawError,
      onDone: _onRawDone,
    );
  }

  RawSocket? _raw;
  StreamSubscription<RawSocketEvent>? _rawSubscription;
  final _input = StreamController<Uint8List>(sync: true);
  late final _RawSocketConsumer _consumer;
  late final IOSink _sink;
  Completer<void>? _writeReady;
  bool _inputClosed = false;
  bool _transferring = false;
  Object? _writeError;
  StackTrace? _writeStack;

  RawSocket get rawSocket =>
      _raw ?? (throw const SocketException('Socket is closed'));

  Future<Socket> secure({
    required String host,
    SecurityContext? context,
    bool Function(X509Certificate)? onBadCertificate,
  }) async {
    final raw = rawSocket;
    if (_transferring) {
      throw const SocketException('TLS upgrade is already pending');
    }
    _transferring = true;
    try {
      // Finish all plaintext writes before handing the stream to TLS. The
      // consumer leaves the send direction open while ownership transfers.
      await _sink.close();
      if (!identical(_raw, raw)) {
        throw const SocketException('Socket closed during TLS upgrade');
      }
      final subscription = _rawSubscription;
      _raw = null;
      _rawSubscription = null;
      _closeInput();
      final secure = await RawSecureSocket.secure(
        raw,
        subscription: subscription,
        host: host,
        context: context,
        onBadCertificate: onBadCertificate,
      );
      return _CancellableSocket(secure);
    } catch (_) {
      unawaited(raw.close());
      destroy();
      rethrow;
    }
  }

  void _updateReadEvents() {
    if (!_inputClosed) {
      _raw?.readEventsEnabled = _input.hasListener && !_input.isPaused;
    }
  }

  void _cancelInput() {
    _inputClosed = true;
    if (!_transferring) {
      // Continue draining receive events until shutdown is acknowledged. A
      // disabled reader could otherwise leave a half-closed raw socket alive.
      _raw
        ?..readEventsEnabled = true
        ..shutdown(SocketDirection.receive);
    }
  }

  void _closeInput() {
    if (!_inputClosed) {
      _inputClosed = true;
      unawaited(_input.close());
    }
  }

  void _onRawEvent(RawSocketEvent event) {
    if (event == RawSocketEvent.read) {
      final bytes = _raw?.read();
      if (bytes != null && !_inputClosed) {
        _input.add(bytes);
      }
    } else if (event == RawSocketEvent.write) {
      final ready = _writeReady;
      _writeReady = null;
      ready?.complete();
    } else if (event == RawSocketEvent.readClosed) {
      _closeInput();
    }
  }

  void _onRawError(Object error, StackTrace stack) {
    if (!_inputClosed) {
      _input.addError(error, stack);
    }
    _endWrites(error, stack);
    destroy();
  }

  void _onRawDone() {
    _raw = null;
    _rawSubscription = null;
    _endWrites(const SocketException('Socket is closed'));
    _closeInput();
  }

  void _endWrites(Object error, [StackTrace? stack]) {
    _writeError ??= error;
    _writeStack ??= stack;
    final ready = _writeReady;
    _writeReady = null;
    ready?.completeError(error, stack);
    _consumer.stop();
  }

  void _checkWrites() {
    final error = _writeError;
    if (error != null) {
      Error.throwWithStackTrace(error, _writeStack ?? StackTrace.current);
    }
  }

  Future<void> _writeBytes(List<int> bytes) async {
    var offset = 0;
    while (offset < bytes.length) {
      _checkWrites();
      final raw = rawSocket;
      offset += raw.write(bytes, offset, bytes.length - offset);
      // Wait for writable readiness even after the final accepted chunk. This
      // keeps flush/close ordered behind pending native writes on all platforms.
      final ready = Completer<void>();
      _writeReady = ready;
      raw.writeEventsEnabled = true;
      await ready.future;
    }
  }

  void _closeWrites() {
    if (!_transferring) {
      _raw?.shutdown(SocketDirection.send);
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

  @override
  Encoding get encoding => _sink.encoding;
  @override
  set encoding(Encoding value) => _sink.encoding = value;
  @override
  void write(Object? object) => _sink.write(object);
  @override
  void writeln([Object? object = '']) => _sink.writeln(object);
  @override
  void writeCharCode(int charCode) => _sink.writeCharCode(charCode);
  @override
  void writeAll(Iterable<dynamic> objects, [String separator = '']) =>
      _sink.writeAll(objects, separator);
  @override
  void add(List<int> bytes) => _sink.add(bytes);
  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      throw UnsupportedError('Cannot send errors on sockets');
  @override
  Future<void> addStream(Stream<List<int>> stream) => _sink.addStream(stream);
  @override
  Future<void> flush() => _sink.flush();
  @override
  Future<void> close() => _sink.close();
  @override
  Future<void> get done => _sink.done;

  @override
  void destroy() {
    final raw = _raw;
    if (raw == null) {
      return;
    }
    _raw = null;
    _endWrites(const SocketException('Socket is closed'));
    unawaited(raw.close());
    unawaited(_rawSubscription?.cancel());
    _rawSubscription = null;
    _closeInput();
  }

  @override
  bool setOption(SocketOption option, bool enabled) =>
      rawSocket.setOption(option, enabled);
  @override
  Uint8List getRawOption(RawSocketOption option) =>
      rawSocket.getRawOption(option);
  @override
  void setRawOption(RawSocketOption option) => rawSocket.setRawOption(option);
  @override
  int get port => rawSocket.port;
  @override
  int get remotePort => rawSocket.remotePort;
  @override
  InternetAddress get address => rawSocket.address;
  @override
  InternetAddress get remoteAddress => rawSocket.remoteAddress;

  // Socket has an SDK-private detach member. This facade uses secure() above,
  // never that private SDK entry point; all public Socket members are provided.
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _RawSocketConsumer implements StreamConsumer<List<int>> {
  _RawSocketConsumer(this.socket);

  final _CancellableSocket socket;
  StreamIterator<List<int>>? _iterator;

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    final iterator = StreamIterator(stream);
    _iterator = iterator;
    try {
      while (await iterator.moveNext()) {
        await socket._writeBytes(iterator.current);
      }
      socket._checkWrites();
    } finally {
      _iterator = null;
      await iterator.cancel();
    }
  }

  void stop() {
    final iterator = _iterator;
    if (iterator != null) {
      unawaited(iterator.cancel());
    }
  }

  @override
  Future<void> close() async => socket._closeWrites();
}
