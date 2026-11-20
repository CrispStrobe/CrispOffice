import 'dart:convert';

import 'package:enough_mail/enough_mail.dart' as mail;

import 'studio_mail_draft.dart';

/// Leaves room for private Bcc headers and the providers' outer base64 request
/// encoding beneath the default 32 MiB cloud request budget.
const studioMailMaxWireBytes = 22 * 1024 * 1024;

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
  final builder = draft.attachments.isEmpty
      ? mail.MessageBuilder.prepareMultipartAlternativeMessage()
      : mail.MessageBuilder.prepareMultipartMixedMessage();
  final body = draft.attachments.isEmpty
      ? builder
      : builder.addPart(mediaSubtype: mail.MediaSubtype.multipartAlternative);
  // Set each child's encoding explicitly: the convenience constructor's
  // transferEncoding does not propagate into addTextPlain/addTextHtml.
  body
    ..addTextPlain(
      draft.body,
      transferEncoding: mail.TransferEncoding.quotedPrintable,
    )
    ..addTextHtml(
      '<p>$escaped</p>',
      transferEncoding: mail.TransferEncoding.quotedPrintable,
    );
  builder
    ..from = <mail.MailAddress>[mail.MailAddress('', sender)]
    ..to = [for (final address in recipients.to) mail.MailAddress('', address)]
    ..cc = [for (final address in recipients.cc) mail.MailAddress('', address)]
    ..subject = draft.subject;
  for (final attachment in draft.attachments.items) {
    final filename = _rfc2231Filename(attachment.name);
    final disposition = mail.ContentDispositionHeader.attachment(
      size: attachment.length,
    )..parameters['filename*'] = filename;
    final mediaType = mail.MediaType.fromText(attachment.mediaType);
    final part = builder.addBinary(
      attachment.content.bytes,
      mediaType,
      disposition: disposition,
    );
    // Binary text/* files retain their original encoding. No guessed charset
    // and no raw user-provided filename may appear in either MIME header.
    part.contentType = mail.ContentTypeHeader.from(mediaType)
      ..parameters['name*'] = filename;
  }
  if (draft.thread.inReplyTo case final parent?) {
    builder
      ..setHeader('In-Reply-To', parent)
      ..setHeader('References', draft.thread.references);
  }
  final message = builder.buildMimeMessage();
  final wire = message.renderMessage();
  if (wire.length > studioMailMaxWireBytes) {
    throw const StudioMailAttachmentException(
      StudioMailAttachmentProblem.tooLarge,
    );
  }
  return message;
}

String _rfc2231Filename(String name) =>
    "utf-8''${utf8.encode(name).map((byte) => '%${byte.toRadixString(16).padLeft(2, '0').toUpperCase()}').join()}";
