import 'compose_body.dart';
import 'identity.dart';

/// One named, literal plain-text fragment owned by a compose-settings snapshot.
/// No markup, variables or recipient substitutions are evaluated by this model.
final class MailQuickText {
  const MailQuickText({
    required this.id,
    required this.name,
    required this.text,
  });

  static const maxIdCodeUnits = 1024;
  static const maxNameCodeUnits = 80;
  static const maxTextCodeUnits = 16384;

  final String id;
  final String name;
  final String text;

  /// Locale-independent name matching. Original Unicode spelling is retained;
  /// this key does not apply accent folding or Unicode normalization.
  String get nameKey => name.trim().toLowerCase();

  bool get isValid =>
      _validComposeIdentity(id) &&
      name.isNotEmpty &&
      name == name.trim() &&
      name.length <= maxNameCodeUnits &&
      _validComposeText(name, multiline: false) &&
      text.length <= maxTextCodeUnits &&
      _validComposeText(text, multiline: true);

  MailQuickText copyWith({String? name, String? text}) =>
      MailQuickText(id: id, name: name ?? this.name, text: text ?? this.text);

  @override
  String toString() => 'MailQuickText(redacted)';
}

/// One named sender choice. This is local authored configuration, not proof
/// that the connected provider permits the address or delegated submission.
/// Hosts keep the chosen values in each immutable draft and prepared message.
final class MailSenderIdentity {
  const MailSenderIdentity({
    required this.id,
    required this.name,
    required this.address,
    this.displayName = '',
    this.replyTo = '',
  });

  static const maxIdCodeUnits = MailQuickText.maxIdCodeUnits;
  static const maxNameCodeUnits = MailQuickText.maxNameCodeUnits;
  static const maxAddressCodeUnits = 254;
  static const maxDisplayNameCodeUnits = 256;

  final String id;
  final String name;
  final String address;
  final String displayName;
  final String replyTo;

  String get nameKey => name.trim().toLowerCase();

  bool get isValid =>
      _validComposeIdentity(id) &&
      _validComposeName(name) &&
      isSupportedAddress(address) &&
      displayName.length <= maxDisplayNameCodeUnits &&
      displayName == displayName.trim() &&
      _validComposeText(displayName, multiline: false) &&
      (replyTo.isEmpty || isSupportedAddress(replyTo));

  /// The current ASCII dot-atom/DNS mailbox subset. Display names belong in
  /// [displayName], not in this field. SMTPUTF8, comments, groups, quoted local
  /// parts and domain literals need separately negotiated transport support.
  static bool isSupportedAddress(String value) {
    if (value.length > maxAddressCodeUnits ||
        value.codeUnits.any((unit) => unit < 0x21 || unit > 0x7e)) {
      return false;
    }
    final parts = value.split('@');
    if (parts.length != 2) return false;
    final local = parts[0];
    final domain = parts[1];
    if (local.isEmpty ||
        local.length > 64 ||
        local.startsWith('.') ||
        local.endsWith('.') ||
        local.contains('..') ||
        !RegExp(r"^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+$").hasMatch(local)) {
      return false;
    }
    final labels = domain.split('.');
    final labelPattern = RegExp(
      r'^[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$',
    );
    return domain.length <= 253 && labels.every(labelPattern.hasMatch);
  }

  MailSenderIdentity copyWith({
    String? name,
    String? address,
    String? displayName,
    String? replyTo,
  }) => MailSenderIdentity(
    id: id,
    name: name ?? this.name,
    address: address ?? this.address,
    displayName: displayName ?? this.displayName,
    replyTo: replyTo ?? this.replyTo,
  );

  @override
  String toString() => 'MailSenderIdentity(redacted)';
}

/// Literal full-message starting content owned by one compose-settings snapshot.
/// Recipients may be incomplete while authoring a template; the composer still
/// validates them before sending. Optional rich content uses the same canonical
/// format as drafts, with a matching plain alternative. No variables, arbitrary
/// HTML, attachment references, thread identity or delivery instructions are
/// evaluated or retained here.
final class MailMessageTemplate {
  const MailMessageTemplate({
    required this.id,
    required this.name,
    this.to = '',
    this.cc = '',
    this.bcc = '',
    this.subject = '',
    this.body = '',
    this.richBody,
    this.senderIdentityId,
  });

  static const maxIdCodeUnits = MailQuickText.maxIdCodeUnits;
  static const maxNameCodeUnits = MailQuickText.maxNameCodeUnits;
  static const maxRecipientCodeUnits = 25600;
  static const maxSubjectCodeUnits = 512;
  static const maxBodyCodeUnits = 16384;

