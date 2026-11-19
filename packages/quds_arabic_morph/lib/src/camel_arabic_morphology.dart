import 'dart:async';
import 'dart:collection';

import 'package:quds_office_engine/quds_office_engine.dart';

import 'morph_catalog.dart';
import 'morph_transport.dart';
import 'morph_transport_stub.dart'
    if (dart.library.io) 'morph_transport_native.dart'
    if (dart.library.js_interop) 'morph_transport_web.dart'
    as platform;

/// [ArabicMorphology] backed by the native Camel Morph analyzer (a C++ port
/// of camel_tools 1.6.0) over a verified, user-downloaded database.
///
/// One instance owns one worker (a persistent isolate natively, a module Web
/// Worker in browsers) and should live as long as the database is installed;
/// proofing providers are recreated per configuration, this object is not.
/// [isAvailable] turns true once [load] has opened the database. Results are
/// cached per session (bounded by [cacheWords] distinct words).
final class CamelArabicMorphology implements ArabicMorphology {
  CamelArabicMorphology({
    required this.database,
    String? nativeLibraryPath,
    Uri? workerUrl,
    ArabicMorphTransport? transport,
    this.cacheWords = 20000,
    this.batchWords = 512,
  }) : _transport =
           transport ??
           platform.createArabicMorphTransport(
             nativeLibraryPath: nativeLibraryPath,
             workerUrl: workerUrl,
           );

  final MorphDatabase database;
  final ArabicMorphTransport _transport;

  /// Distinct words kept in the session cache (oldest dropped first).
  final int cacheWords;

  /// Words sent to the worker per request, so a long document never blocks
  /// the worker or builds one huge message.
  final int batchWords;

  final LinkedHashMap<String, List<ArabicAnalysis>> _cache = LinkedHashMap();
  Future<void>? _loading;
  bool _available = false;
  bool _disposed = false;
  Object? _failure;
  Map<String, Object?>? _info;

  @override
  bool get isAvailable => _available && !_disposed;

  /// Why loading failed, if it did (missing library, tampered bundle, ...).
  Object? get failure => _failure;

  /// The analyzer's description of the open database (variant, hashes,
  /// entry counts); null until loaded.
  Map<String, Object?>? get info => _info;

  /// Opens the database once; later calls return the same future. Completes
  /// normally even when loading fails ([failure] tells why).
  Future<void> load() => _loading ??= _open();

  Future<void> _open() async {
    try {
      _info = await _transport.open(database);
      _available = !_disposed;
    } on Object catch (error) {
      _failure = error;
      _available = false;
    }
  }

  @override
  Future<Map<String, List<ArabicAnalysis>>> analyzeWords(
    Iterable<String> words,
  ) async {
    final distinct = LinkedHashSet<String>.of(words);
    final result = <String, List<ArabicAnalysis>>{};
    final missing = <String>[];
    for (final word in distinct) {
      final cached = _cache.remove(word);
      if (cached != null) {
        _cache[word] = cached; // most recently used last
        result[word] = cached;
      } else {
        missing.add(word);
      }
    }
    if (missing.isNotEmpty) {
      await load();
      if (!isAvailable) {
        for (final word in missing) {
          result[word] = const <ArabicAnalysis>[];
        }
        return result;
      }
      for (var start = 0; start < missing.length; start += batchWords) {
        final batch = missing.sublist(
          start,
          start + batchWords < missing.length
              ? start + batchWords
              : missing.length,
        );
        final List<List<ArabicAnalysis>?> analyses;
        try {
          analyses = await _transport.analyze(batch);
        } on ArabicMorphUnavailableException catch (error) {
          // The worker stopped: behave like an absent analyzer from now on.
          _failure = error;
          _available = false;
          for (final word in missing) {
            result.putIfAbsent(word, () => const <ArabicAnalysis>[]);
          }
          return result;
        }
        if (analyses.length != batch.length) {
          throw const FormatException('Malformed Arabic morphology response.');
        }
        for (var i = 0; i < batch.length; i++) {
          final value = analyses[i] ?? const <ArabicAnalysis>[];
          result[batch[i]] = value;
          _remember(batch[i], value);
        }
      }
    }
    return result;
  }

  void _remember(String word, List<ArabicAnalysis> analyses) {
    if (cacheWords <= 0) return;
    _cache[word] = analyses;
    while (_cache.length > cacheWords) {
      _cache.remove(_cache.keys.first);
    }
  }

  /// Number of words currently cached (diagnostics and tests).
  int get cachedWords => _cache.length;

  /// Drops the session cache (the analyzer stays open).
  void clearCache() => _cache.clear();

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _available = false;
    _cache.clear();
    await _transport.dispose();
  }
}
