import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:quds_office_engine/quds_office_engine.dart';

import 'morph_analysis.dart';
import 'morph_catalog.dart';
import 'morph_transport.dart';

ArabicMorphTransport createArabicMorphTransport({
  String? nativeLibraryPath,
  Uri? workerUrl,
}) => _NativeTransport(nativeLibraryPath);

/// Default library file name for this platform.
String get arabicMorphLibraryName => Platform.isWindows
    ? 'quds_arabic_morph.dll'
    : Platform.isMacOS || Platform.isIOS
    ? 'libquds_arabic_morph.dylib'
    : 'libquds_arabic_morph.so';

/// Owns a persistent isolate holding the native analyzer, so database
/// loading (about 1.5 s) and analysis never block the UI isolate. Analyses
/// are decoded into compact maps inside the worker isolate.
final class _NativeTransport implements ArabicMorphTransport {
  _NativeTransport(this.libraryPath);
  final String? libraryPath;
  final _pending = <int, Completer<Object?>>{};
  Isolate? _isolate;
  ReceivePort? _messages;
  ReceivePort? _errors;
  Future<SendPort>? _opening;
  Completer<SendPort>? _ready;
  bool _disposed = false;
  int _sequence = 0;

  Future<SendPort> _start() async {
    final ready = _ready = Completer<SendPort>();
    final messages = _messages = ReceivePort();
    final errors = _errors = ReceivePort();
    messages.listen((Object? value) {
      if (value is SendPort) {
        if (!ready.isCompleted) ready.complete(value);
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
            ?.completeError(ArabicMorphUnavailableException(message));
      } else if (value case ['unavailable', final String reason]) {
        _fail(ArabicMorphUnavailableException(reason));
      } else if (value == null && !_disposed) {
        _fail(
          const ArabicMorphUnavailableException(
            'The local Arabic morphology worker stopped.',
          ),
        );
      }
    });
    errors.listen(
      (Object? _) => _fail(
        const ArabicMorphUnavailableException(
          'The local Arabic morphology worker failed to start or stopped.',
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
          debugName: 'Quds Arabic morphology',
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
    } on ArabicMorphUnavailableException {
      await dispose();
      rethrow;
    } on Object {
      await dispose();
      throw const ArabicMorphUnavailableException(
        'The local Arabic morphology worker could not be started.',
      );
    }
  }

  void _fail(Object error) {
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

  Future<Object?> _send(List<Object?> message) async {
    if (_disposed) {
      throw const ArabicMorphUnavailableException(
        'Arabic morphology worker is disposed.',
      );
    }
    final port = await (_opening ??= _start());
    if (_disposed) {
      throw const ArabicMorphUnavailableException(
        'Arabic morphology worker is disposed.',
      );
    }
    final id = ++_sequence;
    final result = Completer<Object?>();
    _pending[id] = result;
    port.send([id, ...message]);
    return result.future;
  }

  @override
  Future<Map<String, Object?>> open(MorphDatabase database) async {
    if (database is! MorphDatabaseFiles) {
      throw const ArabicMorphUnavailableException(
        'The native Arabic morphology worker opens an installed bundle.',
      );
    }
    final info = await _send([
      'open',
      database.manifestPath,
      database.bundle.manifest.sha256,
    ]);
    return (jsonDecode(info! as String) as Map).cast<String, Object?>();
  }

  @override
  Future<List<List<ArabicAnalysis>?>> analyze(List<String> words) async {
    if (words.isEmpty) return const [];
    final result = await _send(['analyze', words]);
    return (result! as List).cast<List<ArabicAnalysis>?>();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _fail(
      const ArabicMorphUnavailableException(
        'Arabic morphology worker was disposed.',
      ),
    );
  }
}

void _workerMain(List<Object?> arguments) {
  final host = arguments[0]! as SendPort;
  final input = ReceivePort();
  final _Bindings bindings;
  try {
    final configured = arguments[1] as String?;
    const defined = String.fromEnvironment('QUDS_ARABIC_MORPH_LIBRARY');
    final path =
        configured ?? (defined.isNotEmpty ? defined : arabicMorphLibraryName);
    bindings = _Bindings(DynamicLibrary.open(path));
  } on Object {
    input.close();
    host.send([
      'unavailable',
      'The local Arabic morphology library is missing or incompatible. '
          'Build and package the optional backend.',
    ]);
    return;
  }
  host.send(input.sendPort);
  final decoder = ArabicAnalysisDecoder();
  Pointer<Void> handle = nullptr;
  input.listen((Object? value) {
    if (value is! List || value.isEmpty || value.first is! int) return;
    final id = value.first as int;
    try {
      if (value case [
        _,
        'open',
        final String manifest,
        final String manifestSha256,
      ]) {
        if (handle != nullptr) {
          bindings.free(handle);
          handle = nullptr;
        }
        final (opened, error) = bindings.open(manifest, manifestSha256);
        if (opened == nullptr) {
          host.send([
            'unavailable',
            id,
            'The morphology database could not be opened: $error',
          ]);
          return;
        }
        handle = opened;
        host.send(['result', id, bindings.info(handle)]);
      } else if (value case [_, 'analyze', final List<Object?> words]) {
        if (handle == nullptr) {
          host.send([
            'unavailable',
            id,
            'No Arabic morphology database is open.',
          ]);
          return;
        }
        final results = <List<ArabicAnalysis>?>[];
        for (final word in words) {
          final json = bindings.analyze(handle, word! as String);
          results.add(json == null ? null : decoder.decode(jsonDecode(json)));
        }
        host.send(['result', id, results]);
      }
    } on Object catch (error) {
      host.send(['error', id, 'Native Arabic morphology failed: $error']);
    }
  });
}

const _inputError = 5;
const _maxWordBytes = 4096;
const _errorCapacity = 512;

final class _Bindings {
  _Bindings(DynamicLibrary library)
    : _open = library
          .lookupFunction<
            Pointer<Void> Function(
              Pointer<Uint8>,
              Pointer<Uint8>,
              Int32,
              Pointer<Uint8>,
              Size,
            ),
            Pointer<Void> Function(
              Pointer<Uint8>,
              Pointer<Uint8>,
              int,
              Pointer<Uint8>,
              int,
            )
          >('crispembed_ar_morph_open'),
      _analyze = library
          .lookupFunction<
            Int32 Function(
              Pointer<Void>,
              Pointer<Uint8>,
              Size,
              Pointer<Pointer<Uint8>>,
              Pointer<Size>,
              Pointer<Uint8>,
              Size,
            ),
            int Function(
              Pointer<Void>,
              Pointer<Uint8>,
              int,
              Pointer<Pointer<Uint8>>,
              Pointer<Size>,
              Pointer<Uint8>,
              int,
            )
          >('crispembed_ar_morph_analyze'),
      _stringFree = library
          .lookupFunction<
            Void Function(Pointer<Uint8>),
            void Function(Pointer<Uint8>)
          >('crispembed_ar_morph_string_free'),
      _info = library
          .lookupFunction<
            Pointer<Uint8> Function(Pointer<Void>),
            Pointer<Uint8> Function(Pointer<Void>)
          >('crispembed_ar_morph_info'),
      free = library
          .lookupFunction<
            Void Function(Pointer<Void>),
            void Function(Pointer<Void>)
          >('crispembed_ar_morph_free'),
      _malloc = library
          .lookupFunction<
            Pointer<Uint8> Function(Size),
            Pointer<Uint8> Function(int)
          >('quds_arabic_morph_alloc'),
      _free = library
          .lookupFunction<
            Void Function(Pointer<Uint8>),
            void Function(Pointer<Uint8>)
          >('quds_arabic_morph_free') {
    final abi = library.lookupFunction<Uint32 Function(), int Function()>(
      'crispembed_ar_morph_abi_version',
    );
    final adapter = library.lookupFunction<Uint32 Function(), int Function()>(
      'quds_arabic_morph_adapter_version',
    );
    if (abi() != 1 || adapter() != 1) {
      throw StateError('Unsupported Arabic morphology ABI.');
    }
    _word = _allocate(_maxWordBytes + 1);
    _error = _allocate(_errorCapacity);
    _json = _allocate(sizeOf<Pointer<Uint8>>()).cast();
    _jsonLength = _allocate(sizeOf<Size>()).cast();
  }

  final Pointer<Void> Function(
    Pointer<Uint8>,
    Pointer<Uint8>,
    int,
    Pointer<Uint8>,
    int,
  )
  _open;
  final int Function(
    Pointer<Void>,
    Pointer<Uint8>,
    int,
    Pointer<Pointer<Uint8>>,
    Pointer<Size>,
    Pointer<Uint8>,
    int,
  )
  _analyze;
  final void Function(Pointer<Uint8>) _stringFree;
  final Pointer<Uint8> Function(Pointer<Void>) _info;
  final void Function(Pointer<Void>) free;
  final Pointer<Uint8> Function(int) _malloc;
  final void Function(Pointer<Uint8>) _free;

  // Buffers owned for the isolate's lifetime (one analyzer per isolate).
  late final Pointer<Uint8> _word;
  late final Pointer<Uint8> _error;
  late final Pointer<Pointer<Uint8>> _json;
  late final Pointer<Size> _jsonLength;

  Pointer<Uint8> _allocate(int bytes) {
    final pointer = _malloc(bytes);
    if (pointer == nullptr) throw StateError('Out of memory.');
    return pointer;
  }

  T _withString<T>(String text, T Function(Pointer<Uint8>) body) {
    final bytes = utf8.encode(text);
    final pointer = _allocate(bytes.length + 1);
    try {
      final view = pointer.asTypedList(bytes.length + 1);
      view.setAll(0, bytes);
      view[bytes.length] = 0;
      return body(pointer);
    } finally {
      _free(pointer);
    }
  }

  static String _cString(Pointer<Uint8> pointer, [int limit = 1 << 20]) {
    var length = 0;
    while (length < limit && pointer[length] != 0) {
      length++;
    }
    return utf8.decode(pointer.asTypedList(length), allowMalformed: true);
  }

  (Pointer<Void>, String) open(String manifest, String manifestSha256) {
    _error[0] = 0;
    final handle = _withString(
      manifest,
      (m) => _withString(
        manifestSha256,
        (s) => _open(m, s, 0, _error, _errorCapacity),
      ),
    );
    return (handle, _cString(_error, _errorCapacity));
  }

  String info(Pointer<Void> handle) => _cString(_info(handle));

  /// The JSON analyses of [word], or null when the analyzer rejects it as
  /// input. Other failures throw.
  String? analyze(Pointer<Void> handle, String word) {
    final bytes = utf8.encode(word);
    if (bytes.length > _maxWordBytes) return null;
    _word.asTypedList(bytes.length).setAll(0, bytes);
    _error[0] = 0;
    final status = _analyze(
      handle,
      _word,
      bytes.length,
      _json,
      _jsonLength,
      _error,
      _errorCapacity,
    );
    if (status == _inputError) return null;
    if (status != 0) {
      throw StateError(
        'analysis failed ($status): ${_cString(_error, _errorCapacity)}',
      );
    }
    final json = _json.value;
    try {
      return utf8.decode(json.asTypedList(_jsonLength.value));
    } finally {
      _stringFree(json);
    }
  }
}
