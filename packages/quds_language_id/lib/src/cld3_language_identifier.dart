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
           );

  Uint8List? _model;
  final LanguageIdTransport _transport;

  /// Candidates returned per text.
  final int topK;

  /// Texts sent to the worker per request.
  final int batchTexts;

  Future<void>? _loading;
  bool _available = false;
  bool _disposed = false;
  Object? _failure;

  @override
  bool get isAvailable => _available && !_disposed;

  /// Why loading failed, if it did (missing library, tampered model, ...).
  Object? get failure => _failure;

  /// Opens the model once; later calls return the same future. Completes
  /// normally even when loading fails ([failure] tells why).
  Future<void> load() => _loading ??= _open();

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
    if (texts.isEmpty) return const [];
    await load();
    if (!isAvailable) return [for (final _ in texts) const <LanguageGuess>[]];
    final results = <List<LanguageGuess>>[];
    for (var start = 0; start < texts.length; start += batchTexts) {
      final end = start + batchTexts < texts.length
          ? start + batchTexts
          : texts.length;
      final batch = texts.sublist(start, end);
      final List<List<(String, double)>> answers;
      try {
        answers = await _transport.detect(batch, topK);
      } on Object catch (error) {
        _failure = error;
        _available = false;
        while (results.length < texts.length) {
          results.add(const <LanguageGuess>[]);
        }
        return results;
      }
      if (answers.length != batch.length) {
        throw const FormatException('Malformed language identifier response.');
      }
      for (final answer in answers) {
        results.add([
          for (final (label, probability) in answer)
            LanguageGuess(cld3LabelToLanguage(label), probability),
        ]);
      }
    }
    return results;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _available = false;
    await _transport.dispose();
  }
}
