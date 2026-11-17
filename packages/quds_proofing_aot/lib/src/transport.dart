import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'models.dart';

/// POST is preferred. GET is an explicit compatibility choice for older
/// deployments and puts supplied text in URLs and intermediary logs.
enum AotRequestMethod { post, get }

enum AotErrorCode {
  unavailable,
  http,
  timeout,
  malformedResponse,
  unsupportedLanguage,
  limit,
  disposed,
}

/// Operational errors are distinct from a successful analysis with no findings.
/// Messages deliberately exclude document text and response bodies.
final class AotException implements Exception {
  const AotException(this.code, this.message, {this.statusCode});
  final AotErrorCode code;
  final String message;
  final int? statusCode;

  @override
  String toString() => 'AotException(${code.name}): $message';
}

abstract interface class AotTransport {
  Future<Object?> request({
    required String action,
    required AotLanguage language,
    required String query,
    bool withParadigms = false,
  });
  Future<void> dispose();
}

/// Bounded transport for the upstream SynanDaemon, using form POST by default.
///
/// AOT serializes requests internally, so this transport sends one at a time.
/// The deadline includes queueing and reading the response. Timed-out requests
/// use package:http's abort protocol; pending work is cancelled on disposal.
/// An injected [httpClient] is owned and closed by this transport and should
/// support [http.AbortableRequest] (the standard IO/browser clients do).
///
/// Non-loopback endpoints require an explicit [allowRemote] opt-in. Redirects
/// are disabled so a local endpoint cannot silently forward document text.
final class AotHttpTransport implements AotTransport {
  AotHttpTransport({
    Uri? endpoint,
    bool allowRemote = false,
    http.Client? httpClient,
    this.requestMethod = AotRequestMethod.post,
    this.timeout = const Duration(seconds: 15),
    this.maximumQueryCodeUnits = 32768,
    this.maximumRequestBytes = 256 * 1024,
    this.maximumResponseBytes = 4 * 1024 * 1024,
    this.maximumPendingRequests = 4,
  }) : endpoint = _validateEndpoint(
         endpoint ?? Uri.parse('http://127.0.0.1:17018/'),
         allowRemote,
       ),
       _client = httpClient ?? http.Client() {
    if (timeout <= Duration.zero ||
        maximumQueryCodeUnits < 1 ||
        maximumRequestBytes < 1 ||
        maximumResponseBytes < 1 ||
        maximumPendingRequests < 1 ||
        maximumPendingRequests > 32) {
      _client.close();
      throw ArgumentError('Invalid AOT transport limits.');
    }
  }

  final Uri endpoint;
  final AotRequestMethod requestMethod;
  final Duration timeout;
  final int maximumQueryCodeUnits;
  final int maximumRequestBytes;
  final int maximumResponseBytes;
  final int maximumPendingRequests;
  final http.Client _client;
  final Queue<_PendingAotRequest> _queue = Queue<_PendingAotRequest>();
  final Set<_PendingAotRequest> _pending = <_PendingAotRequest>{};
  _PendingAotRequest? _active;
  bool _disposed = false;

  @override
  Future<Object?> request({
    required String action,
    required AotLanguage language,
    required String query,
    bool withParadigms = false,
  }) async {
    if (_disposed) {
      throw const AotException(
        AotErrorCode.disposed,
        'AOT transport is disposed.',
      );
    }
    if (action != 'syntax' && action != 'morph') {
      throw ArgumentError.value(action, 'action', 'Expected syntax or morph.');
    }
    if (action == 'syntax' && !language.supportsSyntax) {
      throw const AotException(
        AotErrorCode.unsupportedLanguage,
        'AOT syntax analysis supports German and Russian.',
      );
    }
    if (query.trim().isEmpty) {
      throw ArgumentError.value('', 'query', 'AOT requires nonempty text.');
    }
    if (query.length > maximumQueryCodeUnits) {
      throw const AotException(
        AotErrorCode.limit,
        'Text exceeds the configured AOT request limit.',
      );
    }
    if (_pending.length >= maximumPendingRequests) {
      throw const AotException(
        AotErrorCode.limit,
        'The bounded AOT request queue is full.',
      );
    }
    final _PendingAotRequest pending = _PendingAotRequest();
    final Map<String, String> fields = <String, String>{
      'action': action,
      'langua': language.daemonName,
      'query': query,
      if (withParadigms && action == 'morph') 'withparadigms': '1',
    };
    final Uri requestUri = requestMethod == AotRequestMethod.get
        ? endpoint.replace(queryParameters: fields)
        : endpoint;
    final http.AbortableRequest request =
        http.AbortableRequest(
            requestMethod == AotRequestMethod.post ? 'POST' : 'GET',
            requestUri,
            abortTrigger: pending.abort.future,
          )
          ..followRedirects = false
          ..headers['Accept'] = 'application/json';
    if (requestMethod == AotRequestMethod.post) request.bodyFields = fields;
    if (request.bodyBytes.length > maximumRequestBytes ||
        (requestMethod == AotRequestMethod.get &&
            utf8.encode(requestUri.toString()).length > maximumRequestBytes)) {
      throw const AotException(
        AotErrorCode.limit,
        'Encoded text exceeds the configured AOT request limit.',
      );
    }
    pending.request = request;
    _pending.add(pending);
    _queue.add(pending);
    pending.timer = Timer(timeout, () {
      _cancel(
        pending,
        const AotException(
          AotErrorCode.timeout,
          'AOT request exceeded its deadline.',
        ),
      );
    });
    _pump();
    return pending.result.future;
  }

