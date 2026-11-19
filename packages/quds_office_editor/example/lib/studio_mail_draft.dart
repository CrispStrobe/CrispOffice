import 'dart:convert';

import 'studio_mail_recipients.dart';
import 'studio_mail_threading.dart';

enum StudioMailDraftProblem { recipient, subject, body }

/// Immutable plain-text submission snapshot, owned by the current Mail session.
final class StudioMailDraft {
  const StudioMailDraft({
    required this.to,
    required this.subject,
    required this.body,
    this.cc = '',
    this.bcc = '',
    this.thread = const StudioMailThread.empty(),
  });

  final String to;
  final String cc;
  final String bcc;
  final String subject;
  final String body;
  final StudioMailThread thread;

  static const maxBodyBytes = 1024 * 1024;

  static bool isSupportedAddress(String address) =>
      StudioMailRecipients.isSupportedAddress(address);

  StudioMailRecipients get recipients =>
      StudioMailRecipients.tryParse(to: to, cc: cc, bcc: bcc) ??
      (throw const FormatException('Invalid Studio Mail recipients.'));

  StudioMailDraftProblem? get problem {
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
