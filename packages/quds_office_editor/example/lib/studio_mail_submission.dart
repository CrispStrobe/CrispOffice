import 'package:enough_mail/enough_mail.dart' as mail;

import 'studio_mail_draft.dart';

/// Constructs ASCII-safe MIME with visible To/Cc and no Bcc header.
/// The caller must use the envelope in [StudioMailDraft.recipients], including
/// hidden recipients, and must not combine SMTP with concurrent Sent filing.
mail.MimeMessage buildStudioMailMessage(StudioMailDraft draft, String sender) {
  if (draft.problem != null || !StudioMailDraft.isSupportedAddress(sender)) {
    throw const FormatException('Invalid Studio Mail submission.');
  }
  final recipients = draft.recipients;
  final escaped = draft.body
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .replaceAll('\n', '<br>');
  final builder =
      mail.MessageBuilder.prepareMultipartAlternativeMessage(
          plainText: draft.body,
          htmlText: '<p>$escaped</p>',
          transferEncoding: mail.TransferEncoding.quotedPrintable,
        )
        ..from = <mail.MailAddress>[mail.MailAddress('', sender)]
        ..to = [
          for (final address in recipients.to) mail.MailAddress('', address),
        ]
        ..cc = [
          for (final address in recipients.cc) mail.MailAddress('', address),
        ]
        ..subject = draft.subject;
  if (draft.thread.inReplyTo case final parent?) {
    builder
      ..setHeader('In-Reply-To', parent)
      ..setHeader('References', draft.thread.references);
  }
  return builder.buildMimeMessage();
}
