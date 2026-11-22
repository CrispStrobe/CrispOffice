/// One user-visible local mail tag or category.
///
/// Tags are local metadata, not provider keywords. Comparison is
/// case-insensitive; the spelling of the first inserted tag is retained.
final class MailTag {
  MailTag._(this.name, this.key);

  factory MailTag.parse(String input) {
    final name = input.trim();
    if (name.isEmpty ||
        name.length > maxNameLength ||
        name.runes.length > maxNameLength ||
        RegExp(r'[\x00-\x1f\x7f\u202a-\u202e\u2066-\u2069]').hasMatch(name) ||
        !RegExp(
          r'^[\p{L}\p{N}][\p{L}\p{N} _.-]*$',
          unicode: true,
        ).hasMatch(name)) {
      throw const FormatException('Invalid mail tag.');
    }
    return MailTag._(name, name.toLowerCase());
  }

  static const int maxNameLength = 64;
  static const int maxTagsPerMessage = 32;

  final String name;
  final String key;

  /// Parse and deduplicate a set while preserving the first display spelling.
  static List<MailTag> parseAll(Iterable<String> values) {
    final result = <MailTag>[];
    final seen = <String>{};
    for (final value in values) {
      final tag = MailTag.parse(value);
      if (seen.add(tag.key)) result.add(tag);
    }
    if (result.length > maxTagsPerMessage) {
      throw const FormatException('Too many mail tags.');
    }
    result.sort((a, b) => a.key.compareTo(b.key));
    return List.unmodifiable(result);
  }

  @override
  bool operator ==(Object other) => other is MailTag && other.key == key;

  @override
  int get hashCode => key.hashCode;

  @override
  String toString() => name;
}
