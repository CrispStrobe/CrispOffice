import 'header_search.dart';

/// One exact local folder in a host's verified account directory.
///
/// [displayName] is an optional retained label for unavailable-folder feedback;
/// it is never used to resolve identity. Folder whitespace is significant.
final class MailSavedHeaderSearchFolder {
  const MailSavedHeaderSearchFolder({
    required this.accountId,
    required this.mailboxId,
    this.displayName,
  });

  static const maxDisplayNameCodeUnits = 4096;

  final String accountId;
  final String mailboxId;
  final String? displayName;

  static bool isValidMailboxId(String value) =>
      value.isNotEmpty &&
      value.length <= MailSavedHeaderSearch.maxIdCodeUnits &&
      !_controls.hasMatch(value) &&
      _hasWellFormedUtf16(value);

  static bool isValidDisplayName(String? value) =>
      value == null ||
      (value.length <= maxDisplayNameCodeUnits &&
          !_controls.hasMatch(value) &&
          _hasWellFormedUtf16(value));

  bool get isValid =>
      MailSavedHeaderSearch.isValidId(accountId) &&
      isValidMailboxId(mailboxId) &&
      isValidDisplayName(displayName);

  @override
  bool operator ==(Object other) =>
      other is MailSavedHeaderSearchFolder &&
      accountId == other.accountId &&
      mailboxId == other.mailboxId;

  @override
  int get hashCode => Object.hash(accountId, mailboxId);

  @override
  String toString() => 'MailSavedHeaderSearchFolder(redacted)';
}

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
    List<MailSavedHeaderSearchFolder>? folders,
    this.revision = 0,
  }) : accountIds = List<String>.unmodifiable(accountIds),
       folders = folders == null
           ? null
           : List<MailSavedHeaderSearchFolder>.unmodifiable(folders);

  static const maxNameCodeUnits = 128;
  static const maxIdCodeUnits = 1024;
  static const maxAccountIds = 100;
  static const maxFolders = 1000;
  static const maxRevision = 9007199254740991;

  final String id;
  final String name;
  final String query;
  final List<String> accountIds;

  /// Null retains the legacy all-folders scope within [accountIds]. An explicit
  /// set is nonempty and must represent every account exactly by its stable ID.
  /// Missing folders remain in the definition and must never widen the search.
  final List<MailSavedHeaderSearchFolder>? folders;

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
      !_controls.hasMatch(value) &&
      _hasWellFormedUtf16(value);

  bool get isValid {
    if (!isValidId(id) ||
        name.isEmpty ||
        name.length > maxNameCodeUnits ||
        name != name.trim() ||
        _controls.hasMatch(name) ||
        !_hasWellFormedUtf16(name) ||
        query.length > MailHeaderSearchQuery.maxCodeUnits ||
        !_hasWellFormedUtf16(query) ||
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
    final selected = folders;
    if (selected != null) {
      if (selected.isEmpty || selected.length > maxFolders) return false;
      final identities = <MailSavedHeaderSearchFolder>{};
      final represented = <String>{};
      for (final folder in selected) {
        if (!folder.isValid ||
            !seen.contains(folder.accountId) ||
            !identities.add(folder)) {
          return false;
        }
        represented.add(folder.accountId);
      }
      if (represented.length != seen.length) return false;
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
    List<MailSavedHeaderSearchFolder>? folders,
    bool allFolders = false,
    int? revision,
  }) {
    if (allFolders && folders != null) {
      throw ArgumentError('Choose either explicit folders or all folders.');
    }
    return MailSavedHeaderSearch(
      id: id,
      name: name ?? this.name,
      query: query ?? this.query,
      accountIds: accountIds ?? this.accountIds,
      folders: allFolders ? null : folders ?? this.folders,
      revision: revision ?? this.revision,
    );
  }

  @override
  String toString() => 'MailSavedHeaderSearch(redacted)';
}

final _controls = RegExp(r'[\x00-\x1f\x7f]');

// SQLite text uses UTF-8. Reject malformed UTF-16 before an encoder can replace
// an unpaired surrogate and silently change an ID, account scope or query.
// Valid supplementary characters retain their exact original pair of units.
bool _hasWellFormedUtf16(String value) {
  for (var index = 0; index < value.length; index++) {
    final unit = value.codeUnitAt(index);
    if (unit >= 0xd800 && unit <= 0xdbff) {
      if (++index == value.length) return false;
      final low = value.codeUnitAt(index);
      if (low < 0xdc00 || low > 0xdfff) return false;
    } else if (unit >= 0xdc00 && unit <= 0xdfff) {
      return false;
    }
  }
  return true;
}
