import 'package:quds_mail_core/quds_mail_core.dart';
import 'package:quds_office_engine/quds_productivity_automation.dart';

import 'studio_mail_draft.dart';

ProductivityAction studioMcpSendAction({
  required String sender,
  required Future<MailOutboxEntry?> Function(StudioMailDraft, bool Function())
  send,
}) => ProductivityAction(
  label: 'Send plain-text email',
  destination: sender,
  subject: 'New message',
  fields: const {'to': 254, 'title': 250, 'text': 3000},
  prepare: (args) {
    final recipient = args['to']!;
    final subject = args['title']!;
    final draft = StudioMailDraft(
      to: recipient,
      subject: subject,
      body: args['text']!,
    );
    if (!StudioMailDraft.isSupportedAddress(recipient) ||
        draft.problem != null ||
        subject.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
      throw const FormatException('Invalid plain-text email');
    }
    return ProductivityActionPlan(
      label: 'Approve and send email',
      destination: 'From $sender to $recipient',
      subject: subject,
      details: draft.body,
      execute: (current) async {
        if (!current()) return ProductivityApprovalOutcome.rejected;
        final result = await send(draft, current);
        return switch (result?.state) {
          MailOutboxState.submitted => ProductivityApprovalOutcome.sent,
          MailOutboxState.queued => ProductivityApprovalOutcome.queued,
          _ => ProductivityApprovalOutcome.unconfirmed,
        };
      },
    );
  },
);

ProductivityApprovalOutcome studioMcpDeleteOutcome(
  MailBulkFlagReport? report,
  MailBulkFlagReport? previous,
  MailRemoteIdentity identity,
) {
  if (report == null || identical(previous, report)) {
    return ProductivityApprovalOutcome.unconfirmed;
  }
  final item = report.items.singleOrNull;
  if (item == null ||
      item.operation is! MailDelete ||
      item.operation.message != identity) {
    return ProductivityApprovalOutcome.unconfirmed;
  }
  return item.outcome == MailBulkFlagOutcome.confirmed
      ? ProductivityApprovalOutcome.saved
      : ProductivityApprovalOutcome.unconfirmed;
}
