import '../../mail/mail_client.dart';
import '../../mail/mail_exception.dart';

/// Submits once, then files the accepted message and closes its connection.
///
/// The caller owns connection serialization. A submission failure retains its
/// original identity and stack; follow-up failures have a distinct outcome so
/// callers cannot mistake a confirmed submission for an unsent message.
Future<void> submitMessageAndStoreCopy(
  MailClient client, {
  required Future<void> Function() submit,
  required Future<void> Function() disconnect,
  Future<void> Function()? storeCopy,
}) async {
  try {
    await submit();
  } catch (_) {
    try {
      await disconnect();
    } catch (_) {
      // Cleanup must not replace the original submission failure.
    }
    rethrow;
  }

  Object? sentCopyError;
  StackTrace? sentCopyStackTrace;
  if (storeCopy != null) {
    try {
      await storeCopy();
    } catch (error, stackTrace) {
      sentCopyError = error;
      sentCopyStackTrace = stackTrace;
    }
  }

  Object? cleanupError;
  StackTrace? cleanupStackTrace;
  try {
    await disconnect();
  } catch (error, stackTrace) {
    cleanupError = error;
    cleanupStackTrace = stackTrace;
  }

  if (sentCopyError != null || cleanupError != null) {
    throw MailSendPostSubmissionException(
      client,
      sentCopyError: sentCopyError,
      sentCopyStackTrace: sentCopyStackTrace,
      cleanupError: cleanupError,
      cleanupStackTrace: cleanupStackTrace,
    );
  }
}
