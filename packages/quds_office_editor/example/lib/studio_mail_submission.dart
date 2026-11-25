import 'dart:convert';

import 'package:enough_mail/enough_mail.dart' as mail;
import 'package:quds_mail_core/quds_mail_core.dart';

import 'studio_mail_draft.dart';

/// Leaves room for private Bcc headers and the providers' outer base64 request
/// encoding beneath the default 32 MiB cloud request budget.
const studioMailMaxWireBytes = 150 * 1024 * 1024;

/// Constructs ASCII-safe MIME with visible To/Cc and no Bcc header.
/// The caller must use the envelope in [StudioMailDraft.recipients], including
/// hidden recipients, and must not combine SMTP with concurrent Sent filing.
mail.MimeMessage buildStudioMailMessage(StudioMailDraft draft, String sender) {
  if (draft.problem != null || !StudioMailDraft.isSupportedAddress(sender)) {
    throw const FormatException('Invalid Studio Mail submission.');
  }
  final recipients = draft.recipients;
  final authored = draft.sender;
  final html = draft.richBody?.html ?? _plainHtml(draft.body);
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
      html,
      transferEncoding: mail.TransferEncoding.quotedPrintable,
    );
  builder
    ..from = <mail.MailAddress>[
      mail.MailAddress(
        authored?.displayName ?? '',
        authored?.address ?? sender,
      ),
    ]
    ..to = [for (final address in recipients.to) mail.MailAddress('', address)]
    ..cc = [for (final address in recipients.cc) mail.MailAddress('', address)]
    ..subject = draft.subject;
  if (authored != null && authored.replyTo.isNotEmpty) {
    builder.setHeader('Reply-To', authored.replyTo);
  }
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

String _plainHtml(String text) =>
    '<p>${text.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;').replaceAll('\r\n', '\n').replaceAll('\r', '\n').replaceAll('\n', '<br>')}</p>';

String _rfc2231Filename(String name) =>
    "utf-8''${utf8.encode(name).map((byte) => '%${byte.toRadixString(16).padLeft(2, '0').toUpperCase()}').join()}";

/// Replays frozen ASCII MIME without rebuilding Date, Message-ID, boundaries or
/// attachments. The explicit envelope retains Bcc without adding a wire header.
Future<MailSubmissionResult> submitStudioMailNativeOutbox(
  mail.MailClient client,
  MailPreparedMessage prepared, {
  required String attemptId,
}) async {
  final mail.MimeMessage message;
  try {
    final wire = ascii.decode(prepared.wire.bytes);
    message = mail.MimeMessage.parseFromText(wire);
    if (message.renderMessage() != wire) throw const FormatException();
  } on Object {
    return MailSubmissionResult(
      attemptId: attemptId,
      outcome: MailSubmissionOutcome.rejected,
    );
  }
  try {
    await client.sendMessage(
      message,
      from: mail.MailAddress('', prepared.envelope.sender),
      appendToSent: false,
      recipients: [
        for (final address in prepared.envelope.recipients)
          mail.MailAddress('', address),
      ],
    );
    return MailSubmissionResult(
      attemptId: attemptId,
      outcome: MailSubmissionOutcome.accepted,
    );
  } on mail.MailSendPostSubmissionException catch (error) {
    return MailSubmissionResult(
      attemptId: attemptId,
      outcome: identical(error.mailClient, client)
          ? MailSubmissionOutcome.accepted
          : MailSubmissionOutcome.uncertain,
    );
  } on Object {
    // The aggregate native API cannot prove whether DATA was accepted after
    // arbitrary connection failures. Do not convert them to safe auto-retries.
    return MailSubmissionResult(
      attemptId: attemptId,
      outcome: MailSubmissionOutcome.uncertain,
    );
  }
}