  /// Rich templates remain reusable settings, rather than a second draft store.
  /// Both alternatives also count toward [MailComposeSettings.maxMetadataCodeUnits].
  static const maxRichBodyCodeUnits = 65536;

  final String id;
  final String name;
  final String to;
  final String cc;
  final String bcc;
  final String subject;
  final String body;

  /// Optional canonical alternative for [body]. Their text must agree after
  /// CRLF/CR normalization. Null keeps a legacy template's literal plain text.
  final MailComposeBody? richBody;
  final String? senderIdentityId;

  String get nameKey => name.trim().toLowerCase();

  bool get isValid =>
      _validComposeIdentity(id) &&
      _validComposeName(name) &&
      to.length + cc.length + bcc.length <= maxRecipientCodeUnits &&
      _validComposeText(to, multiline: false) &&
      _validComposeText(cc, multiline: false) &&
      _validComposeText(bcc, multiline: false) &&
      subject.length <= maxSubjectCodeUnits &&
      _validComposeText(subject, multiline: false) &&
      body.length <= maxBodyCodeUnits &&
      _validComposeText(body, multiline: true) &&
      (richBody == null ||
          (richBody!.html.length <= maxRichBodyCodeUnits &&
              richBody!.plainText ==
                  body.replaceAll('\r\n', '\n').replaceAll('\r', '\n'))) &&
      (senderIdentityId == null || _validComposeIdentity(senderIdentityId!));

  /// Changing [body] retains the rich alternative until explicitly replaced or
  /// cleared, so a stale text edit fails validation instead of losing formatting.
  MailMessageTemplate copyWith({
    String? name,
    String? to,
    String? cc,
    String? bcc,
    String? subject,
    String? body,
    MailComposeBody? richBody,
    bool clearRichBody = false,
    String? senderIdentityId,
    bool clearSenderIdentity = false,
  }) => MailMessageTemplate(
    id: id,
    name: name ?? this.name,
    to: to ?? this.to,
    cc: cc ?? this.cc,
    bcc: bcc ?? this.bcc,
    subject: subject ?? this.subject,
    body: body ?? this.body,
    richBody: clearRichBody ? null : richBody ?? this.richBody,
    senderIdentityId: clearSenderIdentity
        ? null
        : senderIdentityId ?? this.senderIdentityId,
  );

  @override
  String toString() => 'MailMessageTemplate(redacted)';
}

/// Immutable account-owned defaults and reusable literal compose text.
///
/// Loading or changing these defaults must not alter an existing draft. A host
/// chooses when to insert text and stores the resulting draft independently.
final class MailComposeSettings {
  MailComposeSettings({
    required this.account,
    this.revision = 0,
    this.signature = '',
    this.signatureForNewMessages = false,
    this.signatureForReplies = false,
    List<MailQuickText> quickTexts = const [],
    List<MailSenderIdentity> senderIdentities = const [],
    List<MailMessageTemplate> templates = const [],
    this.defaultSenderIdentityId,
  }) : quickTexts = List<MailQuickText>.unmodifiable(quickTexts),
       senderIdentities = List<MailSenderIdentity>.unmodifiable(
         senderIdentities,
       ),
       templates = List<MailMessageTemplate>.unmodifiable(templates);

  static const maxSignatureCodeUnits = 16384;
  static const maxTextCodeUnits = 16384;
  static const maxQuickTexts = 32;
  static const maxSenderIdentities = 16;
  static const maxTemplates = 32;
  static const maxMetadataCodeUnits = 131072;
  static const maxRevision = 9007199254740991;

  final MailAccountId account;

  /// Zero is the unsaved default; the repository assigns each next revision.
  final int revision;
  final String signature;
  final bool signatureForNewMessages;
  final bool signatureForReplies;
  final List<MailQuickText> quickTexts;
  final List<MailSenderIdentity> senderIdentities;
  final List<MailMessageTemplate> templates;

  /// Null keeps the connected account's existing sender. Defaults apply only at
  /// a new-draft boundary and never rewrite recovered drafts or queued mail.
  final String? defaultSenderIdentityId;

