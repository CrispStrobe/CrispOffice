import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'models.dart';
import 'transport.dart';

final bool processTransportSupported =
    Platform.isLinux || Platform.isMacOS || Platform.isWindows;

AotTransport createProcessTransport({
  required String executable,
  required List<String> arguments,
  required String? rmlDirectory,
  required Map<String, String> environment,
  required Duration timeout,
  required int maximumQueryCodeUnits,
  required int maximumRequestBytes,
  required int maximumResponseBytes,
  required int maximumStderrBytes,
  required int maximumPendingRequests,
}) => _NativeAotProcessTransport(
  executable: executable,
  arguments: arguments,
  environment: <String, String>{...environment, 'RML': ?rmlDirectory},
  timeout: timeout,
  maximumQueryCodeUnits: maximumQueryCodeUnits,
  maximumRequestBytes: maximumRequestBytes,
  maximumResponseBytes: maximumResponseBytes,
  maximumStderrBytes: maximumStderrBytes,
  maximumPendingRequests: maximumPendingRequests,
);

final class _NativeAotProcessTransport implements AotTransport {
  _NativeAotProcessTransport({
    required this.executable,
    required this.arguments,
    required this.environment,
    required this.timeout,
    required this.maximumQueryCodeUnits,
    required this.maximumRequestBytes,
    required this.maximumResponseBytes,
    required this.maximumStderrBytes,
    required this.maximumPendingRequests,
  });

  final String executable;
  final List<String> arguments;
  final Map<String, String> environment;
  final Duration timeout;
  final int maximumQueryCodeUnits;
  final int maximumRequestBytes;
  final int maximumResponseBytes;
  final int maximumStderrBytes;
  final int maximumPendingRequests;
  final Queue<_ProcessRequest> _queue = Queue<_ProcessRequest>();
  final Set<_ProcessRequest> _pending = <_ProcessRequest>{};
  final BytesBuilder _response = BytesBuilder(copy: false);
  _ProcessRequest? _active;
  Process? _process;
  Future<Process>? _starting;
  Future<void>? _stopping;
  StreamSubscription<List<int>>? _stdout;
  StreamSubscription<List<int>>? _stderr;
  AotException? _failure;
  int _nextId = 0;
  int _stderrBytes = 0;
  bool _running = false;
  bool _disposed = false;

