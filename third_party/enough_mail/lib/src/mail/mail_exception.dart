import '../../enough_mail.dart';

/// Provides details about high level unexpected events
class MailException implements Exception {
  /// Creates a new exception
  MailException(this.mailClient, this.message, {this.stackTrace, this.details});

  /// Creates a new exception from the low level one
  MailException.fromImap(
    MailClient mailClient,
    ImapException e, [
    StackTrace? s,
  ]) : this(
         mailClient,
         '${e.imapClient.logName}:  ${e.message}',
         stackTrace: s ?? e.stackTrace,
         details: e.details,
       );

  /// Creates a new exception from the low level one
  MailException.fromPop(MailClient mailClient, PopException e, [StackTrace? s])
    : this(
        mailClient,
        '${e.popClient.logName}:  ${e.message}',
        stackTrace: s ?? e.stackTrace,
        details: e.response,
      );

  /// Creates a new exception from the low level one
  MailException.fromSmtp(
    MailClient mailClient,
    SmtpException e, [
    StackTrace? s,
  ]) : this(
         mailClient,
         '${e.smtpClient.logName}:  ${e.message}',
         stackTrace: s ?? e.stackTrace,
         details: e.response,
       );

  /// The originating mail client
  final MailClient mailClient;

  /// The error message
  final String? message;

  /// The stacktrace
  final StackTrace? stackTrace;

  /// Any details
  final dynamic details;

  @override
  String toString() {
    final buffer = StringBuffer()
      ..write('MailException: ')
      ..write(message);
    if (details != null) {
      buffer
        ..write('\n')
        ..write(details);
    }
    if (stackTrace != null) {
      buffer
        ..write('\n')
        ..write(stackTrace);
    }

    return buffer.toString();
  }
}

/// SMTP accepted the message, but filing its sent copy or cleanup failed.
///
/// Callers must not retry SMTP submission because of this exception. Inspect
/// [sentCopyError] and [cleanupError] to report or recover the remaining work.
class MailSendPostSubmissionException extends MailException {
  /// Creates an outcome for a confirmed submission with unfinished follow-up.
  MailSendPostSubmissionException(
    MailClient mailClient, {
    this.sentCopyError,
    this.sentCopyStackTrace,
    this.cleanupError,
    this.cleanupStackTrace,
  }) : assert(
         sentCopyError != null || cleanupError != null,
         'A post-submission failure is required.',
       ),
       super(
         mailClient,
         'Message was submitted, but saving its sent copy or closing the '
         'connection failed.',
         stackTrace: sentCopyStackTrace ?? cleanupStackTrace,
       );

  /// The original failure to find or append to the Sent mailbox, if any.
  final Object? sentCopyError;

  /// The original stack trace for [sentCopyError], if any.
  final StackTrace? sentCopyStackTrace;

  /// The original outgoing-connection cleanup failure, if any.
  final Object? cleanupError;

  /// The original stack trace for [cleanupError], if any.
  final StackTrace? cleanupStackTrace;
}
