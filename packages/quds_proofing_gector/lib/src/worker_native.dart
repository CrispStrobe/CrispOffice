import 'dart:async';
import 'dart:isolate';

import 'backend.dart';
import 'bundle.dart';
import 'decoder.dart';
import 'guards.dart';
import 'transport.dart';

Future<GectorTransport> startWorker({
  required GectorVerifiedBundle bundle,
  required GectorBackendFactory backendFactory,
  required GectorLexiconFactory lexiconFactory,
  required GectorDecodeOptions options,
  required int maximumPendingRequests,
  required Duration startupTimeout,
}) async {
  final transport = _NativeWorker(maximumPendingRequests);
  // Isolate.spawn can fail before the readiness await is installed (for
  // example, an unsendable factory). Disposal must not leave an unhandled
  // readiness error in that path; the normal await still receives failures.
  transport._ready.future.ignore();
  transport._listen();
  try {
    transport._isolate = await Isolate.spawn<_Boot>(
      _workerMain,
      _Boot(
        transport._replies.sendPort,
        bundle,
        backendFactory,
        lexiconFactory,
        options,
        maximumPendingRequests,
      ),
      onError: transport._errors.sendPort,
      onExit: transport._exits.sendPort,
      errorsAreFatal: true,
      debugName: 'quds-gector-de',
    );
    await transport._ready.future.timeout(startupTimeout);
    return transport;
  } on Object {
    await transport.dispose();
    rethrow;
  }
}

final class _NativeWorker implements GectorTransport {
  _NativeWorker(this.maximumPendingRequests);
  final int maximumPendingRequests;
  final ReceivePort _replies = ReceivePort();
  final ReceivePort _errors = ReceivePort();
  final ReceivePort _exits = ReceivePort();
  final Completer<void> _ready = Completer<void>();
  final Completer<void> _stopped = Completer<void>();
  final Map<int, Completer<GectorDecodedText>> _pending =
      <int, Completer<GectorDecodedText>>{};
  final Map<String, int> _byKey = <String, int>{};
  final Map<int, String> _keys = <int, String>{};
  final List<StreamSubscription<Object?>> _subscriptions =
      <StreamSubscription<Object?>>[];
  Isolate? _isolate;
  SendPort? _commands;
  var _nextId = 0;
  bool _disposed = false;
  Future<void>? _disposing;

  void _listen() {
    _subscriptions.add(_replies.listen(_onReply));
    _subscriptions.add(
      _errors.listen((Object? value) {
        final message = value is List<Object?> && value.isNotEmpty
            ? value.first.toString()
            : 'Unknown worker error';
        _fail(GectorUnavailableException('GECToR worker failed: $message'));
      }),
    );
    _subscriptions.add(
      _exits.listen((Object? _) {
        _fail(const GectorUnavailableException('GECToR worker exited.'));
        if (!_stopped.isCompleted) _stopped.complete();
      }),
    );
  }

  void _onReply(Object? raw) {
    switch (raw) {
      case _Ready():
        _commands = raw.port;
        if (!_ready.isCompleted) _ready.complete();
      case _InitFailed():
        _fail(GectorUnavailableException(raw.message));
      case _Reply():
        final pending = _pending.remove(raw.id);
        final key = _keys.remove(raw.id);
        if (key != null && _byKey[key] == raw.id) _byKey.remove(key);
        if (pending == null) return;
        if (raw.result case final result?) {
          pending.complete(result);
        } else {
          pending.completeError(switch (raw.errorKind) {
            'cancelled' => const GectorCancelledException(),
            'capacity' => GectorCapacityException(raw.errorMessage!),
            'unavailable' => GectorUnavailableException(raw.errorMessage!),
            _ => StateError(raw.errorMessage ?? 'GECToR inference failed.'),
          });
        }
      case _Stopped():
        if (!_stopped.isCompleted) _stopped.complete();
      default:
        _fail(
          const GectorUnavailableException('Invalid GECToR worker protocol.'),
        );
    }
  }

  @override
  Future<GectorDecodedText> check(GectorCheckRequest request) {
    if (_disposed || _commands == null) {
      return Future<GectorDecodedText>.error(
        const GectorUnavailableException('GECToR worker is not available.'),
      );
    }
    final previousId = _byKey[request.key];
    if (previousId != null) {
      _commands!.send(_Cancel(previousId));
      _pending
          .remove(previousId)
          ?.completeError(const GectorCancelledException());
      _keys.remove(previousId);
      _byKey.remove(request.key);
    }
    if (_pending.length >= maximumPendingRequests) {
      return Future<GectorDecodedText>.error(
        const GectorCapacityException(
          'The bounded GECToR request queue is full.',
        ),
      );
    }
    final id = ++_nextId;
    final completer = Completer<GectorDecodedText>();
    _pending[id] = completer;
    _keys[id] = request.key;
    _byKey[request.key] = id;
    _commands!.send(_Run(id, request));
    return completer.future;
  }

  void _fail(Object error) {
    if (!_ready.isCompleted) _ready.completeError(error);
    for (final pending in _pending.values) {
      if (!pending.isCompleted) pending.completeError(error);
    }
    _pending.clear();
    _keys.clear();
    _byKey.clear();
    _disposed = true;
  }

  @override
  Future<void> dispose() => _disposing ??= _dispose();

  Future<void> _dispose() async {
    _fail(const GectorUnavailableException('GECToR worker was disposed.'));
    _commands?.send(const _Stop());
    if (_commands != null) {
      try {
        await _stopped.future.timeout(const Duration(seconds: 2));
      } on TimeoutException {
        /* Bound shutdown if native code cannot return. */
      }
    }
    _isolate?.kill(priority: Isolate.immediate);
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _replies.close();
    _errors.close();
    _exits.close();
  }
}

