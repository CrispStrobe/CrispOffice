import 'backend.dart';
import 'bundle.dart';
import 'decoder.dart';
import 'guards.dart';
import 'worker_unsupported.dart'
    if (dart.library.io) 'worker_native.dart'
    as platform;

final class GectorCheckRequest {
  GectorCheckRequest({
    required this.text,
    required this.key,
    Iterable<String> personalWords = const <String>[],
  }) : personalWords = Set<String>.unmodifiable(personalWords);
  final String text;
  final String key;
  final Set<String> personalWords;
}

/// A preloaded, persistent worker. A result must represent the complete supplied
/// text or throw; reference/unguarded results are not accepted by the provider.
abstract interface class GectorTransport {
  Future<GectorDecodedText> check(GectorCheckRequest request);
  Future<void> dispose();
}

Future<GectorTransport> startGectorWorker({
  required GectorVerifiedBundle bundle,
  required GectorBackendFactory backendFactory,
  required GectorLexiconFactory lexiconFactory,
  GectorDecodeOptions? options,
  int maximumPendingRequests = 3,
  Duration startupTimeout = const Duration(seconds: 60),
}) {
  if (maximumPendingRequests < 1 ||
      maximumPendingRequests > 8 ||
      startupTimeout <= Duration.zero) {
    throw ArgumentError('Invalid GECToR worker limits.');
  }
  return platform.startWorker(
    bundle: bundle,
    backendFactory: backendFactory,
    lexiconFactory: lexiconFactory,
    options: options ?? GectorDecodeOptions(),
    maximumPendingRequests: maximumPendingRequests,
    startupTimeout: startupTimeout,
  );
}
