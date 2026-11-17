import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:ffi/ffi.dart';

import 'backend.dart';

typedef _CreateNative =
    Pointer<Void> Function(Pointer<Utf8>, Int32, Pointer<Utf8>, Size);
typedef _CreateDart =
    Pointer<Void> Function(Pointer<Utf8>, int, Pointer<Utf8>, int);
typedef _FreeNative = Void Function(Pointer<Void>);
typedef _FreeDart = void Function(Pointer<Void>);
typedef _ForwardNative =
    Int32 Function(
      Pointer<Void>,
      Pointer<Int64>,
      Size,
      Pointer<Int64>,
      Size,
      Size,
      Pointer<Float>,
      Size,
      Pointer<Float>,
      Size,
      Pointer<Float>,
      Size,
      Pointer<Utf8>,
      Size,
    );
typedef _ForwardDart =
    int Function(
      Pointer<Void>,
      Pointer<Int64>,
      int,
      Pointer<Int64>,
      int,
      int,
      Pointer<Float>,
      int,
      Pointer<Float>,
      int,
      Pointer<Float>,
      int,
      Pointer<Utf8>,
      int,
    );

/// Sendable configuration for the small CrispEmbed grammar library.
///
/// The host pins both the model and the compiled native library. Loading hashes
/// both files before executing native code and checks the model again after its
/// weights have been loaded. Installation and verification happen before a
/// provider becomes ready, outside the proofing request deadline.
/// Install model files immutably: the native context may retain a mapping.
/// Install the library directly inside a directory named by [librarySha256],
/// for example `<sha256>/libcrispembed-gector.so`. Native library handles are
/// reused across isolates, so a path must identify one hash for the entire
/// process lifetime, including after a grammar worker has been replaced.
///
/// The process must explicitly enable the native experiment with
/// `CRISPEMBED_GECTOR=1`. This factory does not change process environment,
/// download assets, register a model alias or enable background checks.
final class GectorNativeBackendFactory implements GectorBackendFactory {
  GectorNativeBackendFactory({
    required this.modelDirectory,
    required this.libraryPath,
    required this.librarySha256,
    this.threads = 2,
  }) {
    if (modelDirectory.isEmpty ||
        libraryPath.isEmpty ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(librarySha256) ||
        threads < 1 ||
        threads > 64) {
      throw ArgumentError('Invalid native GECToR configuration.');
    }
  }

  final String modelDirectory;
  final String libraryPath;
  final String librarySha256;
  final int threads;

  @override
  Future<GectorBackend> open(GectorModelArtifact artifact) async {
    final model = File(
      '$modelDirectory${Platform.pathSeparator}${artifact.file}',
    );
    await _verifyFile(model, artifact.sha256, expectedBytes: artifact.bytes);
    final String canonicalLibrary;
    try {
      canonicalLibrary = await File(libraryPath).resolveSymbolicLinks();
    } on FileSystemException catch (error) {
      throw GectorUnavailableException(
        'Cannot locate the pinned GECToR library: ${error.message}',
      );
    }
    await _verifyFile(File(canonicalLibrary), librarySha256);
    final parentName = File(
      canonicalLibrary,
    ).parent.uri.pathSegments.lastWhere((part) => part.isNotEmpty);
    if (parentName != librarySha256) {
      throw const GectorUnavailableException(
        'Install the native GECToR library in a directory named by its SHA-256.',
      );
    }
    final bindings = _pinnedBindings(canonicalLibrary, librarySha256);
    final allocations = Arena();
    late final _NativeBackend backend;
    Pointer<Void> context = nullptr;
    try {
      final path = model.absolute.path.toNativeUtf8(allocator: allocations);
      final error = allocations<Uint8>(_errorCapacity).cast<Utf8>();
      error
          .cast<Uint8>()
          .asTypedList(_errorCapacity)
          .fillRange(0, _errorCapacity, 0);
      context = bindings.create(path, threads, error, _errorCapacity);
      if (context == nullptr) {
        throw GectorUnavailableException(
          _diagnostic(error, 'Native model loading failed.'),
        );
      }
      backend = _NativeBackend(
        bindings,
        context,
        GectorBackendIdentity(
          artifactSha256: artifact.sha256,
          sourceModelSha256: artifact.sourceModelSha256,
          revision: artifact.revision,
        ),
      );
      context =
          nullptr; // Ownership transferred, including native finalization.
    } finally {
      if (context != nullptr) bindings.free(context);
      allocations.releaseAll();
    }
    // Attach finalization and release temporary malloc buffers before the next
    // await: a startup timeout can stop the worker without running finally.
    // The host keeps the admitted model immutable while its mapping is live.
    try {
      await _verifyFile(model, artifact.sha256, expectedBytes: artifact.bytes);
    } on Object {
      await backend.dispose();
      rethrow;
    }
    return backend;
  }
}

const int _errorCapacity = 1024;

