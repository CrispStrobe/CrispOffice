// Adapted from Proofbird quickstart.py, Apache-2.0. See NOTICE and third_party/.
import 'package:characters/characters.dart';

import 'bundle.dart';

final class GectorWordSpan {
  const GectorWordSpan(this.word, this.start, this.end);
  final String word;
  final int start;
  final int end;
}

final class GectorEdit {
  const GectorEdit({
    required this.start,
    required this.end,
    required this.original,
    required this.replacement,
  });
  final int start;
  final int end;
  final String original;
  final String replacement;
}

/// Word and edit offsets are always UTF-16 positions in the original string.
/// Only the model view normalizes curly apostrophes and removes one terminator.
final class GectorSourceText {
  GectorSourceText(this.original, this.configuration) {
    if (!isWellFormedUtf16(original)) {
      throw const FormatException(
        'GECToR input contains an unpaired UTF-16 surrogate.',
      );
    }
    final trimmed = original.replaceFirst(_trailingWhitespace, '');
    final remove =
        trimmed.isNotEmpty &&
        configuration.stripTerminators.contains(trimmed[trimmed.length - 1]);
    final end = remove ? trimmed.length - 1 : original.length;
    core = original.substring(0, end);
    tail = original.substring(end);
    plain = core.replaceAll('’', "'");
    spans = wordSpans(plain);
  }

  final String original;
  final GectorConfiguration configuration;
  late final String core;
  late final String tail;
  late final String plain;
  late final List<GectorWordSpan> spans;

  // Python's Unicode \w is letters/numbers/underscore, not combining marks.
  static final _word = RegExp(
    r"[\p{L}\p{N}_]+(?:'[\p{L}\p{N}_]+)?|[^\p{L}\p{N}_\s\u0085\u001c-\u001f]",
    unicode: true,
  );
  static final _trailingWhitespace = RegExp(r'[\s\u0085\u001c-\u001f]+$');
  static final _whitespace = RegExp(r'[\s\u0085\u001c-\u001f]+');
  static final _alnum = RegExp(r'^[\p{L}\p{N}]$', unicode: true);
  static const opening = '([{“«"';
  static const closing = '.,;:!?)]}%»”';

  List<String> words(String source) => <String>[
    for (final span in wordSpans(source)) span.word,
  ];

  List<GectorWordSpan> wordSpans(String source, {bool surface = false}) {
    final result = <GectorWordSpan>[];
    for (final match in _word.allMatches(source)) {
      final value = match.group(0)!;
      final apostrophe = value.indexOf("'");
      if (apostrophe > 0 &&
          apostrophe < value.length - 1 &&
          configuration.gluedArticles.contains(
            value.substring(0, apostrophe).toLowerCase(),
          )) {
        final first = value.substring(0, apostrophe + (surface ? 1 : 0));
        result.add(
          GectorWordSpan(first, match.start, match.start + first.length),
        );
        result.add(
          GectorWordSpan(
            value.substring(apostrophe + 1),
            match.start + apostrophe + 1,
            match.end,
          ),
        );
      } else {
        result.add(GectorWordSpan(value, match.start, match.end));
      }
    }
    return List<GectorWordSpan>.unmodifiable(result);
  }

  List<GectorEdit> suggestions(List<String> correctedWords) {
    final surface = wordSpans(plain, surface: true);
    final originals = <String>[for (final span in surface) span.word];
    final result = <GectorEdit>[];
    for (final op in _opcodes(originals, correctedWords)) {
      if (op.equal) continue;
      var replacement = joinWords(correctedWords.sublist(op.j1, op.j2));
      int start;
      int end;
      if (op.i1 == op.i2) {
        if (op.i1 < originals.length) {
          start = end = surface[op.i1].start;
          if (replacement.isNotEmpty && opening.contains(_last(replacement))) {
            // Opening punctuation hugs the following original word.
          } else if (op.i1 == 0 || isAlphanumeric(_first(originals[op.i1]))) {
            replacement = '$replacement ';
          } else {
            replacement = ' $replacement';
          }
        } else {
          start = end = surface.isEmpty ? 0 : surface.last.end;
          replacement =
              '${isAlphanumeric(_first(replacement)) ? ' ' : ''}$replacement';
        }
      } else {
        start = surface[op.i1].start;
        end = surface[op.i2 - 1].end;
        if (replacement.isNotEmpty &&
            end < plain.length &&
            isAlphanumeric(_first(plain.substring(end))) &&
            isAlphanumeric(_last(replacement))) {
          replacement += ' ';
        }
        if (replacement.isEmpty) {
          if (end < plain.length && plain[end] == ' ') {
            end++;
          } else if (start > 0 && plain[start - 1] == ' ') {
            start--;
          }
        }
      }
      final before = original.substring(start, end);
      if (before != replacement) {
        result.add(
          GectorEdit(
            start: start,
            end: end,
            original: before,
            replacement: replacement,
          ),
        );
      }
    }
    return List<GectorEdit>.unmodifiable(result);
  }

  String apply(List<GectorEdit> edits) {
    var result = original;
    var previous = original.length + 1;
    for (final edit in edits.reversed) {
      if (edit.start < 0 ||
          edit.end < edit.start ||
          edit.end >= previous ||
          edit.end > original.length ||
          original.substring(edit.start, edit.end) != edit.original) {
        throw const FormatException('Invalid source edit sequence.');
      }
      result = result.replaceRange(edit.start, edit.end, edit.replacement);
      previous = edit.start + 1;
    }
    return result;
  }

