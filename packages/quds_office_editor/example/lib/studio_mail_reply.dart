import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_mail_ui/quds_mail_ui.dart' show buildMailBodyPresentation;

import 'studio_mail_draft.dart';
import 'studio_mail_recipients.dart';
import 'studio_mail_threading.dart';

/// A missing, unsupported or over-budget body cannot become a text quote.
final class StudioMailReplyUnavailable implements Exception {
  const StudioMailReplyUnavailable();

  @override
  String toString() => 'No safely quotable body is available.';
}

/// The full attachment set is unavailable or outside the composer contract.
/// This failure never exposes source names, bytes or MIME diagnostics.
final class StudioMailForwardAttachmentsUnavailable implements Exception {
  const StudioMailForwardAttachmentsUnavailable();

  @override
  String toString() => 'The complete attachment set cannot be forwarded.';
}

/// Source addresses cannot safely become a complete supported recipient list.
/// Unsupported addresses are never repaired, split or silently dropped from
/// a partial recipient list.
final class StudioMailReplyRecipientsUnavailable implements Exception {
  const StudioMailReplyRecipientsUnavailable();

  @override
  String toString() => 'The source recipient list is unsupported.';
}

/// Builds a bounded text quote from the authoritative, decoded raw message.
///
/// Plain text is authoritative, including an explicitly empty alternative.
/// HTML-only bodies use the bounded inert body projection. Reader headers,
/// Bcc addresses and attachment names/content never become quoted text.
/// Forwarding requires the user to choose a recipient. This entry never
/// copies attachments; use [buildStudioMailForwardWithAttachmentsDraft] for
/// that explicit action. Replies carry validated thread identifiers; forwards
/// never inherit them. Attribution dates use UTC to avoid host-zone ambiguity.
/// Pass the actual [sourceStatus] when the message came from a MIME result;
/// HTML fallback requires a complete parse.
StudioMailDraft buildStudioMailReplyDraft(
  MailMessage message, {
  required bool forward,
  MailParseStatus sourceStatus = MailParseStatus.complete,
  String truncationNotice = '[Quoted text truncated.]',
  String forwardNotice = '[Text-only forward; attachments are not included.]',
}) {
  final envelope = message.envelope;
  final recipient = forward
      ? ''
      : (envelope.replyTo.firstOrNull?.address ??
            envelope.from.firstOrNull?.address ??
            '');
  // One decoded mailbox must remain one mailbox. In particular, a malformed
  // source address containing a list separator must not become two recipients
  // when copied into the editable multi-recipient field.
  if (recipient.isNotEmpty &&
      !StudioMailRecipients.isSupportedAddress(recipient)) {
    throw const StudioMailReplyRecipientsUnavailable();
  }
  return _buildStudioMailDraft(
    message,
    forward: forward,
    to: recipient,
    sourceStatus: sourceStatus,
    truncationNotice: truncationNotice,
    forwardNotice: forwardNotice,
  );
}

/// Starts a new text forward with every decoded attachment included as a file.
///
/// The authoritative parse must be complete: a partial result may have omitted
/// source parts, even when its visible attachment list meets composer limits.
/// Admission is all-or-none, including inline parts. No transport operation or
/// source mutation occurs here; the host opens its normal recoverable composer.
/// A complete attachment-only message uses an empty quote and attribution;
/// malformed HTML is never treated as an empty body.
StudioMailDraft buildStudioMailForwardWithAttachmentsDraft(
  MailParseResult result, {
  String truncationNotice = '[Quoted text truncated.]',
  String forwardNotice =
      '[Forwarded as text with original attachments. Inline images are attached as files.]',
}) {
  final message = result.message;
  if (result.status != MailParseStatus.complete || message == null) {
    throw const StudioMailForwardAttachmentsUnavailable();
  }
  late final StudioMailAttachments attachments;
  try {
    attachments = StudioMailAttachments.forwarded(message.attachments);
  } on StudioMailAttachmentException {
    throw const StudioMailForwardAttachmentsUnavailable();
  }
  return _buildStudioMailDraft(
    message,
    forward: true,
    to: '',
    truncationNotice: truncationNotice,
    forwardNotice: forwardNotice,
    attachments: attachments,
    allowEmptyBody: attachments.isNotEmpty,
  );
}

