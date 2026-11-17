import 'dart:collection';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';
import 'transport.dart';
import 'transport_process.dart';

/// Injectable interface shared by the analysis UI and grammar provider.
abstract interface class AotAnalyzer {
  Future<AotAnalysis> analyze(
    String text, {
    AotLanguage language = AotLanguage.german,
  });
  Future<AotMorphology> morphology(
    String word, {
    AotLanguage language = AotLanguage.german,
    bool withParadigms = false,
  });
  Future<void> dispose();
}

/// An owning AOT client. Construction does not start a worker or connect.
///
/// The default uses a managed local [AotProcessTransport], requiring no daemon
/// or listening port. [AotClient.http] explicitly selects a legacy HTTP service.
/// Successful morphology results share a bounded LRU cache, keyed by exact
/// surface text, language and paradigm mode. Concurrent identical lookups are
/// coalesced. Syntax text and failures are never cached.
final class AotClient implements AotAnalyzer {
  factory AotClient({
    AotTransport? transport,
    int maximumMorphologyCacheEntries = 64,
    int maximumMorphologyCacheCodeUnits = 512 * 1024,
  }) {
    if (maximumMorphologyCacheEntries < 0 ||
        maximumMorphologyCacheCodeUnits < 0) {
      throw ArgumentError('Invalid AOT morphology cache limits.');
    }
    return AotClient._(
      transport ?? AotProcessTransport(),
      maximumMorphologyCacheEntries,
      maximumMorphologyCacheCodeUnits,
    );
  }

  /// Uses the native worker directly, with optional resource location.
  factory AotClient.local({
    String executable = 'quds_aot_worker',
    String? rmlDirectory,
    Duration timeout = const Duration(seconds: 60),
    int maximumMorphologyCacheEntries = 64,
    int maximumMorphologyCacheCodeUnits = 512 * 1024,
  }) => AotClient(
    transport: AotProcessTransport(
      executable: executable,
      rmlDirectory: rmlDirectory,
      timeout: timeout,
    ),
    maximumMorphologyCacheEntries: maximumMorphologyCacheEntries,
    maximumMorphologyCacheCodeUnits: maximumMorphologyCacheCodeUnits,
  );

  /// Explicit compatibility with a separately managed SynanDaemon service.
  /// Non-loopback endpoints require [allowRemote]. No request is made here.
  factory AotClient.http({
    Uri? endpoint,
    bool allowRemote = false,
    AotRequestMethod requestMethod = AotRequestMethod.post,
    http.Client? httpClient,
    Duration timeout = const Duration(seconds: 15),
    int maximumMorphologyCacheEntries = 64,
    int maximumMorphologyCacheCodeUnits = 512 * 1024,
  }) => AotClient(
    transport: AotHttpTransport(
      endpoint: endpoint,
      allowRemote: allowRemote,
      requestMethod: requestMethod,
      httpClient: httpClient,
      timeout: timeout,
    ),
    maximumMorphologyCacheEntries: maximumMorphologyCacheEntries,
    maximumMorphologyCacheCodeUnits: maximumMorphologyCacheCodeUnits,
  );

  AotClient._(
    this._transport,
    this.maximumMorphologyCacheEntries,
    this.maximumMorphologyCacheCodeUnits,
  );

  final AotTransport _transport;

  /// Maximum number of successful morphology lookups retained. Zero disables
  /// retention; simultaneous identical requests can still share their work.
  final int maximumMorphologyCacheEntries;

  /// Total retention budget measured by the re-encoded raw JSON's UTF-16 size
  /// plus the surface key. This is a deterministic estimate, not a heap limit.
  /// Oversized results are returned normally without being retained.
  final int maximumMorphologyCacheCodeUnits;

  final LinkedHashMap<_MorphologyKey, _CachedMorphology> _morphologyCache =
      LinkedHashMap<_MorphologyKey, _CachedMorphology>();
  final Map<_MorphologyKey, Future<AotMorphology>> _morphologyInFlight =
      <_MorphologyKey, Future<AotMorphology>>{};
  int _morphologyCacheCodeUnits = 0;
  bool _disposed = false;