// A finalizer must outlive its attached objects. Keeping it only in the backend
// would allow the finalizer itself to become unreachable with that backend.
// Retain the library and its finalizer until this worker isolate terminates.
final Map<String, ({String sha256, _Bindings bindings})> _libraries = {};

_Bindings _pinnedBindings(String path, String hash) {
  final previous = _libraries[path];
  if (previous != null) {
    if (previous.sha256 != hash) {
      throw const GectorUnavailableException(
        'A loaded GECToR library path cannot be reused with a different SHA-256.',
      );
    }
    return previous.bindings;
  }
  try {
    final bindings = _Bindings(DynamicLibrary.open(path));
    _libraries[path] = (sha256: hash, bindings: bindings);
    return bindings;
  } on GectorUnavailableException {
    rethrow;
  } on Object catch (error) {
    throw GectorUnavailableException(
      'Cannot load the verified GECToR library: $error',
    );
  }
}

Future<void> _verifyFile(
  File file,
  String expected, {
  int? expectedBytes,
}) async {
  try {
    final stat = file.statSync();
    if (stat.type != FileSystemEntityType.file ||
        (expectedBytes != null && stat.size != expectedBytes)) {
      throw const GectorUnavailableException(
        'A pinned GECToR file is missing or has the wrong size.',
      );
    }
    final digest = await sha256.bind(file.openRead()).first;
    if (digest.toString() != expected) {
      throw const GectorUnavailableException(
        'A pinned GECToR file failed SHA-256 verification.',
      );
    }
  } on FileSystemException catch (error) {
    throw GectorUnavailableException(
      'Cannot read a pinned GECToR file: ${error.message}',
    );
  }
}

String _diagnostic(Pointer<Utf8> buffer, String fallback) {
  final text = buffer.toDartString();
  return text.isEmpty ? fallback : text;
}

final class _Bindings {
  _Bindings(this.library) {
    try {
      create = library.lookupFunction<_CreateNative, _CreateDart>(
        'crispembed_gector_create',
      );
      freePointer = library.lookup<NativeFunction<_FreeNative>>(
        'crispembed_gector_free',
      );
      free = freePointer.asFunction<_FreeDart>();
      forward = library.lookupFunction<_ForwardNative, _ForwardDart>(
        'crispembed_gector_forward',
      );
      finalizer = NativeFinalizer(freePointer);
    } on Object catch (error) {
      throw GectorUnavailableException(
        'The verified library has an incompatible GECToR ABI: $error',
      );
    }
  }

  // Retain the library for at least the lifetime of all callbacks and contexts.
  final DynamicLibrary library;
  late final _CreateDart create;
  late final Pointer<NativeFunction<_FreeNative>> freePointer;
  late final _FreeDart free;
  late final _ForwardDart forward;
  late final NativeFinalizer finalizer;
}

final class _NativeBackend implements GectorBackend, Finalizable {
  _NativeBackend(this._bindings, this._context, this.identity) {
    _bindings.finalizer.attach(this, _context, detach: this);
  }

  final _Bindings _bindings;
  Pointer<Void> _context;
  @override
  final GectorBackendIdentity identity;

  @override
  Future<GectorLogits> forward(GectorPreparedInput input) async {
    if (_context == nullptr) {
      throw const GectorUnavailableException(
        'The native GECToR backend is disposed.',
      );
    }
    final count = input.tokenCount;
    if (count < 2 || count > 512 || input.attentionMask.length != count) {
      throw const FormatException('Invalid native GECToR input dimensions.');
    }
    final allocations = Arena();
    try {
      final ids = allocations<Int64>(count);
      final mask = allocations<Int64>(count);
      final labels = allocations<Float>(count * 5000);
      final detect = allocations<Float>(count * 2);
      final error = allocations<Uint8>(_errorCapacity).cast<Utf8>();
      error
          .cast<Uint8>()
          .asTypedList(_errorCapacity)
          .fillRange(0, _errorCapacity, 0);
      ids.asTypedList(count).setAll(0, input.inputIds);
      mask.asTypedList(count).setAll(0, input.attentionMask);
      final status = _bindings.forward(
        _context,
        ids,
        count,
        mask,
        count,
        1,
        labels,
        count * 5000,
        detect,
        count * 2,
        nullptr,
        0,
        error,
        _errorCapacity,
      );
      if (status != 0) {
        throw GectorUnavailableException(
          'Native GECToR failed ($status): ${_diagnostic(error, 'Inference failed.')}',
        );
      }
      final result = GectorLogits(
        tokenCount: count,
        labels: Float32List.fromList(labels.asTypedList(count * 5000)),
        detection: Float32List.fromList(detect.asTypedList(count * 2)),
      );
      result.validate(input, 5000);
      return result;
    } finally {
      allocations.releaseAll();
    }
  }

  @override
  Future<void> dispose() async {
    if (_context == nullptr) return;
    final context = _context;
    _context = nullptr;
    _bindings.finalizer.detach(this);
    _bindings.free(context);
  }
}
