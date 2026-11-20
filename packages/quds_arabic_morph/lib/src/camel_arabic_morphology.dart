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
/// of camel_tools 1.6.0) over a verified, user-downloaded database. With a
/// verified context disambiguation model ([disambiguator] or
/// [loadDisambiguator]) it is also an [ArabicContextMorphology].
///
/// One instance owns one worker (a persistent isolate natively, a module Web
/// Worker in browsers) and should live as long as the database is installed;
/// proofing providers are recreated per configuration, this object is not.
/// [isAvailable] turns true once [load] has opened the database. Results are
/// cached per session (bounded by [cacheWords] distinct words).
final class CamelArabicMorphology implements ArabicContextMorphology {
  CamelArabicMorphology({
    required MorphDatabase database,
    MorphDatabase? disambiguator,
    String? nativeLibraryPath,
    Uri? workerUrl,
    ArabicMorphTransport? transport,
    this.cacheWords = 4096,
    this.batchWords = 512,
    this.cacheSentences = 1024,
  }) : bundle = database.bundle,
       _database = database,
       _pendingModel = disambiguator,
       _transport =
           transport ??
           platform.createArabicMorphTransport(
             nativeLibraryPath: nativeLibraryPath,
             workerUrl: workerUrl,
           );

  /// The pinned bundle this analyzer opens.
  final MorphBundleDownload bundle;

  /// Released once opened, so browser hosts do not keep the verified bytes
  /// alive next to the worker's copy.
  MorphDatabase? _database;
  final ArabicMorphTransport _transport;

  /// Distinct words kept in the session cache (least recently used dropped
  /// first). Each word keeps its compact analyzer record (about 1-2 KB for
  /// some 30 analyses of the 24 proofing features) and reads features from
  /// it on demand, so the default keeps a long document's vocabulary in a few
  /// MB without growing without bound.
  final int cacheWords;

  /// Words sent to the worker per request, so a long document never blocks
  /// the worker or builds one huge message.
  final int batchWords;

  /// Sentences whose readings are kept (least recently used dropped first);
  /// proofing checks the same paragraph again after every edit elsewhere.
  final int cacheSentences;

  final LinkedHashMap<String, List<ArabicAnalysis>> _cache = LinkedHashMap();
  final LinkedHashMap<String, List<ArabicContextReading>> _readings =
      LinkedHashMap();
  Future<void>? _loading;
  Future<void>? _openingDatabase;
  bool _available = false;
  bool _disposed = false;
  Object? _failure;
  Map<String, Object?>? _info;
  MorphDatabase? _pendingModel;
  Future<void>? _loadingDisambiguator;
  bool _canDisambiguate = false;
  Object? _disambiguatorFailure;
  Map<String, Object?>? _disambiguatorInfo;
  Future<void> _modelOperations = Future<void>.value();
  int _modelGeneration = 0;

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

  @override
  bool get canDisambiguate => _canDisambiguate && isAvailable;

  /// Why the disambiguation model could not be loaded, if it was not.
  Object? get disambiguatorFailure => _disambiguatorFailure;

  /// The model's description (format, hashes, tag and lexeme counts,
  /// training metadata); null until loaded.
  Map<String, Object?>? get disambiguatorInfo => _disambiguatorInfo;

  /// Opens the context disambiguation model [model] once the database is
  /// open; later calls return the same future until a failure
  /// ([disambiguatorFailure]), after which a call retries.
  Future<void> loadDisambiguator(MorphDatabase model) {
    _pendingModel = null;
    final generation = _modelGeneration;
    return _loadingDisambiguator ??= _queueModel(() async {
      // Initial load can itself await the constructor's model. Waiting for
      // database readiness directly keeps these two futures acyclic.
      await (_openingDatabase ??= _openDatabase());
      await _openModel(model, generation);
    });
  }

  Future<void> _queueModel(Future<void> Function() operation) {
    final next = _modelOperations.then((_) => operation());
    _modelOperations = next.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return next;
  }

