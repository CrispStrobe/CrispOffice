import 'harper_transport.dart';

HarperTransport createHarperTransport({
  String? nativeLibraryPath,
  Uri? workerUrl,
}) => _UnavailableTransport();

final class _UnavailableTransport implements HarperTransport {
  @override
  Future<String> check(String request) async =>
      throw const HarperUnavailableException(
        'This platform has no local Harper worker.',
      );
  @override
  Future<void> dispose() async {}
}
