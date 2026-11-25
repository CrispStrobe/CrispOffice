import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:quds_mail_core/quds_mail_core.dart';

import '../configuration.dart';
import '../errors.dart';
import 'ntlm.dart';

/// Internal operation-scoped seam; this is not exported by the public library.
abstract interface class EwsHttpClient {
  Future<String> post(String action, String envelope, {bool mutation = false});
  bool get mutationStarted;
  void abort();
}

/// A fresh authenticated HTTPS connection belongs to one provider operation.
///
/// NTLM is negotiated with body-free HEAD requests before any SOAP is sent.
/// Exactly one TCP connection is admitted: reconnects, HTTP redirects and
/// authentication replays cannot duplicate a mailbox command. The host owns
/// the operation lease and closes this client on cancellation or completion.
final class NativeEwsHttpClient implements EwsHttpClient {
  NativeEwsHttpClient({
    required this.configuration,
    required String secret,
    required this.limits,
    HttpClient Function()? clientFactory,
    this.securityContext,
  }) : _secret = secret,
       _client = (clientFactory ?? HttpClient.new)() {
    limits.validate();
    if (secret.isEmpty ||
        secret.length > limits.maxCredentialBytes ||
        utf8.encode(secret).length > limits.maxCredentialBytes ||
        secret.contains(RegExp(r'[\x00-\x1f\x7f]')) ||
        (configuration.authentication == MailEwsAuthentication.bearer &&
            !RegExp(r'^[A-Za-z0-9\-._~+/]+=*$').hasMatch(secret))) {
      _client.close(force: true);
      _secret = null;
      throw const EwsException(MailProblemCode.invalidInput);
    }
    _client
      ..maxConnectionsPerHost = 1
      ..connectionTimeout = limits.operationTimeout
      ..idleTimeout = limits.operationTimeout
      ..autoUncompress = true
      ..badCertificateCallback = null
      ..authenticate = ((_, _, _) async => false)
      ..authenticateProxy = ((_, _, _, _) async => false)
      ..findProxy = ((_) => 'DIRECT')
      ..connectionFactory = _connect;
    _deadline = Timer(limits.operationTimeout, () {
      _stop(const EwsException(MailProblemCode.unavailable));
    });
  }

  final MailEwsConfiguration configuration;
  final MailEwsLimits limits;
  final HttpClient _client;
  // Internal test trust anchor only; the public factory does not expose it.
  final SecurityContext? securityContext;
  String? _secret;
  Timer? _deadline;
  ConnectionTask<Socket>? _connectionTask;
  ConnectionTask<RawSocket>? _tcpTask;
  RawSocket? _rawTransport;
  Completer<Socket>? _pendingSocket;
  Socket? _socket;
  HttpClientRequest? _request;
  (String, int, int)? _ntlmConnection;
  int _connections = 0;
  int _responseBytes = 0;
  bool _busy = false;
  bool _stopped = false;
  bool _mutationStarted = false;
  EwsException _stopReason = const EwsException(MailProblemCode.staleOperation);

  @override
  bool get mutationStarted => _mutationStarted;

  void _check() {
    if (_stopped) throw _stopReason;
  }

  Future<ConnectionTask<Socket>> _connect(
    Uri uri,
    String? proxyHost,
    int? proxyPort,
  ) async {
    _check();
    if (_connections++ != 0 ||
        uri.scheme != 'https' ||
        uri.host != configuration.endpoint.host ||
        uri.port != configuration.endpoint.port ||
        proxyHost != null ||
        proxyPort != null) {
      throw const EwsException(MailProblemCode.unavailable);
    }
    final pending = Completer<Socket>();
    _pendingSocket = pending;
    pending.future.ignore();
    final task = ConnectionTask.fromSocket(pending.future, () {
      _stop(const EwsException(MailProblemCode.unavailable));
    });
    _connectionTask = task;
    unawaited(_establishTls(uri, pending));
    return task;
  }

  Future<void> _establishTls(Uri uri, Completer<Socket> pending) async {
    RawSocket? tcp;
    try {
      final task = await RawSocket.startConnect(uri.host, uri.port);
      _tcpTask = task;
      if (_stopped) task.cancel();
      tcp = await task.socket;
      _rawTransport = tcp;
      _check();
      // Retain the TCP owner while TLS is pending: SecureSocket.startConnect's
      // task alone cannot close a stalled TLS handshake on the pinned Dart SDK.
      final tls = await RawSecureSocket.secure(
        tcp,
        host: uri.host,
        context: securityContext,
        supportedProtocols: const ['http/1.1'],
      );
      if (_stopped) {
        unawaited(tls.close());
        throw _stopReason;
      }
      final socket = _OwnedTlsSocket(tls, tcp);
      _socket = socket;
      if (pending.isCompleted) {
        socket.destroy();
      } else {
        pending.complete(socket);
      }
    } on Object catch (error, stack) {
      if (tcp != null) unawaited(tcp.close());
      if (!pending.isCompleted) pending.completeError(error, stack);
    } finally {
      if (identical(_pendingSocket, pending)) _pendingSocket = null;
    }
  }

