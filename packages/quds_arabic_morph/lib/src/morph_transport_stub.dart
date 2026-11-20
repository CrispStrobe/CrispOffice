import 'package:quds_office_engine/quds_office_engine.dart';

import 'morph_catalog.dart';
import 'morph_transport.dart';

ArabicMorphTransport createArabicMorphTransport({
  String? nativeLibraryPath,
  Uri? workerUrl,
}) => _UnavailableTransport();

final class _UnavailableTransport implements ArabicMorphTransport {
  static const _error = ArabicMorphUnavailableException(
    'This platform has no local Arabic morphology worker.',
  );
  @override
  Future<Map<String, Object?>> open(MorphDatabase database) async =>
      throw _error;
  @override
  Future<List<List<ArabicAnalysis>?>> analyze(List<String> words) async =>
      throw _error;
  @override
  Future<Map<String, Object?>> openDisambiguator(MorphDatabase model) async =>
      throw _error;
  @override
  Future<void> unloadDisambiguator() async {}
  @override
  Future<List<List<ArabicContextReading>>> disambiguate(
    List<List<String>> sentences,
  ) async => throw _error;
  @override
  Future<void> dispose() async {}
}