  /// Releases only the context model. The database and word cache stay open;
  /// sentence readings are discarded. A later [loadDisambiguator] can load a
  /// model again without transferring or reopening the database.
  Future<void> unloadDisambiguator() {
    _modelGeneration++;
    _pendingModel = null;
    _loadingDisambiguator = null;
    _canDisambiguate = false;
    _disambiguatorInfo = null;
    _disambiguatorFailure = null;
    _readings.clear();
    return _queueModel(() async {
      if (!isAvailable) return;
      try {
        await _transport.unloadDisambiguator();
      } on Object catch (error) {
        // An unavailable worker cannot still serve ordinary analysis. Keep
        // the failure visible to the host instead of reporting a live model.
        _disambiguatorFailure = error;
        _failure = error;
        _available = false;
      }
    });
  }

  Future<void> _openModel(MorphDatabase model, int generation) async {
    if (!isAvailable || generation != _modelGeneration) {
      if (generation == _modelGeneration) _loadingDisambiguator = null;
      return;
    }
    try {
      final info = await _transport.openDisambiguator(model);
      if (_disposed || generation != _modelGeneration) return;
      _disambiguatorInfo = info;
      _canDisambiguate = true;
      _disambiguatorFailure = null;
    } on Object catch (error) {
      if (_disposed || generation != _modelGeneration) return;
      _disambiguatorFailure = error;
      _canDisambiguate = false;
      _loadingDisambiguator = null;
    }
  }

  @override
  Future<List<List<ArabicContextReading>>> disambiguate(
    List<List<String>> sentences,
  ) async {
    await load();
    final pending = _loadingDisambiguator;
    if (pending != null) await pending;
    if (!canDisambiguate || sentences.isEmpty) {
      return const <List<ArabicContextReading>>[];
    }
    final generation = _modelGeneration;
    final out = List<List<ArabicContextReading>?>.filled(
      sentences.length,
      null,
    );
    final missing = <int>[];
    final repeats = <int, int>{}; // sentence -> earlier identical one
    final firstOf = <String, int>{};
    for (var i = 0; i < sentences.length; i++) {
      final key = sentences[i].join('\u0000');
      final cached = _readings.remove(key);
      if (cached != null) {
        _readings[key] = cached;
        out[i] = cached;
      } else if (firstOf[key] case final first?) {
        repeats[i] = first;
      } else {
        firstOf[key] = i;
        missing.add(i);
      }
    }
    // Batches of whole sentences, about batchWords tokens each.
    var start = 0;
    while (start < missing.length) {
      var end = start;
      var tokens = 0;
      while (end < missing.length &&
          (end == start ||
              tokens + sentences[missing[end]].length <= batchWords)) {
        tokens += sentences[missing[end]].length;
        end++;
      }
      final batch = [for (final i in missing.sublist(start, end)) sentences[i]];
      final List<List<ArabicContextReading>> readings;
      try {
        readings = await _transport.disambiguate(batch);
      } on ArabicMorphUnavailableException catch (error) {
        _failure = error;
        _available = false;
        _canDisambiguate = false;
        return const <List<ArabicContextReading>>[];
      }
      if (!canDisambiguate || generation != _modelGeneration) {
        return const <List<ArabicContextReading>>[];
      }
      if (readings.length != batch.length) {
        throw const FormatException(
          'Malformed Arabic disambiguation response.',
        );
      }
      for (var j = 0; j < batch.length; j++) {
        if (readings[j].length != batch[j].length) {
          throw const FormatException(
            'Malformed Arabic disambiguation response.',
          );
        }
        out[missing[start + j]] = readings[j];
        if (cacheSentences > 0) {
          _readings[batch[j].join('\u0000')] = readings[j];
          while (_readings.length > cacheSentences) {
            _readings.remove(_readings.keys.first);
          }
        }
      }
      start = end;
    }
    repeats.forEach((i, first) => out[i] = out[first]);
    return [for (final r in out) r!];
  }

  Future<void> _open() async {
    await (_openingDatabase ??= _openDatabase());
    final model = _pendingModel;
    _pendingModel = null;
    if (model != null && _available) {
      await loadDisambiguator(model);
    }
  }

  Future<void> _openDatabase() async {
    final database = _database;
    _database = null;
    if (database == null) {
      _failure = const ArabicMorphUnavailableException(
        'The morphology database was already released.',
      );
      return;
    }
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

  /// Drops the session caches (the analyzer stays open).
  void clearCache() {
    _cache.clear();
    _readings.clear();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _modelGeneration++;
    _pendingModel = null;
    _database = null;
    _available = false;
    _canDisambiguate = false;
    _cache.clear();
    _readings.clear();
    await _transport.dispose();
  }
}
