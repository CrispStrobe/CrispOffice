import 'models.dart';
import 'transport.dart';

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

/// An owning AOT client. Construction does not connect; requests are explicit.
/// Without a supplied transport only http://127.0.0.1:17018 is contacted.
final class AotClient implements AotAnalyzer {
  AotClient({AotTransport? transport})
    : _transport = transport ?? AotHttpTransport();

  final AotTransport _transport;
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
    final Object? json = await _transport.request(
      action: 'morph',
      language: language,
      query: word,
      withParadigms: withParadigms,
    );
    _checkOpen();
    try {
      return AotMorphology.fromJson(json, word: word, language: language);
    } on FormatException {
      throw const AotException(
        AotErrorCode.malformedResponse,
        'AOT returned an invalid morphology structure.',
      );
    }
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
    await _transport.dispose();
  }
}
