import '../search/header_search.dart';
import 'tag.dart';

/// One ordered local mail rule.
///
/// Rules are local automation over retained headers. A rule never contacts a
/// provider and never changes mailbox membership, read/flag state or provider
/// keywords. Its query uses the same bounded grammar as header search, and its
/// actions only add or remove local tags.
///
/// [position] is zero-based and unique within an account. Lower positions run
/// first. When two matching rules touch the same tag, the later rule wins for
/// that tag, including an explicit removal. Validation rejects an empty rule,
/// overlapping add/remove actions and excessive actions or tags.
final class MailRule {
  MailRule._({
    required this.id,
    required this.name,
    required this.query,
    required this.enabled,
    required this.position,
    required this.addTags,
    required this.removeTags,
  });

  factory MailRule.parse({
    required String id,
    required String name,
    required String query,
    bool enabled = true,
    int position = 0,
    Iterable<String> addTags = const [],
    Iterable<String> removeTags = const [],
  }) {
    final trimmedId = id.trim();
    if (!idPattern.hasMatch(trimmedId)) {
      throw const FormatException('Invalid mail rule ID.');
    }
    final trimmedName = name.trim();
    if (trimmedName.isEmpty ||
        trimmedName.length > maxNameLength ||
        trimmedName.runes.length > maxNameLength ||
        _control.hasMatch(trimmedName)) {
      throw const FormatException('Invalid mail rule name.');
    }
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty || trimmedQuery.length > maxQueryLength) {
      throw const FormatException('Invalid mail rule query.');
    }
    try {
      MailHeaderSearchQuery.parse(trimmedQuery);
    } on MailHeaderSearchException {
      throw const FormatException('Invalid mail rule query.');
    }
    if (position < 0 || position >= maxRules) {
      throw const FormatException('Invalid mail rule position.');
    }
    final List<MailTag> added;
    final List<MailTag> removed;
    try {
      added = MailTag.parseAll(addTags);
      removed = MailTag.parseAll(removeTags);
    } on FormatException {
      throw const FormatException('Invalid mail rule tag.');
    }
    if (added.length > maxActions || removed.length > maxActions) {
      throw const FormatException('Too many mail rule actions.');
    }
    if (added.isEmpty && removed.isEmpty) {
      throw const FormatException('A mail rule needs an action.');
    }
    final addedKeys = {for (final tag in added) tag.key};
    if (removed.any((tag) => addedKeys.contains(tag.key))) {
      throw const FormatException('A mail rule cannot add and remove one tag.');
    }
    return MailRule._(
      id: trimmedId,
      name: trimmedName,
      query: trimmedQuery,
      enabled: enabled,
      position: position,
      addTags: List.unmodifiable(added),
      removeTags: List.unmodifiable(removed),
    );
  }

  static const int maxRules = 100;
  static const int maxNameLength = 100;
  static const int maxQueryLength = MailHeaderSearchQuery.maxCodeUnits;
  static const int maxActions = 8;

  static final RegExp idPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$');
  static final RegExp _control = RegExp(
    r'[\x00-\x1f\x7f\u202a-\u202e\u2066-\u2069]',
  );

  final String id;
  final String name;
  final String query;
  final bool enabled;
  final int position;
  final List<MailTag> addTags;
  final List<MailTag> removeTags;

  MailHeaderSearchQuery get compiledQuery => MailHeaderSearchQuery.parse(query);

  bool matches(MailHeaderSearchDocument document) =>
      compiledQuery.matches(document);

  /// Applies this rule's actions to [currentTags]. Existing display spellings
  /// are retained where possible. The result is deterministic and sorted by
  /// tag key, matching [MailTag.parseAll].
  List<MailTag> applyTags(Iterable<String> currentTags) {
    final removedKeys = {for (final tag in removeTags) tag.key};
    final values = <String>[
      for (final value in currentTags)
        if (!removedKeys.contains(MailTag.parse(value).key)) value,
      for (final tag in addTags) tag.name,
    ];
    return MailTag.parseAll(values);
  }

  MailRule copyWith({
    String? name,
    String? query,
    bool? enabled,
    int? position,
    Iterable<String>? addTags,
    Iterable<String>? removeTags,
  }) => MailRule.parse(
    id: id,
    name: name ?? this.name,
    query: query ?? this.query,
    enabled: enabled ?? this.enabled,
    position: position ?? this.position,
    addTags: addTags ?? this.addTags.map((tag) => tag.name),
    removeTags: removeTags ?? this.removeTags.map((tag) => tag.name),
  );

  /// Generates a stable-shape ID for a newly created local rule. The caller
  /// still owns persistence and collision checks.
  static String newId([DateTime? now]) {
    final stamp = (now ?? DateTime.now()).microsecondsSinceEpoch;
    return 'rule-${stamp.toRadixString(36)}';
  }

  @override
  bool operator ==(Object other) =>
      other is MailRule &&
      other.id == id &&
      other.name == name &&
      other.query == query &&
      other.enabled == enabled &&
      other.position == position &&
      _sameTags(other.addTags, addTags) &&
      _sameTags(other.removeTags, removeTags);

  @override
  int get hashCode => Object.hash(
    id,
    name,
    query,
    enabled,
    position,
    Object.hashAll(addTags),
    Object.hashAll(removeTags),
  );

  static bool _sameTags(List<MailTag> a, List<MailTag> b) {
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index++) {
      if (a[index] != b[index]) return false;
    }
    return true;
  }
}

/// An account's complete ordered rule set.
final class MailRuleSet {
  MailRuleSet._(this.rules);

  factory MailRuleSet.parse(Iterable<MailRule> rules) {
    final list = rules.toList();
    if (list.length > MailRule.maxRules) {
      throw const FormatException('Too many mail rules.');
    }
    final ids = <String>{};
    final positions = <int>{};
    for (final rule in list) {
      if (!ids.add(rule.id) || !positions.add(rule.position)) {
        throw const FormatException(
          'Duplicate mail rule identity or position.',
        );
      }
    }
    list.sort((a, b) => a.position.compareTo(b.position));
    return MailRuleSet._(List.unmodifiable(list));
  }

  final List<MailRule> rules;

  bool get isEmpty => rules.isEmpty;

  List<MailRule> matching(MailHeaderSearchDocument document) => [
    for (final rule in rules)
      if (rule.enabled && rule.matches(document)) rule,
  ];

  /// Applies matching rules in order. [matchedRuleIds] is the set of rules that
  /// matched one retained message; rules missing from the set are skipped.
  List<MailTag> applyTags({
    required Set<String> matchedRuleIds,
    required Iterable<String> currentTags,
  }) {
    var tags = MailTag.parseAll(currentTags);
    for (final rule in rules) {
      if (rule.enabled && matchedRuleIds.contains(rule.id)) {
        tags = rule.applyTags(tags.map((tag) => tag.name));
      }
    }
    return tags;
  }

  /// A bounded, display-only summary of which rules match one candidate.
  List<MailRule> preview(MailHeaderSearchDocument document) =>
      matching(document);
}
