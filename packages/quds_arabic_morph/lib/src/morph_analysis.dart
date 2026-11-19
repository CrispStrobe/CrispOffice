import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';

/// Converts the analyzer's JSON (one array of camel_tools feature objects per
/// word) into compact, read-only [ArabicAnalysis] maps.
///
/// An analysis has about 45 features and a document thousands of analyses, so
/// each map shares its key list with every analysis of the same feature
/// layout and stores only a value list; repeated values are interned. String
/// values are kept as is, numbers (the `*_logprob` placeholders) become their
/// double text (`-99.0`, including JavaScript targets), and `null` features
/// are omitted.
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
        final number = value.toDouble();
        final decimal = number.toString();
        // JavaScript shares the int/double representation and omits `.0`.
        // Restore that suffix only for finite plain-integer text, preserving
        // fractional precision, exponent notation, and negative zero.
        text =
            number.isFinite && !decimal.contains('.') && !decimal.contains('e')
            ? '$decimal.0'
            : decimal;
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

/// Decodes the analyzer's compact output (`crispembed_ar_morph_analyze_compact`,
/// CrispEmbed ABI 2): one little-endian buffer per batch with, per word, a
/// status and a record of unique value strings plus analyses as
/// (key id, string index) pairs. No JSON is involved.
///
/// Each word keeps its own record bytes (about 1-2 KB); the [ArabicAnalysis]
/// maps are views over them, and value strings are decoded on first read and
/// shared between words. `null` features are omitted, as before.
final class CompactAnalysisDecoder {
  /// [keys] is the `keys` array of the analyzer's `info` (names by key id).
  CompactAnalysisDecoder(List<String> keys)
    : _keys = List<String>.unmodifiable(keys),
      _index = {for (var i = 0; i < keys.length; i++) keys[i]: i};

  /// `AMC1` little-endian.
  static const magic = 0x31434D41;
  static const _ok = 0;
  static const _inputError = 5;
  static const _maxInterned = 200000;

  final List<String> _keys;
  final Map<String, int> _index;
  final Map<String, String> _values = {};

  /// Analyses of the [words] words of [buffer] in order; null marks a word
  /// the analyzer rejected as input.
  List<List<ArabicAnalysis>?> decode(Uint8List buffer, int words) {
    final data = ByteData.sublistView(buffer);
    if (buffer.length < 8 ||
        data.getUint32(0, Endian.little) != magic ||
        data.getUint32(4, Endian.little) != words) {
      throw const FormatException('Malformed Arabic morphology buffer.');
    }
    if (_values.length > _maxInterned) _values.clear();
    final out = <List<ArabicAnalysis>?>[];
    var at = 8;
    for (var w = 0; w < words; w++) {
      if (at + 8 > buffer.length) {
        throw const FormatException('Truncated Arabic morphology buffer.');
      }
      final status = data.getUint32(at, Endian.little);
      final length = data.getUint32(at + 4, Endian.little);
      at += 8;
      if (at + length > buffer.length) {
        throw const FormatException('Truncated Arabic morphology buffer.');
      }
      if (status == _ok) {
        // Copied, so a cached word does not keep the whole batch alive.
        out.add(_CompactWord(this, buffer.sublist(at, at + length)));
      } else if (status == _inputError) {
        out.add(null);
      } else {
        throw FormatException('Unexpected analysis status $status.');
      }
      at += length;
    }
    if (at != buffer.length) {
      throw const FormatException('Malformed Arabic morphology buffer.');
    }
    return out;
  }

  String _intern(String value) => _values.putIfAbsent(value, () => value);
}

/// One word's analyses over its compact record (read-only list).
final class _CompactWord extends ListBase<ArabicAnalysis> {
  _CompactWord(this._decoder, this._bytes) {
    final data = ByteData.sublistView(_bytes);
    if (_bytes.length < 12) {
      throw const FormatException('Malformed analysis record.');
    }
    final count = data.getUint32(0, Endian.little);
    final strings = data.getUint32(4, Endian.little);
    _wide = _bytes[8] != 0;
    _stringStarts = Uint32List(strings);
    var at = 12;
    for (var i = 0; i < strings; i++) {
      _stringStarts[i] = at;
      at += 5 + data.getUint32(at + 1, Endian.little);
    }
    _analysisStarts = Uint32List(count);
    final feature = _wide ? 6 : 3;
    for (var i = 0; i < count; i++) {
      _analysisStarts[i] = at;
      at += 2 + feature * data.getUint16(at, Endian.little);
    }
    if (at != _bytes.length) {
      throw const FormatException('Malformed analysis record.');
    }
    _strings = List<String?>.filled(strings, null);
  }

  final CompactAnalysisDecoder _decoder;
  final Uint8List _bytes;
  late final bool _wide;
  late final Uint32List _stringStarts;
  late final Uint32List _analysisStarts;
  late final List<String?> _strings;

  String _string(int index) {
    final cached = _strings[index];
    if (cached != null) return cached;
    final start = _stringStarts[index];
    final length = ByteData.sublistView(
      _bytes,
    ).getUint32(start + 1, Endian.little);
    final text = utf8.decode(
      Uint8List.sublistView(_bytes, start + 5, start + 5 + length),
    );
    return _strings[index] = _decoder._intern(text);
  }

  @override
  int get length => _analysisStarts.length;

  @override
  set length(int value) =>
      throw UnsupportedError('Cannot change an analysis list.');

  /// A small view object per access; nothing per analysis is retained.
  @override
  ArabicAnalysis operator [](int index) => _CompactAnalysis(
    this,
    _analysisStarts[RangeError.checkValidIndex(index, this)],
  );

  @override
  void operator []=(int index, ArabicAnalysis value) =>
      throw UnsupportedError('Cannot change an analysis list.');
}

/// A read-only analysis map over a compact record.
final class _CompactAnalysis extends UnmodifiableMapBase<String, String> {
  _CompactAnalysis(this._word, this._start);
  final _CompactWord _word;
  final int _start;

  int get _count =>
      ByteData.sublistView(_word._bytes).getUint16(_start, Endian.little);

  /// (key id, string index or -1 for null) of feature [i].
  (int, int) _feature(ByteData data, int i) {
    if (_word._wide) {
      final at = _start + 2 + 6 * i;
      final ref = data.getUint32(at + 2, Endian.little);
      return (data.getUint16(at, Endian.little), ref == 0xFFFFFFFF ? -1 : ref);
    }
    final at = _start + 2 + 3 * i;
    final ref = data.getUint16(at + 1, Endian.little);
    return (_word._bytes[at], ref == 0xFFFF ? -1 : ref);
  }

  @override
  String? operator [](Object? key) {
    final id = _word._decoder._index[key];
    if (id == null) return null;
    final data = ByteData.sublistView(_word._bytes);
    final count = _count;
    for (var i = 0; i < count; i++) {
      final (k, ref) = _feature(data, i);
      if (k == id) return ref < 0 ? null : _word._string(ref);
    }
    return null;
  }

  @override
  Iterable<String> get keys sync* {
    final data = ByteData.sublistView(_word._bytes);
    final count = _count;
    for (var i = 0; i < count; i++) {
      final (k, ref) = _feature(data, i);
      if (ref >= 0) yield _word._decoder._keys[k];
    }
  }

  @override
  int get length => keys.length;

  @override
  bool containsKey(Object? key) => this[key] != null;
}