  @override
  void abort() => _stop(const EwsException(MailProblemCode.staleOperation));

  void _stop(EwsException reason) {
    if (_stopped) return;
    _stopped = true;
    _stopReason = reason;
    _secret = null;
    _deadline?.cancel();
    final pending = _pendingSocket;
    if (pending != null && !pending.isCompleted) pending.completeError(reason);
    _request?.abort(reason);
    _client.close(force: true);
    _connectionTask?.cancel();
    _tcpTask?.cancel();
    final raw = _rawTransport;
    if (raw != null) unawaited(raw.close());
    _socket?.destroy();
  }

  @override
  Future<String> post(
    String action,
    String envelope, {
    bool mutation = false,
  }) async {
    _check();
    if (_busy) throw const EwsException(MailProblemCode.unavailable);
    if (!RegExp(r'^[A-Za-z][A-Za-z0-9]{0,63}$').hasMatch(action) ||
        envelope.isEmpty) {
      throw const EwsException(MailProblemCode.invalidInput);
    }
    if (envelope.length > limits.maxRequestBytes) {
      throw const EwsException(MailProblemCode.quotaExceeded);
    }
    final bytes = utf8.encode(envelope);
    if (bytes.length > limits.maxRequestBytes) {
      throw const EwsException(MailProblemCode.quotaExceeded);
    }
    _busy = true;
    try {
      if (configuration.authentication == MailEwsAuthentication.ntlm &&
          _ntlmConnection == null) {
        await _authenticateNtlm();
      }
      _check();
      final request = await _open('POST', expected: _ntlmConnection);
      request.headers
        ..contentType = ContentType('text', 'xml', charset: 'utf-8')
        ..set(
          'SOAPAction',
          '"http://schemas.microsoft.com/exchange/services/2006/messages/$action"',
        );
      request.contentLength = bytes.length;
      switch (configuration.authentication) {
        case MailEwsAuthentication.ntlm:
          // The socket itself is authenticated; a Type 3 token is never reused.
          break;
        case MailEwsAuthentication.basic:
          final user =
              configuration.domain.isNotEmpty &&
                  !configuration.username.contains(r'\') &&
                  !configuration.username.contains('@')
              ? '${configuration.domain}\\${configuration.username}'
              : configuration.username;
          request.headers.set(
            HttpHeaders.authorizationHeader,
            'Basic ${base64.encode(utf8.encode('$user:${_secret!}'))}',
          );
        case MailEwsAuthentication.bearer:
          request.headers.set(
            HttpHeaders.authorizationHeader,
            'Bearer ${_secret!}',
          );
      }
      _check();
      // Any failure after this point leaves a mutation's remote outcome unknown.
      if (mutation) _mutationStarted = true;
      request.add(bytes);
      final response = await request.close();
      _request = null;
      _check();
      _validateResponse(response);
      if (_ntlmConnection != null &&
          _connection(response.connectionInfo) != _ntlmConnection) {
        throw const EwsException(MailProblemCode.unavailable);
      }
      _httpError(response);
      // SOAP faults can arrive with HTTP 500 and must reach the SOAP parser.
      if (response.statusCode != HttpStatus.ok &&
          response.statusCode != HttpStatus.internalServerError) {
        throw const EwsException(MailProblemCode.providerFailure);
      }
      final body = await _body(response);
      _check();
      return utf8.decode(body);
    } on EwsException catch (error) {
      _stop(error);
      rethrow;
    } on HandshakeException {
      const error = EwsException(MailProblemCode.permissionDenied);
      _stop(error);
      throw error;
    } on SocketException {
      final error = _stopped
          ? _stopReason
          : const EwsException(MailProblemCode.unavailable);
      _stop(error);
      throw error;
    } on Object {
      final error = _stopped
          ? _stopReason
          : const EwsException(MailProblemCode.providerFailure);
      _stop(error);
      throw error;
    } finally {
      _busy = false;
    }
  }

  Future<HttpClientRequest> _open(
    String method, {
    (String, int, int)? expected,
  }) async {
    _check();
    final request = await _client.openUrl(method, configuration.endpoint);
    _request = request;
    _check();
    if (expected != null && _connection(request.connectionInfo) != expected) {
      request.abort(const EwsException(MailProblemCode.unavailable));
      throw const EwsException(MailProblemCode.unavailable);
    }
    request
      ..followRedirects = false
      ..maxRedirects = 0
      ..persistentConnection = true
      ..bufferOutput = true;
    request.headers
      ..set(HttpHeaders.userAgentHeader, 'QudsMail/0.1 EWS')
      ..set(HttpHeaders.acceptHeader, 'text/xml, application/soap+xml')
      ..set(HttpHeaders.acceptEncodingHeader, 'identity');
    return request;
  }

  Future<void> _authenticateNtlm() async {
    final negotiate = createNtlmNegotiateMessage();
    final first = await _open('HEAD');
    first.contentLength = 0;
    first.headers.set(
      HttpHeaders.authorizationHeader,
      'NTLM ${base64.encode(negotiate)}',
    );
    final challengeResponse = await first.close();
    _request = null;
    _check();
    _validateResponse(challengeResponse);
    if (challengeResponse.statusCode != HttpStatus.unauthorized) {
      _httpError(challengeResponse);
      throw const EwsException(MailProblemCode.authenticationRequired);
    }
    if (!challengeResponse.persistentConnection) {
      throw const EwsException(MailProblemCode.unavailable);
    }
    final challenge = _ntlmChallenge(challengeResponse.headers);
    final connection = _connection(challengeResponse.connectionInfo);
    final certificate = challengeResponse.certificate;
    if (connection == null || certificate == null) {
      throw const EwsException(MailProblemCode.permissionDenied);
    }
    final binding = tlsServerEndPointChannelBinding(certificate.der);
    final authenticate = createNtlmAuthenticateMessage(
      negotiate: negotiate,
      challenge: challenge,
      username: configuration.username,
      domain: configuration.domain,
      workstation: configuration.workstation,
      password: _secret!,
      channelBinding: binding,
      targetName: 'HTTP/${configuration.endpoint.host}',
    );
    await _body(challengeResponse, head: true);
    _check();
    final last = await _open('HEAD', expected: connection);
    last.contentLength = 0;
    last.headers.set(
      HttpHeaders.authorizationHeader,
      'NTLM ${base64.encode(authenticate)}',
    );
    final response = await last.close();
    _request = null;
    _check();
    _validateResponse(response, allowAuthenticatedHeadRedirect: true);
    _httpError(response);
    final persistentAuth = response.headers['persistent-auth'];
    if (persistentAuth != null &&
        (persistentAuth.length != 1 ||
            persistentAuth.single.trim().toLowerCase() != 'true')) {
      // This adapter deliberately does not replay requests or attach Type 3
      // tokens to mailbox commands for IIS configurations requiring reauth.
      throw const EwsException(MailProblemCode.unsupported);
    }
    if (_connection(response.connectionInfo) != connection ||
        !response.persistentConnection) {
      throw const EwsException(MailProblemCode.unavailable);
    }
    // ASMX can reject HEAD after successful IIS authentication. No SOAP or
    // mailbox operation was submitted. These responses still establish auth.
    if ((response.statusCode < 200 || response.statusCode >= 300) &&
        response.statusCode != HttpStatus.found &&
        response.statusCode != HttpStatus.badRequest &&
        response.statusCode != HttpStatus.methodNotAllowed &&
        response.statusCode != HttpStatus.internalServerError) {
      throw const EwsException(MailProblemCode.providerFailure);
    }
    await _body(response, head: true);
    _check();
    _ntlmConnection = connection;
    _secret = null;
  }

  Uint8List _ntlmChallenge(HttpHeaders headers) {
    final values =
        headers[HttpHeaders.wwwAuthenticateHeader] ?? const <String>[];
    String? token;
    for (final value in values) {
      for (final part in value.split(',')) {
        final match = RegExp(
          r'^NTLM +([A-Za-z0-9+/]+={0,2})$',
          caseSensitive: false,
        ).firstMatch(part.trim());
        if (match != null) {
          if (token != null) {
            throw const EwsException(MailProblemCode.providerFailure);
          }
          token = match.group(1)!;
        }
      }
    }
    if (token == null) {
      throw const EwsException(MailProblemCode.authenticationRequired);
    }
    if (token.length > 87384) {
      throw const EwsException(MailProblemCode.quotaExceeded);
    }
    try {
      return base64.decode(token);
    } on FormatException {
      throw const EwsException(MailProblemCode.providerFailure);
    }
  }

  void _validateResponse(
    HttpClientResponse response, {
    bool allowAuthenticatedHeadRedirect = false,
  }) {
    _check();
    if (response.certificate == null) {
      throw const EwsException(MailProblemCode.permissionDenied);
    }
    var headerBytes = 0;
    response.headers.forEach((name, values) {
      for (final value in values) {
        headerBytes += name.length + value.length + 4;
      }
    });
    if (headerBytes > limits.maxHeaderBytes) {
      throw const EwsException(MailProblemCode.quotaExceeded);
    }
    _consume(headerBytes);
    if (response.statusCode >= 300 &&
        response.statusCode < 400 &&
        !(allowAuthenticatedHeadRedirect &&
            _isAuthenticatedHeadRedirect(response))) {
      throw const EwsException(MailProblemCode.permissionDenied);
    }
  }

  bool _isAuthenticatedHeadRedirect(HttpClientResponse response) {
    // Exchange can redirect the authenticated, body-free HEAD to its
    // same-origin service page. Verify persistent authentication and send SOAP
    // only to the original endpoint on the same connection.
    if (response.statusCode != HttpStatus.found ||
        response.headers['persistent-auth']?.singleOrNull
                ?.trim()
                .toLowerCase() !=
            'true' ||
        response.headers[HttpHeaders.wwwAuthenticateHeader] != null) {
      return false;
    }
    final location = response.headers[HttpHeaders.locationHeader]?.singleOrNull;
    if (location == null || location.isEmpty) return false;
    final reference = Uri.tryParse(location);
    if (reference == null) return false;
    final destination = configuration.endpoint.resolveUri(reference);
    return destination.scheme == configuration.endpoint.scheme &&
        destination.host == configuration.endpoint.host &&
        destination.port == configuration.endpoint.port &&
        destination.userInfo.isEmpty;
  }

  void _httpError(HttpClientResponse response) {
    switch (response.statusCode) {
      case HttpStatus.unauthorized:
        throw const EwsException(MailProblemCode.authenticationRequired);
      case HttpStatus.forbidden:
      case HttpStatus.proxyAuthenticationRequired:
        throw const EwsException(MailProblemCode.permissionDenied);
      case HttpStatus.tooManyRequests:
      case HttpStatus.serviceUnavailable:
        final retry = response.headers[HttpHeaders.retryAfterHeader];
        Duration? retryAfter;
        if (retry != null && retry.length == 1) {
          final seconds = int.tryParse(retry.single);
          if (seconds != null && seconds >= 0 && seconds <= 86400) {
            retryAfter = Duration(seconds: seconds);
          }
        }
        throw EwsException(MailProblemCode.unavailable, retryAfter: retryAfter);
    }
  }

  Future<Uint8List> _body(
    HttpClientResponse response, {
    bool head = false,
  }) async {
    _check();
    if (!head &&
        response.contentLength > limits.maxResponseBytes - _responseBytes) {
      throw const EwsException(MailProblemCode.quotaExceeded);
    }
    final body = BytesBuilder(copy: false);
    await for (final chunk in response) {
      _check();
      _consume(chunk.length);
      body.add(chunk);
    }
    _check();
    return body.takeBytes();
  }

  void _consume(int bytes) {
    if (bytes < 0 || bytes > limits.maxResponseBytes - _responseBytes) {
      throw const EwsException(MailProblemCode.quotaExceeded);
    }
    _responseBytes += bytes;
  }

  (String, int, int)? _connection(HttpConnectionInfo? info) => info == null
      ? null
      : (info.remoteAddress.address, info.remotePort, info.localPort);
}

/// A native TLS socket whose original TCP owner remains closeable throughout
/// the connection. All TLS/certificate work stays in Dart's platform TLS stack.
final class _OwnedTlsSocket extends Stream<Uint8List> implements SecureSocket {
  _OwnedTlsSocket(this._tls, this._tcp)
    : address = _tls.address,
      remoteAddress = _tls.remoteAddress,
      port = _tls.port,
      remotePort = _tls.remotePort,
      peerCertificate = _tls.peerCertificate,
      selectedProtocol = _tls.selectedProtocol {
    _tls
      ..readEventsEnabled = false
      ..writeEventsEnabled = false;
    _input
      ..onListen = _readsChanged
      ..onPause = _readsChanged
      ..onResume = _readsChanged
      ..onCancel = _cancelReads;
    _output = _TlsOutput(this);
    _sink = IOSink(_output);
    _sink.done.ignore();
    _events = _tls.listen(_event, onError: _error, onDone: destroy);
  }

