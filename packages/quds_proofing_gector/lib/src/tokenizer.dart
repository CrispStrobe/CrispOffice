import 'dart:convert';

import 'backend.dart';

/// Frozen cased German BERT WordPiece profile. No truncation or padding.
/// Other normalizers/templates require separate qualification and are rejected.
final class GectorTokenizer {
  GectorTokenizer._(Map<String, int> vocabulary)
    : vocabulary = Map<String, int>.unmodifiable(vocabulary);

  factory GectorTokenizer.fromJson(String source) {
    final root = _map(jsonDecode(source));
    final model = _map(root['model']);
    final normalizer = _map(root['normalizer']);
    final pre = _map(root['pre_tokenizer']);
    final post = _map(root['post_processor']);
    if (model['type'] != 'WordPiece' ||
        model['unk_token'] != '[UNK]' ||
        model['continuing_subword_prefix'] != '##' ||
        model['max_input_chars_per_word'] != 100 ||
        normalizer['type'] != 'BertNormalizer' ||
        normalizer['clean_text'] != true ||
        normalizer['handle_chinese_chars'] != true ||
        normalizer['lowercase'] != false ||
        (normalizer['strip_accents'] != null &&
            normalizer['strip_accents'] != false) ||
        pre['type'] != 'BertPreTokenizer' ||
        post['type'] != 'TemplateProcessing' ||
        root['truncation'] != null ||
        root['padding'] != null) {
      throw const FormatException('Unsupported GECToR tokenizer profile.');
    }
    final template = post['single'];
    if (template is! List<Object?> ||
        template.length != 3 ||
        _map(_map(template[0])['SpecialToken'])['id'] != '[CLS]' ||
        _map(_map(template[1])['Sequence'])['id'] != 'A' ||
        _map(_map(template[2])['SpecialToken'])['id'] != '[SEP]') {
      throw const FormatException('Unsupported GECToR token template.');
    }
    final raw = _map(model['vocab']);
    final vocabulary = <String, int>{};
    final ids = <int>{};
    for (final entry in raw.entries) {
      final id = entry.value;
      if (id is! int || id < 0 || id >= 31102 || !ids.add(id)) {
        throw const FormatException('Invalid GECToR WordPiece vocabulary.');
      }
      vocabulary[entry.key] = id;
    }
    if (vocabulary['[PAD]'] != 0 ||
        vocabulary['[UNK]'] != 101 ||
        vocabulary['[CLS]'] != 102 ||
        vocabulary['[SEP]'] != 103 ||
        vocabulary['[MASK]'] != 104) {
      throw const FormatException('Unexpected GECToR special token IDs.');
    }
    return GectorTokenizer._(vocabulary);
  }

  final Map<String, int> vocabulary;
  static final _unicodePunctuation = RegExp(r'^\p{P}$', unicode: true);
  // The pinned Rust BERT normalizer removes every Unicode Other category,
  // including private-use and unassigned scalars, except tab/newline/CR.
  static final _control = RegExp(r'^\p{C}$', unicode: true);
  static final _space = RegExp(r'^\s$', unicode: true);
  static const _specials = <String>{
    '[PAD]',
    '[UNK]',
    '[CLS]',
    '[SEP]',
    '[MASK]',
  };

  GectorPreparedInput encode(List<String> words, {int maximumTokens = 512}) {
    if (maximumTokens < 2 || maximumTokens > 512) {
      throw RangeError.range(maximumTokens, 2, 512, 'maximumTokens');
    }
    final ids = <int>[102];
    final first = <int>[0];
    for (final word in words) {
      final tokens = _preTokens(word);
      if (tokens.isEmpty) {
        throw const FormatException(
          'A source word vanished during BERT normalization.',
        );
      }
      first.add(ids.length);
      for (final token in tokens) {
        ids.addAll(_wordPieces(token));
        if (ids.length + 1 > maximumTokens) {
          throw GectorCapacityException(
            'GECToR input exceeds $maximumTokens wordpieces; no text was truncated.',
          );
        }
      }
    }
    ids.add(103);
    return GectorPreparedInput(inputIds: ids, firstSubwordIndices: first);
  }

  List<String> _preTokens(String source) {
    final result = <String>[];
    var cursor = 0;
    for (final match in _specialPattern.allMatches(source)) {
      if (match.start > cursor) {
        result.addAll(
          _ordinaryPreTokens(source.substring(cursor, match.start)),
        );
      }
      result.add(match.group(0)!);
      cursor = match.end;
    }
    if (cursor < source.length) {
      result.addAll(_ordinaryPreTokens(source.substring(cursor)));
    }
    return result;
  }

  static final _specialPattern = RegExp(r'\[(?:PAD|UNK|CLS|SEP|MASK)\]');

  List<String> _ordinaryPreTokens(String source) {
    final normalized = StringBuffer();
    for (final rune in source.runes) {
      final char = String.fromCharCode(rune);
      if (rune == 0 ||
          rune == 0xfffd ||
          (_control.hasMatch(char) && rune != 9 && rune != 10 && rune != 13)) {
        continue;
      }
      if (_space.hasMatch(char)) {
        normalized.write(' ');
      } else if (_isChinese(rune)) {
        normalized.write(' $char ');
      } else {
        normalized.write(char);
      }
    }
    final result = <String>[];
    final current = StringBuffer();
    void flush() {
      if (current.isNotEmpty) {
        result.add(current.toString());
        current.clear();
      }
    }

    for (final rune in normalized.toString().runes) {
      final char = String.fromCharCode(rune);
      final asciiPunctuation =
          (rune >= 33 && rune <= 47) ||
          (rune >= 58 && rune <= 64) ||
          (rune >= 91 && rune <= 96) ||
          (rune >= 123 && rune <= 126);
      if (char == ' ') {
        flush();
      } else if (asciiPunctuation || _unicodePunctuation.hasMatch(char)) {
        flush();
        result.add(char);
      } else {
        current.write(char);
      }
    }
    flush();
    return result;
  }

  List<int> _wordPieces(String token) {
    if (_specials.contains(token)) return <int>[vocabulary[token]!];
    final runes = token.runes.toList(growable: false);
    if (runes.length > 100) return const <int>[101];
    final pieces = <int>[];
    var start = 0;
    while (start < runes.length) {
      int? found;
      var end = runes.length;
      while (end > start) {
        final value =
            '${start == 0 ? '' : '##'}${String.fromCharCodes(runes.sublist(start, end))}';
        found = vocabulary[value];
        if (found != null) break;
        end--;
      }
      if (found == null) return const <int>[101];
      pieces.add(found);
      start = end;
    }
    return pieces;
  }

  static bool _isChinese(int cp) =>
      (cp >= 0x4e00 && cp <= 0x9fff) ||
      (cp >= 0x3400 && cp <= 0x4dbf) ||
      (cp >= 0xf900 && cp <= 0xfaff) ||
      (cp >= 0x20000 && cp <= 0x2a6df) ||
      (cp >= 0x2a700 && cp <= 0x2b73f) ||
      (cp >= 0x2b740 && cp <= 0x2b81f) ||
      (cp >= 0x2b820 && cp <= 0x2ceaf) ||
      (cp >= 0x2f800 && cp <= 0x2fa1f);
}

Map<String, Object?> _map(Object? value) {
  if (value is! Map<String, Object?>) {
    throw const FormatException('Expected a tokenizer object.');
  }
  return value;
}
