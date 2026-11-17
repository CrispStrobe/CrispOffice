import 'models.dart';
import 'transport.dart';

const bool processTransportSupported = false;

AotTransport createProcessTransport({
  required String executable,
  required List<String> arguments,
  required String? rmlDirectory,
  required Map<String, String> environment,
  required Duration timeout,
  required int maximumQueryCodeUnits,
  required int maximumRequestBytes,
  required int maximumResponseBytes,
  required int maximumStderrBytes,
  required int maximumPendingRequests,
}) => _UnavailableAotProcessTransport();

final class _UnavailableAotProcessTransport implements AotTransport {
  bool _disposed = false;

  @override
  Future<Object?> request({
    required String action,
    required AotLanguage language,
    required String query,
    bool withParadigms = false,
  }) async {
    if (_disposed) {
      throw const AotException(
        AotErrorCode.disposed,
        'AOT process transport is disposed.',
      );
    }
    throw const AotException(
      AotErrorCode.unavailable,
      'This platform cannot start a local AOT worker. Use a desktop host or an '
      'explicitly configured HTTP transport.',
    );
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
  }
}