  @override
  Future<AotAnalysis> analyze(
    String text, {
    AotLanguage language = AotLanguage.german,
  }) async {
    _checkOpen();
    if (!language.supportsSyntax) {
      throw const AotException(
        AotErrorCode.unsupportedLanguage,
        'AOT syntax analysis supports German and Russian.',
      );
    }
    if (text.trim().isEmpty) {
      return AotAnalysis(
        text: text,
        language: language,
        sentences: const <AotSentence>[],
      );
    }
    final Object? json = await _transport.request(
      action: 'syntax',
      language: language,
      query: text,
    );
    _checkOpen();
    try {
      return AotAnalysis.fromJson(json, text: text, language: language);
    } on FormatException {
      throw const AotException(
        AotErrorCode.malformedResponse,
        'AOT returned an invalid syntax analysis structure.',
      );
    }
  }

  @override
  Future<AotMorphology> morphology(
    String word, {
    AotLanguage language = AotLanguage.german,
    bool withParadigms = false,
  }) async {
    _checkOpen();
    if (word.trim().isEmpty) {
      return AotMorphology(
        word: word,
        language: language,
        readings: const <AotMorphReading>[],
      );
    }
    final _MorphologyKey key = (word, language, withParadigms);
    final _CachedMorphology? cached = _morphologyCache.remove(key);
    if (cached != null) {
      _morphologyCache[key] = cached;
      return cached.value;
    }
    final Future<AotMorphology>? existing = _morphologyInFlight[key];
    if (existing != null) return existing;
    final Future<AotMorphology> pending = _loadMorphology(key);
    _morphologyInFlight[key] = pending;
    try {
      return await pending;
    } finally {
      if (identical(_morphologyInFlight[key], pending)) {
        final Future<AotMorphology>? completed = _morphologyInFlight.remove(
          key,
        );
        assert(identical(completed, pending));
      }
    }
  }

  Future<AotMorphology> _loadMorphology(_MorphologyKey key) async {
    final (String word, AotLanguage language, bool withParadigms) = key;
    final Object? json = await _transport.request(
      action: 'morph',
      language: language,
      query: word,
      withParadigms: withParadigms,
    );
    _checkOpen();
    try {
      final AotMorphology value = AotMorphology.fromJson(
        json,
        word: word,
        language: language,
      );
      _rememberMorphology(key, value, json);
      return value;
    } on FormatException {
      throw const AotException(
        AotErrorCode.malformedResponse,
        'AOT returned an invalid morphology structure.',
      );
    }
  }

  void _rememberMorphology(
    _MorphologyKey key,
    AotMorphology value,
    Object? raw,
  ) {
    if (maximumMorphologyCacheEntries == 0 ||
        maximumMorphologyCacheCodeUnits == 0) {
      return;
    }
    final int codeUnits;
    try {
      codeUnits = jsonEncode(raw).length + key.$1.length;
    } catch (_) {
      // Optional cache admission cannot turn a successfully parsed response
      // from an injected transport into an operational failure.
      return;
    }
    if (codeUnits > maximumMorphologyCacheCodeUnits) return;
    while (_morphologyCache.isNotEmpty &&
        (_morphologyCache.length >= maximumMorphologyCacheEntries ||
            _morphologyCacheCodeUnits + codeUnits >
                maximumMorphologyCacheCodeUnits)) {
      final _MorphologyKey oldest = _morphologyCache.keys.first;
      _morphologyCacheCodeUnits -= _morphologyCache.remove(oldest)!.codeUnits;
    }
    _morphologyCache[key] = _CachedMorphology(value, codeUnits);
    _morphologyCacheCodeUnits += codeUnits;
  }

  void _checkOpen() {
    if (_disposed) {
      throw const AotException(
        AotErrorCode.disposed,
        'AOT client is disposed.',
      );
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _morphologyCache.clear();
    _morphologyInFlight.clear();
    _morphologyCacheCodeUnits = 0;
    await _transport.dispose();
  }
}

typedef _MorphologyKey = (String, AotLanguage, bool);

final class _CachedMorphology {
  const _CachedMorphology(this.value, this.codeUnits);
  final AotMorphology value;
  final int codeUnits;
}
