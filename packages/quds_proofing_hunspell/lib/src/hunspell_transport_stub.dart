import 'hunspell_catalog.dart';
import 'hunspell_transport.dart';

HunspellTransport createHunspellTransport({
  String? nativeLibraryPath,
  Uri? workerUrl,
}) => _UnavailableTransport();

final class _UnavailableTransport implements HunspellTransport {
  static const _error = HunspellUnavailableException(
    'This platform has no local Hunspell worker.',
  );
  @override
  Future<void> open(HunspellDictionary dictionary) async => throw _error;
  @override
  Future<String> check(List<String> words, List<bool> suggest) async =>
      throw _error;
  @override
  Future<void> dispose() async {}
}
