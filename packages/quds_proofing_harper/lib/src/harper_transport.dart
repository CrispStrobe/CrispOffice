/// A local JSON worker. Public for host-specific packaging and adapter tests.
abstract interface class HarperTransport {
  Future<String> check(String request);
  Future<void> dispose();
}

/// The backend could not be loaded on this host.
final class HarperUnavailableException implements Exception {
  const HarperUnavailableException(this.message);
  final String message;
  @override
  String toString() => message;
}
