import 'dart:async';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';

import 'cld3_labels.dart';
import 'cld3_model.dart';
import 'language_id_transport.dart';
import 'language_id_transport_stub.dart'
    if (dart.library.io) 'language_id_transport_native.dart'
    if (dart.library.js_interop) 'language_id_transport_web.dart'
    as platform;

/// [LanguageIdentifier] backed by the bundled CLD3 model.
///
/// One instance owns one worker and should live for the app session. Pass
/// the bundled model bytes (`rootBundle.load(Cld3Model.assetKey)` in a
/// Flutter host); they are checked against the pinned SHA-256 before the
/// worker sees them. [isAvailable] turns true once [load] has opened the
/// model. Failures never throw from [identify]: the identifier then
/// answers with empty lists, like [UnavailableLanguageIdentifier].
final class Cld3LanguageIdentifier implements LanguageIdentifier {
  Cld3LanguageIdentifier({
    required Uint8List this._model,
    String? nativeLibraryPath,
    Uri? workerUrl,
    LanguageIdTransport? transport,
    this.topK = 5,
    this.batchTexts = 256,
  }) : _transport =
           transport ??
           platform.createLanguageIdTransport(
             nativeLibraryPath: nativeLibraryPath,
             workerUrl: workerUrl,
           ) {
    if (topK < 1 || topK > 16) {
      throw RangeError.range(topK, 1, 16, 'topK');
    }
    if (batchTexts < 1) {
      throw RangeError.range(batchTexts, 1, null, 'batchTexts');
    }
  }

  Uint8List? _model;
  final LanguageIdTransport _transport;

  /// Candidates returned per text.
  final int topK;

  /// Texts sent to the worker per request.
  final int batchTexts;

  Future<void>? _loading;
  Future<void>? _disposing;
  bool _available = false;
  bool _disposed = false;
  Object? _failure;

  @override
  bool get isAvailable => _available && !_disposed;

  /// Why loading failed, if it did (missing library, tampered model, ...).
  Object? get failure => _failure;

  /// Opens the model once; later calls return the same future. Completes
  /// normally even when loading fails ([failure] tells why).
  Future<void> load() =>
      _disposed ? Future<void>.value() : _loading ??= _open();

  Future<void> _open() async {
    final model = _model;
    _model = null;
    try {
      if (model == null || !Cld3Model.verify(model)) {
        throw const LanguageIdUnavailableException(
          'The bundled language model is missing or differs from its pinned '
          'SHA-256.',
        );
      }
      await _transport.open(model);
      _available = !_disposed;
    } on Object catch (error) {
      _failure = error;
      _available = false;
    }
  }

  /// Top-[topK] languages of [text] (BCP-47 tags), best first.
  Future<List<LanguageGuess>> detect(String text) async =>
      (await identify([text])).single;

  /// [detect] for many texts with as few worker round trips as possible.
  Future<List<List<LanguageGuess>>> detectBatch(List<String> texts) =>
      identify(texts);

  @override
  Future<List<List<LanguageGuess>>> identify(List<String> texts) async {
    // The caller may mutate its list while the model or a worker is loading.
    final input = List<String>.of(texts, growable: false);
    if (input.isEmpty) return const [];
    final results = [for (final _ in input) const <LanguageGuess>[]];
    final positions = [
      for (var i = 0; i < input.length; i++)
        if (_letter.hasMatch(input[i])) i,
    ];
    if (positions.isEmpty || _disposed) return results;
    await load();
    if (!isAvailable) return results;
    for (var start = 0; start < positions.length; start += batchTexts) {
      final end = start + batchTexts < positions.length
          ? start + batchTexts
          : positions.length;
      final batch = [for (var i = start; i < end; i++) input[positions[i]]];
      try {
        final answers = await _transport.detect(batch, topK);
        if (!isAvailable) {
          return [for (final _ in input) const <LanguageGuess>[]];
        }
        if (answers.length != batch.length) {
          throw const FormatException(
            'Malformed language identifier response.',
          );
        }
        final converted = <List<LanguageGuess>>[];
        for (final answer in answers) {
          if (answer.length > topK) {
            throw const FormatException(
              'Malformed language identifier response.',
            );
          }
          var previousProbability = 1.0;
          final guesses = <LanguageGuess>[];
          for (final (label, probability) in answer) {
            final language = cld3LabelToLanguage(label);
            if (!_languages.contains(language) ||
                !probability.isFinite ||
                probability < 0 ||
                probability > previousProbability) {
              throw const FormatException(
                'Malformed language identifier response.',
              );
            }
            previousProbability = probability;
            guesses.add(LanguageGuess(language, probability));
          }
          converted.add(guesses);
        }
        for (var i = start; i < end; i++) {
          results[positions[i]] = converted[i - start];
        }
      } on Object catch (error) {
        if (!isAvailable) {
          return [for (final _ in input) const <LanguageGuess>[]];
        }
        _failure = error;
        _available = false;
        return results;
      }
    }
    return results;
  }

  Future<void> dispose() => _disposing ??= _dispose();

  Future<void> _dispose() async {
    _disposed = true;
    _available = false;
    _model = null;
    await _transport.dispose();
  }
}

final _letter = RegExp(r'\p{L}', unicode: true);
final _languages = cld3Labels.map(cld3LabelToLanguage).toSet();
