import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'hunspell_catalog.dart';
import 'hunspell_transport.dart';

HunspellTransport createHunspellTransport({
  String? nativeLibraryPath,
  Uri? workerUrl,
}) => _NativeTransport(nativeLibraryPath);

/// Owns a persistent isolate holding the native engine handle, so dictionary
/// loading and checks never block the UI isolate.
final class _NativeTransport implements HunspellTransport {
  _NativeTransport(this.libraryPath);
  final String? libraryPath;
  final _pending = <int, Completer<String>>{};
  Isolate? _isolate;
  ReceivePort? _messages;
  ReceivePort? _errors;
  SendPort? _workerPort;
  Future<SendPort>? _opening;
  Completer<SendPort>? _ready;
  Completer<void>? _closed;
  Future<void>? _disposal;
  bool _disposed = false;
  int _sequence = 0;

  Future<SendPort> _start() async {
    final ready = _ready = Completer<SendPort>();
    final messages = _messages = ReceivePort();
    final errors = _errors = ReceivePort();
    messages.listen((Object? value) {
      if (value is SendPort) {
        if (_disposed) return;
        _workerPort = value;
        if (!ready.isCompleted) ready.complete(value);
      } else if (value == 'closed') {
        final closed = _closed;
        if (closed != null && !closed.isCompleted) closed.complete();
      } else if (value case ['result', final int id, final String body]) {
        _pending.remove(id)?.complete(body);
      } else if (value case ['unavailable', final String reason]) {
        _fail(HunspellUnavailableException(reason));
      } else if (value == null && !_disposed) {
        _fail(
          const HunspellUnavailableException(
            'The local Hunspell worker stopped.',
          ),
        );
      }
    });
    errors.listen(
      (Object? _) => _fail(
        const HunspellUnavailableException(
          'The local Hunspell worker failed to start or stopped.',
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
          debugName: 'Quds Hunspell',
        ).then((isolate) {
          if (_disposed) {
            isolate.kill(priority: Isolate.immediate);
          } else {
            _isolate = isolate;
          }
          return isolate;
        }),
      ], eagerError: true);
      return results.first! as SendPort;
    } on HunspellUnavailableException catch (error) {
      _fail(error);
      rethrow;
    } on Object {
      const error = HunspellUnavailableException(
        'The local Hunspell worker could not be started.',
      );
      _fail(error);
      throw error;
    }
  }

  void _fail(Object error) {
    _disposed = true;
    _cancelRequests(error);
    final closed = _closed;
    if (closed != null && !closed.isCompleted) closed.completeError(error);
    _terminate();
  }

  void _cancelRequests(Object error) {
    final ready = _ready;
    if (ready != null && !ready.isCompleted) ready.completeError(error);
    for (final request in _pending.values) {
      request.completeError(error);
    }
    _pending.clear();
  }

  void _terminate() {
    // Let an active FFI call return and attach its native owner before exit.
    // Immediate termination between open() and attachment can lose a handle.
    _isolate?.kill(priority: Isolate.beforeNextEvent);
    _isolate = null;
    _workerPort = null;
    _messages?.close();
    _errors?.close();
  }

  Future<String> _send(List<Object?> message) async {
    if (_disposed) {
      throw const HunspellUnavailableException('Hunspell worker is disposed.');
    }
    final port = await (_opening ??= _start());
    if (_disposed) {
      throw const HunspellUnavailableException('Hunspell worker is disposed.');
    }
    final id = ++_sequence;
    final result = Completer<String>();
    _pending[id] = result;
    port.send([id, ...message]);
    return result.future;
  }

  @override
  Future<void> open(HunspellDictionary dictionary) async {
    if (dictionary is! HunspellDictionaryFiles) {
      throw const HunspellUnavailableException(
        'The native Hunspell worker opens downloaded dictionary files.',
      );
    }
    final body = await _send(['open', dictionary.affPath, dictionary.dicPath]);
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, Object?> || decoded['status'] != 'success') {
      throw HunspellUnavailableException(
        decoded is Map<String, Object?> && decoded['message'] is String
            ? decoded['message']! as String
            : 'The dictionary could not be opened.',
      );
    }
  }

  @override
  Future<String> check(List<String> words, List<bool> suggest) =>
      _send(['check', words, suggest]);

  @override
  Future<void> dispose() => _disposal ??= _dispose();

  Future<void> _dispose() async {
    if (_disposed) return;
    _disposed = true;
    _cancelRequests(
      const HunspellUnavailableException('Hunspell worker was disposed.'),
    );
    final port = _workerPort;
    if (port == null) {
      // No operation can be submitted before startup supplies this port.
      // A spawn still in flight observes _disposed and kills its late isolate.
      _terminate();
      return;
    }
    final closed = _closed = Completer<void>();
    port.send(['dispose']);
    try {
      // The worker serializes this close after any native call already running.
      // Do not free its handle concurrently with that call.
      await closed.future.timeout(const Duration(seconds: 2));
    } on Object {
      // A stuck or failed worker has a native-finalizer fallback. Forced
      // termination cannot promise immediate destruction of an active C call.
    } finally {
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
    const defined = String.fromEnvironment('QUDS_HUNSPELL_LIBRARY');
    final path =
        configured ??
        (defined.isNotEmpty
            ? defined
            : (Platform.isWindows
                  ? 'quds_proofing_hunspell.dll'
                  // iOS apps embed the library as a signed framework.
                  : Platform.isIOS
                  ? 'quds_proofing_hunspell.framework/quds_proofing_hunspell'
                  : Platform.isMacOS
                  ? 'libquds_proofing_hunspell.dylib'
                  : 'libquds_proofing_hunspell.so'));
    bindings = _Bindings(DynamicLibrary.open(path));
  } on Object {
    input.close();
    host.send([
      'unavailable',
      'Local Hunspell native library is missing or incompatible. Build and package the optional backend.',
    ]);
    return;
  }
  host.send(input.sendPort);
  _OwnedHandle? handle;
  input.listen((Object? value) {
    String reply;
    try {
      if (value case ['dispose']) {
        handle?.close();
        handle = null;
        input.close();
        host.send('closed');
      } else if (value case [
        final int id,
        'open',
        final String aff,
        final String dic,
      ]) {
        handle?.close();
        handle = null;
        final pointer = bindings.open(aff, dic);
        if (pointer != nullptr) handle = _OwnedHandle(bindings, pointer);
        reply = jsonEncode(
          handle == null
              ? {
                  'status': 'failed',
                  'message':
                      'The dictionary could not be opened (UTF-8 .aff/.dic required).',
                }
              : {'status': 'success'},
        );
        host.send(['result', id, reply]);
      } else if (value case [
        final int id,
        'check',
        final List<Object?> words,
        final List<Object?> suggest,
      ]) {
        final owned = handle;
        if (owned == null) {
          host.send([
            'result',
            id,
            jsonEncode({
              'status': 'unavailable',
              'message': 'No Hunspell dictionary is open.',
            }),
          ]);
          return;
        }
        final results = <Object?>[];
        for (var i = 0; i < words.length; i++) {
          final word = words[i]! as String;
          final state = owned.spell(word);
          if (state < 0) throw StateError('Hunspell rejected a word.');
          if (state == 1) {
            results.add({'ok': true});
          } else {
            results.add({
              'ok': false,
              'suggestions': suggest[i] == true
                  ? owned.suggest(word)
                  : const <String>[],
            });
          }
        }
        host.send([
          'result',
          id,
          jsonEncode({'status': 'success', 'results': results}),
        ]);
      }
    } on Object catch (error) {
      if (value case [final int id, ...]) {
        host.send([
          'result',
          id,
          jsonEncode({
            'status': 'failed',
            'message': 'Native Hunspell check failed: $error',
          }),
        ]);
      }
    }
  });
}

