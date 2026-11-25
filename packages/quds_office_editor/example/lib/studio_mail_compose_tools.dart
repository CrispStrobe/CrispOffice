import 'dart:convert';

import 'package:quds_mail_core/quds_mail_core.dart';

import 'studio_mail_draft.dart';

/// Optional account-owned writing tools. The owner serializes these operations
/// with draft writes and drains them before releasing its repository.
abstract interface class StudioMailComposeToolsStore {
  MailAccountId get account;
  Future<MailComposeSettings> loadComposeSettings();
  Future<MailComposeSettings> saveComposeSettings(MailComposeSettings settings);
}

/// No message text or account metadata is included in diagnostics.
final class StudioMailComposeToolsException implements Exception {
  const StudioMailComposeToolsException();

  @override
  String toString() => 'Writing tools are unavailable.';
}

String studioMailComposeText(String text) =>
    text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

String studioMailSignatureText(String signature) =>
    '\n\n-- \n${studioMailComposeText(signature)}';

/// Applies defaults only at a new-draft boundary. Resume, outgoing-message
/// recovery and settings changes never call this on an existing saved draft.
StudioMailDraft applyStudioMailDefaultSignature(
  StudioMailDraft draft,
  MailComposeSettings settings, {
  required bool replyOrForward,
}) {
  if (!settings.isValid) throw const StudioMailComposeToolsException();
  final identity = settings.defaultSenderIdentityId == null
      ? null
      : settings.senderIdentities.firstWhere(
          (item) => item.id == settings.defaultSenderIdentityId,
        );
  final sender =
      draft.sender ??
      (identity == null ? null : StudioMailSender.fromIdentity(identity));
  if (settings.signature.isEmpty ||
      !(replyOrForward
          ? settings.signatureForReplies
          : settings.signatureForNewMessages)) {
    if (sender == draft.sender) return draft;
    return StudioMailDraft(
      to: draft.to,
      cc: draft.cc,
      bcc: draft.bcc,
      subject: draft.subject,
      body: draft.body,
      sender: sender,
      thread: draft.thread,
      attachments: draft.attachments,
    );
  }
  final signature = studioMailSignatureText(settings.signature);
  // Replies retain an editable blank paragraph and put the signature before
  // quoted content. New-message defaults follow any initial text.
  final body = replyOrForward
      ? signature +
            (draft.body.isEmpty || draft.body.startsWith('\n\n')
                ? ''
                : '\n\n') +
            draft.body
      : draft.body + signature;
  if (body.length > StudioMailDraft.maxBodyBytes ||
      utf8.encode(body).length > StudioMailDraft.maxBodyBytes) {
    throw const StudioMailComposeToolsException();
  }
  return StudioMailDraft(
    to: draft.to,
    cc: draft.cc,
    bcc: draft.bcc,
    subject: draft.subject,
    body: body,
    sender: sender,
    thread: draft.thread,
    attachments: draft.attachments,
  );
}

/// Applies a complete, literal template as a new message. The host confirms
/// replacement before calling this; it does not carry attachments or reply
/// threading into an unrelated reusable message.
StudioMailDraft applyStudioMailTemplate(
  MailMessageTemplate template,
  MailComposeSettings settings,
) {
  if (!settings.isValid || !settings.templates.contains(template)) {
    throw const StudioMailComposeToolsException();
  }
  final identity = template.senderIdentityId == null
      ? null
      : settings.senderIdentities.firstWhere(
          (item) => item.id == template.senderIdentityId,
        );
  return StudioMailDraft(
    to: template.to,
    cc: template.cc,
    bcc: template.bcc,
    subject: template.subject,
    body: studioMailComposeText(template.body),
    sender: identity == null ? null : StudioMailSender.fromIdentity(identity),
  );
}

Future<StudioMailDraft> prepareStudioMailComposeDraft(
  Object owner,
  StudioMailDraft draft, {
  required bool replyOrForward,
  required bool Function() isCurrent,
}) async {
  if (!isCurrent()) throw const StudioMailComposeToolsException();
  if (owner is! StudioMailComposeToolsStore) return draft;
  final account = owner.account;
  final settings = await owner.loadComposeSettings();
  if (!isCurrent() ||
      owner.account != account ||
      settings.account != account ||
      !settings.isValid) {
    throw const StudioMailComposeToolsException();
  }
  return applyStudioMailDefaultSignature(
    draft,
    settings,
    replyOrForward: replyOrForward,
  );
}
