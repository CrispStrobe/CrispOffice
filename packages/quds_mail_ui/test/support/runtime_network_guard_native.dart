import 'dart:io';

final class RuntimeNetworkGuard {
  int attempts = 0;
  Future<void> run(Future<void> Function() body) => HttpOverrides.runZoned(
    body,
    createHttpClient: (context) {
      attempts++;
      throw StateError('Outbound HTTP disabled by reader qualification.');
    },
  );
  void probe() {
    try {
      HttpClient();
    } on Object {
      /* The deliberate positive control is denied. */
    }
  }
}
