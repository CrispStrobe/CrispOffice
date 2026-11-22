/// Conservative, account-scoped conversation grouping of observed mail headers.
///
/// This never fetches provider data, guesses from a subject, or treats a
/// Message-ID as the identity of a mailbox row. The input order is preserved,
/// so hosts can apply a local sort/search *before* grouping.
library;

import '../model/message.dart';

/// A single loaded header's threading projection.
///
/// [id] identifies the row, not an RFC Message-ID. [accountId] prevents
/// unrelated accounts with coincident RFC IDs from being joined. Oversized
/// reference lists are ignored instead of being partially trusted.
final class MailConversationEntry {
  MailConversationEntry({
    required this.id,
    required this.accountId,
    this.messageId,
    this.inReplyTo,
    this.conversationId,
    List<String> references = const [],
  }) : references = List<String>.unmodifiable(
         references.length <= maxReferences ? references : const <String>[],
       ) {
    if (id.isEmpty || accountId.isEmpty) {
      throw ArgumentError('Conversation rows need an account and a row ID.');
    }
  }

  static const int maxReferences = 64;

  final String id;
  final String accountId;
  final String? messageId;
  final String? inReplyTo;
  final List<String> references;

  /// Persistent account-scoped conversation key, when the host has one.
  ///
  /// Rows with the same explicit key join even when their loaded reference
  /// headers are incomplete. A key is never treated as a Message-ID or row ID.
  final String? conversationId;
}

/// Deterministic persisted conversation key for conservative threading.
///
/// The first valid reference is treated as the thread root. When no complete
/// reference list is available, a valid In-Reply-To, then the message's own
/// Message-ID, then an account-local fallback identifies the conversation.
/// Malformed partial reference lists are ignored as a whole; no subject or
/// participant guessing is performed.
abstract final class MailConversationKey {
  static String fromEnvelope(
    MailEnvelope envelope, {
    required String fallbackId,
  }) => fromParts(
    messageId: envelope.messageId,
    inReplyTo: envelope.inReplyTo,
    references: envelope.references,
    fallbackId: fallbackId,
  );

  static String fromParts({
    String? messageId,
    String? inReplyTo,
    List<String> references = const [],
    required String fallbackId,
  }) {
    if (fallbackId.isEmpty || fallbackId.length > 1024) {
      throw ArgumentError('Conversation fallback needs a bounded row ID.');
    }
    if (references.isNotEmpty &&
        references.length <= MailConversationEntry.maxReferences) {
      final canonical = <String>[];
      var complete = true;
      for (final reference in references) {
        final id = _canonicalMessageId(reference);
        if (id == null) {
          complete = false;
          break;
        }
        canonical.add(id);
      }
      if (complete) return canonical.first;
    }
    return _canonicalMessageId(inReplyTo) ??
        _canonicalMessageId(messageId) ??
        'local:$fallbackId';
  }
}

/// A sequence of loaded rows connected by valid, explicit message IDs.
///
/// A group containing one row is not evidence of a conversation. No missing
/// messages are fabricated. The order is inherited from the input snapshot.
final class MailConversationGroup {
  MailConversationGroup._(List<MailConversationEntry> entries)
    : entries = List<MailConversationEntry>.unmodifiable(entries);

  final List<MailConversationEntry> entries;
  int get length => entries.length;
  bool get hasReplies => length > 1;
}

/// Groups an already-bounded set of headers without network access.
///
/// In-Reply-To and References may identify an ancestor outside the loaded
/// window. Two loaded replies to the same absent ancestor therefore still
/// belong together. Only strict ASCII dot-atom Message-IDs with brackets are
/// admitted; malformed or partial References fields are never salvaged.
/// The function performs at most 66 alias lookups per row and uses union-find,
/// rather than walking an untrusted ancestor graph recursively.
///
/// Distinct [MailConversationEntry.id] values are required *within* an account.
/// Repeated RFC Message-IDs, duplicate folder copies and reference cycles are
/// safe. IDs in different accounts can never merge.
List<MailConversationGroup> groupMailConversations(
  List<MailConversationEntry> entries,
) {
  if (entries.isEmpty) return const <MailConversationGroup>[];

  final seenRows = <(String, String)>{};
  for (final entry in entries) {
    if (!seenRows.add((entry.accountId, entry.id))) {
      throw ArgumentError('Duplicate conversation row in one account.');
    }
  }

  final parent = List<int>.generate(entries.length, (index) => index);
  final size = List<int>.filled(entries.length, 1);

  int root(int index) {
    var current = index;
    while (parent[current] != current) {
      parent[current] = parent[parent[current]];
      current = parent[current];
    }
    return current;
  }

  void unite(int a, int b) {
    var left = root(a);
    var right = root(b);
    if (left == right) return;
    if (size[left] < size[right]) {
      final previous = left;
      left = right;
      right = previous;
    }
    parent[right] = left;
    size[left] += size[right];
  }

  // A referenced ancestor need not be present in the loaded window.
  final owners = <(String, String), int>{};
  void linkKey(int index, String id) {
    final key = (entries[index].accountId, id);
    final previous = owners[key];
    if (previous == null) {
      owners[key] = index;
    } else {
      unite(index, previous);
    }
  }

  void link(int index, String? candidate) {
    final id = _canonicalMessageId(candidate);
    if (id == null) return;
    linkKey(index, id);
  }

  for (var index = 0; index < entries.length; index++) {
    final entry = entries[index];
    final conversation = entry.conversationId;
    if (conversation != null && conversation.isNotEmpty) {
      linkKey(index, 'conversation:$conversation');
    }
    link(index, entry.messageId);
    final refs = entry.references;
    if (refs.isNotEmpty &&
        refs.every((candidate) => _canonicalMessageId(candidate) != null)) {
      for (final ref in refs) {
        link(index, ref);
      }
    }
    link(index, entry.inReplyTo);
  }

  final byRoot = <int, List<MailConversationEntry>>{};
  for (var index = 0; index < entries.length; index++) {
    byRoot.putIfAbsent(root(index), () => []).add(entries[index]);
  }
  return List<MailConversationGroup>.unmodifiable([
    for (final group in byRoot.values) MailConversationGroup._(group),
  ]);
}

// Preserve the local-part spelling, which may be case-sensitive. Refuse
// comments, quoted atoms, whitespace, domain literals and obsolete syntax;
// a false split is safer than an incorrect merge of unrelated mail.
final _atom = RegExp(r"^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+$");

String? _canonicalMessageId(String? value) {
  if (value == null ||
      value.length < 5 ||
      value.length > 254 ||
      !value.startsWith('<') ||
      !value.endsWith('>')) {
    return null;
  }
  for (final unit in value.codeUnits) {
    if (unit < 0x21 || unit > 0x7e) return null;
  }
  final at = value.indexOf('@');
  if (at < 2 || at != value.lastIndexOf('@') || at >= value.length - 2) {
    return null;
  }
  final local = value.substring(1, at);
  final domain = value.substring(at + 1, value.length - 1);
  if (!_validDotAtom(local) || !_validDotAtom(domain)) return null;
  return value;
}

bool _validDotAtom(String value) =>
    _atom.hasMatch(value) &&
    !value.startsWith('.') &&
    !value.endsWith('.') &&
    !value.contains('..');