  void _pump() {
    if (_disposed || _active != null || _queue.isEmpty) return;
    final _PendingAotRequest pending = _queue.removeFirst();
    _active = pending;
    unawaited(_run(pending));
  }

  Future<void> _run(_PendingAotRequest pending) async {
    try {
      final Object? json = await _send(pending);
      if (!pending.result.isCompleted) pending.result.complete(json);
    } on AotException catch (error, stack) {
      if (!pending.result.isCompleted) {
        pending.result.completeError(error, stack);
      }
    } on FormatException catch (_, stack) {
      if (!pending.result.isCompleted) {
        pending.result.completeError(
          const AotException(
            AotErrorCode.malformedResponse,
            'AOT returned invalid UTF-8 or JSON.',
          ),
          stack,
        );
      }
    } catch (_, stack) {
      if (!pending.result.isCompleted) {
        pending.result.completeError(
          const AotException(
            AotErrorCode.unavailable,
            'The configured AOT daemon could not be reached.',
          ),
          stack,
        );
      }
    } finally {
      pending.timer?.cancel();
      _pending.remove(pending);
      if (identical(_active, pending)) _active = null;
      _pump();
    }
  }

  Future<Object?> _send(_PendingAotRequest pending) async {
    final http.StreamedResponse response = await _client.send(pending.request);
    if (pending.result.isCompleted) {
      await response.stream.listen(null).cancel();
      return null;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      await response.stream.listen(null).cancel();
      throw AotException(
        AotErrorCode.http,
        'AOT daemon returned HTTP ${response.statusCode}.',
        statusCode: response.statusCode,
      );
    }
    if ((response.contentLength ?? 0) > maximumResponseBytes) {
      if (!pending.abort.isCompleted) pending.abort.complete();
      await response.stream.listen(null).cancel();
      throw const AotException(
        AotErrorCode.limit,
        'AOT response exceeds the configured byte limit.',
      );
    }
    final BytesBuilder bytes = BytesBuilder(copy: false);
    await for (final List<int> chunk in response.stream) {
      if (pending.result.isCompleted) break;
      if (chunk.length > maximumResponseBytes - bytes.length) {
        if (!pending.abort.isCompleted) pending.abort.complete();
        throw const AotException(
          AotErrorCode.limit,
          'AOT response exceeds the configured byte limit.',
        );
      }
      bytes.add(chunk);
    }
    if (pending.result.isCompleted) return null;
    return jsonDecode(utf8.decode(bytes.takeBytes()));
  }

  void _cancel(_PendingAotRequest pending, AotException reason) {
    pending.timer?.cancel();
    if (!pending.abort.isCompleted) pending.abort.complete();
    if (!pending.result.isCompleted) pending.result.completeError(reason);
    if (!identical(_active, pending)) {
      _queue.remove(pending);
      _pending.remove(pending);
    }
    // Keep an active slot until the HTTP client acknowledges cancellation.
    // Even a broken injected client cannot accumulate unbounded live requests.
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final _PendingAotRequest pending in _pending.toList()) {
      _cancel(
        pending,
        const AotException(AotErrorCode.disposed, 'AOT transport is disposed.'),
      );
    }
    _queue.clear();
    _client.close();
  }
}

final class _PendingAotRequest {
  final Completer<Object?> result = Completer<Object?>();
  final Completer<void> abort = Completer<void>();
  late final http.AbortableRequest request;
  Timer? timer;
}

Uri _validateEndpoint(Uri endpoint, bool allowRemote) {
  if ((endpoint.scheme != 'http' && endpoint.scheme != 'https') ||
      !endpoint.hasAuthority ||
      endpoint.host.isEmpty ||
      endpoint.userInfo.isNotEmpty ||
      endpoint.hasQuery ||
      endpoint.hasFragment) {
    throw ArgumentError(
      'AOT endpoint must be an HTTP(S) URL without credentials, query or fragment.',
    );
  }
  final String host = endpoint.host.toLowerCase();
  final List<String> parts = host.split('.');
  final bool ipv4Loopback =
      parts.length == 4 &&
      parts.first == '127' &&
      parts.every((String part) {
        final int? number = int.tryParse(part);
        return number != null &&
            number >= 0 &&
            number <= 255 &&
            number.toString() == part;
      });
  final bool loopback =
      host == 'localhost' || host == '::1' || host == '[::1]' || ipv4Loopback;
  if (!loopback && !allowRemote) {
    throw ArgumentError(
      'A non-loopback AOT endpoint requires explicit allowRemote: true consent.',
    );
  }
  return endpoint;
}
