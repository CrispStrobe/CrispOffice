import 'hunspell_catalog.dart';

/// A local Hunspell worker speaking JSON responses. Public for host-specific
/// packaging and adapter tests.
abstract interface class HunspellTransport {
  /// Opens [dictionary]; completes when the engine is ready.
  Future<void> open(HunspellDictionary dictionary);

  /// Checks [words]; for misspelled words with `suggest[i]` set, also returns
  /// suggestions. Response: `{"status":"success","results":[{"ok":bool,
  /// "suggestions":[...]}]}` in input order.
  Future<String> check(List<String> words, List<bool> suggest);
  Future<void> dispose();
}

/// The backend could not be loaded on this host.
final class HunspellUnavailableException implements Exception {
  const HunspellUnavailableException(this.message);
  final String message;
  @override
  String toString() => message;
}
