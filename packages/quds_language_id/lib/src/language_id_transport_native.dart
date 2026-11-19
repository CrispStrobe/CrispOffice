import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'language_id_transport.dart';

LanguageIdTransport createLanguageIdTransport({
  String? nativeLibraryPath,
  Uri? workerUrl,
}) => _NativeTransport(nativeLibraryPath);

/// Default library file name for this platform.
String get languageIdLibraryName => Platform.isWindows
    ? 'quds_language_id.dll'
    : Platform.isMacOS || Platform.isIOS
    ? 'libquds_language_id.dylib'
    : 'libquds_language_id.so';

/// Owns a persistent isolate holding the native classifier, so loading and
/// classification never block the UI isolate.
final class _NativeTransport implements LanguageIdTransport {
  _NativeTransport(this.libraryPath);
  final String? libraryPath;
  final _pending = <int, Completer<Object?>>{};
  Isolate? _isolate;
  ReceivePort? _messages;
  ReceivePort? _errors;
  Future<SendPort>? _opening;
  Completer<SendPort>? _ready;
  final _closed = Completer<void>();
  Future<void>? _disposal;
  bool _disposed = false;
  bool _aborted = false;
  int _sequence = 0;

  Future<SendPort> _start() async {
    final ready = _ready = Completer<SendPort>();
    final messages = _messages = ReceivePort();
    final errors = _errors = ReceivePort();
    messages.listen((Object? value) {
      if (value is SendPort) {
        if (!ready.isCompleted) ready.complete(value);
      } else if (value == 'closed') {
        if (!_closed.isCompleted) _closed.complete();
      } else if (value case ['result', final int id, final Object? body]) {
        _pending.remove(id)?.complete(body);
      } else if (value case ['error', final int id, final String message]) {
        _pending.remove(id)?.completeError(StateError(message));
      } else if (value case [
        'unavailable',
        final int id,
        final String message,
      ]) {
        _pending
            .remove(id)
            ?.completeError(LanguageIdUnavailableException(message));
      } else if (value case ['unavailable', final String reason]) {
        _fail(LanguageIdUnavailableException(reason));
      } else if (value == null && !_disposed) {
        _fail(
          const LanguageIdUnavailableException(
            'The local language identifier stopped.',
          ),
        );
      }
    });
    errors.listen(
      (Object? _) => _fail(
        const LanguageIdUnavailableException(
          'The local language identifier failed to start or stopped.',
        ),
      ),
    );
    try {
      final results = await Future.wait<Object?>([
        ready.future,
        Isolate.spawn<List<Object?>>(
          _workerMain,
          [messages.sendPort, libraryPath],
          onError: errors.sendPort,
          onExit: messages.sendPort,
          errorsAreFatal: true,
          debugName: 'Quds language identifier',
        ).then((isolate) {
          if (_aborted) {
            isolate.kill(priority: Isolate.immediate);
          } else {
            _isolate = isolate;
          }
          return isolate;
        }),
      ], eagerError: true);
      return results.first! as SendPort;
    } on LanguageIdUnavailableException {
      rethrow;
    } on Object {
      const error = LanguageIdUnavailableException(
        'The local language identifier could not be started.',
      );
      _fail(error);
      throw error;
    }
  }

  void _fail(Object error) {
    _disposed = true;
    _aborted = true;
    final ready = _ready;
    if (ready != null && !ready.isCompleted) ready.completeError(error);
    for (final request in _pending.values) {
      request.completeError(error);
    }
    _pending.clear();
    if (!_closed.isCompleted) _closed.complete();
    _terminate();
  }

  void _terminate() {
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _messages?.close();
    _errors?.close();
  }

  Future<Object?> _send(List<Object?> message) async {
    if (_disposed) {
      throw const LanguageIdUnavailableException(
        'The language identifier is disposed.',
      );
    }
    final port = await (_opening ??= _start());
    if (_disposed) {
      throw const LanguageIdUnavailableException(
        'The language identifier is disposed.',
      );
    }
    final id = ++_sequence;
    final result = Completer<Object?>();
    _pending[id] = result;
    port.send([id, ...message]);
    return result.future;
  }

  @override
  Future<void> open(Uint8List model) async {
    await _send([
      'open',
      TransferableTypedData.fromList([model]),
    ]);
  }

  @override
  Future<List<List<(String, double)>>> detect(List<String> texts, int k) async {
    if (texts.isEmpty) return const [];
    final result = await _send(['detect', texts, k]);
    return [
      for (final lines in result! as List)
        parseLanguageIdLines(lines as String),
    ];
  }

  @override
  Future<void> dispose() => _disposal ??= _dispose();

  Future<void> _dispose() async {
    _disposed = true;
    const error = LanguageIdUnavailableException(
      'The language identifier was disposed.',
    );
    for (final request in _pending.values) {
      request.completeError(error);
    }
    _pending.clear();
    try {
      final opening = _opening;
      if (opening != null && !_aborted) {
        // Killing an isolate does not free allocations made by its native
        // library. Let queued native calls finish, then release the model and
        // buffers in their owning worker before acknowledging disposal.
        final port = await opening.timeout(const Duration(seconds: 2));
        port.send(['dispose']);
        await _closed.future.timeout(const Duration(seconds: 2));
      }
    } on Object {
      // A crashed or unresponsive worker still must not hold up app shutdown.
    } finally {
      _aborted = true;
      final ready = _ready;
      if (ready != null && !ready.isCompleted) ready.completeError(error);
      _terminate();
    }
  }
}