/// Keeps native memory owned across FFI calls and exceptional worker shutdown.
/// Normal shutdown closes explicitly; finalization is only a fallback.
final class _OwnedHandle implements Finalizable {
  _OwnedHandle(this._bindings, this._pointer) {
    _bindings.finalizer.attach(this, _pointer, detach: this);
  }

  final _Bindings _bindings;
  Pointer<Void> _pointer;

  int spell(String word) => _bindings.spell(_pointer, word);
  List<String> suggest(String word) => _bindings.suggest(_pointer, word);

  void close() {
    final pointer = _pointer;
    if (pointer == nullptr) return;
    _pointer = nullptr;
    _bindings.finalizer.detach(this);
    _bindings.close(pointer);
  }
}

final class _Bindings {
  _Bindings(DynamicLibrary library)
    : _open = library
          .lookupFunction<
            Pointer<Void> Function(Pointer<Uint8>, Pointer<Uint8>),
            Pointer<Void> Function(Pointer<Uint8>, Pointer<Uint8>)
          >('quds_hunspell_open'),
      close = library
          .lookupFunction<
            Void Function(Pointer<Void>),
            void Function(Pointer<Void>)
          >('quds_hunspell_close'),
      _closeAddress = library.lookup<NativeFinalizerFunction>(
        'quds_hunspell_close',
      ),
      _spell = library
          .lookupFunction<
            Int32 Function(Pointer<Void>, Pointer<Uint8>),
            int Function(Pointer<Void>, Pointer<Uint8>)
          >('quds_hunspell_spell'),
      _suggest = library
          .lookupFunction<
            Pointer<Uint8> Function(
              Pointer<Void>,
              Pointer<Uint8>,
              Pointer<Size>,
            ),
            Pointer<Uint8> Function(
              Pointer<Void>,
              Pointer<Uint8>,
              Pointer<Size>,
            )
          >('quds_hunspell_suggest'),
      _malloc = library
          .lookupFunction<
            Pointer<Uint8> Function(Size),
            Pointer<Uint8> Function(int)
          >('quds_hunspell_alloc'),
      _free = library
          .lookupFunction<
            Void Function(Pointer<Uint8>),
            void Function(Pointer<Uint8>)
          >('quds_hunspell_free') {
    final version = library.lookupFunction<Uint32 Function(), int Function()>(
      'quds_hunspell_abi_version',
    );
    if (version() != 1) throw StateError('Unsupported Hunspell ABI.');
  }

