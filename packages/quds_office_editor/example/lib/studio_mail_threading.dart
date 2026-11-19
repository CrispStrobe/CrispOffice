import 'package:quds_mail_core/quds_mail_core.dart';

/// Validated, immutable reply headers for one foreground Studio draft.
///
/// Only canonical ASCII dot-atom Message-IDs are admitted. Quoted, obsolete,
/// domain-literal, internationalized, malformed and overlong IDs are omitted
/// rather than rewritten. An absent or unsupported parent leaves the reply
/// unthreaded; its recipient, subject and quoted body remain usable. Any
/// unsupported References token discards that entire ancestor chain, preventing
/// an ID inside a comment or malformed field from becoming a thread ancestor.
final class StudioMailThread {
  const StudioMailThread.empty() : inReplyTo = null, references = null;

  const StudioMailThread._(this.inReplyTo, this.references);

  factory StudioMailThread.replyTo(MailEnvelope envelope) {
    final parent = envelope.messageId;
    if (parent == null || !_canonicalMessageId(parent)) {
      return const StudioMailThread.empty();
    }

    // The MIME codec already bounds source headers. Also bound work for
    // independently constructed envelopes without traversing an oversized list.
    if (envelope.references.length > _maxSourceReferences) {
      return StudioMailThread._(parent, parent);
    }

    final ancestors = <String>[];
    final seen = <String>{parent};
    void admit(String candidate) {
      if (seen.add(candidate)) ancestors.add(candidate);
    }

    if (envelope.references.isEmpty) {
      // MailEnvelope represents absent and empty References identically.
      // Only in this case may one canonical In-Reply-To ID supply ancestry.
      // Do not salvage a multi-ID value or extract IDs from comments.
      final previous = envelope.inReplyTo;
      if (previous != null && _canonicalMessageId(previous)) admit(previous);
    } else {
      for (final candidate in envelope.references) {
        // The codec splits References on whitespace, so individually dropping
        // bad tokens could accidentally retain an ID from inside a comment.
        if (!_canonicalMessageId(candidate)) {
          return StudioMailThread._(parent, parent);
        }
        admit(candidate);
      }
    }
    if (ancestors.isEmpty) return StudioMailThread._(parent, parent);

    // Preserve the oldest valid ancestor and the newest contiguous tail.
    // IDs are ASCII, so code-unit lengths are exactly header-value byte counts.
    // The two IDs always fit: each is at most 254 bytes including brackets.
    final root = ancestors.first;
    var length = root.length + 1 + parent.length;
    final newest = <String>[];
    for (var index = ancestors.length - 1; index > 0; index--) {
      final candidate = ancestors[index];
      final nextLength = length + 1 + candidate.length;
      if (nextLength > _maxReferencesBytes) break;
      newest.add(candidate);
      length = nextLength;
    }
    final references = <String>[root, ...newest.reversed, parent].join(' ');
    return StudioMailThread._(parent, references);
  }

  /// One validated parent ID, or null when threading is unavailable.
  final String? inReplyTo;

  /// Validated IDs separated by single spaces, at most 900 ASCII bytes.
  /// The current parent is last; duplicate IDs are compared case-sensitively.
  final String? references;
}

const _maxMessageIdCodeUnits = 254;
const _maxReferencesBytes = 900;
const _maxSourceReferences = 1024;

final _dotAtomCharacters = RegExp(r"^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+$");

bool _canonicalMessageId(String value) {
  if (value.length < 5 ||
      value.length > _maxMessageIdCodeUnits ||
      !value.startsWith('<') ||
      !value.endsWith('>') ||
      value.codeUnits.any((unit) => unit < 0x21 || unit > 0x7e)) {
    return false;
  }
  final separator = value.indexOf('@');
  if (separator < 2 ||
      separator != value.lastIndexOf('@') ||
      separator >= value.length - 2) {
    return false;
  }
  return _dotAtom(value.substring(1, separator)) &&
      _dotAtom(value.substring(separator + 1, value.length - 1));
}

bool _dotAtom(String value) =>
    !value.startsWith('.') &&
    !value.endsWith('.') &&
    !value.contains('..') &&
    _dotAtomCharacters.hasMatch(value);