  Set<int> get graphemeBoundaries {
    final values = <int>{0};
    var offset = 0;
    for (final cluster in original.characters) {
      offset += cluster.length;
      values.add(offset);
    }
    return values;
  }

  static List<String> splitWhitespace(String source) => source
      .split(_whitespace)
      .where((s) => s.isNotEmpty)
      .toList(growable: false);

  static String joinWords(Iterable<String> words) {
    var value = splitWhitespace(words.join(' ')).join(' ');
    value = value.replaceAll(RegExp(' (?=[${RegExp.escape(closing)}])'), '');
    return value.replaceAllMapped(
      RegExp('([${RegExp.escape(opening.replaceAll('"', ''))}]) '),
      (match) => match.group(1)!,
    );
  }

  static List<String> rejoin(Iterable<String> tokens) {
    final result = <String>[];
    for (final token in tokens) {
      if (result.isNotEmpty &&
          result.last.length > 1 &&
          result.last.endsWith("'") &&
          isAlphanumeric(_first(token))) {
        result[result.length - 1] += token;
      } else {
        result.add(token);
      }
    }
    return result;
  }

  static bool isAlphanumeric(String scalar) => _alnum.hasMatch(scalar);
  static String _first(String s) =>
      s.isEmpty ? '' : String.fromCharCode(s.runes.first);
  static String _last(String s) =>
      s.isEmpty ? '' : String.fromCharCode(s.runes.last);

  static bool isWellFormedUtf16(String value) {
    for (var i = 0; i < value.length; i++) {
      final unit = value.codeUnitAt(i);
      if (unit >= 0xd800 && unit <= 0xdbff) {
        if (++i >= value.length) return false;
        final next = value.codeUnitAt(i);
        if (next < 0xdc00 || next > 0xdfff) return false;
      } else if (unit >= 0xdc00 && unit <= 0xdfff) {
        return false;
      }
    }
    return true;
  }
}

// Same longest-contiguous-match tie order as Python SequenceMatcher with
// autojunk=False. A generic LCS can group repeated words differently and move
// an edit to a different occurrence, so it is not interchangeable here.
typedef _Match = ({int a, int b, int size});
typedef _Opcode = ({bool equal, int i1, int i2, int j1, int j2});

List<_Opcode> _opcodes(List<String> a, List<String> b) {
  final positions = <String, List<int>>{};
  for (var j = 0; j < b.length; j++) {
    positions.putIfAbsent(b[j], () => <int>[]).add(j);
  }
  _Match longest(int alo, int ahi, int blo, int bhi) {
    var bestA = alo;
    var bestB = blo;
    var bestSize = 0;
    var previous = <int, int>{};
    for (var i = alo; i < ahi; i++) {
      final current = <int, int>{};
      for (final j in positions[a[i]] ?? const <int>[]) {
        if (j < blo) continue;
        if (j >= bhi) break;
        final size = (previous[j - 1] ?? 0) + 1;
        current[j] = size;
        if (size > bestSize) {
          bestA = i - size + 1;
          bestB = j - size + 1;
          bestSize = size;
        }
      }
      previous = current;
    }
    return (a: bestA, b: bestB, size: bestSize);
  }

  final queue = <({int alo, int ahi, int blo, int bhi})>[
    (alo: 0, ahi: a.length, blo: 0, bhi: b.length),
  ];
  final matches = <_Match>[];
  while (queue.isNotEmpty) {
    final region = queue.removeLast();
    final match = longest(region.alo, region.ahi, region.blo, region.bhi);
    if (match.size == 0) continue;
    matches.add(match);
    if (region.alo < match.a && region.blo < match.b) {
      queue.add((alo: region.alo, ahi: match.a, blo: region.blo, bhi: match.b));
    }
    if (match.a + match.size < region.ahi &&
        match.b + match.size < region.bhi) {
      queue.add((
        alo: match.a + match.size,
        ahi: region.ahi,
        blo: match.b + match.size,
        bhi: region.bhi,
      ));
    }
  }
  matches.sort((x, y) => x.a == y.a ? x.b.compareTo(y.b) : x.a.compareTo(y.a));
  final collapsed = <_Match>[];
  for (final match in matches) {
    if (collapsed.isNotEmpty &&
        collapsed.last.a + collapsed.last.size == match.a &&
        collapsed.last.b + collapsed.last.size == match.b) {
      final old = collapsed.removeLast();
      collapsed.add((a: old.a, b: old.b, size: old.size + match.size));
    } else {
      collapsed.add(match);
    }
  }
  collapsed.add((a: a.length, b: b.length, size: 0));
  final result = <_Opcode>[];
  var i = 0;
  var j = 0;
  for (final match in collapsed) {
    if (i < match.a || j < match.b) {
      result.add((equal: false, i1: i, i2: match.a, j1: j, j2: match.b));
    }
    if (match.size > 0) {
      result.add((
        equal: true,
        i1: match.a,
        i2: match.a + match.size,
        j1: match.b,
        j2: match.b + match.size,
      ));
    }
    i = match.a + match.size;
    j = match.b + match.size;
  }
  return result;
}
