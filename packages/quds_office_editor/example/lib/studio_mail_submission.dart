import 'package:enough_mail/enough_mail.dart' as mail;

import 'studio_mail_compose.dart';

/// Constructs ASCII-safe MIME plus one explicit recipient. The caller owns
/// submission outcome and must not combine SMTP with concurrent Sent filing.
mail.MimeMessage buildStudioMailMessage(StudioMailDraft draft, String sender) {
  if (draft.problem != null || !StudioMailDraft.isSupportedAddress(sender)) {
    throw const FormatException('Invalid Studio Mail submission.');
  }
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
        ..to = <mail.MailAddress>[mail.MailAddress('', draft.to)]
        ..subject = draft.subject;
  return builder.buildMimeMessage();
}