  @override
  Future<Object?> request({
    required String action,
    required AotLanguage language,
    required String query,
    bool withParadigms = false,
  }) async {
    if (_disposed) throw _disposedError;
    if (_failure != null) throw _failure!;
    if (!processTransportSupported) {
      throw const AotException(
        AotErrorCode.unavailable,
        'Local AOT workers are supported on Linux, macOS and Windows desktop '
        'hosts. This platform requires an explicitly configured transport.',
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
    final int id = ++_nextId;
    final List<int> encoded = utf8.encode(
      '${jsonEncode(<String, Object?>{'id': id, 'action': action, 'langua': language.daemonName, 'query': query, 'withparadigms': withParadigms && action == 'morph'})}\n',
    );
    if (encoded.length > maximumRequestBytes) {
      throw const AotException(
        AotErrorCode.limit,
        'Encoded text exceeds the configured AOT request limit.',
      );
    }
    final _ProcessRequest pending = _ProcessRequest(id, encoded);
    _pending.add(pending);
    _queue.add(pending);
    pending.timer = Timer(timeout, () {
      const AotException error = AotException(
        AotErrorCode.timeout,
        'AOT worker request exceeded its deadline.',
      );
      if (identical(_active, pending)) {
        _fail(error);
      } else {
        _queue.remove(pending);
        _pending.remove(pending);
        _completeError(pending, error);
      }
    });
    _pump();
    return pending.result.future;
  }

  void _pump() {
    if (_running || _disposed || _failure != null || _queue.isEmpty) return;
    _running = true;
    unawaited(_run());
  }

  Future<void> _run() async {
    try {
      while (!_disposed && _failure == null && _queue.isNotEmpty) {
        final _ProcessRequest pending = _queue.removeFirst();
        if (pending.result.isCompleted) continue;
        _active = pending;
        _stderrBytes = 0;
        try {
          final Process process = await _ensureProcess();
          if (pending.result.isCompleted || _disposed || _failure != null) {
            continue;
          }
          pending.sent = true;
          process.stdin.add(pending.encoded);
          await process.stdin.flush();
          await pending.result.future;
        } on AotException catch (error) {
          if (!pending.result.isCompleted) _fail(error);
        } catch (_) {
          if (!pending.result.isCompleted) {
            _fail(
              const AotException(
                AotErrorCode.unavailable,
                'The local AOT worker could not be started or contacted. '
                'Check its executable and language resources.',
              ),
            );
          }
        } finally {
          pending.timer?.cancel();
          _pending.remove(pending);
          if (identical(_active, pending)) _active = null;
        }
      }
    } finally {
      _running = false;
      _pump();
    }
  }

  Future<Process> _ensureProcess() async {
    if (_process != null) return _process!;
    final Future<Process> starting = Process.start(
      executable,
      arguments,
      environment: environment,
      includeParentEnvironment: true,
      runInShell: false,
      mode: ProcessStartMode.normal,
    );
    _starting = starting;
    final Process process;
    try {
      process = await starting;
    } finally {
      _starting = null;
    }
    if (_disposed || _failure != null) {
      await _terminate(process);
      throw _failure ?? _disposedError;
    }
    _process = process;
    _stdout = process.stdout.listen(
      _receive,
      onError: (Object _) => _fail(_protocolError),
      onDone: () {
        if (!_disposed && _failure == null) {
          _fail(
            _response.length == 0
                ? const AotException(
                    AotErrorCode.unavailable,
                    'The local AOT worker closed its output unexpectedly.',
                  )
                : _protocolError,
          );
        }
      },
      cancelOnError: true,
    );
    _stderr = process.stderr.listen(
      (List<int> bytes) {
        _stderrBytes += bytes.length;
        if (_stderrBytes > maximumStderrBytes) {
          _fail(
            const AotException(
              AotErrorCode.limit,
              'AOT worker diagnostic output exceeded the configured limit.',
            ),
          );
        }
      },
      onError: (Object _) => _fail(
        const AotException(
          AotErrorCode.unavailable,
          'The local AOT worker output stream failed.',
        ),
      ),
      cancelOnError: true,
    );
    // Consume exit errors, but let stdout EOF determine the outcome after all
    // response bytes have been delivered. Exit and pipe events are unordered.
    unawaited(process.exitCode.then<void>((int _) {}, onError: (Object _) {}));
    return process;
  }

  void _receive(List<int> bytes) {
    if (_disposed || _failure != null) return;
    int start = 0;
    for (int index = 0; index <= bytes.length; index++) {
      if (index != bytes.length && bytes[index] != 10) continue;
      final int length = index - start;
      if (length > maximumResponseBytes - _response.length) {
        _fail(
          const AotException(
            AotErrorCode.limit,
            'AOT response exceeds the configured byte limit.',
          ),
        );
        return;
      }
      if (length > 0) _response.add(bytes.sublist(start, index));
      if (index < bytes.length) {
        _receiveLine(_response.takeBytes());
        if (_failure != null || _disposed) return;
      }
      start = index + 1;
    }
  }

  void _receiveLine(Uint8List bytes) {
    final _ProcessRequest? pending = _active;
    if (pending == null || !pending.sent || pending.result.isCompleted) {
      _fail(_protocolError);
      return;
    }
    try {
      final Object? value = jsonDecode(utf8.decode(bytes));
      if (value is! Map<String, Object?> ||
          value['id'] is! int ||
          value['id'] != pending.id ||
          value.containsKey('result') == value.containsKey('error') ||
          value.keys.any(
            (String key) =>
                key != 'id' &&
                key != 'result' &&
                key != 'error' &&
                key != 'code',
          )) {
        _fail(_protocolError);
        return;
      }
      if (value.containsKey('error')) {
        if (value['error'] is! String ||
            (value['code'] != null && value['code'] is! String)) {
          _fail(_protocolError);
          return;
        }
        final AotErrorCode code = switch (value['code']) {
          'unsupportedLanguage' => AotErrorCode.unsupportedLanguage,
          'limit' => AotErrorCode.limit,
          'invalidRequest' => AotErrorCode.malformedResponse,
          _ => AotErrorCode.unavailable,
        };
        _fail(
          AotException(
            code,
            'The local AOT worker could not complete the requested analysis. '
            'Check its installation and language resources.',
          ),
        );
        return;
      }
      pending.timer?.cancel();
      pending.result.complete(value['result']);
    } catch (_) {
      _fail(_protocolError);
    }
  }

  void _fail(AotException error) {
    if (_disposed || _failure != null) return;
    _failure = error;
    for (final _ProcessRequest pending in _pending.toList()) {
      _completeError(pending, error);
    }
    _pending.clear();
    _queue.clear();
    unawaited(_stop());
  }

  void _completeError(_ProcessRequest pending, AotException error) {
    pending.timer?.cancel();
    if (!pending.result.isCompleted) pending.result.completeError(error);
  }

  Future<void> _stop() => _stopping ??= _stopWorker();

  Future<void> _stopWorker() async {
    final Process? process = _process;
    _process = null;
    if (process != null) await _terminate(process);
    await _stdout?.cancel();
    await _stderr?.cancel();
    _stdout = null;
    _stderr = null;
    _response.clear();
    // If startup was still in progress, _ensureProcess checks the terminal
    // state and kills the process immediately when it obtains the handle.
    final Future<Process>? starting = _starting;
    if (starting != null) {
      try {
        final Process lateProcess = await starting.timeout(
          const Duration(seconds: 2),
        );
        await _terminate(lateProcess);
      } catch (_) {
        // Startup failure is already surfaced without exposing command text.
      }
    }
  }

  Future<void> _terminate(Process process) async {
    // The supplied native worker never spawns children. Force termination
    // bounds cancellation even when native analysis is CPU-bound or blocked.
    try {
      process.kill(ProcessSignal.sigkill);
    } catch (_) {
      // Windows implementations may not support a POSIX signal argument.
      // The normal kill API terminates this direct, childless worker there.
      try {
        process.kill();
      } catch (_) {}
    }
    try {
      await process.stdin.close().timeout(const Duration(seconds: 2));
    } catch (_) {}
    try {
      await process.exitCode.timeout(const Duration(seconds: 2));
    } catch (_) {}
  }

  @override
  Future<void> dispose() async {
    if (!_disposed) {
      _disposed = true;
      for (final _ProcessRequest pending in _pending.toList()) {
        _completeError(pending, _disposedError);
      }
      _pending.clear();
      _queue.clear();
    }
    await _stop();
  }
}

final class _ProcessRequest {
  _ProcessRequest(this.id, this.encoded);
  final int id;
  final List<int> encoded;
  final Completer<Object?> result = Completer<Object?>();
  Timer? timer;
  bool sent = false;
}

const AotException _protocolError = AotException(
  AotErrorCode.malformedResponse,
  'The local AOT worker returned an invalid or unexpected protocol response.',
);
const AotException _disposedError = AotException(
  AotErrorCode.disposed,
  'AOT process transport is disposed.',
);