  final RawSecureSocket _tls;
  final RawSocket _tcp;
  final _input = StreamController<Uint8List>(sync: true);
  late final StreamSubscription<RawSocketEvent> _events;
  late final _TlsOutput _output;
  late final IOSink _sink;
  Completer<void>? _writable;
  bool _closed = false;
  bool _inputEnded = false;

  @override
  final InternetAddress address;
  @override
  final InternetAddress remoteAddress;
  @override
  final int port;
  @override
  final int remotePort;
  @override
  final X509Certificate? peerCertificate;
  @override
  final String? selectedProtocol;

  void _readsChanged() {
    if (!_closed) {
      _tls.readEventsEnabled =
          !_inputEnded && _input.hasListener && !_input.isPaused;
    }
  }

  void _cancelReads() {
    _inputEnded = true;
    if (!_closed) _tls.shutdown(SocketDirection.receive);
  }

  void _finishInput() {
    if (_inputEnded) return;
    _inputEnded = true;
    unawaited(_input.close());
  }

  void _event(RawSocketEvent event) {
    if (_closed) return;
    if (event == RawSocketEvent.read && !_inputEnded) {
      final bytes = _tls.read();
      if (bytes != null) _input.add(bytes);
    } else if (event == RawSocketEvent.write) {
      final ready = _writable;
      _writable = null;
      if (ready != null && !ready.isCompleted) ready.complete();
    } else if (event == RawSocketEvent.readClosed) {
      _finishInput();
    }
  }

