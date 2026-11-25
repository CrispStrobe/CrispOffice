import 'dart:convert';

import 'package:quds_mail_core/quds_mail_core.dart';

import 'studio_mail_attachment.dart';
import 'studio_mail_recipients.dart';
import 'studio_mail_threading.dart';

export 'studio_mail_attachment.dart';

enum StudioMailDraftProblem { recipient, subject, body, sender }

/// The authored sender is frozen with the draft, independently of later edits
/// to account identities. It never changes the account used for authentication.
final class StudioMailSender {
  const StudioMailSender({
    required this.address,
    this.displayName = '',
    this.replyTo = '',
  });

  factory StudioMailSender.fromIdentity(MailSenderIdentity identity) =>
      StudioMailSender(
        address: identity.address,
        displayName: identity.displayName,
        replyTo: identity.replyTo,
      );

  final String address;
  final String displayName;
  final String replyTo;

  bool get isValid => MailSenderIdentity(
    id: 'draft-sender',
    name: 'Draft sender',
    address: address,
    displayName: displayName,
    replyTo: replyTo,
  ).isValid;

  @override
  bool operator ==(Object other) =>
      other is StudioMailSender &&
      address == other.address &&
      displayName == other.displayName &&
      replyTo == other.replyTo;

  @override
  int get hashCode => Object.hash(address, displayName, replyTo);

  @override
  String toString() => 'StudioMailSender(redacted)';
}

/// Immutable submission snapshot, owned by the current Mail session.
final class StudioMailDraft {
  const StudioMailDraft({
    required this.to,
    required this.subject,
    required this.body,
    this.cc = '',
    this.bcc = '',
    this.sender,
    this.thread = const StudioMailThread.empty(),
    this.attachments = const StudioMailAttachments.empty(),
  });

  final String to;
  final String cc;
  final String bcc;
  final String subject;
  final String body;
  final StudioMailSender? sender;
  final StudioMailThread thread;
  final StudioMailAttachments attachments;

  static const maxBodyBytes = 1024 * 1024;

  static bool isSupportedAddress(String address) =>
      StudioMailRecipients.isSupportedAddress(address);

  StudioMailRecipients get recipients =>
      StudioMailRecipients.tryParse(to: to, cc: cc, bcc: bcc) ??
      (throw const FormatException('Invalid Studio Mail recipients.'));

  StudioMailDraftProblem? get problem {
    if (sender != null && !sender!.isValid) {
      return StudioMailDraftProblem.sender;
    }
    if (StudioMailRecipients.tryParse(to: to, cc: cc, bcc: bcc) == null) {
      return StudioMailDraftProblem.recipient;
    }
    if (subject.length > 512 || subject.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
      return StudioMailDraftProblem.subject;
    }
    if (body.length > maxBodyBytes ||
        body.contains('\u0000') ||
        utf8.encode(body).length > maxBodyBytes) {
      return StudioMailDraftProblem.body;
    }
    return null;
  }
}
