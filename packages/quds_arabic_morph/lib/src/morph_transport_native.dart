import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

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
/// loading and analysis never block the UI isolate. The isolate calls the
/// compact batch ABI (no JSON) and transfers each batch's buffer; this side
/// keeps per-word records and reads features from them on demand.
final class _NativeTransport implements ArabicMorphTransport {
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
  CompactAnalysisDecoder? _decoder;

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
          if (_aborted) {
            isolate.kill(priority: Isolate.immediate);
          } else {
            _isolate = isolate;
          }
          return isolate;
        }),
      ], eagerError: true);
      return results.first! as SendPort;
    } on ArabicMorphUnavailableException {
      rethrow;
    } on Object {
      const error = ArabicMorphUnavailableException(
        'The local Arabic morphology worker could not be started.',
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
    final decoded = (jsonDecode(info! as String) as Map)
        .cast<String, Object?>();
    _decoder = CompactAnalysisDecoder(
      (decoded['keys']! as List).cast<String>(),
    );
    return decoded;
  }

  @override
  Future<List<List<ArabicAnalysis>?>> analyze(List<String> words) async {
    if (words.isEmpty) return const [];
    final result = await _send(['analyze', words]);
    final decoder = _decoder;
    if (decoder == null) {
      throw const ArabicMorphUnavailableException(
        'No Arabic morphology database is open.',
      );
    }
    final bytes = (result! as TransferableTypedData)
        .materialize()
        .asUint8List();
    return decoder.decode(bytes, words.length);
  }

  @override
  Future<Map<String, Object?>> openDisambiguator(MorphDatabase model) async {
    if (model is! MorphDatabaseFiles) {
      throw const ArabicMorphUnavailableException(
        'The native Arabic morphology worker opens an installed bundle.',
      );
    }
    final info = await _send([
      'open_model',
      model.manifestPath,
      model.bundle.manifest.sha256,
    ]);
    return (jsonDecode(info! as String) as Map).cast<String, Object?>();
  }

  @override
  Future<List<List<ArabicContextReading>>> disambiguate(
    List<List<String>> sentences,
  ) async {
    if (sentences.isEmpty) return const [];
    final words = [for (final s in sentences) ...s];
    final result = await _send([
      'disambiguate',
      words,
      [for (final s in sentences) s.length],
    ]);
    final decoder = _decoder;
    if (decoder == null) {
      throw const ArabicMorphUnavailableException(
        'No Arabic morphology database is open.',
      );
    }
    final bytes = (result! as TransferableTypedData)
        .materialize()
        .asUint8List();
    final readings = decoder.decodeReadings(bytes, words.length);
    final out = <List<ArabicContextReading>>[];
    var at = 0;
    for (final s in sentences) {
      out.add(readings.sublist(at, at + s.length));
      at += s.length;
    }
    return out;
  }

  @override
  Future<void> dispose() => _disposal ??= _dispose();

  Future<void> _dispose() async {
    _disposed = true;
    const error = ArabicMorphUnavailableException(
      'Arabic morphology worker was disposed.',
    );
    for (final request in _pending.values) {
      request.completeError(error);
    }
    _pending.clear();
    try {
      final opening = _opening;
      if (opening != null && !_aborted) {
        // Native allocations and file mappings survive a killed isolate.
        // Let queued calls finish, then free them in their owning worker.
        final port = await opening.timeout(const Duration(seconds: 2));
        port.send(['dispose']);
        await _closed.future.timeout(const Duration(seconds: 2));
      }
    } on Object {
      // A crashed or unresponsive worker must not hold up app shutdown.
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
  Pointer<Void> handle = nullptr;
  Pointer<Void> model = nullptr;
  input.listen((Object? value) {
    if (value case ['dispose']) {
      try {
        if (model != nullptr) bindings.modelFree(model);
        if (handle != nullptr) bindings.free(handle);
      } finally {
        model = nullptr;
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
      } else if (value case [
        _,
        'open_model',
        final String manifest,
        final String manifestSha256,
      ]) {
        if (model != nullptr) {
          bindings.modelFree(model);
          model = nullptr;
        }
        final (opened, error) = bindings.openModel(manifest, manifestSha256);
        if (opened == nullptr) {
          host.send([
            'error',
            id,
            'The disambiguation model could not be opened: $error',
          ]);
          return;
        }
        model = opened;
        host.send(['result', id, bindings.modelInfo(model)]);
      } else if (value case [
        _,
        'disambiguate',
        final List<Object?> words,
        final List<Object?> lengths,
      ]) {
        if (handle == nullptr || model == nullptr) {
          host.send([
            'error',
            id,
            'No Arabic morphology database or disambiguation model is open.',
          ]);
          return;
        }
        final bytes = bindings.disambiguate(
          handle,
          model,
          words.cast<String>(),
          lengths.cast<int>(),
        );
        host.send([
          'result',
          id,
          TransferableTypedData.fromList([bytes]),
        ]);
      } else if (value case [_, 'analyze', final List<Object?> words]) {
        if (handle == nullptr) {
          host.send([
            'unavailable',
            id,
            'No Arabic morphology database is open.',
          ]);
          return;
        }
        final parts = bindings.analyzeCompact(handle, words.cast<String>());
        host.send(['result', id, TransferableTypedData.fromList(parts)]);
      }
    } on Object catch (error) {
      host.send(['error', id, 'Native Arabic morphology failed: $error']);
    }
  });
}

const _errorCapacity = 512;
const _compactMagic = 0x31434D41;
const _scoresMagic = 0x31534D41;
const _compactDedup = 1;
// quds_arabic_morph_alloc's limit; batches are split to stay below it.
const _maxAllocation = 1 << 20;

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
      _analyzeCompact = library
          .lookupFunction<
            Int32 Function(
              Pointer<Void>,
              Pointer<Uint8>,
              Pointer<Uint32>,
              Uint32,
              Uint32,
              Pointer<Pointer<Uint8>>,
              Pointer<Size>,
              Pointer<Uint8>,
              Size,
            ),
            int Function(
              Pointer<Void>,
              Pointer<Uint8>,
              Pointer<Uint32>,
              int,
              int,
              Pointer<Pointer<Uint8>>,
              Pointer<Size>,
              Pointer<Uint8>,
              int,
            )
          >('crispembed_ar_morph_analyze_compact'),
      _bufferFree = library
          .lookupFunction<
            Void Function(Pointer<Uint8>),
            void Function(Pointer<Uint8>)
          >('crispembed_ar_morph_buffer_free'),
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
      _openModel = library
          .lookupFunction<
            Pointer<Void> Function(
              Pointer<Uint8>,
              Pointer<Uint8>,
              Pointer<Uint8>,
              Size,
            ),
            Pointer<Void> Function(
              Pointer<Uint8>,
              Pointer<Uint8>,
              Pointer<Uint8>,
              int,
            )
          >('crispembed_ar_morph_disambig_open'),
      _disambiguate = library
          .lookupFunction<
            Int32 Function(
              Pointer<Void>,
              Pointer<Void>,
              Pointer<Uint8>,
              Pointer<Uint32>,
              Uint32,
              Pointer<Uint32>,
              Uint32,
              Uint32,
              Pointer<Pointer<Uint8>>,
              Pointer<Size>,
              Pointer<Uint8>,
              Size,
            ),
            int Function(
              Pointer<Void>,
              Pointer<Void>,
              Pointer<Uint8>,
              Pointer<Uint32>,
              int,
              Pointer<Uint32>,
              int,
              int,
              Pointer<Pointer<Uint8>>,
              Pointer<Size>,
              Pointer<Uint8>,
              int,
            )
          >('crispembed_ar_morph_disambiguate'),
      _modelInfo = library
          .lookupFunction<
            Pointer<Uint8> Function(Pointer<Void>),
            Pointer<Uint8> Function(Pointer<Void>)
          >('crispembed_ar_morph_disambig_info'),
      modelFree = library
          .lookupFunction<
            Void Function(Pointer<Void>),
            void Function(Pointer<Void>)
          >('crispembed_ar_morph_disambig_free'),
      _enableDisambiguation = library
          .lookupFunction<Int32 Function(), int Function()>(
            'quds_arabic_morph_enable_disambiguation',
          ),
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
    if (abi() != 3 || adapter() != 2) {
      throw StateError('Unsupported Arabic morphology ABI.');
    }
    try {
      _error = _allocate(_errorCapacity);
      _out = _allocate(sizeOf<Pointer<Uint8>>()).cast();
      _outLength = _allocate(sizeOf<Size>()).cast();
    } on Object {
      dispose();
      rethrow;
    }
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
    Pointer<Uint32>,
    int,
    int,
    Pointer<Pointer<Uint8>>,
    Pointer<Size>,
    Pointer<Uint8>,
    int,
  )
  _analyzeCompact;
  final Pointer<Void> Function(
    Pointer<Uint8>,
    Pointer<Uint8>,
    Pointer<Uint8>,
    int,
  )
  _openModel;
  final int Function(
    Pointer<Void>,
    Pointer<Void>,
    Pointer<Uint8>,
    Pointer<Uint32>,
    int,
    Pointer<Uint32>,
    int,
    int,
    Pointer<Pointer<Uint8>>,
    Pointer<Size>,
    Pointer<Uint8>,
    int,
  )
  _disambiguate;
  final Pointer<Uint8> Function(Pointer<Void>) _modelInfo;
  final void Function(Pointer<Void>) modelFree;
  final int Function() _enableDisambiguation;
  final void Function(Pointer<Uint8>) _bufferFree;
  final Pointer<Uint8> Function(Pointer<Void>) _info;
  final void Function(Pointer<Void>) free;
  final Pointer<Uint8> Function(int) _malloc;
  final void Function(Pointer<Uint8>) _free;

  // Buffers owned for the isolate's lifetime (one analyzer per isolate).
  Pointer<Uint8> _error = nullptr;
  Pointer<Pointer<Uint8>> _out = nullptr;
  Pointer<Size> _outLength = nullptr;

  void dispose() {
    for (final buffer in [
      _error,
      _out.cast<Uint8>(),
      _outLength.cast<Uint8>(),
    ]) {
      if (buffer != nullptr) _free(buffer);
    }
    _error = nullptr;
    _out = nullptr;
    _outLength = nullptr;
  }

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

  /// Opens a disambiguation model bundle. CrispEmbed's disambiguator is
  /// default-off (CRISPEMBED_AR_MORPH_DISAMBIG); the adapter switches it on
  /// for this process unless the environment already sets it, so an
  /// operator's CRISPEMBED_AR_MORPH_DISAMBIG=0 still wins.
  (Pointer<Void>, String) openModel(String manifest, String manifestSha256) {
    _enableDisambiguation();
    _error[0] = 0;
    final handle = _withString(
      manifest,
      (m) => _withString(
        manifestSha256,
        (s) => _openModel(m, s, _error, _errorCapacity),
      ),
    );
    return (handle, _cString(_error, _errorCapacity));
  }

  String modelInfo(Pointer<Void> model) => _cString(_modelInfo(model));

  /// One disambiguation buffer for whole sentences ([lengths] words each),
  /// split into native calls below the adapter's allocation limit and
  /// joined: the compact records of every word, then their scores.
  Uint8List disambiguate(
    Pointer<Void> handle,
    Pointer<Void> model,
    List<String> words,
    List<int> lengths,
  ) {
    final encoded = [for (final word in words) utf8.encode(word)];
    final records = BytesBuilder(copy: false);
    final scores = BytesBuilder(copy: false);
    var word = 0;
    var sentence = 0;
    while (sentence < lengths.length) {
      var end = sentence;
      var bytes = 0;
      var count = 0;
      while (end < lengths.length) {
        var size = 0;
        for (var i = 0; i < lengths[end]; i++) {
          size += encoded[word + count + i].length + 4;
        }
        if (end > sentence &&
            bytes + size + 4 * (end - sentence + 1) >= _maxAllocation) {
          break;
        }
        bytes += size;
        count += lengths[end];
        end++;
      }
      final part = _disambiguateChunk(
        handle,
        model,
        encoded.sublist(word, word + count),
        lengths.sublist(sentence, end),
      );
      final data = ByteData.sublistView(part);
      // AMC1 n | records | AMS1 n | scores
      var at = 8;
      for (var i = 0; i < count; i++) {
        at += 8 + data.getUint32(at + 4, Endian.little);
      }
      records.add(Uint8List.sublistView(part, 8, at));
      scores.add(Uint8List.sublistView(part, at + 8));
      word += count;
      sentence = end;
    }
    final header = ByteData(8)
      ..setUint32(0, _compactMagic, Endian.little)
      ..setUint32(4, words.length, Endian.little);
    final middle = ByteData(8)
      ..setUint32(0, _scoresMagic, Endian.little)
      ..setUint32(4, words.length, Endian.little);
    return (BytesBuilder(copy: false)
          ..add(header.buffer.asUint8List())
          ..add(records.takeBytes())
          ..add(middle.buffer.asUint8List())
          ..add(scores.takeBytes()))
        .takeBytes();
  }

  Uint8List _disambiguateChunk(
    Pointer<Void> handle,
    Pointer<Void> model,
    List<Uint8List> words,
    List<int> lengths,
  ) {
    final total = words.fold<int>(0, (sum, w) => sum + w.length);
    if (total + 4 * words.length + 4 * lengths.length >= _maxAllocation) {
      throw StateError('A sentence is too long to disambiguate.');
    }
    final text = _allocate(total == 0 ? 1 : total);
    Pointer<Uint32> wordLengths = nullptr;
    Pointer<Uint32> sentenceLengths = nullptr;
    try {
      wordLengths = _allocate(4 * (words.isEmpty ? 1 : words.length)).cast();
      sentenceLengths = _allocate(4 * lengths.length).cast();
      var at = 0;
      final view = text.asTypedList(total == 0 ? 1 : total);
      for (var i = 0; i < words.length; i++) {
        view.setAll(at, words[i]);
        at += words[i].length;
        wordLengths[i] = words[i].length;
      }
      for (var i = 0; i < lengths.length; i++) {
        sentenceLengths[i] = lengths[i];
      }
      _error[0] = 0;
      final status = _disambiguate(
        handle,
        model,
        text,
        wordLengths,
        words.length,
        sentenceLengths,
        lengths.length,
        _compactDedup,
        _out,
        _outLength,
        _error,
        _errorCapacity,
      );
      if (status != 0) {
        throw StateError(
          'disambiguation failed ($status): ${_cString(_error, _errorCapacity)}',
        );
      }
      final output = _out.value;
      try {
        return Uint8List.fromList(output.asTypedList(_outLength.value));
      } finally {
        _bufferFree(output);
      }
    } finally {
      _free(text);
      if (wordLengths != nullptr) _free(wordLengths.cast());
      if (sentenceLengths != nullptr) _free(sentenceLengths.cast());
    }
  }

  /// The compact results of [words] in the analyzer's batch format (`AMC1`,
  /// word count, per-word status and record; duplicate analyses dropped),
  /// as parts to concatenate. Words are sent in chunks below the adapter's
  /// allocation limit; a word the analyzer rejects (invalid UTF-8, over
  /// 4,096 bytes) gets the input-error status. Other failures throw.
  List<Uint8List> analyzeCompact(Pointer<Void> handle, List<String> words) {
    final encoded = [for (final word in words) utf8.encode(word)];
    final out = <Uint8List>[
      (ByteData(8)
            ..setUint32(0, _compactMagic, Endian.little)
            ..setUint32(4, words.length, Endian.little))
          .buffer
          .asUint8List(),
    ];
    var start = 0;
    while (start < encoded.length) {
      var end = start;
      var bytes = 0;
      while (end < encoded.length &&
          (end == start ||
              bytes + encoded[end].length + 4 * (end - start + 1) <
                  _maxAllocation)) {
        bytes += encoded[end].length;
        end++;
      }
      out.add(_chunk(handle, encoded.sublist(start, end)));
      start = end;
    }
    return out;
  }

  /// One native call; returns the per-word part (after the 8-byte header).
  Uint8List _chunk(Pointer<Void> handle, List<Uint8List> words) {
    final total = words.fold<int>(0, (sum, w) => sum + w.length);
    if (total + 4 * words.length >= _maxAllocation) {
      // A single word above the limit: the analyzer rejects it anyway.
      final rejected = ByteData(8)
        ..setUint32(0, 5, Endian.little)
        ..setUint32(4, 0, Endian.little);
      return rejected.buffer.asUint8List();
    }
    final text = _allocate(total == 0 ? 1 : total);
    Pointer<Uint32> lengths = nullptr;
    try {
      lengths = _allocate(4 * words.length).cast<Uint32>();
      var at = 0;
      final view = text.asTypedList(total == 0 ? 1 : total);
      for (var i = 0; i < words.length; i++) {
        view.setAll(at, words[i]);
        at += words[i].length;
        lengths[i] = words[i].length;
      }
      _error[0] = 0;
      final status = _analyzeCompact(
        handle,
        text,
        lengths,
        words.length,
        _compactDedup,
        _out,
        _outLength,
        _error,
        _errorCapacity,
      );
      if (status != 0) {
        throw StateError(
          'analysis failed ($status): ${_cString(_error, _errorCapacity)}',
        );
      }
      final output = _out.value;
      try {
        final length = _outLength.value;
        return output.asTypedList(length).sublist(8); // one copy
      } finally {
        _bufferFree(output);
      }
    } finally {
      _free(text);
      if (lengths != nullptr) _free(lengths.cast());
    }
  }
}
