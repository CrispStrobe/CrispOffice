import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'harper_transport.dart';

HarperTransport createHarperTransport({
  String? nativeLibraryPath,
  Uri? workerUrl,
}) => _NativeTransport(nativeLibraryPath);

final class _NativeTransport implements HarperTransport {
  _NativeTransport(this.libraryPath);
  final String? libraryPath;
  final _pending = <int, Completer<String>>{};
  Isolate? _isolate;
  ReceivePort? _messages;
  ReceivePort? _errors;
  Future<SendPort>? _opening;
  Completer<SendPort>? _ready;
  bool _disposed = false;
  int _sequence = 0;

  Future<SendPort> _open() async {
    final ready = _ready = Completer<SendPort>();
    final messages = _messages = ReceivePort();
    final errors = _errors = ReceivePort();
    messages.listen((Object? value) {
      if (value is SendPort) {
        if (!ready.isCompleted) ready.complete(value);
      } else if (value case ['result', final int id, final String body]) {
        _pending.remove(id)?.complete(body);
      } else if (value case ['unavailable', final String reason]) {
        _fail(HarperUnavailableException(reason));
      } else if (value == null && !_disposed) {
        _fail(
          const HarperUnavailableException('The local Harper worker stopped.'),
        );
      }
    });
    errors.listen((Object? value) {
      _fail(
        const HarperUnavailableException(
          'The local Harper worker failed to start or stopped.',
        ),
      );
    });
    try {
      final results = await Future.wait<Object?>(
        [
          ready.future,
          Isolate.spawn<List<Object?>>(
            _workerMain,
            [messages.sendPort, libraryPath],
            onError: errors.sendPort,
            onExit: messages.sendPort,
            errorsAreFatal: true,
            debugName: 'Quds Harper',
          ).then((isolate) {
            if (_disposed) {
              isolate.kill(priority: Isolate.immediate);
            } else {
              _isolate = isolate;
            }
            return isolate;
          }),
        ],
        // If spawning itself fails there can never be a ready message.
        eagerError: true,
      );
      return results.first! as SendPort;
    } on Object {
      await dispose();
      rethrow;
    }
  }

  void _fail(Object error) {
    // Once an isolate fails, its old SendPort cannot accept more work. Close
    // the transport immediately so later checks report unavailable, not a
    // second timeout against a dead port.
    _disposed = true;
    final ready = _ready;
    if (ready != null && !ready.isCompleted) ready.completeError(error);
    for (final request in _pending.values) {
      request.completeError(error);
    }
    _pending.clear();
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _messages?.close();
    _errors?.close();
  }

  @override
  Future<String> check(String request) async {
    if (_disposed)
      throw const HarperUnavailableException('Harper worker is disposed.');
    final port = await (_opening ??= _open());
    if (_disposed)
      throw const HarperUnavailableException('Harper worker is disposed.');
    final id = ++_sequence;
    final result = Completer<String>();
    _pending[id] = result;
    port.send([id, request]);
    return result.future;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _fail(const HarperUnavailableException('Harper worker was disposed.'));
  }
}

void _workerMain(List<Object?> arguments) {
  final host = arguments[0]! as SendPort;
  final input = ReceivePort();
  try {
    final configured = arguments[1] as String?;
    const defined = String.fromEnvironment('QUDS_HARPER_LIBRARY');
    final path =
        configured ??
        (defined.isNotEmpty
            ? defined
            : (Platform.isWindows
                  ? 'quds_proofing_harper.dll'
                  : Platform.isMacOS
                  ? 'libquds_proofing_harper.dylib'
                  : 'libquds_proofing_harper.so'));
    final bindings = _Bindings(DynamicLibrary.open(path));
    host.send(input.sendPort);
    input.listen((Object? value) {
      if (value case [final int id, final String request]) {
        try {
          host.send(['result', id, bindings.check(request)]);
        } on Object {
          host.send([
            'result',
            id,
            jsonEncode({
              'status': 'failed',
              'offsets': 'unicode-scalar',
              'findings': <Object?>[],
              'message': 'Native Harper check failed.',
            }),
          ]);
        }
      }
    });
  } on Object {
    input.close();
    host.send([
      'unavailable',
      'Local Harper native library is missing or incompatible. Build and configure the optional backend.',
    ]);
  }
}

final class _Bindings {
  _Bindings(DynamicLibrary library)
    : _alloc = library
          .lookupFunction<
            Pointer<Uint8> Function(UintPtr),
            Pointer<Uint8> Function(int)
          >('quds_harper_alloc'),
      _free = library
          .lookupFunction<
            Void Function(Pointer<Uint8>, UintPtr),
            void Function(Pointer<Uint8>, int)
          >('quds_harper_dealloc'),
      _check = library
          .lookupFunction<
            Pointer<Uint8> Function(Pointer<Uint8>, UintPtr),
            Pointer<Uint8> Function(Pointer<Uint8>, int)
          >('quds_harper_check'),
      _length = library.lookupFunction<UintPtr Function(), int Function()>(
        'quds_harper_result_len',
      ) {
    final version = library.lookupFunction<Uint32 Function(), int Function()>(
      'quds_harper_abi_version',
    );
    if (version() != 1) throw StateError('Unsupported Harper ABI.');
  }
  final Pointer<Uint8> Function(int) _alloc;
  final void Function(Pointer<Uint8>, int) _free;
  final Pointer<Uint8> Function(Pointer<Uint8>, int) _check;
  final int Function() _length;

  String check(String request) {
    final bytes = utf8.encode(request);
    final pointer = _alloc(bytes.length);
    if (pointer == nullptr)
      throw StateError('Harper request exceeds its size limit.');
    try {
      pointer.asTypedList(bytes.length).setAll(0, bytes);
      final output = _check(pointer, bytes.length);
      final length = _length();
      if (output == nullptr || length < 1 || length > 16 * 1024 * 1024)
        throw StateError('Invalid Harper response buffer.');
      return utf8.decode(output.asTypedList(length));
    } finally {
      _free(pointer, bytes.length);
    }
  }
}