  /// Exact UTF-16 budget, including ownership and stored name-match keys.
  int get metadataCodeUnits =>
      account.value.length +
      account.profile.value.length +
      account.profile.hostId.length +
      signature.length +
      quickTexts.fold<int>(
        0,
        (sum, item) =>
            sum +
            item.id.length +
            item.name.length +
            item.nameKey.length +
            item.text.length,
      ) +
      (defaultSenderIdentityId?.length ?? 0) +
      senderIdentities.fold<int>(
        0,
        (sum, item) =>
            sum +
            item.id.length +
            item.name.length +
            item.nameKey.length +
            item.address.length +
            item.displayName.length +
            item.replyTo.length,
      ) +
      templates.fold<int>(
        0,
        (sum, item) =>
            sum +
            item.id.length +
            item.name.length +
            item.nameKey.length +
            item.to.length +
            item.cc.length +
            item.bcc.length +
            item.subject.length +
            item.body.length +
            (item.richBody?.html.length ?? 0) +
            (item.senderIdentityId?.length ?? 0),
      );

  bool get isValid {
    if (!_validComposeIdentity(account.value) ||
        !_validComposeIdentity(account.profile.value) ||
        !_validComposeIdentity(account.profile.hostId) ||
        revision < 0 ||
        revision > maxRevision ||
        signature.length > maxSignatureCodeUnits ||
        !_validComposeText(signature, multiline: true) ||
        quickTexts.length > maxQuickTexts ||
        senderIdentities.length > maxSenderIdentities ||
        templates.length > maxTemplates) {
      return false;
    }
    final ids = <String>{};
    final names = <String>{};
    for (final item in quickTexts) {
      if (!item.isValid || !ids.add(item.id) || !names.add(item.nameKey)) {
        return false;
      }
    }
    final senderIds = <String>{};
    final senderNames = <String>{};
    for (final item in senderIdentities) {
      if (!item.isValid ||
          !senderIds.add(item.id) ||
          !senderNames.add(item.nameKey)) {
        return false;
      }
    }
    if (defaultSenderIdentityId != null &&
        !senderIds.contains(defaultSenderIdentityId)) {
      return false;
    }
    final templateIds = <String>{};
    final templateNames = <String>{};
    for (final item in templates) {
      if (!item.isValid ||
          !templateIds.add(item.id) ||
          !templateNames.add(item.nameKey) ||
          (item.senderIdentityId != null &&
              !senderIds.contains(item.senderIdentityId))) {
        return false;
      }
    }
    return metadataCodeUnits <= maxMetadataCodeUnits;
  }

  MailComposeSettings copyWith({
    int? revision,
    String? signature,
    bool? signatureForNewMessages,
    bool? signatureForReplies,
    List<MailQuickText>? quickTexts,
    List<MailSenderIdentity>? senderIdentities,
    List<MailMessageTemplate>? templates,
    String? defaultSenderIdentityId,
    bool clearDefaultSenderIdentity = false,
  }) => MailComposeSettings(
    account: account,
    revision: revision ?? this.revision,
    signature: signature ?? this.signature,
    signatureForNewMessages:
        signatureForNewMessages ?? this.signatureForNewMessages,
    signatureForReplies: signatureForReplies ?? this.signatureForReplies,
    quickTexts: quickTexts ?? this.quickTexts,
    senderIdentities: senderIdentities ?? this.senderIdentities,
    templates: templates ?? this.templates,
    defaultSenderIdentityId: clearDefaultSenderIdentity
        ? null
        : defaultSenderIdentityId ?? this.defaultSenderIdentityId,
  );

  @override
  String toString() => 'MailComposeSettings(redacted)';
}

bool _validComposeName(String value) =>
    value.isNotEmpty &&
    value == value.trim() &&
    value.length <= MailQuickText.maxNameCodeUnits &&
    _validComposeText(value, multiline: false);

bool _validComposeIdentity(String value) =>
    value.isNotEmpty &&
    value == value.trim() &&
    value.length <= MailQuickText.maxIdCodeUnits &&
    _validComposeText(value, multiline: false);

// Reject malformed UTF-16 before UTF-8 storage can silently replace an identity
// or authored character. Bodies allow only TAB, CR and LF from the C0 controls;
// DEL and C1 controls have no compose-text meaning and are rejected everywhere.
bool _validComposeText(String value, {required bool multiline}) {
  for (var index = 0; index < value.length; index++) {
    final unit = value.codeUnitAt(index);
    if (unit < 0x20 || (unit >= 0x7f && unit <= 0x9f)) {
      if (!multiline || (unit != 0x09 && unit != 0x0a && unit != 0x0d)) {
        return false;
      }
    } else if (unit >= 0xd800 && unit <= 0xdbff) {
      if (++index == value.length) return false;
      final low = value.codeUnitAt(index);
      if (low < 0xdc00 || low > 0xdfff) return false;
    } else if (unit >= 0xdc00 && unit <= 0xdfff) {
      return false;
    }
  }
  return true;
}
