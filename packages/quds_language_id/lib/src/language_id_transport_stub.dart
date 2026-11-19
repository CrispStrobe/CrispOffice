import 'dart:typed_data';

import 'language_id_transport.dart';

LanguageIdTransport createLanguageIdTransport({
  String? nativeLibraryPath,
  Uri? workerUrl,
}) => _UnavailableTransport();

final class _UnavailableTransport implements LanguageIdTransport {
  static const _error = LanguageIdUnavailableException(
    'This platform has no local language identifier.',
  );
  @override
  Future<void> open(Uint8List model) async => throw _error;
  @override
  Future<List<List<(String, double)>>> detect(
    List<String> texts,
    int k,
  ) async => throw _error;
  @override
  Future<void> dispose() async {}
}