  void _error(Object error, StackTrace stack) {
    if (!_inputEnded) _input.addError(error, stack);
    destroy();
  }

  Future<void> _send(List<int> bytes) async {
    var offset = 0;
    while (offset < bytes.length) {
      if (_closed) throw const EwsException(MailProblemCode.unavailable);
      offset += _tls.write(bytes, offset, bytes.length - offset);
      // Wait for TLS write readiness, including after the final accepted bytes,
      // so IOSink.flush is ordered after the raw socket has drained its buffer.
      final ready = Completer<void>();
      _writable = ready;
      _tls.writeEventsEnabled = true;
      await ready.future;
    }
  }

  @override
  void destroy() {
    if (_closed) return;
    _closed = true;
    final ready = _writable;
    _writable = null;
    ready?.completeError(const EwsException(MailProblemCode.unavailable));
    _output.cancel();
    // Close TCP directly rather than waiting for a TLS close-notify exchange.
    unawaited(_tcp.close());
    unawaited(_tls.close());
    unawaited(_events.cancel());
    _finishInput();
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
  void writeAll(Iterable<Object?> objects, [String separator = '']) =>
      _sink.writeAll(objects, separator);
  @override
  void add(List<int> bytes) => _sink.add(bytes);
  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      _sink.addError(error, stackTrace);
  @override
  Future<void> addStream(Stream<List<int>> stream) => _sink.addStream(stream);
  @override
  Future<void> flush() => _sink.flush();
  @override
  Future<void> close() => _sink.close();
  @override
  Future<void> get done => _sink.done;
  @override
  bool setOption(SocketOption option, bool enabled) =>
      _tls.setOption(option, enabled);
  @override
  Uint8List getRawOption(RawSocketOption option) => _tls.getRawOption(option);
  @override
  void setRawOption(RawSocketOption option) => _tls.setRawOption(option);
  @override
  void renegotiate({
    bool useSessionCache = true,
    bool requestClientCertificate = false,
    bool requireClientCertificate = false,
  }) => throw UnsupportedError('TLS renegotiation is unavailable.');

  // Socket's SDK-private detach method cannot be implemented outside dart:io.
  // HTTPS is already established, and HttpClient never requests that method.
  @override
  Object? noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _TlsOutput implements StreamConsumer<List<int>> {
  _TlsOutput(this.owner);
  final _OwnedTlsSocket owner;
  StreamIterator<List<int>>? _source;

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    final source = StreamIterator(stream);
    _source = source;
    try {
      while (await source.moveNext()) {
        await owner._send(source.current);
      }
      if (owner._closed) throw const EwsException(MailProblemCode.unavailable);
    } finally {
      _source = null;
      await source.cancel();
    }
  }

  void cancel() {
    final source = _source;
    if (source != null) unawaited(source.cancel());
  }

  @override
  Future<void> close() async {
    if (!owner._closed) owner._tls.shutdown(SocketDirection.send);
  }
}
