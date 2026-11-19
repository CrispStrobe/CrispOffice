import 'package:quds_office_engine/quds_office_engine.dart';

import 'morph_catalog.dart';

/// A local analyzer worker (persistent isolate or Web Worker). Public for
/// host-specific packaging and adapter tests.
abstract interface class ArabicMorphTransport {
  /// Opens [database]; completes with the analyzer's `info` object (variant,
  /// hashes, entry counts) when it is ready.
  Future<Map<String, Object?>> open(MorphDatabase database);

  /// Analyses for [words] in input order; `null` marks a word the analyzer
  /// rejects as input (invalid UTF-8, over 4,096 bytes).
  Future<List<List<ArabicAnalysis>?>> analyze(List<String> words);

  Future<void> dispose();
}

/// The backend could not be loaded on this host, or no database is open.
final class ArabicMorphUnavailableException implements Exception {
  const ArabicMorphUnavailableException(this.message);
  final String message;
  @override
  String toString() => message;
}
