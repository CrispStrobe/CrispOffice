import 'header_search.dart';

/// A reusable query over a fixed set of a host's verified local account IDs.
///
/// The definition contains no messages, credentials or continuation cursors.
/// A host resolves these exact IDs through its account directory before each
/// new search. Missing accounts must remain unavailable, never widen the scope.
/// An empty query is allowed and means all retained headers in that fixed scope.
final class MailSavedHeaderSearch {
  MailSavedHeaderSearch({
    required this.id,
    required this.name,
    required this.query,
    required List<String> accountIds,
    this.revision = 0,
  }) : accountIds = List<String>.unmodifiable(accountIds);

  static const maxNameCodeUnits = 128;
  static const maxIdCodeUnits = 1024;
  static const maxAccountIds = 100;
  static const maxRevision = 9007199254740991;

  final String id;
  final String name;
  final String query;
  final List<String> accountIds;

  /// Zero denotes an unsaved definition. Persisted revisions are assigned by
  /// the repository and must be supplied unchanged for update or deletion.
  final int revision;

  /// Locale-independent, case-insensitive uniqueness. Names retain their
  /// original spelling; no accent folding or Unicode normalization is implied.
  String get nameKey => name.toLowerCase();

  static bool isValidId(String value) =>
      value.isNotEmpty &&
      value.length <= maxIdCodeUnits &&
      value == value.trim() &&
      !_controls.hasMatch(value);

  bool get isValid {
    if (!isValidId(id) ||
        name.isEmpty ||
        name.length > maxNameCodeUnits ||
        name != name.trim() ||
        _controls.hasMatch(name) ||
        accountIds.isEmpty ||
        accountIds.length > maxAccountIds ||
        revision < 0 ||
        revision > maxRevision) {
      return false;
    }
    final seen = <String>{};
    for (final account in accountIds) {
      if (!isValidId(account) || !seen.add(account)) return false;
    }
    try {
      MailHeaderSearchQuery.parse(query);
      return true;
    } on MailHeaderSearchException {
      return false;
    }
  }

  MailSavedHeaderSearch copyWith({
    String? name,
    String? query,
    List<String>? accountIds,
    int? revision,
  }) => MailSavedHeaderSearch(
    id: id,
    name: name ?? this.name,
    query: query ?? this.query,
    accountIds: accountIds ?? this.accountIds,
    revision: revision ?? this.revision,
  );

  @override
  String toString() => 'MailSavedHeaderSearch(redacted)';
}

final _controls = RegExp(r'[\x00-\x1f\x7f]');
