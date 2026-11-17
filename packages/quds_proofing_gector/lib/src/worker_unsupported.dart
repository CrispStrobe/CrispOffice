import 'backend.dart';
import 'bundle.dart';
import 'decoder.dart';
import 'guards.dart';
import 'transport.dart';

/// Explicit capability boundary: this increment supplies a native persistent
/// isolate transport. A browser host must provide its own qualified Web Worker.
Future<GectorTransport> startWorker({
  required GectorVerifiedBundle bundle,
  required GectorBackendFactory backendFactory,
  required GectorLexiconFactory lexiconFactory,
  required GectorDecodeOptions options,
  required int maximumPendingRequests,
  required Duration startupTimeout,
}) async => throw const GectorUnavailableException(
  'No local GECToR worker is installed for this platform.',
);
