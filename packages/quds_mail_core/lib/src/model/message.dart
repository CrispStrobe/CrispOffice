import 'bytes.dart';
import 'identity.dart';

/// A decoded display address; transport validation happens when preparing send.
final class MailAddress {
  const MailAddress(this.address, {this.displayName});
  final String address;
  final String? displayName;
}

/// Header projection. This is deliberately separate from the SMTP envelope.
final class MailEnvelope {
  MailEnvelope({
    this.subject = '',
    List<MailAddress> from = const [],
    List<MailAddress> to = const [],
    List<MailAddress> cc = const [],
    List<MailAddress> bcc = const [],
    List<MailAddress> replyTo = const [],
    this.sentAt,
    this.messageId,
    this.inReplyTo,
    List<String> references = const [],
  }) : from = List.unmodifiable(from),
       to = List.unmodifiable(to),
       cc = List.unmodifiable(cc),
       bcc = List.unmodifiable(bcc),
       replyTo = List.unmodifiable(replyTo),
       references = List.unmodifiable(references);

  final String subject;
  final List<MailAddress> from;
  final List<MailAddress> to;
  final List<MailAddress> cc;
  final List<MailAddress> bcc;
  final List<MailAddress> replyTo;
  final DateTime? sentAt;
  final String? messageId;
  final String? inReplyTo;
  final List<String> references;
}

/// Selected MIME alternatives. HTML is untrusted until a renderer sanitizes it.
final class MailBody {
  const MailBody({
    this.plainText,
    this.html,
    this.plainPartPath,
    this.htmlPartPath,
  });
  final String? plainText;
  final String? html;
  final String? plainPartPath;
  final String? htmlPartPath;
}

/// A bounded decoded attachment snapshot, never a writable path to its source.
final class MailAttachment {
  const MailAttachment({
    required this.partPath,
    required this.mediaType,
    required this.displayName,
    required this.content,
    this.contentId,
    this.declaredSize,
    this.inline = false,
  });
  final String partPath;
  final String mediaType;
  final String displayName;
  final MailBytes content;
  final String? contentId;
  final int? declaredSize;
  final bool inline;
  int get observedSize => content.length;
}

final class MailMessage {
  MailMessage({
    required this.raw,
    required this.envelope,
    this.body = const MailBody(),
    List<MailAttachment> attachments = const [],
    this.localId,
    this.remoteIdentity,
  }) : attachments = List.unmodifiable(attachments);

  final MailBytes raw;
  final MailEnvelope envelope;
  final MailBody body;
  final List<MailAttachment> attachments;
  final MailMessageId? localId;
  final MailRemoteIdentity? remoteIdentity;
}