/// Replies to supported visible participants, excluding the connected sender.
///
/// Reply-To takes precedence over From. Those targets and the original To
/// recipients remain in To; original Cc recipients remain in Cc unless already
/// present in To. Bcc is never inspected or copied. Matching preserves local
/// part case and ignores domain case, with the first spelling retained. The
/// host does not infer aliases or additional identities for self-exclusion.
/// HTML fallback requires a complete [sourceStatus].
StudioMailDraft buildStudioMailReplyAllDraft(
  MailMessage message, {
  required String sender,
  MailParseStatus sourceStatus = MailParseStatus.complete,
  String truncationNotice = '[Quoted text truncated.]',
}) {
  if (!StudioMailRecipients.isSupportedAddress(sender)) {
    throw const StudioMailReplyRecipientsUnavailable();
  }
  final envelope = message.envelope;
  final targets = envelope.replyTo.isNotEmpty
      ? envelope.replyTo
      : envelope.from;
  // Bound even independently constructed envelopes before traversing their
  // address lists. The outgoing list has the stricter composer limit below.
  if (targets.length + envelope.to.length + envelope.cc.length > 1024) {
    throw const StudioMailReplyRecipientsUnavailable();
  }
  final seen = <String>{StudioMailRecipients.identityKey(sender)};
  final to = <String>[];
  final cc = <String>[];
  var count = 0;
  void admit(MailAddress source, List<String> destination) {
    final address = source.address;
    if (!StudioMailRecipients.isSupportedAddress(address)) {
      throw const StudioMailReplyRecipientsUnavailable();
    }
    if (!seen.add(StudioMailRecipients.identityKey(address))) return;
    if (++count > StudioMailRecipients.maxRecipients) {
      throw const StudioMailReplyRecipientsUnavailable();
    }
    destination.add(address);
  }

  for (final target in targets) {
    admit(target, to);
  }
  for (final target in envelope.to) {
    admit(target, to);
  }
  for (final target in envelope.cc) {
    admit(target, cc);
  }
  final toText = to.join(', ');
  final ccText = cc.join(', ');
  // Empty or self-only messages deliberately open an editable, unaddressed
  // draft. Every nonempty result must meet the same limits as manual input.
  if (count > 0 &&
      StudioMailRecipients.tryParse(to: toText, cc: ccText) == null) {
    throw const StudioMailReplyRecipientsUnavailable();
  }
  return _buildStudioMailDraft(
    message,
    forward: false,
    to: toText,
    cc: ccText,
    sourceStatus: sourceStatus,
    truncationNotice: truncationNotice,
  );
}

StudioMailDraft _buildStudioMailDraft(
  MailMessage message, {
  required bool forward,
  required String to,
  String cc = '',
  required String truncationNotice,
  String forwardNotice = '[Text-only forward; attachments are not included.]',
  StudioMailAttachments attachments = const StudioMailAttachments.empty(),
  MailParseStatus sourceStatus = MailParseStatus.complete,
  bool allowEmptyBody = false,
}) {
  final plain =
      message.body.plainText ??
      (allowEmptyBody && message.body.html == null
          ? ''
          : _projectHtmlQuote(message.body, sourceStatus));

  final envelope = message.envelope;
  final subject = envelope.subject;
  final prefix = forward ? 'Fwd: ' : 'Re: ';
  final sender = envelope.from.firstOrNull?.address ?? '';
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
    to: to,
    cc: cc,
    attachments: attachments,
    thread: forward
        ? const StudioMailThread.empty()
        : StudioMailThread.replyTo(envelope),
    subject: subject.toLowerCase().startsWith(prefix.trim().toLowerCase())
        ? subject
        : '$prefix$subject',
    body: '\n\n$header$quoted${truncated ? '\n\n$truncationNotice' : ''}',
  );
}

String _projectHtmlQuote(MailBody body, MailParseStatus sourceStatus) {
  // A syntactically complete HTML fragment may come from truncated MIME.
  // Do not turn that prefix into an apparently complete quotation.
  if (sourceStatus != MailParseStatus.complete) {
    throw const StudioMailReplyUnavailable();
  }
  final presentation = buildMailBodyPresentation(body);
  if (presentation.rejected) throw const StudioMailReplyUnavailable();
  return presentation.bodyText;
}
