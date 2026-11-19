import 'dart:typed_data';

/// A local classifier worker (persistent isolate or Web Worker). Public for
/// host-specific packaging and adapter tests.
abstract interface class LanguageIdTransport {
  /// Opens the verified [model] bytes; completes when ready.
  Future<void> open(Uint8List model);

  /// Up to [k] `(CLD3 label, probability)` pairs per text, best first, in
  /// input order. A text without letters has an empty list.
  Future<List<List<(String, double)>>> detect(List<String> texts, int k);

  Future<void> dispose();
}

/// The classifier could not be loaded on this host.
final class LanguageIdUnavailableException implements Exception {
  const LanguageIdUnavailableException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Parses the adapter's result lines (`"<label> <probability>\n"`).
List<(String, double)> parseLanguageIdLines(String text) => [
  for (final line in text.split('\n'))
    if (line.indexOf(' ') case final space when space > 0)
      (line.substring(0, space), double.parse(line.substring(space + 1))),
];
