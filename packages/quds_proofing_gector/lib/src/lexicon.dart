import 'package:quds_office_engine/quds_office_engine.dart';

import 'guards.dart';

/// Loads Quds' existing licensed German dictionary inside the grammar worker.
/// Personal vocabulary travels with each request and is applied separately.
final class GectorGermanLexiconFactory implements GectorLexiconFactory {
  const GectorGermanLexiconFactory();

  @override
  Future<GectorLexicon> open() async {
    final provider = GermanSpellingProvider();
    try {
      await provider.warmUp();
      return _GermanLexicon(provider);
    } on Object {
      await provider.dispose();
      rethrow;
    }
  }
}

final class _GermanLexicon implements GectorLexicon {
  _GermanLexicon(this._provider);
  final GermanSpellingProvider _provider;

  @override
  Future<bool> isKnown(String word) => _provider.isKnownWord(word);

  @override
  Future<void> dispose() => _provider.dispose();
}
