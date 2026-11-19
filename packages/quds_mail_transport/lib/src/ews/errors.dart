import 'package:quds_mail_core/quds_mail_core.dart';

/// Internal content-free exception; never retains server text or credentials.
final class EwsException implements Exception {
  const EwsException(
    this.code, {
    this.retryAfter,
    this.invalidSyncState = false,
  });
  final MailProblemCode code;
  final Duration? retryAfter;
  final bool invalidSyncState;

  @override
  String toString() => 'EWS operation failed (${code.name}).';
}