  final Pointer<Void> Function(Pointer<Uint8>, Pointer<Uint8>) _open;
  final void Function(Pointer<Void>) close;
  final Pointer<NativeFinalizerFunction> _closeAddress;
  // A finalizer must remain reachable independently of its finalizable owners.
  // Distinct host libraries may export different implementations of this ABI.
  static final _finalizers = <int, NativeFinalizer>{};
  late final NativeFinalizer finalizer = _finalizers.putIfAbsent(
    _closeAddress.address,
    () => NativeFinalizer(_closeAddress),
  );
  final int Function(Pointer<Void>, Pointer<Uint8>) _spell;
  final Pointer<Uint8> Function(Pointer<Void>, Pointer<Uint8>, Pointer<Size>)
  _suggest;
  final Pointer<Uint8> Function(int) _malloc;
  final void Function(Pointer<Uint8>) _free;

  T _withString<T>(String text, T Function(Pointer<Uint8>) body) {
    final bytes = utf8.encode(text);
    final pointer = _malloc(bytes.length + 1);
    if (pointer == nullptr) throw StateError('Out of memory.');
    try {
      final view = pointer.asTypedList(bytes.length + 1);
      view.setAll(0, bytes);
      view[bytes.length] = 0;
      return body(pointer);
    } finally {
      _free(pointer);
    }
  }

  Pointer<Void> open(String aff, String dic) {
    // An existing affix file without its dictionary can create an empty engine.
    // Admit neither missing input as a usable spelling backend.
    if (!File(aff).existsSync() || !File(dic).existsSync()) return nullptr;
    return _withString(aff, (a) => _withString(dic, (d) => _open(a, d)));
  }

  int spell(Pointer<Void> handle, String word) =>
      _withString(word, (w) => _spell(handle, w));

  List<String> suggest(Pointer<Void> handle, String word) =>
      _withString(word, (w) {
        final length = _malloc(sizeOf<Size>()).cast<Size>();
        try {
          final output = _suggest(handle, w, length);
          if (output == nullptr) throw StateError('Suggestion failed.');
          final size = length.value;
          if (size == 0) return const <String>[];
          return utf8.decode(output.asTypedList(size)).split('\n');
        } finally {
          _free(length.cast());
        }
      });
}