final class _Boot {
  const _Boot(
    this.reply,
    this.bundle,
    this.backendFactory,
    this.lexiconFactory,
    this.options,
    this.maximumPendingRequests,
  );
  final SendPort reply;
  final GectorVerifiedBundle bundle;
  final GectorBackendFactory backendFactory;
  final GectorLexiconFactory lexiconFactory;
  final GectorDecodeOptions options;
  final int maximumPendingRequests;
}

final class _Ready {
  const _Ready(this.port);
  final SendPort port;
}

final class _InitFailed {
  const _InitFailed(this.message);
  final String message;
}

final class _Run {
  const _Run(this.id, this.request);
  final int id;
  final GectorCheckRequest request;
}

final class _Cancel {
  const _Cancel(this.id);
  final int id;
}

final class _Stop {
  const _Stop();
}

final class _Stopped {
  const _Stopped();
}

final class _Reply {
  const _Reply(this.id, {this.result, this.errorKind, this.errorMessage});
  final int id;
  final GectorDecodedText? result;
  final String? errorKind;
  final String? errorMessage;
}

Future<void> _workerMain(_Boot boot) async {
  GectorBackend? backend;
  GectorLexicon? lexicon;
  try {
    lexicon = await boot.lexiconFactory.open();
    final guards = GectorGermanGuards.fromJson(
      boot.bundle.guardsJson,
      configuration: boot.bundle.configuration,
      lexicon: lexicon,
    );
    backend = await boot.backendFactory.open(boot.bundle.artifact);
    backend.identity.validate(boot.bundle.artifact);
    final decoder = GectorDecoder.guarded(
      configuration: boot.bundle.configuration,
      tokenizer: boot.bundle.tokenizer,
      backend: backend,
      guards: guards,
      options: boot.options,
    );
    _WorkerState(boot, backend, lexicon, decoder).listen();
  } on Object catch (error) {
    try {
      await backend?.dispose();
    } on Object {
      /* Preserve init error. */
    }
    try {
      await lexicon?.dispose();
    } on Object {
      /* Preserve init error. */
    }
    boot.reply.send(_InitFailed('Cannot initialize local GECToR: $error'));
  }
}

final class _WorkerState {
  _WorkerState(this.boot, this.backend, this.lexicon, this.decoder);
  final _Boot boot;
  final GectorBackend backend;
  final GectorLexicon lexicon;
  final GectorDecoder decoder;
  final ReceivePort commands = ReceivePort();
  final List<_Run> queue = <_Run>[];
  final Set<int> cancelled = <int>{};
  _Run? active;
  bool stopping = false;
  bool closing = false;
  StreamSubscription<Object?>? subscription;

  void listen() {
    subscription = commands.listen(_command);
    boot.reply.send(_Ready(commands.sendPort));
  }

  void _command(Object? message) {
    switch (message) {
      case _Run():
        if (stopping) {
          _reject(message.id, 'unavailable', 'GECToR is stopping.');
          return;
        }
        for (final old
            in queue
                .where((task) => task.request.key == message.request.key)
                .toList()) {
          queue.remove(old);
          _reject(old.id, 'cancelled', 'Superseded by a newer request.');
        }
        if (active?.request.key == message.request.key) {
          cancelled.add(active!.id);
        }
        if (queue.length +
                (active == null || cancelled.contains(active!.id) ? 0 : 1) >=
            boot.maximumPendingRequests) {
          _reject(
            message.id,
            'capacity',
            'The bounded GECToR worker queue is full.',
          );
          return;
        }
        queue.add(message);
        _schedule();
      case _Cancel():
        if (active?.id == message.id) cancelled.add(message.id);
        final queued = queue.where((task) => task.id == message.id).toList();
        for (final task in queued) {
          queue.remove(task);
          _reject(task.id, 'cancelled', 'GECToR request was cancelled.');
        }
      case _Stop():
        stopping = true;
        if (active case final task?) cancelled.add(task.id);
        for (final task in queue) {
          _reject(task.id, 'unavailable', 'GECToR was disposed.');
        }
        queue.clear();
        if (active == null) unawaited(_close());
      default:
        stopping = true;
        if (active == null) unawaited(_close());
    }
  }

  void _schedule() {
    if (active != null || queue.isEmpty || stopping) return;
    active = queue.removeAt(0);
    unawaited(_run(active!));
  }

  Future<void> _run(_Run task) async {
    try {
      final result = await decoder.correct(
        task.request.text,
        personalWords: task.request.personalWords,
        isCancelled: () => stopping || cancelled.contains(task.id),
      );
      boot.reply.send(_Reply(task.id, result: result));
    } on GectorCancelledException catch (error) {
      _reject(task.id, 'cancelled', error.toString());
    } on GectorCapacityException catch (error) {
      _reject(task.id, 'capacity', error.message);
    } on GectorUnavailableException catch (error) {
      _reject(task.id, 'unavailable', error.message);
    } on Object catch (error) {
      _reject(task.id, 'failed', error.toString());
    } finally {
      cancelled.remove(task.id);
      active = null;
      if (stopping) {
        await _close();
      } else {
        _schedule();
      }
    }
  }

  void _reject(int id, String kind, String message) =>
      boot.reply.send(_Reply(id, errorKind: kind, errorMessage: message));

  Future<void> _close() async {
    if (closing) return;
    closing = true;
    try {
      await backend.dispose();
    } on Object {
      /* Always release remaining resources. */
    }
    try {
      await lexicon.dispose();
    } on Object {
      /* Shutdown is best effort. */
    }
    await subscription?.cancel();
    commands.close();
    boot.reply.send(const _Stopped());
  }
}
