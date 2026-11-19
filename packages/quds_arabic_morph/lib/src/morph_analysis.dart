import 'dart:collection';

import 'package:quds_office_engine/quds_office_engine.dart';

/// Converts the analyzer's JSON (one array of camel_tools feature objects per
/// word) into compact, read-only [ArabicAnalysis] maps.
///
/// An analysis has about 45 features and a document thousands of analyses, so
/// each map shares its key list with every analysis of the same feature
/// layout and stores only a value list; repeated values are interned. String
/// values are kept as is, numbers (the `*_logprob` placeholders) become their
/// Dart decimal text (`-99.0`), and `null` features are omitted.
final class ArabicAnalysisDecoder {
  final Map<String, _Schema> _schemas = {};
  final Map<String, String> _values = {};

  /// Interning tables are dropped beyond this many entries (no effect on
  /// results, only on sharing).
  static const _maxInterned = 200000;

  /// [json] is the decoded array for one word; anything else is a protocol
  /// error.
  List<ArabicAnalysis> decode(Object? json) {
    if (json is! List<Object?>) {
      throw const FormatException('Analyses must be a JSON array.');
    }
    if (_values.length > _maxInterned) _values.clear();
    if (_schemas.length > 4096) _schemas.clear();
    return List<ArabicAnalysis>.unmodifiable([
      for (final item in json) _analysis(item),
    ]);
  }

  ArabicAnalysis _analysis(Object? item) {
    if (item is! Map<String, Object?>) {
      throw const FormatException('An analysis must be a JSON object.');
    }
    final keys = <String>[];
    final values = <String>[];
    for (final entry in item.entries) {
      final value = entry.value;
      final String text;
      if (value == null) {
        continue;
      } else if (value is String) {
        text = value;
      } else if (value is num) {
        text = value.toDouble().toString();
      } else {
        throw FormatException('Unexpected value for ${entry.key}.');
      }
      keys.add(entry.key);
      values.add(_values.putIfAbsent(text, () => text));
    }
    final signature = keys.join('\u0000');
    final schema = _schemas.putIfAbsent(signature, () => _Schema(keys));
    return CompactArabicAnalysis._(schema, List<String>.unmodifiable(values));
  }
}

final class _Schema {
  _Schema(List<String> keys)
    : keys = List<String>.unmodifiable(keys),
      index = {for (var i = 0; i < keys.length; i++) keys[i]: i};
  final List<String> keys;
  final Map<String, int> index;
}

/// A read-only analysis sharing its key layout with similar analyses.
final class CompactArabicAnalysis extends UnmodifiableMapBase<String, String> {
  CompactArabicAnalysis._(this._schema, this._values);
  final _Schema _schema;
  final List<String> _values;

  @override
  String? operator [](Object? key) {
    final i = _schema.index[key];
    return i == null ? null : _values[i];
  }

  @override
  Iterable<String> get keys => _schema.keys;

  @override
  int get length => _values.length;

  @override
  bool containsKey(Object? key) => _schema.index.containsKey(key);
}
