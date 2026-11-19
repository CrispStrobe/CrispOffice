import 'package:quds_mail_core/quds_mail_core.dart';

import 'studio_mail_compose.dart';
import 'studio_mail_threading.dart';

/// An HTML-only or unsupported body cannot become a plain-text quote silently.
final class StudioMailReplyUnavailable implements Exception {
  const StudioMailReplyUnavailable();

  @override
  String toString() => 'No decoded plain-text body is available.';
}

/// Builds a bounded text quote from the authoritative, decoded raw message.
///
/// Only the plain body is quoted. Reader presentation headers, Bcc addresses,
/// HTML and attachment names/content are never used as a fallback. Forwarding
/// requires the user to choose a recipient and explicitly identifies the
/// text-only boundary. Replies carry bounded, validated thread identifiers;
/// forwards never inherit them. Attachment forwarding remains outside this
/// draft contract. Attribution dates use UTC to avoid host-zone ambiguity.
StudioMailDraft buildStudioMailReplyDraft(
  MailMessage message, {
  required bool forward,
  String truncationNotice = '[Quoted text truncated.]',
  String forwardNotice = '[Text-only forward; attachments are not included.]',
}) {
  final plain = message.body.plainText;
  if (plain == null) throw const StudioMailReplyUnavailable();

  final envelope = message.envelope;
  final subject = envelope.subject;
  final prefix = forward ? 'Fwd: ' : 'Re: ';
  final sender = envelope.from.firstOrNull?.address ?? '';
  final recipient = forward
      ? ''
      : (envelope.replyTo.firstOrNull?.address ?? sender);
  final date = envelope.sentAt?.toUtc().toIso8601String();

  // The bound counts Unicode scalar values, so a UTF-16 surrogate pair cannot
  // be cut in half. Even all non-BMP text remains bounded to 32,000 UTF-8 bytes
  // before quote prefixes and attribution are added.
  final normalized = plain.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final selected = StringBuffer();
  var scalars = 0;
  var truncated = false;
  for (final scalar in normalized.runes) {
    if (scalars == 8000) {
      truncated = true;
      break;
    }
    selected.writeCharCode(scalar);
    scalars++;
  }
  final quoted = selected
      .toString()
      .split('\n')
      .map((line) => '> $line')
      .join('\n');
  final header = forward
      ? '$forwardNotice\n'
            '---------- Forwarded message ----------\n'
            'From: $sender\n'
            '${date == null ? '' : 'Date: $date\n'}'
            'Subject: $subject\n\n'
      : date == null
      ? '$sender wrote:\n'
      : 'On $date, $sender wrote:\n';
  return StudioMailDraft(
    to: recipient,
    thread: forward
        ? const StudioMailThread.empty()
        : StudioMailThread.replyTo(envelope),
    subject: subject.toLowerCase().startsWith(prefix.trim().toLowerCase())
        ? subject
        : '$prefix$subject',
    body: '\n\n$header$quoted${truncated ? '\n\n$truncationNotice' : ''}',
  );
}
