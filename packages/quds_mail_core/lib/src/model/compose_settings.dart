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

  MailQuickText copyWith({String? name, String? text}) => MailQuickText(
    id: id,
    name: name ?? this.name,
    text: text ?? this.text,
  );

  @override
  String toString() => 'MailQuickText(redacted)';
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
  }) : quickTexts = List<MailQuickText>.unmodifiable(quickTexts);

  static const maxSignatureCodeUnits = 16384;
  static const maxTextCodeUnits = 16384;
  static const maxQuickTexts = 32;
  static const maxMetadataCodeUnits = 131072;
  static const maxRevision = 9007199254740991;

  final MailAccountId account;

  /// Zero is the unsaved default; the repository assigns each next revision.
  final int revision;
  final String signature;
  final bool signatureForNewMessages;
  final bool signatureForReplies;
  final List<MailQuickText> quickTexts;

  /// Exact UTF-16 budget, including ownership and stored name-match keys.
  int get metadataCodeUnits =>
      account.value.length +
      account.profile.value.length +
      account.profile.hostId.length +
      signature.length +
      quickTexts.fold<int>(
        0,
        (sum, item) =>
            sum + item.id.length + item.name.length + item.nameKey.length +
            item.text.length,
      );

  bool get isValid {
    if (!_validComposeIdentity(account.value) ||
        !_validComposeIdentity(account.profile.value) ||
        !_validComposeIdentity(account.profile.hostId) ||
        revision < 0 ||
        revision > maxRevision ||
        signature.length > maxSignatureCodeUnits ||
        !_validComposeText(signature, multiline: true) ||
        quickTexts.length > maxQuickTexts) {
      return false;
    }
    final ids = <String>{};
    final names = <String>{};
    for (final item in quickTexts) {
      if (!item.isValid ||
          !ids.add(item.id) ||
          !names.add(item.nameKey)) {
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
  }) => MailComposeSettings(
    account: account,
    revision: revision ?? this.revision,
    signature: signature ?? this.signature,
    signatureForNewMessages:
        signatureForNewMessages ?? this.signatureForNewMessages,
    signatureForReplies: signatureForReplies ?? this.signatureForReplies,
    quickTexts: quickTexts ?? this.quickTexts,
  );

  @override
  String toString() => 'MailComposeSettings(redacted)';
}

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