void _workerMain(List<Object?> arguments) {
  final host = arguments[0]! as SendPort;
  final input = ReceivePort();
  final _Bindings bindings;
  try {
    final configured = arguments[1] as String?;
    const defined = String.fromEnvironment('QUDS_LANGUAGE_ID_LIBRARY');
    final path =
        configured ?? (defined.isNotEmpty ? defined : languageIdLibraryName);
    bindings = _Bindings(DynamicLibrary.open(path));
  } on Object {
    input.close();
    host.send([
      'unavailable',
      'The local language identification library is missing or '
          'incompatible. Build and package it with tool/build.py.',
    ]);
    return;
  }
  host.send(input.sendPort);
  Pointer<Void> handle = nullptr;
  input.listen((Object? value) {
    if (value case ['dispose']) {
      try {
        if (handle != nullptr) bindings.close(handle);
      } finally {
        handle = nullptr;
        bindings.dispose();
        input.close();
        host.send('closed');
      }
      return;
    }
    if (value is! List || value.isEmpty || value.first is! int) return;
    final id = value.first as int;
    try {
      if (value case [_, 'open', final TransferableTypedData model]) {
        if (handle != nullptr) {
          bindings.close(handle);
          handle = nullptr;
        }
        final (opened, error) = bindings.open(
          model.materialize().asUint8List(),
        );
        if (opened == nullptr) {
          host.send([
            'unavailable',
            id,
            'The language model could not be opened: $error',
          ]);
          return;
        }
        handle = opened;
        host.send(['result', id, null]);
      } else if (value case [
        _,
        'detect',
        final List<Object?> texts,
        final int k,
      ]) {
        if (handle == nullptr) {
          host.send(['unavailable', id, 'The language model is not open.']);
          return;
        }
        host.send([
          'result',
          id,
          [
            for (final text in texts)
              bindings.detect(handle, text! as String, k),
          ],
        ]);
      }
    } on Object catch (error) {
      host.send(['error', id, 'Native language identification failed: $error']);
    }
  });
}

const _outCapacity = 1024;
const _errorCapacity = 256;

final class _Bindings {
  _Bindings(DynamicLibrary library)
    : _open = library
          .lookupFunction<
            Pointer<Void> Function(Pointer<Uint8>, Size, Pointer<Uint8>, Size),
            Pointer<Void> Function(Pointer<Uint8>, int, Pointer<Uint8>, int)
          >('quds_language_id_open'),
      close = library
          .lookupFunction<
            Void Function(Pointer<Void>),
            void Function(Pointer<Void>)
          >('quds_language_id_close'),
      _detect = library
          .lookupFunction<
            Int32 Function(
              Pointer<Void>,
              Pointer<Uint8>,
              Size,
              Int32,
              Pointer<Uint8>,
              Size,
            ),
            int Function(
              Pointer<Void>,
              Pointer<Uint8>,
              int,
              int,
              Pointer<Uint8>,
              int,
            )
          >('quds_language_id_detect'),
      _malloc = library
          .lookupFunction<
            Pointer<Uint8> Function(Size),
            Pointer<Uint8> Function(int)
          >('quds_language_id_alloc'),
      _free = library
          .lookupFunction<
            Void Function(Pointer<Uint8>),
            void Function(Pointer<Uint8>)
          >('quds_language_id_free_buffer') {
    final abi = library.lookupFunction<Uint32 Function(), int Function()>(
      'quds_language_id_abi_version',
    );
    if (abi() != 1) throw StateError('Unsupported language identifier ABI.');
    try {
      _out = _allocate(_outCapacity);
      _error = _allocate(_errorCapacity);
      _text = _allocate(_textCapacity);
    } on Object {
      dispose();
      rethrow;
    }
  }

  final Pointer<Void> Function(Pointer<Uint8>, int, Pointer<Uint8>, int) _open;
  final void Function(Pointer<Void>) close;
  final int Function(
    Pointer<Void>,
    Pointer<Uint8>,
    int,
    int,
    Pointer<Uint8>,
    int,
  )
  _detect;
  final Pointer<Uint8> Function(int) _malloc;
  final void Function(Pointer<Uint8>) _free;

  // Buffers owned for the isolate's lifetime (one classifier per isolate).
  Pointer<Uint8> _out = nullptr;
  Pointer<Uint8> _error = nullptr;
  Pointer<Uint8> _text = nullptr;
  int _textCapacity = 4096;

  void dispose() {
    for (final buffer in [_out, _error, _text]) {
      if (buffer != nullptr) _free(buffer);
    }
    _out = _error = _text = nullptr;
  }

  Pointer<Uint8> _allocate(int bytes) {
    final pointer = _malloc(bytes);
    if (pointer == nullptr) throw StateError('Out of memory.');
    return pointer;
  }

  static String _cString(Pointer<Uint8> pointer, int limit) {
    var length = 0;
    while (length < limit && pointer[length] != 0) {
      length++;
    }
    return utf8.decode(pointer.asTypedList(length), allowMalformed: true);
  }

  (Pointer<Void>, String) open(Uint8List model) {
    final bytes = _allocate(model.length);
    try {
      bytes.asTypedList(model.length).setAll(0, model);
      _error[0] = 0;
      final handle = _open(bytes, model.length, _error, _errorCapacity);
      return (handle, _cString(_error, _errorCapacity));
    } finally {
      _free(bytes);
    }
  }

  /// The adapter's result lines for [text].
  String detect(Pointer<Void> handle, String text, int k) {
    final bytes = utf8.encode(text);
    if (bytes.length > _textCapacity) {
      final replacement = _allocate(bytes.length);
      _free(_text);
      _textCapacity = bytes.length;
      _text = replacement;
    }
    _text.asTypedList(_textCapacity).setAll(0, bytes);
    _out[0] = 0;
    final n = _detect(handle, _text, bytes.length, k, _out, _outCapacity);
    if (n < 0) throw StateError('classification failed');
    return _cString(_out, _outCapacity);
  }
}
