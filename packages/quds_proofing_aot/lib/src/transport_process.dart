import 'models.dart';
import 'transport.dart';
import 'transport_process_stub.dart'
    if (dart.library.io) 'transport_process_io.dart'
    as platform;

/// Runs the native AOT engine in a private, managed local worker.
///
/// The worker is started lazily on the first request, communicates through
/// bounded JSON lines on stdin/stdout, and is reused for subsequent requests.
/// No server, listening port, shell, or document text in process arguments is
/// involved. The executable must be the supplied `quds_aot_worker`, or a
/// compatible direct executable that does not spawn descendants.
///
/// [rmlDirectory] points at the installed AOT language resources and overrides
/// the worker's `RML` environment variable. If omitted, the existing environment
/// is inherited. [executable] defaults to `quds_aot_worker` on PATH.
///
/// Every request deadline covers startup, queueing, and response consumption.
/// A worker crash, protocol error, or active-request timeout terminates the
/// worker and fails its pending requests. Create a new transport to retry; the
/// transport never silently resubmits document text. [dispose] terminates the
/// worker and rejects admitted work. Browsers report an explicit unavailable
/// result without attempting any network fallback.
final class AotProcessTransport implements AotTransport {
  AotProcessTransport({
    this.executable = 'quds_aot_worker',
    Iterable<String> arguments = const <String>[],
    this.rmlDirectory,
    Map<String, String> environment = const <String, String>{},
    this.timeout = const Duration(seconds: 60),
    this.maximumQueryCodeUnits = 32768,
    this.maximumRequestBytes = 256 * 1024,
    this.maximumResponseBytes = 4 * 1024 * 1024,
    this.maximumStderrBytes = 256 * 1024,
    this.maximumPendingRequests = 4,
  }) : arguments = List<String>.unmodifiable(arguments),
       environment = Map<String, String>.unmodifiable(environment) {
    if (executable.trim().isEmpty ||
        executable.contains('\u0000') ||
        this.arguments.any((String value) => value.contains('\u0000')) ||
        (rmlDirectory != null &&
            (rmlDirectory!.trim().isEmpty ||
                rmlDirectory!.contains('\u0000')))) {
      throw ArgumentError('Invalid AOT worker executable or resource path.');
    }
    if (timeout <= Duration.zero ||
        maximumQueryCodeUnits < 1 ||
        maximumRequestBytes < 1 ||
        maximumResponseBytes < 1 ||
        maximumStderrBytes < 1 ||
        maximumPendingRequests < 1 ||
        maximumPendingRequests > 32) {
      throw ArgumentError('Invalid AOT process transport limits.');
    }
    if (this.environment.entries.any(
      (MapEntry<String, String> entry) =>
          entry.key.isEmpty ||
          entry.key.contains('=') ||
          entry.key.contains('\u0000') ||
          entry.value.contains('\u0000'),
    )) {
      throw ArgumentError('Invalid AOT worker environment.');
    }
    _delegate = platform.createProcessTransport(
      executable: executable,
      arguments: this.arguments,
      rmlDirectory: rmlDirectory,
      environment: this.environment,
      timeout: timeout,
      maximumQueryCodeUnits: maximumQueryCodeUnits,
      maximumRequestBytes: maximumRequestBytes,
      maximumResponseBytes: maximumResponseBytes,
      maximumStderrBytes: maximumStderrBytes,
      maximumPendingRequests: maximumPendingRequests,
    );
  }

  /// Whether this platform can launch the native worker. This does not imply
  /// that the executable or dictionaries have been installed.
  static bool get isSupported => platform.processTransportSupported;

  final String executable;
  final List<String> arguments;
  final String? rmlDirectory;
  final Map<String, String> environment;
  final Duration timeout;
  final int maximumQueryCodeUnits;
  final int maximumRequestBytes;
  final int maximumResponseBytes;
  final int maximumStderrBytes;
  final int maximumPendingRequests;
  late final AotTransport _delegate;

  @override
  Future<Object?> request({
    required String action,
    required AotLanguage language,
    required String query,
    bool withParadigms = false,
  }) => _delegate.request(
    action: action,
    language: language,
    query: query,
    withParadigms: withParadigms,
  );

  @override
  Future<void> dispose() => _delegate.dispose();
}
