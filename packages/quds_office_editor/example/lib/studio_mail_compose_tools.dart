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
      richBody: draft.richBody,
      sender: sender,
      thread: draft.thread,
      attachments: draft.attachments,
    );
  }
  final signature = studioMailSignatureText(settings.signature);
  // Replies retain an editable blank paragraph and put the signature before
  // quoted content. New-message defaults follow any initial text.
  final prefix = replyOrForward
      ? signature +
            (draft.body.isEmpty || draft.body.startsWith('\n\n') ? '' : '\n\n')
      : '';
  final suffix = replyOrForward ? '' : signature;
  final body = prefix + draft.body + suffix;
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
    richBody: draft.richBody == null
        ? null
        : _signatureRichBody(draft.richBody!, prefix, suffix),
    sender: sender,
    thread: draft.thread,
    attachments: draft.attachments,
  );
}

MailComposeBody _signatureRichBody(
  MailComposeBody original,
  String prefix,
  String suffix,
) {
  try {
    final paragraphs = original.paragraphs.toList();
    if (prefix.isNotEmpty) {
      final parts = prefix.split('\n');
      final first = paragraphs.first;
      paragraphs[0] = MailComposeParagraph(
        runs: [
          MailComposeRun(text: parts.last),
          ...first.runs,
        ],
        alignment: first.alignment,
        rightToLeft: first.rightToLeft,
      );
      paragraphs.insertAll(0, [
        for (final text in parts.take(parts.length - 1))
          MailComposeParagraph(runs: [MailComposeRun(text: text)]),
      ]);
    }
    if (suffix.isNotEmpty) {
      final parts = suffix.split('\n');
      final last = paragraphs.last;
      paragraphs[paragraphs.length - 1] = MailComposeParagraph(
        runs: [
          ...last.runs,
          MailComposeRun(text: parts.first),
        ],
        alignment: last.alignment,
        rightToLeft: last.rightToLeft,
      );
      paragraphs.addAll([
        for (final text in parts.skip(1))
          MailComposeParagraph(runs: [MailComposeRun(text: text)]),
      ]);
    }
    return MailComposeBody(paragraphs: paragraphs);
  } on Object {
    throw const StudioMailComposeToolsException();
  }
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
